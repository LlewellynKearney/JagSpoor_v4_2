# JagSpoor -- Agent Memory

## Phase -- Light-mode contrast/brightness audit + full-portal HunterScaffold rollout (added 2026-08-21)

Comprehensive UI/UX contrast + brightness audit across both portals. Two
root-cause themes: (1) Light Mode over-brightness + washed-out text over
the photographic backgrounds, and (2) hunter sub-views that never carried
the shared acacia background stack.

### Mode-aware adaptive scrim (the core fix for the "too bright" Day mode)

- `HunterAcaciaBackground.scrim({bool isDarkMode = true})` and
  `OutfitterBushveldBackground.scrim({bool isDarkMode = true})` are now
  **mode-aware** (previously always dark 60%/40%/70% black):
  - **Day mode** -> a dense warm **cream veil** `LinearGradient`
    (`Color(0xE6F7F1E6)` top 90% -> `Color(0xDFF5EFE3)` mid ->
    `Color(0xF2EFE5D4)` bottom 95%). The photo shows through subtly
    (immersive) but the screen reads as a soft warm surface instead of a
    blinding washed-out photo; dark espresso text is now readable.
  - **Night mode** -> a DENSER black gradient
    (`Color(0xA6000000)` top 65% -> `Color(0x8C000000)` mid 55% ->
    `Color(0xBF000000)` bottom 75%) so the dark theme stays balanced
    against the photo.
- `stack(child, fallbackColor)` gained an optional `isDarkMode` override;
  both `HunterScaffold` / `OutfitterScaffold` now compute the mode via a
  `Builder` from the *effective* `MediaQuery.platformBrightnessOf` (NOT
  just the `ThemeController.isDarkMode` flag), so a `ThemeMode.system`
  device that flips to dark adapts correctly.

### Toned-down light-mode card surfaces (Task 2)

- `HunterUi.lightCard` / `OutfitterUi.lightCard`:
  `Color(0xF5FCF9F5)` (near-white 96% opacity) -> **`Color(0xFFEFE7DC)`**
  (opaque rich warm tint) — soft on the eyes, zero glare, perfectly
  balanced against the cream veil. Dark-mode branch still delegates to
  `theme.cardColor` (unchanged).
- `lightBody`: `Color(0xFF4A3B32)` for warm-brown secondary text in Day
  mode (subtitleColor resolver).

### Full hunter-portal `HunterScaffold` rollout (Task 3)

- 19 additional hunter sub-views converted to `HunterScaffold` (previously
  plain `Scaffold(backgroundColor: theme.backgroundColor)`):
  trophy room/detail, firearm safe/detail/maintenance, manual firearm form,
  add/edit trophy, spoor identifier, firearm renewal, custom handloads,
  venison permit form, trophy registry browser, SAPS tracker, meat
  processing (+order history), carcass matrix, off-grid team radar, weather
  tracker. All got transparent AppBars + `HunterUi.titleColor` (espresso
  0xFF2C221E Day / white Night) title+icon themes, and their card surfaces
  were swapped `theme.cardColor` -> `HunterUi.cardColor(theme)` (~70 sites)
  so Day-mode cards are the toned-down warm tint.
- New `HunterScaffold.padBodyForAppBar: true` (default false for
  compatibility) — wraps the body in a `SafeArea(top: true)` AND top-pads
  scrollables by `MediaQuery.padding.top + kToolbarHeight`, so the
  previously-flat content never renders under the transparent full-bleed
  AppBar. The 6 already-rolled-out screens keep their explicit insets.
- `saps_tracker_screen` (ThemeData-based) + `mesh_radar_screen`
  (no theme field) resolve `ThemeController.instance` for the scaffold.
- **Intentionally not wrapped** (full-bleed dark camera/HUD surfaces by
  documented design): spoor HUD, scope calibration, license scanner,
  offline navigation, ballistic calc, optic history, shot group analyzer.

### Contrast sweep (Task 1)

- Fixed white-on-now-light-veil AppBar icon themes: hunter dashboard,
  hunter profile, hunter venison permit log.
- Fixed washed-out `widget.theme.subtitleColor` -> `OutfitterUi.subtitleColor`
  in the trophy stock + package manager outfitter screens.
- Fixed `add_firearm_manual_form` + `weather_tracker` AppBar titles to bold
  espresso. Audited all hunter/outfitter AppBar titles for bold +
  `HunterUi/OutfitterUi.titleColor` — the marketplace TabBar, builder,
  farm selection, permit list were already correct.
- Verified every remaining `Colors.white` / white-with-alpha text is on a
  colored/dark surface (accent buttons, red/green/blue gradient hero cards,
  snackbars, dark HUD containers, badges) — none left on the light veil.

### Tests

- `test/hunter_scaffold_rollout_test.dart` — expanded from 6 to 26 hunter
  screens in the structural rollout map; new palette test (EFE7DC card +
  2C221E/4A3B32 text); new mode-aware scrim tests (cream veil day /
  dense black night); widget test updated for the Builder-wrapped Stack.
- `test/outfitter_scaffold_rollout_test.dart` — mode-aware scrim + palette
  tests added.
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings** (277
  pre-existing infos, unchanged baseline).
- `flutter test`: **All 949 tests passed** (was 927).
- Files: the 2 scaffold widgets, 19 hunter screen conversions, 6 core
  screen contrast fixes, 2 rollout test files, AGENTS.md.

## Phase -- HunterScaffold: Solitary Acacia background + global hunter portal rollout (added 2026-08-21)

Mirrors the `OutfitterScaffold` architecture for the hunter portal. New
`lib/features/hunter_mode/widgets/hunter_scaffold.dart` exposes the full
shared-surface stack:

- **`HunterAcaciaBackground`** -- the primary network photo is the Solitary
  Acacia (`https://images.unsplash.com/photo-1523805009345-7448845a9094`),
  full-screen `BoxFit.cover` with a two-step fallback chain: the bundled
  `assets/images/Greater Kudu.jpg` offline fallback, then the theme
  background color. `scrim()` is the adaptive black `LinearGradient`
  (60% top / 40% mid / 70% bottom). `stack(child, fallbackColor)` layers
  photo + scrim + content.
- **`HunterUi`** -- light-mode contrast helpers. `lightTitle` /
  `lightBody = Color(0xFF2C221E)` (dark espresso for titles/descriptions);
  `lightCard = Color(0xF5FCF9F5)` (solid warm off-white/cream at 96%
  opacity); `lightCardBorder = Color(0xFFD6C8BC)`. `titleColor` /
  `cardColor` / `cardBorderColor` / `subtitleColor` resolvers; in dark mode
  they delegate to the standard `ThemeController` palette (white title,
  theme card/subtitle), so Day/Night stays correct. `cardDecoration` +
  `inputDecoration` helpers for cards + form fields.
- **`HunterScaffold`** -- a `Scaffold` pre-configured with the acacia
  background stack behind the body; `extendBodyBehindAppBar: appBar != null`
  full-bleeds the photo behind the transparent AppBar. Call sites wrap
  non-scroll bodies in `SafeArea(top: true)` and scrollables carry a
  `MediaQuery.padding.top + kToolbarHeight` top inset (no header overlap).
- **`HunterActionChip`** -- high-contrast circular AppBar action chip
  (translucent ~45% black circle + faint white rim) like `OutfitterActionChip`,
  so the glyph stays readable against the bright region of the photo.
- **Rollout** (all use `HunterScaffold` + `HunterUi` resolvers, transparent
  AppBar, dark-on-scrim or espresso-on-cream text):
  - **Dashboard** (`hunter_dashboard.dart`) -- theme-toggle + profile
    settings icons converted to `HunterActionChip`; the admin
    `AdminModeSwitcherButton` is wrapped in `HunterActionChip.decoration()`.
    `_resolveAdmin` + `_enforceProfileOnboarding` are now try/catch-hardened
    so an unavailable Firebase Auth (cold launch / test env) never crashes
    the dashboard (mirrors the outfitter dashboard resilience).
  - **Marketplace** (`hunter_package_marketplace_screen.dart`) -- TabBar,
    province dropdown, all package/booking cards + booking confirmation
    sheet converted to `HunterUi` colors; `SafeArea(top: true)` around the
    Column body.
  - **Venison Permits** (`hunter_venison_permit_log_screen.dart`) --
    `SafeArea`-wrapped Column, cream search field + cards, espresso text.
  - **Profile** (`hunter_profile_screen.dart`) -- `SingleChildScrollView`
    top inset; cards + inputs cream, espresso text.
  - **Custom Package Builder** (`hunter_custom_package_builder_screen.dart`
    + `custom_package_farm_selection_screen.dart`) -- both Scaffolds
    converted; farm cards cream with farm thumbnails.
- **`NetworkDiagnosticHud` leak fix** -- its pressure-update `Timer.periodic`
  was never stored/cancelled (leak + widget-test failure), and
  `_loadQueueSize` could throw when sqflite was uninitialized (web / test
  env). Timer now stored + cancelled in `dispose()`, and the queue-size read
  is try/catch hardened (best-effort).
- **Tests** -- `test/hunter_scaffold_rollout_test.dart` (14 tests): the
  acacia helper URL/fallback/scrim contract, `HunterScaffold`/
  `HunterUi`/`HunterActionChip` structural contract, per-screen rollout
  checks (source-parsed, mirroring `outfitter_scaffold_rollout_test`), plus
  widget tests rendering `HunterScaffold` (Stack contract), `HunterActionChip`
  (circle decoration), and `HunterDashboard` (resilient without Firebase).
- **Verification** -- `flutter analyze lib test`: 0 errors, 0 warnings (277
  pre-existing infos unchanged). `flutter test`: **All 927 tests passed**
  (was 913; +14 new). Flutter 3.29.1 (CI pin) re-installed at
  `/home/openhands/flutter`; `libsqlite3.so` symlink for sqflite FFI tests.
- Files: `lib/features/hunter_mode/widgets/hunter_scaffold.dart` (NEW),
  `lib/features/hunter_mode/hunter_dashboard.dart`,
  `lib/features/hunter_mode/hunter_profile_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_venison_permit_log_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`,
  `lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart`,
  `lib/features/hunter_mode/widgets/network_diagnostic_hud.dart` (leak fix),
  `test/hunter_scaffold_rollout_test.dart` (NEW).

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



## Phase 48 -- Shot Group Target Analyzer: UI clipping/contrast fix + firearm linking & offline logging (added 2026-08-15)

Item: fix UI clipping, contrast, and feature enhancements in the Shot Group
Target Analyzer screen.

### 1. Screen overflow / hidden content (fixed)
- The `ShotGroupAnalyzerScreen` body `SingleChildScrollView` used a flat
  `EdgeInsets.all(12)` with no `SafeArea` and no bottom safe-area inset, so on
  gesture-nav phones the bottom SAVE button + results panel rendered under the
  Android 3-button / iOS home-indicator bar. The floating capture buttons were
  also un-SafeArea'd.
- Fix: wrapped the body in `SafeArea(top: false)` and switched the scroll
  padding to `SafeBottomInset.paddingFor(context, horizontal: 12, top: 12)`
  (the project's standard bottom-inset helper) so the last control scrolls
  cleanly above the gesture bar. The empty state + the FAB row are now
  `SafeArea`-wrapped too.

### 2. Color scheme & contrast (fixed)
- The screen + overlay used raw `Colors.amber` for stats, MOA/MIL labels, the
  suggested-clicks line, the ANALYZE button, the auto-detect icon, and the
  floating buttons. On the light theme (`#F4EFEA` background) amber/yellow is
  low-contrast and hard to read.
- Fix: every `Colors.amber` / `Colors.white` / `Colors.black` UI control on the
  screen + overlay toolbar/hint was replaced with the theme-aware
  `ThemeController` palette (`accentColor`, `textColor`, `subtitleColor`,
  `cardColor`), with `selectedColor` on the `ToggleButtons`/`ChoiceChip`s set
  to `textColor` over an `accentColor` fill so the active segment stays legible
  in both modes. The `Colors.white24` dividers in the results panel became
  `subtitleColor.withValues(alpha: 0.25)`. The `greenAccent` precision badge
  became `Colors.green` (theme-stable).
- The overlay painter's canvas elements (amber reference line, red extreme-
  spread line, green COI, cyan aim crosshair, orange/red shot markers) are
  drawn ON TOP of the target photo image, so their high-contrast hues are kept
  intentionally -- they read against the photo, not the screen background.

