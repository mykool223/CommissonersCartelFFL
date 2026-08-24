package com.commissionerscartel.app.feature.news

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.commissionerscartel.app.data.NewsPost
import com.commissionerscartel.app.ui.CartelGold
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The full article. The feed shows only the first line of the body. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewsPostDetail(post: NewsPost, onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
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
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            post.week?.let {
                Text(
                    "WEEK $it",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = CartelGold,
                )
            }
            Text(
                post.title,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "${post.authorName} · ${post.publishedAt.asShortDate()}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                post.body,
                style = MaterialTheme.typography.bodyLarge,
                // The posts are written with blank lines between paragraphs;
                // a little extra leading keeps them readable at length.
                lineHeight = MaterialTheme.typography.bodyLarge.fontSize * 1.5,
            )
        }
    }
}

/** Postgres timestamps arrive in a handful of shapes; none of them is fatal. */
internal fun String.asShortDate(): String = runCatching {
    DateTimeFormatter.ofPattern("MMM d", Locale.US)
        .withZone(ZoneId.systemDefault())
        .format(Instant.parse(this))
}.getOrElse { substringBefore('T') }
