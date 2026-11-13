# TASK 3 — Admin Portal V2: Trial + Subscription KPIs

Branch: `feature/admin-portal-v2` (base `main` @ `d16bb03`). **Not merged, not
deployed.**

---

## ⚠️ Read this first — the Task 1 + Task 2 foundation was NOT in the repo

The brief says to build on Task 2 and reuse its names. When this task started,
**neither Task 1 nor Task 2 was present in the working tree, and the
`feature/admin-portal-v2` branch did not exist** — locally or on GitHub.

Verified before writing any code:

| Check | Result |
| --- | --- |
| `git branch -a` | only `main` (+ unrelated `feat/*`, `fix/*`, `report/*`) |
| `git ls-remote --heads origin` | **no** `feature/admin-portal-v2` ref |
| `find . -iname "*admin_portal*"` | **no** files |
| `find . -iname "*admin_user_metrics*"` | **no** files |
| `grep -r "admin_portal_v2\|admin_user_metrics\|New Users" lib test` | **0 hits** |
| GitHub PRs (state=all) | PRs #1–#9, **none** about an admin portal |
| `git fsck --lost-found` | no dangling commits holding the work |
| `docs/admin-portal-v2/` | did not exist |
| conversation history (`/var/openhands/conversations`) | only THIS conversation |

So Task 1/Task 2 were never committed to this repository. Because the Task 3
acceptance criteria depend on the Task 2 screen/route/model/filter, this task
**reconstructed the Task 2 foundation to the contract described in the brief**,
then implemented the Task 3 KPIs on top of it. The names match the brief
exactly:

* `lib/features/admin/screens/admin_portal_v2_screen.dart`
* route `/admin_portal_v2`
* `lib/features/admin/models/admin_user_metrics.dart`
* date filter **Today / 7d / 30d / All Time** that re-runs aggregation locally

If the real Task 2 artifacts surface later, this reconstruction is a drop-in
compatible baseline (same paths, same names, same fetch-once/aggregate-locally
pattern) — reconcile the diffs rather than re-doing the work.

**No Admin entry was added to the role selector.** The V2 portal is reachable
via the route `/admin_portal_v2` (admin-only) and from an "Admin Portal V2"
card in the existing `/admin_dashboard` Account Management section.

---

## What was built

### 1. Model — `lib/features/admin/models/admin_user_metrics.dart` (NEW)

* `enum AdminDateFilter { today, last7Days, last30Days, allTime }` — the
  date-range filter. `startFor(now)` returns the window start (`null` for
  All Time); `includes(timestamp, now)` is the pure membership test. A `null`
  or **future** timestamp never counts.
* `AdminUserRecord` — one `users/{uid}` document reduced to the fields the KPIs
  need, parsed ONCE via `AdminUserRecord.fromMap(uid, data)`. Trial/premium
  activity is **computed**, never read from a stored flag:
  * `isTrialActive(now)` — mirrors `UserEntitlement.isTrialActive` exactly.
  * `isPremiumActive(now)` — mirrors `UserEntitlement.isPremiumActive` exactly.
  * `everStartedTrial` — true when a trial-start timestamp is present.
* `AdminUserMetrics` — the KPI bundle + the pure
  `AdminUserMetrics.aggregate(records, filter:, now:)` factory. The `now`
  parameter makes every date comparison deterministic in tests.

### 2. Service — `lib/features/admin/services/admin_user_metrics_service.dart` (NEW)

`AdminUserMetricsService.instance.fetchRecords()` reads the `users` collection
**once** (bounded by `scanLimit = 5000`), skips disabled accounts
(`disabled: true` / `role: 'disabled' | 'deleted'`), and returns the parsed
records. Best-effort: a permission / index / network failure returns an empty
list (never throws). `@visibleForTesting firestoreForTesting` seam.

### 3. Screen — `lib/features/admin/screens/admin_portal_v2_screen.dart` (NEW)

