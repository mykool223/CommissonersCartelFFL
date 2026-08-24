package com.commissionerscartel.app.feature.members

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.commissionerscartel.app.ui.SectionPicker

enum class MembersSection(val label: String) {
    Roster("Roster"),
    Thread("League thread"),
    Trophies("Trophy case"),
}

@Composable
fun MembersHost(modifier: Modifier = Modifier, onOpen: (MemberEntry) -> Unit) {
    var section by remember { mutableStateOf(MembersSection.Roster) }

    Column(modifier.fillMaxSize()) {
        SectionPicker(
            scrollable = true,
            sections = MembersSection.entries,
            selected = section,
            label = { it.label },
            onSelect = { section = it },
        )
        when (section) {
            MembersSection.Roster -> MembersScreen(onOpen = onOpen)
            MembersSection.Thread -> LeagueThreadScreen()
            MembersSection.Trophies -> TrophyCaseScreen()
        }
    }
}
