package com.commissionerscartel.app.feature.polls

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.Poll
import com.commissionerscartel.app.data.PollOption
import com.commissionerscartel.app.ui.CartelGold
import kotlin.math.roundToInt

@Composable
fun PollsScreen(modifier: Modifier = Modifier, model: PollsViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    var composing by remember { mutableStateOf(false) }

    if (composing) {
        CreatePollScreen(
            onCancel = { composing = false },
            onCreate = { question, options -> model.create(question, options) { composing = false } },
        )
        return
    }

    Scaffold(
        modifier = modifier,
        floatingActionButton = {
            if (state is PollsState.Loaded) {
                FloatingActionButton(onClick = { composing = true }) {
                    Icon(Icons.Filled.Add, contentDescription = "New poll")
                }
            }
        },
    ) { padding ->
        when (val current = state) {
            is PollsState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                CircularProgressIndicator()
            }

            is PollsState.NotAMember -> Message("You're signed in, but that address isn't on the league list. Ask the commissioner to add it \u2014 they've been told.")

            is PollsState.SignInRequired -> Message(
                "Sign in under Settings to vote in league polls."
            )

            is PollsState.Failed -> Message(current.message)

            is PollsState.Loaded -> if (current.polls.isEmpty()) {
                Message("No polls yet. Tap + to start one.")
            } else {
                LazyColumn(
                    Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(current.polls, key = { it.id }) { poll ->
                        PollCard(poll) { model.vote(poll, it) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Message(text: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun PollCard(poll: Poll, onVote: (String) -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                poll.week?.let {
                    Text(
                        "WEEK $it",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = CartelGold,
                    )
                }
                Text(
                    "${poll.totalVotes} ${if (poll.totalVotes == 1) "vote" else "votes"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Text(
                poll.question,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )

            poll.options.forEach { option ->
                OptionRow(poll, option) { onVote(option.id) }
            }

            Text(
                buildString {
                    append("Started by ${poll.createdByName}")
                    if (poll.isClosed) append(" · closed")
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun OptionRow(poll: Poll, option: PollOption, onVote: () -> Unit) {
    val mine = poll.myVoteOptionId == option.id
    OutlinedCard(
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .then(if (poll.isClosed) Modifier else Modifier.clickable(onClick = onVote)),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(option.label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                if (mine) {
                    Icon(Icons.Filled.Check, contentDescription = "Your vote", tint = CartelGold)
                }
                if (poll.showsResults) {
                    Text(
                        "  ${(poll.share(option) * 100).roundToInt()}%",
                        style = MaterialTheme.typography.labelLarge,
                    )
                }
            }
            // Hidden until you have voted, so early results cannot sway anyone.
            if (poll.showsResults) {
                LinearProgressIndicator(
                    progress = { poll.share(option) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}
