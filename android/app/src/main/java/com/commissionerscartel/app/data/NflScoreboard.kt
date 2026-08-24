package com.commissionerscartel.app.data

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
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
    val home: NflCompetitor?,
    val away: NflCompetitor?,
)

data class NflCompetitor(val abbreviation: String, val score: String, val logo: String?)

/**
 * ESPN's public scoreboard. Separate from the fantasy client on purpose: it
 * needs no credentials, so it keeps working even when the league does not.
 */
object NflScoreboard {
    private val http = HttpClient(OkHttp)
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private var cached: Pair<List<NflGame>, Long>? = null

    suspend fun games(): List<NflGame> {
        cached?.let { (games, at) ->
            if (System.currentTimeMillis() - at < 30_000) return games
        }
        val body = http.get(
            "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
        ).bodyAsText()

        val games = json.decodeFromString<Scoreboard>(body).events.map { event ->
            val competition = event.competitions.firstOrNull()
            val competitors = competition?.competitors.orEmpty()
            NflGame(
                id = event.id,
                name = event.name.orEmpty(),
                shortName = event.shortName.orEmpty(),
                statusText = competition?.status?.type?.shortDetail
                    ?: event.status?.type?.shortDetail.orEmpty(),
                isFinal = competition?.status?.type?.completed == true,
                home = competitors.firstOrNull { it.homeAway == "home" }?.toModel(),
                away = competitors.firstOrNull { it.homeAway == "away" }?.toModel(),
            )
        }
        cached = games to System.currentTimeMillis()
        return games
    }

    private fun Competitor.toModel() = NflCompetitor(
        abbreviation = team?.abbreviation.orEmpty(),
        score = score.orEmpty(),
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
        val team: TeamRef? = null,
    )

    @Serializable
    private data class TeamRef(val abbreviation: String? = null, val logo: String? = null)

    @Serializable
    private data class Status(val type: StatusType? = null)

    @Serializable
    private data class StatusType(
        @SerialName("shortDetail") val shortDetail: String? = null,
        val completed: Boolean = false,
    )
}
