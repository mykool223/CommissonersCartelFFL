package com.commissionerscartel.app.feature.direct

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.Conversation
import com.commissionerscartel.app.data.Session
import com.commissionerscartel.app.ui.CartelGold

/** The inbox: one row per person you have a conversation with. */
@Composable
fun DirectMessagesScreen(
    modifier: Modifier = Modifier,
    model: DirectMessagesViewModel = viewModel(),
) {
    val state by model.state.collectAsStateWithLifecycle()
    var openWith by remember { mutableStateOf<Conversation?>(null) }

    openWith?.let { conversation ->
        ConversationScreen(
            conversation = conversation,
            model = model,
            onBack = { openWith = null },
        )
        return
    }

    when (val current = state) {
        is DirectState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is DirectState.SignInRequired -> Message(
            modifier,
            "Sign in under Settings to send and read private messages.",
        )

        is DirectState.Failed -> Message(modifier, current.message)

        is DirectState.Loaded -> if (current.conversations.isEmpty()) {
            Message(
                modifier,
                "No private messages yet. Open somebody's page from the roster " +
                    "and start one.",
            )
        } else {
            LazyColumn(
                modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(current.conversations, key = { it.userId }) { conversation ->
                    Card(
                        Modifier.fillMaxWidth().clickable { openWith = conversation },
                    ) {
                        Column(
                            Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(
                                conversation.displayName,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                conversation.lastMessage,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Message(modifier: Modifier, text: String) {
    Box(modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
    }
}

/** One conversation. Yours on the right, theirs on the left. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationScreen(
    conversation: Conversation,
    model: DirectMessagesViewModel,
    onBack: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    var draft by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val me = Session.userId

    val messages = (state as? DirectState.Loaded)
        ?.messages
        ?.filter { it.counterpart(me) == conversation.userId }
        .orEmpty()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(conversation.displayName) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
            LaunchedEffect(messages.size) {
                if (messages.isNotEmpty()) listState.scrollToItem(messages.lastIndex)
            }

            LazyColumn(
                Modifier.weight(1f),
                state = listState,
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(messages, key = { it.id }) { message ->
                    val mine = message.senderId == me
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start,
                    ) {
                        Card {
                            Text(
                                message.body,
                                Modifier.padding(12.dp),
                                style = MaterialTheme.typography.bodyMedium,
                                color = if (mine) CartelGold else MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            }

            Row(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    placeholder = { Text("Message ${conversation.displayName}") },
                    modifier = Modifier.weight(1f),
                    maxLines = 4,
                )
                IconButton(
                    onClick = { model.send(conversation.userId, draft.trim()); draft = "" },
                    enabled = draft.isNotBlank(),
                ) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send")
                }
            }
        }
    }
}