### 3. Firearm selection & target logging (new)
- **Firearm selector**: a `DropdownButtonFormField<String>` (with
  `DropdownButtonHideUnderline`) populated strictly from the Digital Firearm
  Safe via `InventoryBridge.watchSafeFirearms()` (cached as a broadcast stream
  in `initState` so a re-mounting `StreamBuilder` never throws "already
  listened to"). Each item renders `RifleProfile.displayName`
  ("make model (calibre)"); the value is guarded against a just-deleted firearm
  so the dropdown never hits the "value not in items" assertion. When the safe
  is empty the dropdown is disabled with a "Choose Firearm" hint and the empty
  state surfaces "No firearms in safe yet -- add one in the Digital Firearm
  Safe."
- **Offline session logging**: new `TargetSessionLog` model
  (`lib/features/hunter_mode/models/target_session_log.dart`) +
  `TargetSessionLogManager` (`services/target_session_log_manager.dart`) that
  persists a completed `ShotGroupAnalysis` (firearm id + label snapshot, shot
  count, extreme spread / mean radius / COI offsets in mm + angular, suggested
  clicks, precision category, calibrated flag, aim point, timestamp) to the
  local SQLite `target_session_logs` table.
- **Local DB migration**: `LocalDatabaseService` bumped to DB version 4 with a
  new `target_session_logs` table (created in `_onCreate` + migrated in
  `_onUpgrade` for existing v3 installs). The manager exposes
  `saveSession` / `loadSessions` (newest-first) / `deleteSession`.
- **SAVE TARGET SESSION button**: a `FilledButton.icon` rendered under the
  results panel (only when an analysis exists) with a loading state
  (`_savingSession`) + success/failure snackbars; `ScaffoldMessenger` is
  captured before the async gap and `mounted` is guarded throughout.
- **Picker error handling**: `_pickFromGallery` / `_capture` now wrap the
  `image_picker` calls in `try/catch` and surface a red snackbar instead of an
  unhandled exception (camera unavailable / permission denied).

### 4. Tests
- `test/target_session_log_test.dart` (NEW, 8 tests, all pass): model
  `toMap`/`fromMap` round-trip (every field), missing-aim-point tolerance, unit
  labels; the pure `TargetSessionLogManager.buildLog` helper; and a SQLite
  integration group (real `sqflite_common_ffi` DB, no manager mocks) covering
  save+load, newest-first ordering, delete, and empty-list. Uses the same
  FFI + `LocalDatabaseService.resetForTest` isolation pattern as the mesh-sync
  integration suite.

### 5. Verification
- `flutter analyze` (local Flutter 3.47.0 stable): 0 errors, 0 warnings in all
  changed/new files. The single remaining issue in the screen is the
  documented pre-existing `DropdownButtonFormField.value` deprecation info
  (only flagged on Flutter >=3.33, NOT the CI 3.29.1 pin; the project uses
  `value:` everywhere for cross-version compatibility).
- `flutter test test/target_session_log_test.dart test/shot_group_analyzer_test.dart`:
  19/19 pass (8 new + 11 existing). No regressions.
- Files: `lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`
  (rewritten), `lib/features/hunter_mode/widgets/shot_group_target_overlay.dart`
  (theme-aware toolbar/hint), `lib/features/hunter_mode/models/target_session_log.dart`
  (NEW), `lib/features/hunter_mode/services/target_session_log_manager.dart`
  (NEW), `lib/features/shared/data/services/local_database_service.dart`
  (DB v4 + target_session_logs table + migration), `test/target_session_log_test.dart`
  (NEW), `context.md` (Section 9.7 Shot Group Target Analyzer), `AGENTS.md`.
- No Firestore rules / index / Storage / pubspec changes (pure on-device UI +
  local SQLite logging; the firearm dropdown reads the existing owner-scoped
  `firearms` collection whose rules are unchanged).


## Phase 49 -- Digital Trophy Room image sharing + Scope Settings firearm dropdown fix (added 2026-08-15)

### 1. Digital Trophy Room -- share the actual trophy photo (fixed)
- The Trophy Room share button (grid card in trophy_room_screen.dart + the
  detail-screen AppBar in trophy_detail_screen.dart) previously invoked
  TrophyShareComposer.shareTrophy, which only called Share.share(message) --
  a TEXT-ONLY share. The trophy photo was never attached, so a hunter
  broadcasting a harvest dispatch sent only the formatted text with no image.
- TrophyShareComposer.shareTrophy now shares the actual image file alongside
  the formatted text caption via Share.shareXFiles:
  - New pure helper firstPhotoPath(Map) extracts the first usable entry from
    the trophy doc's photos list (skips blank entries; null-tolerant).
  - New pure helper isLocalFilePath(String) classifies a path as local vs.
    remote (mirrors AdaptiveImage's detection: /, file://, ./, Windows drive).
  - New resolveShareFile(String?) resolves a photo reference to a local File:
    a local path is returned directly when the file still exists; a remote
    (Firebase Storage) URL is downloaded to a temp file via http + path_provider
    so share_plus can attach it. Best-effort: any failure returns null so the
    caller falls back to text-only (no crash, no failed share).
  - shareTrophy now: compose message -> firstPhotoPath -> resolveShareFile ->
    Share.shareXFiles([XFile(path)], subject:, text: message) when a file
    resolves; falls back to Share.share(message, subject:) when no photo.
- Both call sites already pass the full trophy map (which carries photos), so
  no call-site change was needed -- the photo is auto-extracted. The fallback
  snackbar messaging is unchanged.
- Dependencies: http, path_provider, share_plus were all already in pubspec
  (share_plus + http + path_provider used by the PDF engine + venison permit
  exporter). No pubspec change.

### 2. Scope Settings & Tools -- firearm dropdown tap/binding fix (fixed)
- Root cause: the Optical Suite (scope_tools_bottom_sheet.dart)
  _buildFirearmLink used a DropdownButtonFormField<String> with
  value: effectiveValue. DropdownButtonFormField is a FormField whose internal
  FormFieldState is seeded from the FIRST value and IGNORES a changed value on
  subsequent rebuilds (a long-standing Flutter behaviour). So after a user
  tapped a firearm, _onRifleSelected ran setState and updated _selectedRifleId,
  but the DropdownButtonFormField visually stayed on the hint ('Choose
  Firearm') because its internal state never re-seeded -- the dropdown appeared
  unresponsive / not to bind to the selection.
- Fix: added key: ValueKey<String?>(effectiveValue) to the
  DropdownButtonFormField. The key forces the widget to reinitialise whenever
  the effective value changes, so the FormFieldState re-seeds from the new
  value and the displayed selection reflects the freshly-tapped firearm on
  every rebuild. This is the standard Flutter fix for the
  DropdownButtonFormField-ignores-value-changes bug.
- The dropdown already populates strictly from the Digital Firearm Safe via
  InventoryBridge.watchSafeFirearms() (cached as a broadcast stream in
  initState for re-mount safety), renders RifleProfile.displayName
  ('make model (calibre)'), and is disabled with a clear hint when the safe
  is empty. _onRifleSelected stamps OpticProfile.firearmId and _saveOptic
  persists the binding to the firearms doc via InventoryBridge.saveOpticProfile
  (which stamps firearmId on the optic map) -- so the database binding was
  already correct; only the visual sync was broken (now fixed via the key).
- No Firestore rules / index / Storage change (the firearms read is already
  owner-scoped; the dropdown only reads).

### 3. Tests
- test/trophy_share_composer_test.dart extended with 17 new tests (was 11,
  now 28), all pass:
  - firstPhotoPath (6): first photo from list; skips blank entries; null when
    missing/empty/not-a-list; accepts a remote URL.
  - isLocalFilePath (6): absolute unix / file:// / ./ / Windows paths are
    local; https + Firebase Storage URLs are not.
  - resolveShareFile (5): null for null/blank path; null for a non-existent
    local path; returns the File for a real temp file (proves the local-file
    branch with no download); null for a malformed no-scheme path (no network
    attempt).
- The pure helpers (firstPhotoPath, isLocalFilePath) are fully unit-testable
  with no Flutter/platform plugins; resolveShareFile uses real temp-file I/O
  (no mocks) per the project test pattern.

### 4. Verification
- flutter analyze (local Flutter 3.47.0 stable): 0 errors, 0 warnings in all
  changed/new files. The single remaining issue in the scope tools file is
  the documented pre-existing DropdownButtonFormField.value deprecation info
  (only flagged on Flutter >=3.33, NOT the CI 3.29.1 pin; the project uses
  value: everywhere for cross-version compatibility).
- flutter test test/trophy_share_composer_test.dart test/optic_tools_test.dart:
  61/61 pass (28 trophy-share + 33 optic-tools). No regressions.
- Files: lib/features/hunter_mode/services/trophy_share_composer.dart
  (image-sharing: firstPhotoPath + isLocalFilePath + resolveShareFile +
  Share.shareXFiles wiring),
  lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart
  (ValueKey on the DropdownButtonFormField), test/trophy_share_composer_test.dart
  (+17 tests), context.md (16.4 dropdown fix + 16.6 trophy image sharing),
  AGENTS.md.
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  share composition + a dropdown-key fix).


## Phase 50 -- Factory ammunition pre-population from the bundled asset catalog (added 2026-08-15)

Item: pre-populate factory ammunition profiles from the local asset database
when selecting calibers, so the Ammunition Type Selection screen never shows
"No factory ammunition profiles found" for a caliber that exists in the bundled
catalog.

### 1. Root cause of the empty state
- The factory-load cascading selector (Brand -> Grain -> Description) in
  `lib/features/ballistics/presentation/ammunition_type_selection_screen.dart`
  read from the Firestore `factory_ammunition` collection via a
  `StreamBuilder<QuerySnapshot>` (`_buildFactoryAmmoStream` ->
  `.where('caliber', whereIn: caliberVariations).snapshots()`).
- That Firestore collection is populated ONLY by the one-time
  `BallisticsSeeder.seedAmmunition` startup seed from
  `assets/data/ammunition_database.csv`. The empty state appeared whenever the
  seed had not yet run / failed (e.g. permission-denied before the Phase 37
  rules deploy) / the device was offline with no cache / the curated
  `CaliberNormalizer` variant list did not include the user's exact spelling.
  So a valid caliber present in the asset CSV could still render an empty
  selector because the lookup depended on a networked, seeded Firestore
  collection rather than the bundled asset.

### 2. Offline-first `FactoryAmmunitionRepository` (NEW)
- New `lib/features/ballistics/data/factory_ammunition_repository.dart`:
  - `FactoryAmmoProfile` (brand, caliber, grain, description, bc,
    muzzleVelocityFps) + `displayLabel` ("brand . 168 gr . description").
  - `FactoryAmmunitionRepository` singleton. `loadAll()` reads
    `assets/data/ammunition_database.csv` via `rootBundle` once and caches the
    parsed list for the process lifetime (subsequent lookups are synchronous
    + O(n) over the ~300-row catalog). `getProfilesForCaliber(caliber)`
    returns the matching profiles. `cached` exposes the loaded catalog; a
    `@visibleForTesting resetCache()` + `parseCsv` static method make the
    parsing contract unit-testable without `rootBundle`.
  - **Caliber matching** (`matchesCaliber`, pure static, shared with the
    screen's `isCaliberMatch`): priority (1) exact normalized equality;
    (2) curated `CaliberNormalizer.getVariants` set membership (handles
    `.308 Win` <-> `308 Cal` / `7.62 NATO`, `9mm` <-> `9mm Luger`, `.30-06 Sprg`
    <-> `30-06 Springfield`, etc.); (3) boundary-aware bidirectional contains.
    The boundary check (`_boundaryContains`) requires the needle to sit at a
    digit boundary in the haystack, so `9mm` matches `9mm Luger` (normalized
    `9mmluger`, boundary after = `l`) but NOT `7.62x39mm` (the `9mm` in
    `39mm` is preceded by digit `3` and is rejected) -- a real false-positive
    the prior loose `contains` matcher had. When the caller does not pass a
    pre-computed variant set, the matcher derives one (`_variantSet`) so it
    is self-contained.
  - **Synonym canonicalization** (`_canonicalize`): maps regional/commercial
    spellings the curated normalizer does not enumerate -- `9mm Par` /
    `9mm Parabellum` -> `9mm Luger` (the CSV's canonical 9mm spelling),
    `7.62 Soviet` -> `7.62x39mm` -- applied before variant generation so the
    curated 9mm / 7.62x39 branches resolve. (The task brief named "9mm Par"
    explicitly.)
  - De-duplicates catalog rows by (brand, caliber, grain, description).

### 3. Screen wiring (`ammunition_type_selection_screen.dart`)
- `_buildFactoryAmmoStream` (the Firestore `StreamBuilder` source) was
  replaced with `_loadFactoryAmmo()` -- a caliber-keyed
  `Future<List<FactoryAmmoProfile>>` cache that calls
  `FactoryAmmunitionRepository.instance.getProfilesForCaliber(caliber)`.
- The factory-form `StreamBuilder<QuerySnapshot>` became a
  `FutureBuilder<List<FactoryAmmoProfile>>`; the `filteredAmmo` / `brands` /
  `grains` / `descriptions` derivation now reads typed `FactoryAmmoProfile`
  fields (`p.brand`, `p.grain`, `p.description`) instead of
  `Map<String,dynamic>` field accesses (`data['bulletgrain'] ?? data['bulletGrain']`,
  etc.), and the per-row `isCaliberMatch` filter is delegated to
  `FactoryAmmunitionRepository.matchesCaliber`. The empty-state
  (`_buildEmptyAmmoWarning`) is now reached ONLY for calibers genuinely
  absent from the bundled catalog.
- The now-unused `caliber_normalizer.dart` import was removed (the repository
  owns variant generation); `cloud_firestore` is still imported for the
  custom-handloads (bullets/propellants) flow + the saved-configuration write.

### 4. Tests
- `test/factory_ammunition_repository_test.dart` (NEW, 26 tests, all pass):
  - `parseCsv` (7): header + data rows; BC parsing; `gr` suffix stripping;
    empty/blank content; skips empty brand/caliber rows; non-numeric grain ->
    0; `displayLabel` composition.
  - `matchesCaliber` (8): exact match; `9mm` <-> `9mm Luger`; `9mm Par` <->
    `9mm Luger` (synonym); `.308 Win` <-> `308 Cal` / `7.62 NATO` (curated);
    `.30-06 Sprg` <-> `30-06 Springfield`; `243` <-> `6mm` (special case);
    unrelated calibers do not match; `9mm` does NOT match `7.62x39mm`
    (boundary false-positive guard); null/blank -> false.
  - `getProfilesForCaliber` filtered (5): 9mm matches 9mm + 9mm Luger rows
    (not 7.62x39mm); .308 Win matches .308 Win rows; blank -> empty;
    unrelated -> empty; de-duplication.
  - Live asset integration (6, real `rootBundle`): loads the bundled catalog
    + finds 9mm profiles; resolves `.308 Win`; resolves `9mm Par` to 9mm
    Luger (the empty-state fix for the named caliber); blank/null -> empty
    (no crash); a caliber absent from the catalog -> empty; catalog cache is
    reused across lookups (same instance, no re-read).

### 5. Verification
- `flutter analyze` (local Flutter 3.47.0 stable): **0 errors, 0 warnings**
  in all new/changed files
  (`factory_ammunition_repository.dart`,
  `ammunition_type_selection_screen.dart`,
  `factory_ammunition_repository_test.dart`). The only remaining issues in
  the screen are the documented pre-existing
  `DropdownButtonFormField.value` deprecation infos (flagged on Flutter
  >=3.33 only; the CI pin is 3.29.1 and the project uses `value:` everywhere
  for cross-version compatibility). `lib/` baseline unchanged.
  `analysis_options.yaml` auto-touched by the analyzer was reverted before
  commit.
- `flutter test` (full suite): **all 501 tests pass** (+26 vs the Phase-49
  475-pass baseline, exactly the new repository tests; no regressions).
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  asset read + UI; `csv` was already a dependency used by `BallisticsSeeder`;
  the Firestore `factory_ammunition` seed is unchanged and remains the
  server-side catalog for non-screen consumers).
- Files: `lib/features/ballistics/data/factory_ammunition_repository.dart`
  (NEW), `lib/features/ballistics/presentation/ammunition_type_selection_screen.dart`
  (FutureBuilder over the repository + typed profile access + matcher
  delegation + import cleanup), `test/factory_ammunition_repository_test.dart`
  (NEW, 26 tests), `context.md` (16.7), `AGENTS.md`.

## Phase 48 -- Outfitter Mode refactor: AI price-list quantity limits, per-farm cost config, per-farm PayFast routing (added 2026-08-15)

- **AI price-list scanner -- quantity limits**: `PricelistItem.quantityLimit`
  (`int?`) is now extracted from common SA price-list notations (`x3`,
  `max 5`, `qty 2`, `(3 avail)`, `5 available`). The qty token is popped
  BEFORE price extraction in `_parseLine` (was after) so the greedy price
  matcher (matches digit+space runs) no longer swallows the qty digit
  ("Blesbok R2000 5 available" -> limit 5, not price 20005). The Gemini Vision
  instruction now asks for `quantityLimit`; `GeminiResultNormalizer` carries
  it through (with `quantityAvailable`/`maxQuantity`/`qty`/`available`
  aliases) via a clean `_toQuantityLimit` helper. Persisted on
  `scanned_pricelists.items[].quantityLimit` (verification screen +
  `_itemToExtractedMap`).
- **Per-farm hunting catalog**: `FarmHuntingCatalog` +
  `FarmAnimalListing` + `FarmFeeListing` (pure transformation of a
  `scanned_pricelists` doc) groups items into animals (species, sex/class,
  trophy size tier, price/animal, quantity limit) + fees.
  `PricelistScannerService.getFarmHuntingCatalog(farmId)` returns it from the
  farm's most-recent active price list (readable by signed-in hunters).
- **Per-farm cost config**: `FarmCostConfig` (daily rate hunter/observer,
  accommodation/night, catering/day, vehicle, guide + `extraOptions`) is
  persisted as a nested `costConfig` map on `farms/{farmId}` via
  `OutfitterEnterpriseManager.updateFarmCosts`. The Enterprise Control Panel
  Edit Farm sheet gained a "COST RATES (PACKAGE BUILDER)" section.
- **Per-farm PayFast routing**: `FarmPayFastProfile` (merchant id, key,
  passphrase, live/sandbox) persisted as a nested `payfastProfile` map via
  `OutfitterEnterpriseManager.updateFarmPayFastProfile` /
  `clearFarmPayFastProfile` / `getFarmPayFastProfile`.
  `PayfastCheckout.resolveEndpoint(profile)` routes the deposit to the farm's
  merchant account when configured, else the platform default sandbox. The
  Custom Package Builder `_payDeposit` resolves the farm profile + passes it
  to `PayfastCheckout.launchDeposit`. A "Register a new PayFast account"
  button (`PayfastCheckout.openPayFastRegistration`) links to the merchant-
  application page.
- **Custom Package Builder -- quantity capping**: the per-line `+` stepper is
  disabled (and a `max N` chip renders) when the selected qty reaches the
  line's `quantityLimit`, so a hunter cannot over-book. The booked
  `quantityLimit` is carried through `_collectSelected` onto the booking doc.
- **Security note**: per-farm PayFast merchant key + passphrase are stored on
  the owner-scoped farm doc. For production, prefer a Cloud Function that
  signs the PayFast request server-side; this MVP enables the direct routing
  requested. No `firestore.rules` change required (farms update is already
  owner-scoped; farms read is already signed-in).
- **Verification**: `flutter analyze` lib/ -> 0 errors, 0 warnings. `flutter
  test` -> **534 pass** (was 501; +33 new in `test/farm_config_test.dart`;
  no regressions).
- Files: `lib/features/hunter_mode/models/farm_config.dart`,
  `lib/features/hunter_mode/services/pricelist_text_parser.dart`,
  `lib/features/hunter_mode/services/gemini_vision_extractor.dart`,
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`,
  `lib/features/hunter_mode/screens/outfitter_pricelist_verification_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `lib/core/services/payfast_checkout.dart`,
  `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`,
  `test/farm_config_test.dart` (NEW), `context.md` (16.8), `AGENTS.md`.

## Phase 49 -- Bug Report screenshot attachments (added 2026-08-15)

- The in-app Bug Report modal (`lib/features/hunter_mode/presentation/
  bug_report_modal.dart`) now supports up to 5 screenshot attachments as
  visual proof. Two entry points: **Take Photo** (`image_picker.pickImage`,
  `ImageSource.camera`, `maxWidth/maxHeight: 1920`, quality 85) and **Add
  from Gallery** (`image_picker.pickMultiImage`, quality 80, `limit` = the
  remaining slots). Both gated by a `_canAddScreenshot` cap (re-checked
  after the multi-pick returns).
- Picked images render as a horizontal thumbnail strip (96x96, rounded) with
  a per-image remove button (circular close badge) so the reporter can
  preview + remove before submission. A broken-image fallback renders for an
  undecodable file.
- On submit each attached `XFile` is compressed through the central
  `ImageService.compressExisting` (1280px, JPEG q75) and uploaded to Firebase
  Storage at `bug_report_attachments/{userId}/{timestamp}_{i}.jpg` via
  `ImageService.uploadCompressedPhoto`. The download URLs are passed to
  `FeedbackFirebaseService.submitBugReport(screenshotUrls:)`, persisted on
  the `bug_reports` doc as a `screenshotUrls` array. Best-effort: a failed
  per-image upload is logged (debugPrint) and does not block the report.
- `FeedbackFirebaseService` gained an injectable `FirebaseFirestore` +
  `currentUserIdResolver` constructor seam (default = the global instance +
  `FirebaseAuth.instance.currentUser?.uid`) so the service can be exercised
  against `fake_cloud_firestore` without a Firebase app. The
  `screenshotUrls` field is omitted from the doc entirely when empty so
  legacy reports are unaffected.
- **Storage rules**: new `match /bug_report_attachments/{uid}/{fileName}`
  block in `storage.rules` -- owner-scoped writes
  (`request.auth.uid == uid`); reads covered by the global authenticated-
  read rule. No `firestore.rules` change required (`bug_reports/{reportId}`
  create was already `isSignedIn()`).
- **Permissions**: Android `CAMERA` + `READ_MEDIA_IMAGES` (API 33+) and iOS
  camera/photo usage descriptions were already declared in Phase 13 (package
  creator camera capture); no new native manifest entries needed.
- **Verification**: `flutter analyze` lib/ + the new test -> 0 errors, 0
  warnings. `flutter test` -> **540 pass** (was 534; +6 new in
  `test/bug_report_screenshot_test.dart`; no regressions).
- Files: `lib/features/hunter_mode/presentation/bug_report_modal.dart`
  (screenshot picker + preview strip + remove + upload-on-submit),
  `lib/features/hunter_mode/services/feedback_firebase_service.dart`
  (`screenshotUrls` param + injectable firestore/uid seam),
  `storage.rules` (`bug_report_attachments/{uid}` block),
  `test/bug_report_screenshot_test.dart` (NEW, 6 tests), `context.md` (16.9),
  `AGENTS.md`.

## Phase 50 -- Remove Client Roster & Guided Hunt Logs from Outfitter Mode (added 2026-08-15)

- The **Client Roster** and **Guided Hunt Logs** features were **completely
  removed** from Outfitter Mode. Both were outfitter-side harvest-logging /
  client-book subsystems (added in Phase 9) that had grown redundant with the
  venison-permit + booking + trophy-inventory workflows.
- **UI & navigation**: the two dashboard feature cards ("Client Roster" and
  "Guided Hunt Logs") and their imports were removed from
  `lib/features/outfitter_mode/outfitter_dashboard.dart`.
- **Deleted files** (screens, services, models, test):
  - `lib/features/outfitter_mode/presentation/client_roster_screen.dart`
  - `lib/features/outfitter_mode/presentation/guided_hunt_log_screen.dart`
  - `lib/features/outfitter_mode/data/services/client_roster_manager.dart`
  - `lib/features/outfitter_mode/data/services/guided_hunt_log_manager.dart`
  - `lib/features/outfitter_mode/data/models/client_profile.dart`
  - `lib/features/outfitter_mode/data/models/guided_hunt_log.dart`
  - `test/outfitter_client_roster_test.dart` (6 tests removed).
- **Venison permit form decoupling**: `VenisonPermitFormScreen`
  (`lib/features/hunter_mode/screens/venison_permit_form_screen.dart`) no
  longer imports the client-roster / guided-hunt-log managers. The
  `clientId` / `guidedHuntLogId` constructor params and the post-issue
  permit-linking block (`GuidedHuntLogManager.linkPermit` +
  `ClientRosterManager.addPermitReference`) were removed. The generic
  `prefillData` map param is retained (self-contained; useful for any caller
  that wants to seed the form without a Firestore booking lookup); its
  docstring no longer references the removed managers. The only caller that
  used the removed params was the deleted `guided_hunt_log_screen.dart`; the
  other callers (`hunter_venison_permit_log_screen`,
  `venison_permit_list_screen`) only pass `theme`/`bookingId`/
  `isOutfitterMode`, so they compile unchanged.
- **Firestore rules + indexes cleanup**: the
  `match /client_roster/{clientId}` and `match /guided_hunt_logs/{logId}`
  blocks were removed from `firestore.rules`, and the two composite indexes
  (`client_roster (outfitterId ASC, createdAt DESC)` and
  `guided_hunt_logs (outfitterId ASC, huntDate DESC)`) were removed from
  `firestore.indexes.json`. The collections are simply no longer read or
  written by the app; any existing docs remain in Firestore but are orphaned
  (default-deny applies once the rules deploy).
- **Comments**: stale `client_roster` / `guided_hunt_logs` references in the
  `_ensureOutfitterSelfLink` docstrings/comments in
  `lib/core/splash_screen.dart` and `lib/features/auth/auth_screen.dart` were
  updated to list only the remaining owner-scoped outfitter collections
  (trophies, venison_permits, scanned_pricelists).
- **Verification**: `flutter analyze` lib/ + test/ -> 0 errors, 0 warnings
  (no broken imports, no dead-code warnings). `flutter test` -> **534 pass**
  (was 540; -6 = the deleted `outfitter_client_roster_test.dart`; no
  regressions).
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules,
  firestore:indexes` in a credentialed env to activate the rules/index
  cleanup.
- Files: deleted the 6 files above; modified
  `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `lib/features/hunter_mode/screens/venison_permit_form_screen.dart`,
  `lib/core/splash_screen.dart`, `lib/features/auth/auth_screen.dart`,
  `firestore.rules`, `firestore.indexes.json`, `context.md` (16.10),
  `AGENTS.md`.

## Phase 51 -- Reusable Firearm Dropdown Selector + Optical Suite refactor (added 2026-08-15)

- New reusable widget `lib/widgets/firearm_dropdown_selector.dart`
  (`FirearmDropdownSelector`) — a controlled, stateless firearm selector
  backed by the Digital Firearm Safe (`RifleProfile`). Accepts
  `selectedFirearmId` (String?), `firearms` (List<RifleProfile>),
  `isLoading` (bool), `onChanged` (ValueChanged<String?>), plus optional
  `trailing` widget + `leadingIcon` override. All selection state is owned by
  the parent screen; changes are reported via `onChanged`.
  - `DropdownButtonFormField<String>` binds to the unique string
    `RifleProfile.id` (never an object reference), with a `ValueKey` derived
    from the effective value so the `FormFieldState` reinitialises on every
    selection change (fixes the "dropdown visually never reflects a
    freshly-selected firearm" drift caused by
    `DropdownButtonFormField`'s read-value-once-on-first-build behaviour).
  - `selectedFirearmId` is **validated against the live `firearms` list on
    every build** and coerced to `null` when absent — so a
    `DropdownButtonFormField` "value not in items" assertion error can never
    fire when a firearm is deleted while the dropdown is open.
  - Visual states per spec: `isLoading == true` -> a thin
    `LinearProgressIndicator`; `firearms` empty -> a disabled `TextFormField`
    with the hint "No firearms found in Safe"; otherwise the live dropdown
    with each item labelled `RifleProfile.displayName` ("make model (calibre)").
  - `trailing` is hidden automatically while loading / empty. Uses
    `Theme.of(context)` exclusively (adapts to the Day/Night toggle).
- **Shot Group Target Analyser refactor**
  (`lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`):
  the local `_buildFirearmSelector` dropdown logic was replaced with
  `FirearmDropdownSelector`. **The selector was moved ABOVE the
  `ShotGroupTargetOverlay`** (the gesture canvas / `InteractiveViewer` /
  tap-`GestureDetector` layer) in the body `Column` widget tree, so the
  overlay's tap detector can never intercept taps meant for the dropdown
  menu — the selector is now the first child of the body Column (rendered
  before the overlay). The `StreamBuilder` over
  `InventoryBridge.watchSafeFirearms()` remains the data source; `isLoading`
  = `snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData`.
- **Scope Settings Tool refactor**
  (`lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`):
  the local `_buildFirearmLink` dropdown logic (manual
  `DropdownButtonHideUnderline > DropdownButtonFormField<String>` +
  `ValueKey` + container + turret-unit `Chip`) was replaced with
  `FirearmDropdownSelector`. The turret-unit `Chip` is passed as the
  selector's `trailing` widget; `leadingIcon` overridden to `Icons.link`.
  `_onRifleSelected` (stamps the optic's `firearmId`) is unchanged.
- **Tests**: `test/firearm_dropdown_selector_test.dart` (NEW, 6 widget
  tests, all pass) — live dropdown renders display names + reports selection
  via `onChanged`; stale `selectedFirearmId` coerces to `null` (no assertion);
  empty list renders the disabled "No firearms found in Safe" `TextFormField`;
  `isLoading` renders `LinearProgressIndicator` (uses `pump`, not
  `pumpAndSettle`, because the indeterminate animation never settles);
  `trailing` hidden while loading / empty, shown when populated.
- **Verification**: `flutter analyze` lib/ + test/ -> 0 errors, 0 warnings.
  `flutter test` -> **540 pass** (was 534; +6 = the new widget tests; no
  regressions).
- **Note on requested paths**: the task specified
  `lib/screens/optical_suite/target_analyser_screen.dart` and
  `lib/screens/optical_suite/scope_settings_screen.dart`, which do not exist
  in this codebase. The actual files are
  `lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart` and
  `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`
  (the Shot Group Target Analyzer and Scope Settings & Tools surfaces). Both
  were refactored. The Digital Firearm Safe provider
  (`InventoryBridge.watchSafeFirearms()`) yields `RifleProfile` objects (no
  standalone `Firearm` class exists in the codebase), so the widget is typed
  against `RifleProfile` — the actual model the two screens consume.
- Files: `lib/widgets/firearm_dropdown_selector.dart` (NEW),
  `lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`
  (refactored + selector hoisted above the gesture canvas),
  `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`
  (refactored),
  `test/firearm_dropdown_selector_test.dart` (NEW, 6 tests),
  `context.md` (16.11), `AGENTS.md`. No Firestore / Storage / rules / index /
  pubspec changes (pure UI + a reusable widget).

## Phase 52 -- Resilient trophy image fallback pipeline + PhotoUnavailablePlaceholder (added 2026-08-15)

- Fixed the "Photo unavailable" broken-image issue on the Trophy Room details
  screen by hardening the shared `AdaptiveImage` widget
  (`lib/utils/image_helper.dart`) — the central image renderer used by
  `trophy_detail_screen.dart`, `trophy_room_screen.dart`, AND
  `firearm_detail_screen.dart` (all three benefit). The constructor API is
  unchanged, so all callers remain compatible.
- **3-stage resilient fallback pipeline**:
  1. **Local file** — if the path looks local (`file://`, POSIX absolute,
     Windows drive path, or `./`), strip the `file://` scheme and verify
     `File(localPath).existsSync()` BEFORE attempting `Image.file`. A decode
     failure (corrupt bytes / permission error) is logged and falls through
     to stage 2.
  2. **Network image** — for a remote URL (`http`/`https`) OR a local path
     whose file no longer exists, render via `CachedNetworkImage`. Network
     failures (HTTP 403 Forbidden, 404 Not Found, socket/SSL/storage errors)
     are logged with the exact exception and fall through to stage 3.
  3. **Placeholder** — when every source has failed, render the reusable
     `PhotoUnavailablePlaceholder` (or the caller-supplied `errorWidget`).
- **New reusable widget** `lib/widgets/photo_unavailable_placeholder.dart`
  (`PhotoUnavailablePlaceholder`): neutral broken-image state, theme-aware,
  optional `icon`/`label`/`backgroundColor` overrides. **No raw path or HTTP
  status is surfaced to end users** — exact failure diagnostics go to
  `debugPrint` only (dev logs), satisfying the security guideline that error
  messages must not expose sensitive/internal path information.
- **Explicit error logging**: both the `Image.file` `errorBuilder` and the
  `CachedNetworkImage` `errorWidget` now `debugPrint` the exact exception
  (type + message, offending path/URL, HTTP status where available) so
  failures are visible in logs instead of failing silently. Verified in the
  test output (`AdaptiveImage: local file does not exist at "…" — falling
  back to network load.`).
- **Android scoped storage & permissions** (`AndroidManifest.xml`):
  `READ_MEDIA_IMAGES` was already declared for Android 13+ (API 33+, incl.
  14 / S26+). Added the legacy `READ_EXTERNAL_STORAGE` with
  `maxSdkVersion="32"` for Android 12 and below compat (the standard
  dual-permission pattern) + explanatory comment. `_isLocalPath` explicitly
  documents that `content://` Android media URIs are NOT treated as local
  filesystem paths (Flutter `File()` cannot read them directly) — they fall
  through to the network stage, which degrades gracefully to the placeholder.
  image_picker returns a cached app-internal file path (not `content://`)
  for picked media, so the local-file stage handles real picks.
- **Trophy detail screen** (`trophy_detail_screen.dart`): the inline
  broken-image `errorWidget` replaced with `PhotoUnavailablePlaceholder`.
- **Tests**: `test/adaptive_image_pipeline_test.dart` (NEW, 6 widget tests,
  all pass) — placeholder content + no sensitive detail surfaced + overrides;
  empty path → placeholder; stale local path → delegates to network stage;
  remote URL → network stage; caller errorWidget plumbed through. Tests
  assert structural contracts (which widgets are constructed) rather than
  async decode outcomes, so they're stable in a headless / no-network sandbox.
- **Verification**: `flutter analyze` lib/ + test/ -> 0 errors, 0 warnings.
  `flutter test` -> **546 pass** (was 540; +6 = new widget tests; no
  regressions).
- **Note on requested path**: the task referenced `lib/features/trophy_room/`,
  which does not exist; the real files are `lib/features/hunter_mode/
  trophy_detail_screen.dart` + `trophy_room_screen.dart`, and the shared
  image widget is `lib/utils/image_helper.dart` (also used by
  `firearm_detail_screen.dart`).
- Files: `lib/widgets/photo_unavailable_placeholder.dart` (NEW),
  `lib/utils/image_helper.dart` (3-stage pipeline + logging),
  `lib/features/hunter_mode/trophy_detail_screen.dart` (uses placeholder),
  `android/app/src/main/AndroidManifest.xml` (READ_EXTERNAL_STORAGE
  maxSdkVersion=32 compat), `test/adaptive_image_pipeline_test.dart` (NEW,
  6 tests), `context.md` (16.12), `AGENTS.md`. No Firestore / Storage /
  rules / index / pubspec changes (pure UI + a reusable widget + manifest
  permission).

## Phase 53 -- AdaptiveImage strict URI-path-handling pipeline (added 2026-08-15)

- Fixed the URI-path-handling bug in the shared `AdaptiveImage` widget
  (`lib/utils/image_helper.dart`) where a local-looking path whose file did
  not exist (e.g. `/data/local/tmp/missing.jpg` after a reinstall / new
  device / scoped-storage migration) was wrongly passed to
  `CachedNetworkImage` as if it were a URL — the network loader hung/threw
  because a local path is not a valid absolute http URI.
- **New strict fallback pipeline** (matches the 4 instruction points):
  1. **Local file** — `_isLocalPath` treats a string as local if it starts
     with `/data/`, `/storage/`, `file://`, OR satisfies
     `p.isAbsolute(path)` (the `path` package, already a direct main dep
     `^1.9.0`). The `file://` scheme is stripped via
     `Uri.parse(path).toFilePath()` (raw-substring fallback on parse
     failure), and `File(normalizedPath).existsSync()` is verified BEFORE
     rendering `Image.file(File(normalizedPath))` directly. A decode failure
     is logged and falls to the placeholder (NOT retried as a network URL).
  2. **Network image** — `CachedNetworkImage` is used ONLY when the string
     explicitly starts with `http://` or `https://`. Network failures
     (HTTP 403/404/socket) are logged with the exact exception and fall to
     the placeholder.
  3. **Placeholder** — when the string is neither an existing local file
     NOR an `http(s)` URL, `PhotoUnavailablePlaceholder` (or the caller's
     `errorWidget`) is rendered. A non-existent local path, `content://`
     Android media URI, or bare token is NEVER passed to
     `CachedNetworkImage`.
- **Pure functions extracted** for testability: `isLocalImagePath(path)` and
  `normalizeLocalImagePath(path)` are now top-level pure functions (the
  widget delegates to them). This decouples the URI-path-handling logic
  from the widget tree so it is unit-testable WITHOUT mounting an `Image`
  widget (real image decode via `dart:ui` is flaky/hangs in a headless test
  sandbox, so the decode-dependent widget tests were replaced with
  pure-function unit tests).
- **Tests**: `test/adaptive_image_pipeline_test.dart` rewritten — 22 tests
  (was 6), all pass:
  - Widget branch tests (no decode): empty path → placeholder; stale local
    path (missing) → placeholder NOT CachedNetworkImage; non-existent
    `file://` URI → placeholder NOT CachedNetworkImage; remote `http(s)`
    URL → CachedNetworkImage; non-URL non-local string → placeholder NOT
    CachedNetworkImage; `content://` URI → placeholder NOT CachedNetworkImage;
    caller `errorWidget` honoured for non-URL paths; caller `errorWidget`
    plumbed to the network stage for http(s) URLs.
  - Pure-function unit tests (instructions 1 & 2): `isLocalImagePath` —
    `/data/`, `/storage/`, `file://`, POSIX absolute all local;
    `http(s)`/`content://`/bare-token/relative/empty all NOT local.
    `normalizeLocalImagePath` — strips `file://` via `Uri.toFilePath()`
    (`file:///data/local/tmp/x.png` → `/data/local/tmp/x.png`); plain
    filesystem path + http URL returned unchanged.
- **Verification**: `flutter analyze` lib/ + test/ -> 0 errors, 0 warnings.
  `flutter test` -> **562 pass** (was 546; +16 net, no regressions).
- Files: `lib/utils/image_helper.dart` (strict pipeline + extracted pure
  functions), `test/adaptive_image_pipeline_test.dart` (rewritten, 22
  tests), `context.md` (16.13), `AGENTS.md`. No Firestore / Storage /
  rules / index / pubspec / manifest changes (pure logic + tests).

## Phase 54 -- Enforce PayFast Payout Profile on farm registration, edits & package/pricelist creation (added 2026-08-16)

- **Goal**: guarantee every farm carries a configured PayFast payout profile
  (merchant id + key + passphrase) so hunter deposits for packages /
  pricelists built against a farm route to that farm's PayFast account, and
  block package/pricelist creation when the selected farm has no profile.
- **1. Register New Farm** (`outfitter_enterprise_panel_screen.dart`):
  added a "PAYFAST PAYOUT PROFILE" section to the always-visible create
  form (Merchant ID / Merchant Key / Passphrase fields + Live/Sandbox
  toggle + "Register a new PayFast account" link), rendered via a new
  shared `_buildPayFastSection` helper. The three credential fields carry
  **mandatory validators** (reject empty input) so the `Form` cannot be
  submitted without a complete profile. `_addFarm` builds a
  `FarmPayFastProfile` from dedicated create-form controllers and passes
  it to `OutfitterEnterpriseManager.addFarm` (extended to accept +
  persist `payfastProfile` in the same `farms` doc write).
- **2. Edit Farm Details** (`_showEditFarmSheet`): replaced the inline
  (optional) PayFast fields with the same shared `_buildPayFastSection`
  helper in `mandatory: true` mode, so saving farm edits now also requires
  a complete PayFast profile. The `clearFarmPayFastProfile` branch in
  `_submitFarmEdit` is retained as a safety net but unreachable while the
  validators are mandatory.
- **3. SAVE CHANGES button fix** (Edit Farm sheet): wrapped the button in
  `SafeArea(top: false, bottom: true)` + `EdgeInsets.all(16)` padding so it
  clears the Android 3-button / iOS gesture nav bar; the label is now
  explicit `Colors.white` + `FontWeight.bold` for high contrast against
  the accent background (was relying on the default `foregroundColor`).
- **4. Package & Pricelist creation guards**:
  - New static `OutfitterEnterpriseManager.farmHasPayFastConfigured(
    Map?)` pure helper resolves a farm doc's `payfastProfile.isConfigured`
    synchronously (no extra Firestore read).
  - `outfitter_package_creator_screen.dart`: the BIND TO FARM
    `StreamBuilder` now caches the loaded farm docs into `_farmDataById`;
    selecting a farm with no PayFast profile fires the blocking snackbar
    immediately, and `_publishPackage` re-checks before creating (defense
    in depth). The snackbar reads: "PayFast details are required. Please
    edit this farm to add a PayFast Payout Profile before adding packages
    or price lists."
  - `outfitter_pricelist_scanner_screen.dart`: `_takePhoto` +
    `_chooseFromGallery` now block (snackbar + return) when the selected
    farm has no PayFast profile; the farm dropdown `onChanged` also fires
    the warning on selection so the outfitter knows before attempting a
    scan.
- **5. Firestore `farm_managers` PERMISSION_DENIED fix** (`firestore.rules`):
  widened `match /farm_managers/{managerId}` read from
  `isAdmin() || isOwnerOf('outfitterId')` to `isSignedIn()`, matching the
  `farms` / `lodging` / `fleet` / `packages` / `scanned_pricelists` pattern
  so the outfitter dashboard / enterprise panel can list managers without
  a crash when the manager doc's `outfitterId` does not match the caller
  (e.g. a manager reading their own assignment). Writes remain
  owner-scoped. Reviewed the rest of the file: all other
  outfitter-related collections already permit `isSignedIn()` reads, so
  `farm_managers` was the only outlier.
- **Verification**: `flutter analyze` (local Flutter 3.47.0) -> **0 errors,
  0 warnings**, only the documented pre-existing deprecation `info`s
  (`activeColor`, `DropdownButtonFormField.value` on Flutter ≥3.33 only;
  CI pin 3.29.1 does not flag them). `flutter test` -> **562 pass, 0 fail**
  (installed `libsqlite3-dev` so the SQLite-FFI integration tests
  resolve `libsqlite3.so`). The `firestore_rules_seeding_test` (14) +
  `farm_config_test` (47) both green.
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules` in a
  credentialed env to activate the `farm_managers` read widening.
- Files: `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`
  (`addFarm` + `farmHasPayFastConfigured`),
  `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`
  (create-form PayFast section + shared helper + edit-sheet mandatory +
  SAVE CHANGES SafeArea/contrast),
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`
  (cached farms + PayFast guard on selection + publish),
  `lib/features/hunter_mode/screens/outfitter_pricelist_scanner_screen.dart`
  (PayFast guard on selection + scan actions),
  `firestore.rules` (`farm_managers` read widened), `AGENTS.md`. No
  pubspec / index / Storage / manifest changes.


## Phase 54 -- Remove platform fee (7.5% commission) from the entire codebase (added 2026-08-16)

Removed every platform-commission / 7.5% markup calculation, variable, and
UI text from the codebase. Total amounts now reflect the base
package/booking cost with NO platform cut. Legitimate itemized service fees
(guide / vehicle / slaughter / accommodation fees that are part of package
pricing) are retained — only the platform commission was removed.

### Single-source PricingMath
- Removed: platformCommissionRate (0.075), markupMultiplier (1.075),
  markedUpTotal, commissionFromBase, depositFromBase,
  depositFromMarkedUpTotal, balanceFromMarkedUpTotal, netEarnings,
  resolveDeposit(markedUpTotalValue:).
- New API: depositFromTotal(total), balanceFromTotal(total),
  resolveDeposit(storedDeposit:, total:). resolveHunterTotal now PREFERS
  the base price (so legacy marked-up totals do not surface a platform
  cut); falls back to the stored total only when the base is absent.
  aggregateRevenueSummary returns (grossRevenue, netEarnings,
  totalBookings) where netEarnings == grossRevenue (no platform cut).

### PackageBookingManager
- calculatePricing(basePriceRands) now returns totalPrice = basePrice
  (no x markup), depositAmount = totalPrice x 0.25,
  balanceAmount = totalPrice - depositAmount. No platformCommissionRands
  field written.

### Screens (hunter-facing + outfitter-facing)
- hunter_package_marketplace_screen: deposit/total derived from
  PricingMath.resolveHunterTotal + resolveDeposit/balanceFromTotal; no
  Platform Fee UI row; PayFast charge = 25% deposit off the total.
- hunter_custom_package_builder_screen: hunterDisplayPriceZAR = base;
  grand total = sum(qty x base); deposit = total x 0.25.
- outfitter_booking_dashboard_screen: removed commission variable,
  Platform Commission row, isFee param from _FinancialRow.
- outfitter_revenue_screen: removed platformFees var + card; Gross + Net
  only (net = gross); monthly stats sum basePriceRands.
- outfitter_package_creator_screen: _buildPricingSummary simplified.
- outfitter_package_manager_screen: total fallback uses basePriceRands.
- outfitter_pricelist_scanner_screen: removed Applying 7.5% text.
- outfitter_pricelist_verification_screen: hunterDisplayPriceZAR =
  basePrice; removed commission row + fee label.
- scanned_pricelist_history_screen: single TOTAL chip; _DetailItemRow
  reduced to a single price (base = display); removed commission +
  basePrice fields.

### PDF exporters + admin
- outfitter_invoice_exporter: removed platformFee + Platform Commission
  row; fee breakdown shows only Total Package Value.
- revenue_analytics_report_exporter: removed platformFees; net = gross.
- invoice_pdf_service: removed markup = 1.075 constant; total = base;
  extras use unit price directly.
- carcass_record: calculateHunterTotal = (weight x rate) + slaughterFee.
- manual_invoice_screen: line price = base; removed 7.5% footer.
- admin_analytics_service: FinancialPeriod lost platformCommission;
  outfitterNet == grossBookingRevenue.
- admin_dashboard_screen: financial row lost Commission column.
- outfitter_dashboard: financial-card description lost platform fees.
- farm_config: FarmAnimalListing.hunterPriceZAR doc + fromPricelist
  fallback (base instead of base x 1.075).
- pricelist_text_parser + package_pricing: doc comments cleaned.

### Tests (rewritten for the no-commission model)
- pricing_math_test, custom_package_pricing_test,
  payfast_deposit_button_test, financial_engine_test, farm_config_test
  all rewritten to assert the no-commission contract.

### Verification
- flutter analyze (lib/ + test/): 0 errors, 0 warnings.
- flutter test (full suite): All 559 tests passed, zero failures.
- Final grep: no x 1.075 / * 1.075 / 0.075 commission constants remain
  (the only 0.075 is the physics airDensity constant in
  ballistics_calculator.dart); all remaining platform commission text is
  explanatory comments stating there is no platform commission.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side pricing + UI + test logic).


## Phase 55 -- Remove all deposit mentions + strip out PayFast payment integration (added 2026-08-16)

Task 2 of the two-task cleanup (Task 1 = remove 7.5% platform fee, already
done in Phase 54). The system now deals ONLY with the total price — there is
no deposit split (deposit amount / percentage / deposit+balance) and no
PayFast payment integration anywhere in the codebase.

### Deposit removal (UI + logic + data)
- **outfitter_booking_dashboard_screen.dart**: removed the deposit + balance
  `_FinancialRow`s from the booking financial breakdown (only "Total"
  remains); removed `'Pending Deposit'` / `'Paid'` from the EXPORT INVOICE
  status gate (now only `'Approved'`).
- **outfitter_analytics_service.dart**: `earnedBookingStatuses` reduced from
  `['Approved','Pending Deposit','Paid','Completed']` to
  `['Approved','Completed']` (the post-approval lifecycle is now just
  `Approved -> Completed`); docstring updated.
- **outfitter_revenue_screen.dart**: info-dialog copy updated to "Only
  approved and completed bookings are counted."
- **outfitter_package_manager_screen.dart**: removed the per-card
  `depositPct` read + the "$depositPct% deposit" meta chip text.
- **outfitter_package_creator_screen.dart**: removed the `_depositController`
  field + its dispose, the deposit-percentage prefill, the deposit validation
  block, the `depositPercentage:` arg pass-through to `publishPackage` /
  `updatePackage`, and the entire "DEPOSIT PERCENTAGE (%)" form section.
  Also removed the now-unused `OutfitterEnterpriseManager` import + the
  unused `_farmDataById` cache field + its StreamBuilder assignment
  (pre-existing dead code surfaced by the edit).
- **outfitter_invoice_exporter.dart**: removed the `depositAmount` /
  `balanceAmount` reads, the `_buildContent` params, and the entire
  "Deposit Status (25% Non-Refundable)" PDF section + its caption.
- **hunter_package_marketplace_screen.dart**: restored the `_tabController`
  + `_selectedProvince` field declarations that had been accidentally
  dropped during the prior session's PayFast cleanup (the
  `WidgetsBindingObserver` / app-resume listener / PayFast button /
  `_initiatePayFastCheckout` / `_simulatePaymentSuccess` / deposit rows
  were already removed in the prior session).
- **package_booking_manager.dart**: `approveBookingAndRequestDeposit` method
  NAME retained for backward-compat but its body now just sets `status:
  'Approved'` + the total price (no deposit fields); `depositFraction` /
  `depositPercentage` param / `simulateDepositPaid` were already removed in
  the prior session.
- **pricing_math.dart**: deposit methods already removed in the prior
  session; docstring confirmed clean.
- **firestore.rules**: removed the `depositPercentage` + `platformCommissionZAR`
  field-freeze checks from the `packages` `isInventoryDecrement()` function
  (those fields are no longer written).

### PayFast integration fully stripped
- **Deleted** `lib/core/services/payfast_checkout.dart` (the sandbox launcher
  + `buildReturnUrl` + `resolveEndpoint`).
- **Deleted** `lib/features/hunter_mode/services/deposit_payment_simulator.dart`
  (the kDebugMode simulator).
- **Deleted** `test/deposit_payment_simulator_test.dart` +
  `test/payfast_deposit_button_test.dart`.
- **functions/src/index.ts**: removed the entire `payfastITNHandler`
  onRequest Cloud Function + its `payfast.ts` imports (`parseItnBody`,
  `verifySignature`, `validateWithPayFast`, `PAYFAST_CONFIRMATION_TOKEN`).
  Removed the now-unused `onRequest`, `Request`, `Response`, `Firestore`
  type imports. `FieldValue` retained (used by `adminCreateOutfitter`).
  Cleaned the stale "PayFast ITN webhook" comment in `onBookingUpdated`.
- **Deleted** `functions/src/payfast.ts` (the signature/validate helpers).
- **functions/.env.example**: replaced the PayFast passphrase/mode env vars
  with a note that no payment-gateway env vars are required.
- **functions/package.json**: description updated (removed "PayFast ITN").
- **android/app/src/main/AndroidManifest.xml**: removed the
  `jagspoor://payment-return` custom-scheme intent filter (no longer
  needed without the browser checkout return flow).

### Test updates
- **test/farm_config_test.dart**: removed the `FarmPayFastProfile` +
  `PayfastCheckout` test groups + the `payfast_checkout` import (the
  classes/services were deleted).
- **test/pricing_math_test.dart**: removed the `depositFraction` /
  `depositFromTotal` / `balanceFromTotal` / `resolveDeposit` / "PayFast
  deposit alignment" test groups (methods deleted); kept
  `resolveHunterTotal` + `aggregateRevenueSummary` + `formatCurrency`.
- **test/custom_package_pricing_test.dart**: removed the
  `depositFraction` const + the "deposit is 25% of grand total" test.
- **test/outfitter_revenue_summary_test.dart**: updated the
  `earnedBookingStatuses` assertions from 4 statuses to 2
  (`['Approved','Completed']`).

### Firestore farm_managers read access (verified)
- `firestore.rules` `match /farm_managers/{managerId}` already allows
  `read: if isSignedIn()` (more permissive than the minimum
  `request.auth.uid == managerId` requirement) — so the outfitter
  dashboard / enterprise panel can list managers without a
  PERMISSION_DENIED crash. All other outfitter collections (`farms`,
  `packages`, `scanned_pricelists`, `outfitters`, `lodging`, `fleet`)
  also allow signed-in reads; no read-blocks that would crash Outfitter
  Mode. Rules structurally validated (brace/paren balance 0, default-deny
  present).

### Verification
- `flutter analyze` (local Flutter 3.47.0 stable): **0 errors, 0 warnings,
  308 infos** (all pre-existing `avoid_print` / `deprecated_member_use`
  style hints; no new issues). `analysis_options.yaml` auto-touched by the
  analyzer was reverted before commit.
- `flutter test` (full suite): **All 499 tests passed**, zero failures.
- Final grep across `lib/` + `test/` + `functions/` + `android/` + `ios/`:
  no `payfast` / `PayFast` / `deposit_payment_simulator` /
  `DepositPaymentSimulator` / `simulateDepositPaid` / `depositFromTotal` /
  `balanceFromTotal` / `resolveDeposit` / `depositFraction` /
  `depositPercentage` / `depositAmountRands` / `balanceAmountRands` /
  `_depositController` / `FarmPayFastProfile` / `Pending Deposit` /
  `pending_deposit` / `payfast_checkout` / `PayfastCheckout` references
  remain (the only matches are explanatory comments stating "no deposit
  split" / "PayFast ITN integration has been removed").
- Files: 18 modified, 4 deleted (`payfast_checkout.dart`,
  `deposit_payment_simulator.dart`, `functions/src/payfast.ts`, + 2 test
  files). No pubspec / Storage / index changes (pure client + functions +
  rules + manifest cleanup).
- Deploy reminder: `npx firebase-tools deploy --only functions,firestore:rules`
  in a credentialed env to activate the Cloud Function removal + rules
  update. The `payfastITNHandler` function will be deleted from the
  deployed project; any existing booking docs carrying legacy
  `depositAmountRands` / `balanceAmountRands` / `status: 'Paid'` /
  `status: 'Pending Deposit'` fields are harmless (ignored by the app; the
  revenue summary now counts only `Approved` + `Completed`).


## Phase 54 -- Farm Control Panel rename, Register-farm field sync, 7.5% commission cleanup, AI Price List Scanner removal (added 2026-08-16)

Continues the platform-fee / PayFast removal track. No new Firestore rules /
index / Storage / pubspec-native changes beyond the `google_generative_ai`
dependency removal.

### 1. Farm Control Panel rename
- `outfitter_enterprise_panel_screen.dart` AppBar title changed from
  'Enterprise Control Panel' to 'Farm Control Panel' (the panel manages
  farms / managers / trophy stock, not the broader enterprise).

### 2. Register New Farm form synced with Edit Farm Details
- The "Register New Farm" form previously captured only Farm Name /
  District / Province. It now matches the Edit Farm Details field set:
  Size (hectares, decimal-validated), Contact Number (phone), Registration
  Number, and the full COST RATES (PACKAGE BUILDER) section (Daily Rate
  Hunter/Observer, Accommodation/Night, Catering/Day, Vehicle Fee, Guide
  Fee). Each cost-rate field is optional (blank -> null = not configured);
  Size is parsed + validated (non-numeric -> orange snackbar, no save).
- `OutfitterEnterpriseManager.addFarm` extended with optional
  `sizeHectares`, `contactNumber`, `registrationNumber`, `costConfig`
  params (all omitted -> legacy 3-field behaviour preserved). When
  `costConfig` is supplied it is written as the nested `costConfig` map
  (same shape as `updateFarmCosts`), so a farm created with cost rates is
  immediately consumable by the Custom Package Builder without a separate
  edit pass. Blank contact/registration strings are stored as `null`
  (clears stale values) rather than empty strings.
- New create-form controllers separate from the edit-form controllers so
  the two sheets never collide on shared `TextEditingController` state.
  All disposed in `dispose()`.

### 3. Lingering 7.5% commission cleanup in Package Manager UI
- `outfitter_package_manager_screen.dart` `_PackageCard` total-price
  resolution was inverted: it preferred the legacy marked-up
  `totalPriceZAR` over `basePriceRands`, so a package created under the
  prior 7.5%-commission regime could still display the marked-up total.
  Fixed to prefer `basePriceRands` (the unmarked-up base cost; the hunter
  pays the base package cost -- there is no platform commission) and only
  fall back to `totalPriceZAR` when the base price is absent (very old
  docs). This mirrors `PricingMath.resolveHunterTotal` (already correct)
  and the marketplace price resolution. No `1.075` / `0.075` multiplier
  remains anywhere in `lib/`.

### 4. AI Price List Scanner completely removed
- Deleted (scanner-specific):
  - `lib/features/hunter_mode/screens/outfitter_pricelist_scanner_screen.dart`
  - `lib/features/hunter_mode/screens/outfitter_pricelist_verification_screen.dart`
  - `lib/features/hunter_mode/screens/scanned_pricelist_history_screen.dart`
  - `lib/features/hunter_mode/services/pricelist_text_parser.dart`
  - `lib/features/hunter_mode/services/gemini_vision_extractor.dart`
  - `lib/core/services/gemini_config_service.dart`
  - `test/gemini_config_service_test.dart`, `test/pricelist_text_parser_test.dart`
- `pricelist_scanner_service.dart` refactored: removed the scanner-specific
  methods (`extractPricelistItems`, `processAndUploadPricelistImage`,
  `saveVerifiedPricelist`, `getMyPriceListsStream`, `getMyPriceLists`,
  `getPriceListsForFarm`, `deletePriceList`, `parseRawText`,
  `isAiExtractionAvailable`, the `geminiConfig` / `_gemini` fields) and the
  `dart:io` / `gemini_config_service` / `offline_stream_guard` /
  `gemini_vision_extractor` / `pricelist_text_parser` imports. Kept the
  Custom Package Builder methods (`submitCustomPackageBooking`,
  `getAllActivePricelists`, `getActivePricelistForFarm`,
  `getFarmHuntingCatalog`, `calculateTotalWithFee`) so the custom-package
  flow is unaffected. The `scanned_pricelists` collection remains the
  custom-package catalog data source (readable by signed-in hunters);
  price lists may be seeded by an admin or a future import flow.
- `outfitter_dashboard.dart`: removed the "AI Scan Paper Price List" +
  "Scan History Log" feature cards and their imports.
- `main.dart`: removed the `GeminiConfigService.instance.init()` startup
  call + import (the scanner was its only consumer).
- `pubspec.yaml` / `pubspec.lock`: removed the `google_generative_ai`
  dependency (no remaining consumers).
- `test/farm_config_test.dart`: removed the two test groups that exercised
  the deleted `PricelistTextParser` / `GeminiResultNormalizer` + the
  `pricelist_text_parser` import. The `FarmCostConfig` +
  `FarmHuntingCatalog` groups (testing `farm_config.dart`, still present)
  are retained.
- The auth_screen + splash_screen `scanned_pricelists` comment references
  (listing owner-scoped outfitter collections) are left as-is -- they
  accurately describe the collection, which is still read by the custom
  builder.

### 5. Edit Farm SAVE button (already correct -- verified)
- The `_showEditFarmSheet` SAVE CHANGES button was already wrapped in
  `SafeArea(top: false, bottom: true)` with `EdgeInsets.all(16)` padding
  and a high-contrast white-on-accent (`theme.accentColor`) bold label
  (implemented in a prior phase). No separate `edit_farm_screen.dart`
  exists -- the edit UI is the modal sheet in
  `outfitter_enterprise_panel_screen.dart`. Verified, no change needed.

### 6. Firestore farm_managers / farms / packages read rules (already correct -- verified)
- `firestore.rules` already permits signed-in reads on `farm_managers`
  (`allow read: if isSignedIn()`), `farms` (`allow read: if isSignedIn()`),
  and `packages` (`allow read: if isSignedIn()`), so entering Outfitter
  Mode does not trigger a `PERMISSION_DENIED` crash on the
  dashboard / enterprise-panel / marketplace list queries. Writes remain
  owner-scoped. No rules change needed.

### Verification
- `flutter analyze` (local Flutter 3.47.0 stable): 0 errors, 0 warnings,
  306 infos (all pre-existing `avoid_print` debug calls +
  `deprecated_member_use` + style hints; no new issues introduced). The
  `analysis_options.yaml` auto-touched by `flutter pub get` was reverted
  before commit.
- `flutter test` (full suite): All 447 tests passed (exit 0). The
  deleted `gemini_config_service_test` (20) + `pricelist_text_parser_test`
  (22) + the 11 parser/normalizer tests removed from `farm_config_test`
  account for the count delta vs the prior 500-pass baseline; no
  regressions in the retained suites.
- Files: `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`
  (rename + create-form field sync), `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`
  (`addFarm` extended), `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`
  (price resolution fixed), `lib/features/hunter_mode/services/pricelist_scanner_service.dart`
  (scanner methods removed, builder methods kept), `lib/features/outfitter_mode/outfitter_dashboard.dart`
  (scanner cards + imports removed), `lib/main.dart` (GeminiConfigService
  init removed), `pubspec.yaml` / `pubspec.lock`
  (`google_generative_ai` removed), `test/farm_config_test.dart` (parser
  test groups removed), `AGENTS.md`. Deleted: the 7 scanner/service/test
  files listed above.


## Off-platform booking flow & payment verification state machine (added 2026-08-16)

Implemented the off-platform (direct) booking + payment-verification state
machine across the Hunter and Outfitter modules. The hunter pays the
outfitter directly (off-platform: cash / EFT / WhatsApp); the app tracks the
booking through a clear lifecycle and the outfitter manually verifies when
payment is received.

### Centralized `BookingStatus` model (NEW)
- `lib/features/hunter_mode/models/booking_status.dart` -- the single source
  of truth for booking-status string constants + the state-machine transition
  rules. Off-platform lifecycle:
  `Pending Approval` -> `Awaiting Payment` -> `Confirmed` -> `Completed`
  with `Declined` / `Cancelled` as dead-ends.
  - Constants: `pendingApproval`, `approvedAwaitingPayment`, `confirmed`,
    `completed`, `declined`, `cancelled`.
  - `earnedStatuses` = `[confirmed, completed]` -- only payment-verified
    bookings count toward realized outfitter revenue. `Awaiting Payment` is
    explicitly NOT earned (payment not yet verified).
  - `activeRequestStatuses` = `[pendingApproval, approvedAwaitingPayment]`
    (outfitter must act); `archivedStatuses` = the terminal four.
  - Pure transition guards: `canApprove`, `canConfirmPayment`, `canCancel`,
    `canComplete` -- encode the state-machine rules so they are unit-testable
    without the Firestore emulator. `canConfirmPayment` accepts the legacy
    `'Approved'` status so pre-flow bookings can be migrated forward.
  - `hunterBadgeLabel(status)` -- hunter-facing badge text per status.

### `PackageBookingManager` (updated)
- `bookPackage` / `submitCustomPackageBooking` now write
  `status: BookingStatus.pendingApproval` (hunter-created bookings default to
  pending approval).
- `approveBookingAndRequestDeposit` now transitions to
  `BookingStatus.approvedAwaitingPayment` ("Awaiting Payment") instead of the
  old `'Approved'`. Revenue is NOT yet realized.
- NEW `confirmPaymentReceived({bookingId})` -- outfitter verifies the direct
  payment was received. Transitions `Awaiting Payment` (or legacy `Approved`)
  -> `Confirmed`. Guards: rejects if the booking is not in an awaiting-payment
  state. Writes `paymentVerifiedAt` + `paymentVerified: true`.
- `updateBookingStatus` validates against `BookingStatus.allStatuses`.

### `OutfitterAnalyticsService` (updated)
- `earnedBookingStatuses` now delegates to `BookingStatus.earnedStatuses`
  (`[Confirmed, Completed]`). The revenue summary `whereIn` query + monthly
  chart now count only payment-verified bookings -- `Awaiting Payment` no
  longer inflates revenue.
- `getPendingBookingsCountStream` queries `pendingApproval`.
- `getMonthlyBookingStats` categorizes `approvedAwaitingPayment` / `confirmed`
  / `completed` / legacy `Approved` as "approved".

### Outfitter booking dashboard (updated)
- Added a 2-tab `TabBar`: **Active Requests** (Pending Approval + Awaiting
  Payment) and **Archived** (Confirmed / Completed / Declined / Cancelled).
  Bookings are split in-memory by status so the outfitter sees actionable
  requests separately from history.
- `_buildActionButtons(status)` renders context-specific actions:
  - `Pending Approval`: DECLINE + APPROVE REQUEST + Chat/WhatsApp Hunter row.
  - `Awaiting Payment` (or legacy `Approved`): prominent
    VERIFY / CONFIRM PAYMENT RECEIVED button (green FilledButton, confirmation
    dialog -> `confirmPaymentReceived`) + Chat/WhatsApp Hunter + EXPORT INVOICE.
  - Archived: EXPORT INVOICE only.
- NEW `_confirmPaymentReceived()` -- confirmation dialog + calls
  `PackageBookingManager.confirmPaymentReceived`.
- NEW `_contactHunterWhatsApp()` -- launches `https://wa.me/<phone>?text=...`
  (SMS fallback) pre-filled with the booking + payment details.
- `_getStatusColor` updated for the new statuses (Awaiting Payment = amber,
  Confirmed = green).

### Hunter marketplace (updated)
- `_HunterBookingCard` status badge now uses
  `BookingStatus.hunterBadgeLabel(status)` (e.g. "Payment Required" for
  Awaiting Payment, "Confirmed" for confirmed).
- NEW direct action buttons: IN-APP CHAT (toggles the chat drawer) +
  WHATSAPP OUTFITTER (`_contactOutfitterWhatsApp` -- launches wa.me with the
  booking + payment-arrangement message).
- `_getStatusColor` + status default updated for the new statuses.
- Date-change request visibility extended to post-approval states
  (approved / awaiting payment / confirmed).

### Notifications (`booking_status_service.dart`)
- Notifications fire on: approval (Awaiting Payment / legacy Approved) ->
  "BOOKING APPROVED! ... Please arrange payment with the outfitter.";
  payment verified (Confirmed) -> "PAYMENT CONFIRMED ... outfitter has
  verified your payment."; declined.
- NEW `_showPaymentConfirmedNotification`.

### Admin analytics + exporters (updated)
- `admin_analytics_service.dart`: active-bookings count + financial-period
  revenue sum now query `whereIn: BookingStatus.earnedStatuses` (was the
  removed `'Paid'` status).
- `outfitter_invoice_exporter.dart`, `revenue_analytics_report_exporter.dart`,
  `outfitter_revenue_screen.dart`, `outfitter_enterprise_manager.dart`,
  `pricelist_scanner_service.dart`: all `'Pending Approval'` literals
  replaced with `BookingStatus.pendingApproval`.

### Tests
- `test/outfitter_revenue_summary_test.dart` rewritten: 19 tests (was 5)
  covering the earned-status filter contract, the full `BookingStatus`
  lifecycle (allStatuses / isEarned / isActiveRequest / isArchived /
  hunterBadgeLabel), and the state-machine transition rules (canApprove /
  canConfirmPayment / canCancel / canComplete + the happy-path lifecycle +
  the "revenue not realized at awaiting-payment" invariant).
- `flutter analyze`: 0 errors, 0 warnings, 306 infos (all pre-existing).
- `flutter test`: **461 passed** (was 447; +14 new, no regressions).

### Files
- NEW: `lib/features/hunter_mode/models/booking_status.dart`.
- Updated: `lib/features/hunter_mode/services/package_booking_manager.dart`,
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart`,
  `lib/features/hunter_mode/services/booking_status_service.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`,
  `lib/features/hunter_mode/services/outfitter_invoice_exporter.dart`,
  `lib/features/hunter_mode/services/revenue_analytics_report_exporter.dart`,
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`,
  `lib/features/admin/services/admin_analytics_service.dart`,
  `test/outfitter_revenue_summary_test.dart`, `AGENTS.md`.
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  state machine + UI; the existing `bookings` rules already permit the
  outfitter to flip `status` via `statusUpdateAllowed`).


## Phase — Copyright footer + Outfitter Price List feature (added 2026-08-16)

Two requested features: (1) a "© 2026 JagSpoor. All Rights Reserved." footer on the auth / splash / hunter settings & profile / outfitter settings screens, and (2) a "Price List" feature in the Outfitter Dashboard.

### 1. Copyright footer
- New reusable `lib/core/widgets/copyright_footer.dart` (`CopyrightFooter`): theme-aware (Day/Night via `Theme.of(context).brightness`), centered, small muted caption. Two constructors: default (top:24 padding) + `CopyrightFooter.tight` (top:8).
- Placed as the last child of the scrollable body Column on:
  - `lib/core/splash_screen.dart` (after the loading spinner).
  - `lib/features/auth/auth_screen.dart` login/register card (after the switch-mode TextButton) AND the "Forgot Password?" reset dialog (`_PasswordResetDialog` content Column tail).
  - `lib/features/hunter_mode/hunter_profile_screen.dart` (Hunter settings + profile are the same screen -- the settings icon navigates here) -- after the Danger Zone.
  - `lib/features/outfitter_mode/outfitter_dashboard.dart` `_showSettingsBottomSheet` (Outfitter settings bottom sheet tail).
- The hunter "settings" icon (hunter dashboard AppBar) navigates to the Hunter Profile Screen, so the footer there covers both "Hunter Settings" and "Hunter Profile". The outfitter settings is a bottom sheet (footer added to its Column tail).

### 2. Outfitter Price List feature
- New `lib/features/hunter_mode/models/farm_game_price_entry.dart`:
  - `FarmGamePriceEntry` model: `id`, `farmId`, `outfitterId`, `speciesName`, `qty` (int), `priceZAR` (double), `createdAt`/`updatedAt`. Tolerates field aliases on read (`name`/`speciesName`, `quantity`/`qty`, `price`/`priceZAR`/`priceRands`); numeric strings parsed; trims species. `fromMap` (snapshot-free, unit-testable) + `fromFirestore` + `toMap` + `copyWith`.
  - `FarmGamePriceValidator` pure validators: `validateSpecies` (required, <=80 chars), `validateQty` (required, whole number, >=0), `validatePrice` (required, number, >=0, strips R/r/spaces).
- New `lib/features/hunter_mode/services/farm_game_price_list_manager.dart` (`FarmGamePriceListManager.instance`): owner-scoped `farm_pricelists` Firestore collection. `getFarmPriceListStream(farmId)` (reactive, `Stream.empty()` for null uid/empty farmId), `getFarmPriceList`, `addEntry` (validates auth + species + qty>=0 + price>=0), `updateEntry` (partial update), `deleteEntry`. Writes stamp `outfitterId`/`farmId` + server timestamps.
- New `lib/features/hunter_mode/screens/outfitter_price_list_screen.dart` (`OutfitterPriceListScreen`): farm dropdown (loaded from `OutfitterEnterpriseManager.getMyFarms()`), reactive price-list `StreamBuilder`, per-entry card (species, qty chip, R price chip, edit + delete buttons), FAB add entry, add/edit bottom sheet (validated form), empty-farm / empty-list / error states, copyright footer. SafeArea-aware bottom padding via `SafeBottomInset`. Delete confirmation dialog.
- Outfitter dashboard card added below "Manage My Packages": `Icons.request_quote_rounded` "Price List" -> `OutfitterPriceListScreen`.
- **Firestore rules**: new `match /farm_pricelists/{entryId}` block -- `read: isSignedIn()` (signed-in users can browse pricing), `create, update, delete: ownerOrAdmin('outfitterId')` (owner-scoped writes). Mirrors the `trophies` read-open / write-owner-scoped pattern.
- **Tests**: `test/farm_game_price_entry_test.dart` (21 tests, all pass): `fromMap`/`toMap` round-trip (timestamps compared via `millisecondsSinceEpoch` to be timezone-independent -- Firestore `Timestamp.toDate()` returns local), alias tolerance, numeric-string parsing, missing-field defaults, species trim, `copyWith`; + full validator suites (species/qty/price accept + reject cases).
- **Verification**: `flutter analyze` -> 0 errors, 0 warnings (306 infos, all pre-existing). `flutter test` -> **482 passed** (was 461; +21 = new price list tests; no regressions).
- Files: `lib/core/widgets/copyright_footer.dart` (NEW), `lib/core/splash_screen.dart`, `lib/features/auth/auth_screen.dart`, `lib/features/hunter_mode/hunter_profile_screen.dart`, `lib/features/outfitter_mode/outfitter_dashboard.dart`, `lib/features/hunter_mode/models/farm_game_price_entry.dart` (NEW), `lib/features/hunter_mode/services/farm_game_price_list_manager.dart` (NEW), `lib/features/hunter_mode/screens/outfitter_price_list_screen.dart` (NEW), `firestore.rules`, `test/farm_game_price_entry_test.dart` (NEW), `AGENTS.md`.
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules` in a credentialed env to activate the new `farm_pricelists` rules. Until deployed the writes are denied (the add/edit/delete flow surfaces a snackbar).

## Phase — Price List UI fixes, Rand currency, gender/horn fields, itemized fee pricing (added 2026-08-16)

User-feedback fixes to the Outfitter Price List + Publish Package surfaces.

### 1. Bottom sheet UI clipping + Rand currency
- `OutfitterPriceListScreen._PriceEntrySheet` (the Add/Edit Species Entry modal) wrapped in `SafeArea(bottom: true)` + `SingleChildScrollView` whose bottom padding is `MediaQuery.of(context).viewInsets.bottom + 16`, so the "ADD ENTRY" button clears the system gesture bar AND the open keyboard on every device.
- Replaced the `$` `Icons.attach_money` prefix icon on the price field with `Icons.payments_outlined` (the field label is "Price (ZAR)" + the validator strips an `R`/`r` prefix, so the Rand symbol is now the consistent currency cue). The list-card price chip already rendered `R ${...}`.

### 2. Gender + Horn / Tusk Length fields
- `FarmGamePriceEntry` model gained `gender` ('Male'/'Female'/'Any', default 'Any') and `hornTuskLength` (optional String, e.g. '28"+', 'Trophy', 'Cull').
  - Read aliases tolerated: `gender`/`sex`, `hornTuskLength`/`horn`/`tusk`. `_normalizeGender` accepts case-insensitive input + common aliases (M/F, bull/ram->Male, cow/ewe/hen->Female, both/either->Any).
  - `toMap` writes `gender` always + `hornTuskLength` only when non-empty. `copyWith` supports both new fields.
- `FarmGamePriceListManager.addEntry` + `updateEntry` accept `gender` + `hornTuskLength` (default 'Any' / '' ); `updateEntry` clears the field via `FieldValue.delete()` when an empty string is passed.
- Add/Edit Species Entry sheet: new `_buildGenderSelector` renders a `ToggleButtons` (Male / Female / Any) inside an `InputDecorator`; a new "Horn / Tusk Length" `TextFormField` (`Icons.straighten` prefix, optional, max 40 chars) with `FarmGamePriceValidator.validateHornTuskLength`.
- `_PriceEntryCard` now renders a gender badge (male/female icon, suppressed when 'Any') + a horn/tusk badge (`Icons.straighten`) when present.

### 3. Itemized services pricing (Publish Package)
- The Publish Package "ITEMIZED BREAKDOWN" already listed the 7 standard service categories (`ItemizedBreakdownCategory.all`: Bakkie/Hunting Vehicle, Slaughtering, Coldroom, Hunter Daily, Non-Hunter Observer Daily, Overnight Accommodation, Catering) as tappable rows. The `AlertDialog` editor was rewritten into a `showModalBottomSheet` + `StatefulBuilder` with `SafeArea(bottom: true)` + `viewInsets.bottom + 16` padding, a `Form` with validators, the R prefix on the price field (`Icons.payments_outlined`), and a Save/Remove/Cancel row. Tapping any breakdown card opens it; Save persists the `ItemizedLineItem` into `_lineItems`, which flows into the `PackagePricing.lineItems` written to the `packages` doc on publish/edit.

### 4. Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): 0 errors, 0 warnings in all changed files (276 infos globally, all pre-existing).
- `flutter test`: `farm_game_price_entry_test.dart` 31/31 pass (was 21; +10 new). Full suite 484 pass (excluding the 2 pre-existing `fake_cloud_firestore 4.1.1` / `cloud_firestore 6.8.0` compile-skew test files `offline_sync_queue_test.dart` + `bug_report_screenshot_test.dart`, which fail identically on the baseline before this change -- unrelated dependency skew).
- Environment note: installed Flutter 3.29.1 stable (CI pin) + `libsqlite3-dev` so the `sqflite_common_ffi` integration tests can load `libsqlite3.so`.
- Files: `lib/features/hunter_mode/models/farm_game_price_entry.dart`, `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`, `lib/features/hunter_mode/screens/outfitter_price_list_screen.dart`, `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`, `test/farm_game_price_entry_test.dart`, `AGENTS.md`.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure model + UI + a validator; the `farm_pricelists` rules from the prior phase already permit the owner-scoped writes the new fields use).

## Phase — Itemized Service Rates structure refinement + PDF zero/blank filtering (added 2026-08-16)

Refactored the farm-level itemized service-rate model + form UI to carry explicit per-category unit semantics, and enforced the strict zero/blank/null omission rule in the PDF price list export.

### 1. FarmServiceRate model + FarmServiceCategory (lib/features/hunter_mode/models/farm_service_rate.dart)
- `FarmServiceRate` gained `unitLabel` (rate-unit description, e.g. "Per vehicle per day" / "Per day" / "Per night" / "Per animal") and `quantityNoun` (what the quantity counts, e.g. "vehicles" / "animals" / "hunters" / "nights" / "persons"). Persisted in `toMap`, hydrated in `fromMap` (backfilled from the category when omitted for legacy docs). `copyWith` now accepts a `key` param (used by legacy-key migration).
- New `FarmServiceCategory` class with the 9 standard farm service categories implementing the exact specified breakdown (decoupled from `ItemizedBreakdownCategory`, which remains the package-pricing 7 used by the Publish Package line items -- a separate concept): 1. bakkie_vehicle (qty=vehicles, "Per vehicle per day"), 2. slaughtering_big (qty=animals, "Per animal"), 3. slaughtering_small (qty=animals, "Per animal"), 4. coldroom (qty=animals, "Per day"), 5. hunter_daily (qty=hunters, "Per day"), 6. non_hunter_observer_daily (qty=observers, "Per day"), 7. overnight_accommodation_hunter (qty=nights, "Per night"), 8. overnight_accommodation_non_hunter (qty=nights, "Per night"), 9. catering (qty=persons, "Per day"). Slaughtering Big/Small + Accommodation Hunter/Non-Hunter are modelled as distinct rate keys (cleaner for independent zero/non-zero PDF filtering than composite sub-rates). `FarmServiceCategory.findByKey` + `migrateLegacyKey` (slaughtering -> slaughtering_big, overnight_accommodation -> overnight_accommodation_hunter) provide backward-compat migration.
- `FarmServiceRates.empty`/`fromMap`/`rate`/`configuredRates` now operate on `FarmServiceCategory.all` (9) instead of `ItemizedBreakdownCategory.all`. `fromMap` migrates legacy keys + re-stamps the resolved category label/unit semantics (no dangling legacy keys). `FarmServiceRate.isConfigured` is the single filter gate: qty>0 AND pricePerUnit>0 (blank/null/zero resolve to 0 during parse, so excluded).

### 2. Form UI (lib/features/hunter_mode/screens/outfitter_price_list_screen.dart)
- Switched from `ItemizedBreakdownCategory.all` to `FarmServiceCategory.all` (9 rows). Each row renders the category label + unit label; configured subtitle shows "N {quantityNoun} × R {rate} ({unitLabel}) = R {total}" + unit label caption. Edit sheet: "Rate unit: {unitLabel}" caption; Quantity label "Quantity ({quantityNoun})"; Rate label "Rate — {unitLabel} (ZAR)". Save persists unitLabel+quantityNoun. Removed unused `package_pricing.dart` import. Helper text notes only non-zero services are in the PDF export.

### 3. Manager (lib/features/hunter_mode/services/farm_game_price_list_manager.dart)
- `removeFarmServiceRate` resolves the category via `FarmServiceCategory.findByKey` and zeroes with the category label/unitLabel/quantityNoun. Removed unused `package_pricing.dart` import.

### 4. PDF export filtering (lib/features/hunter_mode/services/farm_price_list_pdf_exporter.dart)
- New pure `filterActiveServices(FarmServiceRates?)` helper returns only configured (qty>0 AND pricePerUnit>0) services -- the strict zero/blank/null omission rule. `buildContent` consumes it. Itemized Services table gained a "Unit" column (5 cols: Service / Qty / Unit / Rate / Total). Null/blank/zero qty or rate => omitted from the PDF. `filterActiveServices` is unit-testable without rendering PDF bytes.

### 5. Verification
- `flutter analyze` (local Flutter 3.47.0): 0 errors, 0 warnings in all changed files (only pre-existing infos elsewhere).
- `flutter test` (full suite): All 567 tests passed, zero failures. New: `farm_service_rate_test.dart` (7->9 categories, unit semantics, legacy-key migration, rate() legacy resolution, copyWith key) + `farm_price_list_pdf_exporter_test.dart` "itemized service filtering" group (10 tests: null/zero-qty/zero-rate/both-zero/all-zero/blank-null-stored/order/all-9/unit-label/buildContent-active).
- Files: `lib/features/hunter_mode/models/farm_service_rate.dart`, `lib/features/hunter_mode/screens/outfitter_price_list_screen.dart`, `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`, `lib/features/hunter_mode/services/farm_price_list_pdf_exporter.dart`, `test/farm_service_rate_test.dart`, `test/farm_price_list_pdf_exporter_test.dart`.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure model + UI + pure filter helper). Existing `farm_service_rates` docs migrate automatically on read via `migrateLegacyKey`.

## Phase 2 -- Optic Save Log, Shot Group Analyzer firearm fix, Custom Package Builder w/ farm price lists (added 2026-08-17)

Three Phase 2 tasks on top of the Phase 1 baseline (commit 3ae7e82).

### Task 1 -- Optic Save Log with audit history
- New `lib/features/ballistics/data/services/optic_log_service.dart`
  (`OpticLogService.instance`) -- owner-scoped `optic_logs` Firestore
  collection. `logSave({firearmId, firearmLabel, optic})` writes one audit
  entry per "Save Optic" event carrying the full `OpticProfile` snapshot +
  the host firearm id + a display label + `FieldValue.serverTimestamp()`.
  `getLogStream()` returns a reactive newest-first stream scoped by
  `userId == auth.uid` (null-uid -> `Stream.empty()`).
- `OpticLogEntry` model: `id`/`userId`/`firearmId`/`firearmLabel`/
  `optic`/`savedAt`. `fromFirestore` delegates to a snapshot-free
  `fromMap({id})` (unit-testable without a Firestore emulator); tolerates
  the `firearmName` legacy alias + `createdAt` timestamp fallback. `toMap`
  writes `FieldValue.serverTimestamp()` for `savedAt`. `copyWith` +
  `firearmLabelForOpticLog(RifleProfile?)` helper (renders
  `RifleProfile.displayName`, "Unknown firearm" for null, "Unnamed firearm
  (—)" for empty make/model).
- Wired into `_saveOptic()` in `scope_tools_bottom_sheet.dart`: after
  `InventoryBridge.saveOpticProfile` persists the optic, the screen calls
  `OpticLogService.instance.logSave(...)` (best-effort, failure logged via
  `debugPrint` so a rules/permission error never blocks the optic save).
  A "View Optic History" `IconButton` (`history_rounded`) in the Optical
  Suite header pushes the new `OpticHistoryScreen`.
- New `lib/features/ballistics/presentation/optic_history_screen.dart`:
  reactive, newest-first log of the user's optic save events. Each card
  shows the firearm label, optic name, turret unit / click value / focal
  plane, and the saved-at timestamp. Empty / error / loading states.
  Themed via `ThemeController.instance` + `CopyrightFooter`.
- Firestore rules: new `match /optic_logs/{logId}` -- read =
  `isAdmin() || isOwnerOf('userId')`; create = signed-in + stamps own uid;
  update/delete = owner or admin. Owner-scoped so a hunter cannot read
  another hunter's optic log.
- Firestore indexes: new composite `optic_logs (userId ASC, savedAt DESC)`
  for the stream query.
- Tests: `test/optic_log_service_test.dart` (10 tests, all pass) -- `toMap`
  carries all fields + `savedAt` is a `FieldValue`; `fromMap` round-trip;
  missing-optic-map defaults; `firearmName` legacy alias; empty-data
  tolerance; missing-id null; `copyWith`; `firearmLabelForOpticLog`
  (displayName / null / empty-make-model fallback).

### Task 2 -- Shot Group Analyzer firearm detection fix
- Root cause: `InventoryBridge.fetchSafeFirearms()` and
  `watchSafeFirearms()` queried `.where('ownerId').orderBy('name')`. The
  Digital Firearm Safe manual form persists `make`/`model`/`caliber`/
  `serial` -- NOT `name` -- so docs without a `name` field were silently
  excluded by the `orderBy('name')` (Firestore requires the orderBy field
  to exist on returned docs for an equality+orderBy composite). The Shot
  Group Target Analyzer's firearm dropdown (which reads through
  `watchSafeFirearms`) therefore rendered "No firearms in safe" even when
  the safe had registered rifles.
- Fix: removed `.orderBy('name')` from both `fetchSafeFirearms()` and
  `watchSafeFirearms()` in `lib/features/ballistics/data/inventory_bridge.dart`.
  The dropdown now renders every owner-scoped firearm doc; the
  `RifleProfile.displayName` getter ("make model (calibre)") already
  handles the make/model rendering.
- File: `lib/features/ballistics/data/inventory_bridge.dart`.

### Task 3 -- Custom Package Builder with farm price lists + marketplace booking parity
- Rewrote the Custom Package Builder to draw species + itemized fees from
  the outfitter's **manual farm price list** (`farm_pricelists`) +
  **itemized service rates** (`farm_service_rates`) instead of the legacy
  AI-scanned `scanned_pricelists`.
- New hunter-readable read APIs on `FarmGamePriceListManager`:
  `getFarmPriceListStreamForHunter(farmId)` + `getFarmPriceListForHunter(farmId)`
  -- query by `farmId` only (no `outfitterId == currentUserId` filter) so a
  hunter browsing the builder can read any farm's published price list.
  Permitted by the existing `farm_pricelists` read rule (`isSignedIn()`).
  The owner-scoped `getFarmPriceList`/`getFarmPriceListStream` (filtered by
  `outfitterId == currentUserId`) remain for the outfitter's own price-list
  management screen.
- `custom_package_farm_selection_screen.dart` rewritten: discovers bookable
  farms by scanning `farm_pricelists` (grouped by `farmId`) +
  `farm_service_rates` (doc id == `farmId`), resolves the `farms` docs, and
  renders each farm with species-count + "service rates" chips. Farms with
  neither are filtered out. `CopyrightFooter` added.
- `hunter_custom_package_builder_screen.dart` rewritten:
  - Streams `farm_pricelists` (species rows with sex/gender + horn/tusk
    badges + qty stepper capped at the outfitter's `qty`) AND
    `farm_service_rates` (itemized fee rows with per-category unit
    semantics "Per vehicle per day" / "Per night" / etc. + qty stepper)
    reactively through the new hunter-readable getters.
  - Hunt-window date pickers + hunter/observer party steppers.
  - Grand total = Σ(qty × unit price); no platform commission / fee row
    (matches the post-Phase-54 no-commission model).
  - On submit writes a `bookings` doc via `submitCustomPackageBooking`
    (`isCustomPackage: true`, `status: BookingStatus.pendingApproval`,
    `pricelistId: 'farm_pricelists:{farmId}'`), then switches to a
    **confirmation view** that mirrors the Package Marketplace booking
    workflow: embedded `BookingChatThread` (hunter↔outfitter negotiation,
    expanded by default) + a live status badge + an "ADD HUNT TO CALENDAR"
    `FilledButton` that appears the instant the booking transitions to
    Confirmed / Completed (subscribes to the booking doc stream so the
    calendar button + status badge update reactively without a reload).
    Calendar hook delegates to `BookingCalendarService.instance.addToCalendar`
    (the same `add_2_calendar` integration the marketplace uses).
  - `CopyrightFooter` added.
- Files: `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`
  (hunter-readable read APIs), `custom_package_farm_selection_screen.dart`
  (rewritten), `hunter_custom_package_builder_screen.dart` (rewritten).

### Verification (Phase 2)
- `flutter analyze` (local Flutter 3.29.1, CI pin): **0 errors, 0 warnings**,
  276 infos (all pre-existing `avoid_print` / `deprecated_member_use` style
  hints; no new issues introduced).
- `flutter test` (full suite): **605 passed, 2 failed**. The 2 failures are
  the documented pre-existing `fake_cloud_firestore 4.1.1` /
  `cloud_firestore 6.8.0` compile skew (`MockWriteBatch.update` declared
  type variables don't match) in `bug_report_screenshot_test.dart` +
  `offline_sync_queue_test.dart` -- verified identical on the clean
  baseline (commit 3ae7e82, stashed my changes); unrelated to Phase 2.
  +38 net passing tests vs the 567-pass Phase 1 baseline (the new
  `optic_log_service_test` 10 + the existing farm/booking suites re-run).
- Files: `lib/features/ballistics/data/services/optic_log_service.dart` (NEW),
  `lib/features/ballistics/presentation/optic_history_screen.dart` (NEW),
  `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`
  (wired `_saveOptic` + history button),
  `lib/features/ballistics/data/inventory_bridge.dart`
  (removed `.orderBy('name')`),
  `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`
  (hunter-readable read APIs),
  `lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart`
  (rewritten),
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (rewritten),
  `firestore.rules` (`optic_logs` owner-scoped block),
  `firestore.indexes.json` (`optic_logs` + `farm_pricelists` composites),
  `test/optic_log_service_test.dart` (NEW, 10 tests),
  `AGENTS.md`.
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules,
  firestore:indexes` in a credentialed env to activate the `optic_logs`
  rules + the `optic_logs` / `farm_pricelists` composite indexes. Until
  deployed the optic-log stream surfaces the index-missing error in-UI
  (graceful, non-crashing) and optic-log writes are denied (best-effort
  `debugPrint`, the optic save itself still succeeds).

## Phase — Scope Settings firearm dropdown replaced with ballistic calculator tactical-HUD pattern (added 2026-08-16)

The Scope Settings & Tools sheet (`lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`) previously used the reusable `FirearmDropdownSelector` widget (`lib/widgets/firearm_dropdown_selector.dart`) backed by `InventoryBridge.watchSafeFirearms()` (`Stream<List<RifleProfile>>`). It was reported as broken — replaced with a verbatim port of the proven tactical-HUD dropdown from `BallisticCalcScreen` (`lib/features/ballistics/presentation/ballistic_calc_screen.dart`).

### Changes
- `_firearmsStream` changed from `Stream<List<RifleProfile>>` (`InventoryBridge.watchSafeFirearms()`) to `Stream<QuerySnapshot>` over raw Firestore `firearms` collection `.where(ownerId, isEqualTo: uid).snapshots().asBroadcastStream()` — the exact query the ballistic calculator uses.
- `_buildFirearmLink()` rewritten as a `StreamBuilder<QuerySnapshot>` with the three ballistic-calc branches: (1) error/no-data/empty docs -> "OFFLINE SAFE MODULE ACTIVE"; (2) no real registered firearms (after filtering demo TIKKA-/SAKO- serials + "Unknown" names) -> "NO REGISTERED FIREARMS"; (3) the live raw `DropdownButton<String>` + `DropdownButtonHideUnderline` + `JagspoorTheme.hudCardBackground` dropdown labelled "Select Firearm Vault Location", items rendered as "make model • [caliber]". The selected id is guarded against a just-deleted firearm (`effectiveValue` null-coalesce) so the DropdownButton never hits the "value not in items" assertion.
- New `_buildHardwareDropdownContainer({label, child})` helper copied verbatim from the ballistic calculator (Container with `JagspoorTheme.hudCardBackground`, walnut border, label + child Column).
- New `_onRifleDocSelected(docs, id)` replaces `_onRifleSelected(rifles, id)` — on selection it hydrates a `RifleProfile` via `RifleProfile.fromFirestore(doc)` so the optic-binding + save flow (`_saveOptic` -> `InventoryBridge.saveOpticProfile`) continues to work unchanged. The turret-unit badge is retained as a trailing `Chip` shown only when a firearm is selected.
- Imports: added `cloud_firestore`, `firebase_auth`, and `show JagspoorTheme` from `ballistic_calc_screen.dart`; removed the `firearm_dropdown_selector.dart` import (no longer used by this screen). `RifleProfile` + `InventoryBridge` imports retained (still used by `_onRifleDocSelected` + `_saveOptic`).

### Notes
- `FirearmDropdownSelector` widget itself is NOT deleted — it remains in use by the Shot Group Target Analyzer screen (`shot_group_analyzer_screen.dart`) + its test (`firearm_dropdown_selector_test.dart`, 6 tests). Only the Scope Settings screen switched to the tactical-HUD pattern.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure UI + stream-source swap; the `firearms` read is already owner-scoped).

### Verification
- `flutter analyze` (lib/ + test/): 0 errors, 0 warnings (306 pre-existing infos, unchanged baseline; the changed file is analyzer-clean — "No issues found").
- `flutter test` (full suite): All 567 tests passed, zero failures. `optic_tools_test.dart` (33) covers the `OpticProfile`/`RifleProfile` models the dropdown reads through; `firearm_dropdown_selector_test.dart` (6) still covers the reusable widget (unchanged).
- Environment note: re-cloned Flutter stable (3.47.0) + installed `unzip` + `libsqlite3-dev` (the SDK + system deps had been removed since the prior session).
- Files: `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart` (only file changed), `AGENTS.md`.


## Phase — Bullet grain slider 30-500gr, copyright footers, WhatsApp removal, native calendar integration (added 2026-08-17)

### 1. Ballistic Calculator bullet weight slider bounds (fixed)
- `lib/features/ballistics/presentation/ballistic_calc_screen.dart`: the
  "Bullet Weight (Grains)" `_buildParameterRow` slider min/max changed from
  `300`/`500` -> `30`/`500` so users can select lightweight loads (55gr,
  150gr) as well as heavy ones. The `_bulletWeightGrains` default changed
  from `300.0` -> `150.0` (a mid-range value inside the new wider band).

### 2. Copyright footers on the three missing screens
- Added the reusable `CopyrightFooter()` widget as the tail child of the
  scrollable body on:
  - Field Estimation screen (`lib/features/game_guide/presentation/field_estimate_screen.dart`)
  - SA Game Guide / Animal List screen (`lib/screens/animal_list_screen.dart`)
  - Weather & Wind Tracker screen (`lib/features/hunter_mode/weather/weather_tracker_screen.dart`)
- Each screen gained the `copyright_footer.dart` import + the widget as the
  last child of its scrollable. The three screens now match the splash /
  auth / hunter-profile / outfitter-settings surfaces that already carry it.

### 3. WhatsApp / external chat buttons removed
- The off-platform payment flow previously exposed a "WhatsApp OUTFITTER"
  button on the hunter booking card and a "WhatsApp Hunter" button on the
  outfitter booking dashboard -- both built on `url_launcher`
  `https://wa.me/<phone>` deep links. Removed so the marketplace + booking
  management surfaces carry only the clean in-app chat + booking workflow:
  - `hunter_package_marketplace_screen.dart`: removed the
    `_contactOutfitterWhatsApp` method + its "WHATSAPP OUTFITTER" button +
    the `url_launcher` import. The in-app `IN-APP CHAT` button is retained.
  - `outfitter_booking_dashboard_screen.dart`: removed the
    `_contactHunterWhatsApp` method + its "WhatsApp Hunter" button (the
    `_buildContactHunterRow` row now renders only the in-app `IN-APP CHAT`
    button) + the `url_launcher` import. Docstrings updated to reference
    the in-app chat drawer only.
- `url_launcher` remains a pubspec dependency (still used by
  `support_email_composer.dart` for the support email handoff).

### 4. Native calendar integration for finalized (Confirmed) bookings
- New `lib/features/hunter_mode/services/booking_calendar_service.dart`:
  - `BookingCalendarService` (singleton) -- the thin platform wrapper. Its
    `buildEvent(booking)` constructs an `add_2_calendar` `Event` from a raw
    booking document map; `addToCalendar(booking)` resolves the event and
    hands it to `Add2Calendar.addEvent2Cal(event)` which opens the device's
    native calendar editor pre-populated with the hunt details. Returns
    `false` when no dates could be resolved (caller surfaces a "no dates on
    file" snackbar instead of launching an empty event).
  - `BookingCalendarEventBuilder` (public, pure, Firebase-aware) -- the
    unit-testable event-construction helper. `resolveDate` handles a
    Firestore `Timestamp`, ISO-8601 string, `DateTime`, or
    milliseconds-since-epoch `num`, collapsing each to midnight (Y/M/D).
    `resolveWindow` resolves the hunt start/end from the booking's date
    fields in priority order (`confirmedStartDate` -> `checkInDate` ->
    `availabilityStart` -> `startDate` -> `huntDate`; end: `confirmedEndDate`
    -> `checkOutDate` -> `availabilityEnd` -> `endDate` -> start). The
    calendar `end` is the start of the day *after* the hunt's final day so
    the native all-day event renders the full final day. `buildTitle`
    ("Package @ Farm"), `buildDescription` (package/farm/outfitter/hunter/
    total/booking-id block), `buildLocation` (farm + district + province),
    `buildEvent` (assembles the all-day `Event` with a 12h iOS reminder).
- New `add_2_calendar: ^3.0.0` dependency in `pubspec.yaml` (pure Dart, no
  native build -- resolves cleanly on the CI Flutter 3.29.1 pin). `Event.allDay = true`
  so the hunt renders as an all-day block in the device calendar.
- Hunter "My Bookings" card
  (`lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`):
  added a green `FilledButton.icon` "ADD HUNT TO CALENDAR" button that
  renders ONLY when the booking status is `Confirmed` or `Completed`
  (`canAddToCalendar`). `_addToCalendar` captures `ScaffoldMessenger` before
  the async gap, calls `BookingCalendarService.instance.addToCalendar`,
  guards `mounted`, and surfaces a green success / orange "no dates" / red
  failure snackbar. Placed after the in-app chat button.
- Outfitter booking dashboard
  (`lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`):
  the archived-status action panel (`Confirmed` / `Completed` / `Declined` /
  `Cancelled`) previously rendered only the "EXPORT INVOICE" button. Now
  also renders the "ADD HUNT TO CALENDAR" green `FilledButton.icon` when
  the status is `Confirmed` or `Completed`. Same `_addToCalendar` handler +
  snackbar contract as the hunter card.
- So both parties can save the hunting dates, farm details, and package
  title to their phone's native calendar once the outfitter verifies the
  direct (off-platform) payment and the booking transitions to Confirmed.
- Tests: `test/booking_calendar_service_test.dart` (36 tests, all pass) --
    `resolveDate` (Timestamp / ISO / DateTime / num / null / empty /
    garbage / trim), `resolveWindow` (priority chain, single-day fallback,
    end-before-start clamp, Timestamp, null when no start), `buildTitle`
    (package @ farm, defaults, blank tolerance), `buildDescription` (all
    fields, base-price fallback, zero-omission, alias tolerance, blank
    omission), `buildLocation` (farm / farm+region / district / province /
    null), `buildEvent` (null when no window, fully-populated all-day
    Event), and the `BookingCalendarService` singleton delegation.

### Verification
- `flutter analyze` (local Flutter 3.29.1, CI pin): 0 errors, 0 warnings
  (276 pre-existing infos, all `avoid_print` / `deprecated_member_use`
  style hints in unrelated files; no new issues introduced). The new
  service + test files are analyzer-clean.
- `flutter test` (full suite): 595 passed, 2 failed. The 2 failures are the
  documented pre-existing `fake_cloud_firestore 4.1.1` compile-skew test
  files (`bug_report_screenshot_test.dart` +
  `offline_sync_queue_test.dart`) -- verified to fail identically on the
  clean HEAD baseline (before these changes); the compile error is inside
  `fake_cloud_firestore`'s own `MockWriteBatch.update` source, not in any
  file touched by this work. No regressions: +36 vs the prior pass baseline,
  exactly the new calendar tests.
- No Firestore rules / index / Storage / manifest changes (pure client-side
  UI + a new pure service + tests; the `add_2_calendar` plugin uses the
  platform's own calendar permissions, no app manifest edit required for
  the add-event flow it drives).
- Files: `lib/features/ballistics/presentation/ballistic_calc_screen.dart`
  (slider bounds + default), `lib/features/game_guide/presentation/field_estimate_screen.dart`
  (footer), `lib/screens/animal_list_screen.dart` (footer),
  `lib/features/hunter_mode/weather/weather_tracker_screen.dart` (footer),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (WhatsApp removed, calendar button + handler),
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`
  (WhatsApp removed, calendar button + handler),
  `lib/features/hunter_mode/services/booking_calendar_service.dart` (NEW),
  `pubspec.yaml` / `pubspec.lock` (`add_2_calendar` dep),
  `test/booking_calendar_service_test.dart` (NEW, 36 tests), `AGENTS.md`.

## Phase — Custom Package Builder blank-screen fix + Shot Group Analyzer firearm dropdown (added 2026-08-17)

### Task 1: Shot Group Target Analyzer firearm dropdown (verified already in place)
- The Shot Group Target Analyzer screen
  (`lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`)
  already had the firearm dropdown fully implemented (confirmed during this
  session, no change needed): a `StreamBuilder<List<RifleProfile>>` over
  `_inventoryBridge.watchSafeFirearms().asBroadcastStream()` (the `ownerId`
  query fix from Phase 2 removes the missing `.orderBy('name')` so every
  owner-scoped firearm doc renders) feeding the reusable
  `FirearmDropdownSelector` widget (`lib/widgets/firearm_dropdown_selector.dart`),
  rendered ABOVE the gesture canvas (`ShotGroupTargetOverlay`) in the body
  Column so the overlay's tap detector never intercepts dropdown taps. The
  selected `_selectedFirearmId` is resolved to a `RifleProfile` via
  `_resolveRifle()` and stamped onto the saved `TargetSessionLog` as
  `firearmId` + `firearmLabel` (`rifle.displayName`). The empty-state shows
  the "No firearms in safe yet — add one in the Digital Firearm Safe" hint.
  The existing `firearm_dropdown_selector_test.dart` (6 widget tests) covers
  the selector: live dropdown renders display names; stale id coerces to
  null (no assertion); empty list renders the disabled hint field; loading
  renders LinearProgressIndicator; trailing hidden while loading/empty;
  reports selection via onChanged.

### Task 2: Custom Package Builder blank-screen diagnosis + fix
- **Diagnosis**: the Custom Package Builder
  (`lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`)
  rendered completely blank except the copyright footer because its nested
  reactive `StreamBuilder`s had NO `ConnectionState.waiting` branch AND the
  species stream (`FarmGamePriceListManager.getFarmPriceListStreamForHunter`)
  used a server-side `.where('farmId').orderBy('speciesName').snapshots()` —
  an equality + orderBy combo requiring a Firestore composite index
  (`farmId ASC + speciesName ASC`). Until that index is deployed, the server
  errors with "Missing Composite Index"; combined with no loading branch,
  the StreamBuilder rendered nothing (blank body). The same composite-index
  bug affected the owner-scoped `getFarmPriceListStream`.
- **Fix (`farm_game_price_list_manager.dart`)**:
  - Removed `.orderBy('speciesName')` from BOTH reactive streams
    (`getFarmPriceListStream` owner-scoped + `getFarmPriceListStreamForHunter`
    hunter-readable) AND the one-shot `getFarmPriceListForHunter`. The
    equality-only `.where('farmId')` query uses the automatic single-field
    index (no composite index needed); the entries are now sorted client-side
    in Dart via `entries.sort((a, b) => a.speciesName.compareTo(b.speciesName))`.
    This mirrors the established project pattern (optic logs, package
    streams) of avoiding equality+orderBy combos that require composite
    indexes.
  - Wrapped BOTH reactive streams (`farm_pricelists` + the single-doc
    `farm_service_rates` stream) in `OfflineStreamGuard.offlineResilient`
    so a hard error (missing index, permissions change, offline with no
    cache) emits the fallback (`[]` / `FarmServiceRates.empty`) and completes
    instead of hanging the StreamBuilder.
  - Added injection seams (`firestoreForTesting` /
    `currentUserIdResolverForTesting` + a `forTesting` factory) mirroring
    `OpticLogService.forTesting` / `FeedbackFirebaseService`, so the stream
    contract can be unit-tested against `FakeFirebaseFirestore` without a
    live Firebase app. The `_currentUserId` getter now wraps
    `FirebaseAuth.instance.currentUser` in a try/catch so a missing Firebase
    app (`[core/no-app]` during a cold-launch race or a widget test) resolves
    to null (-> empty stream) instead of throwing.
- **Fix (`pricelist_scanner_service.dart`)**: converted the eager field
  initializers `final FirebaseFirestore _firestore = FirebaseFirestore.instance`
  / `final FirebaseAuth _auth = FirebaseAuth.instance` to lazy getters. The
  eager initializers threw `[core/no-app]` when the singleton was constructed
  before `Firebase.initializeApp()` (cold-launch race / widget test), which
  crashed the Custom Package Builder screen at State construction (the screen
  holds `PricelistScannerService.instance` as a field initializer). Lazy
  getters defer the Firebase access to first use (semantically equivalent for
  production; robust for cold-launch + testable).
- **Fix (`hunter_custom_package_builder_screen.dart`)**: added an explicit
  `ConnectionState.waiting` branch to the builder's nested StreamBuilder
  (renders a centered `CircularProgressIndicator` + "Loading farm price
  list..." text) so the first-load state renders a defined widget instead of
  a blank body. The error branch (`hasError` -> cloud-off banner) and empty
  branch (no pricing -> "No pricing published yet" banner) were already
  present. The complete builder UI (dates card, party steppers, species rows
  with qty steppers, itemized service-rate rows, Grand Total bottom bar,
  submit button + confirmation view with chat + calendar) was already in
  place — the only issue was the blank screen from the hanging stream, now
  fixed.

### Tests
- `test/custom_package_builder_screen_test.dart` (NEW, 3 widget tests, all
  pass): renders the Scaffold with the farm name AppBar (not blank); renders
  the defined "No pricing published yet" empty state (not blank / not a hung
  spinner) for an unauthenticated caller with no visible pricing; renders the
  CopyrightFooter.
- `test/farm_game_price_list_stream_test.dart` (NEW, 6 unit tests, all pass):
  null uid -> empty stream (no throw, no Firestore access); returns the
  farm's species sorted by name client-side (non-alphabetical insertion order
  -> alphabetical output, proving the client sort); only the requested
  farm's species returned (farmId filter); the one-shot
  `getFarmPriceListForHunter` sorts client-side too; the owner-scoped
  `getFarmPriceListStream` filters by outfitterId + sorts client-side.
- The existing `firearm_dropdown_selector_test.dart` (6 tests) already covers
  Task 1's dropdown.

### Verification
- `flutter analyze` (lib/ + test/, Flutter 3.29.1 CI pin): **0 errors, 0
  warnings** (279 infos, all pre-existing `avoid_print` /
  `deprecated_member_use` / style hints in unrelated files; the changed
  files are analyzer-clean — "No issues found").
- `flutter test` (full suite): **All 627 tests passed**, zero failures
  (was 618; +9 = 3 new builder widget tests + 6 new stream unit tests). No
  regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side stream-resilience + testability seams; the equality-only
  `.where('farmId')` query uses the automatic single-field index so no
  composite index deployment is required).
- Commit `1c9bd9f` pushed to `origin/main` (clean fast-forward
  `6256799..1c9bd9f`); local/origin in sync, working tree clean.
- Files: `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`
  (removed orderBy + client sort + OfflineStreamGuard + injection seams),
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`
  (lazy firestore/auth getters),
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (loading branch),
  `test/custom_package_builder_screen_test.dart` (NEW, 3 tests),
  `test/farm_game_price_list_stream_test.dart` (NEW, 6 tests), `AGENTS.md`.

## Phase — Re-wire Custom Package Builder off outfitter scanner data (added 2026-08-17)

The Custom Package Builder was reported still rendering empty, with the user
suspecting an incorrect coupling to the outfitter-named
`PricelistScannerService` / an outfitter-scoped data source. Audit + fix.

### Audit findings
- The builder's READ path was ALREADY correctly wired to hunter-readable data:
  - `hunter_custom_package_builder_screen.dart` streams species via
    `FarmGamePriceListManager.getFarmPriceListStreamForHunter(farmId)`
    (queries `farm_pricelists` by `.where('farmId')` only — NO `outfitterId`
    filter) and itemized fees via `getFarmServiceRatesStream(farmId)` — both
    readable by any signed-in hunter per `firestore.rules` (`read: isSignedIn()`).
  - The farm-selection screen (`custom_package_farm_selection_screen.dart`)
    discovers bookable farms from `farm_pricelists` + `farm_service_rates`
    (no owner filter) and resolves `farms` docs — also `read: isSignedIn()`.
  - The Firestore rules for `farm_pricelists`, `farm_service_rates`, and
    `farms` ALL allow `read: if isSignedIn()` (no outfitter restriction), so a
    signed-in hunter CAN read published price lists.
- The REAL coupling the user flagged: the builder's WRITE path imported
  `PricelistScannerService` (an outfitter-named service) solely to call
  `submitCustomPackageBooking`. `PricelistScannerService` was the ONLY consumer
  of that import and was the only place the builder touched an
  outfitter-named/scanner module — the source of the "incorrectly wired to
  outfitter scanner data" suspicion. Its remaining methods
  (`getAllActivePricelists`, `getActivePricelistForFarm`, `getFarmHuntingCatalog`,
  `calculateTotalWithFee`) were dead code (zero callers; the only
  `getActivePricelistForFarm` reference was a docstring comment in
  `farm_config.dart`).

### Fix — consolidate the full hunter read+write path on the price-list manager
- **Moved `submitCustomPackageBooking` into `FarmGamePriceListManager`**
  (`lib/features/hunter_mode/services/farm_game_price_list_manager.dart`).
  The method writes the `bookings` doc with `status: BookingStatus.pendingApproval`,
  `isCustomPackage: true`, `hunterId: <caller uid>`, `outfitterId`, `farmId`,
  normalized `selectedItemsList` + `lodgingCateringList`, party/window meta,
  and the no-commission pricing (`basePriceRands == totalHunterPriceRands`).
  The submit path now reads the caller uid via the existing injectable
  `_currentUserId` getter (the same seam the stream queries use), so it is
  unit-testable without a live `FirebaseAuth` app and is cold-launch-safe
  (try/catch around `FirebaseAuth.instance` resolves to null instead of
  throwing `[core/no-app]`).
- **Builder screen decoupled**: removed the `PricelistScannerService` import
  + the `_bookingService` field; the submit call now goes through
  `_priceListManager.submitCustomPackageBooking`. The builder now imports
  ONLY `FarmGamePriceListManager` for both reads and the write — the full
  hunter-facing custom-package path is consolidated on the hunter-readable
  price-list manager.
- **Deleted `lib/features/hunter_mode/services/pricelist_scanner_service.dart`**
  entirely — it had no remaining consumers (confirmed via grep: only the
  builder imported it, and only for the moved method). Eliminates the
  outfitter-scanner-named module the user flagged as the suspected wrong
  data source. No `scanned_pricelists` reads remain in `lib/` (the remaining
  references are docstring comments in `farm_config.dart` / `auth_screen.dart` /
  `splash_screen.dart` describing owner-scoped outfitter collections — not
  active code).

### Result
- The Custom Package Builder now depends on a SINGLE hunter-readable service
  (`FarmGamePriceListManager`) for: the species stream, the service-rates
  stream, AND the booking submission. There is no outfitter-scoped /
  scanner-named dependency anywhere in the builder or its data path. The
  "still empty" symptom — when it occurs — is now strictly a function of
  whether the selected farm has published pricing (the defined "No pricing
  published yet" empty-state banner), never a wrong-data-source / wrong-scope
  read.

### Tests
- `test/farm_game_price_list_stream_test.dart` extended with a new
  `submitCustomPackageBooking (hunter-mode booking write)` group — 5 tests,
  all pass (via the `forTesting` factory + `FakeFirebaseFirestore`):
  - writes the booking doc to `bookings` with the full hunter-mode shape
    (`status: pendingApproval`, `isCustomPackage: true`, `hunterId`,
    `outfitterId`, `farmId`, `farmName`, `packageId: 'CUSTOM_BUILT'`,
    `basePriceRands == totalHunterPriceRands` (no commission), party/window
    meta, both normalized line-item lists, and the returned id matches the
    written doc);
  - rejects an unauthenticated caller;
  - prevents an outfitter from booking their own farm;
  - rejects an empty selection;
  - rejects a non-positive total.
- The existing 6 stream tests (null-uid, client-side sort, farmId filter,
  owner-scoped filter) still pass — total 11 in the file.

### Verification
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings** (278 infos, all
  pre-existing `avoid_print` / `deprecated_member_use` / style hints; the
  changed files are analyzer-clean — "No issues found"). The deleted file
  dropped 1 pre-existing `print` info.
- `flutter test` (full suite): **All 632 tests passed**, zero failures
  (was 627; +5 = the new booking-submission tests). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side service consolidation + a deleted dead module; the read rules
  were already `isSignedIn()` and the `bookings` create rule already permits
  a signed-in hunter to create a booking under their own `hunterId`).
- Commit `33d58c2` pushed to `origin/main` (clean fast-forward
  `869d156..33d58c2`); local/origin in sync, working tree clean. (The push
  initially hit a stale-token password prompt; the remote URL was re-seeded
  with the current `GITHUB_TOKEN` and the push succeeded.)
- Files: `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`
  (`submitCustomPackageBooking` moved here + docstring),
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (decoupled — uses `_priceListManager.submitCustomPackageBooking`,
  `PricelistScannerService` import + field removed),
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart` (DELETED),
  `test/farm_game_price_list_stream_test.dart` (+5 booking-submission tests),
  `AGENTS.md`.


## Phase — Custom Package Builder blank-body fix (cached streams) (added 2026-08-17)

The Custom Package Builder screen
(`lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`)
was reported STILL rendering a completely blank body (no loading spinner, no
empty-state banner, no error banner — nothing between the AppBar and the
footer) after the prior "add a loading branch" fix.

### Root cause
- `_buildBuilderView` created the two reactive streams INLINE inside
  `build()`:
  `StreamBuilder(stream: _priceListManager.getFarmPriceListStreamForHunter(widget.farmId))`
  whose builder returned an INNER
  `StreamBuilder(stream: _priceListManager.getFarmServiceRatesStream(widget.farmId))`.
- The manager's stream getters build a FRESH `OfflineStreamGuard` broadcast
  controller + a FRESH Firestore `.snapshots()` subscription on EVERY call.
  So every State rebuild (e.g. each qty-stepper `setState`, a theme toggle, a
  parent `setState`) re-created BOTH streams.
- The outer StreamBuilder's builder returns the INNER StreamBuilder, so each
  outer emission re-ran the builder, which re-created the inner stream → the
  inner StreamBuilder re-subscribed → reset to `ConnectionState.waiting` → the
  loading guard fired → a rebuild churn loop that never let the screen settle
  on real data. On some device/timing combos this left the body painting
  nothing visible (the reported "completely blank" symptom).
- The loading/error/empty branches were all present and correct, but the
  stream-recreation churn prevented the screen from ever stably landing on a
  visible widget for real (slow) Firestore streams.

### Fix
- Cache the two streams ONCE in `initState` as `late final` fields
  (`_speciesStream` / `_ratesStream`). `build()` now references the cached
  fields, so the StreamBuilders keep a stable subscription for the screen's
  lifetime — no re-creation, no re-subscribe churn. This mirrors the
  documented project pattern (`ballistic_calc_screen` /
  `scope_tools_bottom_sheet` cache `.asBroadcastStream()` streams in
  `initState` for the same reason).
- Extracted the loading branch into a dedicated `_LoadingView` widget so
  the "waiting" state is a single, always-visible, always-`Center`-painted
  widget — never an empty `Container` / `SizedBox` that could leave the body
  blank. (The loading/error/empty branches were already correct; this just
  makes the contract structurally explicit.)

### Tests
- `test/custom_package_builder_screen_test.dart` extended from 3 → 6 tests,
  all pass:
  - (existing) AppBar renders farm name (not blank).
  - (existing) unauthenticated caller (null uid -> `Stream.empty()` /
    `Stream.value(empty)`) lands on the "No pricing published yet" banner.
  - (existing) CopyrightFooter survives.
  - NEW "PRODUCTION: renders a visible widget (not blank) on the first frame
    with real Firestore streams" — swaps the singleton's test seams for a
    `FakeFirebaseFirestore` + real uid so the streams are genuine
    `.snapshots()` streams wrapped in OfflineStreamGuard (mirrors production),
    then asserts the body paints at least one visible state widget (spinner OR
    banner) on the very first `pump()` — never blank.
  - NEW "PRODUCTION: renders the empty-state banner once an empty Fake
    Firestore settles" — asserts the body lands on the "No pricing published
    yet" banner (not a hung spinner, not blank) after `pumpAndSettle`.
  - NEW "PRODUCTION: a rebuild (setState) does NOT recreate the streams" —
    uses a `_RebuildProbe` stateful wrapper to trigger an in-place `setState`
    rebuild (same `HunterCustomPackageBuilderScreen` State survives, so the
    cached `late final` stream fields persist) and asserts the body STAYS on
    the empty-state banner (no flicker-to-blank, no re-subscribe churn). This
    is the direct regression guard for the root cause.
- The unauthenticated-caller test (null uid) still passes because the manager
  resolves `_currentUserId` to null in the test runner → `Stream.empty()` /
  `Stream.value(empty)` (cached once in initState now) → empty-state banner.

### Verification
- `flutter analyze` (lib/ + test/, Flutter 3.47.0): **0 errors, 0 warnings**
  (308 infos, all pre-existing `avoid_print` / `deprecated_member_use` /
  style hints in unrelated files; the changed screen + test are
  analyzer-clean — "No issues found").
- `flutter test` (full suite): **All 641 tests passed**, zero failures
  (was 632; +6 = the new/extended builder-screen tests). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side stream-caching + a widget extraction).
- Files: `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (cached `late final` streams in initState + `_LoadingView` extraction),
  `test/custom_package_builder_screen_test.dart` (+3 production-scenario
  tests + `_RebuildProbe` wrapper), `AGENTS.md`.


## Phase — Calendar button payload alignment + package date fallback (added 2026-08-17)

The "ADD HUNT TO CALENDAR" button on the hunter booking card
(`hunter_package_marketplace_screen.dart`) and the outfitter booking dashboard
(`outfitter_booking_dashboard_screen.dart`) could surface "No hunt dates on
file" even when the booking referenced a package that carries availability
dates, because the calendar action only consulted the booking document's own
date fields.

### Audit
- Both `_addToCalendar()` call sites already pass `widget.data` — the SAME
  raw booking document map the UI card reads through
  `BookingCalendarEventBuilder.resolveWindow(widget.data)` (hunter card
  line 1599). So there was no field-name divergence between the UI's date
  resolution and the calendar action's date resolution: both used the same
  resolver on the same map.
- The gap: when the booking document itself did not copy the package's
  availability dates at booking time (an older booking, or a booking created
  before the date-copy logic shipped), `resolveWindow(booking)` returned
  null -> `addToCalendar` returned false ("No hunt dates on file") even
  though the booking referenced a `packageId` whose `packages/{packageId}`
  document carries `availabilityStart` / `availabilityEnd`. The calendar
  action had no package fallback.

### Fix — `BookingCalendarService` package fallback
(`lib/features/hunter_mode/services/booking_calendar_service.dart`)
- New `buildEventWithPackageFallback(booking)` async method. Resolution
  order:
  1. `BookingCalendarEventBuilder.resolveWindow(booking)` — the SAME
     resolver the UI card uses, so the calendar event matches the dates the
     hunter is already seeing on the card. If non-null -> build the event
     from the booking map (no package read).
  2. If null AND the booking references a `packageId` -> fetch
     `packages/{packageId}`, merge its fields into a copy of the booking
     map (`{...pkgData, ...booking}` — booking fields take precedence so a
     post-date-change `confirmedStartDate` on the booking wins over the
     package's advertised availability), and re-resolve + build the event.
     The event's title / description / location still come from the booking
     (the package only contributes dates), so the calendar entry stays tied
     to the booked trip.
  3. Otherwise -> null (caller surfaces "no dates on file").
- `addToCalendar(booking)` now delegates to `buildEventWithPackageFallback`
  so the button's onPressed (which passes `widget.data`) gets the package
  fallback automatically — the call sites needed NO change (they already
  pass the same map the UI reads).
- `_resolvePackageId` tolerates `packageId` / `package_id` / `packageID`
  field-name aliases, and short-circuits the `'CUSTOM_BUILT'` sentinel
  (custom-built packages have no `packages` doc -> no fetch attempt).
- A Firestore fetch error (offline / permissions / not-found /
  `[core/no-app]`) is caught and returns null (caller surfaces "no dates")
  so the calendar action never crashes.
- Test seam: `firestoreForTesting` (`@visibleForTesting`) injects a
  `FirebaseFirestore` (e.g. `FakeFirebaseFirestore`) so the fallback fetch
  is unit-testable without a live Firebase app.

### Tests
- `test/booking_calendar_service_test.dart` extended from 36 -> 44 tests
  (all pass), +8 in a new
  `BookingCalendarService.buildEventWithPackageFallback` group:
  - uses booking dates directly when the booking has date fields (no fetch);
  - falls back to the package availability window when the booking has no
    date fields (the core fix contract — calendar action never fails when
    the booking references a package with availability dates);
  - returns null when the booking has no dates AND no packageId;
  - returns null when the referenced packageId does not exist;
  - does NOT attempt a fetch for the CUSTOM_BUILT sentinel;
  - tolerates the `package_id` snake_case alias;
  - package fallback does NOT fire when the booking has a start date
    (`resolveWindow(booking)` is non-null -> single-day event from the
    booking alone, matching the UI card);
  - a Firestore fetch error (no Firebase app) does not crash — returns null.

### Verification
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings** (308 pre-existing
  infos; the changed service + test are analyzer-clean — "No issues found").
- `flutter test` (full suite): **All 649 tests passed**, zero failures
  (was 641; +8 = the new package-fallback tests). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side service enhancement + tests; the `packages` read is already
  `isSignedIn()` per `firestore.rules`).
- Files: `lib/features/hunter_mode/services/booking_calendar_service.dart`
  (`buildEventWithPackageFallback` + `_resolvePackageId` + `firestoreForTesting`
  seam + `addToCalendar` delegation),
  `test/booking_calendar_service_test.dart` (+8 package-fallback tests +
  `fake_cloud_firestore` import), `AGENTS.md`.


## Phase — Remove Export Invoice from outfitter booking cards + outfitter hunt-dates banner (added 2026-08-17)

JagSpoor does not handle physical sales between hunter and outfitter, so the
blue "EXPORT INVOICE" button was removed entirely from the outfitter booking
card, and a hunt-dates banner (mirroring the hunter card) was added so the
outfitter sees the dates before tapping "ADD HUNT TO CALENDAR".

### Task 1 -- Export Invoice removal
(`lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`)
- Removed the "EXPORT INVOICE" `ElevatedButton.icon` from BOTH action-button
  branches of `_buildActionButtons`:
  - the `Awaiting Payment` (and legacy `Approved`) branch (was the secondary
    button under the VERIFY / CONFIRM PAYMENT RECEIVED button);
  - the Archived branch (Confirmed / Completed / Declined / Cancelled) -- the
    archived branch now renders ONLY the "ADD HUNT TO CALENDAR" button (for
    Confirmed / Completed); Declined / Cancelled render no actions.
- Removed the `_exportInvoice()` method, the `_isExporting` State field, the
  `outfitter_invoice_exporter.dart` import, and updated the `_buildActionButtons`
  docstring to drop the EXPORT INVOICE references.
- Deleted the now-orphaned `lib/features/hunter_mode/services/
  outfitter_invoice_exporter.dart` service file (zero remaining consumers in
  `lib/` or `test/` -- confirmed via grep). The booking-card financial
  breakdown (Total row) is still rendered inline on the card.

### Task 2 -- Calendar fallback + hunt-dates banner
- The outfitter `_addToCalendar()` already calls
  `BookingCalendarService.instance.addToCalendar(widget.data)`, which (since
  the prior phase) delegates to
  `BookingCalendarService.buildEventWithPackageFallback` -- so the outfitter
  calendar action ALREADY uses the package availability-window fallback when
  the booking document itself lacks date fields. No call-site change was
  needed; the docstring was expanded to document the fallback contract.
- NEW `_buildHuntDatesBanner()` on the outfitter booking card: renders a
  `Hunt dates: <start> -> <end>` banner using
  `BookingCalendarEventBuilder.resolveWindow(widget.data)` -- the SAME
  resolver the hunter card uses (and the SAME resolver
  `addToCalendar`/`buildEventWithPackageFallback` uses) -- so the outfitter
  sees the exact dates that will be written to the device calendar before
  tapping "ADD HUNT TO CALENDAR". Placed between the date-change section and
  the action buttons. Returns `SizedBox.shrink` when the booking has no
  resolvable dates on file (the calendar action's package fallback will still
  attempt to resolve them on tap). The displayed end date is the actual final
  hunt day (resolveWindow's `end` minus 1 day, since `end` is the
  calendar-exclusive next-day for all-day events).
- Added `package:intl` import (`DateFormat('d MMM yyyy')`).

### Verification
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings** (308 pre-existing
  infos; the changed dashboard is analyzer-clean -- "No issues found").
- `flutter test` (full suite): **All 649 tests passed**, zero failures. No
  regressions (the orphaned exporter had no dedicated tests; the calendar
  service's package-fallback suite from the prior phase still covers
  `addToCalendar`'s resolution contract).
- No Firestore rules / index / Storage / pubspec / manifest changes (pure UI
  removal + a banner widget + a deleted dead service file).
- Files: `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`
  (export-invoice removal + `_buildHuntDatesBanner` + intl import + docstring),
  `lib/features/hunter_mode/services/outfitter_invoice_exporter.dart` (DELETED),
  `AGENTS.md`.


## Phase — Firestore bookings enterprise read: explicit outfitter + farm-manager access (added 2026-08-17)

Hardened the `match /bookings/{bookingId}` read rule so the outfitter
enterprise query path is explicit and a farm manager assigned to the
booking's farm can read enterprise bookings.

### Audit finding
- The previous `allow read: if isAdmin() || isBookingParty()` (where
  `isBookingParty()` checked `hunterId == uid || outfitterId == uid`) ALREADY
  permitted the outfitter's `.where('outfitterId', isEqualTo: currentUserId)`
  list query (Firestore's query-based security validates the query constrains
  `outfitterId` to `request.auth.uid`, which the rule checks). So the
  outfitter read was functionally correct but implicit -- the contract was
  buried inside the combined `isBookingParty()` helper.
- The **farm-manager branch** of the outfitter booking dashboard
  (`_buildBookingQuery`, `.where('farmId', isEqualTo: assignedFarmId)`) was a
  genuine gap: a farm manager is neither the hunter nor the outfitter on the
  booking doc, so `isBookingParty()` rejected their list query with
  `PERMISSION_DENIED`. Single-doc reads by a manager (e.g. the calendar
  package-fallback fetch) were also rejected.

### Rule changes (`firestore.rules`)
- Split the bookings read helpers for clarity + an explicit outfitter clause:
  - `isBookingHunter()` -- `resource.data.hunterId == request.auth.uid`
    (the hunter path; queryable for `.where('hunterId', isEqualTo: uid)`).
  - `isBookingOutfitter()` -- `resource.data.outfitterId == request.auth.uid`
    (the enterprise outfitter path; queryable for the outfitter's
    `.where('outfitterId', isEqualTo: uid)` list query).
  - `isBookingParty()` -- `isBookingHunter() || isBookingOutfitter()`
    (back-compat for the existing update/chat callers).
  - `isFarmManagerForBooking()` -- NEW. Looks up
    `farm_managers/{request.auth.uid}` and grants read when the manager's
    assigned `farmId` matches the booking's `farmId`. Covers single-doc
    enterprise reads by a farm manager.
- `allow read: if isAdmin() || isBookingParty() || isFarmManagerForBooking()`
  -- admin, hunter, outfitter, OR farm manager on the booking's farm.
- `statusUpdateAllowed()` / `create` / `update` / `delete` / `chats` --
  unchanged (the outfitter-only status flip, hunter-only create,
  non-outfitter status-freeze update, admin-only delete, and booking-party
  chat subcollection restrictions are all preserved).

### Manager list-query note (documented limitation)
- A `get()`-based rule (`isFarmManagerForBooking`) is NOT directly queryable
  for the manager's `.where('farmId', isEqualTo: assignedFarmId)` LIST query
  (Firestore's query-based security only validates list queries whose filter
  constrains a field the rule checks against `request.auth.uid`; the
  manager's farmId lives on a different doc). The dashboard's manager branch
  comment now documents this, plus the future data-migration path (add a
  `managerUids` array to bookings so the manager can query
  `.where('managerUids', arrayContains: uid)` against a queryable rule).
  Single-doc manager reads work today via the get()-based rule.

### Tests
- `test/firestore_rules_seeding_test.dart` gained a "bookings enterprise
  access" group (8 structural tests, all pass): bookings match block present;
  outfitter read explicit (`outfitterId == request.auth.uid`); hunter read
  explicit; read grants hunter OR outfitter OR manager OR admin;
  farm-manager get()-based path present; create requires `hunterId == caller`
  (no spoofing); status flip outfitter-only (`statusUpdateAllowed` +
  non-outfitter status-freeze); delete admin-only. Total 22 in the file
  (was 14).

### Verification
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings** (308 pre-existing
  infos; the changed dashboard + rules test are analyzer-clean).
- `flutter test` (full suite): **All 657 tests passed**, zero failures
  (was 649; +8 = the new bookings rules tests). No regressions.
- Deploy: `npx firebase-tools deploy --only firestore:rules` CANNOT run in
  this sandbox -- no `FIREBASE_TOKEN` / `firebase login` (verified:
  `firebase projects:list` errors with an auth failure, matching the
  AGENTS.md environment-constraints note). The ruleset is committed + pushed;
  the deploy MUST be run in a credentialed environment:
  `npx firebase-tools deploy --only firestore:rules`.

- Files: `firestore.rules` (bookings read helpers + manager read path),
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`
  (`_buildBookingQuery` comments documenting the queryable outfitter path +
  the manager list-query limitation),
  `test/firestore_rules_seeding_test.dart` (+8 bookings rules tests),
  `AGENTS.md`.

## "Add Hunt to Calendar" end-to-end audit (added 2026-08-18)

Rigorous audit of the "Add Hunt to Calendar" flow across Hunter + Outfitter
modes. Two real defects found + fixed; service + tests otherwise verified
100% functional.

### Task 1 — Data & fallback flow (verified + 2 fixes)
- **Trace booking data**: both the Hunter `_HunterBookingCard` and the
  Outfitter `_BookingCard` pass `widget.data` (the raw booking document map
  from `doc.data() as Map<String, dynamic>`) into
  `BookingCalendarService.instance.addToCalendar(data)`.
  `BookingCalendarEventBuilder.resolveWindow(widget.data)` is the SAME
  resolver both the on-card hunt-dates banner AND the calendar action (via
  `buildEventWithPackageFallback`) use, so the calendar event's dates always
  match the dates displayed on the card.
- **Package fallback**: `buildEventWithPackageFallback(booking)` verified
  correct: (1) resolves via `resolveWindow(booking)` -- no package read when
  the booking carries dates; (2) on null, falls back to
  `packages/{packageId}` (seeded via `FakeFirebaseFirestore` in the 44-test
  suite), merges `{...pkgData, ...booking}` (booking fields win, so a
  post-date-change `confirmedStartDate` overrides the package's advertised
  availability), and re-resolves; (3) short-circuits the `CUSTOM_BUILT`
  sentinel (no 404); (4) tolerates the `package_id` snake-case alias;
  (5) catches Firestore errors -> null (no crash). Covers every requested
  alias: `startDate`/`endDate`, `checkInDate`/`checkOutDate`,
  `availabilityStart`/`availabilityEnd`, `confirmedStartDate`/
  `confirmedEndDate`, `huntDate`.
- **UI date banners**: both screens render the hunt-dates banner via
  `resolveWindow(widget.data)` -> `SizedBox.shrink` when null (so a valid
  booking never shows "No hunt dates on file" on the card; the calendar
  action's package fallback still attempts resolution on tap).

### Defect 1 — Hunter banner showed a spurious extra day (fixed)
- `resolveWindow` normalizes `end` to the day *after* the final hunt day
  (calendar-exclusive, so an all-day event spans the full final day). The
  Outfitter banner already subtracted 1 day
  (`huntEnd = window.end.subtract(Duration(days: 1))`), but the Hunter banner
  rendered `window.end` directly -- so a single-day hunt (Jan 5) wrongly
  displayed as "Jan 5 -> Jan 6". Fixed the Hunter banner to mirror the
  outfitter's `huntEnd` subtraction. (File: `hunter_package_marketplace_screen.dart`.)

### Defect 2 — Booking ID was missing from the calendar description (fixed)
- The booking doc `id` lives on the `QueryDocumentSnapshot`, NOT inside the
  `data()` map; both cards hold it separately as `widget.bookingId`.
  `buildDescription` reads `booking['id'] ?? booking['bookingId']` -- which
  was always null -> the "Booking ID:" line was silently omitted from the
  calendar event description. Fixed both call sites to inject the id at the
  call boundary: `addToCalendar({...widget.data, 'id': widget.bookingId})`
  (minimal, no service API change; `buildDescription` already consumes
  `booking['id']`). Now the device calendar event carries the Booking ID
  for reference. (Files: `hunter_package_marketplace_screen.dart`,
  `outfitter_booking_dashboard_screen.dart`.)

### Task 2 — Device calendar integration (verified)
- `BookingCalendarService.addToCalendar` builds the all-day `Event`
  (`startDate`/`endDate` midnight-local, `allDay: true`, 12h iOS reminder)
  and hands it to `Add2Calendar.addEvent2Cal(event)`. Returns `false` (not a
  crash) when no event resolves or the platform rejects it -> the caller
  surfaces the orange "No hunt dates on file" / red failure snackbar. Both
  `_addToCalendar` handlers capture `ScaffoldMessenger.maybeOf(context)`
  before the async gap, guard `mounted`, and try/catch -> graceful feedback
  on every path. `flutter analyze` on the three touched files: **No issues
  found.**

### Verification
- `flutter analyze` (local Flutter 3.47.0 stable) on the three touched
  files (`booking_calendar_service.dart`,
  `hunter_package_marketplace_screen.dart`,
  `outfitter_booking_dashboard_screen.dart`): **No issues found!** (0
  errors, 0 warnings, 0 infos introduced; project baseline unchanged).
  `analysis_options.yaml` + `pubspec.lock` auto-touched by `flutter pub get`
  were reverted before commit (per the documented baseline pattern).
- `flutter test test/booking_calendar_service_test.dart`: 44/44 pass
  (all date aliases, package fallback incl. CUSTOM_BUILT + snake-case
  alias + merge precedence + Firestore-error resilience, buildDescription
  Booking ID line, all-day Event shape).
- `flutter test` (full suite): **All 657 tests passed**, zero failures. No
  regressions (the `id`-injection at the call boundary doesn't change the
  service contract; the banner end-date fix is a pure label correction).
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side UI label + call-site `id` injection; the `packages` read in
  the fallback is already `isSignedIn()` per `firestore.rules`).
- Files: `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (banner end-date fix + `id` injection),
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`
  (`id` injection), `AGENTS.md`.

## Package date picker serialization & booking calendar mapping audit (added 2026-08-18)

Audited the package-creation date picker → Firestore serialization → booking
creation → calendar fallback pipeline across Hunter + Outfitter modes.

### Task 1 — Package creation date serialization (VERIFIED CORRECT, no fix)
- `outfitter_package_creator_screen.dart` date picker writes
  `_availabilityStart` / `_availabilityEnd` as `DateTime?` (lines 82-83,
  389-395). `_publishPackage` builds
  `PackagePricing(availabilityStart: _availabilityStart,
  availabilityEnd: _availabilityEnd)`.
- `PackagePricing.toMap()` serializes them as
  `Timestamp.fromDate(availabilityStart!)` / `Timestamp.fromDate(
  availabilityEnd!)` (package_pricing.dart lines 215-219) — Firestore
  `Timestamp`, never dropped/nulled.
- `publishPackage` spreads `...pricing.toMap()` into the package doc
  (package_booking_manager.dart line 97); `updatePackage` does
  `update..addAll(pricing.toMap())` (line 170). Edit-mode prefill
  round-trips `Timestamp`→`DateTime` (creator lines 159-162). ✓
- `bookPackage` copies the package's `availabilityStart`/`availabilityEnd`
  onto the booking under BOTH `startDate`/`endDate` AND
  `availabilityStart`/`availabilityEnd` aliases (verbatim Timestamps,
  preserving server-accurate precision). ✓

### Task 2 — Booking calendar fallback (VERIFIED + 1 fix)
- **Package fallback** (`BookingCalendarService.buildEventWithPackageFallback`):
  verified correct (44 calendar tests) — booking dates win (no package
  read); on null, fetches `packages/{packageId}` handling
  `packageId`/`package_id`/`packageID` aliases + the `CUSTOM_BUILT` sentinel
  (no 404), merges `{...pkgData, ...booking}` with booking precedence, and
  catches Firestore errors → null (no crash).
- **Outfitter card resolver consistency** (Task 2.3): verified —
  `_buildHuntDatesBanner()` uses `resolveWindow(widget.data)` (line 873) and
  the "ADD HUNT TO CALENDAR" action calls `addToCalendar(...)` →
  `buildEventWithPackageFallback` → `resolveWindow` (the SAME resolver), so
  the banner dates always match the calendar event dates. No mismatch.

### Defect — Booking missing farm location → calendar event had no location (fixed)
- **Root cause**: the `packages` Firestore doc carries only `farmId` (NOT
  `farmName`/`district`/`province`) — `publishPackage` writes `farmId` only;
  the marketplace resolves the farm name via a runtime `farms`-join at read
  time and passes `farmName` to `_PackageCard` as a separate widget field.
  `bookPackage` copied `farmId` from the package doc but NOT the farm
  name/region → the booking doc had `farmId` but no `farmName`/`district`/
  `province`. Result: `BookingCalendarEventBuilder.buildTitle` had no "@
  Farm" suffix, `buildLocation` returned null, and `buildDescription`
  omitted the Farm/region lines — the device calendar event had no
  location. (Dates were fine; only the farm location was missing.)
- **Fix** (`package_booking_manager.dart` `bookPackage`): inside the booking
  transaction, resolve `farmName` + `district` + `province` from
  `farms/{farmId}` via `transaction.get(...)` and copy them onto the booking
  doc (best-effort — a missing/empty `farmId` or a missing farms doc simply
  omits the fields; the calendar falls back to the package name only). This
  makes the booking self-contained for the calendar exactly the way it's
  already self-contained for dates. A farm read failure never blocks the
  booking (try/catch → omit).
- **Parallel fix** (`farm_game_price_list_manager.dart`
  `submitCustomPackageBooking`): the custom-package booking path already
  accepted + wrote `farmName`, but did NOT resolve `district`/`province`.
  Added the same `farms/{farmId}` region resolution (best-effort) so the
  custom-built booking also carries a located calendar event
  (`buildLocation` → "Farm (district, province)"). Also backfills
  `farmName` + `packageName` from the farm doc when the caller omits
  `farmName` (defensive — the builder screen currently always passes it).
  Both booking-creation paths now produce self-contained, located booking
  docs.

### Tests
- `test/farm_game_price_list_stream_test.dart` +3 tests (all pass via
  `FakeFirebaseFirestore`): (1) district + province resolved from
  `farms/{farmId}` → `buildLocation` returns "Bosveld Ranch (Waterberg,
  Limpopo)"; (2) `farmName` + `packageName` backfilled from the farm doc
  when the caller omits `farmName`; (3) missing farm doc → region fields
  omitted gracefully (no crash, `farmName` retained). The calendar
  service's consumption of `farmName`/`district`/`province`
  (`buildTitle`/`buildLocation`/`buildDescription`) is already covered by
  the 44-test calendar suite.

### Verification
- `flutter analyze` (3 touched files: `package_booking_manager.dart`,
  `farm_game_price_list_manager.dart`,
  `farm_game_price_list_stream_test.dart`): only 2 pre-existing
  `no_leading_underscores_for_local_identifiers` infos in unchanged helper
  locals (lines 26/32, not in the edited code); the changed code is
  analyzer-clean. `analysis_options.yaml` + `pubspec.lock` auto-touched by
  `flutter pub get` were reverted before commit (documented baseline
  pattern).
- `flutter test test/farm_game_price_list_stream_test.dart
  test/booking_calendar_service_test.dart`: 58/58 pass.
- `flutter test` (full suite): **All 660 tests passed**, 0 failures (was
  657; +3 = the new farm-region enrichment tests). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side booking-doc enrichment; the `farms` read is already
  `isSignedIn()` per `firestore.rules`, and `bookPackage` runs server-side
  in a transaction with the caller authenticated).
- Files: `lib/features/hunter_mode/services/package_booking_manager.dart`
  (`bookPackage` farm-location resolution),
  `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`
  (`submitCustomPackageBooking` farm-region resolution + farmName backfill),
  `test/farm_game_price_list_stream_test.dart` (+3 tests +
  `booking_calendar_service` import), `AGENTS.md`.

## Definitive "No hunt dates on file" root-cause fix + exhaustive resolver aliases (added 2026-08-18)

### Root cause (definitive)
- The package creator's date picker (`outfitter_package_creator_screen.dart`)
  was **OPTIONAL**: `_publishPackage` validated title/description/price/
  quantity but NEVER validated that `_availabilityStart`/`_availabilityEnd`
  were non-null. An outfitter could publish a package without picking any
  dates → `PackagePricing.toMap()` wrote `availabilityStart: null` /
  `availabilityEnd: null` → `bookPackage`'s `if (availabilityStart != null)`
  guard skipped copying → the booking had ZERO date fields →
  `resolveWindow` returned null → "No hunt dates on file". The package
  fallback couldn't help because the package doc ITSELF had null dates.
  **The keys all matched; the issue was missing dates, not key mismatch.**

### Task 1 fix — require availability dates at publish/edit (definitive fix)
- `outfitter_package_creator_screen.dart` `_publishPackage`: added a
  hard validation gate requiring `_availabilityStart != null` (clear red
  snackbar: "Please select an availability Start Date -- the hunt window is
  required for booking + calendar."). `_availabilityEnd` defaults to the
  start (single-day hunt is valid) rather than blocking; an end-before-start
  is rejected. The downstream `PackagePricing(availabilityEnd: effectiveEnd)`
  now always carries a non-null end. This stops "No hunt dates on file" at
  the source — a newly published package ALWAYS carries a valid hunt window,
  so every booking derived from it carries one too.

### Task 2 fix — exhaustive resolver aliases + debug logging
- `booking_calendar_service.dart` `resolveWindow` refactored from a chained
  `??` cascade to a priority-ordered scan over two exhaustive alias lists:
  - `startAliases` (12): `confirmedStartDate`, `confirmed_start_date`,
    `checkInDate`, `check_in_date`, `availabilityStart`,
    `availability_start`, `startDate`, `start_date`, `huntStart`,
    `hunt_start`, `huntDate`, `hunt_date`.
  - `endAliases` (10): `confirmedEndDate`, `confirmed_end_date`,
    `checkOutDate`, `check_out_date`, `availabilityEnd`,
    `availability_end`, `endDate`, `end_date`, `huntEnd`, `hunt_end`.
  - Both the canonical camelCase keys the app writes AND snake_case
    variants are accepted so a legacy / third-party-written doc can never
    defeat resolution on a key-spelling mismatch. camelCase wins when both
    are present (canonical priority).
  - **Debug logging**: on success, logs the matched start/end keys + the
    resolved window; on failure (no start resolved), logs the scanned
    aliases, the raw booking keys, and the date-ish values found — so a
    "No hunt dates on file" can be diagnosed instantly from device logs.
  - `_dateishValues` helper surfaces exactly what date data IS present
    when the resolver fails (no silent null).
  - Behaviour preserved exactly for the canonical keys (existing 44 tests
    pass unchanged): priority order, single-day fallback, end-before-start
    clamp, Timestamp/ISO/DateTime/num parsing.

### Tests
- `test/booking_calendar_service_test.dart` +9 tests (all pass): snake_case
  `availability_start`/`availability_end`, `start_date`/`end_date`,
  `check_in_date`/`check_out_date`, `huntStart`/`huntEnd` (camelCase),
  `hunt_start`/`hunt_end` (snake_case), `confirmed_start_date`/
  `confirmed_end_date`; camelCase-wins-over-snake_case priority; the full
  start-alias priority sweep; single-day window when only a start resolves.

### Verification
- `flutter analyze` (3 touched files): only the 2 pre-existing
  `DropdownButtonFormField.value` deprecation infos in the creator (only
  on Flutter ≥3.33, NOT the CI 3.29.1 pin; project uses `value:` for
  cross-version compat); the changed code + the resolver + the test are
  analyzer-clean ("No issues found"). `analysis_options.yaml` +
  `pubspec.lock` auto-touched by `flutter pub get` were reverted before
  commit.
- `flutter test test/booking_calendar_service_test.dart`: 53/53 pass (was
  44; +9 alias/priority tests). Debug logging verified live in test output.
- `flutter test` (full suite): **All 669 tests passed**, 0 failures (was
  660; +9). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side validation gate + resolver refactor; the package doc's
  `availabilityStart`/`availabilityEnd` Timestamp serialization in
  `PackagePricing.toMap()` is unchanged).
- Files: `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`
  (required-dates validation gate + `effectiveEnd` default),
  `lib/features/hunter_mode/services/booking_calendar_service.dart`
  (`resolveWindow` exhaustive alias scan + debug logging +
  `_dateishValues` + `startAliases`/`endAliases` const lists),
  `test/booking_calendar_service_test.dart` (+9 tests), `AGENTS.md`.

## Firebase Storage rules audit & [firebase_storage/unauthorized] fix (added 2026-08-18)

Audited `storage.rules` against every Storage upload path the code writes
to prevent `[firebase_storage/unauthorized]` errors.

### Audit findings (complete upload-path inventory)
Enumerated every `FirebaseStorage.ref().child(...)` / `.ref(...)` write in
`lib/` and mapped each against the rules:
- `users/{uid}/profile.jpg` (hunter_profile_screen) — owner-scoped.
- `trophy_photos/{uid}/{ts}.jpg` (add_trophy / edit_trophy) — owner-scoped.
- `trophy_photos/{outfitterId}/{ts}.jpg` (outfitter_trophy_stock) — owner-
  scoped (outfitterId IS the caller's own uid).
- `package_images/{outfitterId}/{ts}.jpg` (package_creator) — owner-scoped.
- `bug_report_attachments/{userId}/{ts}.jpg` (bug_report_modal) — owner-scoped.
- `firearm_photos/{uid}/{docId}_{ts}.jpg` (firearm_detail) — owner-scoped.
- `permit_signatures/{permitId}/{role}_signature.png` (venison_permit_manager)
  — authenticated write (permitId is a doc id, not a uid; either party may
  upload).
- `hunters/{hunterId}/{ts}.jpg` (image_utils `uploadHunterImage`) — legacy
  helper with zero live callers (dead code); owner-scoped rule retained.
- **No chat-attachment upload to Storage exists** — the chat service
  (`chat_and_filter_service.dart`) + `BookingChatThread` have no image upload
  (confirmed via grep). The template's `chat_attachments/` path is unused.
- **No `trophies/` or `packages/` Storage writes exist** — trophy photos go
  to `trophy_photos/`, package gallery images go to `package_images/`. The
  template's `trophies/` + `packages/` paths are unused (retained as
  defensive aliases).

### Conclusion: the committed rules already covered every real upload path
The most likely real-world cause of `[firebase_storage/unauthorized]` is
that the rules had not been DEPLOYED (AGENTS.md documents that
`firebase deploy` cannot run in this sandbox — no `FIREBASE_TOKEN`; the
deployed project may still carry default-deny storage rules).

### Hardening applied
Rewrote `storage.rules` for clarity + explicit per-collection contracts
while preserving the least-privilege owner-scoped write posture:
- **Reads**: global authenticated read (`match /{allPaths=**} allow read:
  if request.auth != null`) retained; `chat_attachments/{uid}` gained an
  explicit read grant so the contract survives a future tightening of the
  catch-all.
- **Writes**: every collection scoped to `request.auth.uid == uid` (the
  second path segment is the authenticated caller's own uid) — prevents a
  hunter from overwriting another hunter's uploads while admitting every
  legitimate upload path. Switched `{fileName}` -> `{allPaths=**}` so
  nested files under an owner folder are admitted (future-proofs sub-path
  layouts).
- Added the template's requested named collections (`chat_attachments`,
  `packages`) with owner-scoped writes (defensive — no live writer today;
  if a future in-chat image upload or package-image alias is added, it works
  without a rules redeploy).
- **Security: deliberately did NOT adopt the over-broad
  `allow write: if request.auth != null` fallback** from the suggested
  template — it would let any signed-in user write to any path (cross-user
  tampering, arbitrary file upload). The owner-scoped grants are the
  least-privilege posture that still prevents `[firebase_storage/unauthorized]`
  on every real upload path. Documented this choice inline in the rules.
- `permit_signatures/{permitId}`: authenticated write (permitId is a doc id,
  not a uid, so owner-scoping is not applicable — either party uploads).

### Verification
- Structural validation: brace balance 0, paren balance 0, 11 named
  collections + global read all covered, no over-broad authenticated-write
  fallback.
- `flutter analyze` (`lib/`): 96 pre-existing infos (unchanged baseline;
  the rules edit touches no Dart).
- `flutter test` (full suite): **All 669 tests passed**, 0 failures (no
  regressions; pure config change).
- `analysis_options.yaml` + `pubspec.lock` auto-touched by `flutter pub get`
  were reverted before commit.

### Deploy reminder
`npx firebase-tools deploy --only storage` CANNOT run in this sandbox (no
`FIREBASE_TOKEN` / `firebase login`; verified — `firebase projects:list`
errors with an auth failure, matching the AGENTS.md environment-constraints
note). The ruleset is committed + pushed; the deploy MUST be run in a
credentialed environment: `npx firebase-tools deploy --only storage`.
Until deployed the deployed project may still carry default-deny storage
rules, which is the actual source of `[firebase_storage/unauthorized]`.
- Files: `storage.rules` (rewritten — global authenticated read + 11
  owner-scoped write collections + inline security rationale), `AGENTS.md`.

## Standardized date-range badge formatting on UI cards (added 2026-08-18)

Unified every package-availability + hunt-date range badge across Hunter +
Outfitter screens on a single `d MMM yyyy – d MMM yyyy` format (e.g.
`21 Aug 2026 – 23 Aug 2026`), eliminating the clipped/ambiguous numeric
shorthand that omitted the month on the start date.

### Root cause (the clipping bug)
The package card meta chip + the booking confirmation sheet availability
summary rendered the range as a raw numeric shorthand:
`'${start.day}/${start.month} – ${end.day}/${end.month}/${end.year}'` ->
`21/8 – 23/8/2026`. The START omitted the year + used bare numeric
month/day, so a range sharing a month read as clipped/ambiguous (and the
numeric `8` vs `Aug` was locale-unstable). The hunter + outfitter booking
banners already used `DateFormat('d MMM yyyy')` (clean) but joined with an
` → ` arrow — inconsistent with the cards' `–` and with each other.

### Single source of truth
Added three static formatters to `BookingCalendarEventBuilder`
(`booking_calendar_service.dart`) — colocated with the date resolver so the
resolver + formatter live together:
- `formatDate(DateTime)` -> `d MMM yyyy` (e.g. `21 Aug 2026`).
- `formatWindow(({start, end})?)` -> resolves a `resolveWindow` result to a
  label: `null` when no window; one date for a single-day hunt
  (`window.end` is calendar-exclusive, so it subtracts 1 day + collapses
  same-day to one date); `start – end` (en-dash) for a multi-day hunt.
- `formatDateRange({start, end})` -> null-safe range from two raw
  `DateTime?`s (for package-availability badges that don't run through
  `resolveWindow`): null when start null; one date when end null /
  end<=start / start==end; `start – end` otherwise.
All three ALWAYS carry the full month + year on BOTH ends — a range sharing
a month/year is never clipped. Uses `intl` `DateFormat` (locale-stable
month abbreviations). Single en-dash `–` separator everywhere.

### Sites standardized (5 total)
1. **Package card meta chip** (`hunter_package_marketplace_screen.dart`
   line 612): the buggy `21/8 – 23/8/2026` shorthand -> `formatDateRange`.
2. **Booking confirmation sheet availability summary** (line 1054): the
   buggy `Available 21/8 – 23/8/2026` shorthand -> `formatDateRange`.
3. **Hunter booking card hunt-dates banner** (line 1605): inline
   `DateFormat('d MMM yyyy')` + `→` arrow -> `formatWindow` (en-dash).
4. **Outfitter booking card hunt-dates banner**
   (`outfitter_booking_dashboard_screen.dart` line 882): inline
   `DateFormat('d MMM yyyy')` + `→` arrow -> `formatWindow` (en-dash).
5. **Date-change request single-date chip** (line 2055): `d/M/yyyy`
   numeric -> `formatDate`.
The now-unused `import 'package:intl/intl.dart'` was removed from both
screens (the inline `DateFormat` calls are gone; the shared helper owns
the `intl` dependency). Both screens already imported
`booking_calendar_service.dart` (no new import needed).

### Tests
`test/booking_calendar_service_test.dart` +11 tests (all pass): `formatDate`
(d MMM yyyy, single-digit day, month always present); `formatWindow` (null
window, single-day collapse, multi-day `start – end`, shared-month no-clip,
month-boundary cross); `formatDateRange` (null start, null end, start==end,
range, end-before-start clamp).

### Verification
- `flutter analyze` (4 touched files: `booking_calendar_service.dart`,
  `hunter_package_marketplace_screen.dart`,
  `outfitter_booking_dashboard_screen.dart`,
  `booking_calendar_service_test.dart`): **No issues found** (0 errors, 0
  warnings, 0 infos — the unused `intl` imports were removed so no
  `unused_import` warning). `analysis_options.yaml` + `pubspec.lock`
  auto-touched by `flutter pub get` were reverted before commit.
- `flutter test test/booking_calendar_service_test.dart`: 64/64 pass (was
  53; +11 formatter tests).
- `flutter test` (full suite): **All 680 tests passed**, 0 failures (was
  669; +11). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side UI formatting consolidation; `intl` was already a dependency).
- Files: `lib/features/hunter_mode/services/booking_calendar_service.dart`
  (`formatDate` + `formatWindow` + `formatDateRange` + `_dateFormatter` +
  `intl` import),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (3 sites routed through the helper + `intl` import removed),
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`
  (1 site routed + `intl` import removed),
  `test/booking_calendar_service_test.dart` (+11 tests), `AGENTS.md`.

## Hardened Firestore model date parsing — parseFirestoreDate (added 2026-08-18)

Audited + hardened all Firestore model deserialization for the four
package/booking date fields (`availabilityStart`, `availabilityEnd`,
`startDate`, `endDate`) plus the date-change-request dates, so they are
safely converted whether they arrive as a Firestore `Timestamp`, an ISO
`String`, a `DateTime`, or a `num` (milliseconds-since-epoch).

### Audit findings
- `PackagePricing.fromMap` already had a private `static _toDate(dynamic)`
  helper that handled Timestamp/DateTime/String (the robust pattern the
  task wants) but it was private.
- `DateChangeRequest.fromMap` already routed through `PackagePricing._toDate`
  (robust).
- **`OutfitterPackageCreatorScreen._prefillForEdit`** (the edit-mode
  prefill) was the ONLY un-hardened site: it read
  `pkg['availabilityStart']` / `pkg['availabilityEnd']` and only handled
  `if (start is Timestamp) start.toDate()`. A value arriving as an ISO
  `String` (legacy/migrated doc) or a `DateTime` (in-memory / fake
  round-trip) was silently dropped -> the edit form showed empty date
  chips -> the required-dates validation gate (added in the prior phase)
  would block the save until the outfitter re-picked the dates. Real
  regression risk on a legacy doc.
- `package_booking_manager.bookPackage` passes the raw `pkgData` date
  values through verbatim to the booking doc (`startDate`/`endDate`/
  `availabilityStart`/`availabilityEnd` = copied directly, no cast) --
  correct; the values keep their Timestamp type + server precision, and the
  consumers (`resolveWindow`/`parseFirestoreDate`) handle all shapes. No
  change needed.

### Single source of truth -- parseFirestoreDate
Promoted the private `PackagePricing._toDate` to a public top-level
`parseFirestoreDate(dynamic)` helper in `package_pricing.dart`:
- `null` -> `null`.
- `Timestamp` -> `.toDate()`.
- `DateTime` -> passed through unchanged.
- `String` -> `DateTime.tryParse` (returns `null` for an unparseable
  string, so a malformed date never throws).
- `num` -> `DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)` (a
  3rd-party / legacy int representation; the calendar service's
  `resolveDate` already handled this shape; the model parser now matches).
- any other type -> `null`.
This is the exact contract the task specified, plus the `num` shape the
codebase already supported elsewhere. The caller (a `fromMap` /
`fromFirestore` / edit-mode prefill) never throws on a missing or malformed
date field.

### Sites routed through the shared helper
- `PackagePricing.fromMap`: `availabilityStart` / `availabilityEnd` ->
  `parseFirestoreDate`.
- `DateChangeRequest.fromMap`: `requestedStartDate` / `requestedEndDate` /
  `requestedAt` / `resolvedAt` -> `parseFirestoreDate` (was routed through
  the now-removed `_toDate`; behavior identical, now uses the public name).
- `OutfitterPackageCreatorScreen._prefillForEdit` (the previously
  un-hardened site): replaced the `if (start is Timestamp)`-only check with
  `parseFirestoreDate(start)` / `parseFirestoreDate(end)` so the edit form
  pre-fills the saved dates from ANY shape (Timestamp / DateTime / ISO
  string) instead of silently dropping non-Timestamp shapes.
- The calendar service's `resolveDate` is UNCHANGED -- it has a separate
  concern (collapsing to midnight local for all-day events) and already
  handles all four shapes; routing it through `parseFirestoreDate` would
  lose the midnight-collapse, so the two remain separate (both robust).

### Tests
`test/parse_firestore_date_test.dart` (NEW, 22 tests, all pass):
- `parseFirestoreDate`: null; Firestore Timestamp; DateTime pass-through;
  ISO string; unparseable string -> null; empty string -> null; num
  (ms-since-epoch, UTC); double num (truncated); unsupported type (List)
  -> null; bool -> null.
- `PackagePricing.fromMap` round-trip: Timestamp; ISO string; DateTime;
  null start (single-side); null end; both null; malformed string does not
  throw.
- `DateChangeRequest.fromMap` round-trip: Timestamp; ISO string; null
  dates; default status; malformed string does not throw.

### Verification
- `flutter analyze` (3 touched files: `package_pricing.dart`,
  `outfitter_package_creator_screen.dart`,
  `parse_firestore_date_test.dart`): only the 2 pre-existing
  `DropdownButtonFormField.value` deprecation infos (unchanged baseline;
  not introduced by this change). No new issues. `analysis_options.yaml` +
  `pubspec.lock` auto-touched by `flutter pub get` reverted before commit.
- `flutter test test/parse_firestore_date_test.dart`: 22/22 pass.
- `flutter test` (full suite): **All 702 tests passed**, 0 failures (was
  680; +22 new). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side model-deserialization hardening + tests).
- Files: `lib/features/hunter_mode/models/package_pricing.dart`
  (`_toDate` -> public `parseFirestoreDate` + `num` branch + docstring;
  `PackagePricing.fromMap` + `DateChangeRequest.fromMap` routed through
  it),
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`
  (edit prefill hardened),
  `test/parse_firestore_date_test.dart` (NEW, 22 tests), `AGENTS.md`.

## Universal dual-key date synchronization on bookings + packages (added 2026-08-18)

Guarantees that the hunt-window date keys `availabilityStart`/
`availabilityEnd` and `startDate`/`endDate` are always written + read
interchangeably across every booking + package flow, so no downstream
screen / widget / calendar resolver can ever miss the hunt window purely on
a key-spelling mismatch.

### Point 1 — `resolveWindow` dual-key contract (verified + documented)
- `BookingCalendarEventBuilder.resolveWindow`
  (`lib/features/hunter_mode/services/booking_calendar_service.dart`)
  already scanned the exhaustive `startAliases` / `endAliases` lists
  (which include `availabilityStart`, `startDate`, `checkInDate`,
  `huntStart`, `huntDate` + their snake_case variants + the `end`
  counterparts) in priority order, treating any matching key as the
  start/end interchangeably. So a booking with `availabilityStart` uses it
  as the start; a booking with `startDate` treats it identically. No
  logic change was needed; a **dual-key guarantee docstring** was added to
  `resolveWindow` making the interchangeability contract explicit (it
  documents that bookings carry BOTH key sets — written by the Point-2
  change below — and packages carry `availabilityStart`/`availabilityEnd`
  from `PackagePricing.toMap`, so the resolver finds the window under
  whichever alias is present).

### Point 2 — `bookPackage` dual-key resolution + write
  (`lib/features/hunter_mode/services/package_booking_manager.dart`)
- The package's hunt window is now resolved with a **dual-key fallback**:
  `availabilityStart = pkgData['availabilityStart'] ?? pkgData['startDate']`
  (mirrored for `availabilityEnd`/`endDate`). Previously `bookPackage` read
  ONLY `pkgData['availabilityStart']`/`pkgData['availabilityEnd']` — so a
  package that stored its window under `startDate`/`endDate` (a legacy /
  third-party alias) resolved to null and NO date keys were written to the
  booking. Now a package with either key set produces a dated booking.
- The booking doc now carries **BOTH key sets** explicitly:
  `startDate`, `endDate`, `availabilityStart`, `availabilityEnd` (each
  guarded `if (... != null)` so a no-date package writes none). The
  resolved `availabilityStart`/`availabilityEnd` locals carry the
  dual-key fallback, so when the package stored its window under
  `startDate`/`endDate` only, the booking still ends up with both sets
  populated from the single source value. A downstream consumer reading
  either key always finds a value.

### Point 3 — `submitCustomPackageBooking` dual-key parity
  (`lib/features/hunter_mode/services/farm_game_price_list_manager.dart`)
- The custom-package booking path previously wrote only `checkInDate`/
  `checkOutDate`. It now ALSO mirrors them onto `startDate`/`endDate`
  AND `availabilityStart`/`availabilityEnd`, matching the dual-key
  guarantee `bookPackage` writes for marketplace bookings. So the custom-
  built booking is self-contained for the calendar resolver (which scans
  all alias families) and for any UI card reading either key.

### Tests
- `test/package_quantity_test.dart` +4 structural tests (in the
  `bookPackage transaction logic` group) encoding the dual-key resolution
  + write contract: package with `availabilityStart` populates both sets;
  package with only `startDate`/`endDate` falls back + writes both sets;
  `availabilityStart` wins over `startDate` when both present; a no-date
  package writes no date keys (the calendar fallback then consults the
  package doc).
- `test/farm_game_price_list_stream_test.dart`: the existing
  `submitCustomPackageBooking` test gained assertions that all four date
  aliases (`startDate`/`endDate`/`availabilityStart`/`availabilityEnd`)
  are populated; +1 new test verifying `BookingCalendarEventBuilder
  .resolveWindow` resolves the hunt window from a custom-package booking's
  dual-key payload (start + calendar-exclusive end).
- The existing 53-test `booking_calendar_service_test` suite (incl. the
  alias priority sweep + camelCase-wins-over-snake_case) still passes.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin) on the 5 touched files:
  **0 errors, 0 warnings** (only 2 pre-existing `info`s in unchanged
  helper locals `_service`/`_seedSpecies` at
  `test/farm_game_price_list_stream_test.dart:26/32`, not in edited code).
- `flutter test` (full suite): **All 707 tests passed**, 0 failures
  (was 702; +5 new). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side booking-doc enrichment + resolver documentation + tests).
- Commit `3d53aae` pushed to `origin/main` (`d3cd0f8..3d53aae`); local +
  origin in sync, working tree clean.
- Files: `lib/features/hunter_mode/services/booking_calendar_service.dart`
  (`resolveWindow` dual-key docstring),
  `lib/features/hunter_mode/services/package_booking_manager.dart`
  (`bookPackage` dual-key resolution + both-set write),
  `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`
  (`submitCustomPackageBooking` dual-key mirror),
  `test/package_quantity_test.dart` (+4 dual-key tests),
  `test/farm_game_price_list_stream_test.dart` (+1 test + assertions),
  `AGENTS.md`.


## Chat keyboard kick-out fix + "Add to Calendar" post-success button state (added 2026-08-18)

Two-part UX fix: (1) the chat composer on the hunter + outfitter booking
cards (and the reusable `BookingChatThread` in the Custom Package Builder
confirmation view) dropped keyboard focus / collapsed when the software
keyboard opened; (2) the "ADD HUNT TO CALENDAR" button gave no persistent
success state after a successful add.

### Task 1 — Chat keyboard kick-out fix
- Root cause: the chat composer `TextField` had no retained `FocusNode` and
  no stable `ValueKey`. When the Scaffold resized for the software keyboard
  (`resizeToAvoidBottomInset` default true), the booking-card ListView
  reflowed and the composer element could lose focus / unmount, collapsing
  the open chat drawer ("kick-out").
- Fix applied across the three chat surfaces:
  - **`BookingChatThread`** (`lib/features/hunter_mode/widgets/booking_chat_thread.dart`):
    added a retained `FocusNode _chatFocusNode` (disposed in `dispose`),
    bound to the composer `TextField` with a stable
    `key: ValueKey('bookingChatComposer')` + `scrollPadding:
    EdgeInsets.only(bottom: 80)` so the keyboard never hides the field.
  - **`_HunterBookingCard`** (marketplace
    `hunter_package_marketplace_screen.dart`): added
    `FocusNode _chatFocusNode` + `dispose` wiring; the inline
    `_buildChatDrawer` composer `TextField` now carries
    `key: ValueKey('hunterChatComposer')` + `focusNode: _chatFocusNode` +
    `scrollPadding`.
  - **`_BookingCard`** (outfitter `outfitter_booking_dashboard_screen.dart`):
    same — `FocusNode _chatFocusNode` + dispose + `key:
    ValueKey('outfitterChatComposer')` + `scrollPadding` on the inline chat
    drawer composer. (The card State previously had NO `dispose`, so the
    `TextEditingController` + `ScrollController` were leaking; the new
    `dispose` fixes that leak too.)
- The three top-level Scaffolds (marketplace, outfitter dashboard, custom
  package builder) now declare `resizeToAvoidBottomInset: true` explicitly
  (was implicit/default) to document the intent that the body resizes for
  the keyboard so the composer lifts smoothly instead of unmounting.

### Task 2 — "Add to Calendar" post-success button state
- The booking doc now carries an `addedToCalendar: true` flag persisted on a
  successful calendar add, and the button flips to a muted "✓ ADDED TO
  CALENDAR" state (grey background, `check_circle_rounded` icon, disabled
  `onPressed`) so the user sees a persistent success state and cannot
  re-trigger the calendar insertion for the same booking.
- **`_HunterBookingCard`** + **`_BookingCard`**:
  - New local `bool _addedToCalendar` field, seeded from
    `widget.data['addedToCalendar']` on the first `build` (write-once guard
    so a stale stream re-emit never clears a freshly-added state) + kept in
    sync via `didUpdateWidget` (so a doc that already carries the flag
    renders added on mount, and a stream re-emit after the outfitter /
    hunter persists the flag is reflected).
  - `_addToCalendar` now, on `launched == true`, `setState(() =>
    _addedToCalendar = true)` AND best-effort `Firestore.update(
    {'addedToCalendar': true})` on `bookings/{bookingId}` (a Firestore
    write failure is swallowed via `debugPrint`; the local flag still flips
    so the UX is correct for the session).
  - Button UI: `onPressed: _addedToCalendar ? null : _addToCalendar`;
    `backgroundColor: _addedToCalendar ? Colors.grey : Colors.green.shade700`;
    `disabledBackgroundColor: Colors.grey`; icon flips to
    `check_circle_rounded`; label flips to "✓ ADDED TO CALENDAR".
- **Custom Package Builder confirmation view** (`hunter_custom_package_builder_screen.dart`):
  - `_addToCalendar` now persists `addedToCalendar: true` to the booking
    doc on `launched == true`. The booking-doc stream subscription
    (`_bookingSub`) re-emits + `setState`s, so the confirmation view
    re-renders with the added state reactively (no local flag needed here —
    the stream is the source of truth).
  - The confirmation view derives `addedToCalendar = _bookingDoc?['addedToCalendar'] == true`
    and applies the same button state flip (grey / check / disabled / "✓
    ADDED TO CALENDAR").

### Verification
- `flutter analyze` (4 touched files: `booking_chat_thread.dart`,
  `hunter_package_marketplace_screen.dart`,
  `outfitter_booking_dashboard_screen.dart`,
  `hunter_custom_package_builder_screen.dart`): **No issues found** (0
  errors, 0 warnings, 0 infos introduced; project baseline unchanged). The
  `analysis_options.yaml` auto-touched by the analyzer was reverted before
  commit.
- `flutter test` (full suite): **All 707 tests passed**, zero failures. No
  regressions (the calendar-service suite still covers the event-build
  contract; the new local-flag persistence is a UI-state concern exercised
  by the existing builder widget tests + the calendar-service package-
  fallback suite).
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side UI state + a best-effort `bookings` field write; the existing
  `bookings` rule already permits the booking parties to update non-status
  fields, and `addedToCalendar` is a non-status field so the
  `request.resource.data.status == resource.data.status` guard admits it).
- Files: `lib/features/hunter_mode/widgets/booking_chat_thread.dart`
  (FocusNode + key + scrollPadding + dispose),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (Scaffold resize flag + FocusNode + key + scrollPadding + dispose +
  `_addedToCalendar` + didUpdateWidget + persist + button state),
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`
  (same set),
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (Scaffold resize flag + persist + reactive added-state button),
  `AGENTS.md`.


## Isolate chat composer into dedicated StatefulWidget (added 2026-08-18)

Hardened the chat-input keyboard-kick-out fix by extracting the composer
bar into its own dedicated `StatefulWidget`, so the `TextEditingController`
+ `FocusNode` + send-in-flight state live in an isolated element subtree
that is NEVER torn down by the message list's Firestore stream rebuilds or
the keyboard's `resizeToAvoidBottomInset` rebuilds. This is the robust
form of the prior `ValueKey` + retained-`FocusNode` patch — the composer's
state is now fully decoupled from the message list.

### New `ChatComposerBar` widget
(`lib/features/hunter_mode/widgets/chat_composer_bar.dart`, NEW)
- Dedicated `StatefulWidget` that owns its own `TextEditingController` +
  `FocusNode` + `_isSending` flag, created ONCE in the State and disposed
  in `dispose` — never recreated across parent rebuilds.
- API: `bookingId`, `theme` (`ThemeController`), `senderName`, and an
  optional `onMessageSent` callback. The bar handles the full send
  lifecycle (validation, `ChatAndFilterService.sendChatMessage`, the
  in-flight spinner, the success/error snackbar) so the parent no longer
  needs any composer/controller/send logic.
- `onMessageSent` is invoked after a successful send so the parent can
  scroll its message list to the bottom — the composer intentionally does
  NOT own a `ScrollController` so the message-list scroll state stays with
  the list widget (the parent).
- The `TextField` keeps a stable `ValueKey('chatComposerBar')` + the
  retained `FocusNode` + `scrollPadding: EdgeInsets.only(bottom: 80)` as
  defense-in-depth on top of the isolated State.
- `ScaffoldMessenger.maybeOf(context)` is captured before the async gap so
  the error snackbar still fires if the bar unmounts while the send is in
  flight; `mounted` is guarded throughout.

### Refactored consumers (3 chat surfaces)
All three chat surfaces now render the shared `ChatComposerBar` instead of
an inline composer `Row`, and their card/thread States no longer hold a
`TextEditingController` / `FocusNode` / `_isSending` flag / `_sendMessage`
method — they keep ONLY the message-list `ScrollController` and a
`_scrollChatToBottom` helper wired to the composer's `onMessageSent`.

- **`BookingChatThread`** (`lib/features/hunter_mode/widgets/booking_chat_thread.dart`):
  removed `_chatController` / `_chatFocusNode` / `_isSending` /
  `_sendMessage`; kept only `_chatScrollController` + `_scrollToBottom`. The
  `chat_and_filter_service` import was dropped (no longer used here; the
  composer owns the send call).
- **`_HunterBookingCard`** (marketplace
  `hunter_package_marketplace_screen.dart`): removed `_chatController` /
  `_chatFocusNode` / `_sendChatMessage`; kept only `_chatScrollController`
  + added `_scrollChatToBottom`. The `chat_and_filter_service` import was
  dropped (no longer used here).
- **`_BookingCard`** (outfitter `outfitter_booking_dashboard_screen.dart`):
  same removal; kept only `_chatScrollController` + added
  `_scrollChatToBottom`. The `chat_and_filter_service` import was dropped.
- Both screens gained the `chat_composer_bar.dart` import.

### Tests
- `test/chat_composer_bar_test.dart` (NEW, 3 widget tests, all pass):
  - renders the text input + a send button that is enabled when idle
    (the empty-input guard is handled inside `_sendMessage`, which no-ops
    on empty text);
  - **the `TextEditingController` persists across a parent rebuild** — the
    core isolation contract: types "hello bushveld" into the composer,
    forces a parent `_RebuildProbe` rebuild, and asserts the SAME
    `TextEditingController` instance (same identity) + its text content
    survive the rebuild (no controller recreation / no focus drop);
  - shows the send icon when idle (no in-flight spinner).
- The send path itself (which calls `ChatAndFilterService` -> Firestore) is
  not exercised here, so no Firebase app is required; the tests are
  unit-isolated.

### Verification
- `flutter analyze` (4 changed lib files + the new widget + the new test):
  **No issues found** (0 errors, 0 warnings, 0 infos introduced; the two
  now-unused `chat_and_filter_service` imports were removed so no
  `unused_import` warning). `analysis_options.yaml` auto-touched by the
  analyzer was reverted before commit.
- `flutter test` (full suite): **All 710 tests passed**, zero failures
  (was 707; +3 = the new composer-isolation tests). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side widget extraction + tests).
- Files: `lib/features/hunter_mode/widgets/chat_composer_bar.dart` (NEW),
  `lib/features/hunter_mode/widgets/booking_chat_thread.dart` (refactored),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (refactored + import drop),
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`
  (refactored + import drop),
  `test/chat_composer_bar_test.dart` (NEW, 3 tests), `AGENTS.md`.


## ChatComposerBar keyboard-focus / IMM binding fix (added 2026-08-18)

Fixed the "ssi() view is not EditText" / immediate-keyboard-hide defect on
the outfitter booking dashboard chat (and every other `BookingChatThread` /
`ChatComposerBar` consumer -- the hunter marketplace card + the Custom
Package Builder confirmation view).

### Root cause
- `ChatComposerBar.build` wrapped its entire `Row` (including the
  `TextField`) in a `GestureDetector` with `onTap:
  _focusNode.requestFocus()` + `behavior: HitTestBehavior.opaque`. The
  intent was to explicitly request focus on tap to satisfy the platform
  input-manager view-target validation.
- The defect: in Flutter's gesture arena, a `TextField` (via
  `EditableText`) registers its own `TapGestureRecognizer`, and a parent
  `GestureDetector` registers another. Recognizers register inside-out
  (children first), and in a DEFAULT arena the LAST-registered (parent)
  recognizer wins. So the wrapper's tap recognizer won the arena and the
  `EditableText`'s internal tap handler never fired.
- Net effect: `_focusNode.requestFocus()` WAS called (focus briefly gained),
  but the `EditableText` never ran its internal tap logic, so the platform
  InputMethodManager (IMM) never bound to the EditText view. On Android the
  IMM logs "ssi() view is not EditText" and immediately hides the keyboard;
  on iOS the field fails to become first responder. The user could not type.

### Fix (`lib/features/hunter_mode/widgets/chat_composer_bar.dart`)
- Removed the wrapping `GestureDetector` (and its `HitTestBehavior.opaque`).
  The composer's `build` now returns the `Row` directly so the `TextField`
  is exposed with no competing tap recognizer.
- Moved the explicit focus request onto the `TextField`'s own `onTap`
  callback (`onTap: () => _focusNode.requestFocus()`). `TextField.onTap` is
  invoked as part of `EditableText`'s INTERNAL tap handling (not as a
  separate gesture recognizer), so it does NOT compete in the arena -- the
  `EditableText` runs its full tap logic (cursor placement + IMM binding)
  AND the explicit `requestFocus()` fires, so the keyboard binds correctly
  and stays open while typing.
- `onTapOutside: (_) => _focusNode.unfocus()` retained (graceful focus
  release on a tap outside the field).
- The stable `ValueKey('chatComposerBar')` + retained `FocusNode` +
  `TextEditingController` (created once in the isolated State, disposed in
  `dispose`) are unchanged -- the composer-state-isolation contract from
  the prior phase is preserved.

### Outfitter dashboard integration (verified, no change needed)
- `_BookingCard` delegates the chat UI to the shared `BookingChatThread`
  widget via a `GlobalKey<BookingChatThreadState>` (`_chatThreadKey`); the
  external affordances (the unread-mail indicator + the "CHAT" action
  button) call `_chatThreadKey.currentState?.toggleExpanded()`. The thread
  owns its own `_isExpanded` + `_chatScrollController`; the `ChatComposerBar`
  is rendered as a child of the thread's expanded `Column`. This wiring is
  structurally identical to the hunter side (which uses an inline
  `_buildChatDrawer` + `_isChatExpanded`) and to the Custom Package Builder
  confirmation view -- all three consume the SAME `ChatComposerBar`, so the
  fix applies uniformly.
- The outfitter card's gesture detectors (`InkWell` on the custom-items
  expandable header + the unread-mail indicator) and the outer
  `ListView.builder` do NOT sit between the `ChatComposerBar`'s `TextField`
  and its focus target, so they cannot steal pointer events or focus. The
  `ListView` uses the default `HitTestBehavior` (translucent) and does not
  register a `TapGestureRecognizer`, so taps on the composer pass through
  to the `TextField` unimpeded.
- `Scaffold.resizeToAvoidBottomInset: true` is already declared on the
  outfitter dashboard `Scaffold` (line 78) so the body resizes for the
  keyboard and the composer lifts smoothly instead of unmounting.

### Tests (`test/chat_composer_bar_test.dart`, +2 tests, all pass)
- **"the composer is NOT wrapped in a GestureDetector that would steal the
  tap from the TextField"** -- the regression guard for the root cause:
  uses `find.ancestor(of: TextField, matching: GestureDetector)` to assert
  NO `GestureDetector` sits between the `TextField` and the composer's root
  `Row`. If a future change re-introduces an opaque wrapper, this test
  fails with the exact rationale.
- **"tapping the TextField requests focus on the retained FocusNode"** --
  taps the `TextField` and asserts `focusNode.hasFocus` becomes true,
  proving the `TextField`'s own `onTap` requests focus without arena
  contention (the keyboard binds + stays open).
- The existing 3 tests (input + send button present; controller persists
  across a parent rebuild; send icon when idle) still pass.

### Verification
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings**, 278 infos
  (all pre-existing `avoid_print` / `deprecated_member_use` / style hints
  in unrelated files; the changed files are analyzer-clean -- "No issues
  found").
- `flutter test` (full suite): **All 652 tests passed**, zero failures
  (was 650; +2 = the new composer-focus tests). No regressions.
- Environment note: installed Flutter 3.29.1 stable (CI pin) + `unzip` +
  `libsqlite3-dev` (the SDK + system deps had been removed since the prior
  session).
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side widget fix + tests).
- Files: `lib/features/hunter_mode/widgets/chat_composer_bar.dart`
  (removed wrapping `GestureDetector` + moved focus request to
  `TextField.onTap`), `test/chat_composer_bar_test.dart` (+2 tests),
  `AGENTS.md`.


## Package Details -- outfitter / farm manager contact card (added 2026-08-18)

Added a "CONTACT THE OUTFITTER" card to the Package Details bottom sheet
(`_BookingConfirmationSheet` in `hunter_package_marketplace_screen.dart`) so a
hunter can reach the outfitter / farm manager directly from the package
marketplace -- name, tappable phone (tel: intent), and tappable email
(mailto: intent) -- with graceful loading + fallback states.

### New service: `OutfitterContactResolver`
(`lib/features/hunter_mode/services/outfitter_contact_resolver.dart`)
- `OutfitterContactResolver.instance` (singleton, lazy Firestore getter so
  constructing it before `Firebase.initializeApp()` does not throw
  `[core/no-app]`). `resolve(packageData)` fetches:
  1. **Outfitter profile** from `outfitters/{outfitterId}` -- resolves
     `displayName` (with `businessName` / `name` aliases), `email`, and
     `phoneNumber` (with `phone` / `cellNumber` aliases).
  2. **Farm manager** (when the package carries a `farmId`) from
     `farm_managers` `.where('farmId').limit(1)` -- resolves `managerName`
     (with `name` alias), `managerEmail` (with `email` alias), and
     `managerCell` (with `cellNr` / `phone` aliases).
- Both fetches are best-effort: a missing doc, a missing field, or a Firestore
  error (offline / permissions / `[core/no-app]`) is caught and yields a
  partially-populated `OutfitterContact` (empty strings) so the UI renders
  graceful fallbacks instead of crashing.
- `OutfitterContact` model: immutable snapshot with `has*` getters +
  `primaryContactName` / `primaryPhone` / `primaryEmail` / `primaryContactRole`
  (the farm manager takes precedence as the primary contact when one is
  assigned; otherwise the outfitter is the primary).
- `@visibleForTesting forTesting(FirebaseFirestore)` injection seam so the
  resolver can be exercised against `FakeFirebaseFirestore` (mirrors the
  `OpticLogService.forTesting` / `FeedbackFirebaseService` pattern).
- Firestore rules: `outfitters` + `farm_managers` both allow
  `read: if isSignedIn()` (verified), so a signed-in hunter can read them.
  No rules / index change required (the `farm_managers` `.where('farmId')`
  equality query uses the automatic single-field index).

### Package Details card (`_BookingConfirmationSheet`)
- New `_buildContactCard()` rendered between the Price Breakdown and the
  warning banner. Three render states:
  - **Loading** (`_isContactLoading`): a compact spinner + "Loading contact
    details..." row.
  - **No contacts** (`!hasAnyContact`): a graceful "Contact details are not
    available for this package yet. Submit a booking request and use the
    in-app chat to reach the outfitter." fallback (older records / missing
    docs).
  - **Contacts resolved**: the primary contact name + role label
    ("Farm Manager" / "Outfitter"), a tappable phone row (`tel:` intent via
    `url_launcher.launchUrl`), and a tappable email row (`mailto:` intent).
    Each row is an `InkWell` with an open-in-new icon; a failed launch
    surfaces an orange/red snackbar (messenger captured pre-async-gap).
- `_resolveContact()` runs in `initState` (best-effort, try/catch -> empty
  contact on error).

### Tests (`test/outfitter_contact_resolver_test.dart`, 10 tests, all pass)
- Resolves outfitter profile (canonical + alias field names).
- Resolves a farm manager as the primary contact when assigned (manager
  precedence); resolves via the `cellNr` alias.
- Returns an empty contact when the outfitter doc / outfitterId is missing.
- Does not throw when a farmId is present but no manager is assigned.
- Falls back gracefully on a Firestore fetch error (`[core/no-app]`).
- `OutfitterContact` getters: empty-contact contract; primary-contact
  fallback to outfitter when manager has no name.

### Verification
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings** (279 infos, all
  pre-existing `avoid_print` / `deprecated_member_use` / style hints in
  unrelated files; the new files are analyzer-clean).
- `flutter test` (full suite): **All 662 tests passed**, zero failures
  (was 652; +10 = the new contact resolver tests). No regressions.
- No Firestore rules / index / Storage / manifest changes (pure client-side
  service + UI; the reads use existing `isSignedIn()` rules).
- Files: `lib/features/hunter_mode/services/outfitter_contact_resolver.dart`
  (NEW), `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (contact card + state + url_launcher import),
  `test/outfitter_contact_resolver_test.dart` (NEW, 10 tests), `AGENTS.md`.


## Reusable OutfitterContactCard + My Bookings contact card (added 2026-08-18)

Extracted the Package Details contact card into a reusable widget and wired
it into the hunter "My Bookings" card so a hunter can view the outfitter /
farm manager contact details (name + role, tappable phone `tel:` intent,
tappable email `mailto:` intent) for an active or confirmed booking.

### New reusable widget: `OutfitterContactCard`
(`lib/features/hunter_mode/widgets/outfitter_contact_card.dart`)
- `StatefulWidget` that owns its own contact-resolution state (loading /
  resolved / unavailable). Resolves the contact asynchronously via
  `OutfitterContactResolver.instance.resolve(source)` from the
  `outfitterId` (+ optional `farmId`) carried on the supplied document map.
- `didUpdateWidget` re-resolves when the underlying document's
  `outfitterId` / `farmId` changes (covers a `ListView` builder recycling
  the card for a new booking), so the card never shows a stale contact.
- Three render states: a compact loading spinner; a graceful "Contact
  details are not available for this booking yet. Use the in-app chat to
  reach the outfitter." fallback (older records / missing docs / offline /
  `[core/no-app]`); and the resolved primary contact name + role label
  ("Farm Manager" / "Outfitter") + tappable phone (`tel:`) and email
  (`mailto:`) rows via `url_launcher.launchUrl`, each an `InkWell` with an
  open-in-new icon + a failed-launch snackbar (messenger captured
  pre-async-gap, `mounted` guarded).
- Accepts an optional `heading` override so the Package Details sheet
  ("CONTACT THE OUTFITTER") and the My Bookings card can share the widget
  verbatim.

### Package Details sheet (`_BookingConfirmationSheet`) refactored
- The inline `_buildContactCard` + the 6 private contact helper methods +
  `_launchUrl` + `_contact`/`_isContactLoading` state + `initState`/
  `_resolveContact` were removed from `_BookingConfirmationSheetState`.
  The sheet now renders `<OutfitterContactCard source: widget.data,
  theme: widget.theme>` -- a single line replacing ~230 lines of
  duplicated UI + state. The `outfitter_contact_resolver` +
  `url_launcher` imports were dropped from the screen (the widget owns
  them).

### Hunter "My Bookings" card (`_HunterBookingCard`) -- new contact card
- The card now renders `<OutfitterContactCard source: widget.data,
  theme: widget.theme>` between the date-change banners and the chat
  drawer -- the natural place for a hunter to find the outfitter / farm
  manager contact details for an active or confirmed booking. Renders on
  every booking (active, awaiting payment, confirmed, completed) so the
  hunter can reach the outfitter at any stage of the lifecycle. The card's
  async resolution + loading/fallback states mean a freshly-opened booking
  list never blocks on the Firestore read.

### Tests (`test/outfitter_contact_card_test.dart`, 4 widget tests, all pass)
- Heading renders immediately while loading.
- Resolves to the "not available" fallback when no contact data is
  resolvable (production singleton path in the test env -> `[core/no-app]`
  caught -> empty contact).
- The fallback mentions the in-app chat.
- Accepts a custom heading.

### Verification
- `flutter analyze` (lib/ + test/): **0 errors, 0 warnings** (278 infos, all
  pre-existing; the new files are analyzer-clean). `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- `flutter test` (full suite): **All 666 tests passed**, zero failures
  (was 662; +4 = the new contact card widget tests). No regressions.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side widget extraction + UI wiring; the reads use the existing
  `isSignedIn()` rules).
- Files: `lib/features/hunter_mode/widgets/outfitter_contact_card.dart`
  (NEW), `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`
  (sheet refactored to use the widget + My Bookings card wired),
  `test/outfitter_contact_card_test.dart` (NEW, 4 tests), `AGENTS.md`.



## Phase — Separate outfitter trophy stock inventory collection from hunter Digital Trophy Room (added 2026-08-18)

The outfitter's saleable trophy stock inventory and the hunter's personal
Digital Trophy Room previously shared a single Firestore `trophies`
collection, distinguished only by which owner field was present
(`outfitterId`/`farmId`/`availableCount`/`pricePerTrophyRands` for outfitter
stock vs `ownerId` for hunter personal trophies). This conflated two
distinct concerns (saleable marketplace inventory vs a hunter's harvested
trophy log) in one collection. The outfitter side now uses a dedicated
`trophy_stock` collection; the hunter Digital Trophy Room remains on
`trophies` (scoped by `ownerId`).

### Single source of truth — collection-name constant
- New `static const String trophyStockCollection = 'trophy_stock'` on
  `OutfitterEnterpriseManager` (`lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`).
  The single named constant every outfitter-side consumer references, so the
  collection name can never drift across the service / screen / exporter /
  analytics / browser / admin.

### Outfitter-side references migrated to `trophy_stock`
- `OutfitterEnterpriseManager` — all four trophy-stock methods now route
  through `trophyStockCollection`: `syncTrophyStock` (create),
  `updateTrophyStock` (update), `deleteTrophyStock` (delete),
  `getFarmTrophyStock` (query). Docstring updated.
- `outfitter_trophy_stock_screen.dart` — the "Current Stock by Farm"
  reactive `StreamBuilder` now streams
  `collection(OutfitterEnterpriseManager.trophyStockCollection).where('outfitterId').orderBy('lastUpdated', descending)`.
- `trophy_inventory_report_exporter.dart` — the PDF report's trophy fetch
  now reads `trophy_stock` where `outfitterId` (the farm-grouped inventory report).
- `outfitter_analytics_service.dart` — `getTrophyStockSummary` now reads
  `trophy_stock` where `outfitterId`.
- `hunter_trophy_browser_screen.dart` — the hunter-facing Trophy Registry
  (which browses OUTFITTER saleable stock, `availableCount > 0`) now reads
  `trophy_stock` for both the province-filtered and unfiltered queries.
- `admin_analytics_service.dart` — the admin dashboard "Total Trophies"
  metric now counts `trophy_stock` (the outfitter inventory metric;
  previously the count was ambiguous because `trophies` held both hunter
  personal trophies and outfitter stock).

### Hunter-side references UNCHANGED (correctly remain on `trophies`)
- `trophy_room_screen.dart` — the hunter personal Digital Trophy Room
  (write + stream scoped by `ownerId`). Verified unchanged.
- `add_trophy_screen.dart` / `edit_trophy_screen.dart` — query the
  `firearms` collection (ownerId), not trophies. No change.
- `trophy_detail_screen.dart` — no `trophies` collection reference. No change.

### Firestore security rules (`firestore.rules`)
- The previous dual-purpose `match /trophies/{trophyId}` block (which
  allowed writes for `ownerId` / `outfitterId` / `hunterId` / `userId`) was
  split into two explicit blocks:
  - `match /trophies/{trophyId}` — hunter personal trophies. Read
    `isSignedIn()` (sharing); create/update/delete owner-scoped on
    `ownerId` / `outfitterId` (legacy back-compat) / `hunterId` / `userId`.
    The `outfitterId` write allowance is retained only so legacy stock docs
    that have not been migrated to `trophy_stock` can still be edited; new
    outfitter stock is written to `trophy_stock`.
  - `match /trophy_stock/{trophyId}` — NEW. Outfitter saleable trophy stock
    inventory. Read `isSignedIn()` (marketplace browse); create/update/delete
    `ownerOrAdmin('outfitterId')` (least-privilege — only the owning
    outfitter or an admin may mutate the saleable inventory).
- Default-deny catch-all retained; brace/paren balance verified.

### Firestore indexes (`firestore.indexes.json`)
- The `trophies` composite index `(outfitterId ASC, lastUpdated DESC)` —
  which only the outfitter stock stream used — was moved to
  `collectionGroup: trophy_stock` (the outfitter stock stream's new home).
  The hunter trophy room stream queries by `ownerId` + `orderBy('createdAt')`
  (a different field), so no `trophies` composite index is required.

### Tests (`test/firestore_rules_seeding_test.dart`, +13 tests, all pass)
Two new structural test groups encode the separation contract (the Firestore
emulator can't run in this sandbox — see AGENTS.md environment constraints):
- `firestore.rules trophy stock separation` (5): dedicated `trophy_stock`
  match block exists; `trophy_stock` read = `isSignedIn()`; `trophy_stock`
  writes are `ownerOrAdmin('outfitterId')`; `trophies` (hunter room) match
  block still exists; `trophies` read remains `isSignedIn()`.
- `outfitter trophy stock collection-name contract` (8):
  `OutfitterEnterpriseManager.trophyStockCollection == 'trophy_stock'`; the
  manager / exporter / analytics / browser / outfitter-stock-screen /
  admin-analytics source files reference `trophyStockCollection` and do NOT
  contain a raw `collection('trophies')`; the inverse guard that the hunter
  `trophy_room_screen.dart` STILL uses `collection('trophies')` and does NOT
  reference `trophyStockCollection` (the hunter room was not migrated).

### Verification
- `flutter analyze` (lib/ + test/): 0 errors, 0 warnings (278 pre-existing
  infos; all changed/new files are analyzer-clean). `analysis_options.yaml`
  auto-touched by the analyzer was reverted before commit.
- `flutter test` (full suite): All 679 tests passed, zero failures (was 666;
  +13 = the new separation-contract tests). No regressions.
- No Storage / pubspec / manifest changes (pure collection-name migration +
  rules/index split + structural tests).

### Deploy reminder
`npx firebase-tools deploy --only firestore:rules,firestore:indexes` CANNOT
run in this sandbox (no `FIREBASE_TOKEN` / `firebase login`; verified —
`firebase projects:list` errors with an auth failure, matching the AGENTS.md
environment-constraints note). The ruleset + index are committed; the deploy
MUST be run in a credentialed environment. Until deployed: outfitter
trophy-stock writes to `trophy_stock` are denied (default-deny applies to the
not-yet-deployed collection); the `trophy_stock` composite index does not
exist, so the outfitter stock stream errors (surfaced in-UI) until built.

### Data migration note (operational)
Existing outfitter stock docs currently live in the `trophies` collection.
After the rules deploy, a one-time admin migration should copy each
`trophies` doc carrying `outfitterId` + `availableCount` into the
`trophy_stock` collection (and optionally delete the original). The app's
outfitter-side reads now target `trophy_stock`, so until the migration runs
the outfitter stock screen / PDF / analytics will show empty for existing
data. Legacy `trophies` docs with only `ownerId` (hunter personal trophies)
are unaffected.

- Files: `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`
  (`trophyStockCollection` constant + 4 method migrations),
  `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart` (stream migration),
  `lib/features/hunter_mode/services/trophy_inventory_report_exporter.dart` (fetch migration + import),
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart` (summary fetch migration + import),
  `lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart` (browse query migration + import),
  `lib/features/admin/services/admin_analytics_service.dart` (count migration + import),
  `firestore.rules` (split trophies + new trophy_stock block),
  `firestore.indexes.json` (composite index moved to trophy_stock),
  `test/firestore_rules_seeding_test.dart` (+13 separation-contract tests + import), `AGENTS.md`.

## Phase — Remove in-app chat + outfitter-side hunter contact card + mandatory hunter profile onboarding gate (added 2026-08-18)

Three coordinated changes delivered as one logical unit.

### Task 1 — Completely remove in-app chat
- Deleted the entire chat subsystem: `chat_and_filter_service.dart`,
  `booking_chat_thread.dart`, `chat_composer_bar.dart` (services/widgets),
  and their tests (`booking_chat_thread_test.dart`,
  `chat_composer_bar_test.dart`).
- The pure geo/temporal filter helpers that lived on `ChatAndFilterService`
  (`isTimestampWithinHours`, `isCoordinateWithinRadius`) — used ONLY by
  the off-grid navigation screen — were extracted into a NEW
  `lib/features/hunter_mode/services/offline_map_filter_service.dart`
  (`OfflineMapFilterService` singleton, pure Haversine + timestamp-age
  arithmetic, no network). `offline_navigation_screen.dart` import +
  call sites switched to the new service so the offline map filter was not
  broken by the chat removal.
- Hunter marketplace (`hunter_package_marketplace_screen.dart`):
  `_HunterBookingCard` chat drawer (`_buildChatDrawer` / `_isChatExpanded`
  / `_chatScrollController` / the inline composer) removed; the
  `BookingChatThread` in the Custom Package Builder confirmation view
  (`hunter_custom_package_builder_screen.dart`) removed. A missing
  class-closing brace left by the chat removal was restored.
- Outfitter booking dashboard (`outfitter_booking_dashboard_screen.dart`):
  the chat action button + the `BookingChatThread` (via
  `GlobalKey<BookingChatThreadState>`) removed; replaced with the
  hunter contact card (Task 2). `resizeToAvoidBottomInset` retained.
- `firestore.rules`: the `match /bookings/{bookingId}/chats/{chatId}`
  subcollection block + the `isBookingPartyViaParent` helper (used only by
  the chats rule) were removed. The bookings block otherwise unchanged.
- `OutfitterContactCard` fallback copy + `outfitter_contact_card_test.dart`
  updated to drop "in-app chat" references ("reaching the outfitter
  directly").

### Task 2 — Display hunter contact details to outfitter on booked packages
- NEW `lib/features/hunter_mode/services/hunter_contact_resolver.dart`
  (`HunterContactResolver` singleton + `HunterContact` model). `resolve(
  bookingData)` reads `users/{hunterId}` to populate `firstName` /
  `lastName` (with `surname` / `first_name` / `last_name` aliases) +
  `fullName` (composed; with `fullName` legacy alias) + `phone` (with
  `phoneNumber` / `phone` / `cellNumber` / `cell` / `cellNr` aliases) +
  `email`. Best-effort: a missing doc / field / Firestore error yields an
  empty contact (no crash). `@visibleForTesting forTesting(FirebaseFirestore)`
  seam. Permitted by the existing `users` `read: isSignedIn()` rule.
- NEW `lib/features/hunter_mode/widgets/hunter_contact_card.dart`
  (`HunterContactCard` StatefulWidget). Renders the hunter name + role
  label, a tappable phone row (`tel:` via `url_launcher.launchUrl`) and a
  tappable email row (`mailto:`), each an `InkWell` with an open-in-new
  icon; a failed launch surfaces an orange/red snackbar (messenger captured
  pre-async-gap, `mounted` guarded). Loading spinner + graceful
  "unavailable, contact admin" fallback states. `didUpdateWidget`
  re-resolves when the booking's `hunterId` changes (ListView recycle
  safety).
- Wired into the outfitter booking dashboard `_BookingCard`: rendered on
  every booking card (active + archived) between the financial breakdown
  and the action buttons.

### Task 3 — Mandatory hunter profile setup + immediate onboarding redirect
- NEW `lib/features/hunter_mode/services/hunter_profile_completeness.dart`
  (`HunterProfileCompleteness` singleton + `HunterProfileStatus` model).
  `statusFor(uid)` reads `users/{uid}` and returns a `HunterProfileStatus`
  whose `isComplete` is true iff (first name OR legacy multi-token
  `fullName`) AND (last name OR surname alias OR legacy multi-token
  `fullName`) AND (a contact detail: phone OR email). Field-alias tolerant;
  blank/whitespace values are not present. `missingSummary` for the
  redirect snackbar. `@visibleForTesting forTesting(FirebaseFirestore)`
  seam. Lazy Firestore getter so cold-launch construction does not throw
  `[core/no-app]`.
- `hunter_profile_screen.dart`: the single `_fullNameController` was split
  into `_firstNameController` + `_lastNameController` (mandatory, validated
  non-empty); the phone + email fields are now mandatory (validators
  reject empty). The Contact Info section header carries a `*`. The save
  writes `firstName` / `lastName` (keeps `fullName` composed for
  back-compat) + `phone` / `email` to `users/{uid}`.
- Onboarding redirect wired into ALL THREE entry points so a hunter cannot
  bypass the profile screen:
  - `auth_screen.dart` `_routeAfterAuth`: hunters with an incomplete
    profile are redirected to `HunterProfileScreen` (clearing the nav
    stack) with an orange snackbar listing the missing fields, before
    reaching `/hunter_dashboard`.
  - `splash_screen.dart` `_navigateToNextScreen`: same gate on cold launch.
  - `role_selection_screen.dart` `_confirmAndSelectRole`: same gate after
    the role write + cache, so a brand-new hunter is redirected to complete
    onboarding before the dashboard.
  - `hunter_dashboard.dart` `_enforceProfileOnboarding` (defense-in-depth
    in `initState`): if a hunter somehow reaches the dashboard with an
    incomplete profile, redirect them. Admins are NOT gated.
- `widget.theme` field reference fixed per-screen: `auth_screen` uses
  `widget.themedata`; `role_selection_screen` (no theme field) uses
  `ThemeController.instance`; splash + hunter_dashboard use `widget.theme`.
- `Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(...), (_)
  => false)` used (not the non-existent `pushReplacementAndRemoveUntil`).

### Verification
- `flutter analyze` (lib/ + test/, Flutter 3.29.1 CI pin): **0 errors, 0
  warnings** (278 pre-existing infos; all changed/new files are
  analyzer-clean). `analysis_options.yaml` + `pubspec.lock` were NOT
  auto-touched.
- `flutter test` (full suite): **All 694 tests passed**, zero failures
  (was 666; +28 = 13 `hunter_contact_resolver_test` + 15
  `hunter_profile_completeness_test`; no regressions). NOTE: created the
  `/usr/lib/x86_64-linux-gnu/libsqlite3.so` symlink (-> `libsqlite3.so.0`)
  so the `sqflite_common_ffi` SQLite integration tests can load
  `libsqlite3.so` (documented sandbox limitation; the runtime `.so.0`
  exists but the dev `.so` link did not).
- No Firestore rules / index / Storage / pubspec / manifest changes
  required beyond the chats-subcollection removal (the `users` read is
  already `isSignedIn()`; the hunter contact + profile-completeness reads
  are covered by it).
- Files: NEW — `hunter_contact_resolver.dart`, `hunter_contact_card.dart`,
  `hunter_profile_completeness.dart`, `offline_map_filter_service.dart`,
  `test/hunter_contact_resolver_test.dart`,
  `test/hunter_profile_completeness_test.dart`. DELETED —
  `chat_and_filter_service.dart`, `booking_chat_thread.dart`,
  `chat_composer_bar.dart`, `test/booking_chat_thread_test.dart`,
  `test/chat_composer_bar_test.dart`. MODIFIED —
  `hunter_profile_screen.dart`, `auth_screen.dart`, `splash_screen.dart`,
  `role_selection_screen.dart`, `hunter_dashboard.dart`,
  `hunter_package_marketplace_screen.dart`,
  `hunter_custom_package_builder_screen.dart`,
  `outfitter_booking_dashboard_screen.dart`, `offline_navigation_screen.dart`,
  `outfitter_contact_card.dart`, `firestore.rules`,
  `test/outfitter_contact_card_test.dart`, `AGENTS.md`.



## Phase -- Species Revenue Breakdown fix + Farm Revenue Breakdown in analytics PDF (added 2026-08-19)

Two reporting/analytics fixes on the outfitter Enterprise Business
Intelligence dashboard (`outfitter_revenue_screen.dart`).

### Task 1 -- Species Revenue Breakdown (was hardcoded empty)
- **Root cause**: `_getSpeciesRevenueData()` in
  `outfitter_revenue_screen.dart` returned a hardcoded `[]`, so the Species
  Revenue Breakdown card always rendered "No species revenue data yet".
- New `OutfitterAnalyticsService.getSpeciesRevenueBreakdown(outfitterId)`:
  queries earned bookings (`status whereIn earnedBookingStatuses` =
  Confirmed / Completed), then resolves species revenue from two sources:
  - **Custom harvested species** -- the booking's own `selectedItemsList`
    (`name` + `quantity` + `lineTotal` / `unitPriceHunterZAR` /
    `hunterPrice`), written by
    `FarmGamePriceListManager.submitCustomPackageBooking`.
  - **Package animals** -- the linked `packages/{packageId}` doc's
    `speciesItems` (`speciesName` + `quantity` + `pricePerAnimal` /
    `total`); package docs are fetched only for bookings without inline
    species items (`CUSTOM_BUILT` is never fetched).
- New pure static `OutfitterAnalyticsService.aggregateSpeciesRevenue(
  bookings, packagesById)` + `hasInlineSpeciesItems(booking)` helper:
  aggregates revenue + harvest counts by species name, sorted desc by
  revenue (alphabetical tie-break). Blank species names skipped; qty < 1
  clamped to 1. Unit-testable without the Firestore emulator.
- `_getSpeciesRevenueData()` now delegates to the service (null-uid -> []).

### Task 2 -- Farm Revenue Breakdown in the analytics PDF export
- `RevenueAnalyticsReportExporter.generateAndShare` now also fetches earned
  bookings and renders a new **"Farm Revenue Breakdown (ZAR)"** section
  (Farm / Bookings / Revenue table) directly above the Farm Manager
  Directory, aggregating total ZAR revenue per `farmId` via
  `PricingMath.resolveHunterTotal` (base price preferred; stored total as
  legacy fallback).
- New pure static `RevenueAnalyticsReportExporter.aggregateFarmRevenue(
  bookings, farmNames)`: every registered farm is listed (R 0.00 when it
  has no earned bookings); bookings with a missing/unknown `farmId` roll up
  under an "Unassigned / Other" row (omitted when empty). Sorted desc by
  revenue.
- `_buildContent` -> public `buildContent` (mirrors
  `FarmPriceListPdfExporter.buildContent`) so the PDF layout is
  unit-testable by rendering the branded document to bytes.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (278 pre-existing infos, unchanged baseline).
- `flutter test` (full suite): **All 721 tests passed**, zero failures
  (+27 = `test/species_revenue_breakdown_test.dart` 13 +
  `test/revenue_analytics_report_exporter_test.dart` 14, incl. full branded
  PDF-to-bytes render tests).
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  aggregation + PDF layout; the `bookings` / `packages` reads use existing
  `isSignedIn()` / owner-scoped rules).
- Files: `lib/features/hunter_mode/services/outfitter_analytics_service.dart`,
  `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`,
  `lib/features/hunter_mode/services/revenue_analytics_report_exporter.dart`,
  `test/species_revenue_breakdown_test.dart` (NEW),
  `test/revenue_analytics_report_exporter_test.dart` (NEW), `AGENTS.md`.


## Phase -- Outfitter dashboard Managers + Pending counts showing 0 (added 2026-08-19)

Two count-card fixes on the outfitter Enterprise Business Intelligence
dashboard (`outfitter_revenue_screen.dart`).

### Task 1 -- Managers card (showed 0)
- **Root cause**: `_getManagersData()` queried the nonexistent `managers`
  collection instead of `farm_managers` (the collection
  `OutfitterEnterpriseManager.assignManager` writes to, stamped with
  `outfitterId` == the caller's uid). The query matched no documents, so
  the Managers card always rendered 0. Fixed the collection name.

### Task 2 -- Pending bookings card (showed 0)
- **Root cause**: `_getPendingBookingsCount()` used a strict server-side
  `status == 'Pending Approval'` equality match, which silently misses
  pending bookings whose status was written with a legacy case / spelling
  variant (`'pending'`, `'Pending'`, `'pending_approval'`).
- New `BookingStatus.normalize(String?)` -- the single source of truth for
  tolerant status matching: case-insensitive, `_`/`-` treated as spaces,
  maps legacy aliases (`pending`/`Pending` -> Pending Approval;
  `Approved`/`Pending Deposit`/`Pending Payment` -> Awaiting Payment;
  `Paid` -> Confirmed; `Canceled` -> Cancelled); unknown statuses pass
  through trimmed + unchanged (never silently remapped); null/blank ->
  null. New `BookingStatus.isPendingApproval(String?)` helper.
- `_getPendingBookingsCount()` now uses a single-equality `outfitterId`
  query (no composite-index dependency) + the tolerant client-side
  `BookingStatus.isPendingApproval` match.

### Robustness -- per-metric graceful degradation
- Each auxiliary metric in `_combinedAnalyticsStream` (farms / managers /
  packages / pending / species / monthly) now runs through `_tryCount` /
  `_tryList` wrappers that degrade to 0 / empty on any failure
  (permissions, offline with no cache, missing index), so one failing
  query can never error the whole dashboard stream into the "Error
  loading analytics" banner.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (278 pre-existing infos, unchanged baseline).
- `flutter test` (full suite): **All 738 tests passed**, zero failures
  (+17 = `test/outfitter_dashboard_counts_test.dart`: normalize +
  isPendingApproval unit tests + structural source-contract regression
  guards asserting the screen queries `farm_managers` (not `managers`),
  filters bookings by `outfitterId`, and uses the tolerant
  `BookingStatus.isPendingApproval` match).
- No Firestore rules / index / Storage / pubspec changes (pure client-side
  query fixes; `farm_managers` read is already `isSignedIn()` and
  `bookings` read is already outfitter-scoped per `firestore.rules`).
- Files: `lib/features/hunter_mode/models/booking_status.dart`
  (`normalize` + `isPendingApproval`),
  `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`
  (collection fix + tolerant pending count + `_tryCount`/`_tryList`),
  `test/outfitter_dashboard_counts_test.dart` (NEW, 17 tests), `AGENTS.md`.


## Phase -- Income per Farm BI section, marketplace town, My Bookings archive split, optic history fix (added 2026-08-19)

Four coordinated updates delivered as one unit.

### Task 1 -- Income per Farm on the Enterprise BI screen
- New `_getFarmRevenueData()` in `outfitter_revenue_screen.dart`: fetches the
  outfitter's `farms` (id->name) + earned bookings (`status whereIn
  OutfitterAnalyticsService.earnedBookingStatuses` = Confirmed + Completed)
  and aggregates per-farm ZAR revenue via the shared pure
  `RevenueAnalyticsReportExporter.aggregateFarmRevenue` -- the on-screen card
  and the PDF export now share one aggregation, so they always agree.
- New "Income per Farm" section rendered directly below the Species Revenue
  Breakdown: one `_FarmRevenueRow` per farm (name, earned-booking count,
  total ZAR revenue, top 8 by revenue), empty state, and a
  `ContextualInfoIcon` explainer. Payload wired through
  `_combinedAnalyticsStream` as `farmRevenue` with the per-metric `_tryList`
  degradation (a failing query shows an empty section, never errors the page).

### Task 2 -- Town name on the Package Marketplace card
- `OutfitterAnalyticsService.getFilteredPackagesStream` now resolves a `town`
  field into the enriched package map: `packageData['town']` ??
  `farmData['town']` ?? `district` (the SA town-level locality farms carry).
- `_PackageCard` renders the town directly below the package title (accent
  `location_city` row); both location rows gained ellipsis guards.

### Task 3 -- My Bookings split into Active + Past Hunts
- New pure `BookingActivityClassifier`
  (`lib/features/hunter_mode/services/booking_activity_classifier.dart`):
  `isPastHunt(booking, {now})` is true when the normalized status is terminal
  (Completed / Declined / Cancelled -- tolerant of legacy spellings via
  `BookingStatus.normalize`) OR the hunt window's final day has passed
  (uses `BookingDateFormatter.resolveWindow`; `window.end` is
  calendar-exclusive). Everything else -- pending, awaiting payment,
  confirmed with future dates, or no dates yet -- stays ACTIVE.
  `isActiveHunt` is the exact complement. The optional `now` param makes the
  date comparison deterministic in tests.
- The marketplace is now 3 tabs: "📦 Packages" / "📋 My Bookings"
  (active + upcoming only) / "🗂 Past Hunts" (the archive), sharing one
  parameterized `_buildMyBookingsTab(theme, {required bool pastOnly})` list
  builder with per-tab empty states. The split is computed in-memory after
  the existing client-side timestamp sort (no new Firestore query / index).

### Task 4 -- Saved optics history (optic_logs) empty list
- **Root causes**: (a) the history query used a `userId == uid`-only
  equality, so legacy docs stamped with `ownerId` never matched; (b)
  `OpticLogEntry.fromMap` only read the nested `optic` submap, so legacy
  flat documents (top-level `opticName`/`turretUnit`/etc.) rendered as
  "Unnamed optic" with defaults.
- `OpticLogService.getMyOpticLogsStream` now queries
  `Filter.or(Filter('userId', isEqualTo: uid), Filter('ownerId', isEqualTo: uid))`,
  de-duplicates by doc id, and keeps the client-side newest-first sort (no
  composite-index dependency).
- `logSave` + `OpticLogEntry.toMap` dual-stamp `userId` AND `ownerId`.
- `OpticLogEntry.fromMap` tolerates the `ownerId` alias for `userId` and
  builds the optic from top-level flat legacy fields (`opticName`,
  `turretUnit`, `clickValue`, `focalPlane`, `reticleType`,
  `nativeMagnification`, `currentMagnification`, `tubeDiameterMm`,
  `heightOverBoreInches`) when the nested `optic` submap is absent; the
  submap wins when both are present.
- `firestore.rules` `optic_logs` read/update/delete now accept BOTH owner
  aliases (`isOwnerOf('userId') || isOwnerOf('ownerId')`); create still
  requires `request.resource.data.userId == request.auth.uid`.
  **Deploy reminder**: `npx firebase-tools deploy --only firestore:rules` in
  a credentialed env to activate the ownerId-alias read (the OR query is
  permission-denied until the rule covers both branches).

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (278 pre-existing infos, unchanged baseline).
- `flutter test` (full suite): **All 771 tests passed**, zero failures
  (+33 = `test/booking_activity_classifier_test.dart` 17,
  `test/optic_log_service_test.dart` +10,
  `test/enterprise_and_marketplace_ui_contract_test.dart` 14 structural
  source-contract tests locking the screen wiring + the rules alias).
- Files: `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_analytics_service.dart`,
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/hunter_mode/services/booking_activity_classifier.dart` (NEW),
  `lib/features/ballistics/data/services/optic_log_service.dart`,
  `firestore.rules`,
  `test/booking_activity_classifier_test.dart` (NEW),
  `test/optic_log_service_test.dart` (extended),
  `test/enterprise_and_marketplace_ui_contract_test.dart` (NEW), `AGENTS.md`.

## Phase -- Custom Package Builder wired to `farm_pricelists` + orphaned-booking guards (added 2026-08-19)

Audited the hunter Custom Package Builder end-to-end against the
`farm_pricelists` collection (fields per the data screenshot: `farmId`,
`outfitterId`, `speciesName`, `gender`, `hornTuskLength`, `price`, `qty`).
The query/display path was already correct from prior phases; this pass fixed
three real end-to-end defects and locked them with tests.

### Audit result (verified correct, no change)
- **Query source**: `hunter_custom_package_builder_screen.dart` streams
  `FarmGamePriceListManager.getFarmPriceListStreamForHunter(farmId)` (queries
  `farm_pricelists` `.where('farmId')` only -- hunter-readable per the
  `read: isSignedIn()` rule; client-side species sort, no composite-index
  dependency; wrapped in `OfflineStreamGuard`). The farm-selection screen
  (`custom_package_farm_selection_screen.dart`) groups `farm_pricelists` docs
  by `farmId` (+ `farm_service_rates` fallback) and filters out farms with
  no published pricing.
- **Model field mapping**: `FarmGamePriceEntry.fromFirestore`/`fromMap` map
  exactly the screenshot fields (`farmId`, `outfitterId`, `speciesName`,
  `qty`, `price`, `gender`, `hornTuskLength`, `hornTuskUnit`) and tolerate
  aliases (`name`, `quantity`, `priceZAR`, `priceRands`, `sex`, `horn`,
  `tusk`).
- **UI display**: species rows render gender chips (suppressed when 'Any'),
  horn/tusk display labels with unit suffix, "max N" limit chips, and a
  quantity stepper capped at the outfitter's published `qty`; itemized
  service-rate rows render the per-category unit semantics; grand total +
  submit confirmation view.

### Fix 1 -- Farm-selection outfitterId resolution (`custom_package_farm_selection_screen.dart`)
- **Root cause**: the `farmId -> outfitterId` map used `putIfAbsent`, keeping
  the FIRST `farm_pricelists` entry's `outfitterId` even when it was blank --
  despite the comment claiming "the first entry that carries a non-empty
  outfitterId wins". A farm whose earliest-written price-list entry had a
  blank `outfitterId` resolved to `''`, and the builder wrote an ORPHANED
  booking (the outfitter dashboard queries `outfitterId == uid`, so they
  never saw it).
- Extracted a pure top-level `resolveOutfittersByFarm(Iterable<Map>)`:
  the first entry carrying a NON-EMPTY `outfitterId` wins; a later non-empty
  value backfills an empty/missing one; a known non-empty id is never
  overwritten. The same prefer-non-empty rule now applies to the
  `farm_service_rates` merge (previously also `putIfAbsent`).

### Fix 2 -- Builder outfitterId fallback + guard (`hunter_custom_package_builder_screen.dart`)
- New `_resolvedOutfitterId()`: prefers the farm-selection-resolved id;
  falls back to the `outfitterId` stamped on the streamed `farm_pricelists`
  entries themselves (every price-list doc carries it). `_submitBooking`
  blocks with a clear "This farm's price list does not identify its
  outfitter. Please go back and re-select the farm." error when the id is
  still unresolved -- no orphaned booking can be written.

### Fix 3 -- Spec passthrough to the booking (`farm_game_price_list_manager.dart` + builder)
- `submitCustomPackageBooking`'s `normalizeItem` previously DROPPED the
  builder's collected spec fields, so gender / horn-tusk / quantity-limit /
  fee-unit data vanished from the booking doc. It now passes through
  `hornTuskLength`, `hornTuskUnit`, `quantityLimit`, `itemType`, `feeType`,
  `feeUnitLabel`, `quantityNoun` (alongside the existing `sex`, `sexLabel`,
  `trophySizeRange`). The builder's `_collectSelectedSpecies` now also
  emits `hornTuskUnit`.

### Tests
- `test/custom_package_farm_selection_resolver_test.dart` (NEW, 7 tests):
  farm->outfitter mapping; non-empty backfill of empty/missing id; known id
  never overwritten; blank/missing farmId skipped; empty input; all-blank
  farm resolves to '' (builder guard surfaces a clear error).
- `test/farm_game_price_list_stream_test.dart` (+1 test): the
  `submitCustomPackageBooking` normalization passes gender / horn-tusk /
  hornTuskUnit / quantityLimit / itemType / feeType / feeUnitLabel /
  quantityNoun through to `selectedItemsList` + `lodgingCateringList`.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**, 278
  infos (unchanged pre-existing baseline; the changed/new files are
  analyzer-clean). The only issues in the edited test file are the
  documented pre-existing `no_leading_underscores_for_local_identifiers`
  infos at lines 26/32.
- `flutter test` (full suite): **All 779 passed**, zero failures (was 771;
  +8 = 7 resolver + 1 passthrough). No regressions.
- Environment note: re-installed Flutter 3.29.1 stable (CI pin) at
  `/home/openhands/flutter` (the SDK had been removed since the prior
  session); `apt-get install unzip xz-utils libsqlite3-dev` and the
  `/usr/lib/x86_64-linux-gnu/libsqlite3.so -> libsqlite3.so.0` symlink for
  the sqflite-FFI integration tests. The `flutter test` tool emits a
  pre-existing spurious "Unexpected child config found under flutter"
  pubspec warning on EVERY test run (verified on untouched test files too);
  non-blocking, unrelated to this change.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side resolution + passthrough + tests; `farm_pricelists` read is
  already `isSignedIn()` per `firestore.rules`).
- Files: `lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart`
  (`resolveOutfittersByFarm` + prefer-non-empty merge),
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (`_resolvedOutfitterId` + guard + hornTuskUnit),
  `lib/features/hunter_mode/services/farm_game_price_list_manager.dart`
  (`normalizeItem` passthrough), `test/custom_package_farm_selection_resolver_test.dart`
  (NEW, 7), `test/farm_game_price_list_stream_test.dart` (+1), `AGENTS.md`.


## Phase -- Custom Package Builder blank-loading fix + CopyrightFooter tap-swallowing root-cause fix (added 2026-08-19)

Fixed the hunter Custom Package Builder "blank / unresponsive" screen issue
end-to-end. The robust state-handling shims (invalid-farmId error state,
explicit loading indicator, friendly empty state with back button, retry on
stream error) were added first; the forensic investigation then uncovered a
genuine app-wide rendering/root-cause defect in `CopyrightFooter` that
silently swallowed taps. Both are detailed below.

### Task 1 -- Robust state handling in the builder (no blank loading)
(`lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`)
- **Invalid farmId**: `build()` now returns `_buildInvalidFarmScaffold`
  ("Invalid farm reference" error state + "BACK TO FARM SELECTION" button)
  when `widget.farmId.isEmpty` -- the price-list streams are never
  subscribed for invalid route args. The AppBar title falls back to
  "Custom Package Builder" when `farmName` is blank.
- **Loading**: the explicit `_LoadingView` (`CircularProgressIndicator` +
  "Loading farm price list...") branch was already in place and is
  verified by tests; it is rendered while either cached stream is still in
  `ConnectionState.waiting` with no data.
- **Empty**: the no-pricing branch now renders "No price lists published
  for this farm yet" with a friendly detail line AND a "BACK TO FARM
  SELECTION" `FilledButton` (`Navigator.maybePop`) -- no stranded blank.
- **Error**: the stream-error branch gained a primary "RETRY" action
  (`_retryStreams` -- the cached `_speciesStream`/`_ratesStream` were
  changed from `late final` to re-assignable `late` + `_initStreams()` so a
  retry re-subscribes cleanly) and a secondary "BACK TO FARM SELECTION"
  text button, via new optional `actionLabel`/`secondaryAction` params on
  `_StateBanner`.

### Task 2 -- ROOT CAUSE: CopyrightFooter Center-of-doom tap swallowing
(`lib/core/widgets/copyright_footer.dart`)
- The builder's empty/invalid-state "BACK TO FARM SELECTION" button was
  untappable, and the forensic render/hit-test investigation traced it to a
  **real app-wide defect**: `CopyrightFooter` was built as
  `Padding > Center > Text`. When placed in a Scaffold's
  `bottomNavigationBar` slot (as the builder + several screens do), the
  slot offers LOOSE constraints with the FULL screen height, and `Center`
  expands to fill it -- an invisible full-height overlay whose centered
  text sits mid-screen. Because the Scaffold's `CustomMultiChildLayoutBox`
  hit-tests the `bottomNavigationBar` slot BEFORE the body slot
  (reverse z-order), a tap landing on the overlay's text is consumed and
  the body slot is never hit-tested -- body buttons under the text's band
  silently never fire (button rects were still rendered with zero-height
  body slots, compounding the symptom in tests).
- Fix: replaced `Center` with `SizedBox(width: double.infinity)` +
  `Text(textAlign: TextAlign.center)` -- identical visual centring, but the
  footer now shrink-wraps to the caption height (~30px) at the true bottom
  of the screen and never overlays the body. This single fix unblocks taps
  on every screen that uses `CopyrightFooter` as a `bottomNavigationBar`.
- The widget's doc comment now records the Center-of-doom warning so a
  future refactor does not regress.

### Tests
- `test/copyright_footer_test.dart` (NEW, 3): caption renders; REGRESSION
  guard asserting the footer caption stays a short bottom strip (<100px
  tall, top>500px on the 800x600 test surface) AND that a mid-screen body
  button still receives taps when the footer is a `bottomNavigationBar`.
- `test/custom_package_builder_screen_test.dart` (extended 9-->14):
  empty-state message updated to the new friendly copy; NEW -- empty state
  renders the "BACK TO FARM SELECTION" button; tapping it pops the builder;
  an empty `farmId` renders the invalid-farm error state (with the back
  button) and never subscribes/hangs on streams; helper renamed
  `buildScreen` (lint hygiene).
- The existing 9 builder-state tests (loading/empty/error/production
  scenarios) pass unmodified apart from the empty-message copy update.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (277 pre-existing infos, unchanged-to-slightly-lower baseline; changed
  files are analyzer-clean). `analysis_options.yaml` was not auto-touched.
- `flutter test` (full suite): **All 784 tests passed**, zero failures
  (was 779; +5 = 3 new builder-state tests + 2 new footer tests). The
  previously-failing pop test now passes with the footer fix; not a flake.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side UI/state handling + the footer widget fix).
