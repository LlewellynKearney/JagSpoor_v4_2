# JagSpoor v4.2 — Project Context & Architecture

> **Version:** 4.2 | **Platform:** Flutter / Firebase | **Currency:** ZAR (South African Rand)
> **Last Updated:** 2026-08-12

This document is the single source of truth for the current state of the JagSpoor
codebase — architecture, active feature sets, security posture, build pipeline, and
roadmap. It supersedes `PROJECT_CONTEXT.md` and `ai-context.md` for any conflicting
detail. It was reconciled against the actual source on the date above.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Role-Based Access Control & Dashboards](#2-role-based-access-control--dashboards)
3. [Marketplace & Financial Layer](#3-marketplace--financial-layer)
4. [PayFast Payment Integration](#4-payfast-payment-integration)
5. [Firestore Security Rules Overhaul](#5-firestore-security-rules-overhaul)
6. [On-Device Photo Compression Pipeline](#6-on-device-photo-compression-pipeline)
7. [FCM Push Notifications & Real-Time Indicators](#7-fcm-push-notifications--real-time-indicators)
8. [Off-Grid Navigation & Local Caching](#8-off-grid-navigation--local-caching)
9. [Tactical Hardware & Vision Pipelines](#9-tactical-hardware--vision-pipelines)
10. [Track (Spoor) Identifier](#10-track-spoor-identifier)
11. [Compliance & Documentation Exporters](#11-compliance--documentation-exporters)
12. [Firestore Collections Reference](#12-firestore-collections-reference)
13. [Cloud Functions](#13-cloud-functions)
14. [Build & CI/CD Pipeline](#14-build--cicd-pipeline)
15. [Environment & Deployment](#15-environment--deployment)
16. [Roadmap & Master To-Do](#16-roadmap--master-to-do)
17. [Project File Structure](#17-project-file-structure)

---

## 1. System Overview

JagSpoor is a multi-sided marketplace connecting South African outfitters / game
farms with hunters. It is an offline-first Flutter app backed by Firebase
(Auth, Firestore, Storage, Cloud Functions, App Check, Cloud Messaging).

**Design identity:** HUD viewport profile, tactical grid layouts, "Walnut Luxury"
and "Thermal Glow" palettes (`#0xFF8B4513`, `#0xFFC5A059`). All layouts render
inside responsive `SafeArea` viewports with dynamic bottom inset clearance to avoid
clipping behind gesture bars.

**Hardcoded financial rules:**

- **7.5% platform commission multiplier.** Every package rate and manual outfitter
  entry is multiplied by `1.075` and rounded to two decimals
  (`(value * 1.075).toStringAsFixed(2)`) before rendering on any hunter-facing
  viewport or A4 statement. See [§3](#3-marketplace--financial-layer) and
  [§4](#4-payfast-payment-integration) for the split-payment model.
- **Currency standard.** All pricing fields use the South African Rand symbol
  (`R `) exclusively. Dollar (`$`) notations are forbidden.

---

## 2. Role-Based Access Control & Dashboards

### 2.1 Outfitter Enterprise Cockpit (`outfitter_dashboard.dart`)
Six operational cards accessible only to verified master outfitters:

| Card | Function |
|------|----------|
| Manage Farms & Managers | Multi-tenant farm/manager assignment |
| Trophy Stock Inventory | Species/population management |
| Publish Hunting Package | Create/edit package listings |
| Incoming Booking Requests | Client negotiation queue |
| Financial Revenue Summary | Revenue analytics & reporting |
| Issue Game Transport Permit | PDF permit generation |

### 2.2 Farm Manager HUD (Isolation Restrictions)
- Restricts assigned manager profiles from global corporate financial dashboards,
  package editors, and revenue metrics views.
- Locks dropdown forms strictly to their assigned `farmId`.
- Enforces row-level security via Firestore rules.

### 2.3 Hunter Mode Dashboard (`hunter_dashboard.dart`)
Streamlined client view stripped of all administrative tools: field navigation,
tactical enhancement widgets, marketplace booking interface, trophy browser.

### 2.4 Authentication & 2FA (`auth_gate_service.dart`)
- **Google OAuth 2.0** federated login via Firebase Auth Google provider.
- **SMS OTP fallback** — phone-number verification with time-based one-time
  passwords.
- **Offline resilience** — cached credential validation when network is unavailable.
- **Role-gated 2FA triggering** for outfitter/enterprise accounts accessing
  sensitive dashboards.
- **Session token management** with biometric confirmation on supported devices.

> **Note:** The auth screen (`auth_screen.dart`) currently provides email/password
> sign-in and sign-up only. In-app password reset and in-app password change are
> roadmap items (see [§16](#16-roadmap--master-to-do)).

---

## 3. Marketplace & Financial Layer (Locked to ZAR)

### 3.1 Automated 7.5% Platform Commission (`package_booking_manager.dart`)
The 7.5% fee is enforced at the data layer in `PackageBookingManager`:

```dart
static const double platformCommissionRate = 0.075;
```

- **On package publish** (`publishPackage`): accepts a [PackagePricing]
  definition (all-inclusive or itemized) and computes
  `platformCommissionZAR = basePriceRands × 0.075` and
  `totalPriceZAR = basePriceRands + fee`, writing both to the package document.
- **On booking** (`bookPackage`): computes the platform split metrics and writes
  them to the booking document:
  - `basePriceRands` — the outfitter's listed base price.
  - `platformCommissionRands = basePriceRands × 0.075` — the platform commission.
  - `totalHunterPriceRands = basePriceRands + platformCommissionRands` — the gross
    amount the hunter pays (the PayFast charge amount).
  - `depositFraction = 0.25`, `depositAmountRands`, `balanceAmountRands` — the
    25% non-refundable deposit due once the outfitter approves the booking.
- Outfitters cannot book their own packages (enforced in code).

### 3.2 Split-Payment Model (Gross vs. Commission)
The booking document therefore carries the full split:

| Field | Meaning |
|-------|---------|
| `basePriceRands` | Outfitter net (gross minus commission) |
| `platformCommissionRands` | Platform's 7.5% cut |
| `totalHunterPriceRands` | Gross booking volume charged to the hunter via PayFast |
| `depositAmountRands` | 25% non-refundable deposit due on approval |
| `balanceAmountRands` | Remaining balance settled with the outfitter |

This allows revenue dashboards to report gross booking volume separately from
platform commission without re-deriving it.

### 3.3 Checkbox Itinerary Package Builder (`hunter_custom_package_builder_screen.dart`)
Hunters mix and match individual species selections and services from scanned
pricelists, with a live running-sum total. Selections persist to `/bookings` on
confirmation.

### 3.4 Unified Trophy Registry (`hunter_trophy_browser_screen.dart`)
Queries the flat root `/trophies` collection, filtering by province and stock
count, with instant cross-role synchronization (Outfitter ↔ Hunter).

### 3.5 In-App Booking Negotiation Threads (`chat_and_filter_service.dart`)
- Real-time bidirectional messaging.
- Subcollections nested at `/bookings/{bookingId}/chats`.
- Color-coded high-contrast HUD styling; per-message timestamp tracking.

---

## 4. PayFast Payment Integration

PayFast (South African payment gateway) is integrated for booking checkout, with
the server-side reconciliation handled by a Cloud Function webhook.

### 4.1 Sandbox & Checkout Launch Flow
Location: `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`.

- The hunter booking card (`_HunterBookingCard`) renders a **"Pay via PayFast"**
  button only when the booking is in a payable status
  (`pending_payment`, `pending_deposit`, or `approved`) **and** has a non-zero
  price. The price is resolved from `totalHunterPriceRands`, falling back to
  `totalPriceZAR`.
- `_initiatePayFastCheckout()` builds a PayFast sandbox URL from the booking
  details and launches it externally via `url_launcher`
  (`launchUrl(uri, mode: LaunchMode.externalApplication)`).
- **Sandbox configuration** (PayFast's published sandbox test credentials — *not*
  production secrets; replace merchant_id/merchant_key/host with live values
  before launch):

  ```dart
  const String _kPayfastSandboxHost = 'https://sandbox.payfast.co.za';
  const String _kPayfastSandboxMerchantId = '10000100';
  const String _kPayfastSandboxMerchantKey = '46f0cd694581a';
  ```

- **Booking linkage:** the Flutter client passes the Firestore booking id as
  `m_payment_id` when constructing the PayFast payment request. PayFast echoes it
  back unchanged in the ITN, allowing reconciliation.

### 4.2 ITN Webhook Handler (Cloud Function)
Location: `functions/src/index.ts` → `payfastITNHandler`.

`payfastITNHandler` is an HTTPS `onRequest` function (region `us-central1`,
public invoker) that receives PayFast's Instant Transaction Notification (ITN)
after a payment is processed. Flow:

1. **Reject non-POST** requests early (405).
2. **Signature verification** — reads the raw body for byte-exact md5 signature
   verification (`verifySignature`). Uses constant-time comparison. On failure,
   responds `200 signature_invalid` (stops retries without confirming).
3. **Server-to-server validation** — calls PayFast's `validate` endpoint
   (`validateWithPayFast`) to confirm the ITN genuinely originated from PayFast.
4. **Status processing** — only `COMPLETE` payments trigger a booking update.
5. **Booking update** — on `COMPLETE`, updates `bookings/{m_payment_id}`:
   - `status: 'Paid'`
   - `paymentTimestamp` (server timestamp)
   - `payfastpfPaymentId`
   - `itemName`, `paymentStatus`, `updatedAt`
6. **Confirmation** — returns PayFast's confirmation token (`200`) to halt
   retries. On a failed booking write it returns `500` so PayFast retries.

The function uses the Admin SDK, so it bypasses Firestore security rules
entirely. Crypto helpers live in `functions/src/payfast.ts` (signature
build/compute/verify, `validateWithPayFast` using global `fetch`). The merchant
pass phrase is read from the `PAYFAST_PASSPHRASE` environment variable.

### 4.3 Split-Payment Reconciliation
Because the booking document already carries `basePriceRands`,
`platformCommissionRands`, and `totalHunterPriceRands` (see [§3.2](#32-split-payment-model-gross-vs-commission)),
the `Paid` status set by the ITN handler marks the *gross* booking volume as
collected. The platform commission is already computed and stored, so revenue
dashboards can report gross booking volume vs. platform commission directly from
the Firestore fields without any additional calculation at payment time.

---

## 5. Firestore Security Rules Overhaul

Location: `firestore.rules`. The rules were hardened with ownership scoping,
public marketplace reads, and two-party booking access. A default-deny catch-all
remains in force.

### 5.1 Helper Functions
- `isSignedIn()`, `isAdmin()` (custom claim `admin == true`),
  `isOutfitter()` (custom claim `role == 'outfitter'`).
- `isOwnerOf(ownerField)` — true when the caller's uid matches the document's
  owner field. Works for both existing docs (`resource`) and creates
  (`request.resource.data`).
- `ownerOrAdmin(ownerField)` — admin OR owner.
- `isBookingParty()` / `isBookingPartyViaParent(parentPath)` — true when the
  caller is the hunter or outfitter on a booking (the parent variant looks up the
  parent booking via `get()` for nested subcollections).

### 5.2 Public Read Accessibility (Marketplace Browsing)
To allow marketplace browsing without leaking private data:

| Collection | Read | Write |
|------------|------|-------|
| `animals` | **public** (`true`) | admin only |
| `packages` | any signed-in user | owning outfitter only (`outfitterId == auth.uid`) |
| `trophies` | any signed-in user | owner (hunter via `ownerId`/`hunterId`/`userId`, or outfitter via `outfitterId`) or admin |

> `trophies` is a dual-purpose collection: hunter personal trophies (Digital
> Trophy Room, stamped `ownerId`) and outfitter trophy stock (marketplace
> listings, stamped `outfitterId` with `availableCount`). Read is open to signed-in
> users so the Trophy Registry & marketplace can display outfitter stock; writes
> are restricted to the owning party or admin.

### 5.3 Strict Owner-Scoping (Private Collections)
These private collections use `ownerOrAdmin(...)` so only the owner (or an admin)
may read or write:

| Collection | Owner field |
|------------|-------------|
| `firearms` | `ownerId` |
| `firearms/{id}/ammunition` (nested) | parent firearm `ownerId` (or own `ownerId`) |
| `trophies` (write) | `ownerId` / `outfitterId` / `hunterId` / `userId` |
| `carcass_logs` | `hunterId` |
| `waypoints` | `hunterId` |
| `license_applications` | `hunterId` |
| `ammunition` (top-level; read = signed-in) | `ownerId` (write) |
| `spoor_scans` | `userId` |
| `transport_permits` | `outfitterId` |
| `scanned_pricelists` | `outfitterId` |
| `records` | `ownerId` |

### 5.4 Two-Party Scoping (Bookings & Chats)
`bookings/{bookingId}`:
- **Read:** hunter who placed the booking OR outfitter who owns the package
  (`isBookingParty()`).
- **Create:** the hunter placing it (`hunterId == auth.uid`).
- **Update:** the outfitter may flip the `status` field only
  (`statusUpdateAllowed()` requires `outfitterId == auth.uid` and freezes
  `hunterId`/`outfitterId`). Either party may update non-status fields (status
  frozen). This prevents a hunter from self-approving their own booking.
- **Delete:** admin only.
- The PayFast ITN Cloud Function uses the Admin SDK, so it bypasses these rules.

`bookings/{bookingId}/chats/{chatId}` (nested negotiation subcollection):
- **Read/write:** restricted to the two booking parties via
  `isBookingPartyViaParent()` (parent-doc lookup).

### 5.5 Operational & Admin Collections
- `farms` — read for signed-in; create/update/delete owner outfitter or admin.
- `farm_managers` — scoped to issuing outfitter.
- `lodging`, `fleet` — read for signed-in (marketplace availability); write for
  outfitters/admin.
- `outfitters/{uid}` — read for signed-in; create = admin; update/delete = admin
  or owner. Created by the `adminCreateOutfitter` Cloud Function.
- `users` — read for signed-in; write = owner.
- `managers`, `units` — read for signed-in; write = admin.
- `assets` — read for signed-in; write = admin or owner.
- Legacy nested `outfitter/bookings`, `outfitter/lodging`, `outfitter/fleet` —
  outfitter/admin only.

---

## 6. On-Device Photo Compression Pipeline

Location: `lib/core/services/image_service.dart`.

`ImageService` is the centralized image picking + compression + Firebase Storage
upload service. All user-generated photos route through it so images are
consistently downscaled and JPEG-compressed before upload, keeping Storage usage
and Firestore document sizes small.

### 6.1 Compression Specification
- **Library:** `flutter_image_compress` (^2.3.0).
- **Target dimensions:** 1280×1280 (downscaled to fit via `minWidth`/`minHeight`).
- **Quality:** 75% JPEG (`CompressFormat.jpeg`).
- Compressed files are written to the app temp directory and uploaded with
  `SettableMetadata(contentType: 'image/jpeg')`.

### 6.2 Public API
- `pickAndCompressImage({source, quality=75, minWidth=1280, minHeight=1280})` —
  pick + compress, returns a `File?`.
- `compressExisting(File, ...)` — compress an already-picked file in place (for
  multi-image pickers).
- `uploadCompressedPhoto({imageFile, storagePath})` — upload to Storage, returns
  the download URL.
- `pickCompressAndUpload(source, storagePath, ...)` — pick + compress + upload in
  one call.

On compression failure or a null result, the service gracefully falls back to the
original file (never silently drops an upload).

### 6.3 Centralized Photo Pipeline
`ImageService` is the single entry point for photos across: profiles, trophies,
firearms, pricelists, and package listings.

### 6.4 Raw Image Inputs Preserved
Two vision pipelines deliberately bypass the compression pipeline to preserve
full fidelity:

- **PDF417 license scanning** (`license_scanner_screen.dart`) uses `mobile_scanner`
  with `BarcodeFormat.pdf417` and operates on the raw barcode bytes
  (`barcode.rawBytes` / `rawValue`). The scanner reads the live camera stream and
  can also `analyzeImage(file.path)` on a picked photo — neither path goes through
  `ImageService`, so the high-density barcode data is not degraded by JPEG
  downscaling.
- **AI spoor classification** (`SpoorAIService`) takes a raw `XFile` directly
  (`predictSpoor(XFile imageFile)`) and prepares its own model-input tensor. It
  does not use `ImageService` compression, preserving the full-resolution image
  needed for morphological classification.

---

## 7. FCM Push Notifications & Real-Time Indicators

### 7.1 Cloud Function Firestore Triggers (FCM)
Location: `functions/src/index.ts`.

Two Firestore triggers broadcast Firebase Cloud Messaging (FCM) push
notifications. Both resolve the recipient as the "other" party in a booking and
read the recipient's FCM tokens from their `users/{recipientId}` document (via
`extractFcmTokens`, which supports both array and map token storage shapes).
Notifications are sent with `android.priority: "high"`. FCM failures are logged
and never crash a trigger.

- **`onNewChatMessage`** — `onDocumentCreated` on
  `bookings/{bookingId}/chats/{chatId}`. When a chat message is created it
  notifies the party that did *not* send the message (recipient = whichever of
  `hunterId`/`outfitterId` is not the `senderId`).
  - Title: `"New Message on JagSpoor"`
  - Body: the message text (truncated to 100 chars)
  - Data: `{ bookingId, type: "chat" }`

- **`onBookingUpdated`** — `onDocumentUpdated` on `bookings/{bookingId}`. Fires
  only when the `status` field changes between before/after snapshots. The
  recipient is the "other" party: if `updatedBy == hunterId`, alert the outfitter;
  otherwise (outfitter or system, e.g. the PayFast ITN webhook) alert the hunter.
  When `updatedBy` is absent the hunter is alerted by default.
  - Title: `"Booking Status Update"`
  - Body: mapped via `bookingStatusBody()` — e.g. `"Your booking is now Paid!"`,
    `"Your booking has been approved!"`, `"Your booking has been declined."`
  - Data: `{ bookingId, type: "booking" }`

### 7.2 Dynamic Unread Message Envelope Icons
Both hunter and outfitter booking cards render a dynamic unread indicator driven
by per-party boolean flags on the booking document. The `Icons.mail` icon is
highlighted orange when there are unread messages, grey otherwise.

- **Hunter side** (`hunter_package_marketplace_screen.dart`,
  `_buildUnreadMailIndicator()`): reads `booking.hunterHasUnread`.
- **Outfitter side** (`outfitter_booking_dashboard_screen.dart`,
  `_buildUnreadMailIndicator()`): reads `booking.outfitterHasUnread`.

These flags are written by the chat layer as messages are exchanged, giving both
parties a real-time visual cue of unread negotiation messages on their booking
cards.

---

## 8. Off-Grid Navigation & Local Caching Infrastructure

### 8.1 Offline Sync Queue Manager (`offline_sync_queue.dart`)
Local SQLite fallback transaction engine. Buffers waypoints, carcass logs, and
targets during connectivity loss with no telemetry drops; auto-syncs when the
connection is restored.

### 8.2 Topographic Breadcrumb Path Tracer (`map_path_tracer.dart`)
Continuous location tracking streaming from `Geolocator`, overlaid on offline
topographic vector map layers, with blood-spoor trail support.

### 8.3 Carcass-to-Waypoint Auto-Pinning
Captures the current high-accuracy GPS position (falling back to the last known
breadcrumb vector node) and binds it atomically into carcass harvest matrix forms
and the waypoint collection.

### 8.4 Time-Series Radius Filtering Toolbar (`offline_navigation_screen.dart`)
Sliding diagnostic panel computing offline Haversine distance geometry and
timestamp age deltas, clearing map-canvas clutter automatically.

---

## 9. Tactical Hardware & Vision Pipelines

### 9.1 BLE Laser Rangefinder Telemetry Bridge (`advanced_tactical_service.dart`)
Couples phone magnetic-compass heading streams (`flutter_compass`) with Bluetooth
rangefinder GATT notifications, projecting precise target markers along the
hunter's line of sight. Entirely offline; auto-syncs projected targets to the
`OfflineSyncQueue`.

### 9.2 Hardware-Driven Activity Forecaster HUD (`network_diagnostic_hud.dart`)
Binds to the barometric pressure sensor, runs overhead solunar transit
calculations, and streams a dynamic game-movement probability ticker. Metrics:
pressure (hPa), weather condition, moon phase %, SOLUNAR badge.

### 9.3 Predator Ironbow Pseudo-Thermal Shader (`blood_tracker_screen.dart`)
False-color matrix color filter shader that suppresses green/brown foliage
wavelengths, amplifies luminance deltas, and makes blood-drop trails pop in neon
orange/yellow.

### 9.4 Ballistic Scope Calibration & Reticle HUD (`scope_calibration_screen.dart`)
Offline point-mass ballistic calculator with rifle drag-profile parsing (G1/G7),
scope click-value inputs (MOA/MIL/IPHY), barometric corrections, laser distance
telemetry, and an interactive turret-click dial HUD (elevation, windage, DOPE
card history, zero-range marker).

### 9.5 Ballistic Trajectory Solver Engine (`ballistic_solver_service.dart`)
Central offline engine: point-mass trajectory with gravity, slant-range cosine
angle corrections, air-density factor from barometric pressure, MOA/MRAD
conversion with integer click-count output, effective-range estimation, and
trajectory-table generation for DOPE cards.

### 9.6 Vital Zone Anatomy HUD Overlay (`vital_zone_painter.dart`)
Vector-drawn species-specific anatomical overlays (heart/lung/skeletal zones) for
SA game, with color-coded zone highlighting, distance-scaled sizing, and
shot-angle compensation (quartering-away/quartering-toward skew via lateral
transformation matrices).

---

## 10. Track (Spoor) Identifier

Location: `lib/features/track/`.

On-device AI spoor classification using TensorFlow Lite:
- `SpoorAIService` (`data/services/spoor_ai_service.dart`) loads a
  `spoor_classifier.tflite` model (input size 224×224) and a `labels.txt` from
  assets. Falls back to **mock mode** if the model fails to load.
- `predictSpoor(XFile)` returns a classification map. A confidence threshold
  (`0.5`) filters low-certainty predictions.
- Presentation: `spoor_detection_hud_screen.dart` (capture HUD) and
  `classification_result_widget.dart` (result display).

> **Roadmap:** the spoor identifier's accuracy is slated for an overhaul — see
> [§16](#16-roadmap--master-to-do).

---

## 11. Compliance & Documentation Exporters

### 11.1 A4 PDF Manifest Generators

| Exporter | Document Type | Output |
|----------|--------------|--------|
| `outfitter_invoice_exporter.dart` / `invoice_pdf_service.dart` | ZAR-locked billing statements | A4 PDF |
| `transport_permit_pdf_exporter.dart` / `transport_permit_manager.dart` | SA Game Transport Certificates | A4 PDF |
| `saps_pdf_generator.dart` | SAPS license application docs | PDF |

### 11.2 Digital Finger-Drawing Signature Canvas (`signature/`)
High-fidelity local canvas capturing the landowner's handwritten signature,
burned directly onto the transport-permit PDF, with native system sharing.

---

## 12. Firestore Collections Reference

Project ID: `jagspoor`. Full schemas are in `FIREBASE_COLLECTIONS.md`; the
high-level map and current access posture:

| Collection | Purpose | Access posture |
|------------|---------|----------------|
| `users` | Profiles & roles | signed-in read; owner write |
| `outfitters/{uid}` | Outfitter profiles | signed-in read; admin create; admin/owner update |
| `animals` | Wildlife species DB | **public read**; admin write |
| `packages` | Hunting packages + 7.5% fee | signed-in read; owning outfitter write |
| `bookings` | Client bookings | two-party (hunter + outfitter); status = outfitter only |
| `bookings/{id}/chats` | Negotiation messages | two-party via parent lookup |
| `trophies` | Trophy registry + stock | signed-in read; owner write |
| `firearms` (+ nested `ammunition`) | Firearms inventory | owner-scoped |
| `ammunition` (top-level) | Ammo inventory | signed-in read; owner write |
| `license_applications` | SAPS licenses | owner-scoped (`hunterId`) |
| `transport_permits` | Game transport permits | owner-scoped (`outfitterId`) |
| `carcass_logs` | Carcass tracking | owner-scoped (`hunterId`) |
| `waypoints` | GPS markers | owner-scoped (`hunterId`) |
| `spoor_scans` | Track analysis records | owner-scoped (`userId`) |
| `scanned_pricelists` | AI-scanned price lists (7.5% fee split) + history log | owner-scoped (`outfitterId`); indexed `outfitterId+status+createdAt` for the history stream |
| `records` | Generic records | owner-scoped (`ownerId`) |
| `farms` / `farm_managers` | Farm entities | signed-in read; outfitter/admin write |
| `lodging` / `fleet` | Operational assets | signed-in read; outfitter/admin write |
| `factory_ammunition` / `bullets` / `propellants` | Ballistics catalog | signed-in read; admin write |
| `managers` / `units` / `assets` | Admin-managed | signed-in read; admin/owner write |

**Required indexes** are declared in `firestore.indexes.json`, including the
`bookings` composites `outfitterId ASC + bookingTimestamp DESC` and
`hunterId ASC + bookingTimestamp DESC`.

---

## 13. Cloud Functions

Location: `functions/` (TypeScript, `firebase-functions` v2 API, Node 22 runtime).
Build: `cd functions && npm run build` → emits `functions/lib/`. Four exported
functions, all region `us-central1`:

| Function | Type | Purpose |
|----------|------|---------|
| `payfastITNHandler` | HTTPS `onRequest` (public) | PayFast ITN: signature verify → server validation → mark booking `Paid`. Uses `PAYFAST_PASSPHRASE` env var. |
| `adminCreateOutfitter` | `onCall` (admin claim required) | Creates Auth user (Admin SDK, does NOT log out caller), writes `/outfitters/{uid}`, sets `{ role: 'outfitter' }` claims. Rolls back on failure. |
| `onNewChatMessage` | Firestore `onDocumentCreated` (`bookings/{id}/chats/{chatId}`) | FCM push to the non-sender booking party on new chat message. |
| `onBookingUpdated` | Firestore `onDocumentUpdated` (`bookings/{id}`) | FCM push to the "other" party when booking `status` changes. |

Helpers: `functions/src/payfast.ts` (signature build/compute/verify,
`validateWithPayFast`), `functions/src/firebase.ts` (Admin SDK init).

---

## 14. Build & CI/CD Pipeline

### 14.1 Android
- `minSdk = 23` (set in `android/app/build.gradle` — required by Firebase App
  Check and other Firebase plugins).
- Java 17 (Temurin) in CI.

### 14.2 iOS
- Deployment target **15.5.0**, set consistently in:
  - `ios/Podfile` (`platform :ios, '15.5'`)
  - `ios/Runner.xcodeproj/project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET = 15.5`,
    all configs)
  - This satisfies the `mobile_scanner` (^6.0.11) minimum.

### 14.3 Flutter SDK
- Pinned to **Flutter 3.29.1 stable / Dart 3.7.0** (matches the CI pin in
  `.github/workflows/build-and-deploy.yml` and satisfies `sdk: ^3.6.0`).

### 14.4 CI/CD Workflow (`.github/workflows/build-and-deploy.yml`)
Triggered on push to `main` and manual `workflow_dispatch`.

- **`build-android`** (ubuntu, Java 17, Flutter 3.29.1): `flutter pub get` →
  `flutter build apk --debug` → upload `app-debug.apk` artifact.
- **`build-ios`** (macos, Flutter 3.29.1): `flutter pub get` →
  `flutter build ios --simulator --no-codesign` → upload iOS artifact.
- **`deploy-firebase`** (ubuntu, needs build-android, main-only,
  `continue-on-error: true`): rebuilds the APK and uploads to Firebase App
  Distribution via `wzieba/Firebase-Distribution-Github-Action@v1` (service
  account credentials + tester emails from secrets; release notes from commit).
  Best-effort: missing secrets fail the job without failing the workflow.
- **`notify`**: sends a Discord notification when a `DISCORD_WEBHOOK` repo
  variable is set.

---

## 15. Environment & Deployment

### 15.1 Sandbox Constraints (this development environment)
- `firebase-tools` v15.26.0 installed locally (`npx firebase-tools`); not global.
- **No Firebase credentials available** — `FIREBASE_TOKEN` / service account
  absent; `firebase projects:list` returns 401. Deployment must run in an
  environment with `firebase login` or `FIREBASE_TOKEN` set.
- **No Java/JVM** in the sandbox — the Firestore emulator cannot run, so
  `@firebase/rules-unit-testing` cannot execute here. Rules were validated
  structurally (JSON valid, default-deny present, `tsc` clean) but not via
  emulator integration tests.
- PayFast signature logic was unit-tested in isolation (round-trip + tamper
  detection pass).

### 15.2 Deploy Commands (when credentials available)

```bash
cd /workspace/project/JagSpoor_v4_2
(cd functions && npm install && npm run build)
npx firebase-tools deploy --only functions,firestore:rules,firestore:indexes,storage
# Includes: bookings/farms/trophies/scanned_pricelists composite indexes +
# trophy_photos storage rules + hardened firestore.rules.
# Set PayFast passphrase:
npx firebase-tools functions:set PAYFAST_PASSPHRASE=...
```

### 15.3 Security Notes
- PayFast sandbox credentials in `hunter_package_marketplace_screen.dart` are
  PayFast's published sandbox test values, not production secrets. Replace with
  live merchant credentials before launch (and move them off the client into a
  server-generated payment request for production).
- Firestore rules enforce default-deny; Storage rules scope writes per owner uid.
- `PAYFAST_PASSPHRASE` is a server-side env var, never bundled into the client.

---

## 16. Roadmap & Master To-Do

Active roadmap items, in priority order:

### 16.1 Superuser / Admin Portal & Master Analytics Dashboard ✅ Implemented
A dedicated admin surface (Phase 2, implemented 2026-08-12) for platform-wide
oversight. Located in `lib/features/admin/`:
- **Admin authorization guard** (`services/admin_auth_guard.dart`) — resolves
  admin status via the `admin == true` custom claim OR `users/{uid}.role ==
  'admin'` OR `outfitters/{uid}.role == 'admin'`, with an
  `admin@jag-spoor.co.za` bootstrap allow-list. Cached and refreshable.
- **Master analytics dashboard** (`screens/admin_dashboard_screen.dart`) —
  Entity Overview (Total Outfitters, Active Hunters, Listed Packages, Active
  Bookings, Total Trophies), Financial Analytics (daily/weekly/monthly/yearly
  gross booking revenue vs. platform commission, in ZAR), and User Engagement
  (registered users + active sessions).
- **Manual account creation** (`screens/create_user_screen.dart`) — form-driven
  provisioning of hunter/outfitter Firestore documents + password reset email.
- **Bulk CSV importer** (`screens/bulk_csv_import_screen.dart`) — sequential
  CSV import with a summary log ("Successfully imported X accounts, Y errors").
- Entry point: the role-selection screen conditionally renders an "ADMIN PORTAL"
  card for authorized admins; the dashboard also re-checks the guard on entry.
- Backed by the existing `admin` custom claim and Firestore rules
  (`outfitters/{uid}` create = admin).

### 16.2 In-App Password Reset & In-App Password Change
The auth screen currently supports email/password sign-in and sign-up only. Add:
- In-app password reset (send password reset email / inline flow).
- In-app password change for authenticated users (reauthenticate → update
  password), with proper validation and error handling.

### 16.3 Track (Spoor) Identifier Accuracy Overhaul
Improve `SpoorAIService` classification reliability:
- Morphological feature classification beyond raw image embedding.
- Confidence scoring with calibrated thresholds and low-confidence fallback
  guidance.
- Expanded label set and model retraining for SA game tracks.

### 16.4 Scope Settings & Tools Redesign
State-of-the-art redesign of `ScopeToolsBottomSheet` / scope tooling:
- MOA/MRAD click calculators.
- Height-over-bore compensation.
- Tracking-test loggers (zero-confirmation and group-size recording).

### 16.5 Dynamic In-App Info Tooltips `(i)` & Global Theme/HUD Verification
- Add contextual `(i)` info tooltips across screens for in-app guidance.
- Global pass to verify theme/HUD consistency (colors, safe-area insets, HUD
  styling) across all viewports.

---

## 17. Project File Structure

```
lib/
├── core/
│   ├── services/
│   │   ├── image_service.dart              # Centralized photo compression + upload
│   │   └── bluetooth_mesh_sync_service.dart
│   ├── theme/app_theme.dart                # Unified HUD styling system
│   └── splash_screen.dart
├── features/
│   ├── auth/
│   │   ├── auth_screen.dart                # Email/password sign-in + sign-up
│   │   ├── role_selection_screen.dart
│   │   └── screens/privacy_policy_screen.dart
│   ├── authentication/services/auth_gate_service.dart   # Google OAuth + SMS OTP 2FA
│   ├── ballistics/
│   │   ├── data/
│   │   │   ├── scope_calculator.dart       # MOA/MRAD + gyro holdover engine
│   │   │   ├── caliber_normalizer.dart
│   │   │   ├── inventory_bridge.dart
│   │   │   ├── services/ballistics_seeder.dart
│   │   │   └── models/{rifle_profile,saps_application_model}.dart
│   │   └── presentation/
│   │       ├── ballistic_calc_screen.dart
│   │       ├── scope_tools_bottom_sheet.dart
│   │       ├── ammunition_screen.dart
│   │       ├── ammunition_type_selection_screen.dart
│   │       └── widgets/signal_hud_widget.dart
│   ├── firearm_safe/                       # Firearms inventory
│   ├── game_guide/                         # SA Game Guide (animals)
│   ├── hunter_mode/
│   │   ├── screens/
│   │   │   ├── hunter_package_marketplace_screen.dart   # PayFast checkout + booking cards
│   │   │   ├── outfitter_booking_dashboard_screen.dart  # Outfitter booking queue
│   │   │   ├── license_scanner_screen.dart              # PDF417 mobile_scanner
│   │   │   └── ...
│   │   ├── services/
│   │   │   ├── package_booking_manager.dart             # 7.5% commission split
│   │   │   ├── chat_and_filter_service.dart             # Negotiation threads + Haversine
│   │   │   └── ...
│   │   └── ...
│   ├── outfitter_mode/
│   │   ├── outfitter_dashboard.dart                     # Enterprise cockpit
│   │   ├── presentation/{add_booking_sheet,lodge_booking_screen,manual_invoice_screen,slaghuis_matrix_screen}.dart
│   │   └── data/{models,services}/...
│   ├── shared/firebase/                  # Firebase config
│   └── track/                            # Spoor identifier (TFLite)
│       ├── data/services/spoor_ai_service.dart
│       └── presentation/{spoor_detection_hud_screen,classification_result_widget}.dart
├── models/animal.dart
├── repositories/animal_repository.dart
├── services/{ballistics_calculator,location_resolver_service}.dart
├── utils/{animal_seeder,image_helper}.dart
├── image_utils.dart
├── firebase_options.dart
└── main.dart

functions/                                # Cloud Functions (TypeScript, Node 22)
├── src/
│   ├── index.ts                          # payfastITNHandler, adminCreateOutfitter, FCM triggers
│   ├── payfast.ts                        # PayFast signature + validation helpers
│   └── firebase.ts                       # Admin SDK init
├── package.json
└── tsconfig.json

firestore.rules          # Hardened owner-scoped + two-party rules (default-deny)
firestore.indexes.json   # Composite indexes (incl. bookings)
storage.rules            # Per-owner write scoping
firebase.json            # firestore + storage + functions (nodejs22) config
.github/workflows/build-and-deploy.yml   # Android + iOS build + Firebase App Distribution
```

---

*Reconciled against source: 2026-08-12 | JagSpoor v4.2*
