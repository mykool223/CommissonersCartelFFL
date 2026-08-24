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
import com.commissionerscartel.app.feature.members.MemberEntry
import com.commissionerscartel.app.feature.members.MemberDetailScreen
import com.commissionerscartel.app.feature.members.MembersHost
import com.commissionerscartel.app.feature.news.NewsHost
import com.commissionerscartel.app.feature.matchups.MatchupsScreen
import com.commissionerscartel.app.feature.polls.PollsScreen
import com.commissionerscartel.app.feature.settings.SettingsScreen

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
    // A single detail destination rather than a nav graph: there is one, and
    // wiring navigation-compose for it would be more machinery than screen.
    var openMember by remember { mutableStateOf<MemberEntry?>(null) }

    openMember?.let { entry ->
        MemberDetailScreen(entry) { openMember = null }
        return
    }

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
            Tab.News -> NewsHost(inner)
            Tab.Matchups -> MatchupsScreen(inner)
            Tab.Polls -> PollsScreen(inner)
            Tab.Members -> MembersHost(inner, onOpen = { openMember = it })
            Tab.Settings -> SettingsScreen(inner)
        }
    }
}
