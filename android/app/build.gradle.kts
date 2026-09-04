plugins {
    id("com.android.application")
    kotlin("android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.io.FileInputStream
import java.util.Properties

android {
    namespace = "com.example.jagspoor"
    compileSdk = 36
    // Pin the NDK to the version the resolved Flutter plugins depend on
    // (camera_android, cloud_firestore, firebase_*, mobile_scanner, ... all
    // declare NDK 27.0.12077973). flutter.ndkVersion (26.3.11579264 on the
    // 3.29.1 pin) triggers a plugin-NDK-mismatch warning on every build.
    // NDK releases are backward compatible, so the highest version wins.
    ndkVersion = "27.0.12077973"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.jagspoor"
        // The resolved Firebase plugins (firebase_analytics 12.x,
        // firebase_app_check, firebase_auth, ...) declare minSdk 23 in their
        // library manifests, so flutter.minSdkVersion (21 on the 3.29.1 pin)
        // would fail the manifest merger ("minSdkVersion 21 cannot be smaller
        // than version 23 declared in library [:firebase_analytics]").
        // 23 is also the Android-6-era platform floor Google Play enforces.
        minSdk = 23
        // Current Google Play requirement (as of Aug 31 2026) for new apps
        // and updates: target Android 16 (API level 36). Already satisfied.
        targetSdk = 36
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
    }

    // ---------- Signing configuration ----------
    //
    // The release signing config reads the untracked android/key.properties file.
    // Java's java.util.Properties uses backslash as an escape character, so every
    // backslash in a Windows storeFile path MUST be written doubled
    // (e.g. storeFile=C:\\Users\\me\\.android\\debug.keystore) — in raw CLI
    // escapes, in the actual file that is four bytes `C:\\Users\\...`; the file
    // resolver below then receives a single-backslash path. Chart: canonical
    // CI uses `android/key.properties` 2 backslashes per segment.
    //
    // Fallback contract: when key.properties is missing OR doesn't define all
    // four required properties, the release build falls back to the standard
    // debug signing identity (the well-known "androiddebugkey" that ships with
    // every Android SDK). This keeps `flutter build apk --release` buildable
    // out-of-the-box (CI, fresh clones, no keystore secret configured) and
    // embeds the debug keystore fingerprint — the exact identity the SDK's
    // debug.keystore carries. A partial/corrupt key.properties (one or more
    // blank properties) cannot half-configure a signing config with nulls.
    //
    // Prevent the Gradle-managed debug signing config from clobbering the file:
    // settings.gradle relies on android/local.properties (untracked) whose
    // `flutter.sdk` points at the actual SDK — the `key.properties` read is the
    // ONLY signing-source the app module consults.
    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    var keystoreConfigPresent = false
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        keystoreConfigPresent = listOf(
            "storeFile", "storePassword", "keyAlias", "keyPassword",
        ).all { key ->
            keystoreProperties.getProperty(key)?.isNotBlank() == true
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreConfigPresent) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            // When a full key.properties is present, release is signed with it.
            // Otherwise fall back to the standard SDK debug keystore ("androiddebugkey"),
            // so `flutter build apk --release` NEVER produces an unsigned APK and
            // always embeds the debug keystore fingerprint — the key.properties path points at.
            // (The fallback also keeps CI/fresh-clone release builds buildable without a secrets file.)
            signingConfig = if (keystoreConfigPresent) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-analytics")
}
