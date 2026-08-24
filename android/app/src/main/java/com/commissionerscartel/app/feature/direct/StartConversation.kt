package com.commissionerscartel.app.feature.direct

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
    displayName: String,
    onClose: () -> Unit,
    model: DirectMessagesViewModel = viewModel(),
) {
    val resolved by produceState<Conversation?>(initialValue = null, displayName) {
        value = runCatching {
            val match = Supabase.profiles().entries.firstOrNull {
                it.value.equals(displayName, ignoreCase = true)
            }
            match?.let { model.conversationWith(it.key, it.value) }
        }.getOrNull()
    }

    when (val conversation = resolved) {
        null -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }
        else -> ConversationScreen(conversation = conversation, model = model, onBack = onClose)
    }
}

/** Shown when the manager has no account to message. */
@Composable
fun NoAccountYet(displayName: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
        Text(
            "$displayName hasn't signed in to the app yet, so there is nowhere " +
                "to send a message.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
        )
    }
}
