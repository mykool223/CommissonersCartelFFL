package com.commissionerscartel.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color
import com.commissionerscartel.app.data.AppGraph
import com.commissionerscartel.app.data.EspnMapper
import com.commissionerscartel.app.data.MatchupStatus
import java.util.Locale

/**
 * This week's fixture, on the home screen.
 *
 * Fetches its own data rather than reading something the app cached: a stale
 * score shown on Tuesday is worse than showing nothing. Which team is yours
 * comes from [WidgetStore], written by the app — a widget has no session.
 */
class MatchupWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = load(context)
        provideContent {
            GlanceTheme {
                Body(snapshot)
            }
        }
    }

    private suspend fun load(context: Context): Snapshot {
        val teamId = WidgetStore.claimedTeamId(context)
            ?: return Snapshot(message = "Open the Cartel and pick your team.")

        return runCatching {
            val payload = AppGraph.espn.payload()
            val league = EspnMapper.league(payload, AppGraph.season)
            val teams = EspnMapper.teams(payload, AppGraph.espn).associateBy { it.id }
            val fixture = EspnMapper.matchups(payload, league.currentWeek)
                .firstOrNull { it.homeTeamId == teamId || it.awayTeamId == teamId }
                ?: return@runCatching Snapshot(
                    week = league.currentWeek,
                    message = "No fixture this week.",
                )

            val isHome = fixture.homeTeamId == teamId
            val opponentId = if (isHome) fixture.awayTeamId else fixture.homeTeamId
                ?: return@runCatching Snapshot(week = league.currentWeek, message = "Bye week.")

            val mine = if (isHome) fixture.homeScore else fixture.awayScore
            val theirs = if (isHome) fixture.awayScore else fixture.homeScore

            Snapshot(
                week = league.currentWeek,
                myName = teams[teamId]?.name ?: "You",
                myPoints = mine,
                theirName = opponentId?.let { teams[it]?.name } ?: "TBD",
                theirPoints = theirs,
                message = if (fixture.status == MatchupStatus.Scheduled) "Not started" else null,
            )
        }.getOrElse { Snapshot(message = "Couldn't reach the league.") }
    }

    data class Snapshot(
        val week: Int = 0,
        val myName: String? = null,
        val myPoints: Double = 0.0,
        val theirName: String? = null,
        val theirPoints: Double = 0.0,
        val message: String? = null,
    )
}

private val Gold = Color(0xFF9A7B2F)
private val Win = Color(0xFF1E8E3E)

@Composable
private fun Body(snapshot: MatchupWidget.Snapshot) {
    Column(
        GlanceModifier.fillMaxSize().background(GlanceTheme.colors.widgetBackground).padding(12.dp),
    ) {
        if (snapshot.week > 0) {
            Text(
                "WEEK ${snapshot.week}",
                style = TextStyle(
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = ColorProvider(Gold),
                ),
            )
            Spacer(GlanceModifier.height(6.dp))
        }

        if (snapshot.myName != null && snapshot.theirName != null) {
            Side(snapshot.myName, snapshot.myPoints, snapshot.myPoints > snapshot.theirPoints)
            Spacer(GlanceModifier.height(4.dp))
            Side(snapshot.theirName, snapshot.theirPoints, snapshot.theirPoints > snapshot.myPoints)
            snapshot.message?.let {
                Spacer(GlanceModifier.height(6.dp))
                Text(it, style = TextStyle(fontSize = 11.sp, color = GlanceTheme.colors.onSurfaceVariant))
            }
        } else {
            Text(
                snapshot.message ?: "Nothing to show.",
                style = TextStyle(fontSize = 12.sp, color = GlanceTheme.colors.onSurfaceVariant),
            )
        }
    }
}

@Composable
private fun Side(name: String, points: Double, leading: Boolean) {
    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            name,
            maxLines = 1,
            modifier = GlanceModifier.defaultWeight(),
            style = TextStyle(fontSize = 13.sp, color = GlanceTheme.colors.onSurface),
        )
        Text(
            String.format(Locale.US, "%.1f", points),
            style = TextStyle(
                fontSize = 15.sp,
                fontWeight = if (leading) FontWeight.Bold else FontWeight.Normal,
                color = if (leading) ColorProvider(Win) else GlanceTheme.colors.onSurface,
            ),
        )
    }
}

class MatchupWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MatchupWidget()
}
