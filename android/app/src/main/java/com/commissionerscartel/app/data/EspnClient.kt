package com.commissionerscartel.app.data

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

/**
 * The league's ESPN data, fetched through the `espn-proxy` edge function.
 *
 * The proxy holds `espn_s2` and `SWID` server-side, so unlike the iOS app this
 * client needs no credentials and there is nothing for a member to paste into
 * Settings. It also means the private league works on a fresh install.
 *
 * One payload covers every screen, so it is fetched once and shared. Concurrent
 * callers join the in-flight request rather than starting their own — five tabs
 * appearing at once would otherwise be five identical round trips.
 */
class EspnClient(
    private val season: Int = Config.currentSeason(),
    private val leagueId: String = Config.espnLeagueId,
) {
    private val http = HttpClient(OkHttp)
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val mutex = Mutex()
    private var inFlight: Deferred<EspnPayload>? = null
    private var cached: Pair<EspnPayload, Long>? = null

    /** Matches the iOS client's two-minute cache. */
    private val ttlMillis = 2 * 60 * 1000L

    // mBoxscore is what carries player names and their points; without it
    // the roster entries arrive stripped of everything but statistics.
    private val views = listOf("mSettings", "mTeam", "mMatchupScore", "mBoxscore")

    suspend fun payload(): EspnPayload {
        cached?.let { (payload, at) ->
            if (System.currentTimeMillis() - at < ttlMillis) return payload
        }

        val request = mutex.withLock {
            inFlight ?: scope.async { fetch() }.also { inFlight = it }
        }
        return try {
            request.await().also {
                mutex.withLock {
                    cached = it to System.currentTimeMillis()
                    inFlight = null
                }
            }
        } catch (error: Throwable) {
            mutex.withLock { inFlight = null }
            throw error
        }
    }

    suspend fun refresh(): EspnPayload {
        mutex.withLock { cached = null; inFlight = null }
        return payload()
    }

    private suspend fun fetch(): EspnPayload {
        val query = views.joinToString("&") { "view=$it" }
        val url = "${Config.supabaseUrl}/functions/v1/espn-proxy" +
            "/apis/v3/games/ffl/seasons/$season/segments/0/leagues/$leagueId?$query"

        val response = http.get(url) {
            header("Authorization", "Bearer ${Session.proxyToken()}")
            header("apikey", Config.supabaseAnonKey)
        }
        // The proxy's own refusal: it lets in league members only (#15). ESPN's
        // refusals pass through it unmarked, and mean stale cookies.
        if (response.status == HttpStatusCode.Forbidden && response.headers["X-Cartel-Members-Only"] != null) {
            throw IllegalStateException(
                "Only league members can see the league. Sign in from Settings with the email you were invited on."
            )
        }
        if (response.status != HttpStatusCode.OK) {
            throw IllegalStateException(
                "ESPN returned ${response.status.value}. ${response.bodyAsText().take(200)}"
            )
        }
        return json.decodeFromString(response.bodyAsText())
    }

    /**
     * The URL to load a team logo from, or null when it cannot be displayed.
     *
     * `proxyBase` is the espn-proxy function, or null when there is no Supabase
     * to reach it — in which case nothing that needs it can be shown.
     */
    fun logoUrl(
        raw: String?,
        proxyBase: String? = if (Config.hasSupabase) "${Config.supabaseUrl}/functions/v1/espn-proxy" else null,
    ): String? {
        val url = raw?.takeIf { it.isNotBlank() } ?: return null
        // Parsed only where a path is needed, so an ordinary URL the parser
        // dislikes is still handed to the loader untouched, as it always was.
        fun parsed() = runCatching { java.net.URI(url) }.getOrNull()

        // ESPN's stock crests are SVG, which Android's image loaders cannot
        // decode. The proxy draws them as PNGs (#16), so a stock crest goes
        // through it like an uploaded logo. Any other SVG, or one with no proxy
        // to draw it, is not worth downloading to fail. Same rule as iOS.
        if (url.substringBefore('?').endsWith(".svg", ignoreCase = true)) {
            val uri = parsed() ?: return null
            val path = uri.path ?: return null
            if (uri.host != "g.espncdn.com" || !path.startsWith("/lm-static/")) return null
            return proxyBase?.let { it + path }
        }
        // Uploaded logos live behind a host that requires the league cookies,
        // so they have to come back through the proxy.
        if (!url.contains("mystique")) return url
        val path = parsed()?.path ?: return null
        return proxyBase?.let { it + path }
    }
}
