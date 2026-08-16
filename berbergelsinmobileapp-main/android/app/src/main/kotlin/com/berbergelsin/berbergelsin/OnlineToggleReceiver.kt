package com.berbergelsin.berbergelsin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Bildirimdeki "Çevrimdışı Yap" butonuna basılınca tetiklenir.
 * Servisi durdurup Flutter tarafına event iletir.
 */
class OnlineToggleReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "OnlineToggleReceiver"
        var pendingToggle: Boolean = false
        var targetOnline: Boolean = true
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == OnlineForegroundService.ACTION_TOGGLE_OFFLINE) {
            Log.d(TAG, "Toggle offline requested from notification")
            // Servisi durdur
            context?.let { OnlineForegroundService.stop(it) }
            // Flutter tarafına bildir (MainActivity varsa işler)
            pendingToggle = true
            targetOnline = false
        }
    }
}
