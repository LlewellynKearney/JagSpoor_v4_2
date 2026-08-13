# JagSpoor — Agent Memory

## Canonical project context (added 2026-08-12)

- `context.md` is now the **single source of truth** for architecture, features,
  security posture, build/CI config, and roadmap. It supersedes `PROJECT_CONTEXT.md`
  and `ai-context.md` for any conflicting detail. Reconciled against source on
  2026-08-12; 17 sections covering RBAC, marketplace/financial layer, PayFast
  integration, Firestore rules overhaul, image compression pipeline, FCM push
  notifications, off-grid nav, tactical/vision pipelines, spoor identifier,
  compliance exporters, Firestore collections, Cloud Functions, build & CI/CD,
  environment/deploy constraints, and the active roadmap.

## Backend / Firebase infrastructure (added 2026-08-11)

- A `functions/` Cloud Functions source tree now exists (TypeScript, `firebase-functions` v2 API,
  Node 22 runtime). Build: `cd functions && npx tsc` → emits `functions/lib/`.
- Two exported functions in `functions/src/index.ts`:
  - `payfastITNHandler` — HTTPS `onRequest`, public invoker, region `us-central1`.
    Validates PayFast ITN md5 signature (constant-time compare), calls PayFast's
    `validate` endpoint server-to-server, then on `payment_status==COMPLETE` updates
    `bookings/{m_payment_id}` → `status:'Paid'`, `paymentTimestamp`, `payfastpfPaymentId`.
    Reads `PAYFAST_PASSPHRASE` env var for signature generation.
  - `adminCreateOutfitter` — `onCall`, region `us-central1`. Requires caller
    `auth.token.admin == true`. Creates a new Auth user (Admin SDK, does NOT log out
    caller), writes `/outfitters/{uid}` doc, sets `{ role:'outfitter' }` custom claims.
    Rolls back Auth user on doc/claims failure.
- PayFast crypto helpers live in `functions/src/payfast.ts` (signature build/compute/verify,
  `validateWithPayFast` using global `fetch`).
- `firebase.json` now has a `functions` block (`source: functions`, `runtime: nodejs22`).

## Firestore security rules (hardened 2026-08-11)

- `firestore.rules` rewritten with ownership scoping:
  - `firearms`, `trophies`, `ammunition`, `records`: owner-scoped via `isOwnerOf(field)`.
  - `bookings`: read = hunter OR outfitter party; create = hunter; status field update =
    outfitter only (`statusUpdateAllowed()`); other field updates = any party (status frozen).
    Nested `bookings/{id}/chats` restricted to booking parties.
  - `packages`: read for any signed-in; create/update/delete only if `outfitterId == auth.uid`.
  - `outfitters/{uid}`: read for signed-in; create = admin; update/delete = admin or owner.
  - `animals`: public read preserved; write = admin only.
  - Default deny remains.

## Firestore indexes

- `firestore.indexes.json` now includes `bookings` composites:
  `outfitterId ASC + bookingTimestamp DESC` and `hunterId ASC + bookingTimestamp DESC`.

## Environment constraints (this sandbox)

- `firebase-tools` v15.26.0 installed locally (`npx firebase-tools`); NOT global.
- **No Firebase credentials available** — `FIREBASE_TOKEN`/service account absent;
  `firebase projects:list` returns 401 "No OAuth tokens found". Deployment must be run
  in an environment with `firebase login` or `FIREBASE_TOKEN` set.
- **No Java/JVM** — Firestore emulator cannot run here, so `@firebase/rules-unit-testing`
  cannot execute; rules were validated structurally (JSON valid, default-deny present,
  `tsc` clean) but not via emulator integration tests.
- PayFast signature logic was unit-tested in isolation (round-trip + tamper detection pass).

## Deploy command (when credentials available)

```bash
cd /workspace/project/JagSpoor_v4_2
(cd functions && npm install && npm run build)
npx firebase-tools deploy --only functions,firestore:rules,firestore:indexes
# Set PayFast passphrase: npx firebase-tools functions:set PAYFAST_PASSPHRASE=...
```

## Trophy Inventory — measurements, photos, stock-by-farm (added 2026-08-12)

- Trophy Inventory form (`outfitter_trophy_stock_screen.dart`) gained:
  - **Trophy Measurement** field (`_measurementController`, decimal, `in` suffix)
    → passed as `trophyMeasurement` (double?) to
    `OutfitterEnterpriseManager.syncTrophyStock`, which stores it under BOTH
    `trophyMeasurement` and `trophyLengthInches` aliases for read compatibility.
  - **Multi-photo attachments (up to 3)**: `List<XFile> _pickedPhotos` filled via
    `ImagePicker.pickMultipleMedia(imageQuality: 80, limit: remaining)`.
    Horizontal thumbnail strip with per-image remove buttons (`_removeTrophyPhoto`).
    On sync, `_uploadTrophyPhotos()` uploads each to Firebase Storage at
    `trophy_photos/{outfitterId}/{timestamp}_{i}.jpg` and returns download URLs,
    which `syncTrophyStock` stores as the `trophyPhotoUrls` array (capped at 3).
    Added `match /trophy_photos/{uid}/{fileName}` to `storage.rules` (owner-scoped
    write). image_picker 1.2.1 + firebase_storage 13.4.3 already in pubspec.
- **Current Stock by Farm** binding fixed: the list stream
  (`.where('outfitterId').orderBy('lastUpdated', descending)`) had the SAME
  missing-composite-index + silent-error bug as the farms list. Fixes:
  - Added `trophies` composite index `(outfitterId ASC, lastUpdated DESC)` to
    `firestore.indexes.json`.
  - `snapshot.hasError` branch surfaces the error instead of "No trophy stock
    synced".
  - Rewrote the list to actually GROUP by `farmId` (the section is titled
    "Current Stock by Farm"): nested `FutureBuilder` fetches the outfitter's
    farms once into a `farmId → name` map; each farm card shows a per-farm total
    badge + per-species breakdown rows (count, price, measurement, photo count).
    The trophy stream is already reactive (`snapshots()`), so the grouped tally
    updates immediately when a new trophy is added.
- `syncTrophyStock` got new optional params `trophyMeasurement` and
  `trophyPhotoUrls` (both omitted → no field written). Docstring updated.
- Deploy reminder: new `trophies` index + `storage.rules` change need deployment
  (`npx firebase-tools deploy --only firestore:indexes,storage`). Until the
  index is deployed the stock query falls back to the now-surfaced error UI.
- Files: `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `firestore.indexes.json`, `storage.rules`.

## Enterprise Control Panel — farms & managers (fixed 2026-08-12)

- "No farms registered" bug on the Enterprise Control Panel was caused by the
  `Registered Farms` stream query using
  `.where('outfitterId', isEqualTo: uid).orderBy('createdAt', descending: true)`
  with **no matching composite index** in `firestore.indexes.json`. The equality
  + orderBy combo requires a composite index in Firestore; without it the query
  errors — and the `StreamBuilder` only handled `ConnectionState.waiting`,
  silently treating the errored snapshot as empty and rendering "No farms
  registered" even when farms existed.
- Fixes:
  - Added `farms` composite index `(outfitterId ASC, createdAt DESC)` to
    `firestore.indexes.json` (must be deployed: `npx firebase-tools deploy --only firestore:indexes`).
  - `StreamBuilder` in `outfitter_enterprise_panel_screen.dart` now has an
    explicit `snapshot.hasError` branch that surfaces the error instead of
    masquerading as an empty list. The stream itself is already reactive, so the
    list updates dynamically when `addFarm` writes a new doc.
- Manager cell number: `Assign Farm Manager` block now has a dedicated
  `Cell Phone Number` (`_managerCellController`) `TextFormField` (phone
  keyboard, validator stripping `+ - ( )` and requiring ≥9 digits). The value is
  passed through `_assignManager` → `OutfitterEnterpriseManager.assignManager()`
  (new required `managerCell` param) and persisted to the `farm_managers` doc as
  BOTH `managerCell` and `cellNr` fields (covers either read convention).
- Files: `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `firestore.indexes.json`.
- Deploy reminder: the new `farms` index won't exist until
  `firestore:indexes` is deployed in an environment with `firebase login` /
  `FIREBASE_TOKEN`. Until then the query falls back to an error (now surfaced in
  the UI) rather than silently showing empty.

## Camera capture-session hygiene (hardened 2026-08-12)

- Black-preview bug on Blood Trail Tracker Radar was caused by capture-session
  contention: `CameraController.dispose()` was called without first stopping
  the image stream, the controller reference wasn't nullified, and there was
  no delay between sessions — so Android's Camera2 driver couldn't finish
  `waitUntilIdle()` / free the `SurfaceTexture` before the next screen opened
  a fresh session against a half-released surface.
- Both camera screens now follow the same release contract:
  - `_releaseCamera()` helper: `await _stopImageStream()` → nullify the
    controller ref → `await controller.dispose()` in a try/catch. Safe to
    call repeatedly.
  - `dispose()` calls `_releaseCamera()` (fire-and-forget) so the session is
    torn down before the State is destroyed.
  - `didChangeAppLifecycleState` (both states are now `WidgetsBindingObserver`):
    on `inactive`/`paused` → `_releaseCamera()` + clear `_isInitialized`;
    on `resumed` → `_initializeCamera(withHardwareDelay: true)`.
  - `_initializeCamera({withHardwareDelay})`: 300ms `Future.delayed` before
    re-init so Camera2 can release the surface; `_releaseCamera()` before
    creating a fresh controller; inner try-catch around `initialize()` that
    releases + waits 300ms + retries once on failure; outer catch clears the
    error state; `_isInitializing` re-entrancy guard.
- Files: `lib/features/hunter_mode/screens/blood_tracker_screen.dart`
  (image-stream screen — stream stop is essential), `lib/features/track/
  presentation/spoor_detection_hud_screen.dart` (takePicture screen — was
  missing observer/lifecycle entirely; now has them).

## Contextual info icons (added 2026-08-12)

- Reusable `lib/core/widgets/contextual_info_icon.dart`:
  - `ContextualInfoIcon` — compact `IconButton` showing `info_outline` tinted
    with the theme accent (override via `iconColor`); taps open an
    `ExplanationDialog`. Props: `title`, `description`,
    `concepts: List<ExplanationConcept>`, optional `iconColor`/`iconSize`.
  - `ExplanationDialog` — `showModalBottomSheet` (scrollable, theme-coloured)
    rendering Title, Description, a KEY CONCEPTS breakdown of
    `(label, detail)` rows, and a "GOT IT" dismiss action.
    Call via `ExplanationDialog.show(context, title:, description:, concepts:)`.