* `AdminAuthGuard` admin gate (same as `/admin_dashboard`).
* Fetches records ONCE in `_bootstrap`; **changing the date filter only
  re-runs `AdminUserMetrics.aggregate` locally** — no further Firestore read.
* Filter chip bar (`adminV2DateFilterBar`) + a KPI grid with the six cards
  (New Users + the five Task 3 cards).
* Unknown-plan note (shown only when an active subscriber lacks a plan) and a
  snapshot note explaining the filter scope.
* `WebLayout.responsive` centred container + `SafeBottomInset` bottom padding.

### 4. Route + guard wiring

* `lib/main.dart` — `/admin_portal_v2` → `RoleGuardedRoute(route:
  '/admin_portal_v2', requiresPremium: false, builder: AdminPortalV2Screen)`.
  `requiresPremium: false` so an admin whose own subscription lapsed can still
  reach the operator portal (the guard already exempts admins from the
  entitlement gate; this keeps the intent explicit).
* `lib/features/auth/services/role_guard.dart` — `/admin_portal_v2` added to
  `adminOnlyRoutes`, so every non-admin is denied + bounced (same policy as
  `/admin_dashboard`). **The role selector was NOT touched.**
* `lib/features/admin/screens/admin_dashboard_screen.dart` — an "Admin Portal
  V2" card added to Account Management as the entry point.

---

## The five Task 3 KPIs (definitions as implemented)

| Card | Definition |
| --- | --- |
| **Trial Active** | `COUNT(records WHERE isTrialActive(now) AND NOT isPremiumActive(now))` |
| **Trial Expired — No Sub** | `COUNT(records WHERE trialEnd < now AND NOT isPremiumActive(now))` |
| **Subscribed Hunters** | `COUNT(records WHERE role == 'hunter' AND isPremiumActive(now))` |
| **Subscribed Outfitters** | `COUNT(records WHERE role == 'outfitter' AND isPremiumActive(now))` |
| **Trial → Paid Conversion** | `(Subscribed Hunters + Subscribed Outfitters) / EverStartedTrial × 100`, one decimal |

* **Ever Started Trial** = `COUNT(records WHERE a trial-start timestamp is
  present)` — the denominator. `0.0%` when the denominator is 0 (no
  divide-by-zero).
* **Unknown bucket** = active subscribers whose plan
  (`subscriptionProduct` / `plan`) is missing; surfaced as a note so the plan
  split reconciles.
* **Trial Active excludes active subscribers.** This is a deliberate
  correctness fix: the entitlement creation-window fallback (30 days) would
  otherwise classify a brand-new **paid** subscriber as trial-active and
  double-count them. The sibling bucket is literally "Trial Expired — No
  Sub", so the trial buckets are mutually exclusive with the subscription
  buckets.
* Missing trial/subscription fields resolve to `0` / `Unknown` and never
  crash (a fully-empty document is covered by a test).

### Date filter scope

**Only New Users responds to the filter.** Trial / subscription figures are
point-in-time snapshots ("as of now") and are byte-identical across
Today / 7d / 30d / All Time — asserted in both the unit and widget suites.

---

## Where the numbers come from (client vs server)

