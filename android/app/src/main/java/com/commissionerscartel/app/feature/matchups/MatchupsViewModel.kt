package com.commissionerscartel.app.feature.matchups

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.EspnMapper
import com.commissionerscartel.app.data.Matchup
import com.commissionerscartel.app.data.NflGame
import com.commissionerscartel.app.data.NflScoreboard
import com.commissionerscartel.app.data.Team
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MatchupsData(
    val week: Int,
    val matchups: List<Matchup>,
    val teams: Map<Int, Team>,
    val nfl: List<NflGame>,
)

sealed interface MatchupsState {
    data object Loading : MatchupsState
    data class Loaded(val data: MatchupsData) : MatchupsState
    data class Failed(val message: String) : MatchupsState
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
                val nfl = runCatching { NflScoreboard.games() }.getOrDefault(emptyList())
                MatchupsData(
                    week = league.currentWeek,
                    matchups = EspnMapper.matchups(payload, league.currentWeek),
                    teams = teams,
                    nfl = nfl,
                )
            }.fold(
                onSuccess = { MatchupsState.Loaded(it) },
                onFailure = { MatchupsState.Failed(it.message ?: "Couldn't load matchups.") },
            )
        }
    }
}
