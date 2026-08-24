package com.commissionerscartel.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** The gold from the league crest, matching `Color.brand` on iOS. */
val CartelGold = Color(0xFF9A7B2F)
private val CartelBlack = Color(0xFF0B0B0B)

private val Light = lightColorScheme(
    primary = CartelGold,
    onPrimary = Color.White,
    secondary = CartelGold,
)

private val Dark = darkColorScheme(
    primary = CartelGold,
    onPrimary = Color.Black,
    secondary = CartelGold,
    background = CartelBlack,
    surface = Color(0xFF161616),
)

@Composable
fun CartelTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) Dark else Light,
        content = content,
    )
}
