package com.commissionerscartel.app.feature.members

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.LeagueMessage
import com.commissionerscartel.app.data.Session
import com.commissionerscartel.app.data.Supabase
import com.commissionerscartel.app.ui.CartelGold
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface ThreadState {
    data object Loading : ThreadState
    data object SignInRequired : ThreadState
    data class Loaded(val messages: List<LeagueMessage>) : ThreadState
    data class Failed(val message: String) : ThreadState
}

class LeagueThreadViewModel : ViewModel() {
    private val _state = MutableStateFlow<ThreadState>(ThreadState.Loading)
    val state: StateFlow<ThreadState> = _state.asStateFlow()

    init {
        // Reload whenever sign-in state settles or changes. Without this,
        // signing in on the Settings tab leaves this screen showing "sign in"
        // until the app is restarted — and at launch the stored session has
        // usually not finished loading when this runs.
        viewModelScope.launch { Session.status.collect { load() } }
    }

    fun load() {
        viewModelScope.launch {
            if (!Session.isSignedIn) {
                _state.value = ThreadState.SignInRequired
                return@launch
            }
            _state.value = runCatching { Supabase.messages() }.fold(
                onSuccess = { ThreadState.Loaded(it) },
                onFailure = { ThreadState.Failed(it.message ?: "Couldn't load the thread.") },
            )
        }
    }

    fun post(body: String) {
        viewModelScope.launch {
            runCatching { Supabase.postMessage(body) }
            load()
        }
    }
}

@Composable
fun LeagueThreadScreen(modifier: Modifier = Modifier, model: LeagueThreadViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    var draft by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    when (val current = state) {
        is ThreadState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is ThreadState.SignInRequired -> Box(
            modifier.fillMaxSize().padding(32.dp),
            Alignment.Center,
        ) {
            Text(
                "Sign in under Settings to read and post in the league thread.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }

        is ThreadState.Failed -> Box(modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(current.message, style = MaterialTheme.typography.bodyMedium)
        }

        is ThreadState.Loaded -> Column(modifier.fillMaxSize().imePadding()) {
            // New messages arrive at the bottom, so open there.
            LaunchedEffect(current.messages.size) {
                if (current.messages.isNotEmpty()) {
                    listState.scrollToItem(current.messages.lastIndex)
                }
            }

            if (current.messages.isEmpty()) {
                Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                    Text("Nothing said yet.", style = MaterialTheme.typography.bodyMedium)
                }
            } else {
                LazyColumn(
                    Modifier.weight(1f),
                    state = listState,
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(current.messages, key = { it.id }) { MessageRow(it) }
                }
            }

            Row(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    placeholder = { Text("Say something") },
                    modifier = Modifier.weight(1f),
                    maxLines = 4,
                )
                IconButton(
                    onClick = { model.post(draft.trim()); draft = "" },
                    enabled = draft.isNotBlank(),
                ) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send")
                }
            }
        }
    }
}

@Composable
private fun MessageRow(message: LeagueMessage) {
    val mine = message.authorId != null && message.authorId == Session.userId
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                // Names on every message, including your own: a thread where
                // some posts are anonymous reads as broken.
                if (mine) "${message.authorName} (you)" else message.authorName,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = if (mine) CartelGold else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(message.body, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
