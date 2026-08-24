package com.commissionerscartel.app.feature.members

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
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.EspnMapper
import com.commissionerscartel.app.data.Supabase
import com.commissionerscartel.app.data.Team
import com.commissionerscartel.app.data.Trophy
import com.commissionerscartel.app.ui.CartelGold
import com.commissionerscartel.app.ui.TeamLogo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface TrophyState {
    data object Loading : TrophyState
    data class Loaded(val trophies: List<Trophy>, val teams: Map<Int, Team>) : TrophyState
    data class Failed(val message: String) : TrophyState
}

class TrophyCaseViewModel : ViewModel() {
    private val _state = MutableStateFlow<TrophyState>(TrophyState.Loading)
    val state: StateFlow<TrophyState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            _state.value = runCatching {
                val trophies = Supabase.trophies(AppGraph.season)
                // Only pay for the ESPN payload if there is something to label.
                val teams = if (trophies.isEmpty()) {
                    emptyMap()
                } else {
                    EspnMapper.teams(AppGraph.espn.payload(), AppGraph.espn).associateBy { it.id }
                }
                TrophyState.Loaded(trophies, teams)
            }.fold(
                onSuccess = { it },
                onFailure = { TrophyState.Failed(it.message ?: "Couldn't load the trophy case.") },
            )
        }
    }
}

@Composable
fun TrophyCaseScreen(model: TrophyCaseViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()

    when (val current = state) {
        is TrophyState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is TrophyState.Failed -> Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(current.message, style = MaterialTheme.typography.bodyMedium)
        }

        is TrophyState.Loaded -> if (current.trophies.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Filled.EmojiEvents,
                        contentDescription = null,
                        tint = CartelGold,
                        modifier = Modifier.padding(bottom = 12.dp),
                    )
                    Text(
                        "The case is empty. The first trophy goes to whoever posts the " +
                            "highest score in week one.",
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        } else {
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(current.trophies, key = { it.id }) { trophy ->
                    val team = current.teams[trophy.teamId]
                    Card(Modifier.fillMaxWidth()) {
                        Row(
                            Modifier.padding(14.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            TeamLogo(team?.logoUrl, size = 40.dp)
                            Column(Modifier.weight(1f)) {
                                Text(
                                    trophy.title.uppercase(),
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = CartelGold,
                                )
                                Text(
                                    team?.name ?: "Team ${trophy.teamId}",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Bold,
                                )
                                trophy.detail?.let {
                                    Text(
                                        it,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            Icon(
                                Icons.Filled.EmojiEvents,
                                contentDescription = null,
                                tint = CartelGold,
                            )
                        }
                    }
                }
            }
        }
    }
}
