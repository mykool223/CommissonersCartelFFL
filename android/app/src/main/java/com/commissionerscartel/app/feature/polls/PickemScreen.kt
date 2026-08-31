package com.commissionerscartel.app.feature.polls

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.PickemGame
import com.commissionerscartel.app.data.PickemPick
import com.commissionerscartel.app.ui.CartelGold

/**
 * The week's confidence pool: pick every game, weight every pick.
 *
 * Tapping a team picks it and assigns the highest weight left, so working down
 * the list from the game you are surest about is one tap per game rather than
 * a pick and a separate number. The chip on each row changes a weight
 * afterwards.
 */
@Composable
fun PickemScreen(modifier: Modifier = Modifier, model: PickemViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }

    when (val current = state) {
        is PickemState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is PickemState.SignInRequired -> Message(modifier, "Sign in from Settings to play.")

        is PickemState.Failed -> Message(modifier, current.message)

        is PickemState.Loaded -> if (current.games.isEmpty()) {
            Message(modifier, "The week's fixtures appear once the NFL posts them.")
        } else {
            LazyColumn(
                modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    Column(
                        Modifier.fillMaxWidth().padding(bottom = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            "Week ${current.week}",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            current.summary,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }

                items(current.games, key = { it.eventId }) { game ->
                    GameRow(
                        game = game,
                        pick = current.picks[game.eventId],
                        available = model.availableWeights(game),
                        onChoose = { model.choose(it, game) },
                        onWeigh = { model.weigh(game, it) },
                    )
                }

                if (current.standings.isNotEmpty()) {
                    item {
                        Text(
                            "THIS WEEK",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 16.dp),
                        )
                    }
                    itemsIndexed(current.standings) { index, row ->
                        Card(Modifier.fillMaxWidth()) {
                            Row(
                                Modifier.fillMaxWidth().padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Text("${index + 1}", style = MaterialTheme.typography.titleSmall)
                                Text(
                                    row.displayName,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    "${row.correct}/${row.decided}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text("${row.points}", style = MaterialTheme.typography.titleMedium)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GameRow(
    game: PickemGame,
    pick: PickemPick?,
    available: List<Int>,
    onChoose: (String) -> Unit,
    onWeigh: (Int) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Team(game.awayAbbr, pick, game, onChoose, Modifier.weight(1f))
                Text(
                    "at",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Team(game.homeAbbr, pick, game, onChoose, Modifier.weight(1f))
            }

            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    detailFor(game),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                Weight(game, pick, available, onWeigh)
            }
        }
    }
}

@Composable
private fun Team(
    abbreviation: String,
    pick: PickemPick?,
    game: PickemGame,
    onChoose: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val chosen = pick?.chosenAbbr == abbreviation
    val won = game.final && game.winnerAbbr == abbreviation
    Box(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(
                if (chosen) CartelGold.copy(alpha = 0.18f)
                else MaterialTheme.colorScheme.surfaceVariant
            )
            .clickable(enabled = !game.locked) { onChoose(abbreviation) }
            .padding(vertical = 10.dp),
        Alignment.Center,
    ) {
        Text(
            if (won) "$abbreviation ✓" else abbreviation,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = if (chosen) FontWeight.Bold else FontWeight.Normal,
        )
    }
}

@Composable
private fun Weight(
    game: PickemGame,
    pick: PickemPick?,
    available: List<Int>,
    onWeigh: (Int) -> Unit,
) {
    if (game.locked) {
        pick?.let {
            Text(
                "${it.confidence} pts",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    var open by remember { mutableStateOf(false) }
    Box {
        Text(
            pick?.let { "${it.confidence} pts" } ?: "Weight",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier
                .clip(RoundedCornerShape(20.dp))
                .background(CartelGold.copy(alpha = 0.15f))
                .clickable(enabled = pick != null) { open = true }
                .padding(horizontal = 12.dp, vertical = 6.dp),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            available.forEach { value ->
                DropdownMenuItem(
                    text = { Text("$value points") },
                    onClick = { onWeigh(value); open = false },
                )
            }
        }
    }
}

/** Locked games say why; open ones say when they go. */
private fun detailFor(game: PickemGame): String {
    if (game.final) return game.winnerAbbr?.let { "Final · $it" } ?: "Final · tie"
    if (game.locked) return "Started · picks locked"
    return runCatching {
        java.time.format.DateTimeFormatter.ofPattern("EEE h:mm a")
            .withZone(java.time.ZoneId.systemDefault())
            .format(java.time.Instant.parse(game.kickoffAt))
    }.getOrDefault("Kickoff to come")
}

@Composable
private fun Message(modifier: Modifier, text: String) {
    Box(modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
    }
}
