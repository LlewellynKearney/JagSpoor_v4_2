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

### 9.7 Shot Group Target Analyzer (`shot_group_analyzer_screen.dart`)
A calibrated computer-vision + geometry pipeline (replaces the legacy mock
analyzer) for diagnosing rifle precision on a straight-on target photo. Location:
`lib/features/hunter_mode/` (service `shot_group_analyzer_service.dart`, overlay
`widgets/shot_group_target_overlay.dart`, screen
`screens/shot_group_analyzer_screen.dart`).

- **Real shot-hole detection**: dark-blob detection (luminance threshold +
  4-connected-component labelling on a sampled grid) with circularity / size
  gates that reject dust specks, the reference coin, and text strokes; each
  accepted blob's centroid becomes a `ShotImpact` in full-resolution pixel
  coordinates.
- **Scale calibration** via a user-placed two-point `ScaleReference`
  (`pxPerMm = pixelLength / knownLengthMm`); reference length is user-editable
  (defaults: 5-Rand coin 26 mm, 1-inch grid 25.4 mm).
- **Group geometry**: extreme spread (max pairwise distance + contributing
  shot pair), mean radius (avg distance from the center of impact), and
  center-of-impact offset from a marked point of aim — all calibrated, with
  physically-exact angular conversions (1 MOA = 1.047" @100 yd; 1 MIL =
  3.6" @100 yd; yards or meters).
- **Suggested turret correction**: converts the COI offset to clicks at the
  scope's per-click value, applying the opposite-direction dial convention.
- **Firearm linking**: a `DropdownButtonFormField` populated strictly from the
  Digital Firearm Safe (`InventoryBridge.watchSafeFirearms()` stream), rendered
  as "make model (calibre)" via `RifleProfile.displayName`. The selected
  firearm's id + label snapshot travel with the saved session.
- **Offline session logging**: a completed analysis can be saved to the local
  SQLite `target_session_logs` table (`TargetSessionLogManager`) — firearm
  linkage, shot geometry, suggested clicks, and precision category — so a
  hunter can review historical precision diagnostics off-grid. The table is
  created/migrated by `LocalDatabaseService` (DB version 4).
- **UI / accessibility**: theme-aware high-contrast colours throughout (the
  low-contrast amber stat/click labels were replaced with the theme accent
  against card backgrounds); `SafeArea` + `SafeBottomInset` scroll padding so
  bottom controls / the system nav bar never clip content; the floating
  capture buttons are `SafeArea`-wrapped.

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
| `venison_permits` | Legal SA venison / game transport & hunt permits (dual signatures) | two-party (hunter + outfitter) read; signed-in create; outfitter/admin update+delete; indexed `outfitterId+createdAt` and `hunterId+createdAt` |
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
  `permit_signatures/{permitId}/{fileName}` permits any authenticated user to
  write (dual-party permit signatures); reads are globally authenticated-read.
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
- **Firearm-link dropdown** (implemented, fixed 2026-08-15): the Optical
  Suite's "Link to Firearm" `DropdownButtonFormField` now binds correctly to
  the Digital Firearm Safe stream (`InventoryBridge.watchSafeFirearms`) and
  reflects the freshly-selected rifle on every rebuild. The root cause of the
  "dropdown doesn't update after selection" bug was that
  `DropdownButtonFormField` is a `FormField` whose internal state is seeded
  from the first `value` and ignores changed `value`s on rebuild; a
  `ValueKey(effectiveValue)` now forces a clean reinitialise on every
  selection change. Saved profiles persist the `OpticProfile.firearmId`
  binding on the `firearms` doc.

### 16.5 Dynamic In-App Info Tooltips `(i)` & Global Theme/HUD Verification
- Add contextual `(i)` info tooltips across screens for in-app guidance.
- Global pass to verify theme/HUD consistency (colors, safe-area insets, HUD
  styling) across all viewports.

### 16.6 Digital Trophy Room native image sharing (implemented 2026-08-15)
The Trophy Room share button (grid card + detail screen AppBar) now shares the
**actual trophy photo file** alongside the formatted harvest-dispatch text via
`Share.shareXFiles` (`trophy_share_composer.dart`):
- `TrophyShareComposer.firstPhotoPath` extracts the first usable entry from the
  trophy doc's `photos` list.
- `resolveShareFile` resolves it to a local `File`: a local path is used
  directly; a remote (Firebase Storage) URL is downloaded to a temp file via
  `http` so `share_plus` can attach it.
- `shareTrophy` attaches the image + the composed text caption + subject via
  `Share.shareXFiles`; when no photo resolves it falls back to text-only
  `Share.share` (legacy/empty-photo entries still share).

### 16.7 Factory ammunition pre-population from the bundled asset catalog (implemented 2026-08-15)
- `FactoryAmmoProfile` (brand, caliber, grain, description, bc, muzzle
  velocity) + a `displayLabel` helper.
- `FactoryAmmunitionRepository` singleton: `loadAll()` reads + caches the CSV
  once (process-lifetime cache); `getProfilesForCaliber(caliber)` returns the
  matching profiles using a strict, synonym-aware matcher.
- Caliber matching (`matchesCaliber`): exact normalized equality → curated
  `CaliberNormalizer` variant set membership → boundary-aware bidirectional
  contains. The boundary check rejects digit-adjacent false positives (e.g.
  `9mm` no longer matches `7.62x39mm`'s `39mm` suffix). A `_canonicalize` step
  maps regional/commercial synonyms the curated normalizer does not enumerate
  (`9mm Par` / `9mm Parabellum` → `9mm Luger`; `7.62 Soviet` → `7.62x39mm`).
- The screen's `StreamBuilder<QuerySnapshot>` over `factory_ammunition` was
  replaced with a `FutureBuilder<List<FactoryAmmoProfile>>` over the
  repository (caliber-keyed cache so re-opening the form does not re-read the
  asset). The Firestore `factory_ammunition` seed (`BallisticsSeeder`) is
  unchanged — it remains the server-side catalog for any non-screen consumers;
  the repository is the screen's authoritative offline-first source.

### 16.8 Outfitter Mode refactor — AI price-list quantity limits, per-farm cost config, per-farm PayFast routing (implemented 2026-08-15)
- **AI price-list scanner — quantity limits**: `PricelistItem` gained a
  `quantityLimit` (`int?`) field. The parser now extracts the limit from
  common SA price-list notations (`x3`, `max 5`, `qty 2`, `(3 avail)`,
  `5 available`) and pops the token **before** price extraction so the qty
  digit is not swallowed by the greedy price matcher. The Gemini Vision
  instruction prompt now explicitly asks for `quantityLimit` (max animals
  available/allowed per line, or null). `GeminiResultNormalizer` carries
  `quantityLimit` (plus `quantityAvailable`/`maxQuantity`/`qty`/`available`
  aliases) through structured JSON. The limit is persisted in
  `scanned_pricelists.items[].quantityLimit` (verification screen +
  `_itemToExtractedMap`).
- **Per-farm hunting catalog**: `FarmHuntingCatalog` (+ `FarmAnimalListing`
  + `FarmFeeListing`) is a pure transformation of a `scanned_pricelists` doc
  that groups items into animals (species, sex/class, trophy size tier, price
  per animal, quantity limit) and fees (daily/accommodation/vehicle/etc.).
  `PricelistScannerService.getFarmHuntingCatalog(farmId)` returns it for the
  farm's most-recent active price list (readable by signed-in hunters).
- **Per-farm cost config**: `FarmCostConfig` (daily rate per hunter /
  observer, accommodation/night, catering/day, vehicle fee, guide fee, plus
  a free-form `extraOptions` list) is persisted as a nested `costConfig` map
  on the `farms/{farmId}` document via
  `OutfitterEnterpriseManager.updateFarmCosts`. The Edit Farm sheet in the
  Enterprise Control Panel gained a "COST RATES (PACKAGE BUILDER)" section
  editing all six rate fields.
- **Per-farm PayFast routing**: `FarmPayFastProfile` (merchant id, merchant
  key, passphrase, live-vs-sandbox toggle) is persisted as a nested
  `payfastProfile` map on the farm document via
  `OutfitterEnterpriseManager.updateFarmPayFastProfile` /
  `clearFarmPayFastProfile` / `getFarmPayFastProfile`.
  `PayfastCheckout.resolveEndpoint(profile)` routes the deposit to the farm's
  merchant account when `isConfigured`, otherwise the platform default
  sandbox. The Custom Package Builder's `_payDeposit` resolves the farm's
  profile and passes it to `PayfastCheckout.launchDeposit`, so deposits for
  custom packages route directly to the outfitter's PayFast account. A
  `PayfastCheckout.openPayFastRegistration()` helper + an Edit Farm "Register
  a new PayFast account" button link to the PayFast merchant-application
  page.
- **Custom Package Builder — quantity capping**: the per-line quantity
  stepper's `+` button is disabled (and a `max N` chip is shown) when the
  selected quantity reaches the line's `quantityLimit`, so a hunter cannot
  book more animals than the outfitter has available. The booked
  `quantityLimit` is carried through `_collectSelected` onto the booking doc
  for outfitter visibility.
- **Security note**: the per-farm PayFast merchant key + passphrase are
  credentials stored on the owner-scoped farm document. For a production
  hardening pass, prefer a Cloud Function that holds the passphrase
  server-side and signs the PayFast request server-to-server; this MVP
  enables the direct-routing requested. `firestore.rules` already permits
  the owning outfitter to update `farms/{farmId}` (so `updateFarmCosts` /
  `updateFarmPayFastProfile` / `clearFarmPayFastProfile` succeed) and signed-
  in hunters to read `farms` (so `getFarmPayFastProfile` resolves); no rules
  change is required.
- **Tests**: `test/farm_config_test.dart` (33 new, all pass) —
  `FarmCostConfig` empty/toMap/fromMap/copyWith/round-trip,
  `FarmPayFastProfile.isConfigured`/toMap/fromMap,
  `PayfastCheckout.resolveEndpoint` (default sandbox, farm sandbox, farm live,
  not-configured fallback), `buildReturnUrl` encoding,
  `FarmHuntingCatalog.fromPricelist` (animal/fee split, hunterPrice
  derivation, qty-limit collapse on null/zero/negative/string, empty),
  `PricelistTextParser` quantity extraction (`x3`/`max 5`/`(2 avail)`/`5
  available`/none/label-stripped), `GeminiResultNormalizer` quantityLimit
  carry-through. Full suite 534 pass (was 501; +33; no regressions).
- Files: `lib/features/hunter_mode/models/farm_config.dart` (catalog models
  added; cloud_firestore import removed as unused),
  `lib/features/hunter_mode/services/pricelist_text_parser.dart`
  (`quantityLimit` field + `_popQuantityLimit` order fix + Gemini
  normalizer `_toQuantityLimit`),
  `lib/features/hunter_mode/services/gemini_vision_extractor.dart`
  (instruction asks for `quantityLimit`),
  `lib/features/hunter_mode/services/pricelist_scanner_service.dart`
  (`_itemToExtractedMap` persists `quantityLimit`; `getFarmHuntingCatalog`
  added),
  `lib/features/hunter_mode/screens/outfitter_pricelist_verification_screen.dart`
  (`quantityLimit` persisted on save),
  `lib/features/hunter_mode/services/outfitter_enterprise_manager.dart`
  (`updateFarmCosts` / `updateFarmPayFastProfile` /
  `clearFarmPayFastProfile` / `getFarmPayFastProfile`),
  `lib/core/services/payfast_checkout.dart` (`resolveEndpoint` +
  `PayFastEndpoint` + per-farm `launchDeposit` + `openPayFastRegistration` +
  `payfastRegistrationUrl`),
  `lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart`
  (Edit Farm sheet: Cost Rates section + PayFast Profile section + Register
  button + `_parseOptDouble` / `_sectionHeader` helpers),
  `lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart`
  (qty-limit cap + `quantityLimit` carry-through + per-farm PayFast deposit
  routing),
  `test/farm_config_test.dart` (NEW, 33 tests).

### 16.9 Bug Report screenshot attachments (implemented 2026-08-15)
- The in-app Bug Report modal (`BugReportModal`) now supports up to **5
  screenshot attachments** as visual proof. Two entry points were added to
  the form: **Take Photo** (native camera via `image_picker.pickImage`,
  `ImageSource.camera`, `maxWidth/maxHeight: 1920`, quality 85) and **Add
  from Gallery** (`image_picker.pickMultiImage`, quality 80, `limit` = the
  remaining slots). Both are gated by a `_canAddScreenshot` cap so a reporter
  cannot exceed the maximum; the cap is also re-checked after the multi-pick
  returns in case the picker ignored `limit`.
- Picked images render as a **horizontal thumbnail strip** (96×96, rounded)
  with a per-image remove button (circular close badge), so the reporter can
  preview and remove attachments before submission. A broken-image fallback
  renders for an undecodable file.
- On submit, each attached `XFile` is **compressed** through the central
  `ImageService.compressExisting` (1280px, JPEG q75) and **uploaded** to
  Firebase Storage at
  `bug_report_attachments/{userId}/{timestamp}_{i}.jpg` via
  `ImageService.uploadCompressedPhoto` (JPEG `SettableMetadata`). The
  resulting download URLs are passed to
  `FeedbackFirebaseService.submitBugReport(screenshotUrls:)`, which persists
  them on the `bug_reports` doc as an `screenshotUrls` array. The upload is
  **best-effort**: a failed per-image upload is logged (debugPrint) and does
  not block the report itself (the report still submits with whatever URLs
  succeeded; the support email handoff proceeds as before).
- **Storage rules**: new `match /bug_report_attachments/{uid}/{fileName}`
  block in `storage.rules` — owner-scoped writes
  (`request.auth.uid == uid`); reads covered by the global authenticated-read
  rule (admins reviewing the report need to view the attachments). No
  `firestore.rules` change required (`bug_reports/{reportId}` create was
  already `isSignedIn()`).
- **Permissions**: Android `CAMERA` + `READ_MEDIA_IMAGES` (API 33+) and iOS
  `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` /
  `NSPhotoLibraryAddUsageDescription` were already declared in Phase 13
  (package creator camera capture); no new native manifest entries needed.
- **Testability**: `FeedbackFirebaseService` gained an injectable
  `FirebaseFirestore` + `currentUserIdResolver` constructor seam so it can be
  exercised against `fake_cloud_firestore` without a Firebase app.
- **Tests**: `test/bug_report_screenshot_test.dart` (6 new, all pass) —
  persists `screenshotUrls` when attachments provided; omits the field
  entirely when none (legacy reports unaffected); empty-list treated as no
  attachments; single-url preservation; standard audit fields
  (`hunterId`/`timestamp`/`title`/`steps`/`severity`); feature-suggestion
  path unaffected (no `screenshotUrls` field). Full suite 540 pass (was 534;
  +6; no regressions).
- Files: `lib/features/hunter_mode/presentation/bug_report_modal.dart`
  (screenshot picker + preview strip + remove + upload-on-submit),
  `lib/features/hunter_mode/services/feedback_firebase_service.dart`
  (`screenshotUrls` param + injectable firestore/uid seam),
  `storage.rules` (`bug_report_attachments/{uid}` block),
  `test/bug_report_screenshot_test.dart` (NEW, 6 tests).

### 16.10 Removal of Client Roster & Guided Hunt Logs from Outfitter Mode (implemented 2026-08-15)
- The **Client Roster** and **Guided Hunt Logs** features have been
  **completely removed** from Outfitter Mode. Both were outfitter-side
  harvest-logging / client-book subsystems that had grown redundant with the
  venison-permit + booking + trophy-inventory workflows.
- **UI & navigation**: the two dashboard feature cards ("Client Roster" and
  "Guided Hunt Logs") and their imports were removed from
  `outfitter_dashboard.dart`.
- **Screen widgets, services, models deleted**:
  - `lib/features/outfitter_mode/presentation/client_roster_screen.dart`
  - `lib/features/outfitter_mode/presentation/guided_hunt_log_screen.dart`
  - `lib/features/outfitter_mode/data/services/client_roster_manager.dart`
  - `lib/features/outfitter_mode/data/services/guided_hunt_log_manager.dart`
  - `lib/features/outfitter_mode/data/models/client_profile.dart`
  - `lib/features/outfitter_mode/data/models/guided_hunt_log.dart`
  - `test/outfitter_client_roster_test.dart` (6 tests removed).
- **Venison permit form decoupling**: `VenisonPermitFormScreen` no longer
  imports the client-roster / guided-hunt-log managers. The
  `clientId` / `guidedHuntLogId` constructor params and the post-issue
  permit-linking block (`GuidedHuntLogManager.linkPermit` /
  `ClientRosterManager.addPermitReference`) were removed. The generic
  `prefillData` map param is retained (it is self-contained and useful for
  any caller that wants to seed the form without a Firestore booking lookup);
  its docstring no longer references the removed managers.
- **Firestore rules + indexes cleanup**: the `match /client_roster/{clientId}`
  and `match /guided_hunt_logs/{logId}` blocks were removed from
  `firestore.rules`, and the two composite indexes
  (`client_roster (outfitterId ASC, createdAt DESC)` and
  `guided_hunt_logs (outfitterId ASC, huntDate DESC)`) were removed from
  `firestore.indexes.json`. The collections themselves are simply no longer
  read or written by the app; existing docs (if any) remain in Firestore but
  are orphaned (default-deny applies once the rules deploy).
- **Comments**: stale `client_roster` / `guided_hunt_logs` references in the
  `_ensureOutfitterSelfLink` docstrings/comments in `splash_screen.dart` and
  `auth_screen.dart` were updated to list only the remaining owner-scoped
  outfitter collections (trophies, venison_permits, scanned_pricelists).
- **Verification**: `flutter analyze` lib/ + test/ -> 0 errors, 0 warnings.
  `flutter test` -> **534 pass** (was 540; -6 = the deleted
  `outfitter_client_roster_test.dart`; no regressions).
- Deploy reminder: `npx firebase-tools deploy --only firestore:rules,
  firestore:indexes` in a credentialed env to activate the rules/index cleanup.
- Files: deleted the 6 files above; modified
  `lib/features/outfitter_mode/outfitter_dashboard.dart`,
  `lib/features/hunter_mode/screens/venison_permit_form_screen.dart`,
  `lib/core/splash_screen.dart`, `lib/features/auth/auth_screen.dart`,
  `firestore.rules`, `firestore.indexes.json`, `context.md`, `AGENTS.md`.

### 16.11 Reusable Firearm Dropdown Selector + Optical Suite refactor (implemented 2026-08-15)
- New reusable widget `lib/widgets/firearm_dropdown_selector.dart`
  (`FirearmDropdownSelector`) — a controlled, stateless firearm selector
  backed by the Digital Firearm Safe (`RifleProfile`). All selection state
  is owned by the parent (the screen), and changes are reported via
  `onChanged`.
  - `DropdownButtonFormField<String>` binds to the unique string
    `RifleProfile.id` (never an object reference), with a `ValueKey` derived
    from the effective value so the `FormFieldState` reinitialises on every
    selection change (fixing the "dropdown visually never reflects a
    freshly-selected firearm" drift that `DropdownButtonFormField`'s
    read-value-once-on-first-build behaviour causes).
  - `selectedFirearmId` is **validated against the live `firearms` list on
    every build** and coerced to `null` when absent — so a
    `DropdownButtonFormField` "value not in items" assertion error can never
    fire when a firearm is deleted while the dropdown is open.
  - Visual states per spec: `isLoading == true` -> a thin
    `LinearProgressIndicator` replaces the dropdown (first-load state);
    `firearms` empty -> a disabled `TextFormField` with the hint
    "No firearms found in Safe" (no interactive dropdown offered when there
    is nothing to select); otherwise the live dropdown with each item
    labelled `RifleProfile.displayName` ("make model (calibre)").
  - Optional `trailing` widget (e.g. a turret-unit context `Chip`) — the
    selector hides it itself while loading / empty. Optional `leadingIcon`
    override for host-screen iconography.
  - Uses `Theme.of(context)` exclusively (no hardcoded colors) so it adapts
    to the Day/Night toggle.
- **Shot Group Target Analyser refactor**
  (`lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`):
  the local `_buildFirearmSelector` dropdown logic was replaced with
  `FirearmDropdownSelector`. **Crucially, the selector was moved ABOVE the
  `ShotGroupTargetOverlay`** (the gesture canvas / `InteractiveViewer` /
  tap-`GestureDetector` layer) in the body `Column` widget tree, so the
  overlay's tap detector can never intercept taps meant for the dropdown
  menu. The selector is now the first child of the body Column (rendered
  before the overlay), not a sibling rendered after it. The screen's
  `StreamBuilder` over `InventoryBridge.watchSafeFirearms()` remains the
  data source; the `isLoading` flag is derived from
  `snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData`.
- **Scope Settings Tool refactor**
  (`lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`):
  the local `_buildFirearmLink` dropdown logic (the manual
  `DropdownButtonHideUnderline > DropdownButtonFormField<String>` +
  `ValueKey` + container + turret-unit `Chip`) was replaced with
  `FirearmDropdownSelector`. The turret-unit context `Chip` is passed as
  the selector's `trailing` widget (hidden automatically while loading /
  empty). The `leadingIcon` is overridden to `Icons.link` to match the
  prior iconography. The `_onRifleSelected` handler (which stamps the
  optic's `firearmId`) is unchanged and still drives the binding.
- **Tests**: `test/firearm_dropdown_selector_test.dart` (NEW, 6 widget
  tests, all pass) — covers: live dropdown renders display names +
  reports selection via `onChanged`; stale `selectedFirearmId` (deleted
  firearm) coerces to `null` instead of throwing the "value not in items"
  assertion; empty list renders the disabled "No firearms found in Safe"
  `TextFormField`; `isLoading` renders a `LinearProgressIndicator`
  (uses `pump`, not `pumpAndSettle`, because the indeterminate animation
  never settles); `trailing` hidden while loading / empty, shown when
  populated.
- **Verification**: `flutter analyze` lib/ + test/ -> 0 errors, 0 warnings.
  `flutter test` -> **540 pass** (was 534; +6 = the new widget tests; no
  regressions).
- Files: `lib/widgets/firearm_dropdown_selector.dart` (NEW),
  `lib/features/hunter_mode/screens/shot_group_analyzer_screen.dart`
  (refactored + selector hoisted above the gesture canvas),
  `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart`
  (refactored),
  `test/firearm_dropdown_selector_test.dart` (NEW, 6 tests),
  `context.md`, `AGENTS.md`. No Firestore / Storage / rules / index /
  pubspec changes (pure UI + a reusable widget).

### 16.12 Resilient trophy image fallback pipeline + PhotoUnavailablePlaceholder (implemented 2026-08-15)
- Fixed the "Photo unavailable" broken-image issue on the Trophy Room
  details screen by hardening the shared `AdaptiveImage` widget
  (`lib/utils/image_helper.dart`) — the central image renderer used by
  `trophy_detail_screen.dart`, `trophy_room_screen.dart`, AND
  `firearm_detail_screen.dart` (so all three surfaces benefit).
- **Resilient fallback pipeline** (3-stage):
  1. **Local file** — if the path looks local (`file://`, a POSIX absolute
     path, a Windows drive path, or `./`), the `file://` scheme is stripped
     and `File(localPath).existsSync()` is verified BEFORE attempting
     `Image.file`. A decode failure (corrupt bytes / permission error) is
     logged and falls through to stage 2.
  2. **Network image** — for a remote URL (`http`/`https`) OR a local path
     whose file no longer exists (app reinstalled / new device / scoped
     storage migration), render via `CachedNetworkImage`. Network failures
     (HTTP 403 Forbidden, 404 Not Found, socket/SSL/storage errors) are
     logged with the exact exception and fall through to stage 3.
  3. **Placeholder** — when every source has failed, render the reusable
     `PhotoUnavailablePlaceholder` (or the caller-supplied `errorWidget`).
- **New reusable widget** `lib/widgets/photo_unavailable_placeholder.dart`
  (`PhotoUnavailablePlaceholder`): neutral broken-image state with a
  generic "Photo unavailable" caption + `image_not_supported_outlined`
  icon, theme-aware colours, and optional `icon`/`label`/`backgroundColor`
  overrides. **No raw path or HTTP status is surfaced to end users** —
  exact failure diagnostics go to `debugPrint` only (visible in dev logs,
  not the UI), satisfying the security guideline that error messages must
  not expose sensitive/internal path information.
- **Explicit error logging**: both the `Image.file` `errorBuilder` and the
  `CachedNetworkImage` `errorWidget` now `debugPrint` the exact exception
  (exception type + message, the offending path/URL, HTTP status where
  available) so failures are clearly visible in logs instead of failing
  silently. Verified in the test output: e.g.
  `AdaptiveImage: local file does not exist at "…" — falling back to
  network load.` and `AdaptiveImage: network image load failed for "…" —
  <error>`.
- **Android scoped storage & permissions**
  (`android/app/src/main/AndroidManifest.xml`): `READ_MEDIA_IMAGES` was
  already declared for Android 13+ (API 33+, incl. 14 / S26+) scoped
  storage. Added the legacy `READ_EXTERNAL_STORAGE` with
  `maxSdkVersion="32"` for Android 12 and below compatibility (the
  standard dual-permission pattern), with an explanatory comment. The
  `_isLocalPath` detection explicitly documents that `content://` Android
  media URIs are NOT treated as local filesystem paths (Flutter `File()`
  cannot read them directly) — they fall through to the network stage,
  which degrades gracefully to the placeholder if unresolvable.
  image_picker returns a cached app-internal file path (not a `content://`
  URI) for picked media, so the local-file stage handles real picks.
- **Trophy detail screen** (`trophy_detail_screen.dart`): the inline
  broken-image `errorWidget` (custom `Container` + `Icon` + `Text`) was
  replaced with `PhotoUnavailablePlaceholder(backgroundColor: theme.cardColor)`
  so the detail screen uses the shared branded placeholder.
- **Tests**: `test/adaptive_image_pipeline_test.dart` (NEW, 6 widget tests,
  all pass) — `PhotoUnavailablePlaceholder` renders the broken-image icon +
  generic caption with no sensitive path/HTTP detail surfaced + honours
  overrides; `AdaptiveImage` empty path → placeholder (no image widget
  built); stale local path (file missing) → delegates to the network stage
  (CachedNetworkImage constructed); remote URL → network stage;
  caller-supplied errorWidget plumbed through to the network stage. Tests
  assert the structural contract (which widgets are constructed) rather
  than async image-decode outcomes, so they are stable in a headless /
  no-network sandbox.
- **Verification**: `flutter analyze` lib/ + test/ -> 0 errors, 0 warnings.
  `flutter test` -> **546 pass** (was 540; +6 = the new widget tests; no
  regressions).
- Files: `lib/widgets/photo_unavailable_placeholder.dart` (NEW),
  `lib/utils/image_helper.dart` (3-stage pipeline + logging),
  `lib/features/hunter_mode/trophy_detail_screen.dart` (uses placeholder),
  `android/app/src/main/AndroidManifest.xml` (READ_EXTERNAL_STORAGE
  maxSdkVersion=32 compat),
  `test/adaptive_image_pipeline_test.dart` (NEW, 6 tests),
  `context.md`, `AGENTS.md`. No Firestore / Storage / rules / index /
  pubspec changes (pure UI + a reusable widget + manifest permission).

### 16.13 AdaptiveImage strict URI-path-handling pipeline (implemented 2026-08-15)
- Fixed the URI-path-handling bug in the shared `AdaptiveImage` widget
  (`lib/utils/image_helper.dart`) where a local-looking path whose file did
  not exist (e.g. `/data/local/tmp/missing.jpg` after a reinstall / new
  device / scoped-storage migration) was wrongly passed to
  `CachedNetworkImage` as if it were a URL — causing the network loader to
  hang/throw (a local path is not a valid absolute http URI).
- **New strict fallback pipeline**:
  1. **Local file** — `_isLocalPath` now treats a string as local if it
     starts with `/data/`, `/storage/`, `file://`, OR satisfies
     `Path.isAbsolute(path)` (the `path` package, already a direct dep).
     The `file://` scheme is stripped via `Uri.parse(path).toFilePath()`
     (with a raw-substring fallback on parse failure), and
     `File(normalizedPath).existsSync()` is verified BEFORE rendering
     `Image.file`. A decode failure is logged and falls to the placeholder
     (NOT retried as a network URL).
  2. **Network image** — `CachedNetworkImage` is used ONLY when the string
     explicitly starts with `http://` or `https://`. Network failures are
     logged with the exact exception and fall to the placeholder.
  3. **Placeholder** — when the string is neither an existing local file
     NOR an `http(s)` URL, `PhotoUnavailablePlaceholder` (or the caller's
     `errorWidget`) is rendered. A non-existent local path / `content://`
     Android media URI / bare token is NEVER passed to `CachedNetworkImage`.
- **Pure functions extracted** for testability: `isLocalImagePath(path)` and
  `normalizeLocalImagePath(path)` are now top-level pure functions (the
  widget delegates to them). This decouples the URI-path-handling logic
  from the widget tree so it is unit-testable WITHOUT mounting an `Image`
  widget (real image decode via `dart:ui` is flaky/hangs in a headless test
  sandbox).
- **Tests**: `test/adaptive_image_pipeline_test.dart` rewritten — 22 tests
  (was 6), all pass:
  - Widget branch tests (no decode): empty path → placeholder;
    stale local path (missing) → placeholder NOT CachedNetworkImage;
    non-existent `file://` URI → placeholder NOT CachedNetworkImage;
    remote `http(s)` URL → CachedNetworkImage; non-URL non-local string →
    placeholder NOT CachedNetworkImage; `content://` URI → placeholder NOT
    CachedNetworkImage; caller `errorWidget` honoured for non-URL paths;
    caller `errorWidget` plumbed to the network stage for http(s) URLs.
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
  tests), `context.md`, `AGENTS.md`. No Firestore / Storage / rules /
  index / pubspec / manifest changes (pure logic + tests).

### 16.14 Hunter Mode rich media design language expansion (implemented 2026-08-23)

The SA Game Guide's rich media card design language (full-bleed imagery,
smooth dark multi-stop gradient overlays, top-right frosted-circle actions,
translucent frosted-glass telemetry pills, warm amber glow borders) is now
packaged as shared base components and rolled out across Hunter Mode's
tactical + reference modules.

