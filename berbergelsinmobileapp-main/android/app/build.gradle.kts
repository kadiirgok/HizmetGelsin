import java.io.FileInputStream
import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.berbergelsin.berbergelsin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            check(keystorePropertiesFile.exists()) {
                "Release signing için android/key.properties bulunamadı."
            }

            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.berbergelsin.berbergelsin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["deepLinkHost"] = "links.invalid"
        manifestPlaceholders["applicationName"] = "com.berbergelsin.berbergelsin.BerbergelsinApp"
    }

    flavorDimensions += "verification"
    productFlavors {
        create("production") {
            dimension = "verification"
            manifestPlaceholders["deepLinkHost"] = project.findProperty("DEEP_LINK_HOST")?.toString() ?: "links.invalid"
        }
        create("releasetest") {
            dimension = "verification"
            applicationIdSuffix = ".releasetest"
            // Device smoke must update the existing release-signed test package
            // without uninstalling it or losing its protected session data.
            signingConfig = signingConfigs.getByName("release")
            resValue("string", "app_name", "HizmetGelsin Release Test")
            manifestPlaceholders["deepLinkHost"] = project.findProperty("DEEP_LINK_TEST_HOST")?.toString() ?: "links.invalid"
        }
        create("customersmoke") {
            dimension = "verification"
            applicationIdSuffix = ".customersmoke"
            resValue("string", "app_name", "HizmetGelsin Customer Smoke")
            manifestPlaceholders["deepLinkHost"] = "links.invalid"
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

androidComponents {
    beforeVariants(
        selector()
            .withBuildType("release")
            .withFlavor("verification" to "customersmoke")
    ) { variantBuilder ->
        // The isolated fixture application is intentionally debug-only and
        // must never produce an uploadable release artifact.
        variantBuilder.enable = false
    }

    onVariants(
        selector()
            .withBuildType("debug")
            .withFlavor("verification" to "releasetest")
    ) { variant ->
        variant.signingConfig?.setConfig(android.signingConfigs.getByName("release"))
    }
}

val flutterTarget = providers.gradleProperty("target").orElse("lib/main.dart")
val rawDartDefines = providers.gradleProperty("dart-defines").orElse("")
val decodedDartDefines = rawDartDefines
    .map { encoded ->
        encoded.split(',')
            .filter { it.isNotBlank() }
            .mapNotNull {
                runCatching {
                    String(Base64.getDecoder().decode(it), Charsets.UTF_8)
                }.getOrNull()
            }
    }

gradle.taskGraph.whenReady {
    val requestedTasks = gradle.startParameter.taskNames.joinToString(" ")
    val customerSmokeBuild = requestedTasks.contains(
        "customersmoke",
        ignoreCase = true,
    )
    val customerSmokeMode =
        decodedDartDefines.get().contains("CUSTOMER_SMOKE_MODE=true") ||
            rawDartDefines.get().contains("Q1VTVE9NRVJfU01PS0VfTU9ERT10cnVl")
    val customerSmokeTarget = flutterTarget.get()
        .replace('\\', '/')
        .endsWith("lib/main_customersmoke.dart")

    if (customerSmokeBuild && (!customerSmokeMode || !customerSmokeTarget)) {
        throw GradleException(
            "customersmoke requires --target lib/main_customersmoke.dart " +
                "and --dart-define=CUSTOMER_SMOKE_MODE=true"
        )
    }
    if (!customerSmokeBuild && (customerSmokeMode || customerSmokeTarget)) {
        throw GradleException(
            "Customer smoke entrypoint/define is forbidden for production and releasetest variants."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("com.google.android.play:integrity:1.4.0")
    debugImplementation("com.google.firebase:firebase-appcheck-debug:18.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