- Placed info icons across complex feature headers:
  - **Scope Settings & Tools** (`scope_tools_bottom_sheet.dart`): Turret Click
    Math (1/4 MOA ≈ 0.261" @100yd vs 0.1 Mil = 1 cm @100m), SFP Magnification
    Scaling (trueValue = ratedValue × calibratedMag/currentMag), Tall-Target
    Tracking Test (error % = |measured−dialed|/dialed×100).
  - **Spoor Identifier** (legacy `spoor_identifier_screen.dart` + HUD
    `spoor_detection_hud_screen.dart`): Morphological Categories (Paw/Carnivore,
    Cloven-Hoofed/Ungulate, Solid Hoof/Equine), Scale Reference Calibration
    (mm-per-pixel = knownObjectMm/knownObjectPixels), Contour Circularity
    Metric (4πA/P²).
  - **Blood Trail Tracking Radar** (`blood_tracker_screen.dart`): HSV Spectrum
    Thresholding (Hue Tolerance, Min Saturation, Min Value for haemoglobin
    contrast in bush light).
  - **Admin Portal & Analytics**: `outfitter_revenue_screen.dart` (Gross Revenue
    vs Platform Commission — gross × 0.05 fee, net = gross − fee),
    `bulk_csv_import_screen.dart` (CSV column spec: email, fullName, role,
    phoneNumber).

## Universal PDF Document Engine (added 2026-08-12, Phase 6)

- Central reusable PDF template service: `lib/core/services/pdf_document_engine.dart`.
  - `JagSpoorPdfTheme` — static tactical Earth/Gold palette matching the app:
    `accent` `#C68B59` (Warm Gold/Bronze), `accentGold` `#D4AF37` (Brushed Gold),
    `deepBrown` `#795548`, `darkSlate` text, `band`/`cream` backgrounds,
    `divider`, `white`. Text styles: `body`, `caption`, `label`, `value`,
    `sectionTitle`.
  - `JagSpoorPdfDocument` — async builder wrapper. `create(title:, documentId:)`
    loads the branded logo asset (`assets/app logo/logo1.png`) once via root
    bundle and caches it on the instance so every page reuses the same bytes.
    `addPage(margin:, content:)` appends a `pw.MultiPage` with the standard
    header (logo + "JAGSPOOR" wordmark + title + doc ID + issued date) and a
    footer (support email `support@jagspoor.com`, "Page X of Y" via
    `MultiPage`'s `pageFormat`-aware builder, and a legal disclaimer).
    `saveAndShare(filename:, shareSubject:, shareText:)` writes to
    `getApplicationDocumentsDirectory()` and invokes `Share.shareXFiles`.
  - Reusable content builders (all return `pw.Widget`):
    `sectionBar(title)`, `detailBox(rows)`, `infoRow(label, value)`,
    `currencyRow(label, amount, {emphasis, bold})`, `dataTable(headers,
    columnWidths, rows)`, `signatureBlock(label, imageBytes, width, height)`,
    `formatZAR(double)` → "R 1 234.56", `formatDate(DateTime?)` → "YYYY-MM-DD".
- Exporters using the engine (consistent branded header/footer across the
  whole document line):
  - **Venison Transport & Hunt Permit** — `lib/features/hunter_mode/services/
    venison_permit_pdf_exporter.dart` (NEW). Fetches hunter + outfitter
    signature images from Firebase Storage URLs via `http` and embeds them.
    Wired via `onExport` callback into the permit list details sheet.
  - **Booking Invoice / Confirmation** — `lib/features/hunter_mode/services/
    outfitter_invoice_exporter.dart` (REFACTORED). Now takes the raw booking
    map + bookingId; fetches the linked `packages` doc to recover the
    itemized line-item / species / all-inclusive breakdown, prints the 7.5%
    platform commission row, the 25% non-refundable deposit status + balance,
    and any date-change request history. Call site in
    `outfitter_booking_dashboard_screen.dart` updated to pass `bookingData`.
  - **Trophy Inventory Report** — `lib/features/hunter_mode/services/
    trophy_inventory_report_exporter.dart` (NEW). Farm-grouped trophy stock
    (species, qty, price/animal, measurement in inches, photo count) +
    inventory summary. Wired via AppBar PDF icon in
    `outfitter_trophy_stock_screen.dart`.
  - **Revenue & Farm Analytics Report** — `lib/features/hunter_mode/services/
    revenue_analytics_report_exporter.dart` (NEW). Gross revenue, 7.5%
    platform fees, net earnings, enterprise metrics, and a farm-manager
    directory. Wired via AppBar PDF icon in `outfitter_revenue_screen.dart`.
  - **SA Game Transport Permit** — `lib/features/hunter_mode/services/
    transport_permit_pdf_exporter.dart` (REFACTORED to engine; Sections A–E
    + signature blocks).
  - **Slaughterhouse / Meat Processing Manifest** — `lib/features/hunter_mode/
    services/meat_processing_exporter.dart` (REFACTORED to engine).
- Remaining exporters NOT yet migrated to the engine (still use legacy
  per-page layout): `SapsPdfGenerator`, `FirearmPdfGenerator`,
  `InvoicePdfService`. They remain functionally correct; migration is a
  follow-up cosmetic-consistency task.
- Asset note: the header logo path `assets/app logo/logo1.png` is already
  declared under `flutter.assets` in `pubspec.yaml` (and used for the app icon).
- `flutter analyze`: 0 errors, 14 warnings, 319 infos (unchanged from Phase 5
  baseline — no new issues introduced).

## Superuser 3-mode instant switcher (added 2026-08-12)

- Reusable widget `lib/features/admin/widgets/admin_mode_switcher.dart`:
  - `AdminMode` enum: `hunter`, `outfitter`, `admin`.
  - `AdminModeSwitcher` — three-segment control bar (Hunter / Outfitter /
    Admin). Active segment is highlighted with the theme accent; tapping an
    inactive segment issues `Navigator.pushReplacementNamed` to
    `/hunter_dashboard`, `/outfitter_dashboard`, or `/admin_dashboard`,
    rebuilding the navigation stack for the new role context **immediately
    without sign-out or credential re-entry** (mirrors the existing admin
    bypass in `role_selection_screen.dart`).
  - `AdminModeSwitcherButton` — AppBar `IconButton` (swap icon) that opens the
    same selector as a modal bottom sheet. `activeMode` marks the current
    context.
- Wiring:
  - **Admin dashboard** (`admin_dashboard_screen.dart`): `AdminModeSwitcher`
    embedded at the top of the body ListView (activeMode = admin) so admins
    can jump to Hunter/Outfitter mode from the portal.
  - **Hunter dashboard** (`hunter_dashboard.dart`): added `_isAdmin` resolved
    via `AdminAuthGuard.isCurrentUserAdmin()` in initState; conditionally
    renders `AdminModeSwitcherButton` (activeMode = hunter) in the AppBar.
  - **Outfitter dashboard** (`outfitter_dashboard.dart`): `_isAdmin` resolved
    alongside `UserRoleResolver` in `_resolveUserRole`; conditionally renders
    `AdminModeSwitcherButton` (activeMode = outfitter) in the AppBar.
- The switcher relies on the existing named routes registered in `main.dart`
  (`/hunter_dashboard`, `/outfitter_dashboard`, `/admin_dashboard`) and the
  `AdminAuthGuard` admin check (custom claim `admin==true`,
  `users/{uid}.role=='admin'`, or `admin@jag-spoor.co.za` allow-list).

## Branding audit (2026-08-12)

- Codebase audited for Dixon / Dixon Batteries / Dixon logo references: **none
  found** (source, assets, pubspec, PDFs). Only `BatterySaverManager` (the
  off-grid battery-saver feature) matches the "battery" substring — unrelated
  to any Dixon branding.
- All admin/support email references already point to
  `support@jag-spoor.co.za` / `admin@jag-spoor.co.za` (and `privacy@` for the
  privacy policy). PDF engine footer uses `support@jag-spoor.co.za`.
- Only logo asset: `assets/app logo/logo1.png` (official JagSpoor logo), used
  by the PDF engine header and the app icon.

## Theme system (added 2026-08-12)

- Central `ThemeController extends ChangeNotifier` in `lib/core/theme/app_theme.dart`.
  Persists Day/Night choice to `SharedPreferences` key `jagspoor_dark_mode`.
  `main()` calls `await themeController.init()` before `runApp` so the first
  frame uses the saved mode (no cold-start flash).
- `MaterialApp` wired with `theme: lightTheme`, `darkTheme: darkTheme`,
  `themeMode: themeController.themeMode`, wrapped in `AnimatedBuilder` so
  toggling `setDarkMode`/`toggleThemeMode` rebuilds the whole app instantly.
- Official tactical palette in `AppColors` (use these / `Theme.of(context)`,
  never raw `Colors.white`/`Colors.black`):
  - Dark: bg `#121212`, card `#262626`, accent `#C68B59`/`#D4AF37`,
    text `#E0E0E0`, subtitle `#B0B0B0`.
  - Light: bg `#F4EFEA`, card `#FFFFFF`, accent `#795548`/`#8D6E63`,
    text `#212121`, subtitle `#5D4037`.
- Day/Night toggles: Hunter Dashboard AppBar icon (light_mode/dark_mode),
  Hunter Profile switch (`setDarkMode(v)`), Outfitter Dashboard switch
  (`setDarkMode(v)`).
- Standardized screens: `scope_tools_bottom_sheet.dart` (converted hardcoded
  `_tacticalBlack`/`_panelBlack`/`_accent` const → Theme.of getters; all
  `Colors.white`/`black` text → `_textPrimary`/`_textSecondary`/`_textHint`),
  `auth_screen.dart` (Google sign-in button + 2FA sheet use theme colors).
  Dashboards + legacy spoor screen already use `theme.*`/`Theme.of`.
- Camera-overlay screens (spoor HUD, blood tracker) intentionally use
  high-contrast `Colors.white`/`black` for HUD text over the live camera
  preview — that contrast is by design, not a theme violation.
- Tests: `test/theme_controller_test.dart` (9 tests: persistence load/default,
  setDarkMode/toggle persist, idempotency, notify, brightness, exact palette).

## Flutter SDK & analyze (this sandbox)

- Flutter SDK installed at `/home/openhands/flutter`. The local checkout is
  **3.44.9 stable** (Dart 3.9, 2026-08-05) — NEWER than the **CI pin of 3.29.1**
  in `.github/workflows/build-and-deploy.yml`. This version skew matters (see
  below). Add to PATH: `export PATH="$HOME/flutter/bin:$PATH"`.
  - **Why CI stays on 3.29.1, not 3.44.9**: the project's iOS Firebase plugins
    resolve cleanly under CocoaPods (the iOS dependency manager Flutter uses
    on 3.29.1) but hit a Swift Package Manager transitive conflict on newer
    Flutter (3.44.9 defaults iOS to SPM): `firebase_core` → firebase-ios-sdk
    12.17.0 vs `firebase_storage` → 12.15.0. Coordinating every `firebase_*`
    package to one firebase-ios-sdk is a deep dependency rabbit hole, so we
    keep the proven 3.29.1 pin (CocoaPods) and instead revert the iOS native
    template to the classic form that compiles on 3.29.1. See the CI section.
  - **Version-skew note**: on 3.29.1 `DropdownButtonFormField` takes `value:`
    (`initialValue:` is a hard compile error there); on 3.44.9 `value:` is a
    deprecation info in favor of `initialValue:`. We use `value:` everywhere
    (works on both; matches the other 9 dropdowns). The local deprecation
    infos are accepted baseline.
- `flutter pub get` succeeds (148 outdated but constraint-incompatible packages — expected).
- `flutter analyze` result (local 3.44.9): **0 errors, 14 warnings, 320 infos**.
  No analyzer errors block the build.
  - Warnings: `unused_local_variable` (9), `invalid_null_aware_operator` (1 in
    `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart:355`), plus
    unused imports/elements/fields.
  - Infos dominated by `avoid_print` (220, mostly debug `print()` calls), plus
    `non_constant_identifier_names` (16), `curly_braces_in_flow_control_structures` (14),
    `unnecessary_const` (13), `use_build_context_synchronously` (5, in outfitter
    presentation screens), `deprecated_member_use` (`withOpacity`, `androidProvider`,
    `appleProvider` in `lib/main.dart` + `role_selection_screen.dart`, plus
    `DropdownButtonFormField.value` on 3.44.9 only).
  - Production `lib/` ≈ 94 issues; `test/` ≈ 209 issues. No analyzer errors block the build.

## CI workflow — Build & Deploy (fixed 2026-08-12)

- `.github/workflows/build-and-deploy.yml` runs: `build-android` (ubuntu),
  `build-ios` (macOS), then `deploy-firebase` (needs build-android) and
  `notify` (needs deploy-firebase, `if: always()`). Flutter pin: **3.29.1**
  (stable), Java 17 (Temurin).
- **iOS native template reverted to the classic form** (root-cause fix for the
  iOS build failure). The project's iOS code had been regenerated by a modern
  Flutter template that adds scene/implicit-engine APIs:
  - `ios/Runner/SceneDelegate.swift` subclassed `FlutterSceneDelegate` (not in
    3.29.1's framework → "Cannot find type 'FlutterSceneDelegate' in scope").
  - `ios/Runner/AppDelegate.swift` conformed to `FlutterImplicitEngineDelegate`
    + used `FlutterImplicitEngineBridge` / `didInitializeImplicitFlutterEngine`
    (not in 3.29.1 → "Cannot find type 'FlutterImplicitEngineDelegate'").
  - `Info.plist` carried a `UIApplicationSceneManifest` wiring the scene
    delegate.
  Fix applied (classic pre-scene template, works on 3.29.1 through 3.44+):
  - `AppDelegate.swift` → canonical `FlutterAppDelegate` subclass that calls
    `GeneratedPluginRegistrant.register(with: self)` in
    `application(_:didFinishLaunchingWithOptions:)`.
  - Deleted `SceneDelegate.swift` and removed its 4 `project.pbxproj`
    references (PBXBuildFile, PBXFileReference, group child, Sources phase).
  - Removed the `UIApplicationSceneManifest` block from `Info.plist`
    (validated as a well-formed plist after edit).
  This restores the AppDelegate-based window lifecycle (the Flutter default
  for years); a single-window app does not need a scene delegate. iOS now uses
  CocoaPods on 3.29.1 (Podfile present, `platform :ios, '15.5'`), which resolves
  the Firebase plugins without the SPM conflict (see version note above).
- **Dart compile error (fixed)**: `venison_permit_form_screen.dart:861` passed
  `initialValue:` to `DropdownButtonFormField` (no such param on 3.29.1). This
  broke BOTH Android and iOS jobs (both run the Dart kernel compile). Fixed to
  `value: _selectedSex` (non-null, default 'Male', always in `_sexOptions`),
  matching the other 9 `DropdownButtonFormField` call sites. The remaining 4
  `initialValue:` usages are on `FormField<T>` / `TextFormField` (legit) and
  left unchanged.
- **Build incompatibilities verified/aligned**:
  - Java 17 (Temurin) — correct for AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20.
  - Android: `flutter build apk --debug`; `ndkVersion = flutter.ndkVersion`
    (CI auto-installs the NDK plugins request — a 26.3-vs-27.0 version warning
    is emitted but non-fatal). Confirmed green on CI after the compile fix
    (run 31628707429, `Build Android APK` ✓ in ~10 min).
  - iOS: `flutter build ios --simulator --no-codesign` — `--no-codesign`
    skips signing (no provisioning profile on the hosted runner); `pod install`
    runs inside the Flutter build (~8 min; resolves cleanly on 3.29.1 via
    CocoaPods). Confirmed `pod install` + `Xcode build` both run on CI
    (run 31632434809); the build now reaches the simulator link stage.
  - **mobile_scanner arm64-simulator fix**: on Apple-Silicon runners
    (`macos-latest`, arm64) the iphonesimulator build targets arm64, but
    `mobile_scanner` 6.0.11's prebuilt ML xcframework ships no arm64-sim
    slice → Xcode "User-Defined Issue: Unsupported Swift architecture" at
    `mobile_scanner-Swift.h`. Fix: `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`
    added BOTH in `ios/Podfile` post_install (pod targets) AND the Runner
    target's 3 build configs in `project.pbxproj` (Profile/Debug/Release,
    anchored after `ENABLE_BITCODE = NO;`). This forces the simulator build
    to x86_64 (run via Rosetta on the arm64 runner), which the prebuilt
    binaries support. Side effect: local iOS-sim builds also run x86_64
    (acceptable, intentional CI parity).
  - One prior run failed on a transient `java.net.SocketException: Unexpected
    end of file from server` during `flutter pub get` (runner network glitch),
    not a code issue — re-runs clear it.
- **Secret handling**: `deploy-firebase` gates ALL deploy steps behind a
  `Check Firebase secrets` step (`steps.secrets.outputs.deploy` true/false).
  When `FIREBASE_SERVICE_ACCOUNT` is unset it emits a `::warning::` with a
  clear "configure the repo secret" message and skips deploy (every later
  step is `if: deploy == 'true'`) — so missing secrets no longer fail the job.
  Replaced the old broad `continue-on-error: true` (which masked real deploy
  errors) with explicit per-step gating. Confirmed: the deploy job now reports
  `success` (correctly skipped) instead of `failure` when secrets are absent.
  `notify` runs (`if: always()`) and only pings Discord if
  `vars.DISCORD_WEBHOOK` is set (note: the `aristidp/discord-action` step can
  still error when the webhook var is unset — non-essential, does not gate
  build/deploy).
- **permissions**: top-level `permissions: { contents: read }` (least-privilege;
  deploy uses its own Firebase service-account secret, not GITHUB_TOKEN).
- No `environment:` directive (referencing a non-existent GitHub environment
  would block the job).

## Phase 3 — Hunting Package Publisher & Marketplace Pipeline (added 2026-08-12)

- **Platform fee revised 5% → 7.5%** everywhere:
  `PackageBookingManager.platformCommissionRate` is now `0.075`; the manual
  invoice / carcass butchery `markup` is now `1.075`
  (`invoice_pdf_service.dart`, `manual_invoice_screen.dart`,
  `carcass_record.dart`). All UI labels + `context.md` updated to "7.5%".
- **New pricing model** `lib/features/hunter_mode/models/package_pricing.dart`:
  `PackagePricing` (all-inclusive vs itemized), `ItemizedLineItem`,
  `SpeciesLineItem`, the 7 standard `ItemizedBreakdownCategory`s (bakkie,
  slaughtering, coldroom, hunter daily, non-hunter observer daily, overnight
  accommodation, catering), and `DateChangeRequest`.
- **Outfitter Package Publisher** (`outfitter_package_creator_screen.dart`)
  rewritten with an All-Inclusive ↔ Itemized segmented toggle, the 7 itemized
  line-item editors (qty × price each), a SA Game Guide multi-species selector
  (loads `animals` collection), Start/End date availability pickers, and a live
  "Outfitter Base Price + 7.5% Platform Fee = Total Package Value" summary.
- **`publishPackage`** now takes a `PackagePricing` (resolves base price from
  mode + line items + species) and writes `mode`, `lineItems`, `speciesItems`,
  `availabilityStart/End`, `platformCommissionRate`.
- **25% non-refundable deposit**: `PackageBookingManager.depositFraction =
  0.25`. `bookPackage` writes `depositAmountRands`/`balanceAmountRands`.
  New `approveBookingAndRequestDeposit()` transitions an approved booking to
  `Pending Deposit` and stores the deposit split — the outfitter "APPROVE &
  REQUEST DEPOSIT" button calls it. The hunter PayFast button charges the 25%
  deposit amount (falls back to full total for legacy bookings). `Paid` is a
  new status (set by the PayFast ITN handler on COMPLETE payment).
- **Date-change requests**: `requestDateChange()` (hunter) writes
  `dateChangeRequest` + `dateChangeRequestPending:true`;
  `resolveDateChange(approved)` (outfitter) clears the flag, sets the request
  status, and on approval copies requested → `confirmedStartDate/EndDate`.
  Hunter booking card has a "Request Date Change" button + sheet (date pickers
  + reason); outfitter dashboard renders a date-change section with
  APPROVE NEW DATES / DECLINE actions.
- **Marketplace details view**: `_BookingConfirmationSheet` is now an
  interactive details sheet showing the itemized / all-inclusive breakdown,
  advertised species, inclusions, 7.5% fee split, and the 25% deposit row.
  Package card shows the total price *incl.* the 7.5% fee + meta chips
  (mode, species count, availability window).
- **Firestore**: bookings now carry `status` ∈ `Pending Approval`,
  `Approved`, `Pending Deposit`, `Paid`, `Declined`, `Completed`, `Cancelled`.
  The status-update rule (`statusUpdateAllowed()`) is unaffected — only the
  outfitter may flip status. Date-change fields are non-status fields so either
  party can write them; resolution (status flip inside the map + the
  `dateChangeRequestPending` flag) is done via the manager methods which the
  respective party calls.
- **`flutter analyze`**: 0 errors (319 infos + 14 warnings, all pre-existing).
  Two new `deprecated_member_use` infos on `DropdownButtonFormField.value`
  appear only under the locally-installed Flutter 3.44.9; the CI pin (3.29.1)
  does not flag them.
- Files: `lib/features/hunter_mode/models/package_pricing.dart` (new),
  `lib/features/hunter_mode/services/package_booking_manager.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart`,
  `lib/features/hunter_mode/services/outfitter_invoice_exporter.dart`,
  `lib/features/outfitter_mode/data/models/carcass_record.dart`,
  `lib/features/outfitter_mode/data/services/invoice_pdf_service.dart`,
  `lib/features/outfitter_mode/presentation/manual_invoice_screen.dart`,
  `context.md`.

## Batch D — Permit Log Permissions, Dedup & Marketplace Hunter Privacy (added 2026-08-12)

- **`firestore.rules` `venison_permits/{permitId}`** rewritten:
  - `allow read: isSignedIn() && (resource == null || outfitterId == uid || hunterId == uid || isAdmin())` — lets both `.where('outfitterId', isEqualTo: uid)` and `.where('hunterId', isEqualTo: uid)` list queries succeed (server guarantees returned docs satisfy the rule). `resource == null` is the not-yet-existing edge case (harmless for reads of existing docs).
  - `allow create, update: isSignedIn()` — either party may write (both co-complete the legal form + signatures).
  - `allow delete: isOwnerOf('outfitterId') || isAdmin()` — least-privilege (unchanged from before).
  - Removed the local `isPermitParty()` helper (now inlined). Needs `npx firebase-tools deploy --only firestore:rules` in a credentialed env.
- **Permit manager consolidation**: the standalone "Issue Game Transport Permit"
  (`OutfitterTransportPermitScreen`) entry and the direct "Venison Transport
  Permit" form entry were removed from BOTH the outfitter dashboard
  (`outfitter_dashboard.dart`) and the hunter dashboard (`hunter_dashboard.dart`).
  All permit creation + log viewing is now consolidated into
  `VenisonPermitListScreen` (its "New Permit" FAB opens `VenisonPermitFormScreen`).
  Unused imports removed; `OutfitterTransportPermitScreen` file left in place
  (no longer navigated to).
- **Hunter "My Venison Permits" log**: hunter dashboard entry renamed from
  "My Transport Permits" → "My Venison Permits" → `VenisonPermitListScreen(isOutfitterMode: false)`.
- **Dedup**: `VenisonPermitManager.getMyPermitsStream` now de-duplicates the
  snapshot by document id (`seen.add(doc.id)`) before mapping, so a permit can
  never render twice even if a future outfitterId+hunterId stream merge returns
  the same doc twice.
- **Marketplace hunter privacy** (`hunter_package_marketplace_screen.dart`):
  the "Outfitter Base Price" and "7.5% Platform Fee" `_PriceRow`s were removed
  from the booking details sheet; the total remains inclusive of the fee but is
  relabelled "Total Price" (also on the package-card chip "total price" and the
  booked-hunt deposit banner). The dead `isFee` param was removed from `_PriceRow`.
  Primary action button renamed "CONFIRM BOOKING" → "BOOK THIS PACKAGE".

## Phase 4 — AI Paper Price List Scanner Updates & History Log (added 2026-08-12)

- **7.5% platform fee applied to the AI scanner pipeline** (was 5%):
  - `PricelistScannerService.platformCommissionRate` now `0.075`; the legacy
    `processAndUploadPricelistImage`, `calculateTotalWithFee`, and
    `submitCustomPackageBooking` all compute off this constant.
  - `outfitter_pricelist_verification_screen.dart`: `_updateItem` + `_saveToFirestore`
    now multiply base by `1.075`; the `_EditablePriceItem` preview row shows
    "7.5% Fee" and "Hunter Display Price (incl. 7.5%)"; info banner reads
    "7.5% commission will be applied on save."
  - `outfitter_pricelist_scanner_screen.dart`: loading text + info panel updated
    to "7.5% Platform Fees" / "7.5% platform commission".
  - The custom-package builder (`hunter_custom_package_builder_screen.dart`)
    reads `hunterDisplayPriceZAR` from stored items, so it automatically
    reflects the 7.5% split applied at save time — no hardcoded fee there.
- **Verification screen refactored** to persist via a new centralized
  `PricelistScannerService.saveVerifiedPricelist()` method (drops its direct
  Firestore/Auth fields), so both the verification flow and the history
  re-export flow write through one path.
- **Persistent Scanned Price List History Log**:
  - New `lib/features/hunter_mode/screens/scanned_pricelist_history_screen.dart`
    (`ScannedPriceListHistoryScreen`) renders a reactive list of the
    outfitter's past AI scans via `getMyPriceListsStream()` (a `snapshots()`
    query on `scanned_pricelists` scoped by `outfitterId` + `status=='active'`,
    ordered by `createdAt` desc). Each card shows scan date, source farm, item
    count, base total, and grand total incl. 7.5% fee.
  - A draggable details sheet shows the full parsed species/line-item breakdown
    (base price struck-through, hunter display price incl. 7.5%) plus summary
    cells (Base Total / 7.5% Fee / Hunter Total) and three actions:
    VIEW DETAILS, RE-EXPORT (formats a shareable text summary), and APPLY TO
    PACKAGE (navigates to the Package Publisher). Archive (soft-delete) action
    on each card calls `deletePriceList()`.
  - `getMyPriceListsStream()` added to `PricelistScannerService`.
- **Firestore**: new composite index `scanned_pricelists`
  `(outfitterId ASC, status ASC, createdAt DESC)` added to
  `firestore.indexes.json` (must be deployed:
  `npx firebase-tools deploy --only firestore:indexes`). Rules already permit
  owner-scoped read/write on `scanned_pricelists` (`ownerOrAdmin('outfitterId')`),
  so no rules change is required. Until the index deploys, the history stream
  surfaces the error in-UI (rather than silently showing empty).
- **Dashboard**: a "Scan History Log" feature card was added to the outfitter
  dashboard (in the `!_isManager` block, right after the AI Scan card)
  navigating to `ScannedPriceListHistoryScreen`.
- **`flutter analyze`**: 0 errors (319 infos + 14 warnings, all pre-existing).
- Files: `lib/features/hunter_mode/screens/scanned_pricelist_history_screen.dart`
  (new), `lib/features/hunter_mode/services/pricelist_scanner_service.dart`,
  `lib/features/hunter_mode/screens/outfitter_pricelist_verification_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_pricelist_scanner_screen.dart`,
  `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `firestore.indexes.json`.


## Phase 5 — Legal SA Game Transport & Venison Permit (added 2026-08-12)

- New **`venison_permits`** collection models the official South African
  Venison / Game Transport & Hunt Permit. The `VenisonTransportPermit`
  data model (`lib/features/hunter_mode/models/venison_transport_permit.dart`)
  captures the full statutory template: hunter block (name, ID, cell, address),
  authorized-person/farm block (name, farm, address, cell), hunt window
  (start/end dates), species hunted-and-transported list, dual signature URLs
  + signed dates, and audit fields (`outfitterId`, `hunterId`, `bookingId?`,
  `createdAt`, `status`).
- **`VenisonPermitManager`** (`services/venison_permit_manager.dart`) owns the
  issue lifecycle: (1) write the doc to `venison_permits` to obtain a stable
  `permitId`; (2) upload both signature PNGs to Firebase Storage at
  `permit_signatures/{permitId}/hunter_signature.png` +
  `permit_signatures/{permitId}/outfitter_signature.png`; (3) patch the doc
  with the real download URLs + signed timestamps. Also exposes
  `getMyPermitsStream({isOutfitter})` (scopes by `outfitterId` or `hunterId`,
  ordered by `createdAt` desc), `getPermitById`, `updatePermitStatus`,
  `deletePermit` (best-effort storage cleanup), `prefillFromBooking` (fetches
  booking + linked `users`/`outfitters` docs to prefill the form), and
  `generatePermitNumber` (format `JSV-YYYY-...`).
- **`VenisonPermitFormScreen`** (`screens/venison_permit_form_screen.dart`):
  two interactive `SignatureController` pads (hunter + authorized person) via
  the `signature` package (already a dep); JagSpoor branded header rendering
  `assets/app logo/logo1.png`; hunter/farm/date/species field cards;
  multi-species checklist dialog (species, sex, quantity); date pickers for
  the hunt window. Pre-fills hunter + outfitter/farm details when opened with
  a `bookingId`, while remaining fully editable. Both signatures optional.
- **`VenisonPermitListScreen`** (`screens/venison_permit_list_screen.dart`):
  reactive, searchable permit log for both hunters and outfitters. Tap a card
  -> draggable details sheet showing the full permit breakdown + both captured
  signature images (`cached_network_image`) + signed dates, with VOID and
  DELETE actions.
- **Firestore rules**: new `match /venison_permits/{permitId}` -- read by
  hunter OR outfitter party (`isPermitParty()` helper) or admin; create by any
  signed-in party; update/delete by `isOwnerOf('outfitterId')` or admin.
- **Storage rules**: new `match /permit_signatures/{permitId}/{fileName}` --
  write by any authenticated user (both parties are authenticated); reads
  covered by the global authenticated-read rule.
- **Firestore indexes**: two composite indexes added to
  `firestore.indexes.json` for the two `getMyPermitsStream` queries:
  `venison_permits` `(outfitterId ASC, createdAt DESC)` and
  `(hunterId ASC, createdAt DESC)`.
- **Dashboard nav**: outfitter dashboard gained "Venison Transport Permit"
  (form) and "Permit Log & Manager" cards (after the Game Transport Permit
  card, in the `!_isManager` block). Hunter dashboard marketplace features
  gained "Venison Transport Permit" and "My Transport Permits" cards.
- **`flutter analyze`**: 0 errors (319 infos + 14 warnings, all pre-existing;
  the 4 new files + rules are analyzer-clean).
- Deploy reminder: the new `venison_permits` indexes + `firestore.rules` +
  `storage.rules` changes must be deployed
  (`npx firebase-tools deploy --only firestore:indexes,firestore:rules,storage`)
  in an environment with Firebase credentials. Until the indexes are built
  the permit streams surface the index-missing error in-UI.
- Files: `lib/features/hunter_mode/models/venison_transport_permit.dart` (new),
  `lib/features/hunter_mode/services/venison_permit_manager.dart` (new),
  `lib/features/hunter_mode/screens/venison_permit_form_screen.dart` (new),
  `lib/features/hunter_mode/screens/venison_permit_list_screen.dart` (new),
  `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `lib/features/hunter_mode/hunter_dashboard.dart`, `firestore.rules`,
  `storage.rules`, `firestore.indexes.json`.

## Outfitter Package CRUD Polish — full lifecycle + image management (added 2026-08-13)

- **`PackageStatus` enum** added to `lib/features/hunter_mode/models/package_pricing.dart`:
  `active`, `draft`, `archived`, `deleted` (with `label`, `fromString`, and
  `isListed`). Replaces the loose `'active'`/`'deleted'` string literals.
- **`PackageBookingManager`** (`services/package_booking_manager.dart`)
  gained the full outfitter package CRUD surface:
  - `publishPackage` now returns `Future<String>` (the new doc id) and takes
    `status` (default `active`; pass `draft` to save an unlisted WIP),
    `imageUrls` (gallery download URLs), and `depositPercentage` (per-package
    non-refundable deposit, 0–100, default 25 — stored as both
    `depositPercentage` and the fractional `depositFraction`). Validates
    title AND description non-empty (description was previously unvalidated).
  - `updatePackage({packageId, title?, description?, pricing?, inclusions?,
    farmId?, imageUrls?, depositPercentage?})` — owner-scoped edit; recomputes
    the 7.5% commission split whenever pricing changes.
  - `setPackageStatus({packageId, status})` — explicit lifecycle transition.
  - `getMyPackagesStream({status?})` — reactive `snapshots()` scoped by
    `outfitterId` (+ optional status filter) ordered by `createdAt` desc,
    powering the management screen.
  - `deletePackage` now delegates to `setPackageStatus(deleted)` (soft-delete;
    document retained so booking references + audit history stay intact).
  - `getAllPackages`/`getMyPackages` unchanged (backwards compatible).
- **`OutfitterPackageCreatorScreen`** polished:
  - **Edit mode**: optional `existingPackage` + `packageId` ctor params;
    `_prefillForEdit()` hydrates title, description, pricing mode, price,
    farm, status, deposit %, inclusions, image URLs, line items, species,
    and availability. Save action calls `updatePackage` + `setPackageStatus`
    when editing, `publishPackage` when creating. AppBar + button label adapt
    ("Edit Package" / "SAVE CHANGES" / "SAVE AS DRAFT" / "PUBLISH PACKAGE").
  - **Image management**: `_pickedImages` (up to 5) via
    `ImagePicker.pickMultipleMedia(imageQuality: 80, limit: remaining)`; a
    horizontal thumbnail strip with per-image remove buttons; mixed view of
    newly-picked local files + previously-uploaded remote URLs (rendered via
    `cached_network_image`). `_uploadPackageImages()` compresses each file
    through `ImageService.compressExisting` (1280px / JPEG q75) and uploads to
    Firebase Storage at `package_images/{outfitterId}/{timestamp}_{i}.jpg`
    with a `SettableMetadata` JPEG content type, driving a
    `LinearProgressIndicator` + percentage label from the `UploadTask`
    snapshot events.
  - **Deposit percentage field**: validated `TextFormField` (0–100, `%`
    suffix); clamped in the manager.
  - **Listing status toggle**: Active <-> Draft segmented control sets the
    `_saveStatus` written on publish.
  - `_inputDecoration` gained an optional `suffix` param for the `%` label.
- **`OutfitterPackageManagerScreen`** (NEW,
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`):
  reactive "My Packages" management UI. Status filter chips (All / Active /
  Draft / Archived + a Deleted toggle), each card shows thumbnail, title,
  total price, species count, deposit %, and a status badge. Actions:
  Activate/Deactivate, Archive/Unarchive, Edit (opens creator in edit mode),
  and Delete (confirmation modal -> soft-delete). Deleted packages are
  restorable. FAB publishes a new package.
- **Marketplace rendering** (`hunter_package_marketplace_screen.dart`):
  `_PackageCard` gained `_buildGallery` — a horizontal
  `cached_network_image` strip of the package's `imageUrls` (renders nothing
  when the package has no images, so legacy packages are unaffected).
- **Outfitter dashboard** (`lib/features/outfitter_mode/outfitter_dashboard.dart`):
  a "Manage My Packages" feature card (`inventory_2_rounded`) was added right
  after "Publish Hunting Package" (in the `!_isManager` block) navigating to
  `OutfitterPackageManagerScreen`.
- **`storage.rules`**: added `match /package_images/{uid}/{fileName}` —
  owner-scoped writes (the outfitter's uid is the path segment); reads
  covered by the global authenticated-read rule (marketplace listings are
  visible to signed-in hunters).
- **`firestore.rules`**: no change required — `packages/{packageId}` already
  allows `update, delete` by owner (`resource.data.outfitterId == auth.uid`),
  so `updatePackage` / `setPackageStatus` / `deletePackage` are covered.
- **`firestore.indexes.json`**: three `packages` composite indexes added —
  `(outfitterId ASC, createdAt DESC)` for `getMyPackages`/`getMyPackagesStream`,
  `(outfitterId ASC, status ASC, createdAt DESC)` for the status-filtered
  management stream, and `(status ASC, createdAt DESC)` for the marketplace
  `getAllPackages` query. Must be deployed:
  `npx firebase-tools deploy --only firestore:indexes,storage`.
  Until deployed the streams surface the index-missing error in-UI rather
  than silently showing empty.
- **`flutter analyze`** (local Flutter 3.29.1, CI pin): **0 errors, 0 warnings
  in all changed files** (90 pre-existing infos + warnings across `lib/`,
  all in unrelated files — unchanged from the documented baseline). The new
  management screen + creator edits + marketplace gallery are analyzer-clean.
- Files: `lib/features/hunter_mode/models/package_pricing.dart`,
  `lib/features/hunter_mode/services/package_booking_manager.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart` (new),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `storage.rules`, `firestore.indexes.json`.

## Phase 7 — Shot Group Target Analyzer AI Calibration (added 2026-08-13)

- The "AI Shot Group Analyzer" embedded in `scope_calibration_screen.dart`
  was a **mock** — it used `math.Random()` to simulate a pixel spread and
  only computed a single fake "max spread" MOA value, with no real shot-point
  placement, no mean radius, no center of impact, and no actual scale
  calibration of the reference object in the image. Item #12 replaced it
  with a real, calibrated computer-vision + geometry pipeline.
- **New service** `lib/features/hunter_mode/services/shot_group_analyzer_service.dart`
  (`ShotGroupAnalyzerService`, singleton `instance`):
  - **Real shot-hole detection** via dark-blob detection: rasterizes the
    decoded target photo (the `image` package — already a dep, used by the
    spoor service) to a luminance mask (`0.299R+0.587G+0.114B < 110`), runs
    4-connected-component labelling on a sampled grid (step 4px), and keeps
    each blob whose radius, aspect ratio, and fill ratio fall in the
    bullet-hole range — rejecting dust specks (too small), the reference
    coin / large shadows (too big), and text strokes (low fill). Each
    accepted blob's centroid becomes a `ShotImpact` in full-resolution pixel
    coords.
  - **Scale calibration** via a user-placed two-point `ScaleReference` (coin
    diameter or 1-inch grid line): `pxPerMm = pixelLength / knownLengthMm`.
    The reference length is user-editable (defaults: 5-Rand coin 26mm, 1-Rand
    23mm, 1-inch grid 25.4mm).
  - **Group geometry** (the full statistical suite, all calibrated):
    - **Extreme spread** — max pairwise distance between shot points
      (records the contributing shot pair for overlay rendering).
    - **Mean radius** — average distance of each shot from the group
      centroid.
    - **Center of impact (COI)** — arithmetic centroid of the shot points,
      with offset from a user-marked point of aim (bullseye), expressed as
      horizontal (right +) and vertical (up +) in mm and angular units.
  - **Angular conversions** (physically exact): `inchesToMoa` uses the
    1.047in@100yd definition; `inchesToMil` uses 3.6in@100yd (=100mm@100m);
    distances accepted in yards OR meters (1 m = 1.0936 yd). Both MOA and MIL
    output supported (`AngularUnit` enum).
  - **Suggested turret correction** (`suggestedClicks`): converts the COI
    offset to clicks at the scope's per-click value (e.g. 0.25 MOA / 0.1
    MIL), applying the opposite-direction dial convention (COI right → dial
    left; COI low → dial up).
  - `ShotGroupAnalysis` exposes px / mm / inch / angular forms plus a
    `precisionCategory` (Sub-MOA / 1 MOA / Average / Open), mapping MIL back
    to MOA for the threshold.
- **New interactive overlay**
  `lib/features/hunter_mode/widgets/shot_group_target_overlay.dart`
  (`ShotGroupTargetOverlay` + `_TargetOverlayPainter`):
  - Renders the target photo in a `Stack` with a `CustomPainter` that draws
    **alignment guides** (center crosshair, rule-of-thirds grid, corner
    framing brackets — toggleable) to help frame the target paper straight.
  - **Tap-to-place** interaction with four modes: place shot impacts,
    calibrate scale (two taps + editable known-length), mark point of aim,
    plus Undo / Clear. Auto-detected shots render orange, manual ones red,
    each numbered.
  - Draws the calibrated reference scale line (amber, labelled in mm), the
    extreme-spread line (red, between the two farthest shots), the COI
    marker (green) + COI→aim offset vector, and the aim point (cyan
    crosshair).
- **New dedicated screen**
  `lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`
  (`ShotGroupAnalyzerScreen`): camera capture + gallery load (image_picker,
    maxWidth 1920, quality 90-95), auto-detect on image adopt, the overlay, a
    config row (distance + yds/m + MOA/MIL + click value + ref length), an
    ANALYZE button, and a results panel surfacing extreme spread
    (mm/in/angular), mean radius, COI offset (H/V), suggested clicks,
    precision category, and a not-calibrated warning when no reference is
    set.
- **Rewire**: the inline mock in `scope_calibration_screen.dart` was removed
  (`_analyzeShotGroup` + `_pickShotGroupImage` + `_takeLiveTargetPhoto` +
  dead `_referenceScale`/`_targetDistance`/`_bulletCaliberController`/
  `_analysisResults` state). The inline analyzer section now renders a
  compact explainer + an "OPEN CALIBRATED ANALYZER" button (and a
  tap-to-load image tile) that `Navigator.push`es
  `ShotGroupAnalyzerScreen`, passing through any already-captured image.
  Unused `image_picker` import and `scope_calibration_screen` dashboard
  import dropped.
- **Dashboard wiring**: a "🎯 Shot Group Target Analyzer" `DashboardFeature`
  card was added to `hunter_dashboard.dart` (reachable directly from the
  hunter home, since the scope-calibration card had been commented out).
- **Tests**: `test/shot_group_analyzer_test.dart` — 11 tests covering COI
  centroid, extreme spread (incl. recorded shot pair), mean radius, the
  1.047in@100yd MOA definition, the 3.6in@100yd MIL definition, meters→MOA,
  COI offset sign convention (image-y-down → low COI is negative "up"),
  uncalibrated (zero angular, valid px), empty list, precision category, and
  real shot-hole blob detection on a synthetic target (3 holes found, 2 dust
  specks rejected). **All 11 pass.**
- **`flutter analyze`** (local 3.44.9): **0 errors, 0 warnings in all changed
  files** (project total 296 issues, all pre-existing infos/warnings in
  unrelated files — down from the 320 baseline since the mock removal dropped
  several infos). New service + overlay + screen + test are analyzer-clean.
- Files: `lib/features/hunter_mode/services/shot_group_analyzer_service.dart`
  (new), `lib/features/hunter_mode/widgets/shot_group_target_overlay.dart`
  (new), `lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`
  (new), `lib/features/hunter_mode/screens/scope_calibration_screen.dart`
  (mock removed, rewired), `lib/features/hunter_mode/hunter_dashboard.dart`
  (dashboard card + import cleanup), `test/shot_group_analyzer_test.dart`
  (new). No Firestore/Storage/rules changes (pure on-device CV, no backend).

## Phase 8 — Ballistic Engine Muzzle Velocity & BC Calculations (added 2026-08-13)

- The ballistics solver had two independent, simplified trajectory models
  and **no drag-curve selection, no ICAO atmosphere, no powder-temperature
  muzzle-velocity correction, and no energy output**:
  - `BallisticSolverService` (`lib/features/hunter_mode/services/ballistic_solver_service.dart`)
    used a single hardcoded drag formula with a BC scalar and an air-density
    factor derived from **barometric pressure only** (ρ/ρ₀ ≈ P/P₀, no
    temperature / humidity / altitude). Its trajectory table carried only
    drop / MOA / clicks.
  - The inline `BallisticPhysicsEngine` (`lib/features/ballistics/presentation/ballistic_calc_screen.dart`)
    used an ad-hoc altitude + temperature heuristic for density and an
    exponential velocity-decay model with no windage energy, no MOA/MIL, no
    pressure / humidity inputs.
- Item #14 added a single, pure-dart, physically-grounded engine and routed
  both consumers through it.
- **New engine** `lib/features/ballistics/data/ballistics_engine.dart`
  (`BallisticsEngine`, singleton `instance`; pure dart, no deps):
  - **`DragModel` enum** (`g1`, `g7`) — the Ingalls G1 (flat-base) and McCoy
    G7 (boat-tail / VLD) standard drag functions, embedded as
    Mach→G(Mach) tables with linear interpolation. The retardation is
    `a = -(ρ/ρ₀)·(G(M)·1e-4)·v²/BC` (the 1e-4 factor restores the published
    drag-function's 1/ft units; v in ft/s, result converted back to m/s²).
  - **`Atmosphere`** model + **ICAO air density**: `airDensity()` computes
    `ρ = (P_d·M_d + P_v·M_v)/(R·T)` with water-vapour partial pressure via
    the **Tetens saturation-vapour-pressure formula** (humidity correction).
    `airDensityRatio()` returns ρ/ρ₀ against the ICAO sea-level standard
    (1.225 kg/m³). Inputs: ambient temperature (°C), barometric pressure
    (hPa), relative humidity (%), altitude (m).
  - **Density altitude**: `densityAltitude()` — the ICAO standard-atmosphere
    altitude that has the same density as the given (non-standard) air,
    combining the station altitude, the temperature offset vs. the ISA
    standard temperature at that altitude, and a humidity contribution.
  - **Powder-temperature muzzle-velocity correction**:
    `muzzleVelocityForPowderTemp()` — `ΔV = tempCoefficient·ΔT` where ΔT is
    in °F and the coefficient is in fps/°F (default 1.5 fps/°F, typical
    smokeless powder), converted to m/s. Defaults to the ICAO reference
    temperature (15 °C).
  - **Trajectory integration**: `trajectoryTable()` — numerical point-mass
    integration (0.5 ms fixed time step) of the 2D equations of motion with
    the Mach-dependent G1/G7 drag, ICAO density-ratio scaling, incline
    (cos-pitch) gravity correction, crosswind drift, and a bore-elevation
    zero solved from the zero range. Output per range step (50 m default,
    0–1000 m): `TrajectoryPoint` with drop (cm, + = below LOS), windage (cm),
    remaining velocity (m/s), **kinetic energy (Joules, ½·m·v², m from
    grains)**, and time of flight (s). Velocity-floor guard prevents drag
    reversal for extreme inputs.
- **Integration**:
  - `BallisticSolverService.calculateScopeAdjustments` gained optional named
    params (`dragModel`, `temperatureCelsius`, `relativeHumidity`,
    `altitudeMeters`, `powderTempCelsius`, `powderTempCoefficientFpsPerF`,
    `bulletWeightGrains`) — all defaulted so existing call sites (e.g.
    `scope_calibration_screen.dart`) compile unchanged. The returned map now
    also carries `dragModel`, `densityAltitudeMeters`,
    `correctedMuzzleVelocityFps`, and the atmosphere inputs; the single-point
    drop now uses the powder-temp-corrected muzzle velocity.
  - `BallisticSolverService.generateTrajectoryTable` now delegates to the new
    engine (yards↔metres at the API boundary) and each row gains `dropCm`,
    `windageCm`, `velocityMs`, `velocityFps`, `energyJoules`,
    `timeOfFlightSeconds`, `rangeMeters` (in addition to the legacy
    `range`/`dropInches`/`moa`/`clicks`).
  - The inline `BallisticPhysicsEngine` in `ballistic_calc_screen.dart` was
    refactored to delegate `generateTrajectoryGrid` to `BallisticsEngine`
    (preserving the legacy bullet-weight / muzzle-velocity BC heuristic on
    top of the published BC); `calculateAirDensityRatio` now routes through
    the ICAO atmosphere. `TrajectoryPoint` gained `energyJoules`.
- **UI** (`ballistic_calc_screen.dart`): added a **G1/G7 `SegmentedButton`**
  drag-model selector and sliders for **barometric pressure (hPa)**,
  **relative humidity (%)**, and **powder temperature (°C)** alongside the
  existing altitude / ambient-temp / zero-distance / muzzle-velocity / bullet
  weight controls. The analytics summary card now surfaces **remaining
  velocity at target range**, **remaining energy at target range**, the
  selected **drag model**, the **density altitude (ICAO)**, and a full
  atmospheric profile string (altitude / temp / pressure / humidity).
- **Tests**: `test/ballistics_engine_test.dart` — **18 tests, all pass**:
  - ICAO air density (standard sea level ≈ 1.225; altitude/pressure/humidity
    effects), density altitude (standard ≈ 0 m; hot/cold/high-altitude),
    powder-temperature MV correction (reference-temp no-op; hot powder raises
    MV by the expected ~32.9 m/s for a 40 °C delta at 1.5 fps/°F).
  - Trajectory table (one row per step; zero range ≈ 0 drop; monotonic
    velocity decay; energy follows ½·m·v² and decays).
  - **G1 vs G7 drag curves**: G7 retains more velocity and yields less drop
    than G1 at extended range (the low-drag boat-tail curve is flatter).
  - **Atmospheric density altitude affects trajectory**: thin air (high
    density altitude / low pressure) yields higher retained velocity and
    less drop than dense sea-level air.
- **`flutter analyze`** (local 3.44.9): **0 errors, 0 warnings in all
  changed files** (project total 295 issues, all pre-existing infos/warnings
  in unrelated files — down 1 from the 296 baseline). New engine + service
  + screen + test are analyzer-clean. The 4 failing pre-existing tests
  (`saps_tracker`, `offline_sync_queue` [fake_cloud_firestore 4.1.1 mock
  incompat], `advanced_ballistics`, `bluetooth_mesh`) are unchanged and
  unrelated to this work.
- Files: `lib/features/ballistics/data/ballistics_engine.dart` (new),
  `lib/features/hunter_mode/services/ballistic_solver_service.dart`
  (engine integration + new params + richer outputs),
  `lib/features/ballistics/presentation/ballistic_calc_screen.dart`
  (engine delegation + G1/G7 + pressure/humidity/powder-temp UI + energy/DA
  summary), `test/ballistics_engine_test.dart` (new). No Firestore / Storage
  / rules changes (pure on-device ballistics, no backend).

## Phase 9 — Outfitter Client Roster & Guided Hunt Logs (added 2026-08-13)

- The outfitter suite had no dedicated client roster and no guided-hunt
  harvest logging. `ClientBooking` was lodge-only (name + contact + lodging/
  vehicle, no passport/ID, no permit references, no assigned package). The
  `CarcassRecord` (SQLite `carcass_records`, read by the Slaghuis Matrix)
  carried only a `hunterId` placeholder string (`'CURRENT_SESSION_ID'`).
  Item #17 added the full client roster + harvest-logging workflow and
  explicitly tied each harvest to a roster client and onward to venison
  permits + the slaughterhouse manifest.
- **New models** (`lib/features/outfitter_mode/data/models/`):
  - `ClientProfile` — the PH's client hunter book entry: `outfitterId`,
    `fullName`, `idPassportNumber`, `nationality`, `cellNumber`, `email`,
    `address`, optional `assignedPackageId`/`assignedPackageName`/
    `assignedBookingId`, a running `permitReferenceIds` list, `notes`,
    timestamps. `fromFirestore` (now delegates to a snapshot-free
    `fromMap(data, {id})`), `toMap`, `copyWith`.
  - `GuidedHuntLog` — a guided-hunt harvest entry: `outfitterId`,
    `clientId`/`clientName`/`clientIdPassport` snapshot, optional `bookingId`,
    `species`, `sex`, `carcassWeightKg`, `shotLocationDescription` +
    `shotLat`/`shotLng`, `trophyMeasurementInches`/`trophyMeasurementLabel`/
    `trophyPhotoUrls`, `shotPlacement`, `rifleCalibreMm`, `distanceMeters`,
    cross-reference ids `permitId` + `carcassRecordId`, `notes`, `huntDate`,
    timestamps. Same `fromMap`/`toMap`/`copyWith` shape.
- **New services** (`lib/features/outfitter_mode/data/services/`):
  - `ClientRosterManager` (singleton) — `client_roster` Firestore CRUD scoped
    by `outfitterId`: `getMyClientsStream` (reactive, ordered by `createdAt`
    desc, de-duplicated by doc id), `getClientById`, `addClient`,
    `updateClient` (merge), `deleteClient`, and `addPermitReference`
    (transactionally appends a permit id to the client's running list).
  - `GuidedHuntLogManager` (singleton) — `guided_hunt_logs` Firestore CRUD
    scoped by `outfitterId`: `getMyHuntLogsStream` (reactive, ordered by
    `huntDate` desc, de-duplicated), `getHuntLogById`, `addHuntLog`,
    `updateHuntLog`, `deleteHuntLog`, `linkPermit`, `linkCarcassRecord`, plus
    the two downstream bridges:
      * `buildPermitPrefill({log, client})` — assembles the prefill map
        (hunter block + farm block from the `outfitters` doc + the harvested
        species seeded into `speciesHuntedAndTransported`) that seeds a
        venison transport permit straight from the hunt log.
      * `pushToSlaughterhouseManifest(log)` — writes a `CarcassRecord` into
        the local SQLite `carcass_records` table the Slaghuis Matrix reads,
        using the client's `clientId` as `hunterId`, then links the new local
        id back onto the hunt log via `linkCarcassRecord`.
- **New screens** (`lib/features/outfitter_mode/presentation/`):
  - `ClientRosterScreen` — reactive, searchable roster. Tap a card to edit;
    remove with a confirmation modal (linked logs/permits are kept). "Add
    Client" sheet validates name (required) and captures passport/ID,
    nationality, cell, email, address, assigned package, notes.
  - `GuidedHuntLogScreen` — reactive, searchable hunt log. Each card shows
    species, client, date, carcass weight, trophy, shot location/placement
    and status chips ("Permit issued" / "In coldroom") or action chips
    ("Generate Permit", "Push to Manifest", "Delete"). The editor sheet
    requires a client selected from the active roster (blocks logging if the
    roster is empty) and captures species (required), sex, carcass weight,
    trophy measurement + label, shot location + lat/lng, shot placement,
    calibre, distance, hunt date, notes. "Generate Permit" builds the
    prefill map and opens `VenisonPermitFormScreen`; "Push to Manifest"
    pushes the carcass to the Slaghuis coldroom.
- **Venison permit linkage** (`venison_permit_form_screen.dart`): gained
  optional backward-compatible params `prefillData`
  (`Map<String,dynamic>?`), `clientId`, and `guidedHuntLogId`. When
  `prefillData` is present it is applied directly (no Firestore booking
  lookup) and seeds the species list; the hunter block + farm block are
  prefilled from the client + outfitter. After the permit is issued, if
  `guidedHuntLogId`/`clientId` were supplied, the form links the new permit
  id back onto the hunt log (`GuidedHuntLogManager.linkPermit`) and appends
  it to the client's `permitReferenceIds` (`ClientRosterManager.addPermitReference`)
  — end-to-end traceability client → hunt log → permit.
- **Dashboard**: two new cards on the outfitter dashboard
  (`outfitter_dashboard.dart`) — "Client Roster" and "Guided Hunt Logs" —
  placed immediately before the "Permit Log & Manager" card (the natural
  clients → hunt logs → permits grouping).
- **Firestore rules** (`firestore.rules`): new owner-scoped
  `match /client_roster/{clientId}` and `match /guided_hunt_logs/{logId}`
  blocks (`ownerOrAdmin('outfitterId')`).
- **Firestore indexes** (`firestore.indexes.json`): new composite indexes
  `client_roster` `(outfitterId ASC, createdAt DESC)` and `guided_hunt_logs`
  `(outfitterId ASC, huntDate DESC)` for the two stream queries (must be
  deployed: `npx firebase-tools deploy --only firestore:indexes`).
- **Tests**: `test/outfitter_client_roster_test.dart` — **6 tests, all
  pass**: `ClientProfile` + `GuidedHuntLog` `toMap`/`fromMap` round-trips
  (all fields), missing-field tolerance, `huntDate` fallback to now, and
  `copyWith` permit/carcass linking + `updatedAt` bump.
- **`flutter analyze`** (local 3.44.9): **0 errors, 0 warnings, 0 infos in
  all changed/new files** (project total 295, unchanged baseline — all
  remaining issues are pre-existing in unrelated files). The 4 pre-existing
  failing tests (`saps_tracker`, `offline_sync_queue`, `advanced_ballistics`,
  `bluetooth_mesh`) remain unchanged and unrelated.
- Files: `lib/features/outfitter_mode/data/models/client_profile.dart` (new),
  `lib/features/outfitter_mode/data/models/guided_hunt_log.dart` (new),
  `lib/features/outfitter_mode/data/services/client_roster_manager.dart` (new),
  `lib/features/outfitter_mode/data/services/guided_hunt_log_manager.dart` (new),
  `lib/features/outfitter_mode/presentation/client_roster_screen.dart` (new),
  `lib/features/outfitter_mode/presentation/guided_hunt_log_screen.dart` (new),
  `lib/features/hunter_mode/screens/venison_permit_form_screen.dart`
  (prefillData/clientId/guidedHuntLogId + post-issue linking),
  `lib/features/outfitter_mode/outfitter_dashboard.dart` (2 dashboard cards),
  `firestore.rules`, `firestore.indexes.json`,
  `test/outfitter_client_roster_test.dart` (new).
- Deploy reminder: the new `client_roster` / `guided_hunt_logs` rules +
  indexes must be deployed
  (`npx firebase-tools deploy --only firestore:rules,firestore:indexes`) in
  an environment with Firebase credentials. Until the indexes are built the
  roster / hunt-log streams surface the index-missing error in-UI (rather
  than silently showing empty).

## Phase 10 — Global Offline Firestore Persistence Audit (added 2026-08-13)

- **Audit findings**: `main.dart` already set
  `FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true)`
  inline, but with (a) no bounded `cacheSizeBytes`, (b) no web multi-tab
  persistence exception handling, and (c) no centralized helper. Web builds
  ARE configured (`web/` dir + `firebase_options.dart` `web` target), so the
  classic IndexedDB multi-tab `failed-precondition` ("multiple tabs open,
  persistence can only be enabled in one tab at a time") was a real crash
  risk. Most primary managers' streams also lacked a graceful error fallback
  for the case where a stream errors outright (missing composite index /
  offline-with-no-cache); several threw synchronously on an unauthenticated
  caller, bypassing the consumer `StreamBuilder`'s `hasError` branch.
- **Centralized `FirestoreBootstrap`** (`lib/core/services/firestore_bootstrap.dart`):
  - `initialize({cacheSizeBytes: 40 MB})` — called exactly once in `main()`
    after `Firebase.initializeApp()` and App Check, before any query. Sets
    `Settings(persistenceEnabled: true, cacheSizeBytes: …)` so every primary
    Firestore stream serves cached data first and keeps emitting from cache
    when the network drops; writes queue and flush on reconnect (the existing
    `OfflineSyncQueue` connectivity listener in `main.dart` already flushes
    the higher-level write queue).
  - **Web multi-tab guard**: wraps the settings assignment in try/catch. On
    web, when a second tab already owns the IndexedDB cache, the
    `failed-precondition` error is caught and the tab silently falls back to
    `Settings(persistenceEnabled: false)` (in-memory persistence) so the app
    still runs instead of crashing on startup. Native (Android/iOS) builds are
    unaffected (local SQLite cache, no multi-tab constraint); the catch is a
    safety net there too so a settings error never blocks startup.
  - Replaced the inline `Settings(persistenceEnabled: true)` assignment in
    `main.dart`; removed the now-unused `cloud_firestore` import from
    `main.dart`.
- **`OfflineStreamGuard`** (`lib/core/services/offline_stream_guard.dart`):
  - `offlineResilient<T>(source, {required fallback, debugLabel})` — wraps a
    stream so any hard error is logged and replaced with a single `fallback`
    emission, then the stream completes. Normal emissions pass through
    untouched. Firestore's own cache already keeps streams alive across brief
    network drops; this is the safety net for the cases where the stream
    errors outright (missing index, permissions change, web-no-persistence
    unrecoverable network error) so the UI shows a defined empty/zero state
    instead of hanging or crashing.
- **Managers hardened** (cache-first + offline fallback applied):
  - `VenisonPermitManager.getMyPermitsStream` — wrapped with the guard
    (fallback `[]`); `getPermitById` now reads **cache-first**
    (`GetOptions(source: Source.cache)`) then falls back to server, so an
    offline lookup still resolves a recently-viewed permit.
  - `MeatProcessingOrderManager.getMyOrdersStream` — wrapped (fallback `[]`).
  - `PricelistScannerService.getMyPriceListsStream` — wrapped (fallback `[]`);
    the unauthenticated `throw Exception` was replaced with a stable empty
    stream so it no longer crashes the history screen's `StreamBuilder`.
  - `PackageBookingManager.getMyPackagesStream` — unauthenticated `throw`
    replaced with `Stream.empty()` (the consumer already has a `hasError`
    branch for hard stream errors + Firestore cache keeps it alive offline).
  - `CarcassLogManager.getActiveChillerLogs` — null-user guard added
    (`Stream.empty()` instead of querying for a null `hunterId`).
  - `OutfitterAnalyticsService` — all four streams wrapped:
    `getRevenueSummaryStream` (fallback zero-metrics map),
    `getFilteredPackagesStream` (fallback `[]`),
    `getPendingBookingsCountStream` + `getTotalPackagesCountStream`
    (fallback `0`).
  - `OutfitterFirebaseService` (bookings/lodging/fleet) — already had
    `.handleError` fallbacks; unchanged.
  - `ClientRosterManager` + `GuidedHuntLogManager` (Phase 9) — already had
    `.handleError` returning cached/empty; unchanged.
- **Tests**: `test/offline_stream_guard_test.dart` — **5 tests, all pass**:
  normal emissions pass through; stream error replaced with fallback;
  no fallback on clean completion; typed list fallback for cache-failure
  recovery; stream completes after fallback (no hang).
- **`flutter analyze`** (local 3.44.9): **0 errors, 0 warnings, 0 infos in
  all changed/new files**. The only 2 warnings in touched files
  (`pricelist_scanner_service.dart:298` unnecessary_type_check +
  `outfitter_pricelist_scanner_screen.dart:166` unused `_showSuccess`) are
  **pre-existing** (verified present at commit `0a9a599` before this change,
  in code paths I did not touch). Project total 295, unchanged baseline.
  38 tests pass (5 new + 6 client roster + 18 ballistics + 9 theme).
- Files: `lib/core/services/firestore_bootstrap.dart` (new),
  `lib/core/services/offline_stream_guard.dart` (new),
  `lib/main.dart` (FirestoreBootstrap wiring + import cleanup),
  `lib/features/hunter_mode/services/venison_permit_manager.dart`
  (guard + cache-first getPermitById),
  `lib/features/hunter_mode/services/meat_processing_order_manager.dart`
  (guard),
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`
  (guard + throw→empty stream),
  `lib/features/hunter_mode/services/package_booking_manager.dart`
  (throw→empty stream),
  `lib/features/hunter_mode/services/carcass_log_manager.dart`
  (null-user guard),
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart`
  (4 streams guarded),
  `test/offline_stream_guard_test.dart` (new).
- No Firestore rules / index / Storage changes (this is a client-side
  persistence + resilience hardening pass).

## Phase 11 — Package Quantity Tracking & Automatic Sold-Out Status (added 2026-08-13)

- New inventory model for hunting packages: every package now carries a
  `quantityAvailable` slot count (default 1 for legacy docs) that decrements
  atomically on each booking, and a `soldOut` `PackageStatus` that flips on
  automatically when the count hits 0. This is Item #11 / the User Context of
  the master to-do (continuing the Item #10 Package CRUD Polish track).
- **`PackageStatus` enum** (`lib/features/hunter_mode/models/package_pricing.dart`):
  - Added `soldOut` variant; `fromString`/`label` round-trip `"sold_out"`.
    `fromString` falls back to `active` for null/unknown.
  - Added `bool isListed` getter (`active` → true; `draft`/`archived`/
    `deleted`/`soldOut` → false) so analytics/marketplace can branch on
    "is this a bookable listing".
- **`PackageQuantity` helper** (same file): type-safe parsing of the raw
  Firestore `quantityAvailable` value.
  - `fromData(dynamic)` — accepts int/double; returns `defaultQuantity` (1)
    for legacy docs (null), invalid types (String), and negatives; **0 is a
    real 0** (not masked back to 1) so the sold-out state renders correctly.
  - `isSoldOut({quantityAvailable, status})` — true when qty ≤ 0 OR status is
    `sold_out` (defends against stale reads where qty hasn't caught up to the
    transactional flip).
  - `remainingLabel(qty)` — "Sold Out" / "1 slot left!" / "N slots left!"
    for the marketplace + manager cards.
  - `defaultQuantity = 1` — legacy packages (pre-Phase-11) behave as
    single-slot: one booking decrements them to 0 → sold_out.
- **`PackageSoldOutException`** (same file): carries `packageId` + `message`,
    implements `Exception`. Thrown by the booking transaction when a
    hunter tries to book a package with no remaining slots; the marketplace
    catches it and surfaces a clear "sold out" snackbar instead of a generic
    failure message.
- **`PackageBookingManager`** (`lib/features/hunter_mode/services/package_booking_manager.dart`):
  - `publishPackage` — new required `int quantityAvailable` param (written to
    the doc as `quantityAvailable`).
  - `updatePackage` — new optional `int? quantityAvailable` param (omitted →
    field not touched, preserving existing inventory on an edit).
  - `bookPackage` — **rewritten as `FirebaseFirestore.instance.runTransaction`**
    for atomic inventory + status safety:
    1. Reads the package snapshot inside the transaction.
    2. Guard: throws `PackageSoldOutException` if `status != active` OR
       `quantityAvailable <= 0` (rejects concurrent / late bookings).
    3. Decrements `quantityAvailable` by 1; if the result is ≤ 0, atomically
       sets `status = 'sold_out'` in the same transaction.update so the
       marketplace flips to SOLD OUT the instant the last slot is taken
       (no race window between decrement and the status flip).
    4. Writes the booking doc + (deposit split) as before (the booking write
       itself is the transaction's post-commit side effect; the decrement is
       the transactional part).
  - `restockPackage({packageId, quantityAvailable})` — NEW. Sets the slot
    count back to a positive value AND re-activates a `sold_out` listing back
    to `active` in a single update (so the outfitter can reopen a sold-out
    package without editing each field). Wired to the manager's "Restock"
    action chip.
- **Marketplace stream filters**:
  - `OutfitterAnalyticsService.getFilteredPackagesStream` changed from
    `.where('status', isEqualTo: 'active')` →
    `.where('status', whereIn: ['active', 'sold_out'])` so hunters still SEE
    sold-out packages (with a SOLD OUT badge + disabled book button) rather
    than having them vanish mid-browse. `getAllPackages` updated the same way
    for consistency.
  - `getTotalPackagesCountStream` (outfitter analytics) still counts
    `status == 'active'` only — a sold-out package is correctly NOT counted
    as an available listing (it's no longer bookable). This is the intended
    semantic, not a bug.
- **Firestore rules** (`firestore.rules`, `packages/{packageId}` match block):
  the hunter-initiated `bookPackage` transaction calls `transaction.update` on
  the `packages` doc (to decrement `quantityAvailable` + flip status), which
  is a write by the hunter — normally only the owning outfitter can write
  packages. The rule was widened to allow a signed-in hunter to update the
  `quantityAvailable` and `status` fields only (field-level allowance); other
  fields remain outfitter-only. This is the minimal permission needed for the
  transactional decrement to succeed server-side.
- **Outfitter package creator/editor form**
  (`outfitter_package_creator_screen.dart`): added a `_quantityController`
  (integer input, "slots" suffix, ≥1 validation), with edit-mode prefill from
  the existing `quantityAvailable` field. Passed through to both
  `publishPackage` (required) and `updatePackage` (optional). Field placed
  after the deposit-percentage field.
- **Marketplace card** (`hunter_package_marketplace_screen.dart`,
  `_PackageCard`):
  - Computes `quantityAvailable` + `isSoldOut` from the doc data.
  - Price chip shows a red "SOLD OUT" badge below the total when sold out.
  - Meta chip row gains a `confirmation_number` / `do_not_disturb` icon chip
    with the `remainingLabel` ("5 slots left!" / "Sold Out").
  - "VIEW DETAILS & BOOK" button: when sold out, `onPressed` is `null`
    (disabled), background greyed, icon → `do_not_disturb`, label → "SOLD OUT".
- **Booking confirmation sheet** (same file, `_BookingConfirmationSheet`):
  - Shows a red sold-out banner ("This package is sold out…") above the
    action buttons when `isSoldOut`.
  - "BOOK THIS PACKAGE" button disabled (`onPressed: null`) + greyed when
    sold out.
  - `_confirmBooking` catch block detects `PackageSoldOutException` and shows
    a tailored "sold out" snackbar instead of the generic "Booking failed".
- **Outfitter package manager** (`outfitter_package_manager_screen.dart`):
  - Card meta line now includes the remaining-slots label.
  - `_statusBadge` switch gained the `soldOut → (Colors.red, 'SOLD OUT')` case.
  - New `_restock(packageId, currentQty)` method: prompts for a new slot count
    (≥1) and calls `restockPackage`, shown as a "Restock"
    (`add_shopping_cart`) action chip ONLY when the package is sold out or
    has ≤0 slots.
- **Tests** (`test/package_quantity_test.dart`, NEW — 24 tests, all pass):
  `PackageStatus.soldOut` label/fromString round-trip + isListed;
  `PackageQuantity.fromData` parsing (int/double/0-is-real-0/legacy-null/
  invalid-string/negative); `isSoldOut` (qty-0, stale-positive-with-sold_out-
  status, active-while-slots-remain, legacy-default); `remainingLabel`
  (sold-out/singular/plural); `PackageSoldOutException` (packageId/message/
  generic-catch); and a structural group encoding the exact
  decrement + sold-out-at-0 + rejection rules that the `bookPackage`
  transaction applies (multi-slot stays active, last slot flips to sold_out,
  0-slot rejects new bookings, legacy single-slot behavior) — runnable
  without the Firestore emulator (which can't run in this sandbox, see the
  environment-constraints note) by exercising the shared helpers the
  transaction reads through.
- **`flutter analyze`**: 0 errors, 13 warnings (all pre-existing, NONE in any
  modified file), 283 infos. New test file is analyzer-clean.
- **`flutter test`**: `package_quantity_test.dart` 24/24 pass; the previously-
  passing suites (`offline_stream_guard_test`, `theme_controller_test`,
  `outfitter_client_roster_test`, `financial_engine_test`, etc.) still green.
  The only failing suite is `test/features/sync/bluetooth_mesh_test.dart`
  (4 failures on `mockStorage.insertLog.length` assertions) — pre-existing,
  unrelated (zero references to package/booking code; the file is unmodified
  in this session; tests the offline bluetooth mesh sync subsystem).
- Deploy reminder: the `packages` Firestore rule change (hunter field-level
  decrement allowance) needs `npx firebase-tools deploy --only firestore:rules`
  in a credentialed env. No new indexes required (the `whereIn` on `status`
  is a single-field equality-range query that uses the automatic index).
  Until the rule deploys, `bookPackage`'s transactional update will be
  rejected server-side with a permission error (surfaced as the generic
  "Booking failed" snackbar); the client-side sold-out guard still prevents
  double-booking in the happy path.
- Files: `lib/features/hunter_mode/models/package_pricing.dart`,
  `lib/features/hunter_mode/services/package_booking_manager.dart`,
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`,
  `firestore.rules`, `test/package_quantity_test.dart` (new).


## Phase 12 — Global Bottom SafeArea & Scroll Padding Audit (added 2026-08-13)

- **Problem**: on many screens the bottom-most content (cards, buttons, list
  items) rendered under the Android 3-button nav bar / iOS home-indicator
  gesture line because the `Scaffold.body` scrollable either lacked a
  `SafeArea(bottom: true)` wrapper or used a fixed `padding` (e.g.
  `EdgeInsets.all(16)` / `symmetric(horizontal: ...)`) with no bottom safe-area
  inset, so the last child sat at the very screen edge.
- **Reusable helper** `lib/core/widgets/safe_bottom_inset.dart` (NEW):
  - `SafeBottomInset.of(context)` -> `MediaQuery.padding.bottom + 24.0`
    (the +24 breathing room is the standard tail inset appended to scroll
    content so it scrolls cleanly above the gesture bar).
  - `SafeBottomInset.paddingFor(context, {horizontal, top})` -> ready-made
    `EdgeInsets` for a scrollable's `padding`.
  - All body-level scrollables now use this instead of a hard-coded bottom,
    so the inset adapts to each device's nav-bar/gesture height (0 on
    devices with hardware keys, up to ~48px on gesture-nav phones).
