# REFERRAL_PRICING_FIX.md — production-safe pricing + referral grant (v9)

Verification record for the "wire Admin Portal as control plane, Play Console
as charge truth, referral actually grants value server-side" change set.

**Summary:** the Admin Portal is now the single pricing control plane
(`admin_config/pricing`), the dashboards read the live Play price with an
admin fallback, MRR is computed live from subscriber counts × admin rates, the
referral reward is granted server-side by a Cloud Function (not cosmetic promo
copy), the client can no longer write trial/entitlement fields, and a Play-
policy "Restore Purchases" action + a Play-vs-admin price divergence warning
are wired in.

---

## 1. Before / after (file:line)

### Admin Portal control plane

| Concern | Before | After |
| --- | --- | --- |
| Subscription SAVE | `admin_config/pricing` written with only `hunterSubscriptionZAR` / `outfitterSubscriptionZAR` camelCase keys, no audit stamp | `SubscriptionConfig.toMap` (`lib/features/admin/services/subscription_config_service.dart`) writes canonical `hunter_monthly` / `outfitter_monthly` **and** the camelCase aliases; `saveConfig` adds `updatedAt: serverTimestamp` + `updatedBy: uid` |
| SAVE handler | `admin_dashboard_screen.dart` saved straight through | `_saveSubscriptionConfig` (≈line 164) persists via `SubscriptionConfigService.saveConfig`, recomputes MRR from the live metrics, then re-runs the divergence check |
| Referral rewards SAVE | `admin_config/referral_rewards` wrote `hunterRewardZAR` / `outfitterRewardZAR` only | `ReferralRewardConfig.toMap` (`lib/features/referral/models/referral_reward_config.dart:73-78`) now writes canonical `hunter` / `outfitter` + `rewardType: 'extension_days'` + `hunter_days: 30` + `outfitter_days: 30`; `ReferralRepository.saveRewardConfig` stamps `updatedAt` + `updatedBy` |
| Rules | `admin_config/*` already admin-write / signed-in-read | Verified unchanged and correct (`firestore.rules` `match /admin_config/{docId}`): `allow read: if isSignedIn(); allow write: if isAdmin();` |

### Pricing source of truth

| Concern | Before | After |
| --- | --- | --- |
| Product IDs | `subscription_pricing.dart:32-35` | **Unchanged** (`jagspoor_hunter_monthly` / `jagspoor_outfitter_monthly`) |
| Fallback prices | `subscription_pricing.dart:58-59` hard-coded `19.99` / `199.99`, used as-is | Control-plane default `29.99` / `299.99`, and `resolveMonthlyPrice(tier, {playRawPrice})` (≈`:72`) resolves **live Play `rawPrice` → `admin_config/pricing` → hard-coded last resort** |
| Admin fallback read | none | `SubscriptionConfigService.getFallbackPrice(tierKey)` reads `admin_config/pricing` (with in-memory cache) |
| Play fetch | `play_billing_service.dart:137` `loadProducts()` | **Unchanged** (live `rawPrice` is the charge truth) |
| Subscription screen | `subscription_screen.dart:60-66` live price preferred, static fallback | Live `rawPrice` preferred, `admin_config/pricing` fallback, hard-coded last resort |
| Hunter dashboard card | `hunter_dashboard.dart:383` hard-coded `R29.99` | `_hunterMonthlyPrice` (init `hunterMonthlyPriceZAR`) refreshed by `resolveMonthlyPrice(SubscriptionTier.hunter)` in `_loadDashboardData`; card renders `R${_hunterMonthlyPrice.toStringAsFixed(2)}/month` (≈`:398`) |
| Outfitter dashboard card | `outfitter_dashboard.dart:373` hard-coded `R299.99` | Same pattern with `SubscriptionTier.outfitter` (≈`:388`) |

### MRR

