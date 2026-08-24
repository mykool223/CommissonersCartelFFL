package com.commissionerscartel.app.feature

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import com.commissionerscartel.app.R
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.data.NewsPost

@Composable
fun NewsScreen(modifier: Modifier = Modifier, model: NewsViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()

    when (val current = state) {
        is NewsState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        is NewsState.Failed -> Box(modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(current.message, style = MaterialTheme.typography.bodyMedium)
        }

        is NewsState.Loaded -> LazyColumn(
            modifier = modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // The crest heads the feed, the same as iOS.
            item(key = "crest") {
                Box(Modifier.fillMaxWidth(), Alignment.Center) {
                    androidx.compose.foundation.Image(
                        painter = painterResource(R.drawable.league_crest),
                        contentDescription = null,
                        modifier = Modifier.size(180.dp).padding(bottom = 8.dp),
                    )
                }
            }
            items(current.posts, key = { it.id }) { PostCard(it) }
        }
    }
}

@Composable
private fun PostCard(post: NewsPost) {
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(post.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(
                post.body.lineSequence().first(),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "by ${post.authorName}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
