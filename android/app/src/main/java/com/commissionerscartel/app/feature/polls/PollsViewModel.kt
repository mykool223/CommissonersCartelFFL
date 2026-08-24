package com.commissionerscartel.app.feature.polls

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.Poll
import com.commissionerscartel.app.data.Session
import com.commissionerscartel.app.data.Supabase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface PollsState {
    data object Loading : PollsState
    data object SignInRequired : PollsState
    /** Signed in, but the address is not on the league list. */
    data object NotAMember : PollsState
    data class Loaded(val polls: List<Poll>) : PollsState
    data class Failed(val message: String) : PollsState
}

class PollsViewModel : ViewModel() {
    private val _state = MutableStateFlow<PollsState>(PollsState.Loading)
    val state: StateFlow<PollsState> = _state.asStateFlow()

    init {
        // Reload whenever sign-in state settles or changes. Without this,
        // signing in on the Settings tab leaves this screen showing "sign in"
        // until the app is restarted — and at launch the stored session has
        // usually not finished loading when this runs.
        viewModelScope.launch { Session.status.collect { load() } }
    }

    fun load() {
        viewModelScope.launch {
            // Voting is per person, so a signed-out reader is asked to sign in
            // rather than shown a poll they cannot use.
            if (!Session.isSignedIn) {
                _state.value = PollsState.SignInRequired
                return@launch
            }
            // Signed in is not the same as being a member: an address that is
            // not on the invite list gets no profile, and every members-only
            // policy then returns nothing. Saying so beats an empty screen.
            if (!Session.isLeagueMember()) {
                _state.value = PollsState.NotAMember
                return@launch
            }
            _state.value = runCatching { Supabase.polls(AppGraph.season) }
                .fold(
                    onSuccess = { PollsState.Loaded(it) },
                    onFailure = { PollsState.Failed(it.message ?: "Couldn't load polls.") },
                )
        }
    }

    fun vote(poll: Poll, optionId: String) {
        viewModelScope.launch {
            runCatching { Supabase.castVote(poll.id, optionId) }
            // Re-read rather than patching locally: the server replaces any
            // previous vote, and the totals have to match what it decided.
            load()
        }
    }

    fun create(question: String, options: List<String>, onDone: (String?) -> Unit) {
        viewModelScope.launch {
            runCatching { Supabase.createPoll(question, options, null) }
                .onSuccess { load(); onDone(null) }
                .onFailure { onDone(it.message ?: "Couldn't create the poll.") }
        }
    }
}
