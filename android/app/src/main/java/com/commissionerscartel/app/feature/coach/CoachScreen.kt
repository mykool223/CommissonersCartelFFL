package com.commissionerscartel.app.feature.coach

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
import androidx.compose.material3.AssistChip
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.size
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.commissionerscartel.app.R
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.ui.CartelGold

/** Suggested openers, so nobody faces an empty box wondering what to type. */
private val PROMPTS = listOf(
    "Who should I start at flex?",
    "Is my lineup right this week?",
    "Who is my weakest starter?",
)

@Composable
fun CoachScreen(modifier: Modifier = Modifier, model: CoachViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    var draft by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    Column(modifier.fillMaxSize().imePadding()) {
        if (state.turns.isEmpty() && !state.busy) {
            Box(Modifier.weight(1f).fillMaxWidth().padding(24.dp), Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        painterResource(R.drawable.ic_coach),
                        contentDescription = null,
                        tint = CartelGold,
                        modifier = Modifier.size(40.dp).padding(bottom = 10.dp),
                    )
                    Text(
                        "Ask about your own team. He has your roster and this " +
                            "week's projections in front of him.",
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        } else {
            LaunchedEffect(state.turns.size) {
                if (state.turns.isNotEmpty()) listState.scrollToItem(state.turns.lastIndex)
            }
            LazyColumn(
                Modifier.weight(1f),
                state = listState,
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(state.turns) { turn ->
                    Card(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(
                                if (turn.fromCoach) "COACH MADDEN" else "YOU",
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = if (turn.fromCoach) CartelGold
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(turn.text, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                if (state.busy) {
                    item {
                        Box(Modifier.fillMaxWidth().padding(12.dp), Alignment.Center) {
                            CircularProgressIndicator()
                        }
                    }
                }
            }
        }

        if (state.turns.isEmpty()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                PROMPTS.take(2).forEach { prompt ->
                    AssistChip(onClick = { model.ask(prompt) }, label = { Text(prompt) })
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
                placeholder = { Text("Ask Coach Madden") },
                modifier = Modifier.weight(1f),
                maxLines = 3,
            )
            IconButton(
                onClick = { model.ask(draft.trim()); draft = "" },
                enabled = draft.isNotBlank() && !state.busy,
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Ask")
            }
        }
    }
}
