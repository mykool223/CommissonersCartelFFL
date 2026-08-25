package com.commissionerscartel.app.feature.members

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
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.ui.TeamLogo

@Composable
fun MembersScreen(
    modifier: Modifier = Modifier,
    onOpen: (MemberEntry) -> Unit,
    model: MembersViewModel = viewModel(),
) {
    val state by model.state.collectAsStateWithLifecycle()

    when (val current = state) {
        is MembersState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is MembersState.Failed -> Box(modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(current.message, style = MaterialTheme.typography.bodyMedium)
        }

        is MembersState.Loaded -> LazyColumn(
            modifier = modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            current.groups.forEach { group ->
                group.division?.let { division ->
                    item(key = "header-${division.id}") {
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
                                group.entries.size.toString(),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                items(group.entries, key = { it.manager.id }) { entry ->
                    MemberRow(entry) { onOpen(entry) }
                }
            }
        }
    }
}

@Composable
private fun MemberRow(entry: MemberEntry, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(
            Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamLogo(entry.team?.logoUrl)
            Column(Modifier.weight(1f)) {
                Text(
                    entry.team?.name ?: entry.manager.fullName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    entry.manager.fullName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            // The power ranking where the league has published one, and ESPN's
            // seed only once games have actually been played.
            (entry.powerRank ?: entry.team?.playoffSeed)?.let {
                Text("#$it", style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}
