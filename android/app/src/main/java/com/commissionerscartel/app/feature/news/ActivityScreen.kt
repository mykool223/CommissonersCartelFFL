package com.commissionerscartel.app.feature.news

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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.LeagueActivity
import com.commissionerscartel.app.data.Supabase
import com.commissionerscartel.app.ui.CartelGold
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface ActivityState {
    data object Loading : ActivityState
    data class Loaded(val items: List<LeagueActivity>) : ActivityState
    data class Failed(val message: String) : ActivityState
}

class ActivityViewModel : ViewModel() {
    private val _state = MutableStateFlow<ActivityState>(ActivityState.Loading)
    val state: StateFlow<ActivityState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            _state.value = runCatching { Supabase.activity(AppGraph.season) }.fold(
                onSuccess = { ActivityState.Loaded(it) },
                onFailure = { ActivityState.Failed(it.message ?: "Couldn't load league activity.") },
            )
        }
    }
}

@Composable
fun ActivityScreen(model: ActivityViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()

    when (val current = state) {
        is ActivityState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is ActivityState.Failed -> Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(current.message, style = MaterialTheme.typography.bodyMedium)
        }

        is ActivityState.Loaded -> if (current.items.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
                Text(
                    "Nothing has moved yet. Adds, drops and trades turn up here.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(current.items, key = { it.id }) { item ->
                    Card(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    item.label,
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = CartelGold,
                                )
                                Text(
                                    item.occurredAt.asShortDate(),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Text(item.headline, style = MaterialTheme.typography.bodyLarge)
                            item.detail?.takeIf(String::isNotBlank)?.let {
                                Text(
                                    it,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
