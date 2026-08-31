package com.commissionerscartel.app.feature.polls

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.Config
import com.commissionerscartel.app.data.PickemGame
import com.commissionerscartel.app.data.PickemPick
import com.commissionerscartel.app.data.PickemStanding
import com.commissionerscartel.app.data.Session
import com.commissionerscartel.app.data.Supabase
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate

sealed interface PickemState {
    data object Loading : PickemState
    data object SignInRequired : PickemState
    data class Failed(val message: String) : PickemState
    data class Loaded(
        val week: Int,
        val games: List<PickemGame>,
        /** The signed-in member's own picks, by event. */
        val picks: Map<String, PickemPick>,
        val standings: List<PickemStanding>,
    ) : PickemState {
        val summary: String
            get() {
                val open = games.count { !it.locked }
                return when {
                    open == 0 -> "Every game has started. Picks are locked."
                    picks.size == games.size ->
                        "All ${games.size} picked. Tap the points to reweigh, " +
                            "any time before kickoff."
                    else ->
                        "${picks.size} of ${games.size} picked. Tap a team to " +
                            "pick it, then tap the points to change what it is worth."
                }
            }
    }
}

class PickemViewModel : ViewModel() {
    private val _state = MutableStateFlow<PickemState>(PickemState.Loading)
    val state: StateFlow<PickemState> = _state.asStateFlow()

    private var saving: Job? = null

    fun load() {
        viewModelScope.launch {
            val me = Session.userId
            if (me == null) {
                _state.value = PickemState.SignInRequired
                return@launch
            }
            val season = Config.currentSeason()
            val week = currentWeek()
            _state.value = runCatching {
                val games = Supabase.pickemGames(season, week)
                val stored = Supabase.pickemPicks(season, week)
                    .filter { it.userId == me }
                    .associateBy { it.eventId }
                // Anything picked here but not yet saved is kept, so a failed
                // save does not silently undo the pick in front of somebody.
                val pending = (_state.value as? PickemState.Loaded)?.picks.orEmpty()
                val mine = stored + pending.filterKeys { it !in stored }
                // The table is a nicety; losing it should not lose the board.
                val standings = runCatching { Supabase.pickemStandings(season, week) }
                    .getOrDefault(emptyList())
                PickemState.Loaded(week, games, mine, standings)
            }.fold(
                onSuccess = { it },
                onFailure = { PickemState.Failed(it.message ?: "Couldn't load the games.") },
            )
        }
    }

    /** Weights not already spent, plus whatever this game currently holds. */
    fun availableWeights(game: PickemGame): List<Int> {
        val current = _state.value as? PickemState.Loaded ?: return emptyList()
        val spent = current.picks.values
            .filter { it.eventId != game.eventId }
            .map { it.confidence }
            .toSet()
        return (1..maxOf(current.games.size, 1)).filterNot { it in spent }.reversed()
    }

    /**
     * Picking a team assigns the highest weight still unspent, so working down
     * from the game you are surest about is one tap each.
     */
    fun choose(team: String, game: PickemGame) {
        val current = _state.value as? PickemState.Loaded ?: return
        val me = Session.userId ?: return
        if (game.locked) return

        val confidence = current.picks[game.eventId]?.confidence
            ?: availableWeights(game).firstOrNull()
            ?: 1
        val updated = current.picks + (game.eventId to PickemPick(
            userId = me, season = game.season, week = game.week,
            eventId = game.eventId, chosenAbbr = team, confidence = confidence,
        ))
        _state.value = current.copy(picks = updated)
        save()
    }

    fun weigh(game: PickemGame, confidence: Int) {
        val current = _state.value as? PickemState.Loaded ?: return
        val me = Session.userId ?: return
        val existing = current.picks[game.eventId] ?: return
        if (game.locked) return

        // Whoever held this weight swaps into the one being vacated, so the
        // set stays a permutation without the member having to tidy up.
        val updated = current.picks.toMutableMap()
        updated.values.firstOrNull {
            it.confidence == confidence && it.eventId != game.eventId
        }?.let { clash ->
            updated[clash.eventId] = clash.copy(confidence = existing.confidence)
        }
        updated[game.eventId] = existing.copy(confidence = confidence)
        _state.value = current.copy(picks = updated)
        save()
    }

    /**
     * Saves shortly after the last change rather than on every tap: sixteen
     * games would otherwise be sixteen writes, and the weights are only valid
     * as a set anyway.
     */
    private fun save() {
        saving?.cancel()
        saving = viewModelScope.launch {
            delay(600)
            val current = _state.value as? PickemState.Loaded ?: return@launch
            // Only games still open; the database refuses the rest, and
            // including them would fail the whole write.
            val open = current.games.filterNot { it.locked }.map { it.eventId }.toSet()
            runCatching {
                Supabase.savePickemPicks(current.picks.values.filter { it.eventId in open })
            }
        }
    }

    /**
     * Week 1 begins on the first Tuesday of September; clamped to 1-18.
     * The same calculation the scripts and iOS use.
     */
    private fun currentWeek(today: LocalDate = LocalDate.now()): Int {
        val season = Config.currentSeason()
        val september = LocalDate.of(season, 9, 1)
        // DayOfWeek: Monday is 1, so Tuesday is 2.
        val kickoff = september.plusDays(((2 - september.dayOfWeek.value + 7) % 7).toLong())
        if (today.isBefore(kickoff)) return 1
        val days = java.time.temporal.ChronoUnit.DAYS.between(kickoff, today)
        return minOf(18, (days / 7 + 1).toInt())
    }
}
