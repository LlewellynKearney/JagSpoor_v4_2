# Admin Portal V2

**Branch:** `feature/admin-portal-v2` · **Phase 1 (read-only) — COMPLETE.**
Not merged, not deployed. No change to `admin_config` / `min_required_version`.

---

## What this is

Admin Portal V2 is a modern, operator-only surface for JagSpoor's platform
admins. It is reached at the route **`/admin_portal_v2`** (admin-only) and from
the **"Admin Portal V2"** card in the existing `/admin_dashboard` Account
Management section.

Phase 1 delivers **read-only** pages plus a dashboard:

| Tab | What it shows |
| --- | --- |
| **Dashboard** | 4 KPI rows + 3 charts (see layout below) |
| **Users** | Email search, role filter (Hunter / Outfitter / Dual / No Role), trial + `subscriptionProduct` + `subscriptionProvider` + `createdAt`, plus a dedicated **No Role** list |
| **Packages** | Every package with title, outfitter, **province (joined from `farms/{farmId}`)**, status, `quantityAvailable`, `createdAt`; filters by status / province / outfitter |
| **Bookings** | Every booking with hunter email, outfitter email, package title, status, `createdAt`, and **days stuck** for Pending Approval > 7d; filter by status. Payment timing uses **`paymentVerifiedAt`**, never `confirmedAt` |
| **Revenue** | MRR, ARR, PayFast vs Play vs User Choice split, Churned, and **PIPELINE — If all trials convert** |

Every page performs **no writes** — Phase 1 is strictly read-only.

### Dashboard layout (as specified)

```
Row 1   Total Users | Hunters | Outfitters | No Role
Row 2   MRR | Trial Active | Trial→Paid % | Requests→Confirmed %
Row 3   Total Packages | Active | Sold Out | Packages 0 Bookings
Row 4   Charts:  New Users (7d bar) · Bookings By Status (donut)
                 · Packages Per Province (bar)
```

Below the four rows the dashboard keeps the full Task 3/4/5 breakdowns
(Audience / Packages / Bookings / Revenue detail grids + tables) so no
information from the earlier phases was lost.

---

## How to run locally

```bash
# 1. Get the SDK (Flutter 3.44.9 is the CI pin) and dependencies
flutter pub get

# 2. (Optional) point the app at a Firebase project you can sign into as admin
#    — the portal reads Firestore directly, client-side.

# 3. Run the app
flutter run
```

Then open the portal one of two ways:

* **Route** — navigate to **`/admin_portal_v2`** (e.g. paste
  `…/#/admin_portal_v2` in the web build, or `Navigator.pushNamed(context,
  '/admin_portal_v2')`).
* **In-app** — sign in as an admin, open **`/admin_dashboard`**, and tap the
  **"Admin Portal V2"** card in *Account Management*.

**Access:** the route is admin-only (`RoleGuard.adminOnlyRoutes` includes
`/admin_portal_v2`). A non-admin is denied and bounced to their own dashboard.
`requiresPremium: false` is set on the route so an admin whose personal
subscription lapsed can still open the operator portal.

**Tests:**

```bash
flutter analyze lib test
LD_LIBRARY_PATH="$HOME/libs" flutter test        # sqflite-FFI suites need the
                                                 # libsqlite3.so symlink
```

---

## Where the numbers come from

Everything is computed **client-side** from documents the admin can already
read — the fetch happens **once** and the date filter re-aggregates locally
(no extra Firestore read).

* `users/{uid}` → audience, trial/subscription, MRR/ARR, provider split,
  churned, pipeline, and the Users page.
* `packages/{id}` + `farms/{farmId}` (province join) → the Packages page and
  the Packages dashboard row.
* `bookings/{id}` → the Bookings page, the Requests→Confirmed % and the
  Bookings By Status donut.
* `outfitters/{uid}` → outfitter display names / emails for the joins.

### Field truths honoured

* **Trial / premium is COMPUTED**, never read from a stored flag — the same
  resolution as `entitlement_service.dart`, so the admin numbers agree with
  the in-app paywall gate.
* **Packages do NOT store `province`** — it is joined from `farms/{farmId}`;
  a missing farm lands in **"Unknown Province"** and is never dropped.
* **Bookings have no `confirmedAt`** — payment timing uses
  **`paymentVerifiedAt`** (gated on `paymentVerified == true`).
