# JagSpoor — Google Play Billing Security & Flow Audit

**App:** JagSpoor (`za.co.jagspoor.app`)
**Live:** 1.0.11+11 · **In flight:** 1.0.12+12 (Google Sign-In SHA fix)
**Audit date:** 2026-10-14
**Scope:** Read-only audit. No code changed. Baseline for the planned 1.0.13 Butchery/Taxidermy subscription work.
**Method:** Source review of `lib/`, `functions/src/`, `firestore.rules`, `storage.rules`, `android/`, `pubspec.*`; targeted greps; static read of every billing code path.

---

## 1. Executive Summary — the three biggest risks

> **⚠️ Both CRITICAL findings are client-side Firestore rule holes. A single `update()` call from any signed-in account grants permanent free premium access, and a second one grants the Admin Portal. This is a live, one-line exploit against the production project.**

### 🔴 CRITICAL #1 — Any user can self-assign `role: 'admin'` → paywall bypass **and** Admin Portal

`users/{uid}.role` is **not frozen** by `firestore.rules`. The only write guards on `users/{uid}` are the sensitive-PII fields (`noSensitiveFieldAdded()`), `deviceFingerprint`, and the entitlement/trial fields — `role` is freely client-writable.

- Rule that allows it: `firestore.rules:164-231` (no `role` clause anywhere in the guard).
- Consumers that trust it:
  - `AdminAuthGuard.isCurrentUserAdmin()` — `lib/features/admin/services/admin_auth_guard.dart:71-73` (`userDoc.data()?['role'] == 'admin'`).
  - `isAdmin()` rule helper — `firestore.rules:19-25` (`get(...).data.role == 'admin'`).
  - `UserRoleProvider.resolveRole()` — `lib/features/auth/services/user_role_provider.dart:152-169`.
- Paywall bypass: `lib/features/auth/widgets/role_guarded_route.dart:104` skips the entitlement check entirely for `role == AppRole.admin`.

**Exploit (exact steps):**
```dart
// Signed in as any normal account (even a brand-new trial account):
await FirebaseFirestore.instance
    .collection('users').doc(myUid)
    .update({'role': 'admin'});   // ALLOWED by firestore.rules
```
Reload the app → `resolveRole()` returns `admin` → `/admin_dashboard` opens, and the entitlement gate at `role_guarded_route.dart:104` is skipped, so the paywall never appears. This also grants every `isAdmin()`-guarded Firestore collection (admin analytics, admin writes, etc.).

### 🔴 CRITICAL #2 — Any user can forge `subscriptionStatus: 'active'` → permanent free premium

The `users/{uid}` rule permits a client to move `subscriptionStatus` to `'active'` from a trial state:

- `firestore.rules:211-216`:
  ```
  && (!('subscriptionStatus' in request.resource.data)
    || (resource != null
      && (request.resource.data.subscriptionStatus == resource.data.subscriptionStatus
        || (request.resource.data.subscriptionStatus == 'active'
          && ('subscriptionStatus' in resource.data)
          && resource.data.subscriptionStatus in ['trialing', 'trial', 'active']))))
  ```
- Every newly registered account is stamped `subscriptionStatus: 'trialing'` by the backend `initializeNewUserTrial` trigger. So `trialing → active` is a **permitted** client transition.
- `isPro: true` can be set in the *same* write (`firestore.rules:221-225`).
- `isPremiumActive()` then returns `true` with **no expiry**: `lib/services/entitlement_service.dart:119-128` — `subscriptionStatus == 'active'` is treated as active when `premiumExpiry == null`.

**Exploit (exact steps):**
```dart
await FirebaseFirestore.instance
    .collection('users').doc(myUid)
    .update({
      'subscriptionStatus': 'active',
      'isPro': true,
    });   // ALLOWED — trialing -> active transition
```
The dashboard unlocks immediately (`watchMyEntitlement` → `isPremiumActive` → true), and it never expires because no `premiumExpiry` is required for the status-only path.

### 🟠 HIGH #3 — Purchases from the Paywall screen are never acknowledged → Google auto-refunds in 3 days

Acknowledgment = `completePurchase()`. It is called in **exactly one place** — `lib/features/subscription/subscription_screen.dart:331` — and only *after* the server verification round-trip succeeds. The **`PaywallScreen` has no purchase listener at all** (`lib/features/subscription/paywall_screen.dart` — no `purchaseStream.listen`, no `completePurchase`, no `verifyGooglePlayPurchase`, no `recordPurchase`).