- **Audit method**: enumerated every `body:` across `lib/` (66 Scaffolds) and
  classified each:
  - **SafeArea-wrapped bodies** (bottom:true is the default — verified NO
    `SafeArea(bottom: false)` exists anywhere in `lib/`) were left as-is;
    `SafeArea` already reserves the gesture-bar inset, satisfying the
    "SafeArea OR padding" requirement. These include auth, role-selection,
    animal list/detail, ballistic calc, ammunition screens, bulk CSV import,
    create-user, privacy policy, field estimate, trophy room/detail, add/edit
    trophy, saps tracker, meat processing, carcass matrix, etc.
  - **Direct-body scrollables WITHOUT SafeArea** and **Column bodies with an
    inner `Expanded` scrollable** were the real cut-off culprits and got the
    bottom inset applied to their scrollable's `padding`.
- **Screens fixed** (body scrollable `padding` bottom made safe-area-aware):
  - Hunter: `firearm_detail_screen.dart` (body ListView),
    `hunter_package_marketplace_screen.dart` (package list + my-bookings list),
    `hunter_trophy_browser_screen.dart`, `hunter_custom_package_builder_screen.dart`,
    `mesh_radar_screen.dart`, `scope_calibration_screen.dart`,
    `custom_handloads_form_screen.dart`, `outfitter_trophy_stock_screen.dart`,
    `outfitter_enterprise_panel_screen.dart`, `outfitter_revenue_screen.dart`
    (analytics), `scanned_pricelist_history_screen.dart` (analytics),
    `outfitter_booking_dashboard_screen.dart`, `outfitter_package_creator_screen.dart`
    (form), `outfitter_package_manager_screen.dart`, `outfitter_pricelist_verification_screen.dart`,
    `firearm_maintenance_screen.dart` (two tab ListViews).
  - Outfitter: `outfitter_dashboard.dart` (Container->Padding->ListView) AND
    `presentation/outfitter_dashboard.dart` (duplicate dashboard — both fixed
    for consistency).
  - Admin: `admin_dashboard_screen.dart` (RefreshIndicator->ListView; was
    hard-coded bottom:32, now `SafeBottomInset.of(context)`).