- **Shared base components** (`lib/features/shared/widgets/`, NEW):
  - `HunterMediaCard` -- the reusable container extracted from
    `GameSpeciesCard`: full-bleed `ImageProvider` background with a graceful
    icon fallback, the 4-stop dark `legibilityGradient`, an amber
    `topLeftPill` tag, `topRightActions` frosted-circle buttons, title +
    italic subtitle + frosted pills, and the 20px rounded card with the dark
    amber glow / light warm border. Companions: `HunterMediaPill` (spec),
    `HunterFrostedPill` (overlay pill; `accentColor` override), `HunterDataPill`
    (solid card-body stat pill), `HunterFrostedCircleButton`,
    `kHunterMediaAmber`.
  - `HunterGridContainer` -- the standardized responsive high-density
    max-extent grid (280/0.72/16 defaults + static `gridDelegate(...)`).
- **`GameSpeciesCard`** refactored onto `HunterMediaCard` (same API + visuals;
  the 12 game-guide tests pass unchanged).
- **Module rollouts**: Digital Firearm Safe (licence status badge + frosted
  quick-action circles + caliber/barrel pills, grid layout); Ammunition
  Manager (grid of ammunition-profile media cards with caliber pills; saved
  factory/custom loads use clean `HunterDataPill`s for caliber/weight/
  velocity); Package Marketplace (`_PackageCard` full-bleed hero + frosted
  pricing / SOLD-OUT pill, contract-test invariants preserved); Trophy
  Registry (rich-media stock cards with availability/measurement/sex/price
  pills, grid layout).
- **Verification**: `flutter analyze` -> 0 errors / 0 warnings (277 infos,
  unchanged baseline). `flutter test` -> **All 1340 tests passed** (+20 new:
  `hunter_media_card_test.dart` 15 + `hunter_grid_container_test.dart` 5).
- Files: `lib/features/shared/widgets/hunter_media_card.dart` (NEW),
  `lib/features/shared/widgets/hunter_grid_container.dart` (NEW),
  `lib/features/game_guide/widgets/game_species_card.dart`,
  `lib/features/hunter_mode/firearm_safe_screen.dart`,
  `lib/features/ballistics/presentation/ammunition_screen.dart`,
  `lib/features/ballistics/presentation/ammunition_type_selection_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart`,
  `lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart`,
  `test/hunter_media_card_test.dart` (NEW),
  `test/hunter_grid_container_test.dart` (NEW). No Firestore / Storage /
  rules / index / pubspec / manifest changes (pure UI + shared widgets).

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
