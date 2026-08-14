# JagSpoor -- Agent Memory

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
  Node 22 runtime). Build: `cd functions && npx tsc` -> emits `functions/lib/`.
- Two exported functions in `functions/src/index.ts`:
  - `payfastITNHandler` -- HTTPS `onRequest`, public invoker, region `us-central1`.
    Validates PayFast ITN md5 signature (constant-time compare), calls PayFast's
    `validate` endpoint server-to-server, then on `payment_status==COMPLETE` updates
    `bookings/{m_payment_id}` -> `status:'Paid'`, `paymentTimestamp`, `payfastpfPaymentId`.
    Reads `PAYFAST_PASSPHRASE` env var for signature generation.
  - `adminCreateOutfitter` -- `onCall`, region `us-central1`. Requires caller
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
- **No Firebase credentials available** -- `FIREBASE_TOKEN`/service account absent;
  `firebase projects:list` returns 401 "No OAuth tokens found". Deployment must be run
  in an environment with `firebase login` or `FIREBASE_TOKEN` set.
- **No Java/JVM** -- Firestore emulator cannot run here, so `@firebase/rules-unit-testing`
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

## Trophy Inventory -- measurements, photos, stock-by-farm (added 2026-08-12)

- Trophy Inventory form (`outfitter_trophy_stock_screen.dart`) gained:
  - **Trophy Measurement** field (`_measurementController`, decimal, `in` suffix)
    -> passed as `trophyMeasurement` (double?) to
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
    farms once into a `farmId -> name` map; each farm card shows a per-farm total
    badge + per-species breakdown rows (count, price, measurement, photo count).
    The trophy stream is already reactive (`snapshots()`), so the grouped tally
    updates immediately when a new trophy is added.
- `syncTrophyStock` got new optional params `trophyMeasurement` and
  `trophyPhotoUrls` (both omitted -> no field written). Docstring updated.
- Deploy reminder: new `trophies` index + `storage.rules` change need deployment
  (`npx firebase-tools deploy --only firestore:indexes,storage`). Until the
  index is deployed the stock query falls back to the now-surfaced error UI.
- Files: `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `firestore.indexes.json`, `storage.rules`.

## Enterprise Control Panel -- farms & managers (fixed 2026-08-12)

- "No farms registered" bug on the Enterprise Control Panel was caused by the
  `Registered Farms` stream query using
  `.where('outfitterId', isEqualTo: uid).orderBy('createdAt', descending: true)`
  with **no matching composite index** in `firestore.indexes.json`. The equality
  + orderBy combo requires a composite index in Firestore; without it the query
  errors -- and the `StreamBuilder` only handled `ConnectionState.waiting`,
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
  keyboard, validator stripping `+ - ( )` and requiring ‚â•9 digits). The value is
  passed through `_assignManager` -> `OutfitterEnterpriseManager.assignManager()`
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
  no delay between sessions -- so Android's Camera2 driver couldn't finish
  `waitUntilIdle()` / free the `SurfaceTexture` before the next screen opened
  a fresh session against a half-released surface.
- Both camera screens now follow the same release contract:
  - `_releaseCamera()` helper: `await _stopImageStream()` -> nullify the
    controller ref -> `await controller.dispose()` in a try/catch. Safe to
    call repeatedly.
  - `dispose()` calls `_releaseCamera()` (fire-and-forget) so the session is
    torn down before the State is destroyed.
  - `didChangeAppLifecycleState` (both states are now `WidgetsBindingObserver`):
    on `inactive`/`paused` -> `_releaseCamera()` + clear `_isInitialized`;
    on `resumed` -> `_initializeCamera(withHardwareDelay: true)`.
  - `_initializeCamera({withHardwareDelay})`: 300ms `Future.delayed` before
    re-init so Camera2 can release the surface; `_releaseCamera()` before
    creating a fresh controller; inner try-catch around `initialize()` that
    releases + waits 300ms + retries once on failure; outer catch clears the
    error state; `_isInitializing` re-entrancy guard.
- Files: `lib/features/hunter_mode/screens/blood_tracker_screen.dart`
  (image-stream screen -- stream stop is essential), `lib/features/track/
  presentation/spoor_detection_hud_screen.dart` (takePicture screen -- was
  missing observer/lifecycle entirely; now has them).

## Contextual info icons (added 2026-08-12)

- Reusable `lib/core/widgets/contextual_info_icon.dart`:
  - `ContextualInfoIcon` -- compact `IconButton` showing `info_outline` tinted
    with the theme accent (override via `iconColor`); taps open an
    `ExplanationDialog`. Props: `title`, `description`,
    `concepts: List<ExplanationConcept>`, optional `iconColor`/`iconSize`.
  - `ExplanationDialog` -- `showModalBottomSheet` (scrollable, theme-coloured)
    rendering Title, Description, a KEY CONCEPTS breakdown of
    `(label, detail)` rows, and a "GOT IT" dismiss action.
    Call via `ExplanationDialog.show(context, title:, description:, concepts:)`.
- Placed info icons across complex feature headers:
  - **Scope Settings & Tools** (`scope_tools_bottom_sheet.dart`): Turret Click
    Math (1/4 MOA ‚âà 0.261" @100yd vs 0.1 Mil = 1 cm @100m), SFP Magnification
    Scaling (trueValue = ratedValue √ó calibratedMag/currentMag), Tall-Target
    Tracking Test (error % = |measured‚àídialed|/dialed√ó100).
  - **Spoor Identifier** (legacy `spoor_identifier_screen.dart` + HUD
    `spoor_detection_hud_screen.dart`): Morphological Categories (Paw/Carnivore,
    Cloven-Hoofed/Ungulate, Solid Hoof/Equine), Scale Reference Calibration
    (mm-per-pixel = knownObjectMm/knownObjectPixels), Contour Circularity
    Metric (4œÄA/P¬≤).
  - **Blood Trail Tracking Radar** (`blood_tracker_screen.dart`): HSV Spectrum
    Thresholding (Hue Tolerance, Min Saturation, Min Value for haemoglobin
    contrast in bush light).
  - **Admin Portal & Analytics**: `outfitter_revenue_screen.dart` (Gross Revenue
    vs Platform Commission -- gross √ó 0.05 fee, net = gross ‚àí fee),
    `bulk_csv_import_screen.dart` (CSV column spec: email, fullName, role,
    phoneNumber).

## Universal PDF Document Engine (added 2026-08-12, Phase 6)

- Central reusable PDF template service: `lib/core/services/pdf_document_engine.dart`.
  - `JagSpoorPdfTheme` -- static tactical Earth/Gold palette matching the app:
    `accent` `#C68B59` (Warm Gold/Bronze), `accentGold` `#D4AF37` (Brushed Gold),
    `deepBrown` `#795548`, `darkSlate` text, `band`/`cream` backgrounds,
    `divider`, `white`. Text styles: `body`, `caption`, `label`, `value`,
    `sectionTitle`.
  - `JagSpoorPdfDocument` -- async builder wrapper. `create(title:, documentId:)`
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
    `formatZAR(double)` -> "R 1 234.56", `formatDate(DateTime?)` -> "YYYY-MM-DD".
- Exporters using the engine (consistent branded header/footer across the
  whole document line):
  - **Venison Transport & Hunt Permit** -- `lib/features/hunter_mode/services/
    venison_permit_pdf_exporter.dart` (NEW). Fetches hunter + outfitter
    signature images from Firebase Storage URLs via `http` and embeds them.
    Wired via `onExport` callback into the permit list details sheet.
  - **Booking Invoice / Confirmation** -- `lib/features/hunter_mode/services/
    outfitter_invoice_exporter.dart` (REFACTORED). Now takes the raw booking
    map + bookingId; fetches the linked `packages` doc to recover the
    itemized line-item / species / all-inclusive breakdown, prints the 7.5%
    platform commission row, the 25% non-refundable deposit status + balance,
    and any date-change request history. Call site in
    `outfitter_booking_dashboard_screen.dart` updated to pass `bookingData`.
  - **Trophy Inventory Report** -- `lib/features/hunter_mode/services/
    trophy_inventory_report_exporter.dart` (NEW). Farm-grouped trophy stock
    (species, qty, price/animal, measurement in inches, photo count) +
    inventory summary. Wired via AppBar PDF icon in
    `outfitter_trophy_stock_screen.dart`.
  - **Revenue & Farm Analytics Report** -- `lib/features/hunter_mode/services/
    revenue_analytics_report_exporter.dart` (NEW). Gross revenue, 7.5%
    platform fees, net earnings, enterprise metrics, and a farm-manager
    directory. Wired via AppBar PDF icon in `outfitter_revenue_screen.dart`.
  - **SA Game Transport Permit** -- `lib/features/hunter_mode/services/
    transport_permit_pdf_exporter.dart` (REFACTORED to engine; Sections A‚ÄìE
    + signature blocks).
  - **Slaughterhouse / Meat Processing Manifest** -- `lib/features/hunter_mode/
    services/meat_processing_exporter.dart` (REFACTORED to engine).
- Remaining exporters NOT yet migrated to the engine (still use legacy
  per-page layout): `SapsPdfGenerator`, `FirearmPdfGenerator`,
  `InvoicePdfService`. They remain functionally correct; migration is a
  follow-up cosmetic-consistency task.
- Asset note: the header logo path `assets/app logo/logo1.png` is already
  declared under `flutter.assets` in `pubspec.yaml` (and used for the app icon).
- `flutter analyze`: 0 errors, 14 warnings, 319 infos (unchanged from Phase 5
  baseline -- no new issues introduced).

## Superuser 3-mode instant switcher (added 2026-08-12)

- Reusable widget `lib/features/admin/widgets/admin_mode_switcher.dart`:
  - `AdminMode` enum: `hunter`, `outfitter`, `admin`.
  - `AdminModeSwitcher` -- three-segment control bar (Hunter / Outfitter /
    Admin). Active segment is highlighted with the theme accent; tapping an
    inactive segment issues `Navigator.pushReplacementNamed` to
    `/hunter_dashboard`, `/outfitter_dashboard`, or `/admin_dashboard`,
    rebuilding the navigation stack for the new role context **immediately
    without sign-out or credential re-entry** (mirrors the existing admin
    bypass in `role_selection_screen.dart`).
  - `AdminModeSwitcherButton` -- AppBar `IconButton` (swap icon) that opens the
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
  off-grid battery-saver feature) matches the "battery" substring -- unrelated
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
  `_tacticalBlack`/`_panelBlack`/`_accent` const -> Theme.of getters; all
  `Colors.white`/`black` text -> `_textPrimary`/`_textSecondary`/`_textHint`),
  `auth_screen.dart` (Google sign-in button + 2FA sheet use theme colors).
  Dashboards + legacy spoor screen already use `theme.*`/`Theme.of`.
- Camera-overlay screens (spoor HUD, blood tracker) intentionally use
  high-contrast `Colors.white`/`black` for HUD text over the live camera
  preview -- that contrast is by design, not a theme violation.
- Tests: `test/theme_controller_test.dart` (9 tests: persistence load/default,
  setDarkMode/toggle persist, idempotency, notify, brightness, exact palette).

## Flutter SDK & analyze (this sandbox)

- Flutter SDK installed at `/home/openhands/flutter`. The local checkout is
  **3.44.9 stable** (Dart 3.9, 2026-08-05) -- NEWER than the **CI pin of 3.29.1**
  in `.github/workflows/build-and-deploy.yml`. This version skew matters (see
  below). Add to PATH: `export PATH="$HOME/flutter/bin:$PATH"`.
  - **Why CI stays on 3.29.1, not 3.44.9**: the project's iOS Firebase plugins
    resolve cleanly under CocoaPods (the iOS dependency manager Flutter uses
    on 3.29.1) but hit a Swift Package Manager transitive conflict on newer
    Flutter (3.44.9 defaults iOS to SPM): `firebase_core` -> firebase-ios-sdk
    12.17.0 vs `firebase_storage` -> 12.15.0. Coordinating every `firebase_*`
    package to one firebase-ios-sdk is a deep dependency rabbit hole, so we
    keep the proven 3.29.1 pin (CocoaPods) and instead revert the iOS native
    template to the classic form that compiles on 3.29.1. See the CI section.
  - **Version-skew note**: on 3.29.1 `DropdownButtonFormField` takes `value:`
    (`initialValue:` is a hard compile error there); on 3.44.9 `value:` is a
    deprecation info in favor of `initialValue:`. We use `value:` everywhere
    (works on both; matches the other 9 dropdowns). The local deprecation
    infos are accepted baseline.
- `flutter pub get` succeeds (148 outdated but constraint-incompatible packages -- expected).
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
  - Production `lib/` ‚âà 94 issues; `test/` ‚âà 209 issues. No analyzer errors block the build.

## CI workflow -- Build & Deploy (fixed 2026-08-12)

- `.github/workflows/build-and-deploy.yml` runs: `build-android` (ubuntu),
  `build-ios` (macOS), then `deploy-firebase` (needs build-android) and
  `notify` (needs deploy-firebase, `if: always()`). Flutter pin: **3.29.1**
  (stable), Java 17 (Temurin).
- **iOS native template reverted to the classic form** (root-cause fix for the
  iOS build failure). The project's iOS code had been regenerated by a modern
  Flutter template that adds scene/implicit-engine APIs:
  - `ios/Runner/SceneDelegate.swift` subclassed `FlutterSceneDelegate` (not in
    3.29.1's framework -> "Cannot find type 'FlutterSceneDelegate' in scope").
  - `ios/Runner/AppDelegate.swift` conformed to `FlutterImplicitEngineDelegate`
    + used `FlutterImplicitEngineBridge` / `didInitializeImplicitFlutterEngine`
    (not in 3.29.1 -> "Cannot find type 'FlutterImplicitEngineDelegate'").
  - `Info.plist` carried a `UIApplicationSceneManifest` wiring the scene
    delegate.
  Fix applied (classic pre-scene template, works on 3.29.1 through 3.44+):
  - `AppDelegate.swift` -> canonical `FlutterAppDelegate` subclass that calls
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
  - Java 17 (Temurin) -- correct for AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20.
  - Android: `flutter build apk --debug`; `ndkVersion = flutter.ndkVersion`
    (CI auto-installs the NDK plugins request -- a 26.3-vs-27.0 version warning
    is emitted but non-fatal). Confirmed green on CI after the compile fix
    (run 31628707429, `Build Android APK` ‚úì in ~10 min).
  - iOS: `flutter build ios --simulator --no-codesign` -- `--no-codesign`
    skips signing (no provisioning profile on the hosted runner); `pod install`
    runs inside the Flutter build (~8 min; resolves cleanly on 3.29.1 via
    CocoaPods). Confirmed `pod install` + `Xcode build` both run on CI
    (run 31632434809); the build now reaches the simulator link stage.
  - **mobile_scanner arm64-simulator fix**: on Apple-Silicon runners
    (`macos-latest`, arm64) the iphonesimulator build targets arm64, but
    `mobile_scanner` 6.0.11's prebuilt ML xcframework ships no arm64-sim
    slice -> Xcode "User-Defined Issue: Unsupported Swift architecture" at
    `mobile_scanner-Swift.h`. Fix: `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`
    added BOTH in `ios/Podfile` post_install (pod targets) AND the Runner
    target's 3 build configs in `project.pbxproj` (Profile/Debug/Release,
    anchored after `ENABLE_BITCODE = NO;`). This forces the simulator build
    to x86_64 (run via Rosetta on the arm64 runner), which the prebuilt
    binaries support. Side effect: local iOS-sim builds also run x86_64
    (acceptable, intentional CI parity).
  - One prior run failed on a transient `java.net.SocketException: Unexpected
    end of file from server` during `flutter pub get` (runner network glitch),
    not a code issue -- re-runs clear it.
- **Secret handling**: `deploy-firebase` gates ALL deploy steps behind a
  `Check Firebase secrets` step (`steps.secrets.outputs.deploy` true/false).
  When `FIREBASE_SERVICE_ACCOUNT` is unset it emits a `::warning::` with a
  clear "configure the repo secret" message and skips deploy (every later
  step is `if: deploy == 'true'`) -- so missing secrets no longer fail the job.
  Replaced the old broad `continue-on-error: true` (which masked real deploy
  errors) with explicit per-step gating. Confirmed: the deploy job now reports
  `success` (correctly skipped) instead of `failure` when secrets are absent.
  `notify` runs (`if: always()`) and only pings Discord if
  `vars.DISCORD_WEBHOOK` is set (note: the `aristidp/discord-action` step can
  still error when the webhook var is unset -- non-essential, does not gate
  build/deploy).
- **permissions**: top-level `permissions: { contents: read }` (least-privilege;
  deploy uses its own Firebase service-account secret, not GITHUB_TOKEN).
- No `environment:` directive (referencing a non-existent GitHub environment
  would block the job).

## Phase 3 -- Hunting Package Publisher & Marketplace Pipeline (added 2026-08-12)

- **Platform fee revised 5% -> 7.5%** everywhere:
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
  rewritten with an All-Inclusive ->î Itemized segmented toggle, the 7 itemized
  line-item editors (qty √ó price each), a SA Game Guide multi-species selector
  (loads `animals` collection), Start/End date availability pickers, and a live
  "Outfitter Base Price + 7.5% Platform Fee = Total Package Value" summary.
- **`publishPackage`** now takes a `PackagePricing` (resolves base price from
  mode + line items + species) and writes `mode`, `lineItems`, `speciesItems`,
  `availabilityStart/End`, `platformCommissionRate`.
- **25% non-refundable deposit**: `PackageBookingManager.depositFraction =
  0.25`. `bookPackage` writes `depositAmountRands`/`balanceAmountRands`.
  New `approveBookingAndRequestDeposit()` transitions an approved booking to
  `Pending Deposit` and stores the deposit split -- the outfitter "APPROVE &
  REQUEST DEPOSIT" button calls it. The hunter PayFast button charges the 25%
  deposit amount (falls back to full total for legacy bookings). `Paid` is a
  new status (set by the PayFast ITN handler on COMPLETE payment).
- **Date-change requests**: `requestDateChange()` (hunter) writes
  `dateChangeRequest` + `dateChangeRequestPending:true`;
  `resolveDateChange(approved)` (outfitter) clears the flag, sets the request
  status, and on approval copies requested -> `confirmedStartDate/EndDate`.
  Hunter booking card has a "Request Date Change" button + sheet (date pickers
  + reason); outfitter dashboard renders a date-change section with
  APPROVE NEW DATES / DECLINE actions.
- **Marketplace details view**: `_BookingConfirmationSheet` is now an
  interactive details sheet showing the itemized / all-inclusive breakdown,
  advertised species, inclusions, 7.5% fee split, and the 25% deposit row.
  Package card shows the total price *incl.* the 7.5% fee + meta chips
  (mode, species count, availability window).
- **Firestore**: bookings now carry `status` ‚àà `Pending Approval`,
  `Approved`, `Pending Deposit`, `Paid`, `Declined`, `Completed`, `Cancelled`.
  The status-update rule (`statusUpdateAllowed()`) is unaffected -- only the
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

## Batch D -- Permit Log Permissions, Dedup & Marketplace Hunter Privacy (added 2026-08-12)

- **`firestore.rules` `venison_permits/{permitId}`** rewritten:
  - `allow read: isSignedIn() && (resource == null || outfitterId == uid || hunterId == uid || isAdmin())` -- lets both `.where('outfitterId', isEqualTo: uid)` and `.where('hunterId', isEqualTo: uid)` list queries succeed (server guarantees returned docs satisfy the rule). `resource == null` is the not-yet-existing edge case (harmless for reads of existing docs).
  - `allow create, update: isSignedIn()` -- either party may write (both co-complete the legal form + signatures).
  - `allow delete: isOwnerOf('outfitterId') || isAdmin()` -- least-privilege (unchanged from before).
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
  "My Transport Permits" -> "My Venison Permits" -> `VenisonPermitListScreen(isOutfitterMode: false)`.
- **Dedup**: `VenisonPermitManager.getMyPermitsStream` now de-duplicates the
  snapshot by document id (`seen.add(doc.id)`) before mapping, so a permit can
  never render twice even if a future outfitterId+hunterId stream merge returns
  the same doc twice.
- **Marketplace hunter privacy** (`hunter_package_marketplace_screen.dart`):
  the "Outfitter Base Price" and "7.5% Platform Fee" `_PriceRow`s were removed
  from the booking details sheet; the total remains inclusive of the fee but is
  relabelled "Total Price" (also on the package-card chip "total price" and the
  booked-hunt deposit banner). The dead `isFee` param was removed from `_PriceRow`.
  Primary action button renamed "CONFIRM BOOKING" -> "BOOK THIS PACKAGE".

## Phase 4 -- AI Paper Price List Scanner Updates & History Log (added 2026-08-12)

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
    reflects the 7.5% split applied at save time -- no hardcoded fee there.
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


## Phase 5 -- Legal SA Game Transport & Venison Permit (added 2026-08-12)

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

## Outfitter Package CRUD Polish -- full lifecycle + image management (added 2026-08-13)

- **`PackageStatus` enum** added to `lib/features/hunter_mode/models/package_pricing.dart`:
  `active`, `draft`, `archived`, `deleted` (with `label`, `fromString`, and
  `isListed`). Replaces the loose `'active'`/`'deleted'` string literals.
- **`PackageBookingManager`** (`services/package_booking_manager.dart`)
  gained the full outfitter package CRUD surface:
  - `publishPackage` now returns `Future<String>` (the new doc id) and takes
    `status` (default `active`; pass `draft` to save an unlisted WIP),
    `imageUrls` (gallery download URLs), and `depositPercentage` (per-package
    non-refundable deposit, 0‚Äì100, default 25 -- stored as both
    `depositPercentage` and the fractional `depositFraction`). Validates
    title AND description non-empty (description was previously unvalidated).
  - `updatePackage({packageId, title?, description?, pricing?, inclusions?,
    farmId?, imageUrls?, depositPercentage?})` -- owner-scoped edit; recomputes
    the 7.5% commission split whenever pricing changes.
  - `setPackageStatus({packageId, status})` -- explicit lifecycle transition.
  - `getMyPackagesStream({status?})` -- reactive `snapshots()` scoped by
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
  - **Deposit percentage field**: validated `TextFormField` (0‚Äì100, `%`
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
  `_PackageCard` gained `_buildGallery` -- a horizontal
  `cached_network_image` strip of the package's `imageUrls` (renders nothing
  when the package has no images, so legacy packages are unaffected).
- **Outfitter dashboard** (`lib/features/outfitter_mode/outfitter_dashboard.dart`):
  a "Manage My Packages" feature card (`inventory_2_rounded`) was added right
  after "Publish Hunting Package" (in the `!_isManager` block) navigating to
  `OutfitterPackageManagerScreen`.
- **`storage.rules`**: added `match /package_images/{uid}/{fileName}` --
  owner-scoped writes (the outfitter's uid is the path segment); reads
  covered by the global authenticated-read rule (marketplace listings are
  visible to signed-in hunters).
- **`firestore.rules`**: no change required -- `packages/{packageId}` already
  allows `update, delete` by owner (`resource.data.outfitterId == auth.uid`),
  so `updatePackage` / `setPackageStatus` / `deletePackage` are covered.
- **`firestore.indexes.json`**: three `packages` composite indexes added --
  `(outfitterId ASC, createdAt DESC)` for `getMyPackages`/`getMyPackagesStream`,
  `(outfitterId ASC, status ASC, createdAt DESC)` for the status-filtered
  management stream, and `(status ASC, createdAt DESC)` for the marketplace
  `getAllPackages` query. Must be deployed:
  `npx firebase-tools deploy --only firestore:indexes,storage`.
  Until deployed the streams surface the index-missing error in-UI rather
  than silently showing empty.
- **`flutter analyze`** (local Flutter 3.29.1, CI pin): **0 errors, 0 warnings
  in all changed files** (90 pre-existing infos + warnings across `lib/`,
  all in unrelated files -- unchanged from the documented baseline). The new
  management screen + creator edits + marketplace gallery are analyzer-clean.
- Files: `lib/features/hunter_mode/models/package_pricing.dart`,
  `lib/features/hunter_mode/services/package_booking_manager.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart` (new),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `storage.rules`, `firestore.indexes.json`.

## Phase 7 -- Shot Group Target Analyzer AI Calibration (added 2026-08-13)

- The "AI Shot Group Analyzer" embedded in `scope_calibration_screen.dart`
  was a **mock** -- it used `math.Random()` to simulate a pixel spread and
  only computed a single fake "max spread" MOA value, with no real shot-point
  placement, no mean radius, no center of impact, and no actual scale
  calibration of the reference object in the image. Item #12 replaced it
  with a real, calibrated computer-vision + geometry pipeline.
- **New service** `lib/features/hunter_mode/services/shot_group_analyzer_service.dart`
  (`ShotGroupAnalyzerService`, singleton `instance`):
  - **Real shot-hole detection** via dark-blob detection: rasterizes the
    decoded target photo (the `image` package -- already a dep, used by the
    spoor service) to a luminance mask (`0.299R+0.587G+0.114B < 110`), runs
    4-connected-component labelling on a sampled grid (step 4px), and keeps
    each blob whose radius, aspect ratio, and fill ratio fall in the
    bullet-hole range -- rejecting dust specks (too small), the reference
    coin / large shadows (too big), and text strokes (low fill). Each
    accepted blob's centroid becomes a `ShotImpact` in full-resolution pixel
    coords.
  - **Scale calibration** via a user-placed two-point `ScaleReference` (coin
    diameter or 1-inch grid line): `pxPerMm = pixelLength / knownLengthMm`.
    The reference length is user-editable (defaults: 5-Rand coin 26mm, 1-Rand
    23mm, 1-inch grid 25.4mm).
  - **Group geometry** (the full statistical suite, all calibrated):
    - **Extreme spread** -- max pairwise distance between shot points
      (records the contributing shot pair for overlay rendering).
    - **Mean radius** -- average distance of each shot from the group
      centroid.
    - **Center of impact (COI)** -- arithmetic centroid of the shot points,
      with offset from a user-marked point of aim (bullseye), expressed as
      horizontal (right +) and vertical (up +) in mm and angular units.
  - **Angular conversions** (physically exact): `inchesToMoa` uses the
    1.047in@100yd definition; `inchesToMil` uses 3.6in@100yd (=100mm@100m);
    distances accepted in yards OR meters (1 m = 1.0936 yd). Both MOA and MIL
    output supported (`AngularUnit` enum).
  - **Suggested turret correction** (`suggestedClicks`): converts the COI
    offset to clicks at the scope's per-click value (e.g. 0.25 MOA / 0.1
    MIL), applying the opposite-direction dial convention (COI right -> dial
    left; COI low -> dial up).
  - `ShotGroupAnalysis` exposes px / mm / inch / angular forms plus a
    `precisionCategory` (Sub-MOA / 1 MOA / Average / Open), mapping MIL back
    to MOA for the threshold.
