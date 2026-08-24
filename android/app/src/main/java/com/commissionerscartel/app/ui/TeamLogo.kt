package com.commissionerscartel.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.commissionerscartel.app.R

/**
 * A team's crest, falling back to the league avatar.
 *
 * The fallback is not only for teams with no logo: most of ESPN's stock crests
 * are SVG, which the image loader cannot decode, so those arrive here as null
 * by design. Checked on every load, so a member who uploads one later sees it
 * without anything being cleared.
 */
@Composable
fun TeamLogo(url: String?, size: Dp = 44.dp, modifier: Modifier = Modifier) {
    val shape = CircleShape
    if (url.isNullOrBlank()) {
        androidx.compose.foundation.Image(
            painter = painterResource(R.drawable.default_avatar),
            contentDescription = null,
            modifier = modifier.size(size).clip(shape),
            contentScale = ContentScale.Crop,
        )
    } else {
        AsyncImage(
            model = url,
            contentDescription = null,
            modifier = modifier.size(size).clip(shape).background(CartelGold.copy(alpha = 0.08f)),
            contentScale = ContentScale.Crop,
            placeholder = painterResource(R.drawable.default_avatar),
            error = painterResource(R.drawable.default_avatar),
        )
    }
}
