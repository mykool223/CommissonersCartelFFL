package com.commissionerscartel.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * ESPN's fantasy v3 payload. Undocumented and generous with nulls, so every
 * field that is not structurally guaranteed is optional — the same defensive
 * shape as ESPNPayload.swift.
 */
@Serializable
data class EspnPayload(
    val id: Long? = null,
    val seasonId: Int? = null,
    val settings: EspnSettings? = null,
    val teams: List<EspnTeam> = emptyList(),
    val members: List<EspnMember> = emptyList(),
    val schedule: List<EspnGame> = emptyList(),
    val status: EspnStatus? = null,
)

@Serializable
data class EspnStatus(val currentMatchupPeriod: Int? = null, val latestScoringPeriod: Int? = null)

@Serializable
data class EspnSettings(
    val name: String? = null,
    val scheduleSettings: EspnScheduleSettings? = null,
)

@Serializable
data class EspnScheduleSettings(
    val matchupPeriodCount: Int? = null,
    val divisions: List<EspnDivision> = emptyList(),
)

@Serializable
data class EspnDivision(val id: Int, val name: String? = null)

@Serializable
data class EspnTeam(
    val id: Int,
    val name: String? = null,
    val abbrev: String? = null,
    val logo: String? = null,
    val divisionId: Int? = null,
    val playoffSeed: Int? = null,
    val owners: List<String> = emptyList(),
    val record: EspnRecordEnvelope? = null,
)

@Serializable
data class EspnRecordEnvelope(val overall: EspnRecord? = null)

@Serializable
data class EspnRecord(
    val wins: Int = 0,
    val losses: Int = 0,
    val ties: Int = 0,
    val pointsFor: Double = 0.0,
    val pointsAgainst: Double = 0.0,
)

@Serializable
data class EspnMember(
    val id: String,
    val firstName: String? = null,
    val lastName: String? = null,
    val displayName: String? = null,
    val isLeagueManager: Boolean = false,
)

@Serializable
data class EspnGame(
    val matchupPeriodId: Int? = null,
    val winner: String? = null,
    val home: EspnSide? = null,
    val away: EspnSide? = null,
)

@Serializable
data class EspnSide(
    val teamId: Int? = null,
    val totalPoints: Double? = null,
    @SerialName("totalPointsLive") val totalPointsLive: Double? = null,
)