- **Already-safe (verified, left unchanged)**: `hunter_dashboard.dart` and
  `hunter_profile_screen.dart` already used `+ MediaQuery.padding.bottom`;
  the permit-log / guided-hunt-log / client-roster lists already used a
  generous `bottom: 80-96` (FAB clearance, well above the gesture bar);
  camera/map `Stack` bodies (blood tracker, spoor HUD, weather, license
  scanner, offline nav) are intentionally full-bleed overlays.
- **`flutter analyze`**: **0 errors**, 13 warnings (all pre-existing —
  `unused_local_variable`/`unused_element`/`unnecessary_cast` in unrelated
  files; the single `outfitter_trophy_stock_screen.dart:87 unnecessary_cast`
  is in pre-existing code, NOT in the padding edit). 282 infos (no new issues
  introduced; the new helper file is analyzer-clean).
- **Tests**: `test/package_quantity_test.dart` 24/24 pass; pre-existing suites
  unaffected (pure UI padding change, no logic touched).
- Files: `lib/core/widgets/safe_bottom_inset.dart` (new) + the 18 screen files
  listed above (import + one `padding:` edit each).

## RBAC — role-based access control & route guards (added 2026-08-13)

- Centralized the "who is the current user" question in a new
  `lib/features/auth/services/user_role_provider.dart`:
  - `enum AppRole { admin, outfitter, hunter, unknown }` with
    `AppRole.fromString` (collapses null / unknown → `unknown`).
  - `UserRoleProvider` singleton — the single cached source of truth for the
    resolved role. `resolveRole({forceRefresh})` fetches the role on login in
    this order: (1) not signed in → `unknown`; (2) admin email allow-list
    (`admin@jag-spoor.co.za`) → `admin`; (3) `AdminAuthGuard` admin claim /
    Firestore flag → `admin`; (4) `users/{uid}.role` → the stored role;
    (5) fetch error → `unknown`. Result cached for the process lifetime.
    `setRole(role)` lets role-selection cache the freshly chosen role
    without a re-fetch; `reset()` clears it on sign-out. Firestore/Auth are
    lazily resolved via getters so touching the provider in a unit test
    (pre-Firebase-init) does not throw; `@visibleForTesting injectForTesting`
    + `testUid`/`testEmail` override exercise the Firestore path with
    `FakeFirebaseFirestore`.
