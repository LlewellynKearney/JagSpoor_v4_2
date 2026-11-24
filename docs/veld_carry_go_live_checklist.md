# Veld & Carrying Capacity — Go-Live Checklist (Phase 5)

**Status:** PREP ONLY. Nothing in this document has been executed.
**Branch:** `feature/outfitter-veld-carry-weight`
**Feature:** Veld & Carrying Capacity (camp CRUD, stock ledger, planted feed,
predators, permits, hunter veld view)
**Rules file to review:** `firestore.rules.veld_carry.GO_LIVE_READY`

> This document is the go-live runbook. Every step marked **DO NOT EXECUTE**
> is written for Llewellyn to run by hand when he says go. Phase 5 changed no
> live configuration, deployed nothing, and left the feature flag OFF.

---

## 0. What "go-live" actually requires (read this first)

The feature is behind a **two-switch gate** (`VeldCarryFeatureFlag`). Both
switches must be ON before any veld UI renders:

| # | Switch | Where it lives | How it is set | Needs a rebuild? |
|---|--------|----------------|---------------|------------------|
| 1 | `VELD_CARRY_ENABLED` | **compile time** | `--dart-define=VELD_CARRY_ENABLED=true` at build time | **YES** |
| 2 | `veldCarryEnabled` | **`admin_config/feature_flags`** (Firestore) | Admin write / Firebase Console | No |

`VeldCarryFeatureFlag.shouldEnable(compileTime, adminConfig)` returns
`compileTime && adminConfig`. So:

* Turning the Firestore field ON alone does **nothing** — the shipped build
  has the compile-time switch OFF, and `VeldCarryGate` short-circuits without
  even reading Firestore in that case.
* **Go-live therefore requires a REBUILD with the dart-define plus a Web
  deploy and a new Play AAB.** This is not a runtime toggle. Plan the release
  accordingly.

Failure policy is **fail-closed**: a missing `admin_config/feature_flags`
document, a non-`true` value, a Firestore error, or an offline device all
resolve to OFF.

---

## 1. Pre-merge checklist

Run on the branch, before merging to `main`.

| # | Check | Expected | How |
|---|-------|----------|-----|
| 1.1 | Static analysis | **0 errors** | `flutter analyze` |
| 1.2 | Full test suite | All pass **except the one known pre-existing failure** | `flutter test` |
| 1.3 | Known pre-existing failure is the ONLY failure | `trial_onboarding_functions_contract_test` (v1-vs-v2 auth-trigger assertion; unrelated to veld) | Inspect the test output |
| 1.4 | Feature flag default | **OFF** (`compileTimeEnabled` default `false`) | `lib/features/veld_carry/veld_carry_feature_flag.dart` |
| 1.5 | Live rules untouched | `firestore.rules` has **zero** veld/camp/planted/predator matches | `grep -niE "veld\|camp\|planted\|predator" firestore.rules` → no matches |
| 1.6 | DRAFT file untouched | `firestore.rules.veld_carry.DRAFT` unmodified by Phase 5 | `git status` |
| 1.7 | No version bump | `pubspec.yaml` / `android/app/build.gradle.kts` unchanged | `git diff main -- pubspec.yaml android/app/build.gradle.kts` → empty |
| 1.8 | `min_required_version` untouched | still **27** | Firebase Console → `admin_config/app_version` (read-only check) |
| 1.9 | No payment/billing/PayFast/referral/profile/email/auth change | branch diff touches only veld files + 2 gate call sites | see 1.10 |
| 1.10 | Branch diff reviewed | 32 files, **12 432 insertions, 0 deletions** | `git diff --shortstat main...HEAD` |

### 1.10 Branch diff — full file list

Every file below is **purely additive** (0 deletions anywhere in the branch),
which is the strongest single safety property of this release.

**New feature code (`lib/features/veld_carry/`)**

