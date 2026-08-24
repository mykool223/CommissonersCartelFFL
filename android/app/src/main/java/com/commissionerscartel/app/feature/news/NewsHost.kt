package com.commissionerscartel.app.feature.news

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.commissionerscartel.app.feature.NewsScreen
import com.commissionerscartel.app.ui.SectionPicker

enum class NewsSection(val label: String) {
    League("League news"),
    Players("Player news"),
}

/** The News tab, with the two feeds the iOS dropdown offers. */
@Composable
fun NewsHost(modifier: Modifier = Modifier) {
    var section by remember { mutableStateOf(NewsSection.League) }

    Column(modifier.fillMaxSize()) {
        SectionPicker(
            sections = NewsSection.entries,
            selected = section,
            label = { it.label },
            onSelect = { section = it },
        )
        when (section) {
            NewsSection.League -> NewsScreen()
            NewsSection.Players -> PlayerNewsScreen()
        }
    }
}
