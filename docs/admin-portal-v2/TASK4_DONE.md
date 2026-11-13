# TASK 4 — Admin Portal V2: Packages + Bookings KPIs

Branch `feature/admin-portal-v2` (base `221ccce`). Reuses the Task 3 pattern:
fetch ONCE, aggregate LOCALLY. The date filter still applies ONLY to New
Users — every package / booking figure here is a point-in-time snapshot
("as of now") and does not respond to the filter.

## Field truths honoured (from Task 1/3 + the brief)

- **Packages do NOT store `province` / `town`.** Province is derived by joining
  `farms/{farmId}` via `package.farmId`. A package with a missing `farmId` OR a
  missing farm doc is bucketed as **Unknown Province** — it is NEVER dropped.
- **Bookings have no `confirmedAt`.** The payment-verified timestamp is
  `paymentVerifiedAt` (gated on `paymentVerified == true`). Statuses come from
  `booking_status.dart` (`Pending Approval`, `Awaiting Payment`, `Confirmed`,
  `Completed`, `Declined`, `Cancelled`), matched tolerantly via
  `BookingStatus.normalize`.
- **`demo@jagspoor.co.za` is purged** — no demo-account filter is applied.
- **No booking AMOUNT is reported.** JagSpoor does not take booking payment
  in-app (off-platform EFT/cash), so only booking COUNTS / statuses are shown.
  The snapshot note states this explicitly on screen.

## P1 — Packages KPI model + local aggregation

NEW `lib/features/admin/models/admin_operational_metrics.dart`:

- `AdminPackageRecord` — a `packages/{id}` doc reduced to
  `outfitterId` / `title` / `farmId` / `status` / `quantityAvailable` /
  `createdAt`, plus the `resolvedProvince` filled by the service join. Getters:
  `isActive` (`status == 'active'`), `isSoldOut` (`status == 'sold_out'` OR
  `quantityAvailable <= 0` — mirrors `PackageQuantity.isSoldOut`),
  `isDraftArchived` (`draft` / `archived` / `deleted`), `provinceBucket`
  (resolved province, else `Unknown Province`).
- `AdminPackageMetrics.aggregate(...)` — pure + synchronous:
  - **Total Packages** = count of all packages.
  - **Active** = `status == 'active'`.
  - **Sold Out** = `status == 'sold_out'` OR `quantityAvailable == 0`.
  - **Draft / Archived** = `status in {draft, archived, deleted}`.
  - **Packages Per Province** — for each of the 9 SA provinces
    (`kSaProvinces`), count ACTIVE packages; a missing farm / province lands in
    `Unknown Province`. The breakdown always contains every key (zero when
    absent) so it reconciles with the Active total.
  - **Packages With 0 Bookings** — ACTIVE packages whose id appears in NO
    booking (any status). Each row carries title + outfitter email + days live.
  - **Outfitters With 0 Packages** — `outfitters` uids owning no package.

## P2 — Bookings KPI model + local aggregation

Same file:

- `AdminBookingRecord` — `bookings/{id}` reduced to `status` / `hunterId` /
  `outfitterId` / `packageId` / `packageName` / `createdAt` /
  `paymentVerifiedAt` / `paymentVerified`. `normalizedStatus` routes through
  `BookingStatus.normalize`; `isEarned` = Confirmed + Completed;
  `isStuckPending(now)` = Pending Approval older than 7 days;
  `daysToConfirm` = `paymentVerifiedAt - createdAt` (never `confirmedAt`).
- `AdminBookingMetrics.aggregate(...)` — pure + synchronous:
  - **Total Booking Requests** = count of all bookings.
  - **By Status** — a count per the six canonical statuses.
  - **Requests → Confirmed %** = `(Confirmed + Completed) / Total * 100`, one
    decimal, `0.0%` when Total is 0.
  - **Stuck Pending > 7d** — Pending Approval with `createdAt < now - 7d`.
    Rows carry bookingId + hunter email + outfitter email + package title +
    days stuck.
  - **Top 5 Outfitters By Bookings** — grouped by `outfitterId`, sorted DESC by
    total (confirmed tie-break), capped at 5. Rows carry name/email + total +
    confirmed + conversion %.
  - **Avg Days To Confirm** — average `paymentVerifiedAt - createdAt` over
    Confirmed/Completed rows where `paymentVerified == true` AND
    `paymentVerifiedAt` exists. Renders `"—"` when none.

## P3 — Fetch-once service + `farms` province join

NEW `lib/features/admin/services/admin_operational_metrics_service.dart`:

