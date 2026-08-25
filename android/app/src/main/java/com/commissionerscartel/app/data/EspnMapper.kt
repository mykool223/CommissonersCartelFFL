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
                val homeScore = home?.totalPoints ?: 0.0
                val awayScore = away?.totalPoints ?: 0.0
                val live = (home?.totalPointsLive ?: 0.0) + (away?.totalPointsLive ?: 0.0)

                // A winner means it is over. Live points with no winner means
                // it is happening. Neither means it has not started — without
                // this every fixture reads "IN PROGRESS" all preseason.
                val status = when {
                    !game.winner.isNullOrBlank() && game.winner != "UNDECIDED" -> MatchupStatus.Final
                    live > 0.0 || homeScore + awayScore > 0.0 -> MatchupStatus.InProgress
                    else -> MatchupStatus.Scheduled
                }

                Matchup(
                    week = week,
                    homeTeamId = home?.teamId,
                    awayTeamId = away?.teamId,
                    homeScore = homeScore,
                    awayScore = awayScore,
                    status = status,
                )
            }
}
