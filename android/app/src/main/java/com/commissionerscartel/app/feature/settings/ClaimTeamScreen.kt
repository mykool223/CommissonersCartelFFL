package com.commissionerscartel.app.feature.settings

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.EspnMapper
import com.commissionerscartel.app.data.Manager
import com.commissionerscartel.app.data.Team
import com.commissionerscartel.app.ui.CartelGold
import com.commissionerscartel.app.ui.TeamLogo

/**
 * Which team belongs to this account.
 *
 * ESPN exposes no email addresses, so there is no way to work this out
 * automatically — the member has to point at themselves once. It matters
 * because it is what puts the right name on their posts.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClaimTeamScreen(claimedSwid: String?, onClaim: (String) -> Unit, onClose: () -> Unit) {
    val entries by produceState<List<Pair<Manager, Team?>>?>(initialValue = null) {
        value = runCatching {
            val payload = AppGraph.espn.payload()
            val teams = EspnMapper.teams(payload, AppGraph.espn)
            val byOwner = buildMap {
                teams.forEach { team -> team.ownerIds.forEach { putIfAbsent(it, team) } }
            }
            EspnMapper.managers(payload).map { it to byOwner[it.id] }
        }.getOrDefault(emptyList())
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Which team is yours?") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = "Close")
                    }
                },
            )
        },
    ) { padding ->
        val current = entries
        if (current == null) {
            Box(Modifier.fillMaxSize().padding(padding), Alignment.Center) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Text(
                    "Pick yourself once. It puts your team name on your posts " +
                        "in the league thread.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            items(current, key = { it.first.id }) { (manager, team) ->
                val mine = manager.id == claimedSwid
                Card(
                    Modifier.fillMaxWidth().clickable { onClaim(manager.id) },
                ) {
                    Row(
                        Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TeamLogo(team?.logoUrl, size = 40.dp)
                        Column(Modifier.weight(1f)) {
                            Text(
                                team?.name ?: manager.fullName,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                manager.fullName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (mine) {
                            Icon(Icons.Filled.Check, contentDescription = "Yours", tint = CartelGold)
                        }
                    }
                }
            }
        }
    }
}