- **New interactive overlay**
  `lib/features/hunter_mode/widgets/shot_group_target_overlay.dart`
  (`ShotGroupTargetOverlay` + `_TargetOverlayPainter`):
  - Renders the target photo in a `Stack` with a `CustomPainter` that draws
    **alignment guides** (center crosshair, rule-of-thirds grid, corner
    framing brackets -- toggleable) to help frame the target paper straight.
  - **Tap-to-place** interaction with four modes: place shot impacts,
    calibrate scale (two taps + editable known-length), mark point of aim,
    plus Undo / Clear. Auto-detected shots render orange, manual ones red,
    each numbered.
  - Draws the calibrated reference scale line (amber, labelled in mm), the
    extreme-spread line (red, between the two farthest shots), the COI
    marker (green) + COI->aim offset vector, and the aim point (cyan
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
- **Dashboard wiring**: a "üéØ Shot Group Target Analyzer" `DashboardFeature`
  card was added to `hunter_dashboard.dart` (reachable directly from the
  hunter home, since the scope-calibration card had been commented out).
- **Tests**: `test/shot_group_analyzer_test.dart` -- 11 tests covering COI
  centroid, extreme spread (incl. recorded shot pair), mean radius, the
  1.047in@100yd MOA definition, the 3.6in@100yd MIL definition, meters->MOA,
  COI offset sign convention (image-y-down -> low COI is negative "up"),
  uncalibrated (zero angular, valid px), empty list, precision category, and
  real shot-hole blob detection on a synthetic target (3 holes found, 2 dust
  specks rejected). **All 11 pass.**
- **`flutter analyze`** (local 3.44.9): **0 errors, 0 warnings in all changed
  files** (project total 296 issues, all pre-existing infos/warnings in
  unrelated files -- down from the 320 baseline since the mock removal dropped
  several infos). New service + overlay + screen + test are analyzer-clean.
- Files: `lib/features/hunter_mode/services/shot_group_analyzer_service.dart`
  (new), `lib/features/hunter_mode/widgets/shot_group_target_overlay.dart`
  (new), `lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`
  (new), `lib/features/hunter_mode/screens/scope_calibration_screen.dart`
  (mock removed, rewired), `lib/features/hunter_mode/hunter_dashboard.dart`
  (dashboard card + import cleanup), `test/shot_group_analyzer_test.dart`
  (new). No Firestore/Storage/rules changes (pure on-device CV, no backend).

## Phase 8 -- Ballistic Engine Muzzle Velocity & BC Calculations (added 2026-08-13)

- The ballistics solver had two independent, simplified trajectory models
  and **no drag-curve selection, no ICAO atmosphere, no powder-temperature
  muzzle-velocity correction, and no energy output**:
  - `BallisticSolverService` (`lib/features/hunter_mode/services/ballistic_solver_service.dart`)
    used a single hardcoded drag formula with a BC scalar and an air-density
    factor derived from **barometric pressure only** (œÅ/œÅ‚ÇÄ ‚âà P/P‚ÇÄ, no
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
  - **`DragModel` enum** (`g1`, `g7`) -- the Ingalls G1 (flat-base) and McCoy
    G7 (boat-tail / VLD) standard drag functions, embedded as
    Mach->G(Mach) tables with linear interpolation. The retardation is
    `a = -(œÅ/œÅ‚ÇÄ)¬∑(G(M)¬∑1e-4)¬∑v¬≤/BC` (the 1e-4 factor restores the published
    drag-function's 1/ft units; v in ft/s, result converted back to m/s¬≤).
  - **`Atmosphere`** model + **ICAO air density**: `airDensity()` computes
    `œÅ = (P_d¬∑M_d + P_v¬∑M_v)/(R¬∑T)` with water-vapour partial pressure via
    the **Tetens saturation-vapour-pressure formula** (humidity correction).
    `airDensityRatio()` returns œÅ/œÅ‚ÇÄ against the ICAO sea-level standard
    (1.225 kg/m¬≥). Inputs: ambient temperature (¬∞C), barometric pressure
    (hPa), relative humidity (%), altitude (m).
  - **Density altitude**: `densityAltitude()` -- the ICAO standard-atmosphere
    altitude that has the same density as the given (non-standard) air,
    combining the station altitude, the temperature offset vs. the ISA
    standard temperature at that altitude, and a humidity contribution.
  - **Powder-temperature muzzle-velocity correction**:
    `muzzleVelocityForPowderTemp()` -- `ŒîV = tempCoefficient¬∑ŒîT` where ŒîT is
    in ¬∞F and the coefficient is in fps/¬∞F (default 1.5 fps/¬∞F, typical
    smokeless powder), converted to m/s. Defaults to the ICAO reference
    temperature (15 ¬∞C).
  - **Trajectory integration**: `trajectoryTable()` -- numerical point-mass
    integration (0.5 ms fixed time step) of the 2D equations of motion with
    the Mach-dependent G1/G7 drag, ICAO density-ratio scaling, incline
    (cos-pitch) gravity correction, crosswind drift, and a bore-elevation
    zero solved from the zero range. Output per range step (50 m default,
    0‚Äì1000 m): `TrajectoryPoint` with drop (cm, + = below LOS), windage (cm),
    remaining velocity (m/s), **kinetic energy (Joules, ¬Ω¬∑m¬∑v¬≤, m from
    grains)**, and time of flight (s). Velocity-floor guard prevents drag
    reversal for extreme inputs.
- **Integration**:
  - `BallisticSolverService.calculateScopeAdjustments` gained optional named
    params (`dragModel`, `temperatureCelsius`, `relativeHumidity`,
    `altitudeMeters`, `powderTempCelsius`, `powderTempCoefficientFpsPerF`,
    `bulletWeightGrains`) -- all defaulted so existing call sites (e.g.
    `scope_calibration_screen.dart`) compile unchanged. The returned map now
    also carries `dragModel`, `densityAltitudeMeters`,
    `correctedMuzzleVelocityFps`, and the atmosphere inputs; the single-point
    drop now uses the powder-temp-corrected muzzle velocity.
  - `BallisticSolverService.generateTrajectoryTable` now delegates to the new
    engine (yards->îmetres at the API boundary) and each row gains `dropCm`,
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
  **relative humidity (%)**, and **powder temperature (¬∞C)** alongside the
  existing altitude / ambient-temp / zero-distance / muzzle-velocity / bullet
  weight controls. The analytics summary card now surfaces **remaining
  velocity at target range**, **remaining energy at target range**, the
  selected **drag model**, the **density altitude (ICAO)**, and a full
  atmospheric profile string (altitude / temp / pressure / humidity).
- **Tests**: `test/ballistics_engine_test.dart` -- **18 tests, all pass**:
  - ICAO air density (standard sea level ‚âà 1.225; altitude/pressure/humidity
    effects), density altitude (standard ‚âà 0 m; hot/cold/high-altitude),
    powder-temperature MV correction (reference-temp no-op; hot powder raises
    MV by the expected ~32.9 m/s for a 40 ¬∞C delta at 1.5 fps/¬∞F).
  - Trajectory table (one row per step; zero range ‚âà 0 drop; monotonic
    velocity decay; energy follows ¬Ω¬∑m¬∑v¬≤ and decays).
  - **G1 vs G7 drag curves**: G7 retains more velocity and yields less drop
    than G1 at extended range (the low-drag boat-tail curve is flatter).
  - **Atmospheric density altitude affects trajectory**: thin air (high
    density altitude / low pressure) yields higher retained velocity and
    less drop than dense sea-level air.
- **`flutter analyze`** (local 3.44.9): **0 errors, 0 warnings in all
  changed files** (project total 295 issues, all pre-existing infos/warnings
  in unrelated files -- down 1 from the 296 baseline). New engine + service
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

## Phase 9 -- Outfitter Client Roster & Guided Hunt Logs (added 2026-08-13)

- The outfitter suite had no dedicated client roster and no guided-hunt
  harvest logging. `ClientBooking` was lodge-only (name + contact + lodging/
  vehicle, no passport/ID, no permit references, no assigned package). The
  `CarcassRecord` (SQLite `carcass_records`, read by the Slaghuis Matrix)
  carried only a `hunterId` placeholder string (`'CURRENT_SESSION_ID'`).
  Item #17 added the full client roster + harvest-logging workflow and
  explicitly tied each harvest to a roster client and onward to venison
  permits + the slaughterhouse manifest.
- **New models** (`lib/features/outfitter_mode/data/models/`):
  - `ClientProfile` -- the PH's client hunter book entry: `outfitterId`,
    `fullName`, `idPassportNumber`, `nationality`, `cellNumber`, `email`,
    `address`, optional `assignedPackageId`/`assignedPackageName`/
    `assignedBookingId`, a running `permitReferenceIds` list, `notes`,
    timestamps. `fromFirestore` (now delegates to a snapshot-free
    `fromMap(data, {id})`), `toMap`, `copyWith`.
  - `GuidedHuntLog` -- a guided-hunt harvest entry: `outfitterId`,
    `clientId`/`clientName`/`clientIdPassport` snapshot, optional `bookingId`,
    `species`, `sex`, `carcassWeightKg`, `shotLocationDescription` +
    `shotLat`/`shotLng`, `trophyMeasurementInches`/`trophyMeasurementLabel`/
    `trophyPhotoUrls`, `shotPlacement`, `rifleCalibreMm`, `distanceMeters`,
    cross-reference ids `permitId` + `carcassRecordId`, `notes`, `huntDate`,
    timestamps. Same `fromMap`/`toMap`/`copyWith` shape.
- **New services** (`lib/features/outfitter_mode/data/services/`):
  - `ClientRosterManager` (singleton) -- `client_roster` Firestore CRUD scoped
    by `outfitterId`: `getMyClientsStream` (reactive, ordered by `createdAt`
    desc, de-duplicated by doc id), `getClientById`, `addClient`,
    `updateClient` (merge), `deleteClient`, and `addPermitReference`
    (transactionally appends a permit id to the client's running list).
  - `GuidedHuntLogManager` (singleton) -- `guided_hunt_logs` Firestore CRUD
    scoped by `outfitterId`: `getMyHuntLogsStream` (reactive, ordered by
    `huntDate` desc, de-duplicated), `getHuntLogById`, `addHuntLog`,
    `updateHuntLog`, `deleteHuntLog`, `linkPermit`, `linkCarcassRecord`, plus
    the two downstream bridges:
      * `buildPermitPrefill({log, client})` -- assembles the prefill map
        (hunter block + farm block from the `outfitters` doc + the harvested
        species seeded into `speciesHuntedAndTransported`) that seeds a
        venison transport permit straight from the hunt log.
      * `pushToSlaughterhouseManifest(log)` -- writes a `CarcassRecord` into
        the local SQLite `carcass_records` table the Slaghuis Matrix reads,
        using the client's `clientId` as `hunterId`, then links the new local
        id back onto the hunt log via `linkCarcassRecord`.
- **New screens** (`lib/features/outfitter_mode/presentation/`):
  - `ClientRosterScreen` -- reactive, searchable roster. Tap a card to edit;
    remove with a confirmation modal (linked logs/permits are kept). "Add
    Client" sheet validates name (required) and captures passport/ID,
    nationality, cell, email, address, assigned package, notes.
  - `GuidedHuntLogScreen` -- reactive, searchable hunt log. Each card shows
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
  -- end-to-end traceability client -> hunt log -> permit.
- **Dashboard**: two new cards on the outfitter dashboard
  (`outfitter_dashboard.dart`) -- "Client Roster" and "Guided Hunt Logs" --
  placed immediately before the "Permit Log & Manager" card (the natural
  clients -> hunt logs -> permits grouping).
- **Firestore rules** (`firestore.rules`): new owner-scoped
  `match /client_roster/{clientId}` and `match /guided_hunt_logs/{logId}`
  blocks (`ownerOrAdmin('outfitterId')`).
- **Firestore indexes** (`firestore.indexes.json`): new composite indexes
  `client_roster` `(outfitterId ASC, createdAt DESC)` and `guided_hunt_logs`
  `(outfitterId ASC, huntDate DESC)` for the two stream queries (must be
  deployed: `npx firebase-tools deploy --only firestore:indexes`).
- **Tests**: `test/outfitter_client_roster_test.dart` -- **6 tests, all
  pass**: `ClientProfile` + `GuidedHuntLog` `toMap`/`fromMap` round-trips
  (all fields), missing-field tolerance, `huntDate` fallback to now, and
  `copyWith` permit/carcass linking + `updatedAt` bump.
- **`flutter analyze`** (local 3.44.9): **0 errors, 0 warnings, 0 infos in
  all changed/new files** (project total 295, unchanged baseline -- all
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

## Phase 10 -- Global Offline Firestore Persistence Audit (added 2026-08-13)

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
  - `initialize({cacheSizeBytes: 40 MB})` -- called exactly once in `main()`
    after `Firebase.initializeApp()` and App Check, before any query. Sets
    `Settings(persistenceEnabled: true, cacheSizeBytes: ‚Ä¶)` so every primary
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
  - `offlineResilient<T>(source, {required fallback, debugLabel})` -- wraps a
    stream so any hard error is logged and replaced with a single `fallback`
    emission, then the stream completes. Normal emissions pass through
    untouched. Firestore's own cache already keeps streams alive across brief
    network drops; this is the safety net for the cases where the stream
    errors outright (missing index, permissions change, web-no-persistence
    unrecoverable network error) so the UI shows a defined empty/zero state
    instead of hanging or crashing.
- **Managers hardened** (cache-first + offline fallback applied):
  - `VenisonPermitManager.getMyPermitsStream` -- wrapped with the guard
    (fallback `[]`); `getPermitById` now reads **cache-first**
    (`GetOptions(source: Source.cache)`) then falls back to server, so an
    offline lookup still resolves a recently-viewed permit.
  - `MeatProcessingOrderManager.getMyOrdersStream` -- wrapped (fallback `[]`).
  - `PricelistScannerService.getMyPriceListsStream` -- wrapped (fallback `[]`);
    the unauthenticated `throw Exception` was replaced with a stable empty
    stream so it no longer crashes the history screen's `StreamBuilder`.
  - `PackageBookingManager.getMyPackagesStream` -- unauthenticated `throw`
    replaced with `Stream.empty()` (the consumer already has a `hasError`
    branch for hard stream errors + Firestore cache keeps it alive offline).
  - `CarcassLogManager.getActiveChillerLogs` -- null-user guard added
    (`Stream.empty()` instead of querying for a null `hunterId`).
  - `OutfitterAnalyticsService` -- all four streams wrapped:
    `getRevenueSummaryStream` (fallback zero-metrics map),
    `getFilteredPackagesStream` (fallback `[]`),
    `getPendingBookingsCountStream` + `getTotalPackagesCountStream`
    (fallback `0`).
  - `OutfitterFirebaseService` (bookings/lodging/fleet) -- already had
    `.handleError` fallbacks; unchanged.
  - `ClientRosterManager` + `GuidedHuntLogManager` (Phase 9) -- already had
    `.handleError` returning cached/empty; unchanged.
- **Tests**: `test/offline_stream_guard_test.dart` -- **5 tests, all pass**:
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
  (guard + throw->empty stream),
  `lib/features/hunter_mode/services/package_booking_manager.dart`
  (throw->empty stream),
  `lib/features/hunter_mode/services/carcass_log_manager.dart`
  (null-user guard),
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart`
  (4 streams guarded),
  `test/offline_stream_guard_test.dart` (new).
- No Firestore rules / index / Storage changes (this is a client-side
  persistence + resilience hardening pass).

## Phase 11 -- Package Quantity Tracking & Automatic Sold-Out Status (added 2026-08-13)

- New inventory model for hunting packages: every package now carries a
  `quantityAvailable` slot count (default 1 for legacy docs) that decrements
  atomically on each booking, and a `soldOut` `PackageStatus` that flips on
  automatically when the count hits 0. This is Item #11 / the User Context of
  the master to-do (continuing the Item #10 Package CRUD Polish track).
- **`PackageStatus` enum** (`lib/features/hunter_mode/models/package_pricing.dart`):
  - Added `soldOut` variant; `fromString`/`label` round-trip `"sold_out"`.
    `fromString` falls back to `active` for null/unknown.
  - Added `bool isListed` getter (`active` -> true; `draft`/`archived`/
    `deleted`/`soldOut` -> false) so analytics/marketplace can branch on
    "is this a bookable listing".
- **`PackageQuantity` helper** (same file): type-safe parsing of the raw
  Firestore `quantityAvailable` value.
  - `fromData(dynamic)` -- accepts int/double; returns `defaultQuantity` (1)
    for legacy docs (null), invalid types (String), and negatives; **0 is a
    real 0** (not masked back to 1) so the sold-out state renders correctly.
  - `isSoldOut({quantityAvailable, status})` -- true when qty ‚â§ 0 OR status is
    `sold_out` (defends against stale reads where qty hasn't caught up to the
    transactional flip).
  - `remainingLabel(qty)` -- "Sold Out" / "1 slot left!" / "N slots left!"
    for the marketplace + manager cards.
  - `defaultQuantity = 1` -- legacy packages (pre-Phase-11) behave as
    single-slot: one booking decrements them to 0 -> sold_out.
- **`PackageSoldOutException`** (same file): carries `packageId` + `message`,
    implements `Exception`. Thrown by the booking transaction when a
    hunter tries to book a package with no remaining slots; the marketplace
    catches it and surfaces a clear "sold out" snackbar instead of a generic
    failure message.
- **`PackageBookingManager`** (`lib/features/hunter_mode/services/package_booking_manager.dart`):
  - `publishPackage` -- new required `int quantityAvailable` param (written to
    the doc as `quantityAvailable`).
  - `updatePackage` -- new optional `int? quantityAvailable` param (omitted ->
    field not touched, preserving existing inventory on an edit).
  - `bookPackage` -- **rewritten as `FirebaseFirestore.instance.runTransaction`**
    for atomic inventory + status safety:
    1. Reads the package snapshot inside the transaction.
    2. Guard: throws `PackageSoldOutException` if `status != active` OR
       `quantityAvailable <= 0` (rejects concurrent / late bookings).
    3. Decrements `quantityAvailable` by 1; if the result is ‚â§ 0, atomically
       sets `status = 'sold_out'` in the same transaction.update so the
       marketplace flips to SOLD OUT the instant the last slot is taken
       (no race window between decrement and the status flip).
    4. Writes the booking doc + (deposit split) as before (the booking write
       itself is the transaction's post-commit side effect; the decrement is
       the transactional part).
  - `restockPackage({packageId, quantityAvailable})` -- NEW. Sets the slot
    count back to a positive value AND re-activates a `sold_out` listing back
    to `active` in a single update (so the outfitter can reopen a sold-out
    package without editing each field). Wired to the manager's "Restock"
    action chip.
- **Marketplace stream filters**:
  - `OutfitterAnalyticsService.getFilteredPackagesStream` changed from
    `.where('status', isEqualTo: 'active')` ->
    `.where('status', whereIn: ['active', 'sold_out'])` so hunters still SEE
    sold-out packages (with a SOLD OUT badge + disabled book button) rather
    than having them vanish mid-browse. `getAllPackages` updated the same way
    for consistency.
  - `getTotalPackagesCountStream` (outfitter analytics) still counts
    `status == 'active'` only -- a sold-out package is correctly NOT counted
    as an available listing (it's no longer bookable). This is the intended
    semantic, not a bug.
- **Firestore rules** (`firestore.rules`, `packages/{packageId}` match block):
  the hunter-initiated `bookPackage` transaction calls `transaction.update` on
  the `packages` doc (to decrement `quantityAvailable` + flip status), which
  is a write by the hunter -- normally only the owning outfitter can write
  packages. The rule was widened to allow a signed-in hunter to update the
  `quantityAvailable` and `status` fields only (field-level allowance); other
  fields remain outfitter-only. This is the minimal permission needed for the
  transactional decrement to succeed server-side.
- **Outfitter package creator/editor form**
  (`outfitter_package_creator_screen.dart`): added a `_quantityController`
  (integer input, "slots" suffix, ‚â•1 validation), with edit-mode prefill from
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
    (disabled), background greyed, icon -> `do_not_disturb`, label -> "SOLD OUT".
- **Booking confirmation sheet** (same file, `_BookingConfirmationSheet`):
  - Shows a red sold-out banner ("This package is sold out‚Ä¶") above the
    action buttons when `isSoldOut`.
  - "BOOK THIS PACKAGE" button disabled (`onPressed: null`) + greyed when
    sold out.
  - `_confirmBooking` catch block detects `PackageSoldOutException` and shows
    a tailored "sold out" snackbar instead of the generic "Booking failed".
- **Outfitter package manager** (`outfitter_package_manager_screen.dart`):
  - Card meta line now includes the remaining-slots label.
  - `_statusBadge` switch gained the `soldOut -> (Colors.red, 'SOLD OUT')` case.
  - New `_restock(packageId, currentQty)` method: prompts for a new slot count
    (‚â•1) and calls `restockPackage`, shown as a "Restock"
    (`add_shopping_cart`) action chip ONLY when the package is sold out or
    has ‚â§0 slots.
- **Tests** (`test/package_quantity_test.dart`, NEW -- 24 tests, all pass):
  `PackageStatus.soldOut` label/fromString round-trip + isListed;
  `PackageQuantity.fromData` parsing (int/double/0-is-real-0/legacy-null/
  invalid-string/negative); `isSoldOut` (qty-0, stale-positive-with-sold_out-
  status, active-while-slots-remain, legacy-default); `remainingLabel`
  (sold-out/singular/plural); `PackageSoldOutException` (packageId/message/
  generic-catch); and a structural group encoding the exact
  decrement + sold-out-at-0 + rejection rules that the `bookPackage`
  transaction applies (multi-slot stays active, last slot flips to sold_out,
  0-slot rejects new bookings, legacy single-slot behavior) -- runnable
  without the Firestore emulator (which can't run in this sandbox, see the
  environment-constraints note) by exercising the shared helpers the
  transaction reads through.
- **`flutter analyze`**: 0 errors, 13 warnings (all pre-existing, NONE in any
  modified file), 283 infos. New test file is analyzer-clean.
- **`flutter test`**: `package_quantity_test.dart` 24/24 pass; the previously-
  passing suites (`offline_stream_guard_test`, `theme_controller_test`,
  `outfitter_client_roster_test`, `financial_engine_test`, etc.) still green.
  The only failing suite is `test/features/sync/bluetooth_mesh_test.dart`
  (4 failures on `mockStorage.insertLog.length` assertions) -- pre-existing,
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


## Phase 12 -- Global Bottom SafeArea & Scroll Padding Audit (added 2026-08-13)

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
  - **SafeArea-wrapped bodies** (bottom:true is the default -- verified NO
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
    `presentation/outfitter_dashboard.dart` (duplicate dashboard -- both fixed
    for consistency).
  - Admin: `admin_dashboard_screen.dart` (RefreshIndicator->ListView; was
    hard-coded bottom:32, now `SafeBottomInset.of(context)`).
- **Already-safe (verified, left unchanged)**: `hunter_dashboard.dart` and
  `hunter_profile_screen.dart` already used `+ MediaQuery.padding.bottom`;
  the permit-log / guided-hunt-log / client-roster lists already used a
  generous `bottom: 80-96` (FAB clearance, well above the gesture bar);
  camera/map `Stack` bodies (blood tracker, spoor HUD, weather, license
  scanner, offline nav) are intentionally full-bleed overlays.
- **`flutter analyze`**: **0 errors**, 13 warnings (all pre-existing --
  `unused_local_variable`/`unused_element`/`unnecessary_cast` in unrelated
  files; the single `outfitter_trophy_stock_screen.dart:87 unnecessary_cast`
  is in pre-existing code, NOT in the padding edit). 282 infos (no new issues
  introduced; the new helper file is analyzer-clean).
- **Tests**: `test/package_quantity_test.dart` 24/24 pass; pre-existing suites
  unaffected (pure UI padding change, no logic touched).
- Files: `lib/core/widgets/safe_bottom_inset.dart` (new) + the 18 screen files
  listed above (import + one `padding:` edit each).

## RBAC -- role-based access control & route guards (added 2026-08-13)

- Centralized the "who is the current user" question in a new
  `lib/features/auth/services/user_role_provider.dart`:
  - `enum AppRole { admin, outfitter, hunter, unknown }` with
    `AppRole.fromString` (collapses null / unknown -> `unknown`).
  - `UserRoleProvider` singleton -- the single cached source of truth for the
    resolved role. `resolveRole({forceRefresh})` fetches the role on login in
    this order: (1) not signed in -> `unknown`; (2) admin email allow-list
    (`admin@jag-spoor.co.za`) -> `admin`; (3) `AdminAuthGuard` admin claim /
    Firestore flag -> `admin`; (4) `users/{uid}.role` -> the stored role;
    (5) fetch error -> `unknown`. Result cached for the process lifetime.
    `setRole(role)` lets role-selection cache the freshly chosen role
    without a re-fetch; `reset()` clears it on sign-out. Firestore/Auth are
    lazily resolved via getters so touching the provider in a unit test
    (pre-Firebase-init) does not throw; `@visibleForTesting injectForTesting`
    + `testUid`/`testEmail` override exercise the Firestore path with
    `FakeFirebaseFirestore`.
- Separated the "what may they do" policy into a pure, dependency-free
  `lib/features/auth/services/role_guard.dart` (no Firebase / Flutter imports
  -> fully unit-testable):
  - `RoleGuard.canAccess(role, route)` -- **admins short-circuit to `true` for
    EVERY route** (Hunter, Outfitter, Admin Portal, plus all forms/screens),
    so an admin can never trigger an Access Denied banner. Below that:
    admin-only routes (`/admin_dashboard`) deny every non-admin; the Hunter /
    Outfitter dashboards require the matching non-admin role; all other routes
    default to allowed. -> Hunters cannot open the Admin Portal or Outfitter
    Management; Outfitters default to Outfitter Mode and cannot open
    Hunter / Admin; Admins have full cross-mode access to all three.
  - `RoleGuard.defaultHomeFor(role)` -- where an unauthorized user is bounced
    (`unknown` -> `/role_selection`, never dropped on a dashboard).
  - `RoleGuard.canSwitchModes(role)` -- only `admin` may use the instant mode
    switcher.
  - `RoleGuard.accessDeniedMessage(role, route)` -- route-tailored notice text.
- New `lib/features/auth/widgets/role_guarded_route.dart` -- `RoleGuardedRoute`
  widget wraps a route `builder`. On mount it resolves the role (if not yet
  resolved -- covers deep-link cold launches), checks `RoleGuard.canAccess`,
  and on DENIAL redirects cleanly to `defaultHomeFor(role)` via
  `pushReplacementNamed` with a floating red "Access Denied: ‚Ä¶" SnackBar --
  instead of rendering a screen the user may not use. Awaiting resolution
  shows a centered `CircularProgressIndicator`.
- Wired route guards in `main.dart`: `/hunter_dashboard`,
  `/outfitter_dashboard`, `/admin_dashboard` builders are each wrapped in
  `RoleGuardedRoute(route:, builder:)`. All three dashboards are now
  route-level protected.
- `core/splash_screen.dart` now resolves the role ONCE via
  `UserRoleProvider.instance.resolveRole(forceRefresh: true)` and routes by
  `AppRole` (admin->admin, hunter->hunter, outfitter->outfitter, unknown->role
  selection). Removed the duplicated direct Firestore read; the cached role
  is then read by the dashboard route guards.
- `role_selection_screen.dart` caches the chosen role:
  - admin bypass -> `setRole(AppRole.admin)` before navigating.
  - hunter/outfitter confirm -> writes `users/{uid}.role`, then
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
  method -- admins now have guaranteed full access to Hunter, Outfitter, AND
  Admin routes (plus every other screen) and can never trigger an Access
  Denied banner. Previously admin was admitted per-branch on each dashboard
  route, which worked but was implicit and fragile against future admin-only
  routes. The non-admin branches were tightened accordingly (admin-only
  routes deny all non-admins; hunter/outfitter dashboards require the exact
  matching non-admin role). `test/role_guard_test.dart` gained an explicit
  "admin may access <route>" sweep over 7 representative routes.
- **Tests** (all green locally, Flutter 3.44.9):
  - `test/role_guard_test.dart` (31 tests) -- `AppRole.fromString` parsing +
    `RoleGuard.canAccess` / `defaultHomeFor` / `canSwitchModes` /
    `accessDeniedMessage` for admin, outfitter, hunter, and unknown profiles
    across admin-only, hunter, outfitter, and non-restricted routes, plus an
    explicit admin-full-cross-mode-access sweep over 7 representative routes.
  - `test/user_role_provider_test.dart` (7 tests) -- provider default state,
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
    `_currentUserId!` at the top of the `async*` generator -- a
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
- **Verified safe (no change needed)** -- call sites already null-safe:
  - `ammunition_screen.dart` is the gold-standard pattern:
    `_currentUserId != null ? ...snapshots() : const Stream.empty()` + hasError.
  - `InventoryBridge.watchSafeFirearms`/`watchAvailableAmmunition`:
    null-uid -> `Stream.value([])`, empty rifleId -> local fallback, `.handleError`.
  - `ClientRosterManager`/`GuidedHuntLogManager`: null-uid ->
    `Stream.value(const [])` + `.handleError` + doc-id de-dup.
  - `PackageBookingManager.getMyPackagesStream`: null-uid ->
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
- **Tests**: `flutter test` -> 201 passed, 4 failed. All 4 failures are
  **pre-existing** (verified by stashing the changes and re-running on the
  prior commit `17af183` -- identical 4 failures): `saps_tracker_test`
  (status-string conversion), `advanced_ballistics_test` (density assertion),
  `bluetooth_mesh_test` (mesh-sync assertion), `offline_sync_queue_test`
  (fake_cloud_firestore/cloud_firestore compile skew). None touch the 4
  changed files. RBAC + offline-guard + package + theme suites (76 tests) all
  green.
- Files: `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`,
  `lib/features/outfitter_mode/data/services/outfitter_firebase_service.dart`,
  `lib/features/ballistics/presentation/ammunition_type_selection_screen.dart`,
  `lib/repositories/animal_repository.dart`.

## Broadcast-stream audit -- "Bad state: Stream has already been listened to" (added 2026-08-13)

- Crash: `Bad state: Stream has already been listened to.. Error thrown
  building Expanded(flex: 1)`. Root cause: a **single-subscription** stream
  instance cached as a `late Stream` field in a `State` class, passed to a
  `StreamBuilder`. Firestore `.snapshots()` (and `InventoryBridge
  .watchSafeFirearms()`'s `.snapshots().map().handleError()` chain) return
  single-subscription streams. If the `StreamBuilder` is ever re-mounted
  (disposed + recreated at the same position, e.g. parent tree restructure,
  conditional show/hide, or theme-toggle rebuild) while the `State` persists,
  the new `StreamBuilder` calls `widget.stream.listen(...)` on the
  already-listened single-subscription stream -> throws. (Verified: a raw
  `StreamController.stream` throws on a second `.listen()` even after the
  first subscription is cancelled.)
- Audit: grepped the whole `lib/` tree for cached stream fields
  (`late Stream<...> _x`, `Stream<...> _x`, `Stream get x => _field`).
  Exactly **three** cached single-subscription stream instances existed:
  - `ballistic_calc_screen.dart` -- `_firearmsStream` (firearms `.snapshots()`)
    and `_factoryAmmoStream` (factory_ammunition `.snapshots()`), both
    assigned once in `initState`, consumed by `StreamBuilder(stream: _x)`.
  - `scope_tools_bottom_sheet.dart` -- `_firearmsStream`
    (`_inventoryBridge.watchSafeFirearms()`), same pattern.
- **Verified safe (no change needed):**
  - All `StreamController` fields in services are already `.broadcast()`:
    `outfitter_sync_service` (`_syncStatusController`,
    `_dirtyRecordsController`), `bluetooth_mesh_sync_service` (all three).
    Their getters (`dirtyCountStream`, `dirtyRecordsStream`,
    `ingestionStream`, `peerCountStream`) return broadcast streams.
  - `SignalHudWidget` listens to `dirtyCountStream` (broadcast) via manual
    `.listen()` + cancels in `dispose()` -- multi-instance safe.
  - `OfflineStreamGuard.offlineResilient()` returns a fresh
    single-subscription `StreamController.stream` **per invocation**; every
    manager calls it inline in its getter (fresh stream per `build`), so the
    stream instance is never shared across `StreamBuilder`s or remounts.
  - All other `StreamBuilder(stream: ...)` sites call a fresh getter per build
    (`_repo.watchAnimals()`, `_manager.getMyClientsStream()`,
    `_service.getVacantLodgingStream()`, `PackageBookingManager.instance
    .getMyPackagesStream(status:)`, `_combinedAnalyticsStream()` `async*`,
    inline `.snapshots()`, etc.) -- fresh instance each build -> no sharing.
  - Chat `StreamBuilder`s inside expandable list-item cards use a fresh
    `_bookingQuery.snapshots()` per card `State` -> no cross-card sharing.
- Fix applied: wrapped each cached stream in `.asBroadcastStream()` at the
  `initState` assignment. `asBroadcastStream()` converts the single-subscription
  source into a multi-subscription broadcast stream that tolerates (a) multiple
  simultaneous listeners and (b) listen -> cancel -> re-listen without throwing
  (empirically verified: a raw single-sub stream throws on second listen, but
  `source.asBroadcastStream()` allows re-subscribe after cancel). The broadcast
  wrapper listens to the underlying Firestore stream exactly once for the
  `State`'s lifetime and re-attaches listeners as `StreamBuilder`s mount/unmount.
- `flutter analyze`: 0 errors, 13 warnings (all pre-existing, none in changed
  files). `flutter test`: 201 passed, 4 pre-existing failures (saps_tracker,
  offline_sync_queue, advanced_ballistics, bluetooth_mesh -- identical to the
  prior commit; none touch the changed files).
- Files: `lib/features/ballistics/presentation/ballistic_calc_screen.dart`,
  `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`.

## Manage Farms & Managers -- farm selection & editing (added 2026-08-13)

- The "Registered Farms" block in
  `outfitter_enterprise_panel_screen.dart` previously rendered static,
  non-interactive farm cards. Each card is now **tappable** (whole card
  wrapped in `Material > InkWell` with a tap -> edit sheet) AND carries an
  explicit **EDIT** `TextButton.icon`.
- New **Edit Farm sheet** (`_showEditFarmSheet(data, farmId)`): a
  `showModalBottomSheet` + `StatefulBuilder` form pre-filled from the farm
  doc, with validated fields for: Farm Name * (required), District, Province,
  Size (hectares, decimal-validated -> `double?`), Contact Number (phone),
  Registration Number. Uses `isScrollControlled: true` + `viewInsets.bottom`
  padding so the keyboard never covers the save button. The SAVE button
  shows a spinner + `SAVING‚Ä¶` label while the update is in flight
  (`_isUpdatingFarm`).
- `_submitFarmEdit()` validates the form, parses/validates the size, then
  calls `OutfitterEnterpriseManager.instance.updateFarm(...)`. On success it
  pops the sheet + shows a success snackbar; on failure it surfaces the error
  and keeps the sheet open so the user can retry. The Registered Farms list
  refreshes **automatically** -- it is already a reactive Firestore
  `snapshots()` `StreamBuilder`, so the `updateFarm` write triggers a re-render
  with no manual `setState`/reload needed.
- New `OutfitterEnterpriseManager.updateFarm({farmId, name, district,
  province, sizeHectares?, contactNumber?, registrationNumber?})`: validates
  auth + farmId + name, then `_firestore.collection('farms').doc(farmId)
  .update({...})` with `updatedAt: serverTimestamp()`. Optional fields are
  written as `null` when blank (clears stale values). `firestore.rules`
  already permits `update, delete` for `isAdmin() || isOwnerOf('outfitterId')`
  on `farms/{farmId}` -- no rules/index change required.
- Card UI extended to surface the new fields inline: a `Wrap` of detail chips
  (size `ha`, contact number, registration number) renders below a divider
  **only when at least one of those fields is set** on the document, so legacy
  farms (created before these fields existed) render cleanly without empty
  chips. New `_farmDetailChip(icon, label, theme)` helper.
- `flutter analyze`: 0 errors, 13 warnings (all pre-existing, none in changed
  files). `flutter test`: 201 passed, 4 pre-existing failures (saps_tracker,
  offline_sync_queue, advanced_ballistics, bluetooth_mesh -- none touch the
  changed files).
- Files: `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`.

## Trophy Stock Inventory -- farm stock editing & PDF zero-value fix (added 2026-08-13)

### PDF zero-value bug (fixed)
- The top-right `Icons.picture_as_pdf_rounded` AppBar button calls
  `TrophyInventoryReportExporter().generateAndShare()`, which **re-fetched**
  trophy docs from Firestore but read them with the WRONG field names, so every
  value rendered as 0.00 despite valid values on the on-screen cards:
  - Read `data['quantity']` -> the screen/manager write `availableCount`.
    Default `?? 1` inflated the count; price stayed 0.
  - Read `data['pricePerAnimal']` -> the screen/manager write
    `pricePerTrophyRands`. Always null -> `?? 0.0` -> "R 0.00" everywhere.
- Fixed in **3** read sites (the totals loop, the per-farm `_farmSection`
  loop, and the `dataTable` rows): `quantity`->`availableCount` (default
  `?? 0`), `pricePerAnimal`->`pricePerTrophyRands`. Now the PDF's "Estimated
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
  This stays local to the screen's stream build -- the PDF exporter fetches
  its own snapshot, so the private key never contaminates it.
- New **Edit Trophy Stock sheet** (`_showEditTrophySheet`): a
  `showModalBottomSheet` + `StatefulBuilder` form pre-filled from the entry,
  with validated fields for Species * (required), Available Count * (int ‚â•0),
  Price per Trophy (R) * (double ‚â•0), Measurement (inches, optional/decimal).
  `isScrollControlled` + `viewInsets.bottom` padding keeps the keyboard off
  the SAVE button. SAVE -> `_submitTrophyEdit` ->
  `OutfitterEnterpriseManager.instance.updateTrophyStock(...)`.
- A destructive **DELETE ENTRY** `TextButton.icon` opens a confirmation
  `AlertDialog`; confirming calls `_deleteTrophy` ->
  `OutfitterEnterpriseManager.instance.deleteTrophyStock(trophyId)`.
- Reactive refresh: the "Current Stock by Farm" block is already a Firestore
  `snapshots()` `StreamBuilder`, so both update and delete re-render the
  list automatically -- no manual `setState`/reload. On failure the error is
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
  advanced_ballistics, bluetooth_mesh -- none touch the changed files).
- Files: `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `lib/features/hunter_mode/services/trophy_inventory_report_exporter.dart`.


## Phase 13 -- Outfitter Dashboard Cleanup & Package Creator Camera Capture (added 2026-08-14)

- **Outfitter dashboard cleanup**:
  - Removed the **unused duplicate** `lib/features/outfitter_mode/presentation/outfitter_dashboard.dart`
    (a `StatelessWidget` `OutfitterDashboard` that was never imported anywhere --
    `main.dart` imports the real `lib/features/outfitter_mode/outfitter_dashboard.dart`
    `StatefulWidget`). The duplicate had drifted to a 2-card stub (Price Catalog
    + Slaghuis Matrix) and was an overlapping/redundant component.
  - Hardened the **live dashboard** (`lib/features/outfitter_mode/outfitter_dashboard.dart`)
    against overflow on narrow / small-ratio screens (the long tracked-out
    section label "FARM MANAGEMENT HUD (MANAGER ACCESS)" + the multi-line card
    descriptions + the two-line AppBar title could overflow on a 360dp phone):
    - Section header `Text` -> `softWrap: true`, `maxLines: 2`,
      `overflow: ellipsis`, letterSpacing reduced 2.0 -> 1.2, fontSize 16 -> 15.
    - `_buildFeatureCard` title -> `maxLines: 2, overflow: ellipsis`; description
      -> `maxLines: 3, overflow: ellipsis` (the description Column is already in
      an `Expanded`, so wrapping is safe).
    - `_buildStatusBanner` header Row -> header `Text` wrapped in `Expanded` with
      `maxLines: 1, overflow: ellipsis`; status body -> `softWrap: true,
      maxLines: 3, overflow: ellipsis`.
    - `_buildAppBar` two-line title -> both `Text`s get
      `maxLines: 1, overflow: ellipsis`.
  - Smooth scrolling was already in place (`ListView` + `BouncingScrollPhysics` +
    `SafeBottomInset.of(context)` bottom padding from Phase 12); the cleanup
    keeps that and only fixes the overflow-prone text nodes.
- **Package creator -- native camera capture**
  (`lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`):
  - Previously the gallery only offered `pickMultipleMedia` (gallery multi-pick)
    via a single "Add Photos" tile -- there was no way to capture a photo with
    the device camera from inside the package creator.
  - New `_captureWithCamera()`: opens the native camera via
    `ImagePicker.pickImage(source: ImageSource.camera, imageQuality: 85,
    maxWidth: 1920, maxHeight: 1920)`. image_picker saves the captured JPEG to
    the app temp directory; the returned `XFile` is appended to `_pickedImages`
    and is compressed (downscale 1280px, JPEG q75) at upload time via the
    existing `ImageService.compressExisting` step inside `_uploadPackageImages`.
    A max-images guard (`_canAddImage`) + "Maximum N images reached" snackbar
    mirrors the gallery path.
  - The gallery strip now renders **two** explicit add tiles (both gated by
    `_canAddImage`): a **"Take Photo"** tile (`photo_camera_rounded`) wired to
    `_captureWithCamera`, and the original **"Add Photos"** tile
    (`add_photo_alternate_rounded`) wired to the multi-pick gallery flow. A new
    reusable `_addTile(...)` helper renders both. The camera action is now a
    first-class, clearly-labelled entry point -- tapping it brings up the native
    capture sheet immediately.
  - The full capture -> preview -> upload pipeline already existed for
    gallery-picked images and now applies equally to camera captures: each
    picked `XFile` renders as an `Image.file` preview thumbnail (with a remove
    button) in the horizontal strip, and on package submission
    `_uploadPackageImages` compresses + uploads each to Firebase Storage at
    `package_images/{outfitterId}/{timestamp}_{i}.jpg` with a per-file progress
    indicator, returning the download URLs stored on the `packages` doc as
    `imageUrls`. No backend / rules change (the `package_images` Storage match
    from the Package CRUD Polish phase already covers owner-scoped writes).
- **iOS camera/photo permission strings**
  (`ios/Runner/Info.plist`): the plist previously had NO
  `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` /
  `NSPhotoLibraryAddUsageDescription` keys, so any `image_picker` camera or
  gallery call would crash on iOS with a missing-usage-description termination.
  Added all three (camera, photo-library read, photo-library add) with
  JagSpoor-specific copy. Android already declared `CAMERA` permission +
  `camera` feature (`required=false`) in `AndroidManifest.xml`. Validated the
  plist parses with `plistlib`.
- **Verification**: `flutter analyze` (local Flutter 3.47.0 stable) -> **0
  errors, 13 warnings, 316 infos**. The 13 warnings are all pre-existing and
  NONE are in either changed file (`outfitter_dashboard.dart` /
  `outfitter_package_creator_screen.dart`) -- identical warning set to the prior
  baseline. The 2 `info`s in the package creator are the pre-existing
  `DropdownButtonFormField.value` deprecations (only flagged on Flutter ‚â•3.33;
  CI's 3.29.1 pin does not flag them). `flutter test` of the RBAC + package +
  theme suites (64 tests) -> all pass.
- **Flutter SDK note**: the local SDK at `/home/openhands/flutter` was
  re-installed this session (3.47.0 stable, Dart 3.13) after the documented
  `/home/openhands/flutter` checkout was absent. Add to PATH:
  `export PATH="$HOME/flutter/bin:$PATH"`. It is newer than the CI pin of
  3.29.1 -- the only observable difference for this work is the
  `DropdownButtonFormField.value` deprecation infos (documented baseline).
- Files: `lib/features/outfitter_mode/outfitter_dashboard.dart` (hardened),
  `lib/features/outfitter_mode/presentation/outfitter_dashboard.dart` (deleted),
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`
  (camera capture + dual add tiles), `ios/Runner/Info.plist` (permission
  strings). No Firestore / Storage / rules changes.


## Phase 14 -- AI Pricelist Scanner Dynamic Extraction & Afrikaans Game Names (added 2026-08-14)

- **Root cause**: the AI Pricelist Scanner returned **static, hardcoded mock
  data** regardless of the scanned document. `PricelistScannerService
  ._simulateTextExtraction()` always emitted the same ~26 fake lines
  (African Elephant, Cape Buffalo, ‚Ä¶, Daily Rate, ‚Ä¶) -- so every scanned
  image/PDF produced identical "extracted" species + prices. There was no
  OCR / Vision integration and no Afrikaans recognition.
- **New dependency**: `google_generative_ai: ^0.4.7` (pure-Dart Google Gemini
  SDK, no native build -- safe on the CI Flutter 3.29.1 pin and on the local
  3.47.0 stable). Added to `pubspec.yaml`; resolved cleanly.

- **New pure-Dart parser** `lib/features/hunter_mode/services/pricelist_text_parser.dart`
  (`PricelistTextParser`, `PricelistItem`, `GeminiResultNormalizer`,
  `parseGeminiTextResponse`, top-level `parsePrice`):
  - **Dynamic extraction** -- never returns a fixed list. It takes raw
    price-list text (one line per entry) and parses each line: pops the
    trophy size range FIRST (so size tokens aren't mistaken for a price),
    extracts the rightmost ZAR amount, then resolves species / sex / fee from
    the remainder. Lines without a price are skipped; duplicate
    (speciesId + sex + sizeRange) rows are de-duplicated (first wins).
  - **ZAR price parsing** (`parsePrice`) handles South African formatting:
    `R 12 500` (space thousands), `12,500` (comma thousands), `12500,00`
    (comma decimal), `1.234,56` (dot-thousands + comma-decimal),
    `1,234.56` (comma-thousands + dot-decimal), plain integers, and strips
    `R`/`ZAR` prefixes. Ambiguous comma resolved: comma + exactly 2 trailing
    digits -> decimal, else -> thousands; when both `.` and `,` present the
    rightmost is the decimal separator.
  - **Afrikaans species dictionary** (`speciesAliases`) maps every required
    Afrikaans name to a canonical system species id (matching the `animals`
    image-catalog keys): Vlakvark->Common Warthog, Blesbok->Blesbok,
    Springbok->Springbok, Rooibok->Impala, Koedoe->Greater Kudu,
    Blouwildebees->Blue Wildebeest, Swartwildebees->Black Wildebeest,
    Gemsbok->Gemsbok (Oryx), Eland->Eland, Bosbok->Southern Bushbuck,
    Waterbok->Common Waterbuck, Rooihartbees->Red Hartebeest, Nyala->Nyala,
    Sebra->Plains Zebra, Duiker->Common Duiker, Steenbok->Steenbok,
    Takbok->Fallow Deer (plus English synonyms). Longest-match-wins so
    "Greater Kudu" beats "Kudu" and "Jongbul" beats "bul". Word-boundary
    matching so "ram" doesn't match inside "framing".
  - **Sex/class dictionary** (`sexAliases`): Bul/Ram/Bull/Male/Trophy->Male,
    Koei/Ooi/Ewe/Female/Cow->Female, Jongbul/Penkop/Knypkop/Young
    Male/Juvenile/Yearling->Young Male. The **original** token is preserved
    on `sexLabel` (e.g. `bul`, `koei`); `sex` holds the normalized bucket.
  - **Trophy size range** parsing: `>50"`, `<20"`, `‚â•40"`, `40"-50"`,
    `50"+` are captured verbatim on `trophySizeRange`.
  - **Fee dictionary** (`feeAliases`): Dagfooi/Daily Rate->daily,
    Slagfooi/Slaughter Fee->slaughter, Gidskoste/Guide Fee->guide,
    Wildrit/Game Drive->gamedrive, Bakkiefooi/Vehicle Fee->vehicle,
    Accommodation/Akkommodasie->accommodation, Meals/Kos->meals,
    Transport->transport. Each fee row has `itemType:'fee'` + `feeType`.
  - **Gemini normalizer**: `GeminiResultNormalizer.normalize` routes Gemini's
    structured JSON (species/sex/sizeRange/priceZAR/type fields) through the
    SAME Afrikaans-aware resolvers so Gemini-returned Afrikaans labels map to
    system species IDs identically to raw-OCR text. `parseGeminiTextResponse`
    finds the JSON array in a free-text Gemini response and falls back to
    plain-text parsing when no array is present.
  - `PricelistItem.toMap()` carries `displayLabel`, `name` (=displayLabel),
    `speciesName`, `speciesId`, `sex`, `sexLabel`, `trophySizeRange`,
    `outfitterBasePrice`, `itemType`, `feeType`.

- **New Gemini Vision extractor**
  `lib/features/hunter_mode/services/gemini_vision_extractor.dart`
  (`GeminiVisionExtractor`):
  - `isAvailable` is true only when `GEMINI_API_KEY` is set (env var or ctor
    arg). `extract(File)` reads the file bytes, picks the mime type
    (image/jpeg|png|gif|webp, application/pdf), builds a `GenerativeModel`
    (`gemini-1.5-flash`, `responseMimeType: application/json`,
    `temperature: 0`), sends `Content.text(instruction)` +
    `Content.data(mimeType, bytes)`, then routes `response.text` through
    `parseGeminiTextResponse`.
  - The **instruction prompt** is primed with the full Afrikaans vocabulary
    and demands a strict JSON array of `{type, species, sex, sizeRange,
    priceZAR, feeType, displayLabel}` -- preserving the original printed
    wording (no translation) so Afrikaans labels survive into the parser.
  - Throws `StateError` with an actionable "Set GEMINI_API_KEY" message when
    no key is configured -- so the scanner no longer fakes results; it
    surfaces the missing-configuration state.

- **`PricelistScannerService` rewired**
  (`lib/features/hunter_mode/services/pricelist_scanner_service.dart`):
  - `_simulateTextExtraction()` (the hardcoded mock) **deleted**.
  - `extractPricelistItems` + `processAndUploadPricelistImage` now call
    `_gemini.extract(imageFile)` -> dynamic `PricelistItem`s -> mapped to the
    extracted-item shape via `_itemToExtractedMap` (adds `outfitterBasePrice`,
    `hunterDisplayPriceZAR` (√ó1.075), formatted strings, `commissionZAR`,
    plus the new `displayLabel`/`speciesName`/`speciesId`/`sex`/`sexLabel`/
    `trophySizeRange`/`itemType`/`feeType`). `processingVersion` bumped
    `1.0.0 -> 2.0.0`.
  - New `isAiExtractionAvailable` getter + `parseRawText(String)` so the
    parser pipeline is reusable from an on-device OCR / PDF-text layer.
  - Backward-compatible: existing `name`/`outfitterBasePrice`/
    `hunterDisplayPriceZAR` keys are still present, so the custom-package
    builder + history screen read unchanged.

- **Scanner screen** (`outfitter_pricelist_scanner_screen.dart`):
  - `_processImage` catches `StateError` separately and surfaces the
    `e.message` (the no-API-key guidance) instead of a generic failure.
  - Info panel copy updated to describe the dynamic English/Afrikaans
    extraction + 7.5% commission and the `GEMINI_API_KEY` requirement.

- **Verification screen** (`outfitter_pricelist_verification_screen.dart`):
  - Each editable row now renders **metadata badges** (a `Wrap` of
    `_badge`s) for: SPECIES/FEE, sex/class (original Afrikaans or English
    token), trophy size tier, and the resolved species id -- so the outfitter
    sees exactly what was extracted from their specific document.
  - `_saveToFirestore` now persists the full structured payload
    (`displayLabel`, `speciesName`, `speciesId`, `sex`, `sexLabel`,
    `trophySizeRange`, `itemType`, `feeType`) alongside the price fields, so
    the saved `scanned_pricelists` doc carries the Afrikaans-aware structured
    data for downstream booking + analytics.

- **Tests** `test/pricelist_text_parser_test.dart` -- **22 tests, all pass**:
  - `parsePrice` (8): SA space-thousands, R-prefixed, comma-thousands,
    comma-decimal, dot-thousands+comma-decimal, comma-thousands+dot-decimal,
    plain integer, garbage->null.
  - Dynamic extraction (4): full English price list -> 8 structured items
    (Kudu Bull >50" -> Male + size + R18500; Impala Ram -> Male; Warthog/
    Springbok/Blue Wildebeest resolved; Daily Rate/Slaughter Fee/
    Accommodation fee-typed); different inputs -> different outputs
    (no mock); no-price lines skipped; duplicate rows de-duplicated.
  - Afrikaans (5): all 16 required Afrikaans species map to system ids;
    original Afrikaans display label preserved; Afrikaans sex/class tokens
    (Bul/Ram/Koei/Ooi/Jongbul/Penkop/Knypkop) bucketed; Afrikaans fee terms
    (Dagfooi/Slagfooi/Gidskoste/Wildrit/Bakkiefooi) typed; trophy size
    ranges incl. brackets; "ram"-in-"framing" word-boundary rejection.
  - Gemini normalizer (3): Afrikaans JSON -> system ids + sex + size; string
    price parsed through SA separator logic; non-JSON -> text-parsing fallback.
  - `PricelistItem.toMap` round-trip (1).
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 13
  warnings (unchanged baseline)**, 316 infos. The only warnings/infos in
  touched files are pre-existing (`_showSuccess` unused from Phase 4,
  `unnecessary_type_check` in unchanged `getPriceListsForFarm`/
  `getMyPriceLists` code, and `print` debug calls) -- none introduced by this
  change. New parser + extractor + test files are analyzer-clean.
- **`flutter test`**: 223 passed, 4 failed. The 4 failures are the documented
  pre-existing baseline (`saps_tracker`, `offline_sync_queue`,
  `advanced_ballistics`, `bluetooth_mesh`) -- none touch the changed files;
  identical to the prior commit.
- **Runtime note**: real extraction requires `GEMINI_API_KEY` to be set in
  the deploy environment (`firebase functions:config` / Cloud Run env /
  `--dart-define=from-environment`). Without it the scanner surfaces a clear
  "Set GEMINI_API_KEY" snackbar instead of fabricating a price list -- the
  intended honest fallback. The parser + normalizer are pure-Dart and
  unit-testable independent of the API.
- Files: `lib/features/hunter_mode/services/pricelist_text_parser.dart` (new),
  `lib/features/hunter_mode/services/gemini_vision_extractor.dart` (new),
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`
  (mock removed, dynamic pipeline),
  `lib/features/hunter_mode/screens/outfitter_pricelist_scanner_screen.dart`
  (error surfacing + info copy),
  `lib/features/hunter_mode/screens/outfitter_pricelist_verification_screen.dart`
  (metadata badges + structured save),
  `test/pricelist_text_parser_test.dart` (new),
  `pubspec.yaml` / `pubspec.lock` (`google_generative_ai` dep). No Firestore
  rules / index / Storage changes.


## Phase 15 -- Scan save auth-kickout fix, scan-history audit & details-sheet safe-area (added 2026-08-14)

### Auth kickout during price-list save (fixed)
- **Root cause**: `OutfitterPricelistVerificationScreen._saveToFirestore`
  navigated after a successful save with
  `Navigator.of(context).popUntil((route) => route.isFirst)`. `popUntil(isFirst)`
  is a **fragile navigation-stack reset**: the route that satisfies
  `isFirst` depends entirely on how the scanner was reached. The app's
  `initialRoute` is `/splash`, and splash / auth / role-selection screens are
  reached via `pushReplacement` -- so in most flows the outfitter dashboard IS
  the first route (pop lands on the dashboard, the intended behaviour). BUT in
  several real flows (deep-link entry, admin mode-switcher that pushed the
  outfitter dashboard on top of another shell, a scanner reached before the
  role fully resolved, or a stale stack from a prior session) `isFirst` can
  resolve to the `SplashScreen` -- whose `_navigateToNextScreen` re-runs on
  becoming the active route and, on any role-resolution hiccup, falls through
  to `AuthScreen` / `RoleSelectionScreen`. The net observable symptom was
  "saving a price list kicks me back to the login screen."
- **Fix**: replaced the `popUntil(isFirst)` with a **deterministic**
  `Navigator.of(context).pushNamedAndRemoveUntil('/outfitter_dashboard', (_) => false)`.
  This clears the entire nav stack and remounts a fresh outfitter dashboard --
  guaranteeing an authenticated landing on the dashboard (never splash /
  role-selection / login) regardless of how the scanner was opened. It also
  remounts the dashboard's scan-history `StreamBuilder`, so the freshly-saved
  scan appears immediately. The outfitter dashboard route is `RoleGuardedRoute`
  -wrapped, so an outfitter (or an admin in outfitter mode) is admitted; an
  unauthorized caller is bounced to their `defaultHomeFor(role)` by the guard
  -- never to `/login`.
- **No sign-out path exists in the scan flow** (audited): grepped the whole
  `lib/` tree -- the only `signOut()` calls live in `AuthGateService`,
  `AdminAnalyticsService`, and the 2FA-cancel handler in `AuthScreen`; none
  are reachable from the scanner / verification / service code. There is no
  global `FirebaseAuth.authStateChanges()` listener that redirects to login
  on auth changes. So the kickout was purely the nav-stack reset, now fixed.
- File: `lib/features/hunter_mode/screens/outfitter_pricelist_verification_screen.dart`.

### Scan-history persistence & streaming audit (verified + tightened)
- **Persistence path** (single write): scanner ->
  `PricelistScannerService.extractPricelistItems` (Gemini Vision + Afrikaans
  parser, NO Firestore write) -> verification screen ->
  `saveVerifiedPricelist` (the ONLY Firestore `scanned_pricelists.add`).
  `processAndUploadPricelistImage` (the legacy direct-upload path) has zero
  callers -- confirmed via grep -- so there's no double-write / divergent nav.
- **Firestore rule**: `match /scanned_pricelists/{listId} { allow read,
  write: if ownerOrAdmin('outfitterId'); }`. For a CREATE `resource` is null,
  so `isOwnerOf('outfitterId')` evaluates
  `resource == null && request.resource.data.outfitterId == request.auth.uid`
  -- and `saveVerifiedPricelist` stamps `outfitterId: currentUser.uid`, so the
  create is permitted. No rule change needed.
- **Composite index**: `scanned_pricelists (outfitterId ASC, status ASC,
  createdAt DESC)` is present in `firestore.indexes.json` (added in Phase 4),
  so `getMyPriceListsStream`'s equality+equality+orderBy query doesn't error.
- **Stream resilience**: `getMyPriceListsStream` already wraps the
  `snapshots()` in `OfflineStreamGuard.offlineResilient(..., fallback: [])`
  and returns a stable empty stream for an unauthenticated caller -- so the
  history screen's `StreamBuilder` never crashes (it has explicit
  `ConnectionState.waiting` / `snapshot.hasError` / empty branches). No
  silent state-wipe: a hard stream error surfaces the in-UI error state
  (`_buildErrorState`), and a genuine empty result shows `_buildEmptyState`.
- **Version consistency**: `saveVerifiedPricelist` now writes
  `processingVersion: '2.0.0'` (was `'1.0.0'`) to match the dynamic Gemini +
  Afrikaans-parser pipeline introduced in Phase 14 (`processAndUploadPricelistImage`
  already wrote 2.0.0). Saved scans are now stamped with the version that
  actually produced them.
- File: `lib/features/hunter_mode/services/pricelist_scanner_service.dart`.

### Scan-details bottom-sheet safe-area + scroll padding (fixed)
- **Problem**: the `_ScanDetailsSheet` (`DraggableScrollableSheet`) sticky
  action bar (RE-EXPORT / APPLY TO PACKAGE) was a bare `Padding(EdgeInsets.all(20))`
  with no `SafeArea` -- so on gesture-nav phones the buttons sat under the
  Android 3-button / home-indicator bar. The inner items `ListView.builder`
  had only horizontal padding (`EdgeInsets.symmetric(horizontal: 20)`), so the
  last priced line was covered by the sticky action bar.
- **Fix**:
  - Wrapped the action bar in `SafeArea(top: false, bottom: true)` + tuned
    padding (`EdgeInsets.fromLTRB(20, 8, 20, 12)`) so the buttons clear the
    system nav bar on every device (the inset is 0 on hardware-key devices,
    up to ~48px on gesture-nav phones).
  - Added bottom content padding to the items `ListView.builder`
    (`EdgeInsets.fromLTRB(20, 0, 20, 90)`) so the last item scrolls fully
    into view above the sticky action bar.
- File: `lib/features/hunter_mode/screens/scanned_pricelist_history_screen.dart`.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 13
  warnings (unchanged baseline)**, 316 infos. The only issues in touched files
  are the pre-existing `print` debug calls + the `unnecessary_type_check` in
  unchanged `getPriceListsForFarm`/`getMyPriceLists` code (documented since
  Phase 4) -- none introduced by this change. `analysis_options.yaml` was
  auto-touched by the analyzer run and reverted before commit.
- **`flutter test`**: scanner + auth suites green -- `pricelist_text_parser_test`
  (22), `role_guard_test` (31), `user_role_provider_test` (7),
  `offline_stream_guard_test` (5) all pass. Full suite: **223 passed, 4
  failed** -- the 4 failures are the documented pre-existing baseline
  (`saps_tracker`, `offline_sync_queue`, `advanced_ballistics`,
  `bluetooth_mesh`), none touch the changed files, identical to the prior
  commit.
- No Firestore rules / index / Storage / pubspec changes (pure UI +
  navigation fix + a version-string bump).


## Phase 16 -- Client Roster info icon, Firestore permission write fix & loading-loop fix (added 2026-08-14)

### Info icon + feature explanation sheet
- Added a `ContextualInfoIcon` (`Icons.info_outline`) to the Client Roster
  `AppBar.actions` (top-right). Tapping it opens the reusable
  `ExplanationDialog` (modal bottom sheet) describing the feature, with four
  KEY CONCEPTS rows: **Hunter details** (name/ID/nationality/cell/email/
  address), **Booking history** (the package/booking each client is attached
  to), **Permit records** (running list of venison transport permit ids),
  and **Account balances** (notes + assigned package -> per-client view of
  outstanding bookings/deposits/harvests). Reuses `lib/core/widgets/
  contextual_info_icon.dart` (no new widget code) so it matches the rest of
  the app's self-documenting info icons.

### Firestore permission-denied on `client_roster` writes (fixed)
- **Root cause of the raw crash**: the editor sheet's `onSave` callback
  popped the sheet *first* (`Navigator.pop` before `await addClient`), then
  awaited the Firestore write. When the write threw
  `FirebaseException(permission-denied)` -- which happens while the Phase 9
  `client_roster` rules are not yet deployed and the default-deny applies --
  the exception propagated from the `onSave` future up to the button's
  `onPressed` async callback as an **unhandled** error, and the success
  snackbar never showed. Net symptom: tapping ADD TO ROSTER crashed / showed
  a red error screen, and the user lost their input.
- **Fix**: rewrote `onSave` to (1) capture `ScaffoldMessenger` + `Navigator`
  *before* the async gap, (2) `await` the write, (3) `pop()` + success
  snackbar **only on success**, and (4) on `catch (e)` show a floating red
  `‚öÝÔ∏è Failed to save client: ‚Ä¶` snackbar and **keep the editor sheet open**
  so the user can retry without losing their typed fields. The same
  try/catch + snackbar pattern was applied to the `_confirmDelete` REMOVE
  action (which likewise popped before awaiting and had no error handling).
- **Firestore rules verified + made explicit**: the `client_roster` match
  block was split from `allow read, write: if ownerOrAdmin('outfitterId')`
  into explicit `read` / `create` / `update,delete`:
  - `read: ownerOrAdmin('outfitterId')` -- outfitter sees only their own
    roster; admin full access.
  - `create: isSignedIn() && request.resource.data.outfitterId == auth.uid
    || isAdmin()` -- a signed-in outfitter may create a doc whose
    `outfitterId` is their own uid (which `addClient` stamps), or an admin
    may create for any outfitter.
  - `update, delete: ownerOrAdmin('outfitterId')` -- only the owning
    outfitter (or admin) may mutate.
  This is functionally equivalent to the previous `ownerOrAdmin` write
  allowance for the legitimate path (the create still requires
  `outfitterId == auth.uid`), but is now unambiguous and survives the
  default-deny fallback once deployed.
  - **Deploy reminder**: until `firestore:rules` is deployed in a
    credentialed env, the default-deny still rejects `client_roster` writes
    -- but now the app surfaces a graceful snackbar instead of crashing.
- **Composite index** `client_roster (outfitterId ASC, createdAt DESC)` is
  present in `firestore.indexes.json` (added Phase 9), so the stream query
  doesn't error on a missing index.

### Loading-state indefinite loop on stream error (fixed)
- **Root cause of the infinite spinner**: `getMyClientsStream` ended with
  `.handleError((e) { debugPrint(...); return const <ClientProfile>[]; })`.
  `Stream.handleError`'s callback **return value is ignored** -- it only
  *discards* the error and continues the subscription; it does NOT emit the
  returned `[]`. So when the Firestore `.snapshots()` stream errored
  (permission-denied / missing index), the error was silently swallowed and
  the stream never emitted data or a done event -> the `StreamBuilder` stayed
  in `ConnectionState.waiting` **forever** -> the `CircularProgressIndicator`
  spun indefinitely. (The `snapshot.hasError` branch was dead code -- the
  error never reached it.)
- **Fix**:
  - Removed the buggy `.handleError` from `getMyClientsStream` so hard
    errors **propagate** to the consuming `StreamBuilder`. The null-uid ->
    `Stream.value([])` guard is retained. Errors are no longer swallowed
    (documented in the method dartdoc). The unused `package:flutter/
    foundation.dart` import (only there for `debugPrint`) was removed.
  - The screen now caches the stream in a `Stream<List<ClientProfile>>?
    _clientsStream` field (assigned in `initState`). A `_retry()` method
    rebuilds a **fresh** stream (`getMyClientsStream()` returns a new
    `.snapshots()` instance) and `setState`s, so the `StreamBuilder`
    re-subscribes on demand.
  - The `StreamBuilder`'s `snapshot.hasError` branch now renders a dedicated
    `_ErrorState` widget (cloud-off icon + message + the error detail +
    a **RETRY** `FilledButton` calling `_retry`) instead of an `error_outline`
    empty-state. So on a permission/index error the spinner stops and the
    user gets an actionable retry surface -- no more indefinite loop and no
    silent "no clients" masquerade.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0): **0 errors, 0 warnings, 0
  infos** in all changed files. Project total 316 infos + 13 warnings -- all
  pre-existing in unrelated files (unchanged baseline). `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- **`flutter test`**: `outfitter_client_roster_test` (6) + `offline_stream_guard_test`
  (5) + `role_guard_test` (31) all pass. Full suite **223 passed, 4 failed**
  -- the 4 failures are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none touch
  the changed files, identical to the prior commit.
- Files: `lib/features/outfitter_mode/presentation/client_roster_screen.dart`
  (info icon, cached stream + retry, `_ErrorState`, save/delete try/catch,
  removed `_snack`), `lib/features/outfitter_mode/data/services/
  client_roster_manager.dart` (removed `.handleError` + unused import),
  `firestore.rules` (`client_roster` explicit split). No index / Storage /
  pubspec changes (index already present; pure UI + rules-explicitness +
  error-handling pass).
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules` in a
  credentialed env to activate the (already-correct) `client_roster` rules.


## Phase 17 -- Guided Hunt Logs: Firestore permission rules + stream error recovery UI (added 2026-08-14)

Applies the same hardening pattern as Phase 16 (Client Roster) to the
`guided_hunt_logs` collection -- the parallel outfitter harvest-log screen
had the identical two bugs.

### Firestore security rules alignment
- Split the `guided_hunt_logs` match block from
  `allow read, write: if ownerOrAdmin('outfitterId')` into explicit
  `read` / `create` / `update, delete`:
  - `read: ownerOrAdmin('outfitterId')` -- outfitter sees only their own
    logs; admin full access.
  - `create: isSignedIn() && request.resource.data.outfitterId == auth.uid
    || isAdmin()` -- a signed-in outfitter may create a doc whose
    `outfitterId` is their own uid (which `addHuntLog` stamps), or an admin
    may create for any outfitter.
  - `update, delete: ownerOrAdmin('outfitterId')` -- only the owning
    outfitter (or admin) may mutate.
  Functionally equivalent to the previous allowance for the legitimate
  create path, but now unambiguous and survives the default-deny fallback
  once deployed.
- **Composite index** `guided_hunt_logs (outfitterId ASC, huntDate DESC)` is
  present in `firestore.indexes.json` (added Phase 9), so the stream query
  doesn't error on a missing index.
- Deploy reminder: until `firestore:rules` is deployed in a credentialed
  env, the default-deny still rejects `guided_hunt_logs` writes -- but now
  the app surfaces a graceful snackbar instead of crashing.

### Stream hardening & error handling (manager)
- **Root cause of the infinite spinner**: `GuidedHuntLogManager
  .getMyHuntLogsStream` ended with `.handleError((e) { debugPrint(...);
  return const <GuidedHuntLog>[]; })`. `Stream.handleError`'s callback
  **return value is ignored** -- it only *discards* the error and continues
  the subscription; it does NOT emit the returned `[]`. So when the
  Firestore `.snapshots()` stream errored (permission-denied / missing
  index), the error was silently swallowed and the stream never emitted
  data or a done event -> the `StreamBuilder` stayed in
  `ConnectionState.waiting` **forever** -> the `CircularProgressIndicator`
  spun indefinitely. (The `snapshot.hasError` branch was dead code -- the
  error never reached it.)
- **Fix**: removed the buggy `.handleError` so hard errors **propagate** to
  the consuming `StreamBuilder`. The null-uid -> `Stream.value([])` guard is
  retained. Errors are no longer swallowed (documented in the method
  dartdoc). The unused `package:flutter/foundation.dart` import (only there
  for `debugPrint`) was removed.

### UI error state & retry surface (screen)
- The screen now caches the stream in a `Stream<List<GuidedHuntLog>>?
  _logsStream` field (assigned in `initState`). A `_retry()` method rebuilds
  a **fresh** stream (`getMyHuntLogsStream()` returns a new `.snapshots()`
  instance) and `setState`s, so the `StreamBuilder` re-subscribes on demand.
- The `StreamBuilder`'s `snapshot.hasError` branch now renders a dedicated
  `_ErrorState` widget (cloud-off icon + message + the error detail + a
  **RETRY** `FilledButton` calling `_retry`) instead of an `error_outline`
  empty-state. So on a permission/index error the spinner stops and the user
  gets an actionable retry surface -- no more indefinite loop and no silent
  "no logs" masquerade.
- **Write-error handling**: the editor sheet's `onSave` callback previously
  popped the sheet *before* `await addHuntLog`/`updateHuntLog`, so a
  permission-denied `FirebaseException` propagated unhandled and crashed.
  Rewrote `onSave` to capture `ScaffoldMessenger` + `Navigator` before the
  async gap, `await` the write, `pop()` + success snackbar only on success,
  and on `catch` show a floating red `‚öÝÔ∏è Failed to save hunt log: ‚Ä¶`
  snackbar while keeping the editor sheet open so the user can retry without
  losing input. The same try/catch + snackbar was applied to the
  `_confirmDelete` DELETE action (which likewise popped before awaiting with
  no error handling).

### Verification
- **`flutter analyze`** (local Flutter 3.47.0): **0 errors, 0 warnings, 0
  infos introduced** in changed files. The 2 `deprecated_member_use` infos
  (`DropdownButtonFormField.value`) in the editor sheet are **pre-existing**
  (unrelated to this change; only flagged on the local 3.47.0, not the CI
  pin 3.29.1). Project total 316 infos + 13 warnings -- unchanged baseline.
  `analysis_options.yaml` auto-touched by the analyzer was reverted before
  commit.
- **`flutter test`**: `outfitter_client_roster_test` (6 -- covers both
  `ClientProfile` and `GuidedHuntLog` model round-trips) +
  `offline_stream_guard_test` (5) all pass. Full suite **223 passed, 4
  failed** -- the 4 failures are the documented pre-existing baseline
  (`saps_tracker`, `offline_sync_queue`, `advanced_ballistics`,
  `bluetooth_mesh`), none touch the changed files, identical to the prior
  commit.
- Files: `lib/features/outfitter_mode/presentation/guided_hunt_log_screen.dart`
  (cached stream + retry, `_ErrorState`, save/delete try/catch),
  `lib/features/outfitter_mode/data/services/guided_hunt_log_manager.dart`
  (removed `.handleError` + unused import), `firestore.rules`
  (`guided_hunt_logs` explicit split). No index / Storage / pubspec changes
  (index already present; pure UI + rules-explicitness + error-handling
  pass).
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules` in a
  credentialed env to activate the (already-correct) `guided_hunt_logs`
  rules.


## Phase 18 -- Venison Permit Log details sheet & permit creator safe-area bottom padding (added 2026-08-14)

- The two venison-permit surfaces (the draggable details sheet on the permit
  log + the Add/Issue permit form) rendered their bottom action buttons under
  the Android 3-button / iOS gesture nav bar because the action UI sat at the
  very end of the scrollable body with no safe-area inset, and there was no
  bottom content padding so the last section was hidden behind the buttons.
- **Venison Permit details sheet**
  (`lib/features/hunter_mode/widgets/venison_permit_details_sheet.dart`):
  - The EXPORT PDF / VOID / DELETE buttons were previously the tail children
    of the scroll `ListView` (inside the `Expanded`). They are now extracted
    OUT of the scrollable into a **sticky bottom action bar** rendered after
    the `Expanded(ListView)`, wrapped in `SafeArea(top: false, bottom: true)`
    so the buttons clear the system nav bar / gesture line on every device.
    The bar carries the same EXPORT PERMIT PDF (accent) + VOID (orange
    outlined, hidden once `status == 'Voided'`) + DELETE (red) actions, gated
    by the same `onExport`/`onVoid`/`onDelete` callbacks, so no call-site
    changes were needed.
  - The `ListView` gained a trailing `SizedBox(height: 90)` so the last
    section (the signature tiles) scrolls cleanly above the sticky action bar
    instead of being hidden behind it.
- **Add/Issue Venison Permit form**
  (`lib/features/hunter_mode/screens/venison_permit_form_screen.dart`):
  - The `ISSUE & SIGN PERMIT` submit button (the last child of the body
    `ListView`) is now wrapped in `SafeArea(top: false, bottom: true)` so it
    clears the Android 3-button / gesture nav bar on every device.
  - The form `ListView`'s `padding` changed from `EdgeInsets.all(16)` to
    `EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 90.0)` so the
    signature + transport fields (and the submit button) have 90px of
    clearance above the gesture nav bar, clearing the action bar cleanly on
    gesture-nav devices. (90px is reserved explicitly -- the SafeArea on the
    button handles the device inset, so the list padding does not double
    count it.)
- **`flutter analyze`** (local Flutter 3.47.0): **0 errors, 0 warnings, 0
  new infos** in the changed files. The single
  `DropdownButtonFormField.value` deprecation info at
  `venison_permit_form_screen.dart:945` is **pre-existing** (in
  `_AddSpeciesDialog`, unrelated to this change; only flagged on the local
  3.47.0, not the CI pin 3.29.1). Project total 316 infos + 13 warnings --
  unchanged baseline. `analysis_options.yaml` auto-touched by the analyzer
  was reverted before commit.
- **`flutter test`**: `outfitter_client_roster_test` (6) +
  `offline_stream_guard_test` (5) + `role_guard_test` (31) all pass (42
  total). Pure UI padding/layout change -- no logic touched, so no new
  regressions; the 4 documented pre-existing failures remain unchanged and
  unrelated.
- Files: `lib/features/hunter_mode/widgets/venison_permit_details_sheet.dart`
  (sticky SafeArea action bar + 90px list tail), `lib/features/hunter_mode/
  screens/venison_permit_form_screen.dart` (SafeArea on submit button +
  90px list bottom padding). No Firestore / Storage / rules / index / pubspec
  changes (pure presentation-layer padding).


## Phase 19 — Post-auth direct role routing bypass + missing outfitterId self-healing (added 2026-08-14)

### The bypass bug
- `AuthScreen` (email/password sign-in + Google sign-in + 2FA-verified
  callback) routed EVERY freshly-authenticated user to
  `RoleSelectionScreen`, regardless of the role stored on their
  `users/{uid}` document. So a returning outfitter or hunter was bounced
  through "Select Operational Profile" on every login instead of landing
  on their dashboard. The splash screen already did role-aware routing on
  cold launch, but the post-login path in `auth_screen.dart` did not — it
  hardcoded `Navigator.pushReplacement(... RoleSelectionScreen())` in all
  three success paths.
- `SplashScreen._navigateToNextScreen` already mapped
  `AppRole.{admin,hunter,outfitter}` → the matching dashboard and
  `AppRole.unknown` → role selection; the auth screen just wasn't using the
  same contract.

### Direct role routing bypass (auth_screen.dart)
- New `_routeAfterAuth()` async helper resolves the role ONCE via
  `UserRoleProvider.instance.resolveRole(forceRefresh: true)` (cache bypass
  so a stale role from a previous session doesn't bleed), then routes:
  - `outfitter` → `/outfitter_dashboard`
  - `hunter` → `/hunter_dashboard`
  - `admin` → `/admin_dashboard`
  - `unknown` (no role / fetch error / dual-role / unassigned) →
    `RoleSelectionScreen`
  This mirrors `SplashScreen._navigateToNextScreen` exactly, so a
  returning outfitter/hunter/admin bypasses role selection on both cold
  launch AND fresh login. Role selection is now strictly reserved for new
  sign-ups (registration still routes there — a brand-new user has no role
  yet), dual-role accounts, and `unassigned`/`admin` profiles.
- Replaced the three success-path `_navigateToRoleSelection()` /
  `Navigator.pushReplacement(... RoleSelectionScreen())` call sites with
  `_routeAfterAuth()`: (1) email/password sign-in path (post-
  `signInWithEmailAndPassword`), (2) the 2FA `_TwoFAVerificationSheet`
  `onVerified` callback, (3) Google sign-in's no-2FA branch. The
  registration path (new user, no role) keeps its direct
  `RoleSelectionScreen` navigation.
- Removed the now-unused `_navigateToRoleSelection()` helper (would have
  been an `unused_element` warning).

### Missing outfitterId self-healing (auth_screen.dart + splash_screen.dart)
- Outfitter-mode Firestore collections (`trophies`, `venison_permits`,
  `scanned_pricelists`, `client_roster`, `guided_hunt_logs`, `farms`,
  `packages`) are ALL owner-scoped on `outfitterId == auth.uid`. A
  `users/{uid}` document with `role: "outfitter"` but a MISSING (or
  mis-set) `outfitterId` field would make every list query silently empty
  and every create get rejected server-side (permission-denied), crashing
  the dashboard on entry.
- New `_ensureOutfitterSelfLink()` (added to BOTH `AuthScreen` and
  `SplashScreen`, called in the outfitter branch of `_routeAfterAuth` /
  `_navigateToNextScreen` before navigating): reads `users/{uid}`; if
  `outfitterId` is absent or != `uid`, writes `outfitterId: uid` (merge,
  + `updatedAt` server timestamp). Also mirrors the field onto the
  `outfitters/{uid}` enterprise record when that doc exists (the canonical
  outfitter profile keyed by uid; many downstream reads look it up by
  uid). Best-effort, non-fatal — a failure (offline / rules not deployed)
  is swallowed and the user still proceeds to the dashboard; the field can
  be backfilled later. The dashboard's own streams surface errors
  gracefully (Phase 16/17 hardening), so a transient missing field no longer
  crashes the screen.

### Firestore rules note (no change required)
- The `users/{userId}` match block allows a signed-in user to write their own
  doc (`request.auth.uid == userId`), so the `outfitterId` self-link write to
  `users/{uid}` succeeds under the existing rules — this is the critical one,
  since the owner-scoped downstream queries read `outfitterId` off the
  `users` doc (via `UserRoleProvider` / the dashboard managers).
- The `outfitters/{outfitterId}` block allows `update, delete` for
  `isAdmin() || isOwnerOf('uid')` (i.e. `resource.data.uid == auth.uid`).
  `_ensureOutfitterSelfLink` only attempts the `outfitters/{uid}` write when
  that doc already exists (so it's an update, not a create — create is
  admin-only). If the existing enterprise doc lacks a `uid` field equal to
  the caller's uid, the update is denied; that's caught by the non-fatal
  try/catch and the user still proceeds (the field can be backfilled by an
  admin). No rules / index / Storage / pubspec changes were needed.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0): **0 errors, 0 warnings, 0
  new infos** in `lib/features/auth/auth_screen.dart`,
  `lib/core/splash_screen.dart`, `test/role_guard_test.dart`. Project total
  316 infos + 13 warnings — unchanged baseline. `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- **`flutter test`**: `role_guard_test` (35 — incl. 4 new "Post-auth
  direct role routing contract" tests) + `user_role_provider_test` (7) all
  pass (42 total). Full suite **227 passed, 4 failed** — the 4 failures are
  the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none
  touch the changed files, identical to the prior commit (+4 from the new
  routing-contract tests).
- The 4 new tests assert the role→route mapping the router implements:
  each permanent role routes to exactly one dashboard, the routed role is
  admitted by `RoleGuard.canAccess` (no access-denied loop), `unknown` is
  NOT routed to any dashboard (goes to selection), and
  `AppRole.fromString('outfitter'|'hunter')` drives the bypass while
  `'unassigned'`/`'dual'` fall through to selection.
- Files: `lib/features/auth/auth_screen.dart` (`_routeAfterAuth` +
  `_ensureOutfitterSelfLink`, rewired call sites, removed
  `_navigateToRoleSelection`, +`user_role_provider` import),
  `lib/core/splash_screen.dart` (`_ensureOutfitterSelfLink` in the
  outfitter branch + `cloud_firestore` import),
  `test/role_guard_test.dart` (new "Post-auth direct role routing
  contract" group).


## Phase 13 — Outfitter Dashboard Cleanup & Package Creator Camera Capture (added 2026-08-14)

### Outfitter Dashboard responsive cleanup
- The outfitter dashboard (`lib/features/outfitter_mode/outfitter_dashboard.dart`)
  was already structurally sound (Phase 12 had added `SafeBottomInset.of(context)`
  bottom padding + `BouncingScrollPhysics`; the section label + status banner +
  every feature-card title/description already had `maxLines`/`overflow`/`softWrap`
  guards; cards are role-gated via `if (!_isManager)` so no redundant manager-only
  cards render; the feature-card `Row` uses `Expanded` for the text column so
  there is no horizontal overflow). Audit found NO overlapping `Stack`/`Positioned`
  components, NO hardcoded layout spacers causing overflow, and NO redundant
  action cards.
- **Responsive width constraint added**: wrapped the body `ListView` in
  `Center > ConstrainedBox(maxWidth: 560)`. On phones the constraint is wider
  than the viewport so the existing `Padding(horizontal: 20)` governs (no visual
  change); on tablets / large screens the cards now cap at 560 logical px and
  center, so they no longer stretch edge-to-edge (readable line lengths +
  smooth scrolling across various mobile screen ratios). The gradient
  `RadialGradient` background is untouched.

### Package Creator — native camera capture
- `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`
  already had a full image-gallery block (per the "Outfitter Package CRUD
  Polish" entry): `_captureWithCamera()` (image_picker `ImageSource.camera`,
  `imageQuality: 85`, `maxWidth/maxHeight: 1920`), `_pickPackageImages()`
  (`pickMultipleMedia`, `imageQuality: 80`, capped at the remaining slots up to
  `_maxImages = 5`), `_uploadPackageImages()` (per-file compression via
  `ImageService.compressExisting`, upload to `package_images/{outfitterId}/`,
  `SettableMetadata` JPEG, `LinearProgressIndicator` driven by `UploadTask`
  events), and a horizontal thumbnail strip with per-image remove buttons +
  clear "Take Photo" / "Add Photos" tiles.
- **Camera capture hardened**: `_captureWithCamera()` + `_pickPackageImages()`
  now wrap the image_picker calls in `try/catch`. image_picker throws
  `CameraException` / `UnimplementedException` when the camera is unavailable,
  permission is denied, or the platform is unsupported (e.g. desktop without a
  camera plugin). The catch surfaces a friendly red SnackBar
  ("Camera unavailable: …") instead of an unhandled exception crashing the
  creation form mid-flow. New `_friendlyPickerError(e)` maps the thrown
  message to a concise, user-readable reason (camera permission denied / no
  camera detected / camera not supported / could not capture photo). Both
  catch blocks guard `mounted` before touching `ScaffoldMessenger`.
- **Android gallery permission**: added
  `<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />`
  to `android/app/src/main/AndroidManifest.xml` (Android 13+ / API 33+ requires
  this for `pickMultipleMedia` to read the photo library). `CAMERA` +
  `android.hardware.camera` (`required="false"`) were already declared; iOS
  `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` /
  `NSPhotoLibraryAddUsageDescription` were already present and correctly
  describe package-listing image capture.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 13 warnings, 284
  infos** — unchanged baseline; the dashboard + package creator changes are
  analyzer-clean ("No issues found" on both files). No new warnings.
- `flutter test`: **227 passed, 4 failed** — the 4 failures are the documented
  pre-existing baseline (`saps_tracker`, `offline_sync_queue`,
  `advanced_ballistics`, `bluetooth_mesh`), none touch the changed files. No
  regressions.
- Files: `lib/features/outfitter_mode/outfitter_dashboard.dart` (responsive
  width constraint), `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`
  (camera/gallery picker error handling), `android/app/src/main/AndroidManifest.xml`
  (`READ_MEDIA_IMAGES`). No Firestore / Storage / rules / index changes
  (pure UI + manifest hardening).


## Phase 26 — Custom Package Builder refactor (added 2026-08-14)

- Refactored the legacy "Custom Package Itinerary Builder" (a single screen
  that listed every active scanned price list across all outfitters in a
  dropdown and only toggled items on/off with no dates, no party size, no
  lodging/catering, no chat, and no deposit checkout) into a full
  **Custom Package Builder** flow: farm selection → form → submit →
  PayFast deposit + chat, with the 7.5% platform markup **absorbed** into
  the hunter-facing line-item prices (no explicit "Platform Fee" row shown
  to the hunter).
- **1. Rename & routing cleanup**: the hunter dashboard feature card title
  `🦌 Custom Package Itinerary Builder` → `🦌 Custom Package Builder`
  (description + button label `Submit Custom Itinerary Booking` →
  `Submit Custom Package Request` updated). The card now navigates to the
  new `CustomPackageFarmSelectionScreen` (farm-first step) instead of
  straight into the form; the unused `hunter_custom_package_builder_screen`
  import was removed from `hunter_dashboard.dart`.
- **2. Farm selection filter**
  (`lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart`,
  NEW): queries all active scanned price lists (`getAllActivePricelists`),
  indexes the most-recent active list per farm, then resolves the matching
  `farms` docs and renders ONLY farms that have an active price list.
  Farms without an active price list are strictly filtered out — a hunter
  cannot start a custom build against a farm with no pricing data. Each
  qualifying farm card shows province/district + priced-item count; tapping
  it pushes the builder form with the farm + its price list.
- **3. Hunter custom package form**
  (`lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`,
  rewritten): takes a selected farm + price list and lets the hunter assemble
  the itinerary:
  - **Check-in / Check-out** date pickers + a derived **hunting days**
    count.
  - **Hunters** (≥1) and **Observers** (≥0) count steppers.
  - **Species & Trophies**: pulled directly from the farm's price list
    (`itemType != 'fee'` rows), each with the scanned sex/class label +
    trophy size range and a quantity stepper.
  - **Lodging & Catering**: the price list's `itemType == 'fee'` rows
    (accommodation / meals / vehicle / guide / etc.), same qty stepper.
  - **Dynamic pricing**: every line uses the price list's
    `hunterDisplayPriceZAR` (= `basePrice × 1.075`, written at scan-save
    time). The grand total = Σ(qty × hunterDisplayPriceZAR); per-line
    totals update live. **No "Platform Fee" line is shown to the hunter** —
    the 7.5% markup is absorbed into each unit price. The bottom HUD shows
    the grand total (incl. all fees) + the 25% deposit amount due on
    approval.
- **4. Checkout, chat & outfitter ingestion**:
  - `PricelistScannerService.submitCustomPackageBooking` was extended to
    accept `farmName`, `pricelistId`, `lodgingCatering`,
    `checkInDate`/`checkOutDate`, `huntingDays`, `hunterCount`,
    `observerCount`, and now **returns the new booking id**. It writes the
    `bookings` document with `isCustomPackage: true`, `packageName`
    (`"Custom Package · {farm}"`), the species `selectedItemsList` +
    `lodgingCateringList` (each row normalised to the `name` +
    `hunterPrice` + `quantity` shape the existing outfitter booking
    dashboard already renders), the absorbed-commission breakdown
    (`basePriceRands` = total / 1.075, `platformCommissionRands` = total −
    base — kept for outfitter financial visibility only), the 25% deposit
    split (`depositAmountRands` = total × 0.25, `balanceAmountRands`), and
    `status: 'Pending Approval'` (the canonical "pending" state used across
    the booking lifecycle — see note below).
  - **PayFast sandbox checkout**: new `lib/core/services/payfast_checkout.dart`
    (`PayfastCheckout.launchDeposit`) builds the PayFast sandbox payment
    URL (sandbox merchant id/key + the deployed `payfastITNHandler` ITN
    endpoint) with `m_payment_id = bookingId` so the ITN handler reconciles
    the payment back to the booking, and launches it in the external
    browser. After submit, the builder switches to a confirmation view that
    surfaces the deposit amount + a "Pay 25% Deposit via PayFast" button +
    the embedded chat thread. (The hunter's existing "My Bookings" card in
    the marketplace also renders the PayFast button once the outfitter
    approves → `Pending Deposit`.)
  - **Embedded BookingChat**: new reusable
    `lib/features/hunter_mode/widgets/booking_chat_thread.dart`
    (`BookingChatThread`) renders the standard
    `bookings/{bookingId}/chats` subcollection as a stream of bubbles with
    an inline composer (writes via `ChatAndFilterService.sendChatMessage`),
    matching the marketplace / outfitter-dashboard chat look-and-feel. It is
    embedded in the builder's confirmation view (expanded by default) so the
    hunter can negotiate with the outfitter immediately after submitting.
  - **Outfitter incoming requests**: the outfitter booking dashboard
    (`OutfitterBookingDashboardScreen`) query is
    `.where('outfitterId', isEqualTo: currentUserId)` with no status
    filter, so the new custom bookings surface there automatically. Because
    they carry `packageId: 'CUSTOM_BUILT'`, the dashboard renders the
    existing `_buildCustomItemsSection` expandable item breakdown; and
    because `status == 'Pending Approval'`, the APPROVE / DECLINE actions
    appear. The outfitter dashboard's "Incoming Booking Requests" card
    navigates to this screen.
- **Status-string note**: the to-do specified `status: 'pending'`; the app's
  canonical pending state used everywhere (marketplace `_getStatusColor`,
  outfitter dashboard approve-button gate, PayFast deposit-due logic) is
  the exact string `'Pending Approval'`. Using a lowercase `'pending'`
  would orphan the booking (grey status badge, no APPROVE button,
  PayFast-on-approval never appears). So `submitCustomPackageBooking`
  writes `'Pending Approval'` — this IS the pending state in this app's
  vocabulary, and it preserves the full approve → deposit → PayFast → Paid
  lifecycle. `isCustomPackage: true` is the flag that marks the submission
  origin.
- **Firestore rules** (`firestore.rules`): the `scanned_pricelists` match
  block was widened so any signed-in hunter may **read** active price lists
  (they are the custom-package catalog, analogous to `packages`/`farms`
  which are already `isSignedIn()` reads). Writes remain owner-scoped
  (`ownerOrAdmin('outfitterId')` guards create/update/delete). Without
  this change the farm-selection filter + species picker would be
  permission-denied for hunters (the prior rule was `ownerOrAdmin` for
  read too, which is why the legacy builder was broken for hunters).
  **Deploy reminder**: `npx firebase-tools deploy --only firestore:rules`
  in a credentialed env. (No `outfitter_pricelists` collection exists in
  the codebase — no schema, no rules, no writes — so `scanned_pricelists`
  is the sole price-list source; the farm filter checks it.)
- **No new composite indexes required**: `getAllActivePricelists` is a
  single equality query (`status == 'active'`) + orderBy, which uses the
  automatic index. `getActivePricelistForFarm` is
  `farmId` (equality) + `status` (equality) + `createdAt` (desc) — that
  composite (`scanned_pricelists` `(farmId ASC, status ASC, createdAt
  DESC)`) is NOT in `firestore.indexes.json`. To keep the farm-selection
  screen from erroring on the per-farm lookup, the screen does NOT call
  `getActivePricelistForFarm` per farm; it fetches all active lists once
  (`getAllActivePricelists`, automatic-index-safe) and groups in memory.
  `getActivePricelistForFarm` remains available for single-farm lookups
  but will need the composite index deployed before it is used in a
  reactive query.
- **Verification**:
  - `flutter analyze` (local Flutter 3.47.0 stable): **0 errors, 0
    warnings in all modified/new files**. The only issues in touched files
    are the 3 pre-existing `avoid_print` infos (debug `print()` calls in
    `pricelist_scanner_service.dart`, documented baseline since Phase 4 —
    unchanged). Project total: 327 infos + 12 warnings — all pre-existing
    in unrelated files (the baseline dropped by 1 warning because this
    phase cleaned up a pre-existing `unnecessary_type_check` in
    `getPriceListsForFarm`/`getMyPriceLists`). `analysis_options.yaml`
    auto-touched by the analyzer was reverted before commit.
  - `flutter test`: `custom_package_pricing_test.dart` (6 NEW, all pass —
    encodes the absorbed-markup + 25%-deposit contract),
    `package_quantity_test.dart` (24), `role_guard_test.dart` (35) all
    pass (65 total). No regressions; the 4 documented pre-existing
    failures (`saps_tracker`, `offline_sync_queue`, `advanced_ballistics`,
    `bluetooth_mesh`) are unchanged and unrelated.
- Files: `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (rewritten form), `lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart`
  (NEW), `lib/features/hunter_mode/widgets/booking_chat_thread.dart` (NEW),
  `lib/core/services/payfast_checkout.dart` (NEW),
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`
  (extended `submitCustomPackageBooking` + `getAllActivePricelists` +
  `getActivePricelistForFarm` + pre-existing type-check cleanup),
  `lib/features/hunter_mode/hunter_dashboard.dart` (rename + route to farm
  selection), `firestore.rules` (`scanned_pricelists` read widened to
  signed-in), `test/custom_package_pricing_test.dart` (NEW).


## Phase 27 — Off-grid topographic map validation (added 2026-08-14)

Validated and stabilized the off-grid mapping subsystem across the three
audit areas requested by the v4.4 to-do (Item #2): offline tile caching,
on-device coordinate transforms, and battery/background-positioning throttle.

### 1. Offline tile caching audit (fixed)
- **Root cause found**: `OfflineMapCache.initializeCache()` computed a disk
  `cachePath` under `getApplicationDocumentsDirectory()` but then used
  `MemCacheStore()` — a memory-only store — so cached tiles were **never
  persisted to disk** and vanished on every app restart / process kill. The
  comment even framed the memory store as a "fallback if disk arrays lock
  up", but it was actually the default; there was no disk path at all. The
  live `TileLayer` also used a bare `urlTemplate` (network-only) with no
  `tileProvider`, so the Dio cache was never even consulted by flutter_map.
  Separately, `_downloadAreaTiles` was a **simulation** — it ran a 2-second
  `Future.delayed` and added a marker; the code comment itself said "In
  production, this would iterate through tile coordinates".
- **Fix** (`lib/features/hunter_mode/services/offline_map_cache.dart`,
  rewritten):
  - The persistent offline store is now a **deterministic PNG file tree** at
    `{appDocsDir}/map_tiles_cache/{z}/{x}/{y}.png` (created on init). Tiles
    survive app restarts and process kills. The Dio `MemCacheStore` is kept
    only as a short-lived in-memory HTTP-response cache for the active
    download path (clearly documented; it is NOT the offline layer).
  - New public helpers: `tileFile(x,y,z)` (deterministic on-disk path),
    `hasTile(x,y,z)` (sync disk existence, no network), `writeTile(...)`
    (best-effort persist, swallows disk errors), `cachedTileCount` (UI
    diagnostics), `downloadTileRange({bounds, zoom, extraZoomLevels})`
    (real batch pre-download — iterates the XYZ tile range covering the
    visible lat/lng bounds at the chosen zoom ±1 level, downloads each via
    the cache-backed Dio instance, writes it to the deterministic path, skips
    already-cached tiles, and tolerates per-tile network failures so a
    dropped tile does not abort the batch).
  - The slippy-map projection (`lonToTileX`/`latToTileY`/`tileRangeForBounds`
    + the `TileRange` value type) is exposed as pure `static` arithmetic
    (the same Web Mercator formula flutter_map uses internally), so the
    pre-download targets exactly the tiles the live `TileLayer` will request.
- **New `CacheFileTileProvider`** (same file) — a flutter_map `TileProvider`
  wired into the off-grid nav `TileLayer.tileProvider`. Hot path: if the
  tile PNG exists on disk → return `FileImage(file)` with **zero network
  I/O** (this is what makes the map render when the device reports 0
  signal). Cold path: download the tile via the cache-backed Dio, persist
  the bytes to the deterministic path for offline reuse, and decode for the
  current frame via a custom `ImageProvider` (`_CacheAndRenderNetworkImage`)
  using the correct `loadImage(key, ImageDecoderCallback decode)` override.
- **`_downloadAreaTiles` rewritten** (`offline_navigation_screen.dart`): the
  simulation is gone — it now calls `downloadTileRange` on the visible
  bounds at the current zoom (clamped 3–17) ±1 level and surfaces the actual
  count of tiles written ("Cached N topo tiles for offline use" / "Area
  already cached"). The downloaded marker still renders on completion.

### 2. On-device coordinate transforms (audit — already correct, no change)
- Audited the full mapping path for any internet lookup dependency.
  Finding: **all coordinate math is already fully on-device** — no
  geocoding / reverse-geocoding / network lookup is hit when rendering
  waypoints, fence-boundary polylines, or carcass location pins onto the
  topo matrix.
  - `MapPathTracer` (trail + blood-trail path): holds `List<LatLng>` and
    appends raw GPS `LatLng` values; pure in-memory.
  - `AdvancedTacticalService.projectTargetCoordinates` /
    `projectTargetCoordinatesHaversine`: pure `dart:math` spherical
    forward-projection (asin/atan2 great-circle) — no HTTP.
  - `OfflineMapCache` projection helpers (above) are pure arithmetic.
  - Waypoint markers / fence-boundary `PolylineLayer`s / carcass pins all
    consume `LatLng` directly from `flutter_map`/`latlong2`; no coordinate is
    ever resolved through an internet service. Confirmed by grep: zero
    `http`/`dio`/`geocoding` references in the coordinate-rendering path
    (the only network call in the mapping module is the tile PNG fetch, which
    is gated behind the on-disk cache hit).
- No code change was needed for this area; the audit result is recorded
  here so future work does not reintroduce a network coordinate lookup.

### 3. Battery control stabilization (fixed)
- **Root cause found**: the GPS tracking loop
  (`OfflineNavigationScreen._startLocationTracking`) ran
  `Geolocator.getPositionStream` at a fixed `LocationAccuracy.high` /
  5 m distance filter **regardless of whether the hunter was moving**. When
  stationary in the bushveld (e.g. glassing from a hide), that
  high-frequency fix stream drained battery for no map benefit.
  `BatterySaverManager` was a no-op: it toggled a `SharedPreferences` bool
  and `print()`ed a message; the "System Hooks" (throttle BLE / scale back
  location) were comments only — nothing actually throttled.
- **Fix** (`lib/features/hunter_mode/services/battery_saver_manager.dart`,
  extended): centralised an adaptive, dependency-light policy.
  - Constants: `stationaryDistanceMeters = 15.0` (displacement below this =
    stationary), `stationaryWindowSeconds = 90` (must be stationary this long
    before throttling).
  - Two `LocationSettings` presets: `activePreset` (`high` accuracy, 5 m
    filter) and `stationaryPreset` (`medium` accuracy, 50 m filter).
  - `resolveTrackingSettings({batterySaverOn, moving})` — pure function:
    battery saver forces the stationary preset; otherwise moving→active,
    stationary→stationary.
  - `isMoving(previous, current)` — pure function over `Position` values:
    compares great-circle displacement (via `Geolocator.distanceBetween`,
    itself pure arithmetic) to the threshold. Fully unit-testable without
    device hardware.
- **Wired into the nav screen** (`offline_navigation_screen.dart`): the
  screen now reads the persisted battery-saver toggle once at start, then on
  every fix compares the displacement to the previous fix; once the user has
  been stationary for the window it **dynamically restarts the
  `getPositionStream` on the coarse preset** (throttle down), and restores
  the high-frequency preset the moment movement resumes (throttle up).
  Battery-saver mode short-circuits straight to the stationary preset. So
  background positioning intervals now throttle dynamically when the tracking
  system detects the user is stationary in the bushveld.
- Replaced the raw `print()` calls in `BatterySaverManager` with
  `debugPrint` (drops 2 pre-existing `avoid_print` infos from that file).

### 4. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings in all modified/new files**. The only issues in touched files are
  2 pre-existing infos in `offline_navigation_screen.dart`
  (`prefer_final_fields` on `_isRangefinderConnected`; `DropdownButtonFormField.value`
  deprecation — only flagged on the local 3.47.0, not the CI 3.29.1 pin).
  Project total: 324 infos + 11 warnings — all pre-existing in unrelated
  files; the baseline **dropped by 1 warning** because this phase removed the
  pre-existing `unused_local_variable` (`cachePath`) that the old
  `OfflineMapCache` carried. `analysis_options.yaml` auto-touched by the
  analyzer was reverted before commit.
- **`flutter test`**: `off_grid_map_validation_test.dart` (13 NEW, all pass
  — tile projection + battery throttle), `custom_package_pricing_test.dart`
  (6), `package_quantity_test.dart` (24) → 43 pass. No regressions; the 4
  documented pre-existing failures (`saps_tracker`, `offline_sync_queue`,
  `advanced_ballistics`, `bluetooth_mesh`) are unchanged and unrelated.
- Files: `lib/features/hunter_mode/services/offline_map_cache.dart`
  (rewritten: disk tile tree + `CacheFileTileProvider` + real
  `downloadTileRange` + public projection helpers),
  `lib/features/hunter_mode/services/battery_saver_manager.dart`
  (adaptive stationary throttle),
  `lib/features/hunter_mode/screens/offline_navigation_screen.dart`
  (`CacheFileTileProvider` wired into `TileLayer`; real pre-download;
  adaptive GPS stream throttle),
  `test/off_grid_map_validation_test.dart` (NEW). No Firestore / Storage /
  rules / index / pubspec changes (pure on-device mapping + positioning).


## Phase 28 — Automated support emails (added 2026-08-14)

Wired the bug-report and feature-suggestion submission flows to an internal
automated string parser that builds a structured `mailto:support@jag-spoor.co.za`
target with `Uri.encodeComponent`-safe escaping and dynamic injection of the
reporter's User ID, the free-text description, and a System Context block.

### Target widget ingestion
- The two submission widgets are `lib/features/hunter_mode/presentation/
  bug_report_modal.dart` and `feature_suggestion_modal.dart` (the bottom-sheet
  forms surfaced from the Hunter Dashboard). Both previously called
  `FeedbackFirebaseService.launchNativeEmail(subject:, body:)`, which built the
  mailto URI via `Uri(scheme:'mailto', queryParameters:{subject, body})`.
  That `Uri.queryParameters` path encodes spaces as `+` and emits
  raw newlines in some clients, causing the documented line-wrap breaks and
  literal `+` artifacts in the rendered mail body — and it did not inject any
  system context.

### Code handler — `SupportEmailComposer`
- New `lib/features/support/services/support_email_composer.dart`
  (`SupportEmailComposer`, private ctor — pure static API, dependency-light:
  `dart:io Platform` + `url_launcher` only, no extra platform plugins so it
  stays stable on the CI Flutter 3.29.1 pin).
  - `buildBugReportMailtoUri({userId, title, steps, severity})` and
    `buildFeatureSuggestionMailtoUri({userId, title, description, benefits})`
    → return a ready-to-launch `Uri` whose `toString()` is a `mailto:` link
    with every component percent-encoded.
  - `_mailtoUri(subject, body)` builds the link explicitly as
    `mailto:support@jag-spoor.co.za?subject=<enc>&body=<enc>` using
    **`Uri.encodeComponent`** (not `Uri.queryParameters`), so spaces become
    `%20` (not `+`), newlines become `%0A`, and `&`/`=` in user text cannot
    inject a second mailto parameter. This is the encoding every major mobile
    mail client decodes correctly — prevents the line-wrap breaks and `+`
    artifacts the prior path produced.
  - `buildBugReportEmailBody` / `buildFeatureSuggestionEmailBody` (pure
    functions, no I/O — unit-testable) emit the structured tactical /
    platform-expansion brief and inject:
    - **User ID** (`FirebaseAuth.instance.currentUser?.uid ?? 'unknown'`,
      rendered as `N/A` when blank).
    - **Description / steps / benefits / severity** as bulleted lines
      (multi-line input split on `\n`; empty input renders an `N/A` bullet so
      no field is ever a blank line).
    - **System Context** block (`systemContextBlock()`) — platform, OS version,
      locale, CPU core count, app package id, and submission channel, gathered
      from pure `dart:io Platform` (guarded with a try/catch so a web build
      where `Platform` throws falls back to `web`/`unknown` rather than
      crashing). No `package_info_plus`/`device_info_plus` plugin was added —
      the context is sufficient for triage and keeps the builder unit-testable
      on the desktop test runner.
  - `launch(mailtoUri)` hands off to `url_launcher.launchUrl(...,
    LaunchMode.externalApplication)`; returns whether a mail client accepted
    the handoff so the caller can surface a "no mail app found" fallback.

### Rewired submission flows
- `BugReportModal._submitBugReport` and `FeatureSuggestionModal
  ._submitFeatureSuggestion` now: (1) write the report to Firestore (unchanged
  — `bug_reports` / `feature_suggestions` collections, stamped with
  `hunterId` + server timestamp); (2) resolve the current Firebase user id;
  (3) build the mailto URI via `SupportEmailComposer`; (4) launch the native
  mail client; (5) on `launched == false` surface an orange "no mail app
  found — please email support@jag-spoor.co.za manually" snackbar (the report
  is already persisted, so the user's input is never lost) before popping the
  sheet; (6) on any exception show the red failure snackbar. `mounted` is
  guarded before every post-async-gap context use.
- Removed the now-dead `FeedbackFirebaseService.launchNativeEmail`,
  `buildBugReportEmailBody`, and `buildFeatureSuggestionEmailBody` (no callers
  remained) plus its `url_launcher` import; `FeedbackFirebaseService` is now a
  pure Firestore submission service, with a docstring pointing callers to
  `SupportEmailComposer` for email generation. This avoids the deprecated
  duplication and removes the `Uri.queryParameters` encoding path entirely.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0 warnings,
  0 new infos** in all new/modified files. The single info in a touched file
  is the pre-existing `DropdownButtonFormField.value` deprecation in
  `bug_report_modal.dart:183` (only flagged on the local 3.47.0, not the CI
  3.29.1 pin). Project total 324 infos + 11 warnings — unchanged baseline;
  `analysis_options.yaml` auto-touched by the analyzer was reverted before
  commit.
- **`flutter test`**: `support_email_composer_test.dart` (9 NEW — mailto
  target, `Uri.encodeComponent` escaping for spaces/newlines/`&`/`=`, User ID
  + system context injection, empty-field N/A fallback, system-context
  completeness), all pass. Full suite **255 passed, 4 failed** — the 4
  failures are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none touch
  the changed files, identical to the prior commit.
- No Firestore / Storage / rules / index / pubspec changes (pure client-side
  email composition + the existing Firestore writes).
- Files: `lib/features/support/services/support_email_composer.dart` (NEW),
  `lib/features/hunter_mode/presentation/bug_report_modal.dart` (rewired),
  `lib/features/hunter_mode/presentation/feature_suggestion_modal.dart`
  (rewired),
  `lib/features/hunter_mode/services/feedback_firebase_service.dart`
  (dead email helpers removed),
  `test/support_email_composer_test.dart` (NEW).


## Phase 29 — Off-Grid Mesh Sync info icon & integration tests (added 2026-08-14)

### UI info icon & explanatory modal
- The Off-Grid Team Radar screen (`lib/features/hunter_mode/screens/mesh_radar_screen.dart`)
  gained a reusable `ContextualInfoIcon` in its `AppBar.actions` (alongside the
  existing mesh on/off `Switch`). Tapping it opens the standard
  `ExplanationDialog` (the app's self-documenting modal, via
  `lib/core/widgets/contextual_info_icon.dart`) titled "Off-Grid Mesh Sync",
  describing the P2P mesh architecture through three KEY CONCEPTS rows that map
  to the engine's real subsystems:
  - **Automatic Neighbor Discovery** — BLE and Wi-Fi Direct advertise and
    detect nearby team devices automatically; no router or cell tower required.
    (Mirrors `BluetoothMeshSync.startBroadcasting` / `startMeshDiscovery`, which
    use `nearby_connections` `Strategy.P2P_CLUSTER`.)
  - **Encrypted Local Relay** — carcass logs, waypoints, and emergency pings
    are relayed device-to-device across the mesh, so every team member sees the
    latest field state even off-grid. (Mirrors
    `BluetoothMeshSyncService.receiveIncomingMeshPayload` + the
    `carcass_records` / `bookings` / `outfitter_packages` / `invoices` sync
    tables.)
  - **Cloud Catch-Up Sync** — queued transactions are pushed to Firestore
    automatically the moment any single mesh device regains cellular or
    satellite data; no manual sync required. (Mirrors the `isDirty=1` flag the
    merge stamps on every ingested/updated record, which the
    `OfflineSyncQueue` connectivity listener flushes on reconnect.)

### Mesh sync test suite (real code paths, no engine mocks)
- New `test/features/offline_sync/mesh_sync_engine_test.dart` — 9 tests, all
  pass — exercises the REAL `BluetoothMeshSyncService` (in
  `lib/core/services/bluetooth_mesh_sync_service.dart`) against a REAL in-memory
  SQLite database via `sqflite_common_ffi` (added as a `dev_dependency`:
  `sqflite_common_ffi: ^2.4.2`). No mocks of the sync engine itself — the
  existing pre-existing-failing `test/features/sync/bluetooth_mesh_test.dart`
  uses a custom `MockLocalStorageCache` (the mock-based anti-pattern this suite
  avoids); this new suite tests the actual service code.
  - **setUpAll** initializes the FFI SQLite factory globally
    (`sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`) so the real
    `LocalDatabaseService` opens a genuine SQLite database on the desktop test
    runner. **setUp** isolates each test under a fresh temp DB path
    (`databaseFactory.deleteDatabase(testDbPath)` +
    `LocalDatabaseService.resetForTest()`). **tearDown** disposes the mesh
    singleton (`BluetoothMeshSyncService.instance.dispose()`) so each test gets
    a clean service (empty signature cache + zeroed peer count).
  - **Group 1 — Local queue transaction serialization & deserialization:**
    `MeshSyncPayload.serialize()` → `deserialize()` round-trip (every field
    preserved, no raw newlines in the BLE packet frame); `toJson` / `fromJson`
    preserve every field; ISO8601 timestamp with timezone offset parses.
  - **Group 2 — Peer node discovery event broadcasting:**
    `receiveIncomingMeshPayload` emits on the `ingestionStream` (real broadcast
    `StreamController`) AND bumps the `peerCountStream`; own broadcasts are
    skipped (loop prevention — `senderDeviceId == _deviceId`); duplicate
    payloads (same sender/table/recordId/timestamp signature) are de-duplicated
    and emitted exactly once.
  - **Group 3 — Conflict resolution when merging offline records
    (last-writer-wins):** an incoming record with no local match is inserted
    (flat-column data + `isDirty=1` for cloud catch-up); an incoming record
    with an OLDER `timestamp` than the local `updatedAt` does NOT overwrite the
    newer local row; an incoming record with a NEWER `timestamp` DOES overwrite
    the older local row and re-marks it dirty. (The `carcass_records` table
    carries `isDirty` but no timestamp column in the production schema; the
    tests `ALTER TABLE … ADD COLUMN updatedAt/createdAt TEXT` in-test — via an
    idempotent `_tryAddColumn` helper — so the merge's real timestamp-comparison
    branch is exercised against a controlled seeded timestamp, matching the
    `updatedAt`/`createdAt` fallback the engine reads on tables that carry
    those columns.)
- Added `LocalDatabaseService.resetForTest()` (`@visibleForTesting`) — clears
  the static cached `Database` handle so the next `database` access opens a
  fresh test-path DB; the only production-code change, and it is test-gated.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0 warnings,
  0 infos** in all new/modified files (`mesh_radar_screen.dart`,
  `local_database_service.dart`, `mesh_sync_engine_test.dart`). Project total
  0 errors + 11 warnings — unchanged baseline (all pre-existing in unrelated
  files). `analysis_options.yaml` auto-touched by the analyzer was reverted
  before commit.
- **`flutter test test/features/offline_sync/`**: 9/9 pass. Full suite
  **264 passed, 4 failed** — the 4 failures are the documented pre-existing
  baseline (`saps_tracker`, `offline_sync_queue`, `advanced_ballistics`,
  `bluetooth_mesh`), none touch the changed files (+9 from the prior commit's
  255, exactly the new mesh-sync tests).
- No Firestore / Storage / rules / index changes (pure client-side mesh engine
  + UI). The `sqflite_common_ffi` addition is a `dev_dependency` only (does
  not ship in the release build).
- Files: `lib/features/hunter_mode/screens/mesh_radar_screen.dart`
  (info icon + modal), `lib/features/shared/data/services/local_database_service.dart`
  (`resetForTest`), `test/features/offline_sync/mesh_sync_engine_test.dart`
  (NEW), `pubspec.yaml` / `pubspec.lock` (`sqflite_common_ffi` dev dep).

## Phase 30 -- Optical Suite Scope Settings Dynamic Firearm Dropdown Link (added 2026-08-14)

Item #5 of the v4.4 to-do: convert the Optical Suite's static "Link to
Firearm" field into a reactive dropdown populated from the hunter's Digital
Firearm Safe stream, and securely bind the saved scope configuration to the
selected firearm.

### Optical Suite surface (`scope_tools_bottom_sheet.dart`)
- The "OPTICAL SUITE" `ScopeToolsBottomSheet` is the scope-settings profile
  configuration surface (opened from the Hunter Dashboard "Scope Settings &
  Tools" card via `showModalBottomSheet`). Its `_buildFirearmLink()` row is
  the "Link to Firearm" field.
- The field was previously a bare `DropdownButton<String>` that rendered
  `'${rifle.name} (${rifle.caliber})'` with a generic "Link to Firearm" hint
  and no empty-state guidance. The `RifleProfile.name` field is empty for
  real firearm-safe docs (the manual form persists `make`/`model`/`caliber`,
  not `name`), so the dropdown rendered " (--)" for every real rifle.
- Rewritten as a `DropdownButtonHideUnderline > DropdownButtonFormField<String>`:
  - `value`: `firearm.id` (guarded against an id no longer present in the
    safe via an `effectiveValue` null-coalesce, so a just-deleted firearm
    doesn't trigger the "value not in items" assertion).
  - `child`: `Text(rifle.displayName)` formatted as **"make model (calibre)"**
    per spec (e.g. "Tikka T3x (.308 Win)"), with `overflow: ellipsis` so long
    make/model combos never overflow the row.
  - Empty-safe stream: `StreamBuilder<List<RifleProfile>>` over the cached
    `_firearmsStream` (`InventoryBridge.watchSafeFirearms()`, already wrapped
    in `.asBroadcastStream()` in `initState` for multi-listener / re-mount
    safety). When the list is empty the dropdown renders the placeholder
    hint **"No firearms in safe (Add in Firearm Safe)"** (tinted with the
    theme accent), `onChanged` is set to `null` (disabled), and a trailing
    `IconButton` (`add_circle_rounded`, "Open Digital Firearm Safe") appears
    to launch the Firearm Safe registration flow without leaving the
    scope-config sheet. The turret-unit chip is only rendered when a
    firearm is selected (it's meaningless without a host rifle).
- `_onRifleSelected` now stamps the binding: `_optic = (rifle.optic ??
  OpticProfile.defaults).copyWith(firearmId: rifleId)`, so the in-memory
  optic carries the host firearm id and saving persists it (see below).
- New `_FirearmSafeShim` (private `StatefulWidget` at the bottom of the file)
  is pushed by the empty-state CTA. It resolves `ThemeController.instance`
  (the process-wide singleton, see below), awaits `init()` for the persisted
  Day/Night mode (idempotent guard -- no-op if already initialized), and hosts
  the real `FirearmSafeScreen(theme: _theme)` full-screen. On return the
  cached Firestore `_firearmsStream` broadcast re-emits the
  newly-registered firearm automatically, so the dropdown populates with no
  manual reload.

### `OpticProfile` -- `firearmId` binding field (model)
- New `final String firearmId` (default `''`) on `OpticProfile`
  (`lib/features/ballistics/data/models/optic_profile.dart`). Persisted inside
  the nested `optic` map on the firearm document so the binding "travels" with
  the rifle and survives Firestore re-reads. Empty (`''`) for legacy optic
  specs that pre-date the dynamic link (hydrates cleanly via
  `(json['firearmId'] as String?) ?? ''`).
- Added to `toJson()` (`'firearmId': firearmId`), `fromJson()` round-trip, and
  `copyWith(firearmId:)`. `toString()` now logs the bound firearm id.
- `OpticProfile.defaults` still has `firearmId: ''` (a defaults optic is not
  yet bound to any rifle until the user picks one).

### `InventoryBridge.saveOpticProfile` -- secure binding stamp
- `saveOpticProfile(rifleId, optic)` now stamps the optic with `rifleId` as
  its `firearmId` (`optic.copyWith(firearmId: rifleId)`) BEFORE the Firestore
  `set({'optic': ...}, merge: true)`, so the saved scope configuration is
  securely bound to the selected firearm. The blank-rifleId guard (rejects
  empty) already existed; the stamp makes the linkage explicit and
  tamper-evident on the persisted doc.
- Allowed by the existing owner-scoped `firearms/{docId}` Firestore rule
  (`ownerOrAdmin('ownerId')`); no rules / index / Storage change required.

### `RifleProfile` -- make/model fields + `displayName` (model)
- New `final String make` and `final String model` fields on `RifleProfile`
  (`lib/features/ballistics/data/models/rifle_profile.dart`), hydrated from
  the firearm-safe doc's `make` (with `brand`/`manufacturer` fallbacks) and
  `model` (with `modelName` fallback) -- mirroring the field-alias resolution
  the ballistic calc screen already uses. Also tolerates the `calibre` and
  `serial` spelling aliases the safe persists. Added to `toJson()` and
  `copyWith`.
- New `displayName` getter renders the dropdown label as **"make model
  (calibre)"** per spec. Falls back to `name`, then to "Unnamed firearm"
  for legacy/empty docs, and renders an em-dash when calibre is unknown so
  the parentheses are never empty. So a real firearm-safe entry like
  `{make:'Tikka', model:'T3x', caliber:'.308 Win'}` renders
  "Tikka T3x (.308 Win)" (was " (--)" under the old name-only path).

### `ThemeController` -- process-wide singleton
- Added `static ThemeController get instance => _instance ??= ThemeController()`
  + `static ThemeController? _instance` to `ThemeController`
  (`lib/core/theme/app_theme.dart`). `main()` now constructs the app's
  controller via `ThemeController.instance` instead of `ThemeController()`,
  making the singleton the **single source of truth** for the Day/Night
  preference. This lets out-of-tree consumers (the `_FirearmSafeShim` pushed
  from the stateless scope-tools context) read the SAME controller driving
  the `MaterialApp` -- no divergence between the singleton and the main
  instance. Existing in-tree consumers (`widget.theme` passed down from
  `main()`) are unchanged; they hold the same singleton object.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0 warnings,
  0 new infos** in all changed files
  (`optic_profile.dart`, `rifle_profile.dart`, `inventory_bridge.dart`,
  `scope_tools_bottom_sheet.dart`, `app_theme.dart`, `main.dart`,
  `optic_tools_test.dart`). The 3 infos in touched files are the documented
  pre-existing deprecations (`DropdownButtonFormField.value` -- only flagged
  on Flutter ‚â•3.33, NOT the CI 3.29.1 pin; `androidProvider`/`appleProvider`
  in `main.dart`). Project total: **0 errors, 11 warnings, 313 infos** -- all
  pre-existing in unrelated files (unchanged baseline). The one
  `unnecessary_brace_in_string_interps` introduced in `OpticProfile.toString`
  was fixed (braces removed) before commit. `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- **`flutter test test/optic_tools_test.dart`**: **22/22 pass** (was 13;
  +9 new tests: 4 `OpticProfile firearm binding` + 5 `RifleProfile display
  name`). The 9 new tests assert:
  - `firearmId` defaults to `''` for legacy specs; round-trips through JSON;
  - `copyWith(firearmId:)` updates only `firearmId`;
  - a hydrated optic carries the host firearm id;
  - `displayName` formats "make model (calibre)" exactly per spec;
  - brand/manufacturer fallbacks; em-dash for unknown calibre; name then
    "Unnamed firearm" fallbacks; `serial` alias tolerance.
- **`flutter test`** (full suite): **273 passed, 4 failed** -- the 4 failures
  are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none
  touch the changed files; identical failing set to the prior commit (+9
  net pass count vs the Phase-29 264 baseline, exactly the 9 new optic-model
  assertions).
- Files: `lib/features/ballistics/data/models/optic_profile.dart`
  (`firearmId` field + JSON/copyWith/toString),
  `lib/features/ballistics/data/models/rifle_profile.dart` (`make`/`model`
  fields + aliases + `displayName`),
  `lib/features/ballistics/data/inventory_bridge.dart`
  (`saveOpticProfile` stamps `firearmId`),
  `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`
  (`DropdownButtonFormField` + empty-safe placeholder + Firearm-Safe CTA +
  `_onRifleSelected` binding + `_FirearmSafeShim`),
  `lib/core/theme/app_theme.dart` (`ThemeController.instance` singleton),
  `lib/main.dart` (uses singleton),
  `test/optic_tools_test.dart` (+11 tests). No Firestore rules / index /
  Storage / pubspec changes (pure model + UI + secure-binding stamp).

## Phase 31 -- SA Game Guide Animal Card Rowland Ward Data & UI Cleanup (added 2026-08-14)

Item #6 of the v4.4 to-do: resolve the duplicate Rowland Ward display field
on the SA Game Guide animal detail card, populate official South African
Rowland Ward minimum trophy benchmarks, and add an N/A fallback badge with a
grayed-out icon for species with no recorded benchmark.

### 1. Duplicate Rowland Ward UI field removed (`animal_detail_screen.dart`)
- The animal detail card (`lib/screens/animal_detail_screen.dart`) rendered
  the Rowland Ward minimum **twice**: once as a prominent
  "Roland Ward Minimum Trophy Standard" summary `Card` (top of the detail
  body) and again as a `'Rowland Ward Minimum'` `_DetailRow` inside the
  `'TROPHY REFERENCE'` `_SectionCard`. Both read the same underlying value,
  so the trophy minimum appeared twice per animal card.
- The redundant `_DetailRow` was removed; the `'TROPHY REFERENCE'` section now
  renders ONLY the supporting measurement metadata (`Measurement Method` +
  `Horn Description`), which were never duplicated. The Rowland Ward minimum
  now renders exactly **once** per animal card (in the prominent summary).
- The prominent summary card was corrected to read "Rowland Ward" (the
  canonical spelling) and now sources its value from a single new helper,
  `_rowlandWardValue(animal)`, which resolves the three storage aliases
  (`rwMinimum` -> `rolandWardMinimum` -> `trophyMinimumRW`) in priority
  order and trims the result. The old inline resolution + the now-unused
  `_valueOrDash` helper were deleted (would have been `unused_element`).

### 2. Official SA Rowland Ward minimum benchmarks populated
  (`lib/utils/animal_seeder.dart`)
- The static `_rolandWardMetrics` dictionary (the data store backing
  `getRolandWardMinimumForSpecies` / the CSV seeder) was updated with the
  official South African Rowland Ward minimum trophy scores for the 14
  listed species, in the to-do's "X inches" format:
  - greater_kudu: "53 7/8 inches"
  - gemsbok: "40 inches"
  - blue_wildebeest: "28 1/2 inches"
  - black_wildebeest: "22 7/8 inches"
  - impala: "23 5/8 inches"  *(corrected from the prior '23 6/8" (60.0 cm)'*
    *-- the official SA minimum is 23 5/8")*
  - springbok: "14 inches"
  - blesbok: "16 1/2 inches"
  - warthog / common warthog: "13 inches"
  - eland: "35 inches"
  - sable / sable antelope: "41 7/8 inches"  *(corrected from the prior*
    *'40.0' -- the official SA minimum is 41 7/8")*
  - nyala: "27 inches"
  - waterbuck / common waterbuck: "28 inches"
  - red_hartebeest: "23 inches"
  - cape_buffalo: "42 inches"
- Both naming conventions are now keyed so lookups resolve regardless of how
  the caller spells the species: the **space-keyed** form (the CSV
  `commonName` lowercased, e.g. `'greater kudu'`, `'common warthog'`,
  `'sable antelope'`, `'cape buffalo'`, `'red hartebeest'`, `'common
  waterbuck'`) AND the **underscore-keyed** form used by the to-do spec
  (`'greater_kudu'`, `'blue_wildebeest'`, `'black_wildebeest'`, `'warthog'`,
  `'sable'`, `'waterbuck'`, `'red_hartebeest'`, `'cape_buffalo'`).
- The richer measurement metadata (`measurementMethod` + `hornDescription` +
  `earLength`) is preserved for every listed species (and enriched where the
  prior entry was a bare numeric string -- e.g. cape buffalo, red hartebeest,
  waterbuck, sable now carry their measurement method + horn description).
- A latent **duplicate-key compile error** was fixed: the original map still
  held older `'common warthog'`, `'springbok'`, `'springbok (cape)'`, and
  `'springbok (kalahari)'` entries further down that collided with the new
  official entries I added for those species. The stale duplicates were
  removed (the new official entries win), so the `const` map now compiles
  cleanly with no key conflicts.

### 3. N/A fallback badge with icon (`animal_detail_screen.dart`)
- The prominent Rowland Ward summary card now checks the resolved value:
  when `_rowlandWardValue(animal)` returns `null` (the species has no
  recorded benchmark -- null / empty / unlisted), the card renders a new
  `_RowlandWardNaBadge` widget instead of the value text or a bare em-dash.
- `_RowlandWardNaBadge` is a clean, theme-aware pill rendering
  **`Rowland Ward: N/A`** with a grayed-out **`Icons.not_interested`** icon
  (tinted with `theme.subtitleColor` so it reads as "disabled/not
  applicable" in both Day and Night modes), a subtle subtitle-tinted
  background + border. The measurement-type chip is suppressed in the N/A
  state (it's meaningless without a value).
- So an animal with no Rowland Ward record (e.g. a plains zebra, giraffe, or
  hyaena -- none are in the benchmark dictionary) now shows a clear, styled
  "Rowland Ward: N/A" badge instead of an empty field or a confusing "--".

### Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings, 0 infos** in all changed files (`animal_detail_screen.dart`,
  `animal_seeder.dart`, `animal.dart`, `game_guide_rowland_ward_test.dart`).
  Project total: **0 errors, 11 warnings, 323 infos** -- all pre-existing in
  unrelated files (unchanged baseline). The `unused_element` that would have
  been introduced by the now-dead `_valueOrDash` helper was pre-empted by
  deleting the helper. `analysis_options.yaml` auto-touched by the analyzer
  was reverted before commit.
- **`flutter test test/game_guide_rowland_ward_test.dart`**: **36/36 pass**.
  Tests cover: all 14 official SA minimums resolve for BOTH the space-keyed
  (CSV common-name) and underscore-keyed (to-do spec) conventions; case-
  insensitivity + whitespace trimming; null return for an unlisted species
  (the N/A-fallback contract); measurement method/horn description survival
  for listed species; sorted non-empty species-name list; and the
  `Animal`-model alias-resolution priority (`rwMinimum` ->
  `rolandWardMinimum` -> `trophyMinimumRW`) with blank/whitespace collapsing
  to null (renders the N/A badge).
- **`flutter test`** (full suite): **309 passed, 4 failed** -- the 4 failures
  are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none
  touch the changed files; +36 vs the Phase-30 273-pass baseline, exactly
  the new game-guide tests.
- Files: `lib/screens/animal_detail_screen.dart` (duplicate removed,
  `_rowlandWardValue` helper, `_RowlandWardNaBadge`, spelling corrected),
  `lib/utils/animal_seeder.dart` (official SA minimums + underscore aliases
  + stale duplicate keys removed + corrected impala/sable values),
  `test/game_guide_rowland_ward_test.dart` (NEW, 36 tests). No Firestore
  rules / index / Storage / pubspec changes (pure data + presentation +
  the seeder is a one-shot admin seeding utility; existing Firestore
  `animals` docs are unchanged until the seeder is re-run in a
  credentialed env).


## Phase 32 -- Digital Trophy Room Native Trophy Sharing (added 2026-08-14)

Item #7 of the v4.4 to-do: add a native platform share button to every
Digital Trophy Room entry so a hunter can broadcast a harvest dispatch to
WhatsApp / Telegram / Email / SMS via the OS share sheet, with a clean,
engaging composed message.

### Dependency verification
- `share_plus: ^10.0.0` was **already present** in `pubspec.yaml` (used by
  the PDF engine `Share.shareXFiles` and the manual invoice screen). No
  version bump needed; `flutter pub get` resolves cleanly. The 10.x API
  exposes both `Share.share(text, subject:)` (text share) and
  `Share.shareXFiles(...)` (file share); this feature uses the text path.

### Share message composer (pure, testable)
- New `lib/features/hunter_mode/services/trophy_share_composer.dart`
  (`TrophyShareComposer`, private ctor -- pure static API mirroring the
  `SupportEmailComposer` pattern from Phase 28; dependency-light:
  `share_plus` only, no extra platform plugins so it stays stable on the
  CI Flutter 3.29.1 pin and the local 3.47.0 stable).
  - `buildTrophyShareMessage(Map<String, dynamic> trophy)` -- **pure
    function** over a trophy document, fully unit-testable with no
    Flutter / platform plugins. Emits the spec's exact 5-line dispatch:
    ```
    ü¶å Check out my latest harvest on JagSpoor!
    Species: [Species Name]
    Score / Details: [Rowland Ward / SCI Score or horn measurements]
    Date: [Formatted Date]
    Shared via JagSpoor App
    ```
  - **Score / Details line**: trophy documents carry the harvest horn /
    antler measurements (`antlerSpread` / `antlerLength` /
    `antlerCircumference` in cm, `weight` in kg) but **no stored Rowland
    Ward / SCI score**, so the line is assembled from whichever
    measurements are present (the spec's "or horn measurements"
    alternative), joined with `‚Ä¢`. Fields missing from legacy / partial
    entries are skipped (not rendered as 0); when NO measurement is
    recorded the line collapses to `N/A` so it is never blank. Whole
    numbers render without a trailing `.0` (e.g. `Spread 48 cm`, not
    `Spread 48.0 cm`); fractional values render to 1 decimal.
  - **Date line**: `harvestDate` is stored as ISO `YYYY-MM-DD`; validated
    and re-emitted in that canonical shape. A missing / blank date falls
    back to `N/A`; a malformed (unparseable) date is shown verbatim
    (best-effort) rather than dropped.
  - **Species line**: falls back to `Unknown Trophy` when the field is
    null/empty, so the message is always complete and shareable.
  - `shareTrophy(trophy, {subject})` -- thin platform wrapper: composes the
    message and calls `Share.share(message, subject: 'My JagSpoor
    Trophy!')` to activate the native mobile platform share sheet
    (WhatsApp, Telegram, Email, SMS). Returns whether the share
    invocation completed without throwing; a platform error is swallowed
    and reported as `false` so the caller can surface a fallback
    snackbar. `defaultSubject` is exposed for tests.
  - Numeric values stored as strings (legacy / mixed-type docs) are
    parsed via a tolerant `_asNum` (handles `num` + `double.tryParse`),
    matching the storage shape the add/edit trophy screens write.

### UI & button integration
- **Trophy detail screen** (`lib/features/hunter_mode/trophy_detail_screen.dart`):
  added a `share` `IconButton` to the `AppBar.actions` (before the existing
  edit button), tinted with the theme accent, tooltip "Share Trophy". On
  tap it captures `ScaffoldMessenger` before the async gap (matching the
  edit button's existing pattern), calls `TrophyShareComposer.shareTrophy`,
  guards `mounted`, and on failure shows an orange "Unable to open share
  sheet" snackbar. So the full-trophy detail view (all measurements, the
  harvest info, tags) is the primary share surface.
- **Trophy room grid** (`lib/features/hunter_mode/trophy_room_screen.dart`):
  added a compact `share` `IconButton` (18px, tight `BoxConstraints` so it
  fits the 2-column grid card without breaking the aspect ratio) to each
  `_buildPremiumTrophyCard`'s bottom info row, alongside the harvest date
  and the navigation arrow. The date `Text` is wrapped in `Expanded` with
  `ellipsis` so the row never overflows when the share button is present.
  A new `_shareTrophy(trophy)` State method (guards `mounted`, orange
  fallback snackbar on platform failure) backs the card button -- so a
  hunter can share straight from the trophy grid without opening the
  detail view.
- Both surfaces use the SAME composer + the SAME fallback-snackbar
  contract, so the share experience is consistent whether triggered from
  the grid or the detail screen.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings, 0 infos** in all changed/new files
  (`trophy_share_composer.dart`, `trophy_detail_screen.dart`,
  `trophy_room_screen.dart`, `trophy_share_composer_test.dart`). Project
  total: **0 errors, 114 issues** (lib/ only) -- all pre-existing infos in
  unrelated files (unchanged baseline; identical count to the pre-change
  baseline). `analysis_options.yaml` auto-touched by the analyzer / pub
  get was reverted before commit.
- **`flutter test test/trophy_share_composer_test.dart`**: **11/11 pass**.
  Tests cover: full trophy (all four lines + the joined Score/Details
  string); missing species -> `Unknown Trophy`; no measurements -> `N/A`;
  partial measurements (only present fields rendered, absent fields
  omitted not zeroed); missing/blank harvest date -> `N/A`; malformed date
  shown verbatim; numeric-as-string parsing; null measurement values
  skipped; whole-number formatting (no trailing `.0`); exact 5-line
  message structure; and the `defaultSubject` marketing string.
- **`flutter test`** (full suite): **320 passed, 4 failed** -- the 4
  failures are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none
  touch the changed files; +11 vs the Phase-31 309-pass baseline, exactly
  the new trophy-share-composer tests.
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  share composition + the existing `share_plus` dep).
- Files: `lib/features/hunter_mode/services/trophy_share_composer.dart`
  (NEW), `lib/features/hunter_mode/trophy_detail_screen.dart` (AppBar
  share button), `lib/features/hunter_mode/trophy_room_screen.dart`
  (card share button + `_shareTrophy`),
  `test/trophy_share_composer_test.dart` (NEW, 11 tests).


## Phase 33 -- Password Reset Email Delay & Expiration Fix (added 2026-08-14)

Item #8 of the v4.4 to-do: eliminate the perceived password-reset email
delivery delay and token-expiration problems by applying explicit Firebase
`ActionCodeSettings` to every `sendPasswordResetEmail` call (so the reset
code is handled in-app via a deep link instead of a slow generic web flow)
and by adding a 60-second retry cooldown to the reset request UI so users
cannot spam duplicate reset tokens (each new token invalidates the previous
link and re-queues an email delivery -- the root cause of the delay).

### Audit
- Exactly **two** `sendPasswordResetEmail` call sites in the codebase:
  - `lib/features/auth/auth_screen.dart` -- the hunter self-service
    "Forgot Password?" dialog.
  - `lib/features/admin/services/user_management_service.dart` -- the admin
    account-provisioning flow (sends a reset / account-setup email to a
    newly provisioned hunter/outfitter).
- Active package ids resolved from the native build configs:
  - Android `applicationId` = `com.example.jagspoor`
    (`android/app/build.gradle.kts`).
  - iOS `PRODUCT_BUNDLE_IDENTIFIER` = `com.example.jagspoorV42`
    (`ios/Runner.xcodeproj/project.pbxproj`).

### Centralized `ActionCodeSettings` builder
- New `lib/features/auth/services/password_reset_action_code_settings.dart`
  (`PasswordResetActionCodeSettings`, private ctor -- pure static API;
  dependency-light: `firebase_auth` only). All deep-link configuration lives
  in exactly one place so both call sites share identical behaviour.
  - `build()` returns an `ActionCodeSettings` configured with:
    - `url: 'https://jagspoor.page.link/reset-password'` -- the deep-link /
      continue URL the user lands on after completing the reset (a Firebase
      Dynamic Links `*.page.link` domain as suggested in the to-do).
    - `handleCodeInApp: true` -- tells Firebase to deliver the action code
      as an in-app deep link (Universal Link / Android App Link) so the
      installed app opens directly instead of a generic web redirect. This
      is the key setting that eliminates the email delivery delay.
    - `androidPackageName: 'com.example.jagspoor'` -- pins the Android app
      so the link opens the installed app.
    - `androidInstallApp: true` -- offers the Play Store when the app is not
      installed (the to-do's `installApp: true`).
    - `androidMinimumVersion: '1'` -- sends an out-of-date install to the
      Play Store to upgrade.
    - `iOSBundleId: 'com.example.jagspoorV42'` -- pins the iOS app so the
      universal link resolves on Apple devices.
  - **API note**: the project pins `firebase_auth_platform_interface 9.0.5`,
    whose `ActionCodeSettings` API uses flat fields
    (`androidPackageName` / `androidInstallApp` / `androidMinimumVersion` /
    `iOSBundleId` / `handleCodeInApp` / `linkDomain`) -- NOT the newer
    `AndroidPackageName(...)` class / `canHandleCodeInApp` field introduced
    in firebase_auth 12.x. The builder uses the 9.x flat-field shape so it
    compiles cleanly on both the CI Flutter 3.29.1 pin and the local 3.47.0.
  - **Deploy requirement**: the `resetDeepLinkUrl` domain MUST be listed in
    the Firebase Console -> Authentication -> Settings -> Authorized
    domains. If a Dynamic Links domain (`*.page.link`) is used it must also
    be provisioned. Until the domain is authorized the reset call returns
    `auth/invalid-continue-uri`; the auth-screen dialog surfaces that with a
    clear "Reset link domain is not authorized. Please contact support."
    message (added to the error-code switch).

### Applied to both call sites
- **Auth screen** (`lib/features/auth/auth_screen.dart`): the
  `sendPasswordResetEmail` call now passes
  `actionCodeSettings: PasswordResetActionCodeSettings.build()` (via the
  dialog's injected `onSend` callback).
- **Admin user management service**
  (`lib/features/admin/services/user_management_service.dart`):
  `provisionUser` now passes the same `ActionCodeSettings` to its reset
  call, so admin-provisioned account-setup emails use the identical in-app
  deep-link fast path. The existing best-effort `try/catch` (which reports a
  reset failure but still treats provisioning as successful) is preserved.

### Retry cooldown UI (60s)
- The "Forgot Password?" dialog was rewritten from a stateless `AlertDialog`
  into a dedicated `_PasswordResetDialog` `StatefulWidget` that owns its own
  1-second `Timer.periodic` countdown.
  - **On a successful send** the dialog engages a 60-second cooldown
    (`PasswordResetCooldown.defaultCooldownSeconds = 60`): the "Send Reset
    Link" button is disabled (`onPressed: null`) and relabels to
    "Resend in N s" with a live countdown; the email field is locked while
    cooling down; an orange "Please wait N s before requesting another link
    to avoid duplicate reset emails." hint appears.
  - **On Firebase `too-many-requests`** the cooldown is also engaged as a
    safety net so the user cannot hammer the endpoint while the server-side
    rate limit is in effect.
  - **On success** an in-dialog green confirmation banner
    ("Reset link sent! Check your inbox (and spam folder) for instructions.")
    replaces the old transient SnackBar, so the confirmation stays visible
    alongside the cooldown countdown (the user no longer has to re-open the
    dialog to see whether the send worked).
  - The cooldown expiry is held as an absolute `DateTime?` both in the
    parent `_AuthScreenState` (`_resetCooldownUntil`) and in the dialog's own
    State. The parent copy (updated via the `onCooldownEngaged` callback)
    lets a freshly re-opened dialog inherit an in-progress cooldown; the
    dialog's local copy drives the live countdown without depending on a
    parent rebuild. The dialog's timer self-cancels on completion and is
    cancelled in `dispose()`.
  - **Error surfacing**: `invalid-continue-uri` now maps to a clear
    "domain not authorized, contact support" message; `user-not-found`,
    `invalid-email`, and `too-many-requests` keep their tailored copy; the
    generic catch surfaces the Firebase message verbatim. Errors render in
    an in-dialog red banner (not just a SnackBar) so they stay visible while
    the user corrects the email.
- New `lib/features/auth/services/password_reset_cooldown.dart`
  (`PasswordResetCooldown`, private ctor -- pure static API, zero Flutter
  imports so fully unit-testable): `defaultCooldownSeconds` (60), `expiry`
  (absolute expiry timestamp), `remainingSeconds` (floored at 0), and
  `isActive` (before-expiry check). The arithmetic is pure; the dialog owns
  the `Timer.periodic` tick.

### Security
- No secrets / tokens introduced; the deep-link URL is a public link domain.
- Error messages do not leak sensitive information (they restate the Firebase
  error code / public message, never credentials).
- The cooldown is a client-side abuse-prevention measure; Firebase's own
  server-side rate limiting (`too-many-requests`) remains the authoritative
  guard.

### Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings, 0 infos** in all changed/new files
  (`auth_screen.dart`, `password_reset_action_code_settings.dart`,
  `password_reset_cooldown.dart`, `user_management_service.dart`, and both
  test files). Project total: **0 errors, 114 issues** (lib/ only) -- all
  pre-existing infos in unrelated files (unchanged baseline; identical count
  to the pre-change baseline). `analysis_options.yaml` auto-touched by the
  analyzer / pub get was reverted before commit.
- **`flutter test`** (new suites): `password_reset_action_code_settings_test`
  (9/9 pass -- deep-link URL, `handleCodeInApp`, Android package name,
  `androidInstallApp`, minimum version, iOS bundle id, constants stability,
  fresh-instance equivalence, `asMap()` round-trip) +
  `password_reset_cooldown_test` (10/10 pass -- default window, expiry
  arithmetic, remaining-seconds at start / partial / expired / exact-0,
  `isActive` before / at / after expiry).
- **`flutter test`** (full suite): **339 passed, 4 failed** -- the 4
  failures are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none touch
  the changed files; +19 vs the Phase-32 320-pass baseline, exactly the new
  password-reset tests.
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  auth + UI hardening).
- Files: `lib/features/auth/services/password_reset_action_code_settings.dart`
  (NEW), `lib/features/auth/services/password_reset_cooldown.dart` (NEW),
  `lib/features/auth/auth_screen.dart` (dialog rewrite + cooldown State +
  ActionCodeSettings wiring + new `_PasswordResetDialog` widget),
  `lib/features/admin/services/user_management_service.dart`
  (ActionCodeSettings on the provisioning reset call),
  `test/password_reset_action_code_settings_test.dart` (NEW, 9 tests),
  `test/password_reset_cooldown_test.dart` (NEW, 10 tests).
- **Deploy reminder**: authorize `https://jagspoor.page.link` (and provision
  the Dynamic Links domain if used) in the Firebase Console ->
  Authentication -> Settings -> Authorized domains, in a credentialed env.
  Until authorized, the reset call surfaces the in-UI
  `invalid-continue-uri` "domain not authorized" error rather than failing
  silently.


## Phase 34 -- Hunter 7.5% Markup & Outfitter Revenue Protection + PayFast Sandbox Alignment (added 2026-08-14)

Item #9 of the v4.4 to-do: guarantee the 7.5% platform markup is fully
**absorbed** into every hunter-facing price (with the 25% deposit computed
off the marked-up total and **no** explicit "Platform Fee" line shown to
hunters), protect the outfitter financial dashboards so every outfitter
revenue figure reflects the **base amount net of fees** (e.g. R10,000, not
R10,750 and not R9,250), and align the PayFast sandbox charge to the 25%
marked-up deposit via a single-source sandbox launcher.

### 1. Single-source `PricingMath` helper (NEW)
- New `lib/features/hunter_mode/services/pricing_math.dart` — pure,
  dependency-free pricing arithmetic (no Flutter / Firebase imports -> fully
  unit-testable). The single source of truth for the markup, deposit, and
  net-earnings math so hunter-facing and outfitter-facing surfaces can never
  drift.
  - Constants: `platformCommissionRate` (0.075), `depositFraction` (0.25),
    `markupMultiplier` (1.075).
  - `markedUpTotal(base)` = `base √ó 1.075` (absorbed fee).
  - `commissionFromBase(base)` = `base √ó 0.075`.
  - `depositFromBase(base)` = `markedUpTotal(base) √ó 0.25` (25% **off the
    marked-up total**, not the base).
  - `depositFromMarkedUpTotal(total)` / `balanceFromMarkedUpTotal(total)`.
  - `netEarnings({grossRevenue, platformFee})` = `gross ‚àí fee` = the
    outfitter's base earnings (the protected net-revenue figure).
  - `resolveHunterTotal({totalHunterPrice, basePrice})` -- prefers the stored
    marked-up total; for **legacy documents** without `totalHunterPriceRands`
    / `totalPriceZAR`, derives `base √ó 1.075` so a hunter never sees the
    unmarked-up outfitter base price (or R0).
  - `resolveDeposit({storedDeposit, markedUpTotalValue})` -- prefers the stored
    deposit; derives 25% of the marked-up total for legacy docs.
  - `aggregateRevenueSummary(bookings)` -- pure aggregation of a booking-record
    iterable into `{grossRevenue, platformFees, netEarnings, totalBookings}`,
    applying the net-revenue protection rules (gross = sum of marked-up
    totals; fee = 7.5% of base, derived when missing; net = gross ‚àí fee =
    base). Unit-testable without the Firestore emulator.

### 2. Hunter-facing markup presentation (fixed)
- **`hunter_package_marketplace_screen.dart`** -- the marketplace is the
  primary hunter checkout surface. Three pricing sites rewired to
  `PricingMath`:
  - **Package card** (`_PackageCard`): the displayed price previously fell
    back to the bare `basePriceRands` when `totalPriceZAR` was missing
    (legacy packages) -- showing the unmarked-up outfitter base to hunters.
    Now uses `PricingMath.resolveHunterTotal` so the card always shows the
    marked-up total (`base √ó 1.075`), even for legacy packages.
  - **Booking confirmation sheet** (`_BookingConfirmationSheet`): the
    inline `commission = base √ó 0.075; total = base + commission; deposit =
    total √ó 0.25` math replaced with `PricingMath.resolveHunterTotal` +
    `PricingMath.depositFromMarkedUpTotal`. The sheet renders only
    "Total Price" + "25% Deposit (due on approval ¬∑ non-refundable)" --
    **no explicit "Platform Fee" line** is shown to the hunter (the 7.5% is
    fully absorbed into the total). This was already the case; the change
    centralizes the arithmetic so it cannot drift.
  - **Booked-hunts card** (`_BookedHuntCard`): `totalHunterPriceRands ??
    0.0` (which rendered R0 for legacy bookings) replaced with
    `PricingMath.resolveHunterTotal`; the deposit replaced with
    `PricingMath.resolveDeposit`; the balance with
    `PricingMath.balanceFromMarkedUpTotal`. The PayFast charge amount is now
    `depositAmount` directly (resolved off the marked-up total).
- **Custom package builder** (`hunter_custom_package_builder_screen.dart`):
  already correct from Phase 26 -- per-line `hunterDisplayPriceZAR`
  (base √ó 1.075, written at scan-save time) + `_deposit = _grandTotal √ó
  0.25` + `PayfastCheckout.launchDeposit`. Verified unchanged and aligned.

### 3. Outfitter revenue summary protection (fixed)
Two latent bugs in the outfitter financial dashboard corrected:
- **`OutfitterAnalyticsService.getRevenueSummaryStream`**:
  - **Status filter bug**: previously queried `.where('status',
    isEqualTo: 'Approved')` only. After the outfitter approves a booking its
    status transitions `Approved -> Pending Deposit -> Paid -> Completed`, so
    the summary only ever counted bookings stuck at the transient `Approved`
    state -- missing every paid / deposit-pending / completed booking. Now
    uses `.where('status', whereIn: earnedBookingStatuses)` where
    `earnedBookingStatuses = ['Approved','Pending Deposit','Paid',
    'Completed']` (excludes `Pending Approval`, `Declined`, `Cancelled`).
  - **Net-revenue double-count bug**: previously `grossEarnings` = sum of
    `basePriceRands` (already net of fee) and `netEarnings = grossEarnings
    ‚àí platformFees` = base ‚àí fee = base √ó 0.925. For a R10,000 base listing
    this displayed "Net Earnings" = R9,250 -- **understating** the outfitter's
    actual earnings by the fee. The spec requires the outfitter to see
    R10,000. Rewired through `PricingMath.aggregateRevenueSummary`:
    `grossEarnings` = sum of `totalHunterPriceRands` (total collected from
    hunters, incl. the 7.5% fee; derived `base √ó 1.075` for legacy docs);
    `platformFees` = sum of `platformCommissionRands` (derived `base √ó
    0.075` for legacy docs); `netEarnings = gross ‚àí fee = base` = the
    outfitter's actual R10,000 earnings. Now gross = R10,750, fee = R750,
    net = R10,000 (the exact spec figure).
- **`outfitter_revenue_screen._getMonthlyStatsData`**: the monthly revenue
  chart previously summed `totalHunterPriceRands` (the marked-up total) as
  "revenue" -- **overstating** outfitter monthly revenue by the 7.5% fee. Now
  sums `basePriceRands` (net of fees) and uses the same `earnedBookingStatuses`
  `whereIn` filter so the chart agrees with the summary card.
- **Info dialog copy** (`outfitter_revenue_screen` "Gross Revenue vs Platform
  Commission"): corrected to reflect the new semantics -- "Gross Revenue =
  total paid by hunters (incl. 7.5% fee)", "Platform Fee = 7.5% of the
  outfitter base price", "Net Earnings = gross ‚àí fee = the outfitter's base
  price (net of fees)"; and notes only earned bookings are counted.
- **Outfitter booking dashboard** (`outfitter_booking_dashboard_screen`):
  audited -- the per-booking financial breakdown correctly shows
  "Outfitter Base Price" (net) + "7.5% Platform Fee" + "Total (incl. 7.5%
  fee)" + deposit/balance. This is the appropriate outfitter view (they see
  their base net earnings AND the fee split per booking); left unchanged.

### 4. PayFast sandbox alignment (consolidated)
- The marketplace previously carried a **duplicate inline PayFast
  implementation** (its own `_kPayfastSandboxHost` /
  `_kPayfastSandboxMerchantId` / `_kPayfastSandboxMerchantKey` /
  `_kPayfastNotifyUrl` / `_kPayfastReturnUrl` / `_kPayfastCancelUrl`
  constants + its own URL-building + `url_launcher` call), parallel to the
  shared `lib/core/services/payfast_checkout.dart` (`PayfastCheckout`).
  Consolidated: the marketplace's `_initiatePayFastCheckout` now routes
  through `PayfastCheckout.launchDeposit(bookingId:, amount:)` (the same
  launcher the custom-package builder uses), so the sandbox configuration
  (`https://sandbox.payfast.co.za`, merchant `10000100`, ITN endpoint
  `payfastITNHandler`) lives in exactly one place. The duplicate constants
  and the now-unused `url_launcher` import were removed. The amount charged
  is the 25% marked-up deposit (`depositAmount`, resolved off
  `totalHunterPriceRands √ó 0.25`) -- matching the hunter-facing "25% Deposit"
  row exactly. The sandbox config (`isSandbox` semantics -- sandbox host +
  published test credentials) remains fully operational for test checkout
  runs.

### 5. Tests
- `test/pricing_math_test.dart` (NEW, 24 tests, all pass):
  - constants (3); `markedUpTotal` (2); `commissionFromBase` (1);
    `depositFromBase` (2 -- confirms 25% off the marked-up total, NOT the
    base); `depositFromMarkedUpTotal` (1); `balanceFromMarkedUpTotal` (1);
    `netEarnings` (2 -- R10,000 not R10,750 and not R9,250, across a base
    range); `resolveHunterTotal` (4 -- legacy fallback never returns the bare
    base); `resolveDeposit` (2); PayFast deposit alignment (2 -- charge ==
    displayed 25% marked-up deposit, never off the unmarked-up base);
    end-to-end booking contract (1); `aggregateRevenueSummary` (4 -- stored
    totals, legacy derivation, net-never-includes-fee, empty).
- `test/outfitter_revenue_summary_test.dart` (NEW, 5 tests, all pass):
  `earnedBookingStatuses` includes every earned state, excludes
  pre-approval + dead-ends, exactly four statuses, and the filter predicate
  admits/rejects the right statuses.
- Existing `custom_package_pricing_test` (6) still green.

### 6. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings, 0 infos** in all changed/new files
  (`pricing_math.dart`, `outfitter_analytics_service.dart`,
  `hunter_package_marketplace_screen.dart`, `outfitter_revenue_screen.dart`,
  and both test files). Project total: **0 errors, 114 issues** (lib/ only)
  -- identical to the pre-change baseline (all pre-existing infos in
  unrelated files; the consolidation actually removed the marketplace's
  duplicate constants + `url_launcher` import, so no new issues).
  `analysis_options.yaml` auto-touched by the analyzer / pub get was
  reverted before commit.
- **`flutter test`** (full suite): **368 passed, 4 failed** -- the 4
  failures are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none touch
  the changed files; +29 vs the Phase-33 339-pass baseline (24 pricing +
  5 earned-status tests).
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  pricing + UI + PayFast consolidation; the `whereIn` on `status` is a
  single-field equality-range query that uses the automatic index).
- Files: `lib/features/hunter_mode/services/pricing_math.dart` (NEW),
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart`
  (earned-statuses filter + `aggregateRevenueSummary` delegation),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (3 pricing sites rewired to `PricingMath` + PayFast consolidated to
  `PayfastCheckout.launchDeposit` + duplicate constants / `url_launcher`
  import removed),
  `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`
  (monthly revenue net-of-fee + earned-statuses filter + info-dialog copy),
  `test/pricing_math_test.dart` (NEW, 24 tests),
  `test/outfitter_revenue_summary_test.dart` (NEW, 5 tests).


## Phase 35 -- .vscode Gitignore & API Key Security Setup (added 2026-08-14)

Item #10 of the v4.4 to-do: stop VS Code launch configurations (which carry
live API keys / credentials, e.g. `GEMINI_API_KEY`) from leaking into version
control, while still shipping a sanitized template so new environment setups
have a reference config.

### `.gitignore` hardening
- The Flutter template `.gitignore` shipped with `.vscode/` **commented out**
  (the stock comment "you may wish to be included in version control, so this
  line is commented out by default"). For an app that injects API keys via
  `--dart-define` in `launch.json`, that default is a credential-leak hazard.
- Rewrote the `.vscode` block to explicitly ignore the live launch config and
  re-include only the sanitized template:
  ```
  .vscode/*
  .vscode/launch.json
  # Keep the sanitized template (no live keys) tracked for new env setups.
  !.vscode/launch.json.example
  ```
- **Why `.vscode/*` and not a bare `.vscode/`**: Git will **not** descend into
  a directory ignored with a trailing slash, which makes the
  `!launch.json.example` negation impossible (a negated path inside a
  directory-ignored folder is silently dropped). `.vscode/*` ignores the
  directory's **contents** while still letting Git descend so the template
  can be re-included. This was verified empirically: with a bare `.vscode/`,
  `git check-ignore .vscode/launch.json.example` returned "ignored" (negation
  broken); with `.vscode/*` + the negation, `git add --dry-run
  .vscode/launch.json.example` succeeds while `git add --dry-run
  .vscode/launch.json` is rejected as ignored.
- Both `.vscode/launch.json` and the operative `.vscode/*` are present and
  uncommented (the spec's literal requirement); the negation is the only way
  to keep the template tracked.

### Tracked template `.vscode/launch.json.example` (NEW)
- A sanitized VS Code launch config template committed to the repo so new
  contributors can copy it to `.vscode/launch.json` and fill in their own
  key. Contains only the placeholder `GEMINI_API_KEY=YOUR_GEMINI_API_KEY_HERE`
  (no live credential):
  ```json
  {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "JagSpoor (Debug)",
        "request": "launch",
        "type": "dart",
        "program": "lib/main.dart",
        "toolArgs": [
          "--dart-define",
          "GEMINI_API_KEY=YOUR_GEMINI_API_KEY_HERE"
        ]
      }
    ]
  }
  ```
- Onboarding: `cp .vscode/launch.json.example .vscode/launch.json` then
  replace `YOUR_GEMINI_API_KEY_HERE` with a real Gemini key. The copied
  `launch.json` is gitignored, so the live key never enters the index.

### Local dev file left intact & untracked
- A local `.vscode/launch.json` (with a placeholder live key
  `AIzaSyFAKE_LIVE_KEY_REPLACE_ME_...`) exists on disk for local development
  and remains **completely untracked** by the Git index. Verified:
  `git check-ignore -v .vscode/launch.json` -> `.gitignore:34:.vscode/launch.json`
  (ignored); `git status --ignored` shows `!! .vscode/launch.json`; the
  staged set contains only `.gitignore` + `.vscode/launch.json.example`.

### Verification
- `git status` after staging: **Changes to be committed** =
  `modified: .gitignore` + `new file: .vscode/launch.json.example`.
  `.vscode/launch.json` is NOT staged (ignored).
- Scanned the staged diff for credential patterns
  (`api_key=AIza`, `sk-`, `secret`, `password`, `token=`, `Bearer `,
  `AIzaSy[A-Za-z0-9_-]{20,}`): **no live credentials** -- the only match is
  the literal placeholder `YOUR_GEMINI_API_KEY_HERE`.
- `git ls-files .vscode/` -> `.vscode/launch.json.example` (the only tracked
  file under `.vscode/`).
- No Firestore / Storage / pubspec / Dart changes (pure repo-hygiene +
  security). No `flutter analyze` / `flutter test` impact (no code touched).
- Files: `.gitignore` (`.vscode` block rewritten), `.vscode/launch.json.example`
  (NEW, tracked). `.vscode/launch.json` (local, gitignored, untracked).


## Phase 36 -- Gemini API Key Configuration & Resolution Fallback (added 2026-08-14)

Items #1 and #2 of the v4.5 to-do: verify the local VS Code launch
configuration passes `--dart-define=GEMINI_API_KEY=...` correctly, and harden
the Gemini Vision API key lookup with a three-tier fallback chain plus a
reactive key-state helper that drives the scanner's "AI extraction
unavailable" banner.

### 1. Local launch configuration (verified)
- `.vscode/launch.json` exists locally (created in Phase 35) and is
  gitignored (`.gitignore:34 .vscode/launch.json`). Its `toolArgs` use the
  correct VS Code Dart-extension syntax for `--dart-define`:
  ```json
  "toolArgs": [ "--dart-define", "GEMINI_API_KEY=..." ]
  ```
  (two array elements: the flag, then the `KEY=value` pair). The Flutter
  tooling concatenates these into `--dart-define=GEMINI_API_KEY=...` at
  launch, which the new resolver reads via
  `const String.fromEnvironment('GEMINI_API_KEY')`. The tracked
  `.vscode/launch.json.example` template carries the sanitized
  `YOUR_GEMINI_API_KEY_HERE` placeholder so new environment setups have a
  copy-paste reference.

### 2. Centralized `GeminiConfigService` (NEW)
- New `lib/core/services/gemini_config_service.dart` -- the single source of
  truth for the Gemini API key, implementing the spec's three-tier fallback
  chain in priority order:
  1. **`const String.fromEnvironment('GEMINI_API_KEY')`** -- the
     `--dart-define` value baked in at **compile** time (highest priority;
     the canonical way to ship a key in a release build).
  2. **`Platform.environment['GEMINI_API_KEY']`** -- the runtime process env,
     used by desktop / CI runners (`flutter test`, `flutter run -d
     linux/windows`) and by `flutter run --dart-define=...` on mobile. The
     accessor is guarded with try/catch so it is safe on web (where
     `Platform.environment` throws).
  3. **Local storage (SharedPreferences key `jagspoor_gemini_api_key`)** --
     the runtime fallback when `--dart-define` was omitted at compile time.
     An admin / the user can set it at runtime via `setApiKey`; it persists
     across launches. (Firebase Remote Config was NOT added as a dependency
     -- it is not in `pubspec.yaml` and adding it risks the iOS SPM/CocoaPods
     build skew documented in the CI section; `shared_preferences` is already
     a dependency and already used for theme + battery-saver persistence, so
     the local-storage fallback is dependency-light and CI-safe.)
- **Reactive state**: `GeminiConfigService extends ChangeNotifier` (process-
  wide singleton via `GeminiConfigService.instance`, mirroring
  `ThemeController.instance`). `setApiKey` / `clearApiKey` / `reset` call
  `notifyListeners()`, so the scanner banner rebuilds the instant a key is
  set or cleared at runtime.
- **Helper**: `bool get isGeminiApiKeyConfigured` (returns whether a
  non-empty key was resolved from any source) drives the banner state
  reactively. `resolveKey()` returns a `GeminiKeyResolution` carrying the
  key + a `GeminiKeySource` enum (`dartDefine` / `processEnv` /
  `localStorage` / `none`) so the banner can show the *source* too.
- **Testability**: `resolveKey()` is pure given the injected env accessor +
  the cached stored key (no I/O), so it is fully unit-testable without a
  live SharedPreferences / platform environment. `String.fromEnvironment`
  is a `const` that cannot be toggled per-test, so `injectForTesting`
  accepts a `compiledKey` override to exercise the dartDefine branch
  deterministically. The cached resolution is invalidated on
  `setApiKey`/`reset`. `GeminiKeyResolution.toString()` **redacts** the key
  (logs `<redacted>` / `<empty>`) so diagnostics never leak the secret.
- `init()` loads the persisted local-storage key once at startup (called in
  `main()` before `runApp`, alongside `ThemeController.init` /
  `MeasurementFormatter.init`), so the banner reflects the saved key on the
  first frame.

### 3. Wiring
- **`GeminiVisionExtractor`** (`gemini_vision_extractor.dart`): the ctor
  previously read `Platform.environment['GEMINI_API_KEY'] ?? ''` directly.
  Rewired: an explicit ctor `apiKey` still wins (for tests), otherwise the
  key is resolved from `GeminiConfigService` (an injectable
  `configService` param defaults to the singleton). `isAvailable` /
  `_apiKey` now reflect the centralized resolver, so the dart-define + env +
  local-storage fallbacks all apply. The `StateError` "key not configured"
  guard on `extract()` is unchanged (callers still surface a clear message
  instead of faking results).
- **`PricelistScannerService`** (`pricelist_scanner_service.dart`):
  `isAiExtractionAvailable` now delegates to
  `geminiConfig.isGeminiApiKeyConfigured` (exposes the `GeminiConfigService`
  instance as `geminiConfig` so the screen can listen to it), so the
  service and the banner agree on availability.
- **`outfitter_pricelist_scanner_screen.dart`**: the screen State is now a
  `GeminiConfigService` listener (`addListener` in `initState`,
  `removeListener` in `dispose`, `setState` on change). A new
  `_buildAiAvailabilityBanner()` renders a reactive card above the farm
  selector:
  - **Configured** (any source) -> green/accent card: "AI Extraction Ready"
    + the source label ("compile-time --dart-define" / "runtime
    environment" / "local storage").
  - **Not configured** -> orange card: "Gemini API Key Not Configured" +
    guidance to set `GEMINI_API_KEY` via `--dart-define`, the runtime env,
    or local storage.
  So the outfitter knows *why* AI extraction is unavailable before
  attempting a scan, instead of discovering it via a failed scan. The dead
  `_showSuccess` helper (pre-existing `unused_element` warning since
  Phase 4) was removed while editing the file.
- **`main.dart`**: `await GeminiConfigService.instance.init()` added to the
  startup sequence (after `MeasurementFormatter.init()`, before Firebase
  init) + the import.

### 4. Tests
- `test/gemini_config_service_test.dart` (NEW, 20 tests, all pass):
  - **Fallback priority** (4): dart-define wins over env+local; env wins
    when dart-define absent; local storage wins when dart-define+env
    absent; none when all absent.
  - **Empty/whitespace handling** (3): empty env falls through to local
    storage; null env falls through; whitespace env pins the contract.
  - **`isGeminiApiKeyConfigured`** (4): true for each of the three sources,
    false when none.
  - **ChangeNotifier reactivity** (5): `notifyListeners` fires on
    `setApiKey` / `clearApiKey` / `reset`; `setApiKey` trims whitespace;
    empty-string `setApiKey` clears.
  - **Resolution caching** (2): `resolveKey` returns the same instance
    (cached); `setApiKey` invalidates the cache.
  - **Redaction** (2): `toString` redacts a configured key, shows `<empty>`
    for an unconfigured one.

### 5. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings** in all changed/new files
  (`gemini_config_service.dart`, `gemini_vision_extractor.dart`,
  `pricelist_scanner_service.dart`,
  `outfitter_pricelist_scanner_screen.dart`, `main.dart`, the test file).
  The only remaining issues in touched files are the **pre-existing**
  `avoid_print` infos (debug `print()` calls in
  `pricelist_scanner_service.dart`, documented since Phase 4) and the
  pre-existing `deprecated_member_use` infos (`androidProvider` /
  `appleProvider` in `main.dart`). Project total: **0 errors, 113 issues**
  (lib/ only) -- down 1 from the Phase-35 114-issue baseline because the
  dead `_showSuccess` removal dropped one `unused_element` warning.
  `analysis_options.yaml` auto-touched by the analyzer / pub get was
  reverted before commit.
- **`flutter test`** (full suite): **388 passed, 4 failed** -- the 4
  failures are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none
  touch the changed files; +20 vs the Phase-34 368-pass baseline (exactly
  the new Gemini config tests).
- No Firestore / Storage / rules / index / pubspec changes (pure client-side
  configuration + UI; `shared_preferences` was already a dependency).
- Files: `lib/core/services/gemini_config_service.dart` (NEW),
  `lib/features/hunter_mode/services/gemini_vision_extractor.dart`
  (resolves key via `GeminiConfigService`),
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`
  (`isAiExtractionAvailable` delegates to `geminiConfig`),
  `lib/features/hunter_mode/screens/outfitter_pricelist_scanner_screen.dart`
  (reactive availability banner + listener + dead helper removed),
  `lib/main.dart` (`GeminiConfigService.instance.init()` + import),
  `test/gemini_config_service_test.dart` (NEW, 20 tests).


## Phase 37 -- Firestore Security Rules & Permission Audit (startup seeding) (added 2026-08-14)

Item #5 of the v4.5 to-do: audit `firestore.rules` for the collections
populated or read during startup seeding and eliminate
`PERMISSION_DENIED: Missing or insufficient permissions` during startup.

### 1. Audit findings
- **Root cause of startup `PERMISSION_DENIED`**: `BallisticsSeeder.seedAll()`
  (invoked from `main.dart` for EVERY signed-in user on first launch, gated
  only by a `SharedPreferences` `ballistics_seeded` flag) writes the app's
  bundled CSV reference data into three Firestore collections:
  `factory_ammunition`, `bullets`, `propellants`. The previous rules gated all
  three with `allow write: if isAdmin()` -- so the one-time reference-data
  seed was rejected server-side for every non-admin (hunter / outfitter) on
  first launch. The seeder uses `batch.set(..., SetOptions(merge: true))`
  with deterministic doc ids derived from `brand_caliber_grain`, so seeding
  is idempotent and concurrent seeds never clobber each other.
- **`game_guide`**: NOT a Firestore collection -- it is a Hunter Dashboard
  feature-card `id` (navigates to `AnimalListScreen`). No rule needed.
- **`app_config` / `system_benchmarks`**: do NOT exist anywhere in the
  codebase (no reads, no writes, no rules). The to-do listed them as
  examples ("e.g."); the catch-all default-deny (`match /{document=**}
  allow read, write: if false`) covers them defensively. No rule added.
- **`scanned_pricelists`**: already `allow read: if isSignedIn()` (widened
  in Phase 26 so hunters can browse the custom-package catalog); writes
  remain owner-scoped (`ownerOrAdmin('outfitterId')`). Not seeded at
  startup; no change needed.
- **`animals`** (SA Game Guide): `allow read: if true` (public), `allow
  write: if isAdmin()`. `seedAnimalsFromCSV()` writes to `animals` but is a
  MANUAL admin utility (NOT called at startup -- no caller in `main.dart` or
  anywhere except its own definition), so it does not cause startup
  `PERMISSION_DENIED`. No change needed.
- **`users/{uid}`**: `allow read: if isSignedIn()` -- covers the
  `UserRoleProvider` / splash role-resolution read at startup. No change.

### 2. Rule adjustments (the fix)
`firestore.rules` -- the three catalog reference collections were split
from a bare `allow write: if isAdmin()` into explicit read / create+update
/ delete grants:
```
match /factory_ammunition/{docId} {
  allow read: if isSignedIn();
  allow create, update: if isSignedIn();
  allow delete: if isAdmin();
}
```
- **Read** (`isSignedIn()`): unchanged ‚ÄĒ ballistic-calc pickers + marketplace
  read these as reference data.
- **Create / update** (`isSignedIn()`): the fix. Any signed-in user may run
  the one-time seed. This eliminates the `PERMISSION_DENIED` during startup
  seeding for non-admin users. These collections hold static read-only
  catalog reference data (no PII, no financial data), there is no UI path
  that writes to them outside the seeder, and the seeder's `merge: true`
  + deterministic doc ids make the seed idempotent and conflict-free, so
  authenticated create/update is the **minimal** permission needed to seed
  them (the to-do's "allow authenticated users to perform initial seeding
  operations where appropriate"). This mirrors the codebase precedent
  (`venison_permits` create: `isSignedIn()`).
- **Delete** (`isAdmin()`): tightened vs. the old bare `write` (which also
  allowed admin delete). A non-admin must NEVER be able to wipe the shared
  ballistics catalog, so delete remains admin-only while create/update is
  opened for seeding.
All six auth helper functions (`isSignedIn`, `isAdmin`, `isOutfitter`,
`isOwnerOf`, `ownerOrAdmin`, `isBookingPartyViaParent`) verified intact;
the catch-all default-deny (`allow read, write: if false`) retained.

### 3. Structural rules tests (NEW)
`test/firestore_rules_seeding_test.dart` (14 tests, all pass) ‚ÄĒ the
Firestore emulator (`@firebase/rules-unit-testing`) cannot run in this
sandbox (no Java/JVM, no Firebase credentials; see AGENTS.md environment
constraints), so these tests encode the **rule contract** structurally by
parsing `firestore.rules` and asserting the allow clauses (mirrors the
`package_quantity_test` / `custom_package_pricing_test` pattern of encoding
the contract the rules enforce). Groups:
- **Structural integrity** (3): all four core helpers present;
  default-deny present; braces + parentheses balanced.
- **Startup-seeding collections permission contract** (9, 3 per
  collection): for `factory_ammunition` / `bullets` / `propellants` ‚ÄĒ
  read = `isSignedIn()`; create,update = `isSignedIn()` (and the old bare
  `allow write: if isAdmin()` is NOT present); delete = `isAdmin()`.
- **Other startup-read collections** (2): `scanned_pricelists` read =
  `isSignedIn()`; `animals` read = `true` + write = `isAdmin()` (public
  game guide, not seeded at startup).

### 4. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings, 0 infos** in the new test file. No Dart `lib/` changes, so the
  `lib/` baseline is **113 issues** (unchanged from Phase 36 ‚ÄĒ all
  pre-existing). `analysis_options.yaml` auto-touched by the analyzer was
  reverted before commit.
- **`flutter test`**: new `firestore_rules_seeding_test` 14/14 pass.
  Full suite **402 passed, 4 failed** ‚ÄĒ the 4 failures are the documented
  pre-existing baseline (`saps_tracker`, `offline_sync_queue`,
  `advanced_ballistics`, `bluetooth_mesh`), none touch the changed files;
  +14 vs the Phase-36 388-pass baseline (exactly the new rules tests).
- Structural validation: brace balance 0; 39 match blocks; default-deny
  present; all helpers intact (Python parse).
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules` in a
  credentialed env to activate the seed/permission changes. Until
  deployed, the old `write: isAdmin()` gate still rejects the first-launch
  seed for non-admins (surfaced as a `debugPrint` error in the seeder's
  per-collection try/catch ‚ÄĒ non-fatal, but the ballistics reference data
  won't populate for that user until the rules deploy).
- Files: `firestore.rules` (three catalog collections split into
  read / create+update / delete), `test/firestore_rules_seeding_test.dart`
  (NEW, 14 tests), `AGENTS.md`. No Dart `lib/` / Storage / index / pubspec
  changes (pure rules + structural test).


## Phase 38 -- SA Game Guide Rowland Ward Data & Scientific Name Seed Fix (added 2026-08-14)

Item #6 of the v4.5 to-do: populate official Rowland Ward minimum trophy
benchmarks AND scientific (binomial) names for the SA Game Guide species,
force a seed migration so existing installs re-seed the full dataset
automatically, and surface both in the detail UI.

### Background (pre-fix state)
- Phase 31 had already populated the official SA Rowland Ward minimums for
  the 14 to-do species in `_rolandWardMetrics` (and added the duplicate-UI
  removal + N/A badge). BUT:
  - The seeder (`seedAnimalsFromCSV`) wrote `scientificName: ''` ("Not
    provided in CSV" -- the CSV has no scientific-name column), so every
    seeded `animals` doc had a blank scientific name.
  - The seeder only set `trophyMinimumRW`/`rolandWardMinimum`/`rwMinimum`
    + `earLength` from the lookup; it did NOT write `rwMeasurementMethod`
    or `rwHornDescription` (the `getRolandWardMetricsForSpecies` helper
    returned them, but the seeder didn't consume them).
  - `seedAnimalsFromCSV()` was NOT called at startup (only the ballistics
    `BallisticsSeeder.seedAll()` was, in `main.dart`); it was a manual /
    admin utility, so existing installs never re-seeded and stale blank
    scientific names + any legacy em-dash RW values persisted.
  - `firestore.rules` gated `animals` with `allow write: if isAdmin()`, so
    running the seeder at startup for a non-admin would
    `PERMISSION_DENIED` (the same root cause as Phase 37).

### 1. Scientific names dictionary (`lib/utils/animal_seeder.dart`)
- New `_scientificNames` const map keyed by the same lowercased common-name
  variants as `_rolandWardMetrics` (space-keyed CSV common name +
  underscore alias), so a single lookup resolves both the trophy benchmark
  and the scientific name. All 14 to-do species are populated with their
  official binomials / trinomials:
  - Greater Kudu -> `Tragelaphus strepsiceros`
  - Cape Buffalo -> `Syncerus caffer`
  - Blue Wildebeest -> `Connochaetes taurinus`
  - Black Wildebeest -> `Connochaetes gnou`
  - Gemsbok (Oryx) -> `Oryx gazella`
  - Impala -> `Aepyceros melampus`
  - Springbok -> `Antidorcas marsupialis`
  - Blesbok -> `Damaliscus pygargus phillipsi`
  - Common Warthog -> `Phacochoerus africanus`
  - Eland -> `Taurotragus oryx`
  - Sable Antelope -> `Hippotragus niger`
  - Nyala -> `Tragelaphus angasii`
  - Common Waterbuck -> `Kobus ellipsiprymnus`
  - Red Hartebeest -> `Alcelaphus buselaphus caama`
- The broader RW-table species (bushbuck, roan, tsessebe, duikers,
  reedbuck, steenbok, grysbok, bushpig, cheetah, leopard, lion, elephant,
  rhino, hippo, crocodile, dik-dik, suni, Lichtenstein's hartebeest) are
  also keyed with their scientific names so no half-populated records
  remain (any species with a RW benchmark also carries a scientific name).
- New `getScientificNameForSpecies(String)` helper (case-insensitive,
  trimmed, returns null for unlisted -> UI N/A fallback).

### 2. Seeder writes the full benchmark dataset
- `seedAnimalsFromCSV` now resolves `getRolandWardMetricsForSpecies`
  (full metrics: official minimum + measurement method + horn description
  + ear length) and `getScientificNameForSpecies` per row, and constructs
  the `Animal` with `scientificName`, `rwMeasurementMethod`, and
  `rwHornDescription` populated (previously blank). The `searchKeywords`
  now also include the lowercased scientific name so the guide is
  searchable by binomial. The write remains `set(merge: true)`, so a
  re-seed **overwrites** stale null / empty / em-dash Rowland Ward values
  and blank scientific names on existing installs (the to-do's
  "force seed migration / DB overwrite" requirement) -- `merge: true`
  writes every non-null field, so the full benchmark data replaces the
  legacy blanks.

### 3. Forced seed migration via version tag (`lib/main.dart`)
- New `const String gameGuideSeedVersion = 'game_guide_seed_v2'` in
  `animal_seeder.dart`. The `main.dart` startup `addPostFrameCallback`
  runs the game-guide seed (alongside the ballistics seed). Both seeders
  are now FORCED UNCONDITIONAL on every app startup (the
  `SharedPreferences` `ballistics_seeded` / `game_guide_seed_version`
  gates are bypassed for this forced re-seed pass) so local SQLite and
  Firestore are fully populated on every launch -- see the
  "Forced startup re-seed (v4.5 hot-fix)" entry below. Failures are
  caught + `debugPrint`ed (non-fatal; the game guide's own Firestore
  stream surfaces errors gracefully per the Phase 16/17 hardening).
  Import of `animal_seeder.dart` added to `main.dart`.

### Forced startup re-seed (v4.5 hot-fix, added 2026-08-14)
- `lib/main.dart` `addPostFrameCallback` now calls
  `BallisticsSeeder.seedAll()` and `seedAnimalsFromCSV()` UNCONDITIONALLY
  on every app startup -- the `SharedPreferences`
  `ballistics_seeded` boolean gate and the `game_guide_seed_version`
  string gate are both bypassed (the prefs values are still WRITTEN after
  a successful seed so any consumer reading the legacy flag still sees
  `true`/the current version, but the gate no longer prevents the call).
- This forces a full re-seed of the `factory_ammunition` / `bullets` /
  `propellants` ballistics reference catalogs AND the `animals` SA Game
  Guide catalog (official Rowland Ward minimums, measurement method +
  horn description, scientific names, search keywords) on every launch,
  so existing installs whose docs carry null / empty / em-dash Rowland
  Ward values or blank scientific names get the full benchmark dataset
  overwritten via each seeder's `merge: true` / `set(merge: true)` write.
- Both seeders are idempotent (deterministic doc ids, merge writes), so
  re-seeding is safe and conflict-free. The seeders run for every
  signed-in user; the Phase 37 / Phase 38 `firestore.rules` splits
  (`factory_ammunition` / `bullets` / `propellants` / `animals` ->
  `create, update: if isSignedIn()`, `delete: if isAdmin()`) permit the
  non-admin seed without `PERMISSION_DENIED` once deployed.
- `flutter analyze` (Flutter 3.47.0): 0 errors in `lib/main.dart`
  (only the 2 pre-existing `androidProvider` / `appleProvider`
  deprecation infos, documented baseline).

### 4. Firestore rules -- `animals` write split (`firestore.rules`)
- The `animals` match block was widened from `allow write: if isAdmin()`
  into explicit grants so the startup seeder (run for every signed-in user)
  succeeds without `PERMISSION_DENIED`:
  ```
  match /animals/{animalId} {
    allow read: if true;                    // public game guide
    allow create, update: if isSignedIn();  // enables startup seed
    allow delete: if isAdmin();              // catalog cannot be wiped
  }
  ```
  Public read is preserved (the SA Game Guide works offline +
  unauthenticated for reference). `create, update: isSignedIn()` mirrors
  the Phase 37 ballistics-catalog pattern (static reference catalog data,
  `merge: true`, deterministic doc ids -- authenticated seeding is the
  minimal permission; no UI writes to `animals` outside the seeder).
  `delete: isAdmin()` is tightened vs. the old bare `write` so a non-admin
  can never wipe the catalog. **Deploy reminder**:
  `npx firebase-tools deploy --only firestore:rules` in a credentialed env.

### 5. UI display (`lib/screens/animal_detail_screen.dart`)
- The IDENTIFICATION section's "Scientific Name" `_DetailRow` now renders
  `N/A` when `scientificName` is empty (was a blank value), consistent with
  the Rowland Ward N/A badge added in Phase 31. So a species with no
  recorded scientific name shows a clear "N/A" instead of an empty row.
  (The Rowland Ward summary card + TROPHY REFERENCE section already render
  the official minimum, measurement method, and horn description from
  Phase 31; the seeder now actually populates the method + description
  fields onto the doc, so they display.)

### 6. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings, 0 new infos** in the changed files
  (`animal_seeder.dart`, `main.dart`, `animal_detail_screen.dart`,
  `game_guide_rowland_ward_test.dart`, `firestore_rules_seeding_test.dart`).
  The only issues in touched files are the 2 pre-existing
  `androidProvider`/`appleProvider` deprecation infos in `main.dart`
  (documented baseline; only flagged on the local 3.47.0). `lib/` total
  **113 issues** -- unchanged baseline. `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- **`flutter test`**: `game_guide_rowland_ward_test` (43 -- was 36; +7 new:
  5 scientific-name + 2 seed-version) + `firestore_rules_seeding_test`
  (14 -- updated the `animals` assertion to the new create/update/delete
  split) all pass (57 total). Full suite **409 passed, 4 failed** -- the 4
  failures are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none
  touch the changed files; +7 vs the Phase-37 402-pass baseline (exactly
  the new game-guide tests).
- Structural rules validation: brace balance 0; default-deny present;
  `animals` read=true, create+update=isSignedIn, delete=isAdmin, no bare
  write (Python parse).
- Files: `lib/utils/animal_seeder.dart` (`_scientificNames` +
  `getScientificNameForSpecies` + `gameGuideSeedVersion` + seeder writes
  full metrics + scientific name), `lib/main.dart` (startup game-guide seed
  gated by version tag + import), `lib/screens/animal_detail_screen.dart`
  (scientific-name N/A fallback), `firestore.rules` (`animals` write
  split), `test/game_guide_rowland_ward_test.dart` (+7 tests),
  `test/firestore_rules_seeding_test.dart` (`animals` assertion updated),
  `AGENTS.md`. No Storage / index / pubspec changes.
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules` in a
  credentialed env to activate the `animals` seed/permission split. Until
  deployed, the old `write: isAdmin()` gate still rejects the first-launch
  game-guide seed for non-admins (surfaced as a non-fatal `debugPrint` in
  the startup try/catch -- the guide still renders from whatever `animals`
  docs exist + the in-memory RW/scientific-name lookups the field-estimate
  + detail screens use directly).


## Phase 39 -- PayFast deposit checkout button on Pending Deposit booking cards (added 2026-08-14)

Item #7 of the v4.5 to-do: add a prominent, primary PayFast deposit
checkout button directly on the hunter's "My Bookings" cards for
`Pending Deposit` bookings, with loading state + success/failure feedback.

### Background (pre-fix state + the bug)
- The hunter's "My Bookings" tab renders a private `_HunterBookingCard`
  per booking in
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`.
  A PayFast `ElevatedButton.icon` already existed, BUT:
  - It rendered at the **bottom** of the card, below the chat expansion
    panel (`_buildChatDrawer()`), so a hunter had to scroll past the chat
    thread to reach it (not "prominent").
  - **Bug (the core issue)**: the eligibility check was
    `statusLower == 'pending_deposit'` (underscore). The canonical
    post-approval status written by `approveBookingAndRequestDeposit` is
    `'Pending Deposit'` (space-separated) -- `statusLower` becomes
    `'pending deposit'` (space). The underscore form `'pending_deposit'`
    **never matched**, so the Pay button silently failed to render on the
    canonical `Pending Deposit` bookings; it only ever appeared on legacy
    `'Approved'` / `'pending_payment'` bookings (the fallback branches).
    This is why the to-do framed it as "add the button to PENDING DEPOSIT
    bookings" -- for the canonical status it was effectively absent.
  - The label used a raw `'R ${...toStringAsFixed(2)}'` rather than a
    shared currency formatter (the to-do references
    `PricingMath.formatCurrency(...)`).
  - The checkout handler passed no `itemName` (the package title), so the
    PayFast line item read `'JagSpoor Booking <id>'` instead of the
    package name.
  - There was no loading state and no **success** confirmation snackbar
    (only a failure snackbar).

### 1. `PricingMath.formatCurrency` (NEW)
- New pure, locale-independent ZAR formatter in
  `lib/features/hunter_mode/services/pricing_math.dart`:
  `formatCurrency(double)` -> `'R 1\u202F234.50'` (thin-space thousands
  grouping, two decimals, optional minus). It is now the single source of
  truth for the marketplace / booking-card deposit labels (matches the
  app's existing ZAR formatting). Pure string arithmetic via a private
  `_groupThousands` helper (no `intl` dependency, keeps it unit-testable).

### 2. Eligibility fix -- canonical `Pending Deposit` status
- `_HunterBookingCardState`'s `isDepositDueStatus` now matches the
  canonical **space** form case-insensitively
  (`statusLower == 'pending deposit'`), with the legacy
  `'pending_deposit'` / `'approved'` / `'pending_payment'` spellings
  retained as fallbacks for older booking documents. The fix is the
  addition of the `'pending deposit'` (space) match -- the v4.5 Item #7
  bug. `showPayButton = isDepositDueStatus && payfastAmount > 0`
  (unchanged guard). The deposit is resolved via
  `PricingMath.resolveDeposit(storedDeposit: depositAmountRands,
  markedUpTotalValue: totalPrice)` (already in place), where `totalPrice`
  is `PricingMath.resolveHunterTotal(totalHunterPriceRands, basePrice)`.

### 3. Prominent card-level button (above the chat panel)
- The PayFast `ElevatedButton.icon` was **moved from the bottom of the
  card to directly above the chat expansion panel** (rendered right after
  the deposit-breakdown banner, before the date-change banners and the
  chat drawer), so the hunter can pay the deposit without scrolling past
  the chat thread (the to-do's "above or alongside the expansion panel").
  - `icon`: `Icons.lock_clock_rounded` (toggles to an inline
    `CircularProgressIndicator` while `_isPaying`).
  - `label`: `'Pay 25% Deposit (<PricingMath.formatCurrency(depositAmount)>)'`
    (falls back to `'Pay via PayFast'` when deposit is 0, which is gated
    out by `showPayButton` anyway).
  - `style`: `Colors.green.shade700` primary elevated (deep-green accent),
    white foreground, `elevation: 2`, `disabledBackgroundColor` for the
    loading state.
  - `onPressed`: `_initiatePayFastCheckout(bookingId, amount, itemName:
    packageName)` (passes the **package title** as the PayFast line-item
    name); `null` (disabled) while `_isPaying`.

### 4. Loading + success/failure feedback (`_initiatePayFastCheckout`)
- New `_isPaying` state on `_HunterBookingCardState`; the handler now:
  1. guards re-entry (`if (_isPaying) return`), `setState(_isPaying =
     true)`;
  2. captures `ScaffoldMessenger.maybeOf(context)` **before** the async
     gap (the card may unmount while the browser hand-off is in flight);
  3. calls `PayfastCheckout.launchDeposit(bookingId, amount, itemName:)`;
  4. on `launched == true` shows a green confirmation snackbar:
     *"PayFast checkout portal opened in your browser -- pay your 25%
     deposit to confirm the booking."* (5s);
  5. on `launched == false` shows a failure snackbar:
     *"Unable to open PayFast checkout -- no browser app available.
     Please try again or contact the outfitter."*;
  6. `catch` surfaces `'PayFast checkout failed: <e>'`;
  7. `finally` clears `_isPaying` (guarded by `mounted`).
- All post-async-gap context use is `mounted`-guarded; the messenger is
  captured pre-gap so the snackbar still fires if the card unmounted is
  false. `ScaffoldMessenger.maybeOf` (null-safe) avoids the
  `use_build_context_synchronously` lint.

### 5. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings, 0 infos** in the changed files
  (`pricing_math.dart`, `hunter_package_marketplace_screen.dart`).
  `lib/` total **113 issues** -- unchanged baseline (all pre-existing in
  unrelated files; no new issues introduced). `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- **`flutter test`**: new `payfast_deposit_button_test` 16/16 pass
  (5 `formatCurrency` + 4 `resolveDeposit` + 5 eligibility + 2
  item-name). Full suite **425 passed, 4 failed** -- the 4 failures are
  the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`), none
  touch the changed files; +16 vs the Phase-38 409-pass baseline (exactly
  the new tests).
- No Firestore / Storage / rules / index / pubspec changes (pure UI +
  pricing-helper + tests).
- Files: `lib/features/hunter_mode/services/pricing_math.dart`
  (`formatCurrency` + `_groupThousands`),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (`_isPaying` state, eligibility fix, prominent pre-chat button,
  `formatCurrency` label, `itemName` pass-through, loading +
  success/failure snackbars, `mounted` guards),
  `test/payfast_deposit_button_test.dart` (NEW, 16 tests), `AGENTS.md`.


## Phase 40 -- Align Optical Suite firearm dropdown with ballistic calculator selector pattern (added 2026-08-14)

Item #8 of the v4.5 to-do: remove the `+` `IconButton` and the full-screen
navigation fallback from the Optical Suite's top firearm-linking header bar
so the section is a clean, direct `DropdownButtonFormField<String>` that
mirrors the firearm selector in `ballistic_calc_screen.dart`.

### Background (pre-fix state)
- The Optical Suite (`lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`,
  `_buildFirearmLink()`) had already been refactored to a
  `DropdownButtonFormField<String>` fed by a `StreamBuilder<List<RifleProfile>>`
  over the cached `_firearmsStream`
  (`InventoryBridge.watchSafeFirearms().asBroadcastStream()`), with
  `r.displayName` ("make model (calibre)") items, an empty-state hint, and
  reactive `OpticProfile.firearmId` binding via `_onRifleSelected` (Phase 30).
  BUT the header bar still carried two non-selector controls that the to-do
  flagged for removal:
  - A trailing `IconButton(Icons.add_circle_rounded, onPressed: _openFirearmSafe)`
    rendered when the safe was empty (the `+` button) -- a full-screen
    navigation trigger.
  - The `_openFirearmSafe` method + the `_FirearmSafeShim` widget it pushed
    (a `StatefulWidget` that resolved `ThemeController.instance`, awaited
    `init()`, and hosted `FirearmSafeScreen` full-screen) -- the full-screen
    navigation fallback.
- The non-empty hint read `'Link to Firearm'`; the to-do spec and the
  ballistic calculator's own selector use a `Choose Firearm`/`'CHOOSE FIREARM'`
  label, so the hint was inconsistent with the pattern being mirrored.

### 1. Removed the `+` IconButton + full-screen navigation fallback
- Removed the trailing `if (isEmpty) ... IconButton(Icons.add_circle_rounded,
  onPressed: _openFirearmSafe)` block from `_buildFirearmLink()`. The
  dropdown is now the sole header control (the to-do's "clean, direct
  `DropdownButtonFormField<String>`").
- Removed the `_openFirearmSafe()` method (the `Navigator.push` of the shim).
- Removed the `_FirearmSafeShim` widget class + its `_FirearmSafeShimState`
  (the full-screen `FirearmSafeScreen` host) and the preceding docstring --
  the entire tail-of-file navigation-fallback component.
- Removed the two now-unused imports that only the shim consumed:
  `package:jagspoor/core/theme/app_theme.dart` (`ThemeController`) and
  `package:jagspoor/features/hunter_mode/firearm_safe_screen.dart`
  (`FirearmSafeScreen`). (Verified both symbols had no other references in
  the file.)

### 2. Hint aligned with the ballistic calculator selector pattern
- The non-empty hint changed from `'Link to Firearm'` to `'Choose Firearm'`,
  matching the to-do's spec and the ballistic calculator's `'CHOOSE FIREARM'`
  selector label. The empty-state hint stays
  `'No firearms in safe (Add in Firearm Safe)'` (guidance text only -- not a
  navigation trigger; the to-do explicitly wants this text displayed when the
  safe is empty, and the hunter registers firearms via the dashboard's Digital
  Firearm Safe card rather than an in-sheet redirect).

### 3. Turret-unit badge retained (read-only, not a navigation trigger)
- The `Chip` showing `_optic.turretUnitLabel` is retained but now only
  renders `if (!isEmpty)` (it was previously inside an `else` branch that
  also gated the `+` button). It is a read-only context badge, not a
  navigation trigger, so it does not violate the to-do's "clean, direct
  dropdown" requirement; it surfaces the active turret unit (MOA/MIL) next
  to the linked rifle, which is meaningful only once a host firearm is
  selected.

### 4. Reactive profile binding (unchanged, verified)
- Selecting a rifle from the dropdown calls `_onRifleSelected(rifles, id)`,
  which resolves the loaded `RifleProfile`, stamps the optic's `firearmId`
  (`_optic = loaded.copyWith(firearmId: rifleId)`), and `setState`s -- so the
  active `OpticProfile.firearmId` updates in real-time without closing the
  sheet or forcing any page redirect (the to-do's reactive-binding
  requirement, already satisfied by Phase 30 and now the only control on
  the header).

### 5. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings** in `scope_tools_bottom_sheet.dart`. The single remaining issue
  is the documented pre-existing `DropdownButtonFormField.value`
  deprecation info (only flagged on Flutter >=3.33, NOT the CI 3.29.1 pin;
  Phase 30 baseline). `lib/` total **113 issues** -- unchanged baseline
  (removing the shim + 2 imports introduced zero new issues and dropped no
  flagged issues, confirming the removal is clean). `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- **`flutter test`**: `optic_tools_test` (22) + `ballistics_engine_test`
  (18) + `shot_group_analyzer_test` (11) all pass (51 total). Full suite
  **425 passed, 4 failed** -- the 4 failures are the documented
  pre-existing baseline (`saps_tracker`, `offline_sync_queue`,
  `advanced_ballistics`, `bluetooth_mesh`), none touch the changed file;
  identical pass count to the Phase-39 baseline (no new tests needed -- this
  is a UI cleanup removing dead navigation code; the existing optic/ballistics
  suites already cover the `OpticProfile.firearmId` binding +
  `RifleProfile.displayName` models the dropdown reads through).
- No Firestore / Storage / rules / index / pubspec changes (pure UI
  cleanup).
- Files: `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`
  (removed `_FirearmSafeShim` + `_openFirearmSafe` + `+` IconButton + 2
  imports; hint `'Link to Firearm'` -> `'Choose Firearm'`; turret-unit chip
  gated on `!isEmpty`), `AGENTS.md`.


## Phase 41 -- Complete removal of Blood Trail Tracking Radar feature (added 2026-08-14)

Item #9 of the v4.5 to-do: completely remove the Blood Trail Tracking Radar
feature (camera overlay with red-tone isolation to locate blood spoor + GPS
waypoint drops) and all associated UI shortcuts, services, models, and tests.

### 1. Audit
- Code search for `blood_trail` / `BloodTrail` / `blood trail` /
  `blood_tracker` / `BloodTracker` / `TrackingRadar` / `bloodPath` /
  `appendBloodDropNode` / `blood_detection_engine` /
  `BloodDetectionEngine` across `lib` + `test` found the feature confined
  to a small, self-contained cluster with one shared-service bleed:
  - `lib/features/hunter_mode/screens/blood_tracker_screen.dart` -- the
    radar screen (`BloodTrackerScreen`), its `_BloodMaskPainter`
    `CustomPainter` (the HSV red-isolation canvas overlay), and an inline
    `_BloodTrailMapScreen` (the waypoint map). Self-contained -- no public
    classes reused elsewhere.
  - `lib/features/hunter_mode/services/blood_detection_engine.dart` --
    `BloodDetectionEngine` (pixel luminance/YUV420 -> RGBA grid red
    detection). Used EXCLUSIVELY by the radar screen (verified: only caller
    was `blood_tracker_screen.dart`).
  - `test/blood_detection_engine_test.dart` -- 6 unit tests for the engine.
  - `lib/features/hunter_mode/hunter_dashboard.dart` -- import + a
    `DashboardFeature` card `id:'blood_trail_tracker'`
    ('Blood Trail Tracking Radar') navigating to `BloodTrackerScreen`.
  - `lib/features/hunter_mode/services/map_path_tracer.dart` -- the shared
    `MapPathTracer` singleton carried a blood-trail vector path API
    (`_bloodTrailVectorPath`, `bloodPath` getter,
    `appendBloodDropNode`) used exclusively by the radar screen.
  - `lib/features/hunter_mode/screens/offline_navigation_screen.dart` --
    rendered `MapPathTracer.instance.bloodPath` as a crimson `Polyline`
    (the "wounded animal escape route" overlay on the off-grid map).
- No pubspec / asset / Firestore / rules / index references to blood.

### 2. Removed UI components & navigation
- Deleted `lib/features/hunter_mode/screens/blood_tracker_screen.dart`
  (the radar screen + `_BloodMaskPainter` + `_BloodTrailMapScreen` -- the
  custom radar paint/canvas widget + overlay controllers).
- `hunter_dashboard.dart`: removed `import 'screens/blood_tracker_screen.dart'`
  and the `blood_trail_tracker` `DashboardFeature` card (the dashboard
  button / navigation shortcut). The 'Report Bug' card now follows the
  offline-navigation card directly.

### 3. Deprecated / cleaned up services & tests
- Deleted `lib/features/hunter_mode/services/blood_detection_engine.dart`
  (the dedicated blood-detection service tied exclusively to the radar).
- Deleted `test/blood_detection_engine_test.dart` (6 tests for the removed
  engine; removed rather than left referencing a deleted service).
- `map_path_tracer.dart`: removed the blood-trail vector path surface --
  the `_bloodTrailVectorPath` field, the `bloodPath` getter, the
  `appendBloodDropNode` method, and the `_bloodTrailVectorPath.clear()`
  line in `clearAllPaths`. The remaining `MapPathTracer` surface (the
  hunter GPS trail: `_activeHuntingPath` / `currentPath` /
  `startNewPathTracing` / `appendCoordinate` / `stopPathTracing` /
  `clearAllPaths` / `clearRecordedPath` / `isTracking`) is the off-grid
  navigation feature's path primitive and is unchanged -- the only bleed
  from the removed feature into a shared service is gone.
- `offline_navigation_screen.dart`: removed the crimson bloodPath
  `Polyline` (and its "Blood trail vector path" comment) from the
  `PolylineLayer`. With the radar screen gone, `bloodPath` can never be
  populated, so the crimson overlay was dead rendering; the orange
  `currentPath` hunter-trail polyline (the actual off-grid mapping
  feature) is retained.

### 4. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **0 errors, 0
  warnings** in all modified/remaining files
  (`hunter_dashboard.dart`, `map_path_tracer.dart`,
  `offline_navigation_screen.dart`). The only remaining issues in touched
  files are the documented pre-existing baseline
  (`prefer_final_fields` on `_isRangefinderConnected` +
  `DropdownButtonFormField.value` deprecation in the offline nav screen,
  both pre-existing and only the latter flagged on Flutter >=3.33, NOT
  the CI 3.29.1 pin). `lib/` total **113 issues** -- unchanged baseline;
  the removal introduced zero new issues and no broken references
  (verified: a full grep for blood-trail symbols across `lib`+`test`
  returns NONE after the removal). `analysis_options.yaml` auto-touched
  by the analyzer was reverted before commit.
- **`flutter test`**: full suite **419 passed, 4 failed**. The 4 failures
  are the documented pre-existing baseline (`saps_tracker`,
  `offline_sync_queue`, `advanced_ballistics`, `bluetooth_mesh`) -- none
  touch the removed feature; identical failing set to the prior baseline.
  The pass count dropped from 425 to 419 = exactly the 6
  `blood_detection_engine_test` tests removed (which passed previously);
  no new regressions. The adjacent off-grid mapping + mesh-sync + tracking
  suites still pass -- no regressions in adjacent tracking/mapping
  features.
- No Firestore / Storage / rules / index / pubspec / asset changes (pure
  code removal).
- Files DELETED: `lib/features/hunter_mode/screens/blood_tracker_screen.dart`,
  `lib/features/hunter_mode/services/blood_detection_engine.dart`,
  `test/blood_detection_engine_test.dart`.
- Files MODIFIED: `lib/features/hunter_mode/hunter_dashboard.dart`
  (import + dashboard card removed),
  `lib/features/hunter_mode/services/map_path_tracer.dart`
  (blood-trail vector path API removed),
  `lib/features/hunter_mode/screens/offline_navigation_screen.dart`
  (crimson bloodPath polyline removed), `AGENTS.md`.


## Phase 42 -- PayFast Debug Payment Simulator & Return Deep Link Handler (added 2026-08-14)

Item #10 of the v4.5 to-do: add a `kDebugMode`-only PayFast deposit payment
simulator button to the hunter's `Pending Deposit` booking cards so a sandbox
tester can exercise the full booking-status transition without going through
the browser checkout, and wire the PayFast `return_url` to a per-booking deep
link with an app-resume lifecycle listener that detects the browser-checkout
return and prompts a booking-status refresh.

### 1. Pure simulator helper
  (`lib/features/hunter_mode/services/deposit_payment_simulator.dart`, NEW)
- `DepositPaymentSimulator` (private ctor -- pure static API; only Flutter
  import is `kDebugMode` so fully unit-testable, no Firestore).
  - Constants: `paidStatus = 'Paid'` (the canonical post-payment booking
    status set by the deployed ITN handler on `payment_status==COMPLETE`),
    `payfastPaymentStatusComplete = 'COMPLETE'`, `depositPaidAtField =
    'depositPaidAt'`, `depositPaidField = 'depositPaid'`.
  - `depositDueStatuses` -- the statuses awaiting the 25% deposit
    (`Pending Deposit`, `Approved`, `pending_payment`, `pending_deposit`).
  - `canSimulate(String? status)` -- `true` only when `kDebugMode` AND the
    status (case-insensitive) is deposit-due. Release builds always return
    `false` so the simulator can never ship.
  - `simulateUpdateMap()` -- pure `Map<String, dynamic>` carrying the
    post-payment state that mirrors the ITN handler's write: `status ->
    'Paid'`, `paymentStatus -> 'COMPLETE'`, `depositPaid -> true`. The
    server-timestamp fields (`depositPaidAt`, `paymentTimestamp`,
    `updatedAt`) are NOT pure (they need `FieldValue.serverTimestamp()`)
    so they are appended by the service wrapper, not the helper.

### 2. Service method -- `PackageBookingManager.simulateDepositPaid`
- New `simulateDepositPaid({required String bookingId})` on
  `PackageBookingManager`. Gated behind an `assert(kDebugMode, ...)` AND a
  runtime `if (!kDebugMode) throw StateError(...)` (defense-in-depth -- the
  assert is stripped in release but the runtime guard still throws). Requires
  authentication. Resolves the pure `simulateUpdateMap()` and appends the
  three server-timestamp fields, then performs the Firestore `update` on
  `bookings/{bookingId}`.
- **Production security note**: the `bookings` Firestore rule only permits
  the **outfitter** (or the Admin-SDK-backed ITN Cloud Function, which
  bypasses rules entirely) to flip the `status` field. A hunter-triggered
  debug write that flips `status` to `Paid` is therefore permission-denied
  under the production rules. The simulator is `kDebugMode`-only (stripped
  from release builds) and is intended for the outfitter/admin sandbox tester
  or a locally-relaxed rules env -- it is NOT a shipped production code path.
  The card surfaces the permission error as a clear orange snackbar
  ("Simulation failed: ... run as the outfitter/admin or relax rules in your
  sandbox") rather than crashing.

### 3. PayFast return URL / deep link (`PayfastCheckout`)
- `PayfastCheckout` (`lib/core/services/payfast_checkout.dart`) gained
  `buildReturnUrl(String bookingId)` -> the per-booking return deep link
  `https://jagspoor.page.link/payment-return?booking_id=<enc>&status=success`
  (percent-encoded via `Uri.encodeQueryComponent`). The base
  `returnBaseUrl = 'https://jagspoor.page.link/payment-return'` (a Firebase
  Dynamic Links `*.page.link` domain, matching the password-reset deep-link
  pattern from Phase 33).
- `launchDeposit` now passes the per-booking return URL as PayFast's
  `return_url` (was a static `booking-success` web URL), so the app can detect
  a return from the browser checkout carrying the booking id + success flag.
- The `notify_url` / `cancel_url` / sandbox host / merchant credentials are
  unchanged.

### 4. App-resume lifecycle listener (marketplace screen)
- `_HunterPackageMarketplaceScreenState` is now a `WidgetsBindingObserver`
  (`addObserver` in `initState`, `removeObserver` in `dispose`) and tracks an
  `_awaitingPayfastReturn` flag.
- `_HunterBookingCard` gained an optional `onPayFastCheckoutLaunched`
  callback; the card invokes it at the start of `_initiatePayFastCheckout`
  (before the browser hand-off) so the parent screen sets
  `_awaitingPayfastReturn = true`.
- `didChangeAppLifecycleState(AppLifecycleState.resumed)` checks the flag:
  if a checkout was in flight, clears the flag and shows a "Welcome back!
  Verifying your latest booking status from the PayFast checkout..." snackbar.
  The bookings list is already a reactive Firestore `snapshots()` stream, so
  the data auto-updates on resume; the snackbar is the explicit prompt the
  spec wants. (A spurious resume with no checkout in flight shows nothing.)

### 5. Debug simulator button (booking card)
- `_HunterBookingCard` renders a secondary debug `OutlinedButton.icon` below
  the real PayFast deposit button ONLY when `kDebugMode &&
  DepositPaymentSimulator.canSimulate(status) && depositAmount > 0`.
  - Label: `Simulate PayFast Deposit (Debug)`, icon `Icons.bug_report`,
    deep-orange accent.
  - `onPressed`: `_simulatePaymentSuccess(bookingId)` (disabled + spinner
    while `_isSimulating`).
- `_simulatePaymentSuccess(String bookingId)`: guards re-entry, captures the
  `ScaffoldMessenger` before the async gap, calls
  `PackageBookingManager.instance.simulateDepositPaid`, shows a teal
  success snackbar on completion, and a deep-orange failure snackbar
  (carrying the rules-permission guidance) on error. All post-async-gap
  context use is `mounted`-guarded.

### 6. Tests
- `test/deposit_payment_simulator_test.dart` (NEW, 24 tests, all pass):
  - Constants (5): `paidStatus`, `payfastPaymentStatusComplete`,
    `depositPaidAtField`, `depositPaidField`, `depositDueStatuses`
    (canonical + legacy spellings).
  - `canSimulate` (6): canonical `Pending Deposit`, `Approved`, snake-case
    legacy, case-insensitive, false for non-deposit-due (`Paid` /
    `Pending Approval` / `Declined` / `Completed` / `Cancelled`), false for
    null.
  - `simulateUpdateMap` (5): writes `status`/`paymentStatus`/`depositPaid`;
    does NOT contain the server-timestamp fields (added by the service);
    fresh map per call (no shared mutable state).
  - `PayfastCheckout.buildReturnUrl` (4): page.link base, encodes
    booking_id + status=success, percent-encodes special chars, different
    ids -> different urls.
  - Booking status transition contract (4): a `Pending Deposit` booking
    transitions to `Paid`; a `Paid` / `Pending Approval` booking cannot be
    simulated forward; the simulated `Paid` status is not deposit-due (a
    second simulation attempt is rejected).
- The Flutter test runner executes in debug mode, so `kDebugMode` is true
  in the tests and `canSimulate` reflects the status check only (the
  intended contract).

### 7. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **No issues found**
  in all changed/new files (`deposit_payment_simulator.dart`,
  `payfast_checkout.dart`, `package_booking_manager.dart`,
  `hunter_package_marketplace_screen.dart`,
  `deposit_payment_simulator_test.dart`). Project baseline unchanged.
  `analysis_options.yaml` auto-touched by the analyzer / pub get was
  reverted before commit.
- **`flutter test test/deposit_payment_simulator_test.dart`**: 24/24 pass.
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  debug UI + a deep-link URL shape; the bookings rule already permits the
  outfitter / ITN handler to flip `status`, and the debug simulator surfaces
  the permission error gracefully when a hunter triggers it under prod
  rules).
- Files: `lib/features/hunter_mode/services/deposit_payment_simulator.dart`
  (NEW), `lib/core/services/payfast_checkout.dart` (per-booking return deep
  link + `buildReturnUrl`), `lib/features/hunter_mode/services/
  package_booking_manager.dart` (`simulateDepositPaid` + imports),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (`WidgetsBindingObserver` + app-resume listener + `_awaitingPayfastReturn`
  flag + `onPayFastCheckoutLaunched` callback + debug simulator button +
  `_simulatePaymentSuccess`), `test/deposit_payment_simulator_test.dart`
  (NEW, 24 tests), `AGENTS.md`.

## Phase 43 -- Sandbox booking rules widening for debug deposit simulator (added 2026-08-14)

⚠️ **Sandbox/debug-only change — must be reverted before any production
deployment.**

### What changed
- `firestore.rules` `match /bookings/{bookingId}` block was widened so that
  ANY signed-in user may read, create, and update bookings (delete stays
  admin-only), as requested for sandbox checkout + `kDebugMode` debug
  simulator testing (Phase 42):
  ```
  allow read: if isSignedIn();
  allow create: if isSignedIn();
  allow update: if isSignedIn();  // Enables hunter deposit status updates & debug simulator
  allow delete: if isAdmin();
  ```
- The production-hardened helpers (`isBookingParty`, `statusUpdateAllowed`)
  and the original `read`/`create`/`update` grants are preserved in
  comments inside the block, with a prominent ⚠️ warning banner explaining
  the exact holes and the revert path.

### Security posture / production risk
- This is a deliberate, user-directed weakening for the sandbox. Under these
  rules, ANY signed-in user may:
  - **read** every booking in the system (PII: hunter names, contact info,
    booking financials);
  - **create** spoofed bookings under any `hunterId`/`outfitterId`
    (impersonation, financial fraud);
  - **flip ANY booking's status** — including marking it `Paid`, which fully
    bypasses PayFast (payment fraud), and self-approving their own bookings.
- The production deposit status flip is performed by the deployed
  `payfastITNHandler` Cloud Function using the Admin SDK, which bypasses
  Firestore rules entirely — so the production deposit flow does NOT need
  any client-side rule widening. This sandbox widening exists ONLY so the
  `kDebugMode`-only debug simulator button (Phase 42, stripped from release
  builds) can write the post-payment state directly from the client.

### Safer production alternative
- Gate the widened update on a custom auth claim issued only to test
  accounts, e.g. `allow update: if isSignedIn() &&
  request.auth.token.sandbox == true;`, instead of widening for every
  signed-in user. This keeps the production surface least-privilege while
  still letting a tagged sandbox account drive status transitions.

### Revert before production deploy
- Restore the commented production-hardened rules in the block:
  ```
  allow read: if isAdmin() || isBookingParty();
  allow create: if isSignedIn()
    && request.resource.data.hunterId == request.auth.uid;
  allow update: if statusUpdateAllowed()
    || (isBookingParty()
        && request.resource.data.status == resource.data.status);
  ```
  (un-comment the `isBookingParty` / `statusUpdateAllowed` functions and
  delete the sandbox `isSignedIn()` grants).

### Verification
- `flutter analyze`: 0 errors (no Dart changed; 324 pre-existing
  infos/warnings in unrelated files, unchanged baseline). The
  `analysis_options.yaml` auto-touch was reverted before commit.
- Structural rules validation: braces balance 0, parens balance 0,
  default-deny present, bookings block carries the `isSignedIn()` read +
  update grants.
- `flutter test test/firestore_rules_seeding_test.dart`: 14/14 pass (the
  seeding tests assert the unrelated `factory_ammunition` / `bullets` /
  `propellants` / `scanned_pricelists` / `animals` collection contracts,
  which are unchanged).

### Deploy reminder
- `npx firebase-tools deploy --only firestore:rules` in a credentialed env
  to activate. **Do NOT deploy this ruleset to the production Firebase
  project** — restore the hardened rules first. This commit is intended
  for the sandbox/test project only.
- Files: `firestore.rules` (bookings block widened + hardened rules
  preserved in comments), `AGENTS.md`.

## Phase 44 -- Restore production-hardened least-privilege rules on bookings (added 2026-08-14)

Reverts the Phase 43 sandbox widening of the `match /bookings/{bookingId}`
block back to the production-hardened least-privilege posture.

### What changed
- `firestore.rules` `match /bookings/{bookingId}` block restored to the
  strict production access controls (the same body that shipped before
  Phase 43):
  ```
  function isBookingParty() {
    return isSignedIn() && (
      resource.data.hunterId == request.auth.uid ||
      resource.data.outfitterId == request.auth.uid
    );
  }
  function statusUpdateAllowed() {
    return isSignedIn()
      && resource.data.outfitterId == request.auth.uid
      && request.resource.data.outfitterId == resource.data.outfitterId
      && request.resource.data.hunterId == resource.data.hunterId;
  }
  allow read: if isAdmin() || isBookingParty();
  allow create: if isSignedIn()
    && request.resource.data.hunterId == request.auth.uid;
  allow update: if statusUpdateAllowed()
    || (isBookingParty()
        && request.resource.data.status == resource.data.status);
  allow delete: if isAdmin();
  ```
- The wide `allow read/create/update: if isSignedIn()` sandbox grants AND the
  Phase 43 ⚠️ sandbox warning banner + commented helpers were removed. The
  `chats` subcollection booking-party restriction is unchanged.

### Why this is least-privilege
- **read**: only the admin, the hunter who placed the booking, or the
  outfitter who owns the package (no cross-tenant PII exposure).
- **create**: a signed-in user may create a booking only under their own
  `hunterId` (no spoofed bookings under another hunter/outfitter id).
- **update**: the outfitter may flip the `status` field
  (`statusUpdateAllowed`, which also freezes `hunterId`/`outfitterId`); any
  booking party may update NON-status fields (the
  `request.resource.data.status == resource.data.status` guard freezes the
  status field for non-outfitters, so a hunter can never self-approve or
  self-mark-Paid).
- **delete**: admin only.
- The production deposit `status -> Paid` flip is performed by the deployed
  `payfastITNHandler` Cloud Function using the Admin SDK, which bypasses
  Firestore rules entirely -- so the production deposit flow needs no
  client-side rule widening.

### Debug simulator note
- The `kDebugMode`-only PayFast deposit simulator (Phase 42) is unaffected
  in code: the button + `PackageBookingManager.simulateDepositPaid` remain.
  Under these hardened rules a hunter-triggered simulation write that flips
  `status` to `Paid` will be permission-denied server-side -- which is the
  intended production posture. The card's `_simulatePaymentSuccess` catch
  block surfaces that as a clear orange snackbar ("Simulation failed: ...
  run as the outfitter/admin or relax rules in your sandbox") rather than
  crashing. For sandbox testing of the simulator, run as the outfitter/admin
  (the outfitter `statusUpdateAllowed` branch permits the flip) or use the
  safer custom-claim alternative noted in Phase 43
  (`request.auth.token.sandbox == true`).

### Verification
- `flutter analyze`: 0 errors (no Dart changed; 324 pre-existing
  infos/warnings in unrelated files, unchanged baseline).
- Structural rules validation: braces balance 0, parens balance 0,
  default-deny present; the bookings block carries `isBookingParty` +
  `statusUpdateAllowed`, the hardened read/create/update/delete grants, the
  status-frozen update branch, and NO sandbox `isSignedIn()`-wide grants
  or warning banner.
- `flutter test test/firestore_rules_seeding_test.dart`: 14/14 pass (the
  seeding tests assert the unchanged catalog collection contracts).

### Deploy reminder
- `npx firebase-tools deploy --only firestore:rules` in a credentialed env
  to activate the production-hardened rules. This is the ruleset that
  SHOULD deploy to the production Firebase project.
- Files: `firestore.rules` (bookings block restored to least-privilege),
  `AGENTS.md`.

## Phase 45 -- PayFast return URL custom-scheme migration off page.link (added 2026-08-14)

Migrated the PayFast `return_url` deep link off the deprecated /
unconfigured Firebase Dynamic Links `*.page.link` domain onto a direct app
custom scheme (`jagspoor://payment-return`) captured by an Android
`MainActivity` intent filter. (v4.5 to-do Item #10 follow-up.)

### 1. `PayfastCheckout.buildReturnUrl` custom scheme
- `lib/core/services/payfast_checkout.dart` (note: the spec referenced
  `lib/features/packages/services/payfast_checkout.dart`, which does not
  exist -- the real file is `lib/core/services/payfast_checkout.dart`):
  - `returnBaseUrl = 'https://jagspoor.page.link/payment-return'` ->
    `returnScheme = 'jagspoor://payment-return'`.
  - `buildReturnUrl(bookingId)` now emits the custom-scheme URI
    `jagspoor://payment-return?booking_id=<enc>&status=success`
    (`Uri.encodeComponent` on the booking id), exactly per the spec.
  - `launchDeposit` continues to pass `buildReturnUrl(bookingId)` as PayFast's
    `return_url`; the `notify_url` / `cancel_url` / sandbox host / merchant
    credentials are unchanged.
- The marketplace's app-resume lifecycle listener (Phase 42) is unchanged --
    it detects the browser-checkout return on `AppLifecycleState.resumed`
    and prompts a booking-status refresh; the return URL is now resolved by
    the OS intent filter instead of a Dynamic Link.

### 2. Android intent filter
- `android/app/src/main/AndroidManifest.xml` `.MainActivity` gained an
  intent filter capturing the `jagspoor://payment-return` deep link so the
  browser checkout can redirect back into the app:
  ```xml
  <intent-filter>
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data android:scheme="jagspoor" android:host="payment-return" />
  </intent-filter>
  ```
  Placed alongside the existing LAUNCHER intent filter (the activity already
  had `android:exported="true"` + `launchMode="singleTop"`). XML validated
  well-formed.
- iOS Universal Link / custom-scheme config (`Info.plist` LSApplicationQueries
  / CFBundleURLTypes) for `jagspoor://` is NOT added in this phase -- the
  spec scoped this change to the Android manifest. iOS will fall back to the
  app-resume lifecycle listener (which still fires on resume) until a
  matching `CFBundleURLType` is added in a follow-up.

### 3. Scope note (Dynamic Links left intact elsewhere)
- Only the PayFast return URL was migrated. The password-reset deep link
  (`lib/features/auth/services/password_reset_action_code_settings.dart`
  `url: 'https://jagspoor.page.link/reset-password'` + its tests) is a
  separate Firebase Dynamic Links feature configured separately and is
  intentionally left unchanged -- it requires the `ActionCodeSettings`
  `handleCodeInApp` flow, which has no custom-scheme equivalent. The
  password-reset deep-link domain still must be authorized in the Firebase
  Console (per Phase 33's deploy reminder).

### 4. Tests
- `test/deposit_payment_simulator_test.dart`
  (`PayfastCheckout.buildReturnUrl` group) updated:
  - returns the `jagspoor://payment-return` custom scheme (startsWith
    `returnScheme`; explicitly asserts NO `jagspoor.page.link`).
  - encodes booking_id + status=success as query params; `Uri.parse` yields
    `scheme == 'jagspoor'`, `host == 'payment-return'`.
  - percent-encodes special characters in the booking id.
  - different ids -> different urls.
- All 24 tests in the suite pass (the other 20 -- simulator constants /
  canSimulate / simulateUpdateMap / booking-status-transition contract --
  are unchanged).

### 5. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable): **No issues found**
  in `lib/core/services/payfast_checkout.dart` +
  `test/deposit_payment_simulator_test.dart`. No Dart `lib/` baseline change.
- **`flutter test test/deposit_payment_simulator_test.dart`**: 24/24 pass.
- **`android/app/src/main/AndroidManifest.xml`**: well-formed XML; intent
  filter present with `scheme="jagspoor"` + `host="payment-return"`.
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  URL builder + Android manifest intent filter).
- Files: `lib/core/services/payfast_checkout.dart`
  (`returnScheme` + custom-scheme `buildReturnUrl`),
  `android/app/src/main/AndroidManifest.xml` (`jagspoor://payment-return`
  intent filter), `test/deposit_payment_simulator_test.dart` (return-URL
  assertions updated), `AGENTS.md`.

## Phase 46 -- My Packages card action-bar horizontal overflow fix (added 2026-08-14)

Fixed the yellow-stripes horizontal overflow on the "My Packages" package
card action bar that appeared on narrow screens / large font scaling.

### 1. Root cause
- The package card in
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`
  (note: the spec referenced
  `lib/features/outfitter_mode/presentation/widgets/outfitter_package_card.dart`,
  which does not exist -- the actual card is `_PackageCard` in the manager
  screen) rendered the action buttons in a bare `Row` with a trailing
  `Spacer()` + a delete `IconButton`:
  `[Activate/Deactivate] [Restock?] [Archive/Unarchive] [Edit] + Spacer +
  [Delete IconButton]`.
- The `Spacer` only distributes leftover space; it does NOT shrink the
  chips when their combined intrinsic width exceeds the available width.
  On a narrow phone (or with large text-scale / sold-out adding the extra
  Restock chip), the four `_actionChip` `ActionChip`s + the delete button
  overflowed the card width by ~57px -> the red/yellow "RenderFlex overflow"
  stripe. There was no horizontal scroll or wrap.

### 2. Fix
- Wrapped the chip group in a horizontal `SingleChildScrollView`
  (`scrollDirection: Axis.horizontal`,
  `physics: const BouncingScrollPhysics()`) inside an `Expanded`, so the
  chips stay fully visible + reachable via a smooth swipe regardless of
  screen width, font scale, or how many chips render (sold-out adds Restock)
  -- no overflow, no clipping.
- The destructive delete `IconButton` is kept OUTSIDE the scroller (after
  the `Expanded`) so it stays pinned at the trailing edge and is always
  reachable without scrolling. The trailing `SizedBox(width: 8)` separates
  it from the scroller's last chip.
- For `PackageStatus.deleted` packages, the scroller renders just the
  `Restore` chip and no delete button (unchanged behaviour), so the deleted
  state stays clean.
- Option A (`SingleChildScrollView` with `Row`) from the spec was chosen
  over `Wrap` because the chips are a single logical action group that
  reads left-to-right; a horizontal scroller keeps them on one line (no
  ambiguity about which row a chip landed on) while `Wrap` would reorder
  the visual grouping on narrow screens.

### 3. Verification
- **`flutter analyze`** (local Flutter 3.47.0 stable) on
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`:
  **No issues found** (0 errors, 0 warnings, 0 infos introduced). Project
  baseline unchanged. `analysis_options.yaml` auto-touched by the analyzer
  was reverted before commit.
- Pure UI layout change -- no logic, no Firestore / rules / index / Storage
  / pubspec changes. The existing package-quantity tests (24) +
  deposit-payment-simulator tests (24) still pass (no test logic touched).
- Files: `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`
  (action `Row` -> `Expanded(SingleChildScrollView(Row(chips)))` + delete
  IconButton hoisted out), `AGENTS.md`.


## Phase 47 -- Production Readiness Bug, Dependency & Crash Cleanup (added 2026-08-14)

Resolved the 4 long-standing "documented pre-existing failing" test suites
that every prior phase had carried as unmovable baseline, plus a sweep of
static-analyzer warnings and cross-async-gap `BuildContext` risks. After
this phase `flutter analyze` reports **0 errors, 0 warnings** and
`flutter test` reports **All tests passed** (≈450 framework tests) with **no
failures** for the first time in the project's tracked history.

### Task 1 -- sqflite_common_ffi CI build dependency (fixed)
- The Phase 29 `dev_dependency` `sqflite_common_ffi: ^2.4.2` requires
  Dart `^3.12`, but the CI Flutter 3.29.1 pin ships Dart 3.7 (and even the
  local 3.47.0 stable ships Dart 3.13) -- so `flutter pub get` + the
  mesh-sync test compile broke under the CI toolchain. Pinned to
  `sqflite_common_ffi: '>=2.3.6 <2.4.0'` (resolves to 2.3.7+1, Dart
  `>=2.18` compatible). `pubspec.lock` regenerated; `flutter pub get`
  succeeds. `libsqlite3-dev` installed system-wide for the FFI backend.
- Files: `pubspec.yaml`, `pubspec.lock`.

### Task 2 -- saps_tracker status-conversion logic bug (fixed)
- `SapsTrackerService.convertRawStatusToStage` matched the raw SAPS status
  string with a sequence of `contains()` checks. "submitted to provincial"
  matched Stage-0 ("submitted") BEFORE Stage-1 ("submitted to provincial"),
  so a provincially-submitted case was classified as merely "submitted".
  Rewrote as a **longest-match-wins** scan over a `stagePatterns` map
  (`bestStage` / `bestLen` tracking) so the longest matching pattern wins.
  Removed the now-unused `_matchesStatus` helper and prefixed the unused
  `idNumber`/`referenceNumber` locals. 42/42 `saps_tracker_test` pass.
- Files: `lib/features/hunter_mode/services/saps_tracker_service.dart`,
  `test/features/hunter_mode/saps_tracker_test.dart` (now green).

### Task 3 -- fake_cloud_firestore 4.1.1 MockWriteBatch compile skew (fixed)
- `offline_sync_queue_test` could not compile because
  `fake_cloud_firestore 4.1.1`'s `MockWriteBatch` lacked a method the
  resolved `cloud_firestore` called. Resolved by the dependency
  re-resolution from Task 1 (pubspec.lock now pulls `cloud_firestore 6.8.0`
  + a compatible `fake_cloud_firestore`). The test was also made runnable:
  FFI init (`databaseFactory = databaseFactoryFfi`) in `setUpAll`, Firestore
  injection via a new `@visibleForTesting resetForTest(FirebaseFirestore?)`,
  and a lazy `_firestore` getter so the singleton no longer eagerly calls
  `FirebaseFirestore.instance` at construction (test-isolation friendly).
  Removed the unused `db` local + `foundation.dart` import. 2/2 pass.
- Files: `lib/features/hunter_mode/services/offline_sync_queue.dart`,
  `test/features/hunter_mode/offline_sync_queue_test.dart` (now green).

### Task 4 -- advanced_ballistics_test cold->warm density assertion + integrator (fixed)
- The suite had been failing for the project's entire tracked history. Root
  causes (4):
  1. `calculateAtmosphericDensityRatio` **ignored its `temperatureC`
     parameter** and derived temperature purely from the ISA lapse rate,
     so cold and warm calls at the same altitude returned identical
     densities -- the "cold > warm density" assertion (line 380) failed.
     Fixed to use `temperatureC` for the ambient-temperature term while
     still applying the ISA lapse-rate altitude correction.
  2. `calculateG7DragCoefficient` had a transonic-boundary discontinuity at
     Mach 1.0 (the subsonic and supersonic branches did not meet), producing
     a velocity sign flip in the integrator. Adjusted the transonic branch
     to ~0.40 so the curve is continuous at Mach 1.0.
  3. The trajectory `while` loop had **no iteration cap**; once the
     integrator went unstable it spun forever (the test "hung"). Added a
     200k-iteration guard + NaN/`x.isNaN` break.
  4. With the density bug fixed, the latent **trajectory-integrator
     instability** was unmasked: the explicit-Euler integrator at `dt=0.01s`
     with the over-magnitude drag retardation (~10^5 ft/s²) overshot the
     velocity sign each step, so the bullet "flew backward" and the drop
     diverged to 10^6+ inches (Test 11+). Stabilized: `dt=0.001s` (per-step
     Δv ≪ v) and a `dragCalibration` divisor (100×) so the toy model lands
     in the realistic .308 drop range while keeping the relative
     altitude/temperature comparisons the suite asserts on meaningful.
  5. Two toy-model physics bugs the unmasking exposed: the wind-drift term
     `(windFps - vx) * dt * 12 / v` subtracted the bullet's axial velocity
     (≈2800 fps) from the crosswind (≈15 fps), so the wind run accumulated a
     *smaller* drift than the no-wind run and the "wind drift should be
     present" assertion inverted -- rewritten as a lateral crosswind push
     `windFps * dt * 12` (0 with no wind, positive with wind). The Test 11
     assertion `trajectory.first.drop < 0.01` checked the *muzzle* point
     after zero-correction (which is `-drop_at_100`, not 0); corrected to
     check the *zeroed* point at the zero range (drop ≈ 0 by construction).
  - Wrapped the raw-`assert`/`print` `runBallisticsTests()` in a single
    framework `test(...)` so the Flutter runner reports a pass/fail instead
    of "No tests were found" (the file previously exited 79). All 18
    internal assertions pass.
- Files: `test/features/ballistics/advanced_ballistics_test.dart` (now green).

### Task 5 -- bluetooth_mesh_test shared-mock state isolation + framework wrap (fixed)
- The 4th long-standing "pre-existing failing" suite. Root cause:
  `runBluetoothMeshTests()` declared ONE shared `mockStorage` at the top of
  the function and reused it across every test. Test 2 inserted a record,
  so by Test 3 `mockStorage.insertLog.length` was already > 0 -- but Test 3
  asserted `insertLog.length == 1` (and `count == 1`, `skippedLog.length ==
  1`) against a *fresh* store. The duplicate-packet test therefore always
  failed at line 364. Fixed by giving Test 3 its own isolated
  `MockLocalStorageCache` (the test's own assertions assume a fresh store;
  Tests 1-2 do not insert-then-assert-global-count, so they remain on the
  shared instance). Also wrapped `runBluetoothMeshTests()` in a framework
  `test(...)` (was exiting 79 "No tests were found"). All internal assertions
  pass.
- Files: `test/features/sync/bluetooth_mesh_test.dart` (now green).

### Task 6 -- Static-analyzer warning cleanup (0 warnings)
- Swept the remaining `flutter analyze` warnings (was 11, then 6 after the
  earlier phases) to **0**:
  - `outfitter_trophy_stock_screen.dart:93` -- removed an unnecessary
    `as Map<String, dynamic>?` cast on `DocumentSnapshot.data()` (already
    returns the nullable map).
  - `carcass_matrix_screen.dart:786` -- removed the unused `timestamp`
    local in `_buildChillerCard` (`cloud_firestore` import retained for
    `FieldValue.serverTimestamp`).
  - `outfitter_sync_service.dart:34` -- removed the unused `_dirtyCounts`
    field.
  - `financial_engine_test.dart` -- removed the unused `dart:math` import.
  - `feedback_workflow_test.dart` -- removed the unused `service` field +
    `setUp` + the now-orphaned `feedback_firebase_service` import (the
    tests only assert on string structure).
  - `payfast_deposit_button_test.dart:152` -- changed the const-non-null
    `packageName` to a runtime `final String?` so the `??` fallback is no
    longer a `dead_null_aware_expression` (mirrors the real resolution path).
- Final `flutter analyze`: **0 errors, 0 warnings, 307 infos** (down from
  the 324-issue / 11-warning baseline). The 307 infos are all `avoid_print`
  (218, debug `print()` calls) + `deprecated_member_use` (39, mostly
  `DropdownButtonFormField.value` on Flutter ≥3.33 only + the documented
  `androidProvider`/`appleProvider`) + style hints; none block the build.

### Task 7 -- Cross-async-gap BuildContext `mounted` guards (fixed)
- Audited the 7 `use_build_context_synchronously` infos (the raw "47
  unguarded sites" count was a heuristic over-count; the analyzer found 7
  genuine cross-async-gap `BuildContext` uses, all in outfitter presentation
  screens + the admin dashboard). Each used a captured `sheetContext` (the
  modal-sheet context) or the State's `context` after an `await` with only
  a `State.mounted` guard (which does not guard the captured
  `BuildContext`). Added `sheetContext.mounted` / `context.mounted` guards:
  - `admin_dashboard_screen.dart` (sign-out -> `Navigator.pushReplacementNamed`)
  - `outfitter_trophy_stock_screen.dart` (`_deleteTrophy` -> sheet pop +
    snackbar)
  - `lodge_booking_screen.dart` (save booking -> sheet pop + error snackbar)
  - `manual_invoice_screen.dart` (save package -> sheet pop + error snackbar)
  - `slaghuis_matrix_screen.dart` (add to coldroom -> sheet pop + refresh)
- All 7 lints are now resolved (verified by re-analyzing the 5 files: 0
  `use_build_context_synchronously` remain). This closes the real
  runtime risk of using a `BuildContext` whose `State`/sheet has unmounted
  mid-async (would throw "deactivated widget's ancestor" / state-on-unmounted).

### Task 8 -- Raw-assert test suites framework-wrapped (consistency)
- Three additional test files (`financial_engine_test.dart`,
  `sensor_ai_integration_test.dart`, and the now-fixed
  `bluetooth_mesh_test.dart`) used the raw-`assert`/`print` pattern with a
  bare `main() { runXxxTests(); }`, so the Flutter runner reported "No tests
  were found" (exit 79) even though every internal assertion passed. Wrapped
  each `runXxxTests()` call in a single framework `test(...)` so the runner
  reports a pass/fail and the suite is counted in the aggregate. No
  assertion logic changed.
- Files: `test/financial_engine_test.dart`,
  `test/features/ballistics/sensor_ai_integration_test.dart`,
  `test/features/sync/bluetooth_mesh_test.dart` (wrap only).

### Verification (final)
- `flutter analyze` (local Flutter 3.47.0 stable): **0 errors, 0 warnings,
  307 infos** -- first time at 0 errors + 0 warnings. The 307 infos are all
  pre-existing style/debug hints (no new issues introduced; the warning
  cleanup dropped the count from the 324/11 baseline).
- `flutter test` (full suite): **All tests passed** (≈450 framework tests,
  exit 0) -- the 4 long-standing pre-existing failures
  (`saps_tracker`, `offline_sync_queue`, `advanced_ballistics`,
  `bluetooth_mesh`) are all green for the first time, and the 3
  raw-assert suites are now counted. No skipped tests, no timeouts.
- Generated plugin registrars (`linux/flutter/generated_plugins.cmake`,
  `macos/Flutter/GeneratedPluginRegistrant.swift`,
  `windows/flutter/generated_plugins.cmake`) regenerated by `flutter pub
  get` to reflect the dependency re-resolution (e.g. `jni` FFI plugin
  added); committed for consistency with `pubspec.lock`.
- No Firestore rules / index / Storage / native-manifest changes in this
  phase (pure dependency, test, and UI-safety cleanup).
- Files (summary): `pubspec.yaml`, `pubspec.lock`,
  `lib/features/hunter_mode/services/offline_sync_queue.dart`,
  `lib/features/hunter_mode/services/saps_tracker_service.dart`,
  `lib/features/admin/screens/admin_dashboard_screen.dart`,
  `lib/features/hunter_mode/screens/carcass_matrix_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart`,
  `lib/features/outfitter_mode/data/services/outfitter_sync_service.dart`,
  `lib/features/outfitter_mode/presentation/lodge_booking_screen.dart`,
  `lib/features/outfitter_mode/presentation/manual_invoice_screen.dart`,
  `lib/features/outfitter_mode/presentation/slaghuis_matrix_screen.dart`,
  `test/features/ballistics/advanced_ballistics_test.dart`,
  `test/features/ballistics/sensor_ai_integration_test.dart`,
  `test/features/hunter_mode/feedback_workflow_test.dart`,
  `test/features/hunter_mode/offline_sync_queue_test.dart`,
  `test/features/sync/bluetooth_mesh_test.dart`,
  `test/financial_engine_test.dart`,
  `test/payfast_deposit_button_test.dart`,
  `linux/flutter/generated_plugins.cmake`,
  `macos/Flutter/GeneratedPluginRegistrant.swift`,
  `windows/flutter/generated_plugins.cmake`, `AGENTS.md`.

