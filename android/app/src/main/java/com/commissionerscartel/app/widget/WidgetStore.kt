package com.commissionerscartel.app.widget

import android.content.Context

/**
 * The sliver of state the widget needs from the app.
 *
 * A widget has no session, so it cannot work out which team is yours. The app
 * writes the answer here and the widget fetches everything else itself.
 *
 * Deliberately tiny — an id and a name, no scores. A cached score goes stale
 * silently, which is worse than one the widget fetched for itself.
 */
object WidgetStore {
    private const val FILE = "cartel_widget"
    private const val TEAM_ID = "claimed_team_id"
    private const val TEAM_NAME = "claimed_team_name"

    fun claimedTeamId(context: Context): Int? {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val value = prefs.getInt(TEAM_ID, -1)
        return value.takeIf { it > 0 }
    }

    fun setClaimedTeam(context: Context, id: Int, name: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putInt(TEAM_ID, id)
            .putString(TEAM_NAME, name)
            .apply()
    }
}
