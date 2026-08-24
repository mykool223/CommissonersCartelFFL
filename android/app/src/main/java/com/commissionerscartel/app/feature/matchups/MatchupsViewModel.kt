package com.commissionerscartel.app.feature.matchups

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.Division
import com.commissionerscartel.app.data.EspnMapper
import com.commissionerscartel.app.data.Matchup
import com.commissionerscartel.app.data.NflGame
import com.commissionerscartel.app.data.NflScoreboard
import com.commissionerscartel.app.data.Team
import com.commissionerscartel.app.data.WeeklyAward
import com.commissionerscartel.app.data.WeeklyAwards
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MatchupsData(
    val week: Int,
    val matchups: List<Matchup>,
    val teams: Map<Int, Team>,
    val nfl: List<NflGame>,
    val awards: List<WeeklyAward>,
    /** Standings, grouped by division as iOS does. */
    val standings: List<StandingsGroup>,
)

/**
 * A division's table. `division` is null for a league without divisions, and
 * for the group holding any team ESPN did not place in one.
 */
data class StandingsGroup(val division: Division?, val teams: List<Team>)

sealed interface MatchupsState {
    data object Loading : MatchupsState
    data class Loaded(val data: MatchupsData) : MatchupsState
    data class Failed(val message: String) : MatchupsState
}

/**
 * Seed first where ESPN has assigned one, then win percentage, then points
 * for. Every seed is absent before the season starts, which is why the
 * fallbacks exist rather than being defensive padding.
 */
private val standingsOrder = Comparator<Team> { a, b ->
    val seedA = a.playoffSeed
    val seedB = b.playoffSeed
    when {
        seedA != null && seedB != null -> seedA.compareTo(seedB)
        seedA != null -> -1
        seedB != null -> 1
        a.record.winPercentage != b.record.winPercentage ->
            b.record.winPercentage.compareTo(a.record.winPercentage)
        a.record.pointsFor != b.record.pointsFor ->
            b.record.pointsFor.compareTo(a.record.pointsFor)
        else -> a.name.compareTo(b.name)
    }
}

/**
 * Splits the table by division. The Cartel runs The Board and The Council, and
 * a single league-wide table hides which of the two a team is actually racing.
 */
private fun groupStandings(ordered: List<Team>, divisions: List<Division>): List<StandingsGroup> {
    if (divisions.size <= 1) return listOf(StandingsGroup(null, ordered))

    val groups = divisions.map { division ->
        StandingsGroup(division, ordered.filter { it.divisionId == division.id })
    }.toMutableList()

    // A team ESPN did not place in a division would otherwise be missing from
    // the table entirely.
    val known = divisions.map { it.id }.toSet()
    val orphans = ordered.filter { it.divisionId?.let { id -> id !in known } ?: true }
    if (orphans.isNotEmpty()) groups += StandingsGroup(null, orphans)

    return groups.filter { it.teams.isNotEmpty() }
}

class MatchupsViewModel : ViewModel() {
    private val _state = MutableStateFlow<MatchupsState>(MatchupsState.Loading)
    val state: StateFlow<MatchupsState> = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = runCatching {
                val payload = AppGraph.espn.payload()
                val league = EspnMapper.league(payload, AppGraph.season)
                val teams = EspnMapper.teams(payload, AppGraph.espn).associateBy { it.id }
                // Real NFL scores are a bonus; losing them must not empty the
                // fantasy fixtures, which are the point of the screen.
                val nfl = runCatching { NflScoreboard.games() }
                    .onFailure {
                        // Swallowing this silently is what hid the section
                        // being empty: an outage and a decode bug looked
                        // identical from the outside.
                        Log.w("Matchups", "NFL scoreboard unavailable", it)
                    }
                    .getOrDefault(emptyList())
                val week = league.currentWeek
                val matchups = EspnMapper.matchups(payload, week)
                MatchupsData(
                    week = week,
                    matchups = matchups,
                    teams = teams,
                    nfl = nfl,
                    awards = WeeklyAwards.compute(
                        matchups,
                        // Week one has nothing to improve on.
                        previousWeek = if (week > 1) EspnMapper.matchups(payload, week - 1)
                        else emptyList(),
                    ),
                    standings = groupStandings(
                        teams.values.sortedWith(standingsOrder),
                        league.divisions,
                    ),
                )
            }.fold(
                onSuccess = { MatchupsState.Loaded(it) },
                onFailure = { MatchupsState.Failed(it.message ?: "Couldn't load matchups.") },
            )
        }
    }
}
