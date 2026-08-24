package com.commissionerscartel.app.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.Config
import com.commissionerscartel.app.data.NotificationPreferences
import com.commissionerscartel.app.data.Push
import com.commissionerscartel.app.data.Session
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SettingsState(
    val signedIn: Boolean = false,
    val email: String? = null,
    val isMember: Boolean = false,
    /** ESPN member id of the claimed team, or null if none claimed yet. */
    val claimedSwid: String? = null,
    val codeSentTo: String? = null,
    val busy: Boolean = false,
    val message: String? = null,
    val preferences: NotificationPreferences = NotificationPreferences(),
)

class SettingsViewModel : ViewModel() {
    private val _state = MutableStateFlow(SettingsState())
    val state: StateFlow<SettingsState> = _state.asStateFlow()

    init {
        // Same reason as Polls: the stored session loads asynchronously, so a
        // single read at startup reports signed out and never corrects itself.
        viewModelScope.launch { Session.status.collect { refresh() } }
    }

    fun refresh() {
        viewModelScope.launch {
            val signedIn = Session.isSignedIn
            _state.value = _state.value.copy(
                signedIn = signedIn,
                email = Session.email,
                isMember = if (signedIn) Session.isLeagueMember() else false,
                claimedSwid = if (signedIn) {
                    runCatching { Session.claimedTeamSwid() }.getOrNull()
                } else {
                    null
                },
                preferences = if (signedIn) {
                    runCatching { Push.preferences() }.getOrDefault(NotificationPreferences())
                } else {
                    NotificationPreferences()
                },
            )
        }
    }

    fun sendCode(email: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(busy = true, message = null)
            runCatching { Session.sendCode(email) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        busy = false,
                        codeSentTo = email,
                        // Without a domain the sender has no SPF record, so the
                        // email frequently lands in junk. Saying so up front
                        // saves a round of "I never got it".
                        message = "Check your email — including the junk folder.",
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        busy = false,
                        message = it.message ?: "Couldn't send the code.",
                    )
                }
        }
    }

    fun verify(code: String) {
        val email = _state.value.codeSentTo ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(busy = true, message = null)
            runCatching { Session.verify(email, code) }
                .onSuccess {
                    _state.value = _state.value.copy(busy = false, codeSentTo = null)
                    refresh()
                    // Only now is there a user id to store a device against.
                    runCatching { Push.register() }
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        busy = false,
                        message = "That code didn't work. They expire after an hour.",
                    )
                }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            runCatching { Push.unregister() }
            runCatching { Session.signOut() }
            refresh()
        }
    }

    fun setPreferences(preferences: NotificationPreferences) {
        _state.value = _state.value.copy(preferences = preferences)
        viewModelScope.launch { runCatching { Push.setPreferences(preferences) } }
    }

    fun claimTeam(swid: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(busy = true)
            runCatching { Session.claimTeam(swid) }
                .onFailure {
                    _state.value = _state.value.copy(
                        message = it.message ?: "Couldn't claim that team.",
                    )
                }
            _state.value = _state.value.copy(busy = false)
            refresh()
        }
    }

    val leagueId: String get() = Config.espnLeagueId
    val season: Int get() = Config.currentSeason()
}
