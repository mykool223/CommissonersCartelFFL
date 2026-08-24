package com.commissionerscartel.app.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order

/**
 * The league's Supabase project.
 *
 * Row level security is enforced in Postgres, so this client is not trusted
 * with anything: the anon key shipped in the app can read league news and team
 * bios and nothing else until someone signs in.
 */
object Supabase {
    val client: SupabaseClient by lazy {
        createSupabaseClient(
            supabaseUrl = Config.supabaseUrl,
            supabaseKey = Config.supabaseAnonKey,
        ) {
            install(Postgrest)
            install(Auth)
        }
    }

    suspend fun newsPosts(season: Int, limit: Long = 50): List<NewsPost> =
        client.from("news_posts").select {
            filter { eq("season", season) }
            order("published_at", Order.DESCENDING)
            limit(limit)
        }.decodeList()

    suspend fun teamBios(season: Int): Map<Int, TeamBio> =
        client.from("team_bios").select {
            filter { eq("season", season) }
        }.decodeList<TeamBio>().associateBy { it.teamId }
}