| Concern | Before | After |
| --- | --- | --- |
| MRR box | implied fixed `18 × 29.99 + 2 × 299.99 ≈ R1139.80` | live: `SubscriptionRevenue.monthlyRecurringRevenue` = `hunterCount × config.hunterSubscriptionZAR + outfitterCount × config.outfitterSubscriptionZAR`, where counts come from `AdminMetrics.activeHunters` / `totalOutfitters` and rates from `admin_config/pricing` (`admin_dashboard_screen.dart` `SubscriptionConfigService.computeRevenue(...)` call sites) |

### Referral flow (cosmetic → real)

| Concern | Before | After |
| --- | --- | --- |
| Reward grant | promo code displayed a discount; Play charged full price; nothing extended the referrer | On `referral_conversions/{id}` create, the v2 Firestore trigger `onReferralConversionCreated` (`functions/src/referral.ts`) validates the parties, resolves reward days from `admin_config/referral_rewards`, extends the **referrer's** entitlement via `writeEntitlement` (same writer as Play validation), and marks the conversion `granted` |
| Idempotency | none | Trigger no-ops when the conversion is already `granted`/`rewarded`, and rejects a second grant for the same `referredUserId` (`already_rewarded`) |
| Client expiry writes | client could write the trial window | client writes removed; only the Admin SDK writes entitlement (rules freeze, §5) |
| Reward defaults | `19.99` / `199.99` | `29.99` / `299.99` with `rewardType: extension_days`, 30 days per tier (`lib/features/referral/models/referral_conversion.dart` `ReferralRewards`, and `functions/src/referral.ts` `DEFAULT_*`) |

### Restore Purchases & divergence

| Concern | Before | After |
| --- | --- | --- |
| Restore Purchases | missing (Play policy gap) | `_buildRestoreButton` (`subscription_screen.dart:872`, key `restorePurchasesButton`) calls the existing `PlayBillingService.instance.restorePurchases()` (`_restorePurchases` ≈`:365`); always available |
| Divergence warning | none | `_buildPriceDivergenceBanner` (`admin_dashboard_screen.dart:469`) renders when live Play `rawPrice` differs from `admin_config/pricing` by > R0.01: *"Play Console price Rxx.xx != Admin pricing Ryy.yy — update Play Console base plan to match."* |

### Trial-abuse security

| Concern | Before | After |
| --- | --- | --- |
| `users/{userId}` write rule | froze entitlement fields (`isPremium`, `premiumExpiry`, `subscriptionSource`, `subscriptionProduct`, `subscriptionPlayPurchaseToken`, `payfastPaymentId`, `entitlementUpdatedAt`) | **also freezes** `trialEndsAt`, `trialEnd`, `subscriptionTrialEndsAt`, `trialStartedAt`, `trialStart`, `subscriptionTrialStart`, `subscriptionStatus`, `createdAt`, `referralCodeUsed` (`firestore.rules:151-179`) using the same change-detection shape, so a client cannot widen its own trial via any alias |
| Client trial writes | `markTrialStarted` wrote both trial schemas + status; `backfillTrialSchemaAliases` backfilled aliases | `markTrialStarted` writes **only** client-owned `subscriptionTier` / `subscriptionPromoCode` / `subscriptionProvider`; `backfillTrialSchemaAliases` is a no-op; new read-only `readTrialState()` for inspection (`subscription_status_service.dart`) |
| Demo reviewer seed | wrote `subscriptionStatus`/renewal fields | omits every frozen field (`demo_reviewer_service.dart`) |
| Authoritative trial | backend `initializeNewUserTrial` Auth `onCreate` trigger (unchanged) | unchanged — still the sole trial provisioner |

---

## 2. Play Console steps (charge truth)

The app's display/MRR fallback follows the Admin Portal; the **actual charge**
is the Play base plan. Keep them equal.

1. Play Console → **Monetize → Products → Subscriptions**.
2. Open `jagspoor_hunter_monthly` → base plan → set the price to
   **R 29.99 / month** (matching `admin_config/pricing.hunter_monthly`).
3. Open `jagspoor_outfitter_monthly` → base plan → set the price to
   **R 299.99 / month** (matching `admin_config/pricing.outfitter_monthly`).
