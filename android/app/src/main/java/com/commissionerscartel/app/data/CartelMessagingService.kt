package com.commissionerscartel.app.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.commissionerscartel.app.MainActivity
import com.commissionerscartel.app.R
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Receives pushes from the `push` edge function.
 *
 * Android delivers notification-payload messages itself while the app is in the
 * background; this class exists for the token callback and for showing
 * something sensible when the app is open.
 */
class CartelMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        Push.token = token
        // A token can arrive before anyone signs in. register() is a no-op
        // until there is a user id to store it against, and the sign-in flow
        // calls it again.
        CoroutineScope(Dispatchers.IO).launch { runCatching { Push.register() } }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val notification = message.notification ?: return
        val manager = NotificationManagerCompat.from(this)

        val channel = NotificationChannel(
            CHANNEL_ID,
            "League activity",
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        manager.createNotificationChannel(channel)

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            // Which tab to open, matching the iOS payload.
            putExtra("destination", message.data["destination"])
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val built = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(notification.title)
            .setContentText(notification.body)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        runCatching { manager.notify(notification.body.hashCode(), built) }
    }

    private companion object {
        const val CHANNEL_ID = "league_activity"
    }
}
