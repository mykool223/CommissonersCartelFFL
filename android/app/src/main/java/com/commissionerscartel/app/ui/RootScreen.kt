package com.commissionerscartel.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SportsFootball
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.commissionerscartel.app.feature.NewsScreen
import com.commissionerscartel.app.feature.PlaceholderScreen

/** The five tabs, in the same order as iOS so the two apps feel like one app. */
private enum class Tab(val label: String, val icon: ImageVector) {
    News("News", Icons.Filled.Newspaper),
    Matchups("Matchups", Icons.Filled.SportsFootball),
    Polls("Polls", Icons.Filled.BarChart),
    Members("Members", Icons.Filled.Groups),
    Settings("Settings", Icons.Filled.Settings),
}

@Composable
fun RootScreen() {
    var selected by remember { mutableStateOf(Tab.News) }

    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selected == tab,
                        onClick = { selected = tab },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { padding ->
        val inner = Modifier.padding(padding)
        when (selected) {
            Tab.News -> NewsScreen(inner)
            Tab.Matchups -> PlaceholderScreen("Matchups", inner)
            Tab.Polls -> PlaceholderScreen("Polls", inner)
            Tab.Members -> PlaceholderScreen("Members", inner)
            Tab.Settings -> PlaceholderScreen("Settings", inner)
        }
    }
}