**Computed client-side.** The deployed `getAdminPortalKpis` Cloud Function
(`functions/src/admin/kpis.ts`) does **not** expose trial buckets — its
`aggregateUserKpis` reports subscriber totals + the Play/PayFast split only
(`isActiveSubscription` deliberately treats a trial as NOT a subscription).
Per the brief ("reuse if it already exposes trial buckets, otherwise compute
client-side like Task 2"), the trial + conversion figures are computed here
from the same `users` documents, using the exact `entitlement_service.dart`
resolution so the admin numbers agree with the in-app paywall gate.

If the server KPI function is later extended with trial buckets, the screen can
prefer them the same way `/admin_dashboard` prefers `_kpis` over its local
fallback.

---

## Field corrections honoured (per the brief)

* **NOT** queried: `trialStartDate`, `trialEndDate`, `isTrialActive`,
  `isPremiumActive`, `plan`, `paymentProvider` — none are stored fields.
* **Trial dates** read from the `entitlement_service.dart` alias lists
  (`trialEndFieldAliases` / `trialStartFieldAliases`): `trialStartedAt`,
  `trialEndsAt`, `trialStart`, `trialEnd`, `subscriptionTrialEndsAt`,
  `subscriptionTrialStart`, `subscriptionTrialStartedAt`, plus snake_case
  variants.
* **Plan** from `subscriptionProduct` (canonical) with `subscription_product`
  / `plan` fallbacks.
* **Payment provider** from `subscriptionProvider` / `subscriptionPlatform` /
  `subscriptionSource` (+ snake_case).
* **Demo account NOT filtered** — `demo@jagspoor.co.za` was purged in v4.2.22;
  there are 0 references, so nothing to exclude. (The service still skips
  genuinely disabled accounts, matching the server's `isDisabledAccount`.)

---

## Tests

Two new suites, **37 tests, all passing**:

* `test/admin_portal_v2_metrics_test.dart` (31) — the filter window math;
  `isTrialActive` / `isPremiumActive` matrices; the aggregation (new users per
  filter, snapshot invariance, trial-expired-no-sub, role split, conversion %
  incl. the 0-denominator case + 1-decimal rounding, unknown-plan bucket,
  missing-field safety); `fromMap` alias coverage; and the
  `FakeFirebaseFirestore` fetch path (disabled exclusion, full-bundle
  aggregation, graceful failure).
* `test/admin_portal_v2_screen_test.dart` (6) — all five Task 3 cards render;
  the subscriber count reflects Firestore; the date filter changes ONLY New
  Users while snapshots stay fixed; the filter bar renders; the Unknown-plan
  note; non-admin denial.

## Verification

* `flutter analyze lib test`: **0 errors, 0 warnings**, 320 pre-existing
  info-level issues (the documented baseline — the 6 `main.dart` infos are
  pre-existing, proven by stashing the edits and re-analyzing). All new files:
  **No issues found**.
* `flutter test` (full suite, `LD_LIBRARY_PATH="$HOME/libs"`):
  **2435 passed, 1 failed**. The single failure is the DOCUMENTED pre-existing
  `trial_onboarding_functions_contract_test` (v1-vs-v2 auth trigger) — proven
  pre-existing by stashing every change and re-running at clean `main`; it
  contains 0 references to this work.
* `pubspec.lock` drift from `pub get` (test-only transitive `matcher` / `meta`
  / `test` downgrades) was **reverted**.
* Env: Flutter **3.44.9** (the CI pin) at `/tmp/flutter_sdk_dl/flutter`; the
  `~/libs/libsqlite3.so -> /usr/lib/x86_64-linux-gnu/libsqlite3.so.0` symlink
  for the sqflite-FFI suites.

---

## Constraints honoured

* ✅ Stayed on `feature/admin-portal-v2`; **not merged** to `main`.
* ✅ **No deploy.**
* ✅ **No change** to `admin_config` / `min_required_version`.
* ✅ **No Admin added** to the role selector.

## Files

* NEW: `lib/features/admin/models/admin_user_metrics.dart`,
  `lib/features/admin/services/admin_user_metrics_service.dart`,
  `lib/features/admin/screens/admin_portal_v2_screen.dart`,
  `test/admin_portal_v2_metrics_test.dart`,
  `test/admin_portal_v2_screen_test.dart`.
* MODIFIED: `lib/main.dart` (route + import),
  `lib/features/auth/services/role_guard.dart` (admin-only route),
  `lib/features/admin/screens/admin_dashboard_screen.dart` (entry card),
  `AGENTS.md`.
* No Firestore rules / index / Storage / functions / manifest changes.

---

## Acceptance

* 5 new cards show ✅ (plus New Users); numbers derive from the `users`
  documents a Firestore console spot-check reads ✅.
* Date filter still only changes New Users; trial/subs are snapshots ✅.
* `flutter analyze`: No issues ✅. New tests pass ✅. Existing suite: only the 1
  documented pre-existing failure ✅.

TASK 3 DONE
