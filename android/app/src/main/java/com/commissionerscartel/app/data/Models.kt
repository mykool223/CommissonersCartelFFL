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

@Serializable
data class PollOption(
    val id: String,
    val label: String,
    val position: Int,
    val votes: Int = 0,
)

@Serializable
data class Poll(
    val id: String,
    val question: String,
    val season: Int,
    val week: Int? = null,
    @SerialName("created_by_name") val createdByName: String,
    @SerialName("closes_at") val closesAt: String? = null,
    val options: List<PollOption> = emptyList(),
) {
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
