package com.commissionerscartel.app.feature.news

import android.content.Intent
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.commissionerscartel.app.data.AnalysisItem
import com.commissionerscartel.app.data.Supabase
import com.commissionerscartel.app.ui.CartelGold

/**
 * Articles from FantasyPros.
 *
 * Their headline and a short extract of their read; the full piece opens on
 * their site. Their writing is theirs, and a link is the honest way to pass
 * somebody else's work along — as well as the one our licence supports.
 */
@Composable
fun AnalysisScreen(modifier: Modifier = Modifier) {
    var items by remember { mutableStateOf<List<AnalysisItem>?>(null) }
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        items = runCatching { Supabase.analysis() }.getOrDefault(emptyList())
    }

    val current = items
    when {
        current == null -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }

        current.isEmpty() -> Box(modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Text(
                "No articles yet. FantasyPros articles appear here through the day.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
        }

        else -> LazyColumn(
            modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(current, key = { it.id }) { item ->
                Card(
                    Modifier.fillMaxWidth().clickable {
                        context.startActivity(Intent(Intent.ACTION_VIEW, item.link.toUri()))
                    },
                ) {
                    Column(
                        Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        item.author?.let {
                            Text(
                                it.uppercase(),
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = CartelGold,
                            )
                        }
                        Text(
                            item.title,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold,
                        )
                        item.excerpt?.let {
                            // An extract, not the whole piece.
                            Text(
                                it,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(
                            "Read on FantasyPros",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = CartelGold,
                        )
                    }
                }
            }
            item {
                Text(
                    "From FantasyPros.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
        }
    }
}
