package com.commissionerscartel.app.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

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

    /**
     * Whether this account has a profile row. Only invited addresses get one,
     * and row level security hides everyone else's, so an empty result means
     * "not a member" rather than an error.
     */
    suspend fun profileExists(userId: String): Boolean =
        client.from("profiles").select { filter { eq("id", userId) } }
            .decodeList<kotlinx.serialization.json.JsonObject>()
            .isNotEmpty()

    suspend fun playerNews(limit: Long = 40): List<PlayerNews> =
        client.from("player_news").select {
            order("published_at", Order.DESCENDING)
            limit(limit)
        }.decodeList()

    /**
     * Every message you are party to. Row level security returns only those,
     * so there is no filter here — and could not usefully be one.
     */
    suspend fun directMessages(): List<DirectMessage> =
        client.from("direct_messages").select {
            order("created_at", Order.ASCENDING)
        }.decodeList()

    suspend fun sendDirectMessage(recipientId: String, body: String) {
        client.from("direct_messages").insert(
            buildJsonObject {
                put("recipient_id", recipientId)
                put("body", body)
            }
        )
    }

    /** Display names for everyone who has signed in, for conversation titles. */
    suspend fun profiles(): Map<String, String> =
        client.from("profiles").select { }
            .decodeList<ProfileRow>()
            .associate { it.id to (it.display_name ?: "Someone") }

    suspend fun reactions(): List<MessageReaction> =
        client.from("message_reactions").select().decodeList()

    /** user_id is defaulted from the session in Postgres, not sent by us. */
    suspend fun addReaction(messageId: String, emoji: String) {
        client.from("message_reactions").insert(
            buildJsonObject {
                put("message_id", messageId)
                put("emoji", emoji)
            }
        )
    }

    /** No user filter: the delete policy already restricts this to your rows. */
    suspend fun removeReaction(messageId: String, emoji: String) {
        client.from("message_reactions").delete {
            filter {
                eq("message_id", messageId)
                eq("emoji", emoji)
            }
        }
    }

    @Serializable
    private data class ProfileRow(val id: String, val display_name: String? = null)

    /** The trophy case. Empty until the first week is in the books. */
    suspend fun trophies(season: Int): List<Trophy> =
        client.from("trophies").select {
            filter { eq("season", season) }
            order("awarded_at", Order.DESCENDING)
        }.decodeList()

    /** Adds, drops, waivers and trades, collected from ESPN hourly. */
    suspend fun activity(season: Int, limit: Long = 100): List<LeagueActivity> =
        client.from("league_activity").select {
            filter { eq("season", season) }
            order("occurred_at", Order.DESCENDING)
            limit(limit)
        }.decodeList()

    /** The league thread. Members only — RLS returns nothing to anyone else. */
    suspend fun messages(limit: Long = 200): List<LeagueMessage> =
        client.from("league_messages").select {
            order("created_at", Order.ASCENDING)
            limit(limit)
        }.decodeList()

    /**
     * Posts to the thread. The author is taken from the session inside the
     * function, so the client cannot post as somebody else.
     */
    suspend fun postMessage(body: String) {
        client.postgrest.rpc("post_league_message", buildJsonObject { put("p_body", body) })
    }

    suspend fun deleteMessage(id: String) {
        client.from("league_messages").delete { filter { eq("id", id) } }
    }

    /**
     * Polls with vote counts, via a security-definer function. Reading the vote
     * table directly is deliberately forbidden — who voted for what is private,
     * and only the totals come back.
     */
    suspend fun polls(season: Int): List<Poll> =
        client.postgrest.rpc(
            "polls_with_results",
            buildJsonObject { put("p_season", season) },
        ).decodeList()

    suspend fun castVote(pollId: String, optionId: String) {
        client.postgrest.rpc(
            "cast_vote",
            buildJsonObject {
                put("p_poll_id", pollId)
                put("p_option_id", optionId)
            },
        )
    }

    suspend fun createPoll(question: String, options: List<String>, closesAt: String?) {
        client.postgrest.rpc(
            "create_poll",
            buildJsonObject {
                put("p_question", question)
                putJsonArray("p_options") { options.forEach { add(it) } }
                if (closesAt != null) put("p_closes_at", closesAt) else put("p_closes_at", JsonNull)
            },
        )
    }

    /** Ties this account to an ESPN team, so posts carry the right name. */
    suspend fun claimEspnTeam(swid: String) {
        client.postgrest.rpc("claim_espn_team", buildJsonObject { put("p_swid", swid) })
    }

    suspend fun claimedSwid(userId: String): String? =
        client.from("profiles").select { filter { eq("id", userId) } }
            .decodeList<kotlinx.serialization.json.JsonObject>()
            .firstOrNull()
            ?.get("espn_swid")
            ?.let { if (it is kotlinx.serialization.json.JsonNull) null else it.toString().trim('"') }

    suspend fun teamBios(season: Int): Map<Int, TeamBio> =
        client.from("team_bios").select {
            filter { eq("season", season) }
        }.decodeList<TeamBio>().associateBy { it.teamId }
}
