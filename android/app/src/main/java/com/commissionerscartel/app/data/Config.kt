package com.commissionerscartel.app.data

import com.commissionerscartel.app.BuildConfig

/**
 * Build-time configuration, read from `secrets.properties` at the root of the
 * Android project. Mirrors `AppConfiguration` on iOS, including the rule that
 * absent configuration is not an error: the app falls back to sample data so a
 * fresh clone runs.
 */
object Config {
    val supabaseHost: String = BuildConfig.SUPABASE_HOST
    val supabaseAnonKey: String = BuildConfig.SUPABASE_ANON_KEY
    val espnLeagueId: String = BuildConfig.ESPN_LEAGUE_ID

    val hasSupabase: Boolean
        get() = supabaseHost.isNotBlank() && supabaseAnonKey.isNotBlank()

    val supabaseUrl: String
        get() = "https://$supabaseHost"

    /**
     * The fantasy season. ESPN rolls over in the spring, so anything before
     * June still belongs to the previous season — the same rule as
     * `Season.current()` on iOS, and it has to agree or the two clients show
     * different content.
     */
    fun currentSeason(now: java.time.LocalDate = java.time.LocalDate.now()): Int =
        if (now.monthValue >= 6) now.year else now.year - 1
}
