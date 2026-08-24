package com.commissionerscartel.app.feature.members

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.commissionerscartel.app.data.TeamRecord
import com.commissionerscartel.app.ui.CartelGold
import com.commissionerscartel.app.ui.TeamLogo
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MemberDetailScreen(
    entry: MemberEntry,
    onBack: () -> Unit,
    onMessage: ((String) -> Unit)? = null,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(entry.manager.fullName) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            TeamLogo(entry.team?.logoUrl, size = 88.dp)
            Text(
                entry.team?.name ?: entry.manager.fullName,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "@${entry.manager.displayName}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Only for members who have signed in: a message needs somewhere
            // to arrive, and an ESPN manager is not necessarily an account.
            if (onMessage != null) {
                Button(onClick = { onMessage(entry.manager.fullName) }) {
                    Icon(
                        Icons.Filled.Email,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Text("  Message ${entry.manager.fullName.substringBefore(' ')}")
                }
            }

            entry.bio?.let { bio ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Filled.FormatQuote,
                                contentDescription = null,
                                tint = CartelGold,
                                modifier = Modifier.size(16.dp),
                            )
                            Text(
                                bio.title.uppercase(Locale.US),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 1.2.sp,
                                color = CartelGold,
                            )
                        }
                        Text(bio.bio, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }

            entry.team?.record?.let { SeasonCard(it, entry.team.playoffSeed) }
        }
    }
}

@Composable
private fun SeasonCard(record: TeamRecord, seed: Int?) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Season", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            StatRow("Record", record.summary)
            StatRow("Win %", String.format(Locale.US, "%.1f%%", record.winPercentage * 100))
            StatRow("Points for", String.format(Locale.US, "%.1f", record.pointsFor))
            StatRow("Points against", String.format(Locale.US, "%.1f", record.pointsAgainst))
            StatRow(
                "Differential",
                String.format(Locale.US, "%+.1f", record.pointDifferential),
            )
            seed?.let { StatRow("Standing", "#$it") }
        }
    }
}

@Composable
private fun StatRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