- Separated the "what may they do" policy into a pure, dependency-free
  `lib/features/auth/services/role_guard.dart` (no Firebase / Flutter imports
  → fully unit-testable):
  - `RoleGuard.canAccess(role, route)` — **admins short-circuit to `true` for
    EVERY route** (Hunter, Outfitter, Admin Portal, plus all forms/screens),
    so an admin can never trigger an Access Denied banner. Below that:
    admin-only routes (`/admin_dashboard`) deny every non-admin; the Hunter /
    Outfitter dashboards require the matching non-admin role; all other routes
    default to allowed. → Hunters cannot open the Admin Portal or Outfitter
    Management; Outfitters default to Outfitter Mode and cannot open
    Hunter / Admin; Admins have full cross-mode access to all three.
  - `RoleGuard.defaultHomeFor(role)` — where an unauthorized user is bounced
    (`unknown` → `/role_selection`, never dropped on a dashboard).
  - `RoleGuard.canSwitchModes(role)` — only `admin` may use the instant mode
    switcher.
  - `RoleGuard.accessDeniedMessage(role, route)` — route-tailored notice text.
- New `lib/features/auth/widgets/role_guarded_route.dart` — `RoleGuardedRoute`
  widget wraps a route `builder`. On mount it resolves the role (if not yet
  resolved — covers deep-link cold launches), checks `RoleGuard.canAccess`,
  and on DENIAL redirects cleanly to `defaultHomeFor(role)` via
  `pushReplacementNamed` with a floating red "Access Denied: …" SnackBar —
  instead of rendering a screen the user may not use. Awaiting resolution
  shows a centered `CircularProgressIndicator`.
