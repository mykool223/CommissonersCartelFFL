package com.commissionerscartel.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Wire models, mirroring the Swift types in CartelCore. Field names match the
 * Postgres columns so no custom decoding is needed.
 */
@Serializable
data class NewsPost(
    val id: String,
    val title: String,
    val body: String,
    @SerialName("author_name") val authorName: String,
    val season: Int,
    val week: Int? = null,
    @SerialName("published_at") val publishedAt: String,
)

/**
 * One choice on a poll.
 *
 * Shape comes from `polls_with_results`, which returns `vote_count` and no
 * position — the function already orders options by position, so the list
 * arrives in the right order and the field would be redundant.
 */
@Serializable
data class PollOption(
    val id: String,
    val label: String,
    @SerialName("vote_count") val votes: Int = 0,
)

@Serializable
data class Poll(
    val id: String,
    val question: String,
    val season: Int,
    val week: Int? = null,
    @SerialName("created_by_name") val createdByName: String,
    @SerialName("closes_at") val closesAt: String? = null,
    /** The caller's own vote, or null. Results stay hidden until they vote. */
    @SerialName("my_vote_option_id") val myVoteOptionId: String? = null,
    val options: List<PollOption> = emptyList(),
) {
    val totalVotes: Int get() = options.sumOf { it.votes }

    /** Results are revealed once you have voted, or once voting has closed. */
    val showsResults: Boolean get() = myVoteOptionId != null || isClosed

    fun share(option: PollOption): Float =
        if (totalVotes == 0) 0f else option.votes.toFloat() / totalVotes

    /** Mirrors `Poll.isClosed` on iOS. */
    val isClosed: Boolean
        get() = closesAt?.let {
            runCatching { java.time.Instant.parse(it).isBefore(java.time.Instant.now()) }
                .getOrDefault(false)
        } ?: false
}

@Serializable
data class TeamBio(
    val season: Int,
    @SerialName("espn_team_id") val teamId: Int,
    val title: String,
    val bio: String,
)

@Serializable
data class PlayerNews(
    val id: String,
    @SerialName("player_name") val playerName: String? = null,
    @SerialName("player_position") val playerPosition: String? = null,
    @SerialName("player_team") val playerTeam: String? = null,
    val headline: String,
    val blurb: String? = null,
    @SerialName("published_at") val publishedAt: String,
) {
    /** "Josh Allen · QB, BUF", skipping whatever the source left out. */
    val subtitle: String
        get() = listOfNotNull(
            playerName?.takeIf(String::isNotBlank),
            listOfNotNull(
                playerPosition?.takeIf(String::isNotBlank),
                playerTeam?.takeIf(String::isNotBlank),
            ).joinToString(", ").takeIf(String::isNotBlank),
        ).joinToString(" · ")
}

@Serializable
data class LeagueMessage(
    val id: String,
    @SerialName("author_id") val authorId: String? = null,
    @SerialName("author_name") val authorName: String,
    val body: String,
    @SerialName("created_at") val createdAt: String,
)
