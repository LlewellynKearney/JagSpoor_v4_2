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
- [ ] Confirm the booking-check TODO is understood as a **known gap** (§7).

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
- [ ] Watch for the hunter permit-read failure described in §7 item 2 — it
      presents as `permission-denied` on the permits collection.
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

### 7.1 — Permit file upload is file-name only (Phase 6)
`VeldCarryPermitFormScreen._pickFile` stores **only** the picked file's
**name** (`fileName`). There is no Firebase Storage upload path for permit
documents yet, and `fileUrl` is deliberately left unset rather than written as
a link that resolves to nothing. See `TODO(Phase 6)` in
`lib/features/veld_carry/ui/veld_carry_permit_form_screen.dart:162`.

Impact: an outfitter cannot attach the actual permit PDF/image and cannot
retrieve it later from the app. Acceptable for a first release; schedule
Phase 6 before marketing the permits vault as a document store.

### 7.2 — Hunter permit read will FAIL under the go-live rule (BLOCKER — needs a code change)
`VeldCarryRepository.getPermitsForHunter` issues an **unconstrained**
collection read (`.../permits.get()`) and then filters to
`hunter_visible` **client-side**.

Firestore rules are not filters. The go-live rule for permits is
`resource.data.visibility == 'hunter_visible'`, which Firestore can only honour
for a query that **constrains the same field**. An unconstrained collection
read by a non-owner is therefore rejected with `permission-denied` — the
whole query fails, it does not silently return fewer documents.

**Required before go-live (code, not rules):** change the hunter permit read
to

```dart
.collection(permitsCollection)
.where('visibility', isEqualTo: FarmPermit.visibilityHunterVisible)
.get()
```

(or move the hunter permit read behind a callable). The camps / stock /
plantedAreas hunter reads are **unaffected** — their rules have no per-document
condition, so an unconstrained read is valid.

Impact if shipped as-is: the hunter view renders camps, stock and planted
capacity correctly, but the permits section shows nothing (the read throws and
the screen logs + degrades). It fails closed, so nothing leaks — but the
hunter-visible permits feature does not work.

### 7.3 — Booking check is not in the rules yet (Phase 6)
The hunter read rules grant **any signed-in user** read on camps, stock,
planted areas and hunter-visible permits for **any** `outfitterUid`/`farmId`
they know. There is no check that the caller holds a booking on that farm.

This is the documented interim gate (`TODO(veld-carry Phase 6)` in the rules
file and in `VeldCarryRepository`). The exposure is bounded — camp names,
species counts, hectares and hunter-visible permits only; no GPS, no weights,
no predators, no private permits — but it is broader than "hunters with a
booking". Phase 6 must add the booking relationship before the feature is
promoted beyond a soft launch.

### 7.4 — Species weight/feeding table needs verification against official SA tables
`lib/features/veld_carry/species_defaults.dart` is a **fallback** table: the
app's `animals_seed.csv` carries no weight, feeding-class or grazer/browser
split columns, so these values are the interim source of truth. They were
authorised by Llewellyn but must be verified against the official SA tables
(Phase 3 note in the file header). Any species absent from the table is
carried as a placeholder (`avgWeightKg: 0`, `feedingClass: unknown`) and
listed in `missingSpeciesNames`.

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

TODOs left in `lib/`:

```
lib/features/veld_carry/veld_carry_repository.dart:481   TODO(go-live)
lib/features/veld_carry/ui/veld_carry_permit_form_screen.dart:162  TODO(Phase 6)
```

Both are tracked in §7.1 and §7.3 above.
