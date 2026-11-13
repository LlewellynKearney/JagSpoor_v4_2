# TASK 5 — Admin Portal V2: Revenue KPIs

Branch `feature/admin-portal-v2` (base `221ccce`). Reuses the Task 3 / Task 4
pattern: fetch ONCE, aggregate LOCALLY. Revenue is a point-in-time snapshot
("as of now") and does **not** respond to the date filter.

## Scope guardrails honoured

- **Subscription revenue ONLY.** JagSpoor does NOT take booking payment
  in-app — booking payment is OFF-PLATFORM (EFT / cash). No booking amount is
  ever surfaced as revenue. The screen states this explicitly in the Revenue
  note.
- **No `demo@jagspoor.co.za` filter** — the demo account is purged.
- **Field truths**: `subscriptionProduct` (not `plan`),
  `subscriptionProvider` / `subscriptionPlatform` / `subscriptionSource` (not
  `paymentProvider`). `isPremiumActive` is COMPUTED from
  `premiumExpiry` / `hasActivePurchase` / `subscriptionStatus` (never read
  from a stored flag), exactly as Task 3 does.
- **No change** to `admin_config` / `min_required_version`. Not merged, not
  deployed.

## Prices — server truth (`functions/src/payfast/plans.ts:51-70`)

| Plan | Charge | MRR contribution |
| --- | --- | --- |
| Hunter Monthly | R34.99 | R34.99 |
| Hunter Yearly | R349.99 | R349.99 / 12 = **R29.17** |
| Outfitter Monthly | R299.99 | R299.99 |
| Outfitter Yearly | R2999.99 | R2999.99 / 12 = **R250.00** |

These are the FINAL, VAT-inclusive charges (Option A). The constants live in
`admin_revenue_metrics.dart` (`kHunterMonthlyZar` … `kOutfitterYearlyMrrZar`)
so there is one place to update if the catalog changes.

## P1 — Revenue model + pure aggregation

NEW `lib/features/admin/models/admin_revenue_metrics.dart`:

- `AdminPlanBucket` (hunterMonthly / hunterYearly / outfitterMonthly /
  outfitterYearly) with `mrrPerSubscriber` + `isOutfitter`.
- `resolveAdminPlanBucket(String?)` — tolerant of all three id families
  (`hunter_monthly`, `jagspoor_hunter_monthly`,
  `jagspoor_hunter_monthly_payfast`); detects role by substring, cycle by
  `year` / `annual` vs `month`. A blank / unrecognised id returns `null` so it
  is surfaced as "Unknown plan" instead of being silently mispriced.
- `AdminProviderBucket` (payfast / play / userChoice / unknown) +
  `resolveAdminProviderBucket(String?)` — `user_choice` is matched FIRST so a
  User Choice purchase is never swallowed by the `payfast` prefix match, then
  `payfast`, then Play (`play` / `google`). A blank / unrecognised value
  buckets as **Unknown** so the split reconciles.
- `formatAdminZar(double)` → `R1,234.56` (comma thousands, two decimals;
  pure string arithmetic, no `intl` dep).
- `AdminChurnedRow` — email + plan + `cancelledAt` (fallback `updatedAt`),
  rendered as `yyyy-MM-dd`.
- `AdminRevenueMetrics` — the KPI bundle:
  - **Total MRR** = Σ (bucket count × bucket MRR contribution).
  - **Hunter MRR** / **Outfitter MRR** split.
  - **ARR** = MRR × 12.
  - **Provider split** — counts + one-decimal % per bucket.
  - **Churned** — `subscriptionStatus == 'cancelled'` count + the sorted
    (newest-first) rows.
  - **Pipeline** = `trialActiveHunters × 34.99 +
    trialActiveOutfitters × 299.99`, labelled "PIPELINE — If all trials
    convert".
  - `AdminRevenueMetrics.aggregate(records, {now})` — pure + synchronous.
    Trial-active accounts already paying are excluded from the pipeline; a
    `dual` trial counts as a hunter (its `RoleGuard.defaultHomeFor` landing).

## P2 — `AdminUserRecord` gained two fields

`lib/features/admin/models/admin_user_metrics.dart`:

- `cancelledAt` — read from `subscriptionCancelledAt` / `subscription_cancelled_at`
  / `cancelledAt` / `cancelled_at`.
- `updatedAt` — read from `updatedAt` / `updated_at` (the churned-date
  fallback the brief specifies).