- Files: `lib/core/widgets/copyright_footer.dart` (Center-of-doom fix),
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (invalid-farm guard + empty/error actions + retry-capable streams),
  `test/copyright_footer_test.dart` (NEW),
  `test/custom_package_builder_screen_test.dart` (extended), `AGENTS.md`.


## Phase -- Custom Package Builder card spacing + Trophy Registry farm resolution & standard booking flow (added 2026-08-19)

Three UI / booking-flow fixes delivered as one unit.

### Task 1 -- Custom Package Builder farm card spacing cleanup
- `custom_package_farm_selection_screen.dart` `_FarmCard`: the metadata
  chip `Wrap` (province / district / species count / "service rates" pill)
  previously had only `spacing: 6` and NO `runSpacing`, so a wrapped second
  chip row sat flush against the first (awkward vertical crowding). Now
  `spacing: 8, runSpacing: 6`; the title-to-chips gap grew 4 -> 8; and the
  `_chip` helper renders a clean bordered pill (8-radius + an
  accentColor-0.18 border, accent icon, 8x5 padding). Chips now align
  cleanly without awkward wrapping or crowding.

### Task 2 -- "Unknown Farm" in Trophy Registry (root cause + fix)
- Root cause: `trophy_stock` documents carry ONLY a `farmId` (see
  `OutfitterEnterpriseManager.syncTrophyStock` -- no denormalised farmName /
  province / imageUrl). The browser read `farmName` off the stock doc (where
  it does not exist) so every card fell back to "Unknown Farm". Two sibling
  defects: the province filter ran SERVER-side on
  `trophy_stock.province` (a field that does not exist there), matching ZERO
  documents for any specific province; and `imageUrl` was read directly
  while `syncTrophyStock` writes a `trophyPhotoUrls` array.
