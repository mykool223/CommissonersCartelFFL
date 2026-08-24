package com.commissionerscartel.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import android.util.Log
import com.commissionerscartel.app.BuildConfig
import com.google.firebase.messaging.FirebaseMessaging
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resumeWithException
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

/**
 * No default values, deliberately.
 *
 * kotlinx.serialization omits a property whose value equals its default, so a
 * default of "android" was never sent — and the column's own default is 'ios',
 * because every row predated Android. The device registered itself as an
 * iPhone, Apple rejected the Firebase token, and it was pruned as dead.
 */
@Serializable
private data class DeviceRow(
    val token: String,
    @SerialName("user_id") val userId: String,
    val platform: String,
    /** Meaningless on Android; the column exists for APNs, which needs it. */
    val environment: String,
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

    /**
     * Fetches this device's Firebase token if it is not already known.
     *
     * [CartelMessagingService.onNewToken] only fires on first install and on
     * rotation, so relying on it alone means a member who signs in on any
     * later launch is never registered and silently receives nothing.
     */
    suspend fun ensureToken(): String? {
        token?.let { return it }
        val fetched = runCatching {
            suspendCancellableCoroutine { continuation ->
                FirebaseMessaging.getInstance().token
                    .addOnSuccessListener { continuation.resume(it) {} }
                    .addOnFailureListener { continuation.resumeWithException(it) }
            }
        }
            // Logged in release too. Silently returning null here is what made
            // a device that never registers look identical to one that has
            // notifications switched off.
            .onFailure { Log.w(TAG, "Could not get an FCM token", it) }
            .getOrNull()
        if (fetched != null) {
            token = fetched
            if (BuildConfig.DEBUG) Log.d(TAG, "FCM token: $fetched")
        }
        return fetched
    }

    suspend fun register() {
        val token = ensureToken()
        if (token == null) {
            Log.w(TAG, "Not registering: no FCM token")
            return
        }
        val userId = Session.userId
        if (userId == null) {
            Log.w(TAG, "Not registering: not signed in")
            return
        }
        runCatching {
            Supabase.client.from("device_tokens")
                .upsert(
                    DeviceRow(
                        token = token,
                        userId = userId,
                        platform = "android",
                        environment = "production",
                    )
                ) { onConflict = "token" }
        }
            .onSuccess { Log.i(TAG, "Registered this device for notifications") }
            .onFailure { Log.w(TAG, "Could not register device", it) }
    }

    private const val TAG = "CartelPush"

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