* Plan = **`subscriptionProduct`**, provider = **`subscriptionProvider`**
  (with the documented aliases).
* **No booking amount is ever shown as revenue** — JagSpoor does not take
  booking payment in-app (off-platform EFT / cash). Only **subscription**
  revenue is reported.
* All money is rendered **ZAR as `R1,234.56`** (`formatAdminZar`).

### Missing-field safety

A missing farm, a missing `paymentVerifiedAt`, a missing `subscriptionProduct`
/ `subscriptionProvider`, an empty document, or a disabled account **never
crashes** the portal — every field defaults, and every read is best-effort per
collection (one failing collection degrades to zeroes rather than throwing).

---

## Phase 1 vs Phase 2

**Done in Phase 1 (read-only):**

* The five-tab portal (Dashboard + Users + Packages + Bookings + Revenue).
* All filters (Users email search + role filter; Packages status / province /
  outfitter; Bookings status; Dashboard date filter for New Users).
* The four dashboard KPI rows and the three charts.
* ZAR formatting + missing-field safety.
* Tests: `test/admin_portal_v2_pages_test.dart` (16 widget tests),
  `test/admin_portal_v2_pages_model_test.dart` (22 model tests), plus the
  pre-existing Task 3/4/5 suites (97 tests) — all green.

**NOT done — deferred to Phase 2 (write actions):**

* **No write actions anywhere.** No role edits, no account disable/enable, no
  package approve/archive, no booking status changes, no refund / churn
  actions, no CSV export from the pages. Phase 1 is intentionally read-only.
* No server-side KPI function changes (`getAdminPortalKpis` is untouched).
* No pagination — each collection is read with a bounded `scanLimit` (5000);
  a larger production dataset would need paging in Phase 2.
* No real-time listeners — the portal is fetch-once + manual **Refresh**
  (pull-to-refresh / the AppBar refresh button).
* No per-row drill-down / detail modals (Phase 2).
* No CSV / PDF export of the page tables (Phase 2).

---

## Files

**New**

* `lib/features/admin/pages/admin_users_page.dart`
* `lib/features/admin/pages/admin_packages_page.dart`
* `lib/features/admin/pages/admin_bookings_page.dart`
* `lib/features/admin/pages/admin_revenue_page.dart`
* `lib/features/admin/widgets/admin_v2_common.dart`
* `lib/features/admin/widgets/admin_v2_charts.dart`
* `test/admin_portal_v2_pages_test.dart`
* `test/admin_portal_v2_pages_model_test.dart`
* `docs/admin-portal-v2.md` (this file)

**Modified**

* `lib/features/admin/screens/admin_portal_v2_screen.dart` — tab bar +
  Dashboard tab (4 rows + 3 charts) + page wiring.
* `lib/features/admin/models/admin_user_metrics.dart` — role category
  (`AdminUserRoleCategory`), audience counts, per-day new-user series, date /
  trial display helpers.
* `lib/features/admin/screens/admin_dashboard_screen.dart` — entry-card copy.

**Untouched:** `lib/main.dart` route wiring, `role_guard.dart`
(`/admin_portal_v2` was already admin-only), Firestore rules / indexes /
Storage, Cloud Functions, manifests, `admin_config`, `min_required_version`.

---

## Verification (this sandbox)

* `flutter analyze lib test`: **0 errors, 0 warnings**, 320 pre-existing
  info-level issues (the documented baseline). No issue touches any
  changed / new file.
* Targeted suites: the two new Task 6 suites **38/38**; the four
  pre-existing `admin_portal_v2_*` suites **97/97** — no regressions.
* Full suite: only the DOCUMENTED pre-existing
  `trial_onboarding_functions_contract_test` fails (v1-vs-v2 auth trigger) —
  explicitly excluded by the task.
* Env: Flutter **3.44.9** at `/tmp/flutter_sdk_dl/flutter`;
  `LD_LIBRARY_PATH="$HOME/libs"` with the
  `~/libs/libsqlite3.so → /usr/lib/x86_64-linux-gnu/libsqlite3.so.0` symlink
  for the sqflite-FFI suites. `pubspec.lock` drift from `pub get` reverted.

---

## Deploy status

**Not deployed.** No Hosting deploy, no Rules deploy, no Functions deploy.
The branch is pushed to `origin/feature/admin-portal-v2` for preview only.
