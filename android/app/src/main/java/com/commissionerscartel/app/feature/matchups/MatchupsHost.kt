package com.commissionerscartel.app.feature.matchups

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
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
import com.commissionerscartel.app.data.Team
import com.commissionerscartel.app.data.WeeklyAward
import com.commissionerscartel.app.feature.coach.CoachScreen
import com.commissionerscartel.app.ui.CartelGold
import com.commissionerscartel.app.ui.TeamLogo
import java.util.Locale

enum class MatchupsSection(val label: String) {
    Scoreboard("Scoreboard"),
    Recap("Weekly recap"),
    Standings("Standings"),
    Nfl("NFL scores"),
    Coach("Coach Landry"),
}

/** The Matchups tab, with the four sections the iOS dropdown offers. */
@Composable
fun MatchupsHost(modifier: Modifier = Modifier, model: MatchupsViewModel = viewModel()) {
    var section by remember { mutableStateOf(MatchupsSection.Scoreboard) }
    val state by model.state.collectAsStateWithLifecycle()

    Column(modifier.fillMaxSize()) {
        // Four chips do not fit across a phone, so this row scrolls.
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            MatchupsSection.entries.forEach { entry ->
                FilterChip(
                    selected = entry == section,
                    onClick = { section = entry },
                    label = { Text(entry.label) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = CartelGold.copy(alpha = 0.2f),
                    ),
                )
            }
        }

        when (val current = state) {
            is MatchupsState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                CircularProgressIndicator()
            }

            is MatchupsState.Failed -> Message(current.message)

            is MatchupsState.Loaded -> when (section) {
                MatchupsSection.Scoreboard -> ScoreboardSection(current.data)
                MatchupsSection.Recap -> RecapSection(current.data)
                MatchupsSection.Standings -> StandingsSection(current.data.standings)
                MatchupsSection.Nfl -> NflSection(current.data)
                MatchupsSection.Coach -> CoachScreen()
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
private fun RecapSection(data: MatchupsData) {
    if (data.awards.isEmpty()) {
        // Ranking teams on games that have not been played produces confident
        // nonsense, so say nothing instead.
        Message("No results yet for week ${data.week}. The recap fills in once games are final.")
        return
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(data.awards) { award -> AwardCard(award, data.teams) }
    }
}

@Composable
private fun AwardCard(award: WeeklyAward, teams: Map<Int, Team>) {
    val team = teams[award.teamId]
    Card(Modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamLogo(team?.logoUrl, size = 40.dp)
            Column(Modifier.weight(1f)) {
                Text(
                    award.kind.title.uppercase(Locale.US),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = CartelGold,
                )
                Text(
                    team?.name ?: "Team ${award.teamId}",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    award.kind.blurb,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                String.format(Locale.US, "%.1f", award.value),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun StandingsSection(groups: List<StandingsGroup>) {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        groups.forEach { group ->
            group.division?.let { division ->
                item(key = "division-${division.id}") {
                    Row(
                        Modifier.fillMaxWidth().padding(top = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            division.name,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            group.teams.size.toString(),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            // Rank is within the division, not the league — that is the whole
            // point of splitting the table.
            itemsIndexed(group.teams, key = { _, team -> team.id }) { index, team ->
                StandingsRow(rank = index + 1, team = team)
            }
        }
    }
}

@Composable
private fun StandingsRow(rank: Int, team: Team) {
    Card(Modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "$rank",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TeamLogo(team.logoUrl, size = 36.dp)
            Column(Modifier.weight(1f)) {
                Text(
                    team.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    team.record.summary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    String.format(Locale.US, "%.1f", team.record.pointsFor),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    "PF",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