The Paywall is the primary surface an **expired-trial** user sees (`role_guarded_route.dart:106,161-163`). A user who subscribes there:
- purchase is never recorded, never server-verified, never acknowledged → **Google refunds it after 3 days** and the user is charged nothing while briefly unlocking premium (if any listener elsewhere fires) — or is stuck paid-but-no-access.

Additionally, even on the subscription screen, if `verifyGooglePlayPurchase` throws, the code `continue`s (`subscription_screen.dart:316-330`) **before** `completePurchase` at line 331 → unacknowledged → refund.

**No `acknowledgePurchase` call exists anywhere** (`grep -rn acknowledgePurchase lib functions/src` → only a doc comment). The Flutter `in_app_purchase` API folds acknowledge into `completePurchase()`, so the finding is "acknowledge is not reliably reached", not "wrong API used".

---

## 2. What the codebase actually contains (schema correction)

| Item in the brief | Reality in the repo |
|---|---|
| `lib/services/billing/`, `lib/core/billing/`, `lib/widgets/paywall/` | **Do not exist.** Billing lives under `lib/features/subscription/` + `lib/services/entitlement_service.dart`. |
| `subscriptions/{uid}` collection | **Does not exist.** Entitlement is stored on `users/{uid}` (mirrored to `entitlements/{uid}`). No `subscriptions` collection anywhere (`grep` → 0 hits). |
| RevenueCat / Stripe | **Not used.** `grep` for `revenuecat`/`stripe` → 0 hits. Only Google Play Billing (`in_app_purchase: ^3.3.0`). |
| Roles hunter/internationalHunter/outfitter/butchery/taxidermy/admin | **Only 4 exist** in `AppRole` (`user_role_provider.dart:8-30`): `admin`, `outfitter`, `hunter`, `dual`. No `internationalHunter`, `butchery`, or `taxidermy`. |
| Free trial 14 days | Repo uses **30 days** (`subscription_pricing.dart:47`, `entitlement_service.dart:23`). |
| Prices R199/R399 | Repo uses **R34.99 hunter / R299.99 outfitter** (VAT-inclusive Option A) as the Play catalog figures. |

**Billing inventory (files):**
- `lib/features/subscription/services/play_billing_service.dart` — plugin adapter (load/buy/restore/complete).
- `lib/features/subscription/services/play_purchase_recorder.dart` — writes `users/{uid}` + `purchases/{uid}_{productId}`.
- `lib/features/subscription/services/subscription_pricing.dart` — tiers, product ids, VAT math, promo engine.
- `lib/features/subscription/services/subscription_status_service.dart` — reads/writes `users/{uid}` subscription mirror.
- `lib/features/subscription/paywall_screen.dart` — paywall.
- `lib/features/subscription/subscription_screen.dart` — checkout / purchase listener / restore.
- `lib/services/entitlement_service.dart` — entitlement model + server callable.
- `functions/src/entitlement.ts` — `validateGooglePlayPurchase`, `onGooglePlayRTDN`, `payfastITN`, `writeEntitlement`.
- `android/app/src/main/AndroidManifest.xml:14` — `com.android.vending.BILLING` present ✅.
- `pubspec.yaml:136` — `in_app_purchase: ^3.3.0` (resolves `in_app_purchase_android 0.5.0`, Billing Library 8.x) ✅.

---

## 3. Flow-by-flow results

### A) Purchase Flow

