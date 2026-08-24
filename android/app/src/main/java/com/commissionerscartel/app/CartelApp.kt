package com.commissionerscartel.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.core.app.NotificationManagerCompat
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import com.commissionerscartel.app.data.Config
import com.commissionerscartel.app.data.Push
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

/**
 * Exists to teach the image loader about the ESPN proxy.
 *
 * Uploaded team logos live on a host that requires the league cookies, so they
 * come back through the `espn-proxy` edge function — which requires the
 * Supabase key. Coil sends no such header on its own, so every uploaded logo
 * came back 401 and fell silently to the default avatar: the failure looked
 * exactly like "this team has no logo".
 */
class CartelApp : Application(), SingletonImageLoader.Factory {

    override fun onCreate() {
        super.onCreate()

        // Declared up front: a message that arrives while the app is in the
        // background is posted by the system, which will not create it for us.
        NotificationManagerCompat.from(this).createNotificationChannel(
            NotificationChannel(
                "league_activity",
                "League activity",
                NotificationManager.IMPORTANCE_DEFAULT,
            )
        )
        // Fetch the Firebase token up front. Asking for it needs no account,
        // and having it in hand means signing in registers the device
        // immediately rather than on the launch after.
        CoroutineScope(Dispatchers.IO).launch { runCatching { Push.ensureToken() } }
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader {
        val client = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request()
                // Only our own project gets the key. It must not be attached
                // to ESPN's public CDN or anywhere else an image may live.
                val isProxy = Config.hasSupabase &&
                    request.url.host.equals(Config.supabaseHost, ignoreCase = true)
                chain.proceed(
                    if (!isProxy) {
                        request
                    } else {
                        request.newBuilder()
                            .header("Authorization", "Bearer ${Config.supabaseAnonKey}")
                            .header("apikey", Config.supabaseAnonKey)
                            .build()
                    }
                )
            }
            .build()

        return ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { client })) }
            .build()
    }
}