- `hunter_trophy_browser_screen.dart` `_loadTrophies` rewritten: loads all
  stock with `availableCount > 0` (no provincial server query), collects the
  unique non-empty `farmId`s, batch-fetches `farms` docs
  (`FieldPath.documentId whereIn`, mirroring the farm-selection join), then
  enriches every trophy with farm name + province + town via new PURE
  resolver functions (unit-testable without Firestore):
  - `resolveFarmName(trophy, farm?)` -- denormalised `farmName` (legacy) ??
    farm `name` ?? 'Unknown Farm'.
  - `resolveTrophyProvince(trophy, farm?)` -- trophy `province` ?? farm
    `province` ?? '' (the client-side province filter runs on this).
  - `resolveTown(trophy, farm?)` -- trophy `town`/`district` ?? farm `town`
    ?? farm `district` ?? ''.
  - `resolveLocationLabel(trophy, farm?)` -- "Bosveld Ranch • Waterberg,
    Limpopo", empty parts omitted.
  - `resolveImageUrl(trophy)` -- explicit `imageUrl` ?? first
    `trophyPhotoUrls` ?? '' (fixes the placeholder-on-every-card bug).
  - `resolveMeasurement(trophy)` -- `trophyMeasurement` ??
    `trophyLengthInches` alias, num-or-string tolerant.
  The card's location row uses `locationLabel(trophy)` over the pre-resolved
  map. Farms readable by any signed-in hunter per `firestore.rules`.