- `AdminOperationalMetricsService.fetchData({userEmailByUid})` reads
  `packages`, `bookings`, `farms`, `outfitters` ONCE (each bounded by
  `scanLimit`), performs the `farms/{farmId}` province join, and returns an
  `AdminOperationalData` snapshot.
  - The caller's `users` emails (already parsed by the Task 3 fetch) are passed
    in via `userEmailByUid`, so **`users` is never read a second time**;
    outfitter emails from the `outfitters` collection are merged on top.
  - Disabled outfitters (`disabled: true` / `role: disabled|deleted`) are
    excluded from the outfitter set (mirrors the server's `isDisabledAccount`).
  - Every collection read is best-effort: a failure yields an empty result for
    that collection (the screen then renders zeroes) — one broken read never
    crashes the portal.
- `AdminOperationalData.packageMetrics()` / `.bookingMetrics()` run the pure
  aggregations.
- `firestoreForTesting` seam for tests.

## P4 — Screen wiring (cards + 2 tables + breakdowns)

`lib/features/admin/screens/admin_portal_v2_screen.dart`:

- The bootstrap now also fetches the operational snapshot (reusing the user
  emails) and stores the package + booking metric bundles. A filter change
  re-aggregates ONLY the user metrics (the operational figures are snapshots).
- New **Packages** section: a 5-card grid (Total / Active / Sold Out /
  Draft-Archived / Outfitters With 0 Packages), an "Active Packages Per
  Province" breakdown (9 provinces + Unknown), and the **Packages With 0
  Bookings** table.
- New **Bookings** section: a 4-card grid (Total / Requests → Confirmed % /
  Stuck Pending >7d / Avg Days To Confirm), a "Bookings By Status" breakdown
  (six statuses), the **Stuck Pending > 7 Days** table, and the **Top 5
  Outfitters By Bookings** table.
- A snapshot note clarifies that package/booking figures ignore the date filter
  and that no booking amount is reported as revenue (off-platform payment).
- `_tableCard` renders an explicit empty-state label per table (never blank).
- `AdminUserRecord` gained an `email` field (read from `users.email`) so the
  operational email columns resolve without a second `users` read.

## Tests

- NEW `test/admin_portal_v2_operational_test.dart` (25 tests): record parsing
  (real fields, null-data tolerance), `isSoldOut` / `isDraftArchived` /
  province bucketing, package counts, province reconciliation + active-only
  counting, zero-booking packages (active only), outfitters-with-zero,
  booking status normalization, `isEarned`, `daysToConfirm` (paymentVerifiedAt,
  never confirmedAt), `isStuckPending`, by-status counts, conversion %,
  stuck-pending rows (emails + title + days), top-5 grouping/sort/cap, avg days
  (payment-verified only), and the FakeFirestore `fetchData` join (missing
  farm -> Unknown, disabled-outfitter exclusion, email reuse/merge, graceful
  degradation).
- `test/admin_portal_v2_screen_test.dart` +6 Task 4 widget tests: all Task 4
  cards render; the province breakdown + both tables + status breakdown render;
  package counts derive from the `packages` collection; booking conversion
  derives from booking statuses; the zero-booking table shows an unbooked
  active package; a missing farm / missing `paymentVerifiedAt` never crashes
  (Unknown Province + Avg Days `"—"`).

## Verification

- `flutter analyze lib test`: **0 errors, 0 warnings**, 320 pre-existing
  info-level issues (unchanged baseline). None of the 320 touch the changed /
  new files.
- Targeted suites: `admin_portal_v2_operational_test` **25/25**,
  `admin_portal_v2_screen_test` **12/12**.
- Full suite: **2466 passed, 1 failed** — the single failure is the DOCUMENTED
  pre-existing `trial_onboarding_functions_contract_test` (v1-vs-v2 auth
  trigger), which the task explicitly says to ignore. No new failures.
- Env: Flutter **3.44.9** at `/tmp/flutter`; `LD_LIBRARY_PATH="$HOME/libs"`
  with the `~/libs/libsqlite3.so` symlink for the sqflite-FFI suites.
  `pubspec.lock` drift from `pub get` (test-only transitive churn) reverted.
- No Firestore rules / index / Storage / functions / manifest changes. No
  change to `admin_config` / `min_required_version`.

## Files

- NEW: `lib/features/admin/models/admin_operational_metrics.dart`,
  `lib/features/admin/services/admin_operational_metrics_service.dart`,
  `test/admin_portal_v2_operational_test.dart`.
- MODIFIED: `lib/features/admin/screens/admin_portal_v2_screen.dart`,
  `lib/features/admin/models/admin_user_metrics.dart` (`email` field),
  `test/admin_portal_v2_screen_test.dart`.

TASK 4 DONE