```
lib/features/veld_carry/models/camp.dart
lib/features/veld_carry/models/farm_permit.dart
lib/features/veld_carry/models/planted_area.dart
lib/features/veld_carry/models/predator_entry.dart
lib/features/veld_carry/models/stock_entry.dart
lib/features/veld_carry/species_defaults.dart
lib/features/veld_carry/veld_carry_calculator.dart
lib/features/veld_carry/veld_carry_constants.dart
lib/features/veld_carry/veld_carry_feature_flag.dart
lib/features/veld_carry/veld_carry_repository.dart
lib/features/veld_carry/ui/veld_carry_camp_detail_screen.dart
lib/features/veld_carry/ui/veld_carry_camp_form_screen.dart
lib/features/veld_carry/ui/veld_carry_camp_list_screen.dart
lib/features/veld_carry/ui/veld_carry_gate.dart
lib/features/veld_carry/ui/veld_carry_hunter_view_screen.dart
lib/features/veld_carry/ui/veld_carry_permit_form_screen.dart
lib/features/veld_carry/ui/veld_carry_permits_screen.dart
lib/features/veld_carry/ui/veld_carry_planted_form_screen.dart
lib/features/veld_carry/ui/veld_carry_predator_form_screen.dart
lib/features/veld_carry/ui/veld_carry_stock_form_screen.dart
lib/features/veld_carry/ui/veld_carry_ui_common.dart
```

**Existing files touched — INSERTIONS ONLY (gate wiring, no refactor)**

```
lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart  (+16, -0)
lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart  (+87, -0)
```

**Draft rules (unchanged, for reference only)**

```
firestore.rules.veld_carry.DRAFT
```

**Tests**

```
test/veld_carry_calculator_real_test.dart
test/veld_carry_calculator_smoke_test.dart
test/veld_carry_feature_flag_test.dart
test/veld_carry_gate_test.dart
test/veld_carry_models_test.dart
test/veld_carry_phase3_ui_test.dart
test/veld_carry_phase4_test.dart
test/veld_carry_repository_test.dart
```

**Phase 5 additions**

```
firestore.rules.veld_carry.GO_LIVE_READY
docs/veld_carry_go_live_checklist.md
```

---

## 2. Manual QA — Outfitter (run with the flag ON in a staging build)

Entry point: **Farm Control Panel** → each farm card → **"Veld Carrying
Capacity"** button. (The button renders nothing while the flag is OFF.)

Work through the whole chain in order. Record actual values next to expected.

### 2.1 Create a farm
- [ ] Farm Control Panel → Register New Farm → save.
- [ ] Farm card appears in **Registered Farms**.

> The veld feature nests its data under `users/{uid}/farms/{farmId}/…`. The
> `farmId` is the **top-level `farms` document id**, so the farm must exist
> before veld data is meaningful.

### 2.2 Add a camp
- [ ] Farm card → **Veld Carrying Capacity** → camp list opens (empty state).
- [ ] Add camp: name, total size (ha), province, district, veld type, veld
      condition.
- [ ] Camp appears in the list.

### 2.3 Set the camp location
- [ ] Open the camp → **Update Location** → grant permission / accept GPS.
- [ ] `lat` / `lng` populate and `locationSource` becomes `gps`
      (or `manual` if entered by hand).

> GPS is **outfitter-only**. It must never appear in the hunter view (see §3).

### 2.4 Add stock — counted species
- [ ] Camp → **Add Stock** → pick a counted species (e.g. Impala).
- [ ] Confirm the form pre-fills average weight + grazer/browser split from
      the species table.
- [ ] Save with count > 0.
- [ ] Camp detail shows the species, count and the LSU/GU/BU totals.

**Verify the maths** (reference: 450 kg LSU steer):

```
lsuPerAnimal   = (avgWeightKg / 450) ^ 0.75
totalWeightKg  = count × avgWeightKg
totalLsu       = count × lsuPerAnimal
guPerAnimal    = lsuPerAnimal × grazerPct
buPerAnimal    = lsuPerAnimal × browserPct
```

- [ ] Spot-check one row by hand against the formula.

