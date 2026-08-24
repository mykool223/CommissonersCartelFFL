package com.commissionerscartel.app.feature.news

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import coil3.compose.AsyncImage
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import com.commissionerscartel.app.data.PlayerNews
import com.commissionerscartel.app.data.Supabase
import com.commissionerscartel.app.ui.CartelGold
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** The player's photo, falling back to initials — a quarter of rows have none. */
@Composable
private fun Headshot(url: String?, initials: String, size: Dp = 44.dp) {
    val shape = CircleShape
    if (url.isNullOrBlank()) {
        Box(
            Modifier.size(size).clip(shape).background(CartelGold.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                initials,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = CartelGold,
            )
        }
    } else {
        AsyncImage(
            model = url,
            contentDescription = null,
            modifier = Modifier.size(size).clip(shape)
                .background(CartelGold.copy(alpha = 0.10f)),
            contentScale = ContentScale.Crop,
        )
    }
}

@Composable
private fun PlayerCard(item: PlayerNews) {
    Card(Modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Headshot(item.headshotUrl, item.initials)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (item.subtitle.isNotBlank()) {
                    Text(
                        item.subtitle.uppercase(),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = CartelGold,
                    )
                }
                Text(
                    item.headline,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                )
                item.blurb?.takeIf(String::isNotBlank)?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

sealed interface PlayerNewsState {
    data object Loading : PlayerNewsState
    data class Loaded(val items: List<PlayerNews>) : PlayerNewsState
    data class Failed(val message: String) : PlayerNewsState
}

class PlayerNewsViewModel : ViewModel() {
    private val _state = MutableStateFlow<PlayerNewsState>(PlayerNewsState.Loading)
    val state: StateFlow<PlayerNewsState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            _state.value = runCatching { Supabase.playerNews() }.fold(
                onSuccess = { PlayerNewsState.Loaded(it) },
                onFailure = { PlayerNewsState.Failed(it.message ?: "Couldn't load player news.") },
            )
        }
    }
}

@Composable
fun PlayerNewsScreen(model: PlayerNewsViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()

    when (val current = state) {
        is PlayerNewsState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is PlayerNewsState.Failed -> Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(current.message, style = MaterialTheme.typography.bodyMedium)
        }

        is PlayerNewsState.Loaded -> if (current.items.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
                Text(
                    "No player news yet. The feed refreshes every morning.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(current.items, key = { it.id }) { item -> PlayerCard(item) }
            }
        }
    }
}