### Task 3 -- Trophy Registry card tap -> standard booking confirmation flow
- Replaced the entire multi-select quick-add (`_selectedTrophyIds` /
  `_toggleTrophySelection` / `_addToBookingLog` "Add to Booking Log"
  AlertDialog + the selection bottom bar + the "N Selected" AppBar action)
  with the standard flow: tapping a trophy card opens
  `TrophyBookingConfirmationSheet` (NEW,
  `lib/features/hunter_mode/widgets/trophy_booking_confirmation_sheet.dart`)
  -- a modal bottom sheet mirroring the package marketplace's confirmation
  sheet exactly (handle, "Trophy Details" title, meta summary chips, the
  TROPHY STOCK ITEM breakdown, the Total Price row, the same
  `OutfitterContactCard`, the approval warning, the sold-out banner, and the
  Cancel / "BOOK THIS TROPHY" action row).
- NEW `PackageBookingManager.bookTrophyStock({trophyId, outfitterId,
  pricePerTrophyRands, species?, sex?, trophyMeasurement?, farmId?,
  farmName?, district?, province?})`: an atomic `runTransaction` that (1)
  reads the stock doc, (2) throws `PackageSoldOutException` when
  `availableCount <= 0` or status != 'available', (3) creates the booking
  record with `packageId: 'CUSTOM_BUILT'` + `isTrophyStockBooking: true` +
  `trophyStockId` + a one-entry `selectedItemsList` + `status:
  BookingStatus.pendingApproval` (standard routing -> outfitter Incoming
  Booking Requests dashboard renders the expandable custom-items section +
  APPROVE/DECLINE; hunter "My Bookings" tab renders it as a standard
  booking), and (4) decrements `availableCount` by 1 and flips `status` to
  'sold_out' when it hits 0 -- all in the same transaction (no race).
  On sheet close the browser reloads so availability drops immediately.
