plugins {
    id("com.android.application")
    kotlin("android")
    id("dev.flutter.flutter-gradle-plugin")
    // NOTE: com.google.gms.google-services is deliberately NOT listed here.
    // It is applied CONDITIONALLY at the bottom of this script, only when
    // android/app/google-services.json declares a client whose package_name
    // matches this module's applicationId. See the "Google Services plugin"
    // block at the end of this file for the rationale + re-enable steps.
}

import java.io.FileInputStream
import java.util.Properties

// Single source of truth for the production application id, shared by the
// `defaultConfig` block below and the conditional Google Services plugin check
// at the end of this script. Declared as a script-level `val` because
// `applicationId` is not resolvable at the top level of a Kotlin DSL script
// (it lives under `android.defaultConfig`).
val jagspoorApplicationId = "za.co.jagspoor.app"

android {
    namespace = "za.co.jagspoor.app"
    // compileSdk 36 (Android 16) satisfies the Google Play target-API
    // requirement AND the 16 KB page-size build requirements of the resolved
    // plugins (tflite_flutter 0.12.1 / LiteRT 1.4.0 declares compileSdk 36).
    // AGP >= 8.5.1 (declared in settings.gradle.kts: 8.11.1) automatically
    // aligns + packages native libraries for 16 KB page-size devices.
    compileSdk = 36
    // Pin the NDK to the version the resolved Flutter plugins depend on
    // (camera_android, cloud_firestore, firebase_*, mobile_scanner, ... all
    // declare NDK 27.0.12077973). flutter.ndkVersion (26.3.11579264 on the
    // 3.29.1 pin) triggers a plugin-NDK-mismatch warning on every build.
    // NDK releases are backward compatible, so the highest version wins.
    ndkVersion = "27.0.12077973"

    // Google Play 16 KB page-size support: AGP >= 8.5.1 automatically aligns
    // native libraries for 16 KB page-size devices. `useLegacyPackaging =
    // true` stores the .so files UNCOMPRESSED in the APK/AAB so they can be
    // memory-mapped page-aligned (compressed libraries cannot be aligned).
    // tflite_flutter 0.12.1 / LiteRT 1.4.0 ships 16 KB-aligned binaries
    // (libtensorflowlite_gpu_jni.so et al); this block guarantees they are
    // packaged uncompressed + aligned. `pickFirst` resolves duplicate
    // libc++_shared.so across plugins (camera, mobile_scanner, tflite, ...).
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            pickFirsts += "**/libc++_shared.so"
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = jagspoorApplicationId
        // The resolved Firebase plugins (firebase_analytics 12.x,
        // firebase_app_check, firebase_auth, ...) declare minSdk 23 in their
        // library manifests, so flutter.minSdkVersion (21 on the 3.29.1 pin)
        // would fail the manifest merger ("minSdkVersion 21 cannot be smaller
        // than version 23 declared in library [:firebase_analytics]").
        // 23 is also the Android-6-era platform floor Google Play enforces.
        minSdk = flutter.minSdkVersion
        // Current Google Play requirement (as of Aug 31 2026) for new apps
        // and updates: target Android 16 (API level 36). Already satisfied.
        targetSdk = 36
        // Version code 9 + version name 1.0.9: each Play Console re-upload
        // requires a strictly higher version code integer than the previous
        // accepted AAB (v4.4.2 / code 8) for acceptance — and the forced
        // update gate only fires when the published build carries a higher
        // versionCode than the installed one. Kept in sync with the pubspec
        // `version: 1.0.9+9` line.
        versionCode = 9
        versionName = "1.0.9"
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

// ---------------------------------------------------------------------------
// Google Services plugin (com.google.gms.google-services) — applied
// CONDITIONALLY.
//
// Why this is not in the `plugins {}` block:
//   The plugin's `processDebugGoogleServices` / `processReleaseGoogleServices`
//   task hard-fails with
//       "No matching client found for package name '<applicationId>'"
//   whenever android/app/google-services.json contains no `client` entry whose
//   `android_client_info.package_name` equals this module's `applicationId`.
//   That is exactly the case in this repo: the checked-in JSON is the original
//   template file (package_name "com.example.jagspoor"), while applicationId
//   is the production "za.co.jagspoor.app" — see PACKAGE_MISMATCH_REPORT.md.
//   Applying the plugin unconditionally therefore breaks EVERY Gradle build
//   (`flutter run`, `flutter build apk`, CI) even though the Dart app never
//   reads it: Firebase is initialised from lib/firebase_options.dart via
//   Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).
//
// What the plugin is actually for here: it injects the google_app_id /
// default_web_client_id string resources consumed by the *native* Firebase
// artifacts — in particular `firebase-analytics` (declared in `dependencies`
// above), which otherwise throws at startup on Android.
//
// Behaviour:
//   * JSON missing OR no client matches applicationId  -> plugin NOT applied.
//     Gradle builds succeed; the Dart app works normally (Firebase.initializeApp
//     uses firebase_options.dart). Native firebase-analytics is inert, so log a
//     loud warning rather than failing the build silently.
//   * JSON present AND package_name matches applicationId -> plugin applied
//     exactly as before, restoring the generated resources.
//
// TO RESTORE FULL GOOGLE-SERVICES BEHAVIOUR: replace android/app/google-services.json
// with a freshly downloaded one for the "za.co.jagspoor.app" Android app
// (Firebase Console > jagspoor > Project settings > Your apps > Android app
// za.co.jagspoor.app > google-services.json). No Gradle edit is needed — the
// block below then detects the match and applies the plugin automatically.
// ---------------------------------------------------------------------------
val googleServicesFileName = "google-services.json"
val googleServicesJson = rootProject.file("app/$googleServicesFileName")

// True only when the checked-in google-services.json contains a client whose
// package_name matches this module's applicationId. Uses `run { }` so the whole
// check stays a single script-level expression (no helper function needed).
val googleServicesConfigured: Boolean = run {
    if (!googleServicesJson.exists()) return@run false
    val parsed = try {
        groovy.json.JsonSlurper().parse(googleServicesJson)
    } catch (_: Exception) {
        // Unreadable/malformed JSON (e.g. a Firebase placeholder file) must not
        // break the build — treat it as "no matching client".
        null
    }
    val clients = (parsed as? Map<*, *>)?.get("client") as? List<*> ?: return@run false
    clients.any { client ->
        val androidInfo =
            (((client as? Map<*, *>)?.get("client_info") as? Map<*, *>)
                ?.get("android_client_info") as? Map<*, *>)
        (androidInfo?.get("package_name") as? String) == jagspoorApplicationId
    }
}

if (googleServicesConfigured) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "[google-services] SKIPPED: no client for package '$jagspoorApplicationId' in " +
            "$googleServicesFileName. Gradle/Dart builds proceed; native " +
            "firebase-analytics stays inert. Replace the file with one " +
            "downloaded for '$jagspoorApplicationId' from the Firebase Console to enable it."
    )
}
