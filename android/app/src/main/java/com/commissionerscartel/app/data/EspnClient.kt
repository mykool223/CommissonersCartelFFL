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

    private val views = listOf("mSettings", "mTeam", "mMatchupScore")

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
            header("Authorization", "Bearer ${Config.supabaseAnonKey}")
            header("apikey", Config.supabaseAnonKey)
        }
        if (response.status != HttpStatusCode.OK) {
            throw IllegalStateException(
                "ESPN returned ${response.status.value}. ${response.bodyAsText().take(200)}"
            )
        }
        return json.decodeFromString(response.bodyAsText())
    }

    /** The URL to load a team logo from, or null when it cannot be displayed. */
    fun logoUrl(raw: String?): String? {
        val url = raw?.takeIf { it.isNotBlank() } ?: return null
        // Android's image loaders cannot decode ESPN's stock SVG crests, and
        // there is no point downloading one to fail. Same rule as iOS.
        if (url.substringBefore('?').endsWith(".svg", ignoreCase = true)) return null
        // Uploaded logos live behind a host that requires the league cookies,
        // so they have to come back through the proxy.
        if (!url.contains("mystique")) return url
        val path = runCatching { java.net.URI(url).path }.getOrNull() ?: return null
        return "${Config.supabaseUrl}/functions/v1/espn-proxy$path"
    }
}