### 2.5 Add stock — present-only species
- [ ] Add a present-only species (Baboon / Vervet Monkey / Porcupine /
      Aardvark).
- [ ] A "present only" banner explains it is recorded but not counted.
- [ ] **VERIFY: total LSU contribution = 0.** The camp's current-stock LSU
      must not change after adding it.

### 2.6 Add planted areas — ALL_YEAR and SUMMER
- [ ] Add a planted area with season **ALL_YEAR** (e.g. Lucerne Irrigated).
- [ ] Add a second planted area with season **SUMMER** (e.g. Teff).
- [ ] Verify the camp's **year-round capacity** increased by the ALL_YEAR area
      only, and that the SUMMER area shows up in the seasonal boost instead.

**Verify the maths:**

```
plantedCapacityLsu = areaHa / haPerLsu
yearRoundCapacity  = veldCapacity + Σ(ALL_YEAR planted)
seasonalBoost(sum) = Σ(planted where season == SUM)   // ALL_YEAR excluded
```

- [ ] Confirm `haPerLsu` is pre-filled from the feed-type table and that
      `OTHER_CUSTOM` lets you type your own norm.

### 2.7 Add a predator
- [ ] Camp → **Add Predator** → pick a species (e.g. Black-backed Jackal),
      enter a count.
- [ ] The form previews prey kg/year and prey animals/year
      (`count × dailyIntakeKg × 365`).
- [ ] **VERIFY: predator total LSU = 0**, GU = 0, BU = 0. Predators must not
      change the stocking percentage.