- Wired route guards in `main.dart`: `/hunter_dashboard`,
  `/outfitter_dashboard`, `/admin_dashboard` builders are each wrapped in
  `RoleGuardedRoute(route:, builder:)`. All three dashboards are now
  route-level protected.
- `core/splash_screen.dart` now resolves the role ONCE via
  `UserRoleProvider.instance.resolveRole(forceRefresh: true)` and routes by
  `AppRole` (admin→admin, hunter→hunter, outfitter→outfitter, unknown→role
  selection). Removed the duplicated direct Firestore read; the cached role
  is then read by the dashboard route guards.
- `role_selection_screen.dart` caches the chosen role:
  - admin bypass → `setRole(AppRole.admin)` before navigating.
  - hunter/outfitter confirm → writes `users/{uid}.role`, then
    `setRole(outfitter|hunter)` so the destination route guard admits the
    user immediately (the Firestore write may not be readable for a few
    hundred ms).
- `AdminModeSwitcher._switchTo` (admin instant switcher) gained a
  defense-in-depth re-check: `RoleGuard.canSwitchModes(role)` before
  navigating; a non-admin (stale render / programmatic tap) is blocked with
  an access-denied SnackBar instead of switching modes. The switcher button
  remains admin-gated at the dashboard level.
- Sign-out clears cached role state: `AuthGateService.signOut()` and
  `AdminAnalyticsService.signOut()` now call `UserRoleProvider.instance.reset()`
  + `AdminAuthGuard.instance.reset()` so the next sign-in re-resolves from
  scratch (no role bleed between sessions).
