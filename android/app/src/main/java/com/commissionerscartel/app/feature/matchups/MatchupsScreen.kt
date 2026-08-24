package com.commissionerscartel.app.feature.matchups

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
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.Matchup
import com.commissionerscartel.app.data.MatchupStatus
import com.commissionerscartel.app.data.NflGame
import com.commissionerscartel.app.data.Team
import com.commissionerscartel.app.ui.CartelGold
import com.commissionerscartel.app.ui.TeamLogo
import java.util.Locale

@Composable
fun MatchupsScreen(modifier: Modifier = Modifier, model: MatchupsViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()

    when (val current = state) {
        is MatchupsState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is MatchupsState.Failed -> Box(modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(current.message, style = MaterialTheme.typography.bodyMedium)
        }

        is MatchupsState.Loaded -> LazyColumn(
            modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Text(
                    "WEEK ${current.data.week}",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = CartelGold,
                )
            }

            if (current.data.matchups.isEmpty()) {
                item {
                    Text(
                        "No fixtures for this week yet.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }

            items(current.data.matchups.size) { index ->
                MatchupCard(current.data.matchups[index], current.data.teams)
            }

            if (current.data.nfl.isNotEmpty()) {
                item {
                    Text(
                        "AROUND THE NFL",
                        Modifier.padding(top = 20.dp),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = CartelGold,
                    )
                }
                items(current.data.nfl.size) { index -> NflRow(current.data.nfl[index]) }
            }
        }
    }
}

@Composable
private fun MatchupCard(matchup: Matchup, teams: Map<Int, Team>) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Side(teams[matchup.awayTeamId], matchup.awayScore, matchup.status)
            Side(teams[matchup.homeTeamId], matchup.homeScore, matchup.status)
            Text(
                when (matchup.status) {
                    MatchupStatus.Final -> "Final"
                    MatchupStatus.InProgress -> "In progress"
                    MatchupStatus.Scheduled -> "Not started"
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Side(team: Team?, score: Double, status: MatchupStatus) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TeamLogo(team?.logoUrl, size = 32.dp)
        Text(
            team?.name ?: "TBD",
            Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
        )
        // Before kickoff every score is 0.0, which reads as a result that has
        // not happened. Show nothing instead.
        if (status != MatchupStatus.Scheduled) {
            Text(
                String.format(Locale.US, "%.1f", score),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun NflRow(game: NflGame) {
    OutlinedCard(Modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    game.shortName.ifBlank { game.name },
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    game.statusText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            val away = game.away
            val home = game.home
            if (away != null && home != null && (away.score.isNotBlank() || home.score.isNotBlank())) {
                Text(
                    "${away.abbreviation} ${away.score}  ·  ${home.abbreviation} ${home.score}",
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }
    }
}