### 2.8 Add permits — one private, one hunter-visible
- [ ] Camp → **Permits** (or the farm card's Permits button).
- [ ] Add permit #1 with visibility **Private**.
- [ ] Add permit #2 with visibility **Hunter visible**.
- [ ] Both appear on the outfitter's permit list.
- [ ] Expiry/status badge renders (`valid` / `expiring_soon` / `expired` /
      `no_expiry`).

### 2.9 Verify the stocking summary
- [ ] Camp detail shows: capacity LSU, current stock LSU, usage %, headroom,
      and a stocking band.

```
usagePct    = totalLsu / totalCapacity × 100        (0 if capacity <= 0)
headroomLsu = totalCapacity − totalLsu              (negative = overstocked)
bands: understocked < 70 | optimal 70..100 | overstocked 100..120 | severe > 120
effectiveHaPerLsu = deptNorm × conditionMultiplier
                    (good 1.0 | fair 1.25 | poor 1.60 | unknown → 1.25)
veldCapacityLsu   = veldHa / effectiveHaPerLsu
```

- [ ] Change veld condition `good` → `poor` and confirm capacity DROPS
      (multiplier 1.0 → 1.60) and usage % RISES.

---

## 3. Manual QA — Hunter (run with the flag ON in a staging build)

Entry point: hunter opens a **package / farm** they can see →
package details → the **Veld** tile appears **only if the farm has at least
one veld camp**.

### 3.1 Must be visible
- [ ] The **Veld** tile appears for a farm that has camps.
- [ ] The tile does **not** appear for a farm with zero camps.
- [ ] Hunter view lists the camps (name).
- [ ] Per camp: capacity summary (total capacity LSU, current stock LSU,
      usage %, headroom, stocking band).
- [ ] Counted stock shows **species + count only**.
- [ ] **Hunter-visible** permits are listed.
- [ ] Planted feed contributes to the capacity total (feed type + hectares).

### 3.2 Must NOT be visible (privacy gates — verify each one explicitly)
- [ ] **No GPS coordinates** — no lat, no lng, no accuracy, no map pin,
      no "open in maps" action.
- [ ] **No weights** — no average weight, no total live weight per species.
- [ ] **No GU / BU split** — no grazer/browser units per species.
- [ ] **No per-animal LSU breakdown** — only the camp-level summary.
- [ ] **No private permits** — a permit marked Private must be absent.
- [ ] **No permit numbers** — the permit number column/value is hidden.
- [ ] **No issuing authority**, no province on the permit card.
- [ ] **No file name / file URL** on any permit.
- [ ] **No predators at all** — the hunter view has no predator section.
- [ ] **No nearest town**, no district, no farm address.
- [ ] **No edit / add / delete affordance** anywhere in the hunter view
      (read-only).

> Cross-check with source: `lib/features/veld_carry/ui/veld_carry_hunter_view_screen.dart`
> must contain **zero** `lat` / `lng` / `latitude` / `longitude` / `LatLng`
> references. Phase 5 verified this grep is empty.

### 3.3 Confirm the flag gate
- [ ] With the flag OFF, the hunter view has **no Veld tile** and the package
      details sheet is otherwise unchanged (no gap, no empty space).

---

## 4. Go-live steps — **DO NOT EXECUTE**

Documented for Llewellyn. Run in order, in one sitting, and stop if any step
fails.

### Step 1 — Llewellyn reviews `firestore.rules.veld_carry.GO_LIVE_READY`
- [ ] Read the header. It is a **merge fragment**, not a replacement ruleset.
- [ ] Confirm the five paths match the code:
      `users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}` + `/stock` +
      `/plantedAreas` + `/predators`, and `…/permits/{permitId}`.
- [ ] Confirm the hunter read surface: camps + stock + plantedAreas + permits
      (`hunter_visible` only). **No** predator read. **No** hunter write.
- [ ] Confirm the booking gate is enforced in CODE
      (`VeldCarryRepository.hunterHasBookingForFarm`, fail-closed) and that the
      rules-level gate remains a documented limitation (§7.3).

### Step 2 — Llewellyn applies the rules **manually** in the Firebase Console
- [ ] Firebase Console → Firestore Database → Rules.
- [ ] **Copy the current live ruleset somewhere safe first** (this is the
      rollback artefact — see §5).
- [ ] Paste the fragment's helper + five `match` blocks **inside**
      `match /databases/{database}/documents { … }`, **above** the existing
      default-deny catch-all.
- [ ] Do **not** duplicate the default-deny block.
- [ ] Publish. Watch for a syntax error — if the Console rejects it, nothing
      has changed and you can retry.

### Step 3 — Merge the branch to `main` (after review)
- [ ] PR from `feature/outfitter-veld-carry-weight` → `main`.
- [ ] Confirm the diff is 100% additive (12 432 insertions, 0 deletions).
- [ ] Merge.

### Step 4 — Deploy Web
- [ ] Build **with the dart-define** (switch 1 must be ON for the UI to exist
      at all):
      `flutter build web --release --dart-define=VELD_CARRY_ENABLED=true`
- [ ] Deploy hosting.
- [ ] Smoke-test the login + an unrelated screen (confirm no regression).

### Step 5 — Build + upload the Play AAB
- [ ] `flutter build appbundle --release --dart-define=VELD_CARRY_ENABLED=true`
- [ ] Upload to Play (internal / closed track first).
- [ ] Note: the AAB must carry the dart-define, otherwise mobile users never
      get the feature even with the Firestore flag ON.

### Step 6 — Enable the control-plane flag (switch 2)
The app uses **`admin_config/feature_flags`** — a Firestore document in the
same `admin_config` family as `app_version` and `review_config`. There is no
Remote Config, no env var, and no other mechanism.

- [ ] Firebase Console → Firestore → `admin_config` → document
      `feature_flags` (create it if absent).
- [ ] Add field: `veldCarryEnabled` = **boolean** `true`.
- [ ] Leave every other field in that document untouched.
- [ ] Rules already permit this: `admin_config/{docId}` is
      `read: isSignedIn()` / `write: isAdmin()` — no rules change needed for
      the flag itself.

> Reminder: switch 2 alone cannot enable anything. If the deployed build was
> made **without** `--dart-define=VELD_CARRY_ENABLED=true`, the UI will still
> not appear. Verify the build was made with the define before concluding the
> flag "didn't work".

### Step 7 — Verify ON in staging first
- [ ] Sign in as a test outfitter → Farm Control Panel → the
      "Veld Carrying Capacity" button is present on each farm card.
- [ ] Sign in as a test hunter → package details → Veld tile present.
- [ ] Run §2 and §3 once more against staging data.

### Step 8 — Verify the hunter view on live
- [ ] Repeat the §3.2 privacy checklist on **production** data with a real
      hunter account. Do not skip this — it is the only check that proves the
      rules + UI combination leaks nothing.
- [ ] Confirm a private permit and a predator record are invisible.

### Step 9 — Monitor
- [ ] Firebase Console → Firestore → Usage: watch read/write volume for
      `users/*/farms/*` (the new subcollections).
- [ ] Watch Crashlytics / error logs for `permission-denied` on veld paths
      (a `permission-denied` here almost always means Step 2 was skipped or
      pasted in the wrong place).
- [ ] The hunter permit read now uses
      `.where('visibility', isEqualTo: 'hunter_visible')` (§7.2 — FIXED), so it
      no longer fails with `permission-denied`. A `permission-denied` here now
      means Step 2 was skipped or pasted in the wrong place.
- [ ] 24-hour check-in: any operator report of missing/blank veld data.

---

## 5. Rollback

### 5.1 Turn the feature OFF (1 step — the fastest rollback)
- [ ] Firebase Console → `admin_config/feature_flags` → set
      `veldCarryEnabled` = `false` (or delete the field).

Effect: every `VeldCarryGate` fails closed → **no tile, no button, no gap, no
Firestore read**. The feature disappears from both portals without a deploy.
No data is deleted — the documents stay in place for a later re-enable.

> Caveat: this only works on builds compiled **with** the dart-define (the
> ones shipped in Steps 4–5). A build without the dart-define never showed the
> feature in the first place, so it needs no rollback.

### 5.2 Revert the rules
- [ ] Firebase Console → Firestore → Rules → history: restore the version from
      **before** Step 2 (this is why Step 2 requires saving a copy first).
- [ ] Alternatively, delete the five veld `match` blocks and the
      `isVeldOwner` helper, leaving the default-deny catch-all in place.

Effect: every veld read/write falls back to the default-deny catch-all — the
dark posture the feature shipped with for Phases 0–4. The UI is already
hidden by 5.1, so users see no errors.

### 5.3 Hide the UI
- [ ] Nothing else to do: **flag OFF = no UI**. There is no separate kill
      switch, no navigation entry to unpick, and no menu item to remove — the
      gate is the only entry point in both portals.

### 5.4 Order of operations for a rollback
1. `veldCarryEnabled = false` (instant, hides everything).
2. Revert the rules (only if the rules themselves are the problem).
3. Leave the data in place unless there is a privacy reason to purge it.

---

## 6. Data locations (for support / forensics)

```
users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}
users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}/stock/{entryId}
users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}/plantedAreas/{areaId}
users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}/predators/{predatorId}
users/{outfitterUid}/farms/{farmId}/permits/{permitId}
```

Collection-name constants live in `VeldCarryRepository`
(`campsCollection = 'veldCamps'`, `stockCollection`, `plantedAreasCollection`,
`predatorsCollection`, `permitsCollection`).

> Note: this is **not** the Phase 0D DRAFT layout (`farms/{farmId}/camps/…`).
> Applying the DRAFT instead of `GO_LIVE_READY` would leave every real veld
> read/write denied.

---

## 7. Known limitations (accept at go-live, or fix first)

### 7.1 — Permit file upload (FIXED in Phase 6)
`VeldCarryPermitFormScreen` now uploads the picked document to Firebase
Storage and stores the download URL in `FarmPermit.fileUrl` alongside
`FarmPermit.fileName`.

* **Helper reused, not duplicated.** The app already had ONE Storage uploader
  (`lib/core/services/image_service.dart`). Phase 6 added a generic
  `ImageService.uploadDocument(...)` (byte-for-byte upload with a progress
  callback) next to the existing `uploadCompressedPhoto`, and a
  `ImageService.deleteByDownloadUrl(...)` for cleanup — no second uploader
  class was written.
* **Path:** `veld_permits/{outfitterUid}/{farmId}/{permitId}/{fileName}`
  (`VeldCarryPermitFormScreen.permitStoragePath`).
* **Validation:** PDF or image only (`pdf`, `jpg`, `jpeg`, `png`, `webp`,
  `heic`) and **max 10 MB**, enforced at pick time with an explicit error.
* **UX:** the upload runs on save with a `LinearProgressIndicator` + a
  percentage label; a failed upload ABORTS the save with a red error snackbar
  so a permit never points at a missing file.
* **Delete:** `VeldCarryPermitsScreen._delete` also deletes the Storage object,
  best-effort — a Storage failure is logged and never fails the Firestore
  delete.
* **Storage rules:** NEW `storage.rules.veld_carry.GO_LIVE_READY` (owner
  read/write only, no public read, **no hunter read**). The live
  `storage.rules` is untouched.
* **Hunter view:** still renders permit type + expiry + status only; the file
  URL is never exposed (verified — no `fileUrl` / `fileName` reference exists
  in `veld_carry_hunter_view_screen.dart`).

### 7.2 — Hunter permit read under the go-live rule (BLOCKER — FIXED in Phase 6)
`VeldCarryRepository.getPermitsForHunter` previously issued an
**unconstrained** collection read and filtered to `hunter_visible`
client-side. Firestore rules are not filters: the go-live rule
(`resource.data.visibility == 'hunter_visible'`) can only be honoured for a
query that **constrains the same field**, so a non-owner's unconstrained read
would have been rejected with `permission-denied`.

**Fixed (code, not rules).** The hunter permit read is now

```dart
.collection(permitsCollection)
.where('visibility', isEqualTo: FarmPermit.visibilityHunterVisible)
.get()
```

and the client-side `hunterVisiblePermits` filter is **kept as a second line
of defence** — the query is never trusted on its own.

* File / line: `lib/features/veld_carry/veld_carry_repository.dart:721`
  (`.where('visibility', isEqualTo: FarmPermit.visibilityHunterVisible)`)
  inside `VeldCarryRepository.getPermitsForHunter`; the defence-in-depth
  filter is `:729` (`return hunterVisiblePermits(permits);`).
* Tests: `test/veld_carry_phase6_test.dart` — the hunter read returns ONLY
  `hunter_visible` permits from a mixed collection, a private-only collection
  yields an empty list, and `hunterVisiblePermits` is asserted to be the
  second gate.
* **Camps / stock / plantedAreas need NO `where()`** — verified: their
  go-live rules have no per-document condition, so an unconstrained read is
  valid for them. Only permits are `resource.data`-guarded.

### 7.3 — Booking check (FIXED VIA `allowedHunterUids` in Phase 7D; rules can now enforce it)
`VeldCarryRepository.hunterHasBookingForFarm(hunterUid, farmId)` is now
implemented against the app's **real** booking store:

* Collection: **`bookings`** (top-level; written by `PackageBookingManager`
  and `FarmGamePriceListManager`).
* Fields: `hunterId`, `farmId`, `status`.
* Statuses that grant access: `BookingStatus.confirmed` + `BookingStatus.completed`
  (the legacy `Paid` spelling is accepted too — `BookingStatus.normalize`
  maps it to `Confirmed`). Pending / awaiting-payment / declined / cancelled
  bookings do **not** grant access.
* Query shape: `where('hunterId', isEqualTo: hunter)` (single-field equality —
  automatic index, no composite index) then `farmId` + status filtered in
  Dart.

Every hunter read (`getCampsForHunter`, `getCampForHunter`,
`getStockForHunter`, `getPlantedAreasForHunter`, `getPermitsForHunter`) takes
an optional `hunterUid`; when it is supplied and the booking check is false
the read returns an **empty list / null** (fail closed). `VeldCarryHunterViewScreen`
and `VeldCarryHunterEntryTile` pass the signed-in uid.

**Rules-level gate — FIXED (prepared) in Phase 7D.** A rule still cannot read
`bookings`, so the relationship is now **denormalised**: every camp document
carries `allowedHunterUids` (List<String>), written by

```dart
VeldCarryRepository.syncAllowedHuntersForFarm(farmId)
```

which collects the hunters holding a **Confirmed / Completed** booking on that
farm (Pending / Awaiting Payment / Declined / Cancelled never grant access) and
merges them onto **every camp** of the farm with `FieldValue.arrayUnion`
(union semantics — never a duplicate; an existing entry is never dropped).

`firestore.rules.veld_carry.GO_LIVE_READY` now gates the hunter reads on

```
allow read: if isVeldOwner(outfitterUid)
  || (isSignedIn()
      && resource.data.keys().hasAny(['allowedHunterUids'])
      && resource.data.allowedHunterUids is list
      && request.auth.uid in resource.data.allowedHunterUids);
```

for **camps**, and via the `isAllowedCamper(...)` parent-`get()` helper for
**stock** and **plantedAreas**. The old `allow read: if isSignedIn();` line is
kept **commented** in each block as the fallback. **The rules are NOT applied**
— the fragment is prepared, and `firestore.rules` itself is untouched.

**Apply-time prerequisite (same trap as §7.2).** Firestore rules are not
filters: a rule that inspects `resource.data.allowedHunterUids` can only serve a
query that constrains the same field. Before this ruleset is applied,
`VeldCarryRepository.getCampsForHunter` must add

```dart
.where('allowedHunterUids', arrayContains: hunterUid)
```

Stock / plantedAreas need no change — their rule resolves the field through a
`get()` on the fully-specified parent camp path, which is constant across the
query. The constraint is deliberately **not** added in Phase 7D: the rules are
not applied, and constraining now would deny hunters on farms whose allow-list
has not been synced yet.

Three properties to know before enabling it:

* **The sync must run first.** A camp that has never been synced has no
  `allowedHunterUids`, so every non-owner read of it is denied (fail closed —
  `request.auth.uid in <missing field>` errors).
* **There is NO automatic hook.** `PackageBookingManager.confirmPaymentReceived`
  is unchanged: the booking flow was read-only for this work, so the sync is a
  **manual** action — the outfitter taps **Sync hunter access** on the Veld camp
  list (outfitter-only, flag-gated, `ValueKey('veldSyncHunterAccessButton')`).
  Re-run it after confirming a booking. A booking-confirmation Cloud Function /
  trigger is the natural Phase 8 follow-up.
* **Removal is deliberately NOT automatic.** Cancelling or refunding a booking
  does not revoke access. Keeping access is the safer failure mode (a hunter
  losing camp data mid-trip is worse than stale access) and cancellations are
  often followed by a rebooking. Revoking is an explicit operator action.

**Permits** keep the Phase 6 `visibility == 'hunter_visible'` gate: permits are
farm-level (not camp-level) and the camp sync does not write onto them, so the
allow-list clause for permits is present but **commented** — enabling it today
would deny every hunter permit read. It becomes available once the permit write
stamps the farm's allow-list (a Phase 8 item).

The code-side `hunterHasBookingForFarm` gate **stays in place** as defence in
depth: every `...ForHunter` read still fails closed when a `hunterUid` is
supplied. So even without the rules deploy, the app never serves veld data to a
hunter without a confirmed/completed booking.

### 7.4 — Species weight/feeding table (VERIFIED in Phase 7D — 48 of 49; 1 UNVERIFIED)
`lib/features/veld_carry/species_defaults.dart` is a **fallback** table: the
app's `animals_seed.csv` carries no weight, feeding-class or grazer/browser
split columns, so these values are the interim source of truth. They were
authorised by Llewellyn but must be verified against the official SA tables
(Phase 3 note in the file header). Any species absent from the table is
carried as a placeholder (`avgWeightKg: 0`, `feedingClass: unknown`) and
listed in `missingSpeciesNames`.

**Phase 7D result — checked every row against a citable published source.**
Each entry in `species_defaults.dart` now carries `isVerified` +
`verificationSource` and an inline `// VERIFIED:` / `// UNVERIFIED —` marker.

* **48 of 49 rows VERIFIED.** The fallback weight was within the ±20% tolerance
  of the source, so the authorised value was **kept**.
* **1 row CORRECTED:** **Cane Rat 8 kg → 4.5 kg**. The source's typical range is
  3.2–5.2 kg (males average 4.5 kg); 8 kg matched only the exceptional 7–9 kg
  upper tail and overstated the row by ~78%.
* **1 row UNVERIFIED:** **Cape Hare** — Animal Diversity Web gives 4–5 kg for
  *Lepus capensis*, but regional southern-African accounts give 1.5–3 kg and
  *L. capensis* is a recognised species complex. The 2 kg fallback is retained
  rather than replaced with a value that may be wrong for South Africa. Needs an
  official SA source before it can be marked verified.

The three Phase-6 "most uncertain" species are now resolved (no value changed):

| Species | Table | Source | Verdict |
| --- | --- | --- | --- |
| African Elephant | 4500 kg | Wikipedia (en): bulls mean 6.0 t, cows mean 3.0 t | sex-average = 4500 kg — VERIFIED |
| Giraffe | 1100 kg | Wikipedia (en): male mean 1,192 kg, female 828 kg (≈1010 kg) | +8.9% — VERIFIED |
| Hippopotamus | 1500 kg | Wikipedia (en): mean 1.48 t bulls, 1.365 t cows (≈1422 kg) | +5.5% — VERIFIED |

Grazer/browser splits were reviewed and **not changed** — every pure grazer is
≥0.90 graze, every pure browser ≤0.10 graze, and no clearly-wrong split was
found.

Remaining gap: the `missingSpeciesNames` placeholders (species present in the
app's seed catalogue but absent from the authorised table) still carry
`avgWeightKg: 0`. They are **not** part of the 49 and remain unverified.

Impact: a species with `avgWeightKg: 0` contributes 0 LSU, which
**understates** stocking pressure. Review `missingSpeciesNames` before go-live
and fill in anything common on the target farms.

### 7.5 — Camp delete does not cascade to children
Firestore does not cascade deletes. `VeldCarryRepository.deleteCamp`
deletes only the camp document; the camp detail screen deletes each child
(stock / planted / predators) explicitly **before** calling it. Anything the
client cannot remove (a rules-denied document, a concurrent write) is surfaced
to the caller rather than silently orphaned — but a partially failed delete can
leave orphaned child documents under a deleted camp.

Impact: cosmetic/storage only — an orphaned child is unreachable from the UI
(it has no camp to render under). Clean up manually if the operator reports
unexpected Firestore usage.

---

## 8. Phase 5 verification log (what was actually run)

| Check | Result |
|-------|--------|
| `flutter analyze` | 0 errors (see hand-back for warning/info count) |
| `flutter test` | all pass except the one known pre-existing failure |
| Rules braces / parens / brackets balanced | balanced |
| Rules unconditional read grant | none |
| Rules match paths vs repository path builders | exact match (5/5) |
| `lat`/`lng`/`latitude`/`longitude`/`LatLng` in hunter view | **0** |
| Hardcoded test data in `lib/features/veld_carry/` | **0** |
| Live `firestore.rules` veld references | **0** (untouched) |
| Version bump | none |
| Deploy | none |

TODOs left in `lib/` after Phase 6:

```
(none)
```

The Phase 5 TODOs are resolved: the permit query fix (§7.2) and the permit
Storage upload (§7.1) are implemented, and the booking check (§7.3) is
implemented in code. The remaining rules-level booking gate is a DATA change
documented in §7.3, not a `TODO` in `lib/`.