- `firestore.rules` `trophy_stock` block split the blanket
  `ownerOrAdmin('outfitterId')` write into `create` (owner/admin), `delete`
  (owner/admin), and `update` (`isOwner() || isStockDecrement() ||
  isAdmin()`) where the new `isStockDecrement()` helper (mirroring the
  `packages` `isInventoryDecrement` contract) permits a signed-in hunter's
  TIGHTLY-SCOPED decrement: outfitterId/species/farmId/pricePerTrophyRands
  frozen, `availableCount` strictly lower, status unchanged or 'sold_out'.
  **Deploy reminder**: `npx firebase-tools deploy --only firestore:rules` in
  a credentialed env to activate the hunter decrement allowance; until
  deployed the booking transaction fails with permission-denied (surfaced
  as the generic "Booking failed" snackbar).

### Tests
- `test/trophy_registry_resolver_test.dart` (NEW, 24 tests): farm-name /
  province / town / location-label / image-url / measurement resolvers.
- `test/trophy_booking_contract_test.dart` (NEW, 12 tests): standard-sheet
  wiring (showModalBottomSheet + TrophyBookingConfirmationSheet + quick-add
  removal + BookTrophyStock confirm), the booking transaction contract
  (transaction + atomic guard + CUSTOM_BUILT routing + pending status +
  safe decrement + sold_out flip), guard / status-flip pure logic, and the
  Task-1 chip spacing contract.