- The `AdminDashboardScreen` keeps its own `AdminAuthGuard` bootstrap-check as
  defense-in-depth, but the primary enforcement is now the route guard (which
  redirects unauthorized users before the screen mounts).
- **`flutter analyze`**: 0 errors, 13 warnings (all pre-existing, unchanged;
  no new issues in the new/modified files).
- **Admin cross-mode access fix (2026-08-13)**: `RoleGuard.canAccess` was
  restructured so `AppRole.admin` short-circuits to `true` at the TOP of the
  method — admins now have guaranteed full access to Hunter, Outfitter, AND
  Admin routes (plus every other screen) and can never trigger an Access
  Denied banner. Previously admin was admitted per-branch on each dashboard
  route, which worked but was implicit and fragile against future admin-only
  routes. The non-admin branches were tightened accordingly (admin-only
  routes deny all non-admins; hunter/outfitter dashboards require the exact
  matching non-admin role). `test/role_guard_test.dart` gained an explicit
  "admin may access <route>" sweep over 7 representative routes.
- **Tests** (all green locally, Flutter 3.44.9):
  - `test/role_guard_test.dart` (31 tests) — `AppRole.fromString` parsing +
    `RoleGuard.canAccess` / `defaultHomeFor` / `canSwitchModes` /
    `accessDeniedMessage` for admin, outfitter, hunter, and unknown profiles
    across admin-only, hunter, outfitter, and non-restricted routes, plus an
    explicit admin-full-cross-mode-access sweep over 7 representative routes.
  - `test/user_role_provider_test.dart` (7 tests) — provider default state,
    `setRole` caching for all three roles, `resolveRole` cache-hit contract
    (returns cached role without touching Firebase), and `reset`.
  - Note: the Firestore `users/{uid}.role` fetch in `resolveRole` is a
    one-line read + `AppRole.fromString` (whose mapping is covered by the
    role_guard tests). A `fake_cloud_firestore`-backed resolution suite is
    not included because `fake_cloud_firestore 4.1.1` does not compile against
    the locally-resolved `cloud_firestore 6.7.1` in this sandbox (pre-existing
    dep skew; same reason `offline_sync_queue_test.dart` can't compile here).
    It compiles/runs in CI under the Flutter 3.29.1 pin.
- Files: `lib/features/auth/services/user_role_provider.dart` (new),
  `lib/features/auth/services/role_guard.dart` (new),
  `lib/features/auth/widgets/role_guarded_route.dart` (new),
  `lib/main.dart`, `lib/core/splash_screen.dart`,
  `lib/features/auth/role_selection_screen.dart`,
  `lib/features/admin/widgets/admin_mode_switcher.dart`,
  `lib/features/admin/services/admin_analytics_service.dart`,
  `lib/features/authentication/services/auth_gate_service.dart`,
  `test/role_guard_test.dart` (new), `test/user_role_provider_test.dart` (new).

## StreamBuilder initialization safeguards (added 2026-08-13)

- Audited all `StreamBuilder`/`FutureBuilder` call sites (34 files) for the
  "initialization crash in lazy list/sliver items" pattern: stream getters
  that pass `null`, throw synchronously, or leak single-subscription stream
  errors to the widget. Findings + fixes:
  - **`OutfitterRevenueScreen._combinedAnalyticsStream`** (CRASH): dereferenced
    `_currentUserId!` at the top of the `async*` generator — a
    `NullCheckException` when the uid was unresolved (manager w/ no uid,
    pre-auth mount, or post-sign-out). Now guards `uid == null` and yields a
    stable empty payload `{'revenue':{}, 'enterprise':{}, 'speciesRevenue':[],
    'monthlyStats':[]}` so the screen renders zero-state metrics instead of
    the "Error loading analytics" banner.
  - **`OutfitterFirebaseService`** (5 stream getters: bookings/lodging/fleet/
    vacant-lodging/active-fleet): had NO auth guard and only `.handleError`
    (not the project's `OfflineStreamGuard`). Hardened: each getter now
    returns `Stream.value(const <T>[])` when `_auth.currentUser == null`
    (unauthenticated / pre-auth / post-sign-out), and the live Firestore
    stream is wrapped in `OfflineStreamGuard.offlineResilient(..., fallback:
    const <T>[])` so a hard error (missing index / permissions / offline w/
    no cache) serves an empty list instead of propagating to the
    `StreamBuilder`. Matches the pattern already used by
    `ClientRosterManager`, `GuidedHuntLogManager`, `MeatProcessingOrderManager`,
    `PricelistScannerService`, `VenisonPermitManager`, `PackageBookingManager`,
    `OutfitterAnalyticsService`.
  - **`AmmunitionTypeSelectionScreen._buildFactoryAmmoStream`**:
    `.where('caliber', whereIn: caliberVariations)` threw a Firestore
    "A non-empty array is required for 'whereIn'" error when the firearm had
    no caliber (empty variants). Now returns `const Stream.empty()` when
    `caliberVariations.isEmpty`, so the dropdown renders its empty/warning
    state cleanly (the builder's `snapshot.hasError` branch no longer fires).
  - **`AnimalRepository.watchAnimals`**: wrapped the `animals` snapshots
    stream in `OfflineStreamGuard.offlineResilient(..., fallback: const
    <Animal>[])` for offline resilience + consistency. The two consumers
    (`animal_list_screen`, `add_trophy_screen`) already had `snapshot.hasError`
    branches; the guard converts hard errors to a clean empty list.
- **Verified safe (no change needed)** — call sites already null-safe:
  - `ammunition_screen.dart` is the gold-standard pattern:
    `_currentUserId != null ? ...snapshots() : const Stream.empty()` + hasError.
  - `InventoryBridge.watchSafeFirearms`/`watchAvailableAmmunition`:
    null-uid → `Stream.value([])`, empty rifleId → local fallback, `.handleError`.
  - `ClientRosterManager`/`GuidedHuntLogManager`: null-uid →
    `Stream.value(const [])` + `.handleError` + doc-id de-dup.
  - `PackageBookingManager.getMyPackagesStream`: null-uid →
    `const Stream.empty()` (documented).
  - Chat `StreamBuilder`s inside expandable list items
    (`outfitter_booking_dashboard_screen`, `hunter_package_marketplace_screen`):
    `bookingId` is a non-nullable `String`, so `.doc(bookingId)` never throws;
    builders have `snapshot.hasError` branches.
  - `snapshot.data!.docs` usages (`spoor_identifier_screen`,
    `ballistic_calc_screen`, `slaghuis_matrix_screen`) are all gated by
    `!snapshot.hasData` first.
- **`flutter analyze`**: 0 errors, 13 warnings (all pre-existing in unmodified
  files; none in the 4 changed files).
- **Tests**: `flutter test` → 201 passed, 4 failed. All 4 failures are
  **pre-existing** (verified by stashing the changes and re-running on the
  prior commit `17af183` — identical 4 failures): `saps_tracker_test`
  (status-string conversion), `advanced_ballistics_test` (density assertion),
  `bluetooth_mesh_test` (mesh-sync assertion), `offline_sync_queue_test`
  (fake_cloud_firestore/cloud_firestore compile skew). None touch the 4
  changed files. RBAC + offline-guard + package + theme suites (76 tests) all
  green.
- Files: `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`,
  `lib/features/outfitter_mode/data/services/outfitter_firebase_service.dart`,
  `lib/features/ballistics/presentation/ammunition_type_selection_screen.dart`,
  `lib/repositories/animal_repository.dart`.

## Broadcast-stream audit — "Bad state: Stream has already been listened to" (added 2026-08-13)

- Crash: `Bad state: Stream has already been listened to.. Error thrown
  building Expanded(flex: 1)`. Root cause: a **single-subscription** stream
  instance cached as a `late Stream` field in a `State` class, passed to a
  `StreamBuilder`. Firestore `.snapshots()` (and `InventoryBridge
  .watchSafeFirearms()`'s `.snapshots().map().handleError()` chain) return
  single-subscription streams. If the `StreamBuilder` is ever re-mounted
  (disposed + recreated at the same position, e.g. parent tree restructure,
  conditional show/hide, or theme-toggle rebuild) while the `State` persists,
  the new `StreamBuilder` calls `widget.stream.listen(...)` on the
  already-listened single-subscription stream → throws. (Verified: a raw
  `StreamController.stream` throws on a second `.listen()` even after the
  first subscription is cancelled.)
- Audit: grepped the whole `lib/` tree for cached stream fields
  (`late Stream<...> _x`, `Stream<...> _x`, `Stream get x => _field`).
  Exactly **three** cached single-subscription stream instances existed:
  - `ballistic_calc_screen.dart` — `_firearmsStream` (firearms `.snapshots()`)
    and `_factoryAmmoStream` (factory_ammunition `.snapshots()`), both
    assigned once in `initState`, consumed by `StreamBuilder(stream: _x)`.
  - `scope_tools_bottom_sheet.dart` — `_firearmsStream`
    (`_inventoryBridge.watchSafeFirearms()`), same pattern.
- **Verified safe (no change needed):**
  - All `StreamController` fields in services are already `.broadcast()`:
    `outfitter_sync_service` (`_syncStatusController`,
    `_dirtyRecordsController`), `bluetooth_mesh_sync_service` (all three).
    Their getters (`dirtyCountStream`, `dirtyRecordsStream`,
    `ingestionStream`, `peerCountStream`) return broadcast streams.
  - `SignalHudWidget` listens to `dirtyCountStream` (broadcast) via manual
    `.listen()` + cancels in `dispose()` — multi-instance safe.
  - `OfflineStreamGuard.offlineResilient()` returns a fresh
    single-subscription `StreamController.stream` **per invocation**; every
    manager calls it inline in its getter (fresh stream per `build`), so the
    stream instance is never shared across `StreamBuilder`s or remounts.
  - All other `StreamBuilder(stream: ...)` sites call a fresh getter per build
    (`_repo.watchAnimals()`, `_manager.getMyClientsStream()`,
    `_service.getVacantLodgingStream()`, `PackageBookingManager.instance
    .getMyPackagesStream(status:)`, `_combinedAnalyticsStream()` `async*`,
    inline `.snapshots()`, etc.) — fresh instance each build → no sharing.
  - Chat `StreamBuilder`s inside expandable list-item cards use a fresh
    `_bookingQuery.snapshots()` per card `State` → no cross-card sharing.
- Fix applied: wrapped each cached stream in `.asBroadcastStream()` at the
  `initState` assignment. `asBroadcastStream()` converts the single-subscription
  source into a multi-subscription broadcast stream that tolerates (a) multiple
  simultaneous listeners and (b) listen → cancel → re-listen without throwing
  (empirically verified: a raw single-sub stream throws on second listen, but
  `source.asBroadcastStream()` allows re-subscribe after cancel). The broadcast
  wrapper listens to the underlying Firestore stream exactly once for the
  `State`'s lifetime and re-attaches listeners as `StreamBuilder`s mount/unmount.
- `flutter analyze`: 0 errors, 13 warnings (all pre-existing, none in changed
  files). `flutter test`: 201 passed, 4 pre-existing failures (saps_tracker,
  offline_sync_queue, advanced_ballistics, bluetooth_mesh — identical to the
  prior commit; none touch the changed files).
- Files: `lib/features/ballistics/presentation/ballistic_calc_screen.dart`,
  `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`.

## Manage Farms & Managers — farm selection & editing (added 2026-08-13)

- The "Registered Farms" block in
  `outfitter_enterprise_panel_screen.dart` previously rendered static,
  non-interactive farm cards. Each card is now **tappable** (whole card
  wrapped in `Material > InkWell` with a tap → edit sheet) AND carries an
  explicit **EDIT** `TextButton.icon`.
- New **Edit Farm sheet** (`_showEditFarmSheet(data, farmId)`): a
  `showModalBottomSheet` + `StatefulBuilder` form pre-filled from the farm
  doc, with validated fields for: Farm Name * (required), District, Province,
  Size (hectares, decimal-validated → `double?`), Contact Number (phone),
  Registration Number. Uses `isScrollControlled: true` + `viewInsets.bottom`
  padding so the keyboard never covers the save button. The SAVE button
  shows a spinner + `SAVING…` label while the update is in flight
  (`_isUpdatingFarm`).
- `_submitFarmEdit()` validates the form, parses/validates the size, then
  calls `OutfitterEnterpriseManager.instance.updateFarm(...)`. On success it
  pops the sheet + shows a success snackbar; on failure it surfaces the error
  and keeps the sheet open so the user can retry. The Registered Farms list
  refreshes **automatically** — it is already a reactive Firestore
  `snapshots()` `StreamBuilder`, so the `updateFarm` write triggers a re-render
  with no manual `setState`/reload needed.
- New `OutfitterEnterpriseManager.updateFarm({farmId, name, district,
  province, sizeHectares?, contactNumber?, registrationNumber?})`: validates
  auth + farmId + name, then `_firestore.collection('farms').doc(farmId)
  .update({...})` with `updatedAt: serverTimestamp()`. Optional fields are
  written as `null` when blank (clears stale values). `firestore.rules`
  already permits `update, delete` for `isAdmin() || isOwnerOf('outfitterId')`
  on `farms/{farmId}` — no rules/index change required.
- Card UI extended to surface the new fields inline: a `Wrap` of detail chips
  (size `ha`, contact number, registration number) renders below a divider
  **only when at least one of those fields is set** on the document, so legacy
  farms (created before these fields existed) render cleanly without empty
  chips. New `_farmDetailChip(icon, label, theme)` helper.
- `flutter analyze`: 0 errors, 13 warnings (all pre-existing, none in changed
  files). `flutter test`: 201 passed, 4 pre-existing failures (saps_tracker,
  offline_sync_queue, advanced_ballistics, bluetooth_mesh — none touch the
  changed files).
- Files: `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`.

## Trophy Stock Inventory — farm stock editing & PDF zero-value fix (added 2026-08-13)

### PDF zero-value bug (fixed)
- The top-right `Icons.picture_as_pdf_rounded` AppBar button calls
  `TrophyInventoryReportExporter().generateAndShare()`, which **re-fetched**
  trophy docs from Firestore but read them with the WRONG field names, so every
  value rendered as 0.00 despite valid values on the on-screen cards:
  - Read `data['quantity']` → the screen/manager write `availableCount`.
    Default `?? 1` inflated the count; price stayed 0.
  - Read `data['pricePerAnimal']` → the screen/manager write
    `pricePerTrophyRands`. Always null → `?? 0.0` → "R 0.00" everywhere.
- Fixed in **3** read sites (the totals loop, the per-farm `_farmSection`
  loop, and the `dataTable` rows): `quantity`→`availableCount` (default
  `?? 0`), `pricePerAnimal`→`pricePerTrophyRands`. Now the PDF's "Estimated
  Stock Value", per-farm totals, and per-species Price/Animal + Qty columns
  consume the actual stock values and species pricing from the loaded
  dataset. Measurement + photo-count fields were already correct. The
  measurement field reads `trophyMeasurement` ?? `trophyLengthInches`
  (matches the dual-alias write in `syncTrophyStock`).
- File: `lib/features/hunter_mode/services/trophy_inventory_report_exporter.dart`.

### Farm stock editing (new)
- The "Current Stock by Farm" block previously rendered read-only
  per-species rows. Each row is now **tappable** (wrapped in
  `Material > InkWell` with an edit hint icon) and opens a modal
  **Edit Trophy Stock** sheet for that exact trophy document.
- To target the right doc, the grouping loop now carries the snapshot doc id
  on each entry under a private `_docId` key (`data['_docId'] = doc.id`).
  This stays local to the screen's stream build — the PDF exporter fetches
  its own snapshot, so the private key never contaminates it.
- New **Edit Trophy Stock sheet** (`_showEditTrophySheet`): a
  `showModalBottomSheet` + `StatefulBuilder` form pre-filled from the entry,
  with validated fields for Species * (required), Available Count * (int ≥0),
  Price per Trophy (R) * (double ≥0), Measurement (inches, optional/decimal).
  `isScrollControlled` + `viewInsets.bottom` padding keeps the keyboard off
  the SAVE button. SAVE → `_submitTrophyEdit` →
  `OutfitterEnterpriseManager.instance.updateTrophyStock(...)`.
- A destructive **DELETE ENTRY** `TextButton.icon` opens a confirmation
  `AlertDialog`; confirming calls `_deleteTrophy` →
  `OutfitterEnterpriseManager.instance.deleteTrophyStock(trophyId)`.
- Reactive refresh: the "Current Stock by Farm" block is already a Firestore
  `snapshots()` `StreamBuilder`, so both update and delete re-render the
  list automatically — no manual `setState`/reload. On failure the error is
  surfaced and the sheet stays open for retry.
- New `OutfitterEnterpriseManager.updateTrophyStock({trophyId, species?,
  availableCount?, pricePerTrophyRands?, trophyMeasurement?,
  clearMeasurement})`: partial update (only supplied fields written) +
  `lastUpdated: serverTimestamp()`. Measurement written under both
  `trophyMeasurement` and `trophyLengthInches` (matches `syncTrophyStock`).
  `clearMeasurement: true` nulls the measurement fields.
- New `OutfitterEnterpriseManager.deleteTrophyStock(trophyId)`: hard-deletes
  the trophy doc (`firestore.rules` already permits owner/admin
  `update, delete` on `trophies/{trophyId}`).
- `flutter analyze`: 0 errors, 13 warnings (all pre-existing, none new; the
  `unnecessary_cast` at `outfitter_trophy_stock_screen.dart:93` is the
  pre-existing baseline shifted by added code). `flutter test`: 201 passed,
  4 pre-existing failures (saps_tracker, offline_sync_queue,
  advanced_ballistics, bluetooth_mesh — none touch the changed files).
- Files: `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `lib/features/hunter_mode/services/trophy_inventory_report_exporter.dart`.

