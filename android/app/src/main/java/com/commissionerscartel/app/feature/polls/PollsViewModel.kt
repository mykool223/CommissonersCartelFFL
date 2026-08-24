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
    data class Loaded(val polls: List<Poll>) : PollsState
    data class Failed(val message: String) : PollsState
}

class PollsViewModel : ViewModel() {
    private val _state = MutableStateFlow<PollsState>(PollsState.Loading)
    val state: StateFlow<PollsState> = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            // Voting is per person, so a signed-out reader is asked to sign in
            // rather than shown a poll they cannot use.
            if (!Session.isSignedIn) {
                _state.value = PollsState.SignInRequired
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
