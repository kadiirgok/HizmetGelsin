package com.berbergelsin.berbergelsin

import android.app.Application
import android.content.pm.ApplicationInfo
import android.util.Log

/**
 * Debug build'lerde Play Integrity yerine debug App Check token kullanır.
 * Sideloaded APK'larda Play Integrity çalışmadığı için bu zorunludur.
 * Firebase sınıflarına reflection ile erişir — böylece debug/release
 * classpath farklılıklarından etkilenmez.
 */
class BerbergelsinApp : Application() {
    override fun onCreate() {
        super.onCreate()

        val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebuggable) return

        try {
            // FirebaseApp.initializeApp(this)
            val firebaseAppClass = Class.forName("com.google.firebase.FirebaseApp")
            val initializeAppMethod = firebaseAppClass.getMethod("initializeApp", Application::class.java)
            initializeAppMethod.invoke(null, this)

            // FirebaseAppCheck.getInstance()
            val firebaseAppCheckClass = Class.forName("com.google.firebase.appcheck.FirebaseAppCheck")
            val getInstanceMethod = firebaseAppCheckClass.getMethod("getInstance")
            val appCheckInstance = getInstanceMethod.invoke(null)

            // DebugAppCheckProviderFactory.getInstance()
            val factoryClass = Class.forName(
                "com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory"
            )
            val factoryGetInstance = factoryClass.getMethod("getInstance")
            val factory = factoryGetInstance.invoke(null)

            // appCheckInstance.installAppCheckProviderFactory(factory)
            val AppCheckProviderFactoryClass = Class.forName(
                "com.google.firebase.appcheck.AppCheckProviderFactory"
            )
            val installMethod = firebaseAppCheckClass.getMethod(
                "installAppCheckProviderFactory", AppCheckProviderFactoryClass
            )
            installMethod.invoke(appCheckInstance, factory)

            Log.d("BerbergelsinApp", "Debug App Check provider kuruldu (reflection).")
        } catch (e: Exception) {
            Log.w("BerbergelsinApp", "Debug App Check kurulamadı: ${e.message}")
        }
    }
}
