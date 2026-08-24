package com.commissionerscartel.app.feature.direct

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.Conversation
import com.commissionerscartel.app.data.Supabase

/**
 * Opens a conversation with somebody chosen from the roster.
 *
 * ESPN managers and app accounts are different things: a manager who has never
 * signed in has nowhere for a message to arrive, and this says so rather than
 * appearing to send into a void.
 */
@Composable
fun StartConversation(
    managerId: String,
    onClose: () -> Unit,
    model: DirectMessagesViewModel = viewModel(),
) {
    // Three states, not two: still looking, found, and "this manager has no
    // account". Collapsing the last into a spinner leaves it spinning forever.
    val resolved by produceState<Result<Conversation>?>(initialValue = null, managerId) {
        value = runCatching {
            val match = Supabase.members().firstOrNull {
                it.espnSwid?.trim().equals(managerId.trim(), ignoreCase = true)
            } ?: error("no account")
            model.conversationWith(match.id, match.displayName)
        }
    }

    when (val outcome = resolved) {
        null -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        else -> outcome.fold(
            onSuccess = { ConversationScreen(it, model, onClose) },
            onFailure = { NoAccountYet(onClose) },
        )
    }
}

/** Shown when the manager has no account to message. */
@Composable
fun NoAccountYet(onClose: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                "They haven't signed in to the app yet, so there is nowhere to " +
                    "send a message.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
            TextButton(onClick = onClose) { Text("Back") }
        }
    }
}
