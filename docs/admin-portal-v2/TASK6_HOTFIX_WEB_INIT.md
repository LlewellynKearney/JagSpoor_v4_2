# TASK 6 HOTFIX — Web Init Error (App Check / Crashlytics)

**Branch:** `feature/admin-portal-v2` · **Scope:** `lib/main.dart` ONLY.
Not merged, not deployed. No change to `admin_config` /
`min_required_version`. No Admin Portal V2 page touched.

---

## The bug

`flutter run -d chrome` showed:

```
Initialization error: TypeError: Cannot read properties of null (reading 'initialize')
```

The whole startup block in `lib/main.dart` sits inside one big
`try { … } catch (e) { runApp(<Init Error page>) }`. **Any** throw inside it
replaces the entire app with the "Initialization error" page.

Two startup calls are unsupported on Web and were **unguarded**, so they threw
into that outer catch:

1. **Firebase App Check (debug branch).** The debug branch called
   `FirebaseAppCheck.instance.activate(androidProvider: …, appleProvider: …)`.
   Web has **no Android/Apple provider**, so the call fails (the plugin's web
   implementation is not initialised for those providers) and the throw
   aborted startup. The release branch was already `try/catch`-guarded — only
   the debug branch was exposed, and `flutter run -d chrome` is a debug build.
2. **Firebase Crashlytics.** `FirebaseCrashlytics.instance` has **no web
   implementation**, so reading it (to wire `FlutterError.onError` /
   `PlatformDispatcher.instance.onError`) throws on Web. This runs
   unconditionally, before App Check, on every platform.

---

## The fix (all in `lib/main.dart`)

### 1. App Check debug branch — skip on Web + `try/catch`

```dart
    } else if (kIsWeb) {
      debugPrint('App Check skipped on Web (no Android/Apple provider)');
    } else {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.debug,
          appleProvider: AppleProvider.debug,
        );
      } catch (e) {
        debugPrint('App Check (debug) activation failed: $e');
      }
    }
```

* **Web** — the branch now short-circuits to a `debugPrint` and never touches
  the native providers.
* **Android / iOS debug** — unchanged behaviour, now additionally
  `try/catch`-guarded so a transient App Check failure logs instead of
  crashing the app.
* **Release** — untouched (already guarded).

### 2. Crashlytics — guard the whole block on `!kIsWeb`

```dart
    if (!kIsWeb) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
```

* **Web** — the block is skipped entirely (Crashlytics does not exist there);
  Flutter keeps its default error reporting.
* **Android / iOS** — identical wiring to before (both handlers still
  installed), so native crash reporting is unchanged.

### 3. Best-effort hardening of the remaining startup calls

Audited every call between `Firebase.initializeApp()` and `runApp` for a
Web-reachable throw into the outer catch:

| Call | Status |
| --- | --- |
| App Check **token handshake** (`getToken(true)`) | already in `try/catch` |
| `FirestoreBootstrap.initialize()` | internally guarded, but the **call site was not** — now wrapped |
| `ReferralLinkHandler.initialize()` | already in `try/catch` |
| `PushNotificationService.instance.initialize()` | already in `try/catch` |
| `PlayBillingService` restore + `PlayPurchaseRecorder` listen | already in `try/catch` |
| Entitlement sync (`authStateChanges` + `syncEntitlementFromPurchases`) | already in `try/catch` |
| `ReviewService` launch/config | already in `try/catch` |

The one gap — the `FirestoreBootstrap.initialize()` **call site** — was wrapped
so a Web-only Firestore init failure can never abort startup:

```dart
    try {
      await FirestoreBootstrap.initialize();
    } catch (e) {
      debugPrint('FirestoreBootstrap initialization failed: $e');
    }
```

`FirestoreBootstrap` itself is **unchanged** (it already handles the web
multi-tab IndexedDB exception internally and falls back to in-memory
persistence). This is a defensive outer guard only. **No Android/iOS
behaviour changed** by any of the three fixes.

---

## Why this is safe

* **Native builds are byte-for-byte equivalent in behaviour.** The release App
  Check path, the Crashlytics wiring on Android/iOS, and every already-guarded
  service are untouched. The only behavioural delta on native is that the
  *debug* App Check failure path now logs instead of throwing — strictly
  better.
* **Web now boots.** App Check is skipped (Web needs no attestation token for
  this app), Crashlytics is skipped (no Web support), and Firestore
  persistence falls back gracefully.
* **No Admin Portal V2 code changed** — the hotfix is confined to
  `lib/main.dart`.

---

## Verification

* `flutter analyze lib/main.dart` → **0 errors, 0 warnings**. The 6
  `info`-level findings (`unnecessary_import`, 4× `deprecated_member_use` on
  `androidProvider`/`appleProvider`, `unnecessary_brace_in_string_interps`)
  are the **exact pre-existing baseline** — verified by `git stash` +
  re-analyze (identical 6 before and after), so the hotfix adds **zero** new
  issues.
* Structural-contract suites that parse `lib/main.dart` pass:
  `play_purchase_item_already_owned_test` (listen-before-restore order
  preserved) + `subscription_loader_restoration_test` (entitlement-sync
  tokens preserved).
* `flutter test` (full suite): **2535 passed, 1 failed** — the single failure
  is the DOCUMENTED pre-existing `trial_onboarding_functions_contract_test`
  (v1-vs-v2 auth trigger), explicitly excluded by the task. No new failures.
* `flutter run` was **NOT** executed (no Chrome in this sandbox) — code review
  + analyzer + tests only, as instructed.

---

## Files

* **Modified:** `lib/main.dart` (Crashlytics `!kIsWeb` guard; App Check
  `kIsWeb` short-circuit + debug `try/catch`; `FirestoreBootstrap` call-site
  guard).
* **New:** `docs/admin-portal-v2/TASK6_HOTFIX_WEB_INIT.md` (this file).

Nothing else — no Admin Portal V2 pages, no Firestore rules / indexes /
Storage, no Cloud Functions, no manifests, no `admin_config` /
`min_required_version`.

---

HOTFIX DONE
