package com.commissionerscartel.app.data

/**
 * Logos the league supplies for teams that never uploaded one to ESPN.
 *
 * Eight of the twelve are still on ESPN's stock art, which is SVG and does not
 * decode here, so those teams arrive with no logo at all and the members list
 * becomes a wall of identical crests — the one thing a logo exists to prevent.
 *
 * Held here rather than threaded through five call sites: every screen that
 * draws a team reads the same mapper, so filling the gap there means none of
 * them need to know. A team with its own ESPN logo is never overridden.
 */
object TeamLogos {
    @Volatile
    private var overrides: Map<Int, String> = emptyMap()

    /** Empty until this runs, which costs a picture rather than a screen. */
    suspend fun refresh(season: Int = Config.currentSeason()) {
        overrides = runCatching {
            Supabase.teamBios(season)
                .mapNotNull { (id, bio) -> bio.logoUrl?.let { id to it } }
                .toMap()
        }.getOrDefault(overrides)
    }

    fun forTeam(id: Int): String? = overrides[id]
}
