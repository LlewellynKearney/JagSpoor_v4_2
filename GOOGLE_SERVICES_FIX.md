# GOOGLE_SERVICES_FIX.md — google-services.json package mismatch

## Status: MISMATCH CONFIRMED — action required in a credentialed Firebase environment

`android/app/google-services.json` is registered for the Flutter template
package id, **not** the production application id.

| Location | Expected | Actual |
| --- | --- | --- |
| `android/app/build.gradle.kts` `namespace` / `applicationId` | `za.co.jagspoor.app` | `za.co.jagspoor.app` ✅ |
| `android/app/google-services.json` `client_info.android_client_info.package_name` | `za.co.jagspoor.app` | `com.example.jagspoor` ❌ |
| `android/app/google-services.json` oauth client `android_info.package_name` (×4) | `za.co.jagspoor.app` | `com.example.jagspoor` ❌ |

`project_id` is `jagspoor` (correct project, wrong Android package
registration).

## Impact

- The Flutter Android Gradle plugin's `com.google.gms.google-services` plugin
  compares the app's `applicationId` against the `package_name` in
  `google-services.json`. On a mismatch the plugin **fails the build**
  (`No matching client found for package name 'za.co.jagspoor.app'`).
- Danger-monkey / `firebase-analytics` native init is inert until the
  registration matches.
- The bundled `default_web_client_id` (used by Google Sign-In) is generated
  from this file, so Google Sign-In can fail.

Dart-side Firebase (initialised via `lib/firebase_options.dart`, which matches
by app id, not package name) is **unaffected** — only the native plugin +
Analytics + the auto-generated web client id are impacted.

> NOTE: per the task instruction, this file was **not** overwritten with
> fabricated content. The real `google-services.json` must be downloaded from
> the Firebase Console. This document is the report.

## Fix — regenerate from the Firebase Console

1. Sign in to the Firebase Console for project **jagspoor**:
   <https://console.firebase.google.com/project/jagspoor/settings/general>
2. Under **Your apps**, if there is no Android app with the package
   `za.co.jagspoor.app`, click **Add app → Android** and register it with:
   - Android package name: `za.co.jagspoor.app`
   - App nickname: `JagSpoor (Android)`
   - Debug signing certificate SHA-1 / SHA-256 (see step 3)
3. Add the signing certificate fingerprints for **every** keystore you ship
   with (debug keystore for local builds, the release/upload keystore for
   Play, and the Play App Signing key if enrolled):
   - Local debug keystore:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
   - Release keystore:
     `keytool -list -v -keystore <path/to/upload-keystore.jks> -alias <alias>`
   - Play App Signing: copy the SHA-1 / SHA-256 from
     Play Console → Release → Setup → App integrity.
4. Download `google-services.json` (the file contains **all** registered
   Android apps for the project, so downloading once covers
   `com.example.jagspoor` and `za.co.jagspoor.app`) and replace
   `android/app/google-services.json`.
5. Confirm the downloaded file contains a client block with
   `"package_name": "za.co.jagspoor.app"` (both the `client_info` entry and
   the oauth `android_info` entries).
6. Rebuild: `flutter build appbundle --release` (or `flutter build apk`).
7. Remove the stale `com.example.jagspoor` Android app registration from the
   Firebase Console once every environment has migrated (optional but
   recommended to avoid confusion).

## Verification

After replacing the file, verify:

```bash
grep -n '"package_name"' android/app/google-services.json
# must include "za.co.jagspoor.app"
```

Then a release AAB build must complete without a
`No matching client found for package name` error.