- `test/firestore_rules_seeding_test.dart` (+1 test): the trophy_stock
  hunter-decrement rule contract (isStockDecrement + update split +
  strictly-lower count).

### Verification
- `flutter analyze` (local Flutter 3.47.0 stable): 0 errors, 0 warnings,
  307 pre-existing infos (unchanged baseline; the changed/new files are
  analyzer-clean). `analysis_options.yaml` auto-touched by `flutter pub
  get` / analyze was reverted before commit (documented baseline pattern).
- `flutter test` (full suite): **All 821 tests passed** (was 784; +37 =
  24 resolver + 12 booking-contract + 1 rules test). No regressions.
- No Storage / index / pubspec / manifest changes (pure client-side +
  rules; `farms` read was already `isSignedIn()`; the only new write path
  is the hunter decrement covered by the rules change above).
- Files: `lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart`
  (chip spacing), `lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart`
  (farm resolution + booking-sheet rewire + quick-add removal),
  `lib/features/hunter_mode/widgets/trophy_booking_confirmation_sheet.dart`
  (NEW), `lib/features/hunter_mode/services/package_booking_manager.dart`
  (`bookTrophyStock`), `firestore.rules` (trophy_stock decrement),
  `test/trophy_registry_resolver_test.dart` (NEW),
  `test/trophy_booking_contract_test.dart` (NEW),
  `test/firestore_rules_seeding_test.dart` (+1), `AGENTS.md`.


