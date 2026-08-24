package com.commissionerscartel.app.data

/**
 * The week's superlatives, computed from the fixtures rather than fetched —
 * ESPN has no such endpoint. A direct port of WeeklyAwards.swift; the two must
 * agree, because both platforms show the same week to the same people.
 */
data class WeeklyAward(
    val kind: Kind,
    val teamId: Int,
    val opponentId: Int? = null,
    val value: Double,
) {
    enum class Kind(val title: String, val blurb: String) {
        HighestScore("Highest score", "Nobody scored more this week."),
        LowestScore("Lowest score", "Somebody has to be down here."),
        BiggestBlowout("Biggest blowout", "Won by the widest margin."),
        ClosestGame("Closest game", "Decided by almost nothing."),
        Shootout("Shootout", "The most points in one fixture."),
        Unluckiest("Unluckiest", "Scored enough to win most weeks. Lost anyway."),
        Luckiest("Luckiest", "Won with a score that usually loses."),
        MostImproved("Most improved", "The biggest jump on last week."),
    }
}

private data class Performance(val teamId: Int, val points: Double, val won: Boolean)

object WeeklyAwards {

    /**
     * @param previousWeek last week's fixtures, for [WeeklyAward.Kind.MostImproved].
     *   Pass an empty list in week one and that award is simply omitted.
     */
    fun compute(matchups: List<Matchup>, previousWeek: List<Matchup> = emptyList()): List<WeeklyAward> {
        // Only completed fixtures. Ranking teams on a game that has not been
        // played produces confident nonsense.
        val played = matchups.filter { it.status == MatchupStatus.Final }
        if (played.isEmpty()) return emptyList()

        val performances = played.flatMap { matchup ->
            listOfNotNull(
                matchup.homeTeamId?.let {
                    Performance(it, matchup.homeScore, matchup.homeScore > matchup.awayScore)
                },
                matchup.awayTeamId?.let {
                    Performance(it, matchup.awayScore, matchup.awayScore > matchup.homeScore)
                },
            )
        }
        if (performances.isEmpty()) return emptyList()

        val awards = mutableListOf<WeeklyAward>()

        performances.maxByOrNull { it.points }?.let {
            awards += WeeklyAward(WeeklyAward.Kind.HighestScore, it.teamId, value = it.points)
        }
        performances.minByOrNull { it.points }?.let {
            awards += WeeklyAward(WeeklyAward.Kind.LowestScore, it.teamId, value = it.points)
        }

        // Head-to-head awards need both sides, so byes are excluded.
        val contested = played.filter { it.homeTeamId != null && it.awayTeamId != null }

        contested.maxByOrNull { margin(it) }?.let { blowout ->
            val winnerIsHome = blowout.homeScore >= blowout.awayScore
            awards += WeeklyAward(
                WeeklyAward.Kind.BiggestBlowout,
                teamId = if (winnerIsHome) blowout.homeTeamId!! else blowout.awayTeamId!!,
                opponentId = if (winnerIsHome) blowout.awayTeamId else blowout.homeTeamId,
                value = margin(blowout),
            )
        }

        contested.minByOrNull { margin(it) }?.let { closest ->
            val winnerIsHome = closest.homeScore >= closest.awayScore
            awards += WeeklyAward(
                WeeklyAward.Kind.ClosestGame,
                teamId = if (winnerIsHome) closest.homeTeamId!! else closest.awayTeamId!!,
                opponentId = if (winnerIsHome) closest.awayTeamId else closest.homeTeamId,
                value = margin(closest),
            )
        }

        contested.maxByOrNull { it.homeScore + it.awayScore }?.let { shootout ->
            awards += WeeklyAward(
                WeeklyAward.Kind.Shootout,
                teamId = shootout.homeTeamId!!,
                opponentId = shootout.awayTeamId,
                value = shootout.homeScore + shootout.awayScore,
            )
        }

        // Highest score among the losers, and lowest among the winners.
        performances.filter { !it.won }.maxByOrNull { it.points }?.let {
            awards += WeeklyAward(WeeklyAward.Kind.Unluckiest, it.teamId, value = it.points)
        }
        performances.filter { it.won }.minByOrNull { it.points }?.let {
            awards += WeeklyAward(WeeklyAward.Kind.Luckiest, it.teamId, value = it.points)
        }

        mostImproved(performances, previousWeek)?.let { awards += it }
        return awards
    }

    private fun margin(matchup: Matchup) = kotlin.math.abs(matchup.homeScore - matchup.awayScore)

    private fun mostImproved(
        performances: List<Performance>,
        previousWeek: List<Matchup>,
    ): WeeklyAward? {
        if (previousWeek.isEmpty()) return null

        val before = buildMap {
            previousWeek.forEach { matchup ->
                matchup.homeTeamId?.let { put(it, matchup.homeScore) }
                matchup.awayTeamId?.let { put(it, matchup.awayScore) }
            }
        }

        val best = performances
            .mapNotNull { performance ->
                before[performance.teamId]?.let { performance.teamId to (performance.points - it) }
            }
            .filter { it.second > 0 }
            .maxByOrNull { it.second }
            ?: return null

        return WeeklyAward(WeeklyAward.Kind.MostImproved, best.first, value = best.second)
    }
}
