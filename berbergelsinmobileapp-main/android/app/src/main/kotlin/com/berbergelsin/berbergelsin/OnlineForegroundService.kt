package com.berbergelsin.berbergelsin

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Çevrimiçi durumda kalıcı bildirim gösteren foreground service.
 * Standard notification API — tüm cihaz ve emülatörlerde çalışır.
 */
class OnlineForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "hizmetgelsin_online"
        const val NOTIFICATION_ID = 2001
        const val ACTION_TOGGLE_OFFLINE = "com.berbergelsin.TOGGLE_OFFLINE"

        private var instance: OnlineForegroundService? = null
        private var pendingCount = 0
        private var todayEarning = 0.0

        fun isActive(): Boolean = instance != null

        fun start(context: Context, pendingReqs: Int = 0, earning: Double = 0.0) {
            pendingCount = pendingReqs
            todayEarning = earning
            val intent = Intent(context, OnlineForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OnlineForegroundService::class.java))
        }

        fun update(pendingReqs: Int, earning: Double) {
            pendingCount = pendingReqs
            todayEarning = earning
            instance?.showNotification()
        }
    }

    private lateinit var receiver: BroadcastReceiver

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        receiver = createReceiver()
        registerReceiver(receiver, IntentFilter(ACTION_TOGGLE_OFFLINE))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        showNotification()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        try { unregisterReceiver(receiver) } catch (_: Exception) {}
        instance = null
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Çevrimiçi Durum",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "İşletme çevrimiçi olduğunda gösterilir"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createReceiver(): BroadcastReceiver {
        return object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_TOGGLE_OFFLINE) {
                    val toggleIntent = Intent("com.berbergelsin.FLUTTER_ONLINE_TOGGLE")
                    toggleIntent.putExtra("online", false)
                    context?.sendBroadcast(toggleIntent)
                    stop(context!!)
                }
            }
        }
    }

    fun showNotification() {
        // Dinamik alt metin
        val subtitle = buildString {
            append("Çevrimiçi — yeni taleplere açıksınız")
            if (pendingCount > 0) {
                append("\n$pendingCount talep bekliyor")
            }
            if (todayEarning > 0) {
                append(" · Bugün ${todayEarning.toInt()} TL")
            }
        }

        // Toggle action
        val toggleIntent = Intent(ACTION_TOGGLE_OFFLINE)
        val togglePI = PendingIntent.getBroadcast(
            this, 0, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Open app action
        val appIntent = packageManager.getLaunchIntentForPackage(packageName)
        val appPI = PendingIntent.getActivity(
            this, 1, appIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Large icon — app launcher icon'ı
        val largeIcon = try {
            BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        } catch (_: Exception) {
            null
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("HizmetGelsin")
            .setContentText("Çevrimiçi — yeni taleplere açıksınız")
            .setStyle(NotificationCompat.BigTextStyle().bigText(subtitle))
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(0xFF111111.toInt())
            .setContentIntent(appPI)
            .addAction(0, "Çevrimdışı Yap", togglePI)
            .apply {
                if (largeIcon != null) setLargeIcon(largeIcon)
            }
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }
}
