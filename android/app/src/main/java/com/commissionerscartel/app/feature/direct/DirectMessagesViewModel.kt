package com.commissionerscartel.app.feature.direct

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.Conversation
import com.commissionerscartel.app.data.DirectMessage
import com.commissionerscartel.app.data.Session
import com.commissionerscartel.app.data.Supabase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface DirectState {
    data object Loading : DirectState
    data object SignInRequired : DirectState
    /** Signed in, but the address is not on the league list. */
    data object NotAMember : DirectState
    data class Loaded(
        val messages: List<DirectMessage>,
        val conversations: List<Conversation>,
    ) : DirectState
    data class Failed(val message: String) : DirectState
}

class DirectMessagesViewModel : ViewModel() {
    private val _state = MutableStateFlow<DirectState>(DirectState.Loading)
    val state: StateFlow<DirectState> = _state.asStateFlow()

    init {
        viewModelScope.launch { Session.status.collect { load() } }
    }

    fun load() {
        viewModelScope.launch {
            if (!Session.isSignedIn) {
                _state.value = DirectState.SignInRequired
                return@launch
            }
            // Signed in is not the same as being a member: an address that is
            // not on the invite list gets no profile, and every members-only
            // policy then returns nothing. Saying so beats an empty screen.
            if (!Session.isLeagueMember()) {
                _state.value = DirectState.NotAMember
                return@launch
            }
            _state.value = runCatching {
                val messages = Supabase.directMessages()
                val names = runCatching { Supabase.profiles() }.getOrDefault(emptyMap())
                DirectState.Loaded(messages, fold(messages, names))
            }.fold(
                onSuccess = { it },
                onFailure = { DirectState.Failed(it.message ?: "Couldn't load messages.") },
            )
        }
    }

    fun send(recipientId: String, body: String) {
        if (body.isBlank()) return
        viewModelScope.launch {
            runCatching { Supabase.sendDirectMessage(recipientId, body) }
            load()
        }
    }

    /** Starts an empty conversation locally, so a first message has somewhere to go. */
    fun conversationWith(userId: String, displayName: String): Conversation =
        (state.value as? DirectState.Loaded)
            ?.conversations
            ?.firstOrNull { it.userId == userId }
            ?: Conversation(userId, displayName, "", "")

    private fun fold(
        messages: List<DirectMessage>,
        names: Map<String, String>,
    ): List<Conversation> {
        val me = Session.userId
        return messages
            .groupBy { it.counterpart(me) }
            .map { (userId, thread) ->
                val last = thread.maxByOrNull { it.createdAt }
                Conversation(
                    userId = userId,
                    displayName = names[userId] ?: "Someone",
                    lastMessage = last?.body.orEmpty(),
                    lastAt = last?.createdAt.orEmpty(),
                )
            }
            // Most recently active first, which is the only order an inbox
            // should ever be in.
            .sortedByDescending { it.lastAt }
    }
}
