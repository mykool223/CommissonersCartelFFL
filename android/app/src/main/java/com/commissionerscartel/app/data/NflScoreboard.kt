package com.commissionerscartel.app.data

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A real NFL game, from ESPN's public scoreboard. No authentication needed. */
data class NflGame(
    val id: String,
    val name: String,
    val shortName: String,
    val statusText: String,
    val isFinal: Boolean,
    val isLive: Boolean,
    val home: NflCompetitor?,
    val away: NflCompetitor?,
)

data class NflCompetitor(
    val abbreviation: String,
    /** "Texans" rather than "Houston Texans" — it has to fit a phone row. */
    val name: String,
    val record: String?,
    val score: String,
    val isWinner: Boolean,
    val logo: String?,
)

/**
 * ESPN's public scoreboard. Separate from the fantasy client on purpose: it
 * needs no credentials, so it keeps working even when the league does not.
 */
object NflScoreboard {
    /**
     * Deliberately identifies as the HTTP library rather than as this app.
     * ESPN's public scoreboard allows known HTTP clients such as okhttp and
     * curl, and rejects browser-like and app-like agents; see the request
     * below. (Note for the next editor: Kotlin block comments nest, so a
     * literal slash-star in here silently swallows the rest of the file.)
     */
    private const val USER_AGENT = "okhttp/4.12.0"

    private val http = HttpClient(OkHttp)
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private var cached: Pair<List<NflGame>, Long>? = null

    suspend fun games(): List<NflGame> {
        cached?.let { (games, at) ->
            if (System.currentTimeMillis() - at < 30_000) return games
        }
        val response = http.get(
            "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
        ) {
            // ESPN's edge blocks anything that looks like a browser or an app
            // and lets through known API clients. Ktor's default "ktor-client"
            // is refused with an HTML "Access Denied" page, which then fails to
            // parse as JSON — so the symptom is a decode error, not a 403.
            header("User-Agent", USER_AGENT)
            header("Accept", "application/json")
        }
        val body = response.bodyAsText()
        if (!body.startsWith("{")) {
            throw IllegalStateException(
                "ESPN refused the scoreboard request (${response.status.value}): " +
                    body.take(120)
            )
        }

        val games = json.decodeFromString<Scoreboard>(body).events.map { event ->
            val competition = event.competitions.firstOrNull()
            val competitors = competition?.competitors.orEmpty()
            val state = competition?.status?.type?.state ?: event.status?.type?.state
            NflGame(
                id = event.id,
                name = event.name.orEmpty(),
                shortName = event.shortName.orEmpty(),
                statusText = competition?.status?.type?.shortDetail
                    ?: event.status?.type?.shortDetail.orEmpty(),
                isFinal = competition?.status?.type?.completed == true,
                isLive = state == "in",
                home = competitors.firstOrNull { it.homeAway == "home" }?.toModel(),
                away = competitors.firstOrNull { it.homeAway == "away" }?.toModel(),
            )
        }
        cached = games to System.currentTimeMillis()
        return games
    }

    private fun Competitor.toModel() = NflCompetitor(
        abbreviation = team?.abbreviation.orEmpty(),
        name = team?.shortDisplayName ?: team?.displayName.orEmpty(),
        // ESPN returns several records per team; "overall" is the season one.
        record = records.firstOrNull { it.type == "total" }?.summary
            ?: records.firstOrNull()?.summary,
        score = score.orEmpty(),
        isWinner = winner == true,
        logo = team?.logo,
    )

    @Serializable
    private data class Scoreboard(val events: List<Event> = emptyList())

    @Serializable
    private data class Event(
        val id: String,
        val name: String? = null,
        val shortName: String? = null,
        val status: Status? = null,
        val competitions: List<Competition> = emptyList(),
    )

    @Serializable
    private data class Competition(
        val status: Status? = null,
        val competitors: List<Competitor> = emptyList(),
    )

    @Serializable
    private data class Competitor(
        val homeAway: String? = null,
        val score: String? = null,
        val winner: Boolean? = null,
        val team: TeamRef? = null,
        val records: List<Record> = emptyList(),
    )

    @Serializable
    private data class Record(val type: String? = null, val summary: String? = null)

    @Serializable
    private data class TeamRef(
        val abbreviation: String? = null,
        val displayName: String? = null,
        val shortDisplayName: String? = null,
        val logo: String? = null,
    )

    @Serializable
    private data class Status(val type: StatusType? = null)

    @Serializable
    private data class StatusType(
        @SerialName("shortDetail") val shortDetail: String? = null,
        val state: String? = null,
        val completed: Boolean = false,
    )
}
