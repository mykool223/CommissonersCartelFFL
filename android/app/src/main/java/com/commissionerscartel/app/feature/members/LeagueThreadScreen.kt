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
import androidx.compose.material.icons.filled.AddReaction
import androidx.compose.material.icons.filled.AlternateEmail
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.TextButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.LeagueMessage
import com.commissionerscartel.app.data.Mentions
import com.commissionerscartel.app.data.MessageReaction
import com.commissionerscartel.app.data.ReactionSummary
import com.commissionerscartel.app.data.Reactions
import com.commissionerscartel.app.data.Session
import com.commissionerscartel.app.data.Supabase
import com.commissionerscartel.app.ui.CartelGold
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

sealed interface ThreadState {
    data object Loading : ThreadState
    data object SignInRequired : ThreadState
    /** Signed in, but the address is not on the league list. */
    data object NotAMember : ThreadState
    data class Loaded(
        val messages: List<LeagueMessage>,
        val reactions: List<MessageReaction>,
        val memberNames: List<String>,
    ) : ThreadState
    data class Failed(val message: String) : ThreadState
}

class LeagueThreadViewModel : ViewModel() {
    private val _state = MutableStateFlow<ThreadState>(ThreadState.Loading)
    val state: StateFlow<ThreadState> = _state.asStateFlow()

    private var watching: Job? = null

    init {
        // Reload whenever sign-in state settles or changes. Without this,
        // signing in on the Settings tab leaves this screen showing "sign in"
        // until the app is restarted — and at launch the stored session has
        // usually not finished loading when this runs.
        viewModelScope.launch { Session.status.collect { load() } }
    }

    /**
     * Re-reads the thread while it is on screen.
     *
     * A conversation that only updates when you leave and come back is not a
     * conversation. Landry made it obvious: you ask him something, the
     * notification arrives, and the thread you are staring at shows nothing.
     *
     * Polling rather than a live subscription — for twelve people the honest
     * cost is one small request every few seconds while somebody is actually
     * reading, and a websocket is the right answer for a thousand leagues.
     * Cancelled with the screen, so it runs only while it is being watched.
     */
    fun watch() {
        if (watching?.isActive == true) return
        watching = viewModelScope.launch {
            while (true) {
                delay(5_000)
                val current = _state.value as? ThreadState.Loaded ?: continue
                // Quiet: keep what is on screen if the request fails, so a
                // tunnel does not empty the thread.
                val fresh = runCatching { Supabase.messages() }.getOrNull() ?: continue
                if (fresh != current.messages) {
                    val reactions = runCatching { Supabase.reactions() }
                        .getOrDefault(current.reactions)
                    _state.value = current.copy(messages = fresh, reactions = reactions)
                }
            }
        }
    }

    fun stopWatching() {
        watching?.cancel()
        watching = null
    }

    fun load() {
        viewModelScope.launch {
            if (!Session.isSignedIn) {
                _state.value = ThreadState.SignInRequired
                return@launch
            }
            // Signed in is not the same as being a member: an address that is
            // not on the invite list gets no profile, and every members-only
            // policy then returns nothing. Saying so beats an empty screen.
            if (!Session.isLeagueMember()) {
                _state.value = ThreadState.NotAMember
                return@launch
            }
            _state.value = runCatching {
                val messages = Supabase.messages()
                // Reactions are a nice-to-have; a failure here should not cost
                // the thread itself.
                val reactions = runCatching { Supabase.reactions() }.getOrDefault(emptyList())
                val names = runCatching { Supabase.profiles().values.toList() }
                    .getOrDefault(emptyList())
                ThreadState.Loaded(messages, reactions, names)
            }.fold(
                onSuccess = { it },
                onFailure = { ThreadState.Failed(it.message ?: "Couldn't load the thread.") },
            )
        }
    }

    fun react(messageId: String, emoji: String, isMine: Boolean) {
        viewModelScope.launch {
            runCatching {
                if (isMine) Supabase.removeReaction(messageId, emoji)
                else Supabase.addReaction(messageId, emoji)
            }
            load()
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
    var mentioning by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    // Watch only while this screen is composed; DisposableEffect stops it the
    // moment somebody navigates away.
    DisposableEffect(Unit) {
        model.watch()
        onDispose { model.stopWatching() }
    }

    when (val current = state) {
        is ThreadState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is ThreadState.NotAMember -> Box(
            modifier.fillMaxSize().padding(32.dp),
            Alignment.Center,
        ) {
            Text("You're signed in, but that address isn't on the league list. Ask the commissioner to add it \u2014 they've been told.", style = MaterialTheme.typography.bodyMedium)
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
                    items(current.messages, key = { it.id }) { message ->
                        MessageRow(
                            message = message,
                            summaries = Reactions.summarise(
                                current.reactions, message.id, Session.userId
                            ),
                            onReact = { emoji, mine -> model.react(message.id, emoji, mine) },
                            memberNames = current.memberNames,
                        )
                    }
                }
            }

            if (mentioning) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    current.memberNames.forEach { name ->
                        AssistChip(
                            onClick = {
                                draft = (draft.trimEnd() + " @" + name + " ").trimStart()
                                mentioning = false
                            },
                            label = { Text(name) },
                        )
                    }
                }
            }

            Row(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { mentioning = !mentioning }) {
                    Icon(
                        Icons.Filled.AlternateEmail,
                        contentDescription = "Mention someone",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
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
private fun MessageRow(
    message: LeagueMessage,
    summaries: List<ReactionSummary>,
    onReact: (String, Boolean) -> Unit,
    memberNames: List<String>,
) {
    val mine = message.authorId != null && message.authorId == Session.userId
    var picking by remember { mutableStateOf(false) }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                // Names on every message, including your own: a thread where
                // some posts are anonymous reads as broken.
                if (mine) "${message.authorName} (you)" else message.authorName,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = if (mine) CartelGold else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                buildAnnotatedString {
                    append(message.body)
                    Mentions.ranges(message.body, memberNames).forEach { range ->
                        addStyle(
                            SpanStyle(color = CartelGold, fontWeight = FontWeight.Bold),
                            range.first,
                            range.last + 1,
                        )
                    }
                },
                style = MaterialTheme.typography.bodyMedium,
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                summaries.forEach { summary ->
                    AssistChip(
                        onClick = { onReact(summary.emoji, summary.isMine) },
                        label = { Text("${summary.emoji} ${summary.count}") },
                        colors = AssistChipDefaults.assistChipColors(
                            containerColor = if (summary.isMine) {
                                CartelGold.copy(alpha = 0.22f)
                            } else {
                                MaterialTheme.colorScheme.surfaceVariant
                            },
                        ),
                    )
                }
                IconButton(onClick = { picking = !picking }) {
                    Icon(
                        Icons.Filled.AddReaction,
                        contentDescription = "React",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (picking) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Reactions.palette.forEach { emoji ->
                        val alreadyMine = summaries.any { it.emoji == emoji && it.isMine }
                        TextButton(onClick = { onReact(emoji, alreadyMine); picking = false }) {
                            Text(emoji, style = MaterialTheme.typography.titleMedium)
                        }
                    }
                }
            }
        }
    }
}
