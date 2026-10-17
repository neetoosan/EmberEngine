plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Game exports pass their identity, icon and signing key in environment
// variables (see GameExporter.exportAndroid); without them this builds the
// Ember Engine player itself, debug-signed.
val emberKeystore: String? = System.getenv("EMBER_KEYSTORE")
val emberIconRes: String? = System.getenv("EMBER_ICON_RES")

android {
    namespace = "com.emberengine.ember_engine"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Game exports set their own id and name (see GameExporter.exportAndroid),
        // so several exported games can be installed side by side.
        applicationId = System.getenv("EMBER_APP_ID") ?: "com.emberengine.ember_engine"
        manifestPlaceholders["emberAppName"] = System.getenv("EMBER_APP_NAME") ?: "Ember Engine"
        // A game's own icon comes from an extra resource folder as mipmap/ember_game_icon
        manifestPlaceholders["emberIcon"] = if (emberIconRes != null) "@mipmap/ember_game_icon" else "@mipmap/ic_launcher"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (emberIconRes != null) {
        sourceSets.getByName("main").res.srcDir(emberIconRes)
    }

    signingConfigs {
        if (emberKeystore != null) {
            create("ember") {
                storeFile = file(emberKeystore)
                storePassword = System.getenv("EMBER_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("EMBER_KEY_ALIAS")
                keyPassword = System.getenv("EMBER_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // The game's upload key when exporting for Google Play; the debug key otherwise
            signingConfig = signingConfigs.getByName(if (emberKeystore != null) "ember" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
