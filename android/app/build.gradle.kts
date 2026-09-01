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

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
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
