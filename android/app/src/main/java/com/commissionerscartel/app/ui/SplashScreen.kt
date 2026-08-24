package com.commissionerscartel.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.commissionerscartel.app.R
import kotlinx.coroutines.delay

/**
 * Holds the crest over the app briefly, then cross-fades — the same opening as
 * iOS, so the two feel like one app.
 *
 * The delay is a floor rather than a wait: the tabs are loading underneath, so
 * by the time it clears the News feed usually has content.
 */
@Composable
fun SplashGate(content: @Composable () -> Unit) {
    var showing by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        delay(1_400)
        showing = false
    }

    Box(Modifier.fillMaxSize()) {
        content()

        AnimatedVisibility(visible = showing, exit = fadeOut()) {
            Box(
                Modifier.fillMaxSize().background(Color.Black),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painter = painterResource(R.mipmap.ic_launcher),
                    contentDescription = null,
                    modifier = Modifier.size(220.dp),
                )
            }
        }
    }
}