4. Save + activate the base plans.
5. (Optional — trial via Play) On each base plan add a **free-trial offer**
   of **30 days**. If you prefer to keep the app-side trial path (the backend
   `initializeNewUserTrial` trigger already grants a 30-day trial), you do not
   need a Play offer — but a Play offer makes the trial survive reinstall.
6. After the base plans are live, open the Admin Portal. If a divergence
   banner appears, the Play price and the admin price disagree — fix whichever
   is wrong and re-check.

Product IDs must remain `jagspoor_hunter_monthly` /
`jagspoor_outfitter_monthly` under application id `za.co.jagspoor.app`.
Current Admin Portal defaults: **R 29.99 / R 299.99** per month.

---

## 3. Deploy steps

```bash
# 1. Firestore rules (trial-field freeze + admin_config commentary)
npx firebase-tools deploy --only firestore:rules

# 2. Cloud Functions (referral grant trigger + reward-config loader)
(cd functions && npm install && npm run build)
npx firebase-tools deploy --only functions
```

Until the rules deploy, client writes that touch a frozen field are rejected
server-side (the client no longer sends them, so this is defence-in-depth).
Until the function deploys, conversions stay `pending` (no reward granted) —
the client-side flow still records the conversion.

The Admin Portal SAVE writes require the signed-in user to be an admin
(`isAdmin()`); `admin_config` reads are open to any signed-in user.

---

## 4. Verification performed

- `flutter test --reporter=compact` — full suite green (see below).
- `flutter analyze` — **0 errors, 0 warnings** (320 pre-existing info-level
  items; unchanged baseline).
- `cd functions && npm test` — **40/40 pass** (incl. new reward-default +
  grant-trigger export tests).
- `cd functions && npx tsc --noEmit` — clean.

### Tests updated for the new contracts

CRLF normalization from commit `c757c22` is preserved in the structural
contract suites (`firestore_rules_seeding_test.dart`,
`admin_analytics_enhancements_test.dart`, etc.).

| File | Change |
| --- | --- |
| `test/subscription_screen_test.dart` | Seeds `admin_config/pricing` (29.99/299.99) via `SubscriptionConfigService.firestoreForTesting`; price expectations updated to R29.99 / R299.99 / promo R26.99 |
| `test/subscription_status_service_test.dart` | `markTrialStarted` now asserted to write **only** client-owned metadata (never a frozen field); added `readTrialState` coverage |
| `test/entitlement_trial_status_test.dart` | New "server-owned trial window" + "backfill disabled" + `readTrialState` groups |
| `test/referral_models_test.dart` | Default reward expectations → 29.99 / 299.99 |
| `test/referral_rewards_admin_card_test.dart` | Default field text → 29.99 / 299.99 |
| `test/demo_reviewer_service_test.dart` | Asserts the seed does **not** write `subscriptionStatus` (frozen) |
| `test/referral_reward_admin_config_test.dart` | `rewardType` / days round-trip |
| `test/firestore_rules_seeding_test.dart` | Frozen-field list expanded (trial window + `createdAt` + `referralCodeUsed`) |
| `test/admin_analytics_enhancements_test.dart` | SubscriptionConfig round-trip includes canonical keys |
| `functions/test/referral.test.js` | Reward defaults + `rewardDaysForTier` + grant-trigger export |

Final full-suite result: **1813 passed / 0 failed** (`flutter test
--reporter=compact`, exit 0).

---

## 5. Notes / follow-ups

- **No new dependencies.**
- `google-services.json` still registers `com.example.jagspoor` while the app
  id is `za.co.jagspoor.app` — see `GOOGLE_SERVICES_FIX.md` for the Console
  regeneration steps. Not auto-fixed (would require credentialed Firebase
  access).
- A store-side "Restore Purchases" is required for Play policy and is now
  present on the subscription screen.
- The legacy camelCase config keys are still written as read aliases so a doc
  written by an older build resolves; the canonical snake_case keys are the
  source of truth.
</task>
</file_text>
