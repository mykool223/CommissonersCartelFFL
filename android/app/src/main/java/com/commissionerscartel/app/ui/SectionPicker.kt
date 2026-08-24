package com.commissionerscartel.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * The equivalent of the iOS dropdown under the navigation title. Chips rather
 * than a menu because Android has the room and one tap beats two.
 */
@Composable
fun <T> SectionPicker(
    sections: List<T>,
    selected: T,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        sections.forEach { section ->
            FilterChip(
                selected = section == selected,
                onClick = { onSelect(section) },
                label = { Text(label(section)) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = CartelGold.copy(alpha = 0.2f),
                ),
            )
        }
    }
}