| Sub-check | File:Line | Verdict | Risk | Notes / Fix |
|---|---|---|---|---|
| `acknowledgePurchase` / `completePurchase` reached | `subscription_screen.dart:331` (only site) | **FAIL** | CRITICAL | Paywall path never acknowledges; verification-failure path `continue`s before ack. **Fix:** acknowledge (`completePurchase`) as soon as `purchased`/`restored` arrives, before/independent of server verify; add a listener to `PaywallScreen`. |
| Server-side token verification | `entitlement_service.dart:346-401` → `entitlement.ts:227-289` | **PASS** | LOW | `validateGooglePlayPurchase` calls Play Developer API `purchases.subscriptionsv2.get`, rejects expired/cancelled, writes server-authoritative entitlement. |
| Replay protection (same token reused) | `entitlement.ts:227-289` | **PARTIAL** | MEDIUM | Token is validated against Google, but the function does not assert the token is not already bound to another uid, nor dedupe a re-submitted token to a different account. Low practical risk (token is tied to the Play account) but no explicit binding check. |
| Pending purchases (4-hour hold) | `subscription_screen.dart:276-334` | **FAIL** | MEDIUM | Only `purchased`/`restored`/`error` handled; `PurchaseStatus.pending` is silently ignored → no UI, no state, no retry on the eventual completion. |
| Client-side-only entitlement (hackable) | `play_purchase_recorder.dart:152-158` | **FAIL** | HIGH | The recorder writes `subscriptionStatus:'active'` + `isPro:true` **client-side**, and the rules allow it (see Critical #2). A patched client skips Play entirely and writes the same fields. |

### B) Entitlement / Gate Logic

| Sub-check | File:Line | Verdict | Risk | Notes / Fix |
|---|---|---|---|---|
| Where the subscription is checked | `role_guarded_route.dart:104-113` | **PARTIAL** | HIGH | Checked **once at route entry** for `/hunter_dashboard`, `/outfitter_dashboard`, `/admin_dashboard` only. Sub-screens are `Navigator.push`ed from a gated dashboard, so they inherit the gate — but the 4 non-dashboard named routes (`/add_trophy` etc., `main.dart:329+`) are **not** entitlement-gated. |
| Cached / offline bypass | `entitlement_service.dart:314-333` | **FAIL** | HIGH | Falls back server → cache → empty. The cache is a plain local Firestore cache the user can't easily forge, **but** the real bypass is the writable source doc (Critical #2), and `isTrialActive`'s last resort grants a 30-day window purely from `createdAt` (`entitlement_service.dart:152-169`). |
| `subscriptions/{uid}` read own / write only CF | N/A | **N/A** | — | Collection does not exist. `entitlements/{uid}` is `read own / write:false` ✅ (`firestore.rules:259-262`). |
| Can user set `role=admin` or `status=active` by direct write | `firestore.rules:164-231` | **FAIL** | CRITICAL | Both. `role` unfrozen; `trialing→active` transition allowed. See Critical #1/#2. |
| `if (subscription != null)` = free leak | `entitlement_service.dart:119-128,152-158` | **FAIL** | HIGH | `isPremiumActive` returns true on `status=='active'` **with null expiry**; `isTrialActive` returns true on a trial status **with no timestamp**. Absence of data grants access rather than denying. |

### C) Multi-Role Pricing

| Sub-check | File:Line | Verdict | Risk | Notes / Fix |
|---|---|---|---|---|
| Price from Play Console vs hardcoded | `paywall_screen.dart:62-76`; `subscription_pricing.dart:68-69` | **PASS (display)** | LOW | Display price comes from the live Play catalog (`ProductDetails.rawPrice` → VAT-inclusive). Hardcoded R34.99/R299.99 exist **only** as last-resort fallbacks. |
| Correct plan per role | `subscription_pricing.dart:14-17,39-42` | **FAIL** | MEDIUM | Only hunter/outfitter tiers. `fromAppRole` maps **everything non-outfitter → hunter**; `fromPlayProductId` maps **everything non-outfitter → hunter**. No `internationalHunter`/`butchery`/`taxidermy` tier. |
| Currency ZAR vs USD | `subscription_pricing.dart:68-83` | **FAIL** | MEDIUM | All VAT/price math is hardcoded to 15% SA VAT + ZAR `R`; no USD/international branch. An international hunter is shown/charged the SA ZAR product. |

### D) Lifecycle

| Sub-check | File:Line | Verdict | Risk | Notes / Fix |
|---|---|---|---|---|
| Cancel / expire | `entitlement.ts:210,221-272` | **PASS** | LOW | RTDN types 12/13/9 revoke entitlement. |
| Grace period / on-hold / past_due | `entitlement.ts:186-201,210` | **FAIL** | HIGH | `getPlayPurchaseInfo` lumps grace + on-hold into "active" but **no RTDN notification types** for grace/on-hold/renewal are handled; no `'grace'`/`'on-hold'`/`'past_due'` statuses exist in the model (`grep` → 0 hits). Access relies entirely on the client's `premiumExpiry`. |
| `currentPeriodEnd` updated via RTDN/webhook | `entitlement.ts:221-272` | **PARTIAL** | MEDIUM | Renewals are **not** pushed to Firestore; `premiumExpiry` only advances when the app re-verifies. A silent renewal with no app open → stale expiry → possible false lockout. |
| `purchasesUpdated` listener / Cloud Function | `entitlement.ts` | **PARTIAL** | MEDIUM | `validateGooglePlayPurchase` (client-invoked) + `onGooglePlayRTDN` (revocations only) exist; there is **no** renewal/renewal-time RTDN handler. |
| Restore on reinstall / new device | `hunter_dashboard.dart:95-102`, `outfitter_dashboard.dart:105-112`, `subscription_screen.dart:420-425` | **PASS** | LOW | `restorePurchases()` wired on both dashboards + an explicit Restore button. |
| Trial once-per-user vs abusable | `entitlement_service.dart:152-169`; `firestore.rules:193-210` | **PARTIAL** | MEDIUM | Trial timestamps are frozen in rules (good) and the backend trigger provisions once. But the `createdAt`-window fallback means a doc with a recent `createdAt` and no trial dates still gets access — and `createdAt` immutability relies on the same writable doc. |

### E) Security

| Sub-check | File:Line | Verdict | Risk | Notes / Fix |
|---|---|---|---|---|
| Bypass with patched APK / Lucky Patcher | `firestore.rules:164-231` | **FAIL** | CRITICAL | A patched client can write `subscriptionStatus:'active'`/`role:'admin'` directly to Firestore (rules allow). No client-side signature check is relevant — the hole is server-side. |
| Server-side Google Play Developer API verification | `entitlement.ts:168-289` | **PASS** | LOW | Present and correct for the paths that call it. |
| Subscription docs protected by rules | `firestore.rules:130-233,259-281` | **FAIL** | CRITICAL | Entitlement **fields** are frozen (good) but the `'active'` transition + `role` are not. See §4. |
| All rules for subscriptions/users/bookings | §4 below | — | — | — |

---

## 4. Firestore rules — are they secure?

### Secure ✅
```js
// entitlements/{uid} — server-write-only mirror (firestore.rules:259-262)
match /entitlements/{entitlementId} {
  allow read: if isSignedIn() && request.auth.uid == entitlementId;
  allow write: if false;              // only Admin SDK (Cloud Functions)
}

// purchases/{id} — owner-scoped transaction record (firestore.rules:273-281)
match /purchases/{purchaseId} {
  allow read:   if isSignedIn() && resource.data.uid == request.auth.uid;
  allow create: if isSignedIn() && request.resource.data.uid == request.auth.uid;
  allow update: if isSignedIn() && resource.data.uid == request.auth.uid
                                && request.resource.data.uid == request.auth.uid;
  allow delete: if isAdmin();
}
```
The premium fields (`isPremium`, `premiumExpiry`, `subscriptionSource`, `subscriptionProduct`, `subscriptionPlayPurchaseToken`, `payfastPaymentId`, `entitlementUpdatedAt`) and the trial timestamps are all frozen with change-detection (`firestore.rules:169-210`) — a client genuinely cannot fabricate `isPremium:true` or extend a trial window. **This part is well done.**

### Vulnerable ❌
```js
// users/{userId}  (firestore.rules:164-231) — excerpts
allow write: if isSignedIn() && request.auth.uid == userId
  && noSensitiveFieldAdded()                       // PII only
  && <deviceFingerprint immutability>
  && <isPremium / premiumExpiry / subscriptionSource / … frozen>
  && <trial timestamps frozen>
  && (!('subscriptionStatus' in request.resource.data)
      || (resource != null
        && (request.resource.data.subscriptionStatus == resource.data.subscriptionStatus
          || (request.resource.data.subscriptionStatus == 'active'      // ⛔ HOLE
            && ('subscriptionStatus' in resource.data)
            && resource.data.subscriptionStatus in ['trialing','trial','active']))))
  && <isPro rule that allows isPro:true when status becomes 'active'>
  && <createdAt / referralCodeUsed frozen>;
  // ⛔ 'role', 'isDualRole', 'roles', 'subscriptionTier' are NOT frozen
```

**Holes:**
1. `subscriptionStatus` `trialing→active` transition is client-permitted → free premium (Critical #2).
2. `role` / `isDualRole` / `roles` are client-writable → admin escalation + tier upgrade (Critical #1).
3. `subscriptionTier` is client-writable → a hunter can claim the outfitter tier.
4. `users` `allow list: if isSignedIn()` (`firestore.rules:263-265`) lets any signed-in user enumerate all user documents (privacy, not billing — flagged for completeness).

---

## 5. Static analysis summary

- `grep -rn "isPurchased" lib` → **0 hits** (no local purchase flag to spoof — good).
- `grep -rn "acknowledgePurchase" lib functions/src` → **0 real calls** (doc comment only).
- `grep -rn "completePurchase" lib` → `subscription_screen.dart:331` (1 call) + definitions.
- `grep -rn "revenuecat|stripe"` → **0 hits**.
- `grep -rn "subscriptions"` (collection) → **0 hits** — collection does not exist.
- `grep -rn "internationalHunter|USD|butchery|taxidermy"` (roles) → **0 role hits**.
- `grep -rn "expired|grace|on-hold|past_due"` (lifecycle) → **0 hits**.
- `grep -rn "TODO|FIXME|HACK"` in billing → 1 (a benign `TODO #5` doc reference).
- `flutter analyze` was **not run** in this sandbox (no Flutter SDK); analysis was performed by source review. Run `flutter analyze | grep -i billing` on a machine with the SDK to confirm (expected: 0 errors; the pre-existing info-level baseline).

---

## 6. Recommendations

### Must-fix before 1.0.13 (Butchery/Taxidermy subscription)

1. **Freeze `role`, `isDualRole`, `roles`, `subscriptionTier` in `firestore.rules` `users/{uid}`.** Mirror the existing change-detection pattern used for the entitlement fields. Role must be set only by Cloud Functions (or an admin-only path). *(Closes Critical #1 and the tier-upgrade hole.)*
2. **Remove the client `subscriptionStatus → 'active'` transition** from `firestore.rules:211-216` (and the paired `isPro` clause at 221-225). Entitlement status must be written **only** by `writeEntitlement` (Cloud Functions, Admin SDK). The purchase recorder should be deleted or reduced to writing the `purchases` transaction doc only. *(Closes Critical #2.)*
3. **Acknowledge purchases reliably.** Add a purchase listener to `PaywallScreen` (or hoist a single app-level listener) and call `completePurchase()` immediately on `purchased`/`restored`, **before** and independent of server verification; ensure the verification-failure branch still acknowledges. *(Closes High #3 — stops the 3-day auto-refund.)*
4. **Add Butchery / Taxidermy / International Hunter tiers.** Extend `AppRole` + `SubscriptionTier` + `playProductId` mapping, the `GOOGLE_PLAY_PRODUCTS` allow-list in `entitlement.ts:40-43`, and the pricing/currency math (USD branch for international). Update `SubscriptionTier.fromAppRole` / `fromPlayProductId` so a non-hunter/outfitter role does not silently resolve to the cheapest tier.
5. **Handle pending purchases** (`PurchaseStatus.pending`) with a visible "payment pending" state and re-processing on completion.

### Nice-to-have

6. **Wire full RTDN lifecycle:** subscribe to `SUBSCRIPTION_RENEWED`, `SUBSCRIPTION_IN_GRACE_PERIOD`, `SUBSCRIPTION_ON_HOLD`, and update `premiumExpiry` server-side on renewal so the client mirror never goes stale.
7. **Add token↔uid binding + dedupe** in `validateGooglePlayPurchase` (reject a token already bound to a different uid; idempotent re-verify).
8. **Gate the remaining named routes** (`/add_trophy`, etc.) with `RoleGuardedRoute(requiresPremium: true)` or re-check entitlement inside each feature.
9. **Tighten `users` list** (`firestore.rules:263-265`) to admin-only or remove.
10. **Remove/rotate the hardcoded demo-reviewer credentials** (`demo_reviewer_config.dart` — `demo@jagspoor.co.za` / `JagSpoorDemo2026!`, `enabled = true`) before a broad production release; gate behind a build flavor.
11. **Bind the entitlement to the entitlement mirror** — have gates read `entitlements/{uid}` (write:false) instead of `users/{uid}` where feasible, reducing the blast radius of any future `users` rule regression.

---

## 7. Appendix — all entitlement checks & where they can be bypassed

| Check | File:Line | Bypassable? | How |
|---|---|---|---|
| Route premium gate | `role_guarded_route.dart:104-113` | Yes | `role:'admin'` write (Critical #1); or `subscriptionStatus:'active'` write (Critical #2) |
| Dashboard entitlement banner | `hunter_dashboard.dart:594-600`, `outfitter_dashboard.dart:207-214` | Yes | Same writable `users/{uid}` source |
| `isPremiumActive` | `entitlement_service.dart:119-128` | Yes | `status:'active'` with null expiry |
| `isTrialActive` | `entitlement_service.dart:152-158` | Yes | Trial status with no timestamp; or `createdAt`-window fallback |
| `canAccessPremium` | `entitlement_service.dart:172-173` | Yes | Union of the two above |
| Server verify | `entitlement.ts:227-289` | No | Correct — but not the gate the UI trusts |
| RTDN revoke | `entitlement.ts:221-272` | n/a | Correct for revocations only |

**Bottom line:** the *server-side* pieces (Developer API verification, `entitlements` write:false, frozen premium fields, RTDN revoke) are sound. The system fails because the **client-facing `users/{uid}` document is the gate's source of truth and remains partly writable** — so the entire paywall can be defeated with two `update()` calls, and the Paywall's own purchase path never acknowledges.
