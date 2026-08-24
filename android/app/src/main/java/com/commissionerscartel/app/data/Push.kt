package com.commissionerscartel.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest

/** What a member wants to hear about. Everything on unless they say otherwise. */
data class NotificationPreferences(
    val messages: Boolean = true,
    val news: Boolean = true,
    val polls: Boolean = true,
)

@Serializable
private data class PreferencesRow(
    val messages: Boolean = true,
    val news: Boolean = true,
    val polls: Boolean = true,
)

@Serializable
private data class DeviceRow(
    val token: String,
    @SerialName("user_id") val userId: String,
    val platform: String = "android",
    // Meaningless on Android — the column exists for APNs — but the check
    // constraint requires one of the two values.
    val environment: String = "production",
)

/**
 * Device registration and notification preferences.
 *
 * Sending happens server-side: a database trigger fires when a message, news
 * post or poll is inserted. The app's only jobs are handing over its Firebase
 * token and remembering which kinds the member wants.
 */
object Push {
    /**
     * The Firebase token for this device, or null when Firebase is not
     * configured in this build. Set by [FirebaseTokenProvider]; kept as a
     * plain reference so the rest of the app does not depend on Firebase
     * being present.
     */
    @Volatile
    var token: String? = null

    suspend fun register() {
        val token = token ?: return
        val userId = Session.userId ?: return
        Supabase.client.from("device_tokens")
            .upsert(DeviceRow(token = token, userId = userId)) { onConflict = "token" }
    }

    suspend fun unregister() {
        val token = token ?: return
        Supabase.client.from("device_tokens").delete { filter { eq("token", token) } }
    }

    suspend fun preferences(): NotificationPreferences {
        val userId = Session.userId ?: return NotificationPreferences()
        val rows = Supabase.client.from("notification_preferences")
            .select { filter { eq("user_id", userId) } }
            .decodeList<PreferencesRow>()
        // No row means the member has never opened Settings, which must not
        // read as "wants silence".
        val row = rows.firstOrNull() ?: return NotificationPreferences()
        return NotificationPreferences(row.messages, row.news, row.polls)
    }

    suspend fun setPreferences(preferences: NotificationPreferences) {
        val userId = Session.userId ?: return
        Supabase.client.from("notification_preferences")
            .upsert(
                buildJsonObject {
                    put("user_id", userId)
                    put("messages", preferences.messages)
                    put("news", preferences.news)
                    put("polls", preferences.polls)
                }
            ) { onConflict = "user_id" }
    }
}