## Phase -- Admin outfitters count fix, hunter logout, farm/trophy photos, booking category filters (added 2026-08-20)

Six coordinated updates delivered as one unit.

### Task 1 -- Admin portal "Outfitters" count showed 0
- **Root cause**: outfitters exist in TWO collections -- `users` docs with
  `role == 'outfitter'` (self-registered via role selection, the common
  path) and `outfitters` docs (admin-provisioned via the
  `adminCreateOutfitter` Cloud Function / user management service).
  `AdminAnalyticsService.fetchEntityMetrics` only counted the `outfitters`
  collection, so it returned 0 when every outfitter had self-registered.
- **Fix**: new `_countAllOutfitters()` unions the document ids of
  `users.where('role', isEqualTo: 'outfitter')` and the `outfitters`
  collection, so each outfitter is counted exactly once regardless of
  source. The eager `final _db`/`_auth` field initializers were converted
  to lazy getters (cold-launch-safe) with a `@visibleForTesting static
  firestoreForTesting` seam.
- Tests: `test/admin_outfitters_count_test.dart` (6 tests via
  `FakeFirebaseFirestore`): zero-state, users-only, outfitters-only, union,
  dedup-across-collections, hunter/role-less exclusion.

### Task 2 -- Logout button in Hunter Profile
- `hunter_profile_screen.dart`: a prominent branded `ElevatedButton.icon`
  "LOGOUT" (accent background, white bold label, `Icons.logout_rounded`) in
  the ACCOUNT SECURITY section under Change Password. Confirmation dialog,
  then `AuthGateService().signOut()` (which also resets `UserRoleProvider`
  + `AdminAuthGuard`) and `pushNamedAndRemoveUntil('/', (_) => false)` back
  to the auth screen. Error path surfaces a red snackbar and re-enables the
  button.

### Task 3 -- Farm photo upload during farm registration
- `outfitter_enterprise_panel_screen.dart` Register New Farm form: new
  "FARM PHOTO (OPTIONAL)" section with Take Photo (camera) / From Gallery
  tiles via `ImageService.pickAndCompressImage` (1280px, JPEG q80), a
  preview with remove badge, and upload to
  `farm_photos/{outfitterId}/{timestamp}.jpg` on submit (best-effort --
  upload failure does not block farm registration).
- `OutfitterEnterpriseManager.addFarm` gained optional `photoUrl`; writes
  both `photoUrl` and `photoUrls: [url]` on the `farms` doc.
- `storage.rules`: new owner-scoped `match /farm_photos/{uid}/{allPaths=**}`
  write block. **Deploy reminder**: `npx firebase-tools deploy --only storage`.

### Task 4 -- Farm thumbnails in the Farm Control Panel
- Registered Farms cards now render a 52x52 rounded thumbnail via the
  resilient `AdaptiveImage` pipeline (explicit `photoUrl` first, then first
  `photoUrls` entry), with the clean landscape-icon placeholder when no
  photo exists. Pure top-level `resolveFarmPhotoUrl(Map)` resolver
  (unit-testable).

### Task 5 -- Thumbnails in the Trophy Stock Inventory
- "Current Stock by Farm" per-species rows now render a 40x40 rounded
  thumbnail via `AdaptiveImage` (first `trophyPhotoUrls` entry, then
  `photoUrl` fallback), with a clean pets-icon placeholder. Pure top-level
  `resolveTrophyStockPhotoUrl(Map)` resolver (unit-testable).
- Tests for both resolvers: `test/farm_and_trophy_photo_resolver_test.dart`
  (11 tests).

### Task 6 -- Incoming Booking Requests category filters
- New pure `lib/features/hunter_mode/services/booking_category_classifier.dart`
  (`BookingCategory {standard, custom, trophy}` + `classify(Map)`): trophy
  wins over custom (`isTrophyStockBooking` / `trophyStockId`), then custom
  (`isCustomPackage` / `packageId == 'CUSTOM_BUILT'`), else standard.
- `outfitter_booking_dashboard_screen.dart`: a horizontal filter-chip bar
  under the AppBar -- All / Standard Hunting Packages / Custom Hunting
  Packages / Trophy Hunt Requests -- filters BOTH the Active Requests and
  Archived lists in-memory (no new Firestore query/index). Empty-state copy
  is filter-aware.
- Tests: `test/booking_category_classifier_test.dart` (9 tests).

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (277 pre-existing infos, unchanged baseline; all changed/new files
  analyzer-clean).
- `flutter test` (full suite): **All 847 tests passed** (was 821; +26 new).
  No regressions. Re-installed Flutter 3.29.1 at `/home/openhands/flutter`
  + `/usr/lib/x86_64-linux-gnu/libsqlite3.so -> libsqlite3.so.0` symlink
  for the sqflite-FFI integration tests (documented sandbox pattern).
- Files: `lib/features/admin/services/admin_analytics_service.dart`,
  `lib/features/hunter_mode/hunter_profile_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`,
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`,
  `lib/features/hunter_mode/services/booking_category_classifier.dart` (NEW),
  `storage.rules`,
  `test/admin_outfitters_count_test.dart` (NEW),
  `test/booking_category_classifier_test.dart` (NEW),
  `test/farm_and_trophy_photo_resolver_test.dart` (NEW), `AGENTS.md`.


## Phase -- Hunter photo galleries, payment text, farm/agent detail panels (added 2026-08-20)

Four hunter-side enhancements delivered as one unit.

### Shared building blocks (NEW)
- `lib/features/hunter_mode/services/photo_gallery_resolver.dart` -- pure
  `resolveGalleryUrls(Map)` that collects photo URLs across all known
  field aliases (`imageUrls` / `photoUrls` / `trophyPhotoUrls` / `photoUrl`
  / `imageUrl`) in priority order, de-duplicated, non-string entries
  ignored (strings-only guard), blank entries skipped, URLs trimmed.
- `lib/features/hunter_mode/widgets/photo_gallery_strip.dart`
  (`PhotoGalleryStrip`) -- a horizontally scrollable gallery that renders
  EVERY photo URL via the resilient `AdaptiveImage` pipeline, with a
  "N photos -- swipe to browse" position chip and a tap-to-open full-screen
  `InteractiveViewer` viewer. Returns `SizedBox.shrink` on empty.
- `lib/features/hunter_mode/models/farm_details.dart` -- `FarmDetails`
  immutable farm snapshot (name / district / province / town / contact /
  registration / size / photoUrls) with alias-tolerant `fromMap`
  (`name`/`farmName`, `town`/`district`, gallery resolver) + display
  getters (`displayName`, `primaryPhotoUrl`, `infoChips`). Same file
  carries `FarmThumbnail` (rounded thumb + clean terrain placeholder).
- `lib/features/hunter_mode/services/farm_details_resolver.dart`
  (`FarmDetailsResolver` singleton) -- async `farms/{farmId}` fetch with a
  `@visibleForTesting static firestoreForTesting` seam; swallows errors
  into an empty-details snapshot (never throws).

### Task 1 -- Multiple photos on Package Marketplace details
- `_BookingConfirmationSheet` in `hunter_package_marketplace_screen.dart`
  now renders a `PhotoGalleryStrip` (full gallery, tap-to-fullscreen) above
  the itemized breakdown -- every image the outfitter uploaded on the
  package (previously the sheet had no gallery at all; the card's own
  preview only handled one feed). The package card's `_buildGallery` was
  also switched to the shared `PhotoGalleryStrip` (the inline
  `CachedNetworkImage` strip + its import were removed).

### Task 2 -- Payment information text updated
- The info-icon note in the package details sheet now reads "Booking
  request is sent for outfitter approval. On approval please contact the
  outfitter to arrange for payment." (was "...the total price is due to
  confirm your dates.").

### Task 3 -- Farm images & details in the Custom Package Builder
- Farm-selection `_BookableFarm` now carries a `FarmDetails` (name /
  location / size / contact / registration / full photo gallery resolved
  via `_farmDetailsFrom(doc)`), and `_FarmCard` renders a `FarmThumbnail`
  (60px) instead of the generic terrain icon tile.
- `HunterCustomPackageBuilderScreen` takes `farmDetails` instead of
  `farmName` (the only other caller was the widget test, updated). The
  builder body now renders a prominent FARM header panel at the top: farm
  name + detail chips (province / district / town / size ha / contact /
  registration) + the full farm photo gallery (tap-to-fullscreen) -- see
  `_buildFarmHeader`.

### Task 4 -- Farm details & trophy photos in the Trophy Booking sheet
- `TrophyBookingConfirmationSheet` now renders (a) a trophy photo gallery
  (every `trophyPhotoUrls` attachment, tap-to-fullscreen) below the species
  title, and (b) a FARM DETAILS panel (name + all detail chips + the farm's
  own photo gallery) above the item breakdown.
- The sheet seeds farm details from an optional `farmDetails` param, else
  the raw farm map the Trophy Registry browser now embeds under `farmData`
  (its existing `farms` join), else asynchronously resolves
  `farms/{farmId}` via `FarmDetailsResolver` and updates reactively (slim
  loading row while in flight).

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (277 pre-existing infos, unchanged baseline; all changed/new files
  analyzer-clean -- `debugPrint`, `AdaptiveImage`, and resolver files all
  clean).
- `flutter test` (full suite): **All 861 tests passed** (was 847; +14 new
  in `test/photo_gallery_and_farm_details_test.dart` -- gallery resolver
  dedup/trim/non-string/null-safety, `FarmDetails.fromMap` alias + chips,
  `FarmDetailsResolver` fake-Firestore resolution). The existing
  `custom_package_builder_screen_test` was updated to the new `farmDetails`
  constructor param and still passes. No regressions.
- Files: `lib/features/hunter_mode/services/photo_gallery_resolver.dart`
  (NEW), `lib/features/hunter_mode/widgets/photo_gallery_strip.dart` (NEW),
  `lib/features/hunter_mode/models/farm_details.dart` (NEW),
  `lib/features/hunter_mode/services/farm_details_resolver.dart` (NEW),
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart`,
  `lib/features/hunter_mode/widgets/trophy_booking_confirmation_sheet.dart`,
  `test/photo_gallery_and_farm_details_test.dart` (NEW),
  `test/custom_package_builder_screen_test.dart` (updated), `AGENTS.md`.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  hunter-side UI + pure resolvers; photo reads use existing signed-in
  Storage read rules).


## Phase -- Venison permits hunter-side visibility fix (added 2026-08-20)

Fixed the hunter-side venison permit list showing nothing for permits issued
without a booking context.

### Root cause
- The `venison_permits` docs carried an `outfitterId` but often NO `hunterId`:
  permits issued from the outfitter form without a `bookingId` prefill wrote
  `hunterId: null`, and hunter-self-issued permits stamped no hunter uid at
  all. The hunter-side permit stream queried only `.where('hunterId',
  isEqualTo: uid)`, and `fromMap` read only the `hunterId` key -- so those
  permits never rendered for the hunter.
- The `venison_permits` Firestore read rule granted
  `outfitterId == uid || hunterId == uid`, so a client-side widening alone
  would still be denied by the rules.

### Fixes (mirror the `optic_logs` dual-alias pattern)
- Model (`venison_transport_permit.dart`): new `userId` alias field;
  `fromMap` treats `hunterId`/`userId` as the same party (either spelling
  resolves); `toMap` dual-stamps both; new `effectiveHunterId` getter.
- Manager (`venison_permit_manager.dart`):
  - `issueVenisonPermit` resolves the hunter's uid via the pure static
    `resolveHunterUid` (explicit `permitHunterId` wins; else the issuer uid
    when the issuer != outfitter -- hunter self-issue; else null) and stamps
    BOTH `hunterId` and `userId` on the doc.
  - `getMyPermitsStream(isOutfitter: false)` now queries
    `Filter.or(Filter('hunterId', isEqualTo: uid), Filter('userId',
    isEqualTo: uid))`; the server-side `.orderBy('createdAt')` was removed in
    favour of client-side newest-first sorting (avoids the missing-composite-
    index failure mode). De-duplicated by doc id (dual-stamped docs match
    both OR branches).
  - Lazy Firestore/Storage getters + `@visibleForTesting`
    `firestoreForTesting`/`currentUserIdResolverForTesting` seams with a
    `forTesting` factory (mirrors `OpticLogService`) so construction before
    `Firebase.initializeApp()` no longer throws `[core/no-app]`.
- Rules (`firestore.rules`): the `venison_permits` read grant now also accepts
  `resource.data.userId == request.auth.uid` so the OR-query and legacy
  userId-stamped documents are readable; create/update remain `isSignedIn()`;
  delete stays least-privilege (`isOwnerOf('outfitterId') || isAdmin()`).
  **Deploy reminder**: `npx firebase-tools deploy --only firestore:rules` in
  a credentialed env to activate the widened read.

### Tests
- `test/venison_permit_model_test.dart` (11): alias tolerance
  (`userId`->`hunterId`, `hunterId`->`userId`, both, neither),
  `effectiveHunterId`, toMap dual-stamp / omission contract, round-trip.
- `test/venison_permit_manager_test.dart` (14): hunter stream matches
  `hunterId` alias, matches legacy `userId`-only docs, excludes other hunters,
  dual-stamp dedupe, client-side newest-first sort, outfitter stream,
  `resolveHunterUid` (explicit wins / self-issue stamps issuer / outfitter
  stamps null / blank falls through), issue-write dual-stamping (booking-
  linked and self-issue), unauth rejection -- via `FakeFirebaseFirestore` +
  the `forTesting` seam.
- `test/firestore_rules_seeding_test.dart` (+6 structural tests): the
  `venison_permits` read grant accepts `hunterId` AND `userId` aliases +
  outfitter/admin, isSignedIn required, least-privilege delete.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (278 pre-existing infos, unchanged baseline).
- `flutter test` (full suite): **All 892 tests passed** (was 861; +31 new).
- Environment note: re-installed Flutter 3.29.1 stable at
  `/home/openhands/flutter` + `libsqlite3-dev` for the sqflite-FFI
  integration tests.
- Files: `lib/features/hunter_mode/models/venison_transport_permit.dart`,
  `lib/features/hunter_mode/services/venison_permit_manager.dart`,
  `firestore.rules`, `test/venison_permit_model_test.dart` (NEW),
  `test/venison_permit_manager_test.dart` (NEW),
  `test/firestore_rules_seeding_test.dart`, `AGENTS.md`.


## Phase -- Outfitter portal bushveld background image (added 2026-08-20)

Applied a full-screen bushveld background to the Outfitter portal screen
(`lib/features/outfitter_mode/outfitter_dashboard.dart` -- no
`outfitter_portal_screen.dart` exists; the portal screen is the outfitter
dashboard).

### Layout
- The `Scaffold` body is now a `Stack(fit: StackFit.expand)` with three
  layers:
  1. `_buildBackgroundImage()` -- `Image.network` of the bushveld photo
     (`https://images.unsplash.com/photo-1516426122078-c23e76319801?auto=format&fit=crop&w=1600&q=80`,
     exposed as `OutfitterDashboard.kBackgroundImageUrl`), `BoxFit.cover`,
     with a two-step fallback chain: a bundled bushveld asset
     (`assets/images/Greater Kudu.jpg`, `kBackgroundFallbackAsset`) when the
     network image fails (offline/off-grid), then the theme background
     color if the asset also fails.
  2. `_buildScrim()` -- a semi-transparent dark `LinearGradient` scrim
     (60% -> 40% -> 70% black, top -> mid -> bottom) so text and cards stay
     high-contrast over any photo exposure.
  3. The existing dashboard content (status banner, section label, feature
     cards, footer) layered on top, unchanged apart from the top inset.
- `extendBodyBehindAppBar: true` full-bleeds the photo behind the
  (already transparent) AppBar; the ListView's top padding now includes
  `MediaQuery.padding.top + kToolbarHeight + 12` so content clears the
  AppBar.
- Cross-theme contrast: the two texts rendered directly on the scrim (the
  AppBar two-line title and the OUTFITTER OPERATIONS / FARM MANAGEMENT HUD
  section label) now use white / gold (`#D4AF37`) instead of the theme
  text/accent color, since the default Day theme's dark text would be
  unreadable on the dark scrim. Card contents remain theme-colored (they
  sit on opaque `theme.cardColor` surfaces). This is the same raw-white
  exception already documented for camera-overlay HUD screens.

### Resilience
- `_resolveUserRole` is now wrapped in try/catch: if Firebase Auth is
  unavailable (cold-launch race or widget-test env) the dashboard renders
  with default non-manager flags instead of hanging on the loading
  spinner. The route guard upstream still enforces role access.

### Tests
- `test/outfitter_dashboard_background_test.dart` (NEW, 5 widget tests):
  body is a Stack with >= 3 layers; first child is an `Image` backed by a
  `NetworkImage` with `kBackgroundImageUrl` and `BoxFit.cover`; the scrim
  is a pure-black alpha `LinearGradient`; the dashboard content (status
  banner, section label, feature cards) still renders; the screen renders
  when Firebase auth is unavailable.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (278 pre-existing infos, unchanged baseline; new test uses the
  non-deprecated `Color.r/g/b/a` fields).
- `flutter test` (full suite): **All 897 tests passed** (was 892; +5 new).
- Files: `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `test/outfitter_dashboard_background_test.dart` (NEW), `AGENTS.md`.
- No Firestore / Storage / rules / index / pubspec / manifest changes
  (pure presentation-layer).


## Phase -- Automatic UID stamping on venison permit creation (added 2026-08-20)

Strengthened the venison-permit stamping contract so `userId` + `hunterId`
are ALWAYS auto-populated with the target hunter's UID at write time, with
correct fallback when only one alias is known.

### Changes
- `VenisonTransportPermit.toMap()` now stamps BOTH `hunterId` and `userId`
  from the single `effectiveHunterId` getter whenever the designated
  hunter's uid is known under EITHER alias (previously `toMap` wrote only
  the alias that was set on the model, so a `hunterId`-only model wrote no
  `userId`). `hunterId` is preferred; `userId` is the fallback. A
  single-alias legacy doc read via `fromMap` and written back now migrates
  forward to the dual-stamped shape automatically.
- `VenisonPermitManager.issueVenisonPermit` now resolves the hunter uid via
  `permit.effectiveHunterId` (was `permit.hunterId`), so a model carrying
  ONLY the legacy `userId` alias also stamps BOTH aliases correctly at
  issue time. The `resolveHunterUid` priority chain is unchanged (explicit
  permit hunter uid wins; hunter self-issue stamps the issuer uid when the
  issuer != outfitter; outfitter issue without a booking stamps nothing).
- Removed the redundant `dart:typed_data` import in the manager
  (`flutter/foundation.dart` re-exports `Uint8List`).

### Tests (32 in the two permit suites, all pass)
- `test/venison_permit_model_test.dart`: `toMap` auto-stamps BOTH aliases
  from a `hunterId`-only model; from a `userId`-only model; `hunterId`
  wins when both set; omission contract preserved when neither set;
  `fromMap` single-alias legacy doc -> `toMap` re-stamps both.
- `test/venison_permit_manager_test.dart` (+1): issuing a permit whose
  model carries ONLY the `userId` alias stamps BOTH `hunterId` and
  `userId` on the Firestore doc.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (277 infos -- the manager's redundant-import info was cleaned up).
- `flutter test` (full suite): **All 899 tests passed** (was 897; +2 net:
  +1 new manager test, +1 new model test, two model tests replaced by the
  strengthened auto-stamping contract).
- Files: `lib/features/hunter_mode/models/venison_transport_permit.dart`,
  `lib/features/hunter_mode/services/venison_permit_manager.dart`,
  `test/venison_permit_model_test.dart`,
  `test/venison_permit_manager_test.dart`, `AGENTS.md`.
- No Firestore rules / index / Storage / pubspec / manifest changes (pure
  client-side model + manager stamping logic).


## Phase -- Outfitter portal global bushveld background rollout + top-right icon contrast chips (added 2026-08-20)

Two coordinated changes delivered as one unit.

### Task 1 -- Top-right action icons contrast fix
- New `OutfitterActionChip` in the shared
  `lib/features/outfitter_mode/widgets/outfitter_scaffold.dart`: a
  high-contrast circular chip (translucent ~45% black circle + faint white
  rim) wrapping an AppBar action icon so the glyph stays clearly readable
  against the bright sunrise portion of the bushveld background in both
  light and dark modes. Replaces the raw accent-only `IconButton`s:
  - outfitter dashboard: settings + sign-out chips;
  - price list: PDF export, CSV import, refresh chips;
  - trophy stock: PDF export chip;
  - revenue/BI: PDF export chip.

### Task 2 -- Shared outfitter scaffold & global rollout
- New shared `OutfitterBushveldBackground` helper in
  `lib/features/outfitter_mode/widgets/outfitter_scaffold.dart` exposing
  `backgroundImage` (the bushveld network photo with the bundled
  `Greater Kudu.jpg` offline fallback then theme-color fallback),
  `scrim` (the 60%/40%/70% black gradient), and `stack` (photo + scrim +
  content layered), plus an `OutfitterScaffold` convenience Scaffold
  wrapper. The dashboard's duplicated `_buildBackgroundImage`/`_buildScrim`
  helpers were removed in favour of the shared helper (the dashboard-level
  `kBackgroundImageUrl`/`kBackgroundFallbackAsset` constants are now aliases
  so existing tests/consumers still compile).
- Rolled the shared background stack out across every outfitter-side
  screen so the whole portal carries the immersive bushveld aesthetic:
  Farm Management (enterprise panel), Trophy Stock Inventory, Package
  Publishing (creator), Package Management (my packages), Price Lists,
  Incoming Booking Requests (booking dashboard), the Permit Log, and the
  Enterprise BI (revenue) screen. Each Scaffold gained
  `extendBodyBehindAppBar: true` + a transparent AppBar; scrollable bodies
  got the `MediaQuery.padding.top + kToolbarHeight` top inset, non-scroll
  Column/StreamBuilder bodies got a `SafeArea` wrapper.
- New `test/outfitter_scaffold_rollout_test.dart` (13 structural tests):
  every outfitter screen renders the shared background stack; the action
  chips exist and are applied (dashboard settings/sign-out, price-list
  triple icons, trophy-stock + revenue PDF icons); the raw low-contrast
  IconButtons are gone.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (277 pre-existing infos, unchanged baseline; all changed/new files
  analyzer-clean).
- `flutter test` (full suite): **All 913 tests passed** (was 899; +14 =
  13 rollout + 1 structural; no regressions).
- Files: `lib/features/outfitter_mode/widgets/outfitter_scaffold.dart`
  (NEW), `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_price_list_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart`,
  `lib/features/hunter_mode/screens/venison_permit_list_screen.dart`,
  `lib/features/hunter_mode/screens/outfitter_revenue_screen.dart`,
  `test/outfitter_scaffold_rollout_test.dart` (NEW), `AGENTS.md`.
- No Firestore / Storage / rules / index / pubspec / manifest changes
  (pure presentation-layer).


## Phase -- Outfitter portal light-mode contrast sweep (OutfitterUi helpers) (added 2026-08-20)

Light-mode readability fix across every outfitter screen: the bushveld
background photo has a bright sunrise exposure in its upper portion, so the
default Day-theme colors (translucent white cards, washed-out subtitles)
failed contrast.

### Shared `OutfitterUi` helper (NEW)
- `lib/features/outfitter_mode/widgets/outfitter_scaffold.dart` gained an
  `OutfitterUi` class -- the single source of truth for outfitter light-mode
  contrast:
  - `lightTitle` (`Color(0xFF2C221E)` dark espresso) -- screen titles /
    primary headers in light mode.
  - `lightCard` (`Color(0xFAF7F2EC)` cream, 98% opacity) -- card/form-fill
    surfaces in light mode.
  - `lightCardBorder` (`Color(0xFFD6C8BC)`) -- defined card/input borders in
    light mode.
  - `lightBody` (`Color(0xFF4A3B32)`) -- subtitles / descriptions / hint
    text in light mode.
  - Resolvers: `titleColor(theme)` (espresso light / white dark),
    `cardColor(theme)` (cream light / theme card dark),
    `cardBorderColor(theme)` (defined warm border light / faint white rim
    dark), `subtitleColor(theme)` (warm brown light / theme subtitle dark),
    plus `cardDecoration(...)` and `inputDecoration(...)` convenience
    builders. All dark-mode branches delegate to the standard
    `ThemeController` palette (the scrim keeps those readable).

### Task fixes applied across 10 files
- **My Packages top-of-screen overlap** (`outfitter_package_manager_screen.dart`):
  a `SizedBox(height: MediaQuery.padding.top + kToolbarHeight)` spacer was
  added above the status-filter chip bar so it renders cleanly below the
  back button + title under the transparent full-bleed AppBar
  (`extendBodyBehindAppBar: true`). The chip bar itself is now a cream
  container with a defined bottom border.
- **High-contrast screen titles**: every outfitter AppBar title +
  `foregroundColor` (My Packages, Farm Control Panel, Publish Package,
  Trophy Stock Inventory, Price List, Incoming Booking Requests, Permit
  Log, Revenue/BI) now uses `OutfitterUi.titleColor(theme)` (dark espresso
  in light mode). The dashboard's on-scrim AppBar two-line title + section
  label use espresso in Day mode and white/gold in Night mode.
- **Card & form contrast**: card surfaces, filter-chip bars, search fields,
  `_inputDecoration` fills, and add-tile containers across the enterprise
  panel, trophy stock, package creator, price list, booking dashboard,
  revenue/BI, and permit list now use `OutfitterUi.cardColor(theme)` +
  `OutfitterUi.cardBorderColor(theme)` instead of translucent white +
  faint accent-tinted borders. Configured-state distinctions (e.g. the
  service-rate / line-item rows) keep a solid accent border in light mode
  and the tinted accent in dark mode. All body-level
  `theme.subtitleColor` refs were swapped to
  `OutfitterUi.subtitleColor(theme)`; dialog / bottom-sheet
  (`widget.theme.*`) refs were intentionally left on the theme palette.

### Verification
- `flutter analyze` (Flutter 3.29.1, CI pin): **0 errors, 0 warnings**
  (277 pre-existing infos -- down 1 from the 278 baseline).
- `flutter test` (full suite): **All 913 tests passed**, zero failures.
  No regressions.
- Environment note: re-installed Flutter 3.29.1 stable at
  `/home/openhands/flutter` (SDK had been removed since the prior session)
  + `apt-get install unzip xz-utils libsqlite3-dev` and the
  `/usr/lib/x86_64-linux-gnu/libsqlite3.so -> libsqlite3.so.0` symlink for
  the sqflite-FFI integration tests.
- Commit `72cdefa` pushed to `origin/main` (`faa7cb5..72cdefa`).
- Files: `lib/features/outfitter_mode/widgets/outfitter_scaffold.dart`
  (`OutfitterUi`),
  `lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart`,
  `outfitter_booking_dashboard_screen.dart`,
  `outfitter_enterprise_panel_screen.dart`,
  `outfitter_package_creator_screen.dart`,
  `outfitter_price_list_screen.dart`,
  `outfitter_revenue_screen.dart`,
  `outfitter_trophy_stock_screen.dart`,
  `venison_permit_list_screen.dart`,
  `lib/features/outfitter_mode/outfitter_dashboard.dart`.
- No Firestore / Storage / rules / index / pubspec / manifest changes
  (pure presentation-layer contrast sweep).
