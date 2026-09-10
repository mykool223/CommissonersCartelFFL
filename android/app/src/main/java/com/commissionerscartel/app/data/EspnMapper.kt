package com.commissionerscartel.app.data

/** Turns ESPN's payload into the app's models. Mirrors ESPNMapper.swift. */
object EspnMapper {

    fun league(payload: EspnPayload, season: Int): League {
        val divisions = payload.settings?.scheduleSettings?.divisions
            .orEmpty()
            .map { Division(it.id, it.name?.takeIf(String::isNotBlank) ?: "Division ${it.id}") }

        return League(
            id = payload.id ?: 0,
            name = payload.settings?.name?.takeIf(String::isNotBlank) ?: "Fantasy League",
            season = payload.seasonId ?: season,
            currentWeek = payload.status?.currentMatchupPeriod ?: 1,
            weekCount = payload.settings?.scheduleSettings?.matchupPeriodCount ?: 14,
            divisions = divisions,
        )
    }

    fun teams(payload: EspnPayload, client: EspnClient): List<Team> =
        payload.teams.map { team ->
            val overall = team.record?.overall
            Team(
                id = team.id,
                name = team.name?.takeIf(String::isNotBlank) ?: "Team ${team.id}",
                abbreviation = team.abbrev.orEmpty(),
                // ESPN's own logo wins; the league's fills the gap.
                logoUrl = client.logoUrl(team.logo) ?: TeamLogos.forTeam(team.id),
                divisionId = team.divisionId,
                // ESPN reports 0 before the season starts, meaning "no seed
                // yet". Treating that as first place would be wrong.
                playoffSeed = team.playoffSeed?.takeIf { it > 0 },
                ownerIds = team.owners,
                record = TeamRecord(
                    wins = overall?.wins ?: 0,
                    losses = overall?.losses ?: 0,
                    ties = overall?.ties ?: 0,
                    pointsFor = overall?.pointsFor ?: 0.0,
                    pointsAgainst = overall?.pointsAgainst ?: 0.0,
                ),
            )
        }

    fun managers(payload: EspnPayload): List<Manager> =
        payload.members.map { member ->
            Manager(
                id = member.id,
                firstName = member.firstName.orEmpty(),
                lastName = member.lastName.orEmpty(),
                displayName = member.displayName?.takeIf(String::isNotBlank) ?: member.id,
                isCommissioner = member.isLeagueManager,
            )
        }

    fun matchups(payload: EspnPayload, week: Int): List<Matchup> =
        payload.schedule
            .filter { it.matchupPeriodId == week }
            .map { game ->
                val home = game.home
                val away = game.away
                val settled = !game.winner.isNullOrBlank() && game.winner != "UNDECIDED"

                // ESPN holds totalPoints at 0.0 for the whole week it is being
                // played and puts the running score in totalPointsLive. The
                // status already knew that; the score did not, so a live
                // fixture read "IN PROGRESS" next to nothing at all. Once the
                // period settles totalPoints is the authority — ESPN stops
                // updating totalPointsLive, and a corrected stat lands only on
                // the former.
                val homeScore =
                    if (settled) home?.totalPoints ?: 0.0
                    else home?.totalPointsLive ?: home?.totalPoints ?: 0.0
                val awayScore =
                    if (settled) away?.totalPoints ?: 0.0
                    else away?.totalPointsLive ?: away?.totalPoints ?: 0.0

                // A winner means it is over. Points with no winner means it is
                // happening. Neither means it has not started — without this
                // every fixture reads "IN PROGRESS" all preseason.
                val status = when {
                    settled -> MatchupStatus.Final
                    homeScore + awayScore > 0.0 -> MatchupStatus.InProgress
                    else -> MatchupStatus.Scheduled
                }

                Matchup(
                    week = week,
                    homeTeamId = home?.teamId,
                    awayTeamId = away?.teamId,
                    homeScore = homeScore,
                    awayScore = awayScore,
                    status = status,
                    homeRoster = roster(home, settled),
                    awayRoster = roster(away, settled),
                )
            }

    /** What a player is, by ESPN's defaultPositionId. */
    private val positions = mapOf(
        1 to "QB", 2 to "RB", 3 to "WR", 4 to "TE", 5 to "K",
        9 to "DT", 10 to "DE", 11 to "LB", 12 to "CB", 13 to "S", 14 to "DB",
        16 to "D/ST", 17 to "P", 18 to "HC",
    )

    /**
     * Where a player is being played, by ESPN's lineupSlotId, with the order a
     * lineup is conventionally read in. Bench and injured reserve sort last:
     * a boxscore is read starters first, and burying the people who scored
     * under the ones who did not would be a strange way to show it.
     */
    private data class Slot(val label: String, val rank: Int, val isStarter: Boolean)

    private val slots = mapOf(
        0 to Slot("QB", 0, true),
        2 to Slot("RB", 1, true),
        4 to Slot("WR", 2, true),
        6 to Slot("TE", 3, true),
        23 to Slot("FLEX", 4, true),
        3 to Slot("RB/WR", 4, true),
        5 to Slot("WR/TE", 4, true),
        7 to Slot("OP", 5, true),
        16 to Slot("D/ST", 6, true),
        17 to Slot("K", 7, true),
        8 to Slot("DT", 8, true), 9 to Slot("DE", 8, true), 10 to Slot("LB", 8, true),
        11 to Slot("DL", 8, true), 12 to Slot("CB", 8, true), 13 to Slot("S", 8, true),
        14 to Slot("DB", 8, true), 15 to Slot("DP", 8, true), 18 to Slot("P", 8, true),
        19 to Slot("HC", 8, true),
        20 to Slot("Bench", 98, false),
        21 to Slot("IR", 99, false),
    )

    /**
     * A settled week wants the roster that actually played it; ESPN's
     * "current" roster would show whoever is on the team today. A week still
     * going wants the opposite: the matchup-period roster fills in only as
     * players lock, so mid-Sunday it is a handful of names, not a lineup.
     */
    private fun roster(side: EspnSide?, settled: Boolean): List<RosterEntry> {
        if (side == null) return emptyList()
        val source =
            if (settled) side.rosterForMatchupPeriod ?: side.rosterForCurrentScoringPeriod
            else side.rosterForCurrentScoringPeriod ?: side.rosterForMatchupPeriod
        val entries = source?.entries ?: return emptyList()

        return entries.mapIndexedNotNull { index, entry ->
            val pool = entry.playerPoolEntry ?: return@mapIndexedNotNull null
            val player = pool.player
            // Nothing identifiable or nothing to call them by: not a row worth
            // showing anybody.
            val id = player?.id ?: pool.id ?: return@mapIndexedNotNull null
            val name = player?.fullName ?: return@mapIndexedNotNull null
            // An unknown slot counts as a starter: ESPN adds slots for new
            // formats, and hiding somebody who is scoring is worse than
            // showing a label we do not have a name for.
            val slot = slots[entry.lineupSlotId] ?: Slot("—", 50, true)
            Triple(
                index,
                slot.rank,
                RosterEntry(
                    playerId = id,
                    name = name,
                    position = positions[player.defaultPositionId] ?: "—",
                    slot = slot.label,
                    isStarter = slot.isStarter,
                    points = pool.appliedStatTotal ?: 0.0,
                ),
            )
        }
            // Stable within a slot: ESPN's own order, which is what keeps two
            // running backs in the same order between refreshes.
            .sortedWith(compareBy({ it.second }, { it.first }))
            .map { it.third }
    }
}
