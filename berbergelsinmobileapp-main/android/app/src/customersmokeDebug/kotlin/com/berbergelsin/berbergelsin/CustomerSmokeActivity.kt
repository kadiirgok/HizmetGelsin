package com.berbergelsin.berbergelsin

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Networkless activity used only by the combined customersmokeDebug source set.
 *
 * Deliberately does not invoke GeneratedPluginRegistrant: the UI fixture graph
 * needs no platform plugins, push provider, location provider or storage.
 */
class CustomerSmokeActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Intentionally empty.
    }
}
