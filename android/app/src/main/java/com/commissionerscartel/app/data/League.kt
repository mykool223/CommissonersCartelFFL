package com.commissionerscartel.app.data

/** App-facing league models, mirroring CartelCore. */
data class League(
    val id: Long,
    val name: String,
    val season: Int,
    val currentWeek: Int,
    val weekCount: Int,
    val divisions: List<Division>,
) {
    val hasDivisions: Boolean get() = divisions.size > 1
}

data class Division(val id: Int, val name: String)

data class TeamRecord(
    val wins: Int,
    val losses: Int,
    val ties: Int,
    val pointsFor: Double,
    val pointsAgainst: Double,
) {
    val summary: String get() = if (ties > 0) "$wins-$losses-$ties" else "$wins-$losses"
    val pointDifferential: Double get() = pointsFor - pointsAgainst
    val winPercentage: Double
        get() {
            val played = wins + losses + ties
            return if (played == 0) 0.0 else (wins + ties * 0.5) / played
        }
}

data class Team(
    val id: Int,
    val name: String,
    val abbreviation: String,
    val logoUrl: String?,
    val divisionId: Int?,
    val playoffSeed: Int?,
    val ownerIds: List<String>,
    val record: TeamRecord,
)

data class Manager(
    val id: String,
    val firstName: String,
    val lastName: String,
    val displayName: String,
    val isCommissioner: Boolean,
) {
    val fullName: String
        get() = listOf(firstName, lastName).filter { it.isNotBlank() }
            .joinToString(" ")
            .ifBlank { displayName }

    val initials: String
        get() = listOf(firstName, lastName)
            .filter { it.isNotBlank() }
            .mapNotNull { it.firstOrNull()?.uppercase() }
            .joinToString("")
            .ifBlank { displayName.take(1).uppercase() }
}

enum class MatchupStatus { Scheduled, InProgress, Final }

/**
 * One player on a team for a week, and what they have scored.
 *
 * Free of ESPN's numbering on purpose: the wire format uses integer ids for
 * both the position and the slot, and those mean nothing outside ESPN. They
 * are translated once, in EspnMapper.
 */
data class RosterEntry(
    val playerId: Int,
    val name: String,
    /** What the player is — "QB", "RB", "D/ST". */
    val position: String,
    /** Where they are being played — "QB", "FLEX", "Bench". Not the same. */
    val slot: String,
    val isStarter: Boolean,
    val points: Double,
)

data class Matchup(
    val week: Int,
    val homeTeamId: Int?,
    val awayTeamId: Int?,
    val homeScore: Double,
    val awayScore: Double,
    val status: MatchupStatus,
    /** Starters first in lineup order, then the bench. Empty if ESPN has
     *  posted no lineup for the week. */
    val homeRoster: List<RosterEntry> = emptyList(),
    val awayRoster: List<RosterEntry> = emptyList(),
)