Both default to `null`, so a partial / legacy document still parses.

## P3 — Screen wiring (Revenue section)

`lib/features/admin/screens/admin_portal_v2_screen.dart`:

- `_bootstrap` now also computes `AdminRevenueMetrics.aggregate(records)` from
  the SAME user records Task 3 already fetched — **no extra Firestore read**.
  A filter change re-aggregates only the user metrics; the revenue snapshot is
  untouched (it ignores the filter).
- New **Revenue** section:
  - a 4-card grid — **Total MRR / ARR / Hunter MRR / Outfitter MRR** (all
    formatted `R1,234.56`);
  - an **MRR By Plan** breakdown (the four buckets × count + MRR contribution,
    plus an "Unknown plan (unpriced)" note when applicable);
  - a **PayFast vs Play Split** (four buckets: PayFast / Google Play / User
    Choice / Unknown, each `count · %`);
  - a **PIPELINE — If all trials convert** card (accent border) showing the
    value + the `(hunters × R34.99) + (outfitters × R299.99)` derivation;
  - a **Churned (Cancelled) — N** table (Email / Plan / Cancelled, explicit
    empty state);
  - a Revenue note clarifying subscription-only revenue + the off-platform
    booking-payment rule + the price table.
- Every card/table carries a `ValueKey` (`adminV2CardTotalMrr`,
  `adminV2CardArr`, `adminV2CardHunterMrr`, `adminV2CardOutfitterMrr`,
  `adminV2PlanSplit`, `adminV2ProviderSplit`, `adminV2PipelineCard`,
  `adminV2ChurnedTable`) so the widget tests assert on the exact surfaces.

## Tests

NEW `test/admin_portal_v2_revenue_test.dart` (29 tests):

- **Model / helper**: price constants; `mrrPerSubscriber` mapping;
  `resolveAdminPlanBucket` (PayFast ids, Play ids, alternative ids,
  case/annual tolerance, blank/unrecognised → null); `resolveAdminProviderBucket`
  (payfast, `payfast_alternative`, `user_choice`, the
  `user_choice_payfast` ordering guard, play/google_play, blank → unknown);
  `formatAdminZar`.
- **Aggregation**: empty → all-zero; the manual-calc MRR
  (2×34.99 + 29.17 + 299.99 + 250.00 = 649.14) with the hunter/outfitter split;
  ARR = MRR × 12; the canonical plan-split order; the provider split counts +
  percentages; a missing provider → Unknown; an unpriced active subscriber
  excluded from MRR but counted; a trial-only account is not a subscriber;
  the churned list (email + plan + `cancelledAt`); the `updatedAt` fallback;
  newest-first sort; the pipeline value; a paying subscriber is not also in
  the pipeline.
- **Screen**: all eight revenue surfaces render; the MRR card matches a manual
  calc from a Firestore spot-check (`R284.99`, ARR `R3,419.88`, hunter
  `R34.99`, outfitter `R250.00`); the pipeline card is labelled not-realized;
  the churned table shows email + plan + date; the zero state renders cleanly.

## Verification

- `flutter analyze lib test`: **0 errors, 0 warnings**, 320 pre-existing
  info-level issues (unchanged baseline). None of the 320 touch the changed /
  new files.
- Targeted suites: all four `admin_portal_v2_*` suites **97/97** (the 29 new
  Task 5 tests + the 68 Task 3/4 tests, no regressions).
- Full suite: see the run log — the only failure is the DOCUMENTED pre-existing
  `trial_onboarding_functions_contract_test` (v1-vs-v2 auth trigger), which the
  task explicitly says to ignore.
- Env: Flutter **3.44.9** at `/tmp/flutter`; `LD_LIBRARY_PATH="$HOME/libs"`
  with the `~/libs/libsqlite3.so` symlink for the sqflite-FFI suites.
  `pubspec.lock` drift from `pub get` (test-only transitive churn) reverted.
- No Firestore rules / index / Storage / functions / manifest changes. No
  change to `admin_config` / `min_required_version`. Not merged, not deployed.

## Files

- NEW: `lib/features/admin/models/admin_revenue_metrics.dart`,
  `test/admin_portal_v2_revenue_test.dart`.
- MODIFIED: `lib/features/admin/models/admin_user_metrics.dart`
  (`cancelledAt` + `updatedAt`),
  `lib/features/admin/screens/admin_portal_v2_screen.dart` (Revenue section).

TASK 5 DONE
