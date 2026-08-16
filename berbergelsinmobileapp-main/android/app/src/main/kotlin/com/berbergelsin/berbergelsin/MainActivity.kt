package com.berbergelsin.berbergelsin

import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.berbergelsin/online_service"
        private var channelInstance: MethodChannel? = null

        fun notifyOnlineToggle(online: Boolean) {
            channelInstance?.invokeMethod("onOnlineToggle", online)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channelInstance?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    val pending = call.argument<Int>("pendingCount") ?: 0
                    val earning = call.argument<Double>("todayEarning") ?: 0.0
                    OnlineForegroundService.start(this, pending, earning)
                    result.success(true)
                }
                "stopForeground" -> {
                    OnlineForegroundService.stop(this)
                    result.success(true)
                }
                "updateForeground" -> {
                    val pending = call.argument<Int>("pendingCount") ?: 0
                    val earning = call.argument<Double>("todayEarning") ?: 0.0
                    OnlineForegroundService.update(pending, earning)
                    result.success(true)
                }
                "isForegroundActive" -> {
                    result.success(OnlineForegroundService.isActive())
                }
                "consumeToggle" -> {
                    val pending = OnlineToggleReceiver.pendingToggle
                    val online = OnlineToggleReceiver.targetOnline
                    OnlineToggleReceiver.pendingToggle = false
                    result.success(if (pending) online else null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Bildirimden gelen toggle varsa Flutter'a ilet
        if (OnlineToggleReceiver.pendingToggle) {
            notifyOnlineToggle(OnlineToggleReceiver.targetOnline)
            OnlineToggleReceiver.pendingToggle = false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setOnExitAnimationListener { provider ->
            val splashView = provider.view as ViewGroup
            val logoSize = (240 * resources.displayMetrics.density).toInt()
            val logo = ImageView(this).apply {
                setImageResource(R.drawable.splash_logo)
                scaleType = ImageView.ScaleType.FIT_CENTER
                scaleX = 0.92f
                scaleY = 0.92f
            }
            splashView.addView(
                logo,
                FrameLayout.LayoutParams(logoSize, logoSize, Gravity.CENTER),
            )
            logo.animate()
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(180L)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction { provider.remove() }
                .start()
        }
        super.onCreate(savedInstanceState)
    }
}
