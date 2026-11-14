# TASK 2A — Referral Flow Audit (AUDIT ONLY)

**Branch:** `fix/referral-audit` (base `main` @ `7c916fe`)
**Date:** 2026-11-14
**Scope:** Audit only. **No code changed.** No merge. No deploy. Payment/billing
code (plans.ts, payfast.service, PlayBillingService, validateGooglePlayPurchase,
prices, trial lengths, entitlements) was read for coupling only — **not modified**.

---

## 0. TL;DR

The referral system is a **half-built feature with a live reward path**.

* **Generation, sharing, capture, signup redemption all WORK** end-to-end.
* **The reward IS granted** — a Cloud Function extends the *referrer's*
  entitlement by 30 days (free premium) the moment the referred user *signs up*.
  **No payment is required** of the referred user.
* The *referred* user gets **nothing**, yet the share copy promises
  "Join JagSpoor and get 1 month free!" → **misleading copy**.
* The reward fires on **signup**, not on subscription, and is **not** tied to
  Play or PayFast — it is platform-agnostic and fires on both (and on neither,
  i.e. a never-paying free-tier account still rewards the referrer).
* Two **compliance risks**: (1) copy promises a reward to the *friend* that the
  system never delivers; (2) an **unbounded referral-farming loop** — each new
  account can reward a referrer 30 free days with no payment and no cap.
* **PayFast is clean**: no PayFast/Play/plans/entitlement file reads any referral
  field. Verified by grep. The referral grant *writes* an entitlement via the
  shared `writeEntitlement` (the same writer Play validation uses) but **does not
  change price, plan, trial length, or ITN validation**.
* **POPIA is clean**: no referrer ever sees the referred user's email, name, or
  payment data. `referral_conversions` reads are party-scoped in rules, and **no
  UI exists** that lists conversions.

**Verdict: the flow functions, but Task 2B is required before it is
shippable/compliant.** See §8.

---

## 1. Flow diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ GENERATION (per signed-in user, lazily on first share-widget open)          │
│  hunter_profile_screen.dart:1139  /  outfitter_dashboard.dart:836            │
│    └─ ReferralShareWidget(theme:)                                           │
│         └─ ReferralRepository.getOrCreateMyReferralProfile()                │
│              ├─ getMyReferralProfile()  → referral_profiles/{uid}           │
│              └─ createMyReferralProfile()                                   │
│                   ├─ generateReferralCode()  → 8 chars, [A-Z2-9] (no 0/O/1/I)│
│                   ├─ WRITE referral_profiles/{uid} {userId, referralCode}   │
│                   └─ WRITE referralCodes/{CODE} {code, ownerUid, uses, active}│
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ SHARING                                                                     │
│  ReferralShareComposer.buildReferralLink(code)                              │
│    → https://jag-spoor.co.za/r/<CODE>      (HTTPS App Link / Universal Link) │
│  ReferralShareComposer.buildCustomSchemeLink(code)                          │
│    → jagspoor://referral?code=<CODE>       (custom-scheme fallback)          │
│  Share text: "Join JagSpoor and get 1 month free! <link>"                    │
│  Buttons: COPY LINK / WHATSAPP (wa.me) / native share sheet                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                     ┌──────────────┴───────────────┐
                     ▼                              ▼
        App INSTALLED (App Link)        App NOT installed (browser)
        Android: autoVerify intent      → https://jag-spoor.co.za/r/<CODE>
        iOS: associated domain          → public/r/index.html landing page
        → app opens → app_links           • shows CODE
          getInitialLink()/stream         • "Download on Google Play" button
                                          • intent:// → jagspoor:// fallback
                                          • ⚠️ NO code passed to the store URL
                                            (deferred deep link LOST)
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ CAPTURE                                                                     │
│  main.dart:149  ReferralLinkHandler.instance.initialize()                   │
│    ├─ _restorePendingCode()  ← SharedPreferences 'pending_referral_code'     │
│    ├─ getInitialLink()  (cold start)                                        │
│    └─ uriLinkStream     (warm links)                                        │
│         └─ extractReferralCode(uri)  → ReferralLinkService                  │
│         └─ _defaultValidateCode(code) → ReferralRepository.getReferralCode() │
│              → referralCodes/{CODE}  (direct doc read, O(1))                │
│         └─ registerCode()  → in-memory _pendingCode + SharedPreferences     │
│              (persists across app close / cold restart)                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ SIGNUP                                                                      │
│  auth_screen.dart:74  _prefillReferralFromIncomingLink()                    │
│    → reads ReferralLinkHandler.pendingCode (or SharedPreferences)           │
│    → sets _isLoginMode = false, pre-fills _referralCodeController            │
│  Registration submit (auth_screen.dart:397):                                │
│    → ReferralRepository.redeemReferralCode(referredUserId: newUid, code:)   │
│         ├─ findReferrerByCode(code)  → referralCodes index → owner uid      │
│         ├─ self-referral check (referrer.userId == newUid → skip)           │
│         ├─ recordConversion() → WRITE referral_conversions/{auto}           │
│         │     {referrerId, referredUserId, referralCode, tier,              │
│         │      status:'pending', rewardAmountZAR, createdAt}                │
│         └─ markReferralCodeUsed() → referralCodes/{CODE}.uses += 1          │
│    → on recorded: ReferralLinkHandler.clearPendingCode()                    │
│  ⚠️ NO referral field is written on users/{newUid}. The link lives only     │
│     in referral_conversions (and the pending SharedPreferences cache).      │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ REWARD  (SERVER — functions/src/referral.ts:440 onReferralConversionCreated) │
│  Trigger: referral_conversions/{id} onCreate                                │
│    ├─ validate referrer != referred, both non-empty                         │
│    ├─ idempotency: skip if already granted/rewarded; reject 2nd grant for    │
│    │   same referredUserId (status:'rejected', reason:'already_rewarded')   │
│    ├─ loadReferralRewardConfig() → admin_config/referral_rewards            │
│    ├─ days = hunterDays|outfitterDays (default 30)                          │
│    ├─ extendReferrerEntitlement(referrerId, days)                           │
│    │     → writeEntitlement(referrer, {isPremium:true, premiumExpiry:+days, │
│    │        subscriptionSource: existing||'google_play', status:'active'})  │
│    └─ mark conversion status:'granted', rewarded:true, rewardDays,          │
│         rewardAmountZAR, grantedPremiumExpiry, grantedAt                    │
│                                                                             │
│  🔴 FIRES ON SIGNUP — no payment, no Play, no PayFast, no subscription.     │
│  🔴 Only the REFERRER is rewarded. The REFERRED user gets nothing.          │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Step-by-step trace table

| # | Step | file:line | Status |
|---|------|-----------|--------|
| 1a | Code generation (alphabet, length 8) | `lib/features/referral/services/referral_repository.dart:106-113`; alphabet `lib/features/referral/models/referral_profile.dart:10-11` | **WORKS** |
| 1b | `referral_profiles/{uid}` write | `referral_repository.dart:215-227` | **WORKS** |
| 1c | `referralCodes/{code}` reverse-index write | `referral_repository.dart:233-249` | **WORKS** |
| 1d | Format = 8 chars, `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, upper-cased; max len 12 | `referral_profile.dart:4,10-11`; `referral_code.dart:98-99` | **WORKS** |
| 2a | Canonical share link `https://jag-spoor.co.za/r/<CODE>` | `lib/services/referral_link_service.dart:69-73` | **WORKS** |
| 2b | Custom scheme `jagspoor://referral?code=<CODE>` | `referral_link_service.dart:83-88` | **WORKS** |
| 2c | Android App Link config (`autoVerify`, host, `/r`, `/.well-known`) | `android/app/src/main/AndroidManifest.xml:96-113` | **WORKS** |
| 2d | Android `assetlinks.json` | `public/.well-known/assetlinks.json` | **WORKS** (real fingerprints present) |
| 2e | iOS Universal Link entitlement | `ios/Runner/Runner.entitlements` | **WORKS** |
| 2f | iOS AASA | `public/.well-known/apple-app-site-association` | **BROKEN** — `appID` still `REPLACE_WITH_TEAM_ID.za.co.jagspoor.app` |
| 2g | Hosting rewrite `/r/**` → landing page | `firebase.json` (rewrites) | **WORKS** |
| 2h | Web landing page (`/r/<CODE>`) | `public/r/index.html` | **PARTIAL** — see §6 (Play survival) |
| 3a | Handler init at startup | `lib/main.dart:149`; `lib/services/incoming_referral_handler.dart:89` | **WORKS** |
| 3b | In-memory cache `_pendingCode` | `incoming_referral_handler.dart:69,74` | **WORKS** |
| 3c | SharedPreferences key `pending_referral_code` | `incoming_referral_handler.dart:67,145-146,199-203` | **WORKS** — survives app close |
| 3d | Code validation vs `referralCodes/{code}` | `incoming_referral_handler.dart:209-212` | **WORKS** |
| 4a | Signup prefill (in-memory → prefs fallback) | `lib/features/auth/auth_screen.dart:74-91` | **WORKS** |
| 4b | Redemption on email/password registration | `auth_screen.dart:397-410` | **WORKS** |
| 4c | Field stored on `users/{newUid}` | — | **NONE** — no referral field on the user doc; link recorded only in `referral_conversions` |
| 5a | Reward trigger | `functions/src/referral.ts:440-555` | **WORKS** (grants) |
| 5b | Reward type | `referral.ts:359-417` — 30-day entitlement extension (free premium) | **WORKS** |
| 5c | Reward trigger point | conversion `onCreate` = **signup** | **RISK** — not payment-gated |
| 5d | Reward for Play users | — | **N/A** — trigger is platform-agnostic, fires regardless |
| 5e | Reward for PayFast users | — | **N/A** — same |
| 5f | Reward for never-paying users | fires anyway | **RISK** |
| 5g | Reward for the REFERRED user | — | **MISSING** — referrer-only |
| 6a | Admin sees referred users (V1) | `lib/features/admin/screens/admin_dashboard_screen.dart:296-297` | **N/A** — only the *reward amounts* card |
| 6b | Admin sees referred users (V2) | `admin_portal_v2_screen.dart` | **MISSING** — zero referral refs |
| 6c | PII shown to admin | `lib/features/admin/widgets/referral_rewards_admin_card.dart` | **NONE** — amounts only (Hunter R / Outfitter R), no per-user data |

---

## 3. Compliance table

| Domain | Finding | Verdict |
|--------|---------|---------|
| **Play — cash/credit promise** | No cash, no Play credit. Reward is a 30-day in-app entitlement extension (`referral.ts:359-417`). | **PASS** |
| **Play — payment requirement** | Referral copy/flow does **not** require the referred user to pay. But the reward fires on **signup** regardless of payment — so the programme is "invite → free premium for referrer" with no purchase gate. | **RISK** — see below |
| **Play — misleading copy** | Share text `"Join JagSpoor and get 1 month free!"` (`referral_link_service.dart:57`) and the share widget copy `"friends get a reward, and so do you"` (`referral_share_widget.dart:93`) promise a reward to the *friend*. The backend grants **nothing** to the referred user. | **RISK (REJECTION RISK if reported)** — misleading promotional claim |
| **Play — incentivised installs / abuse** | An install → signup with a code rewards the referrer 30 free days with **no payment**, no cap on how many codes one account can redeem, no device/IP/abuse gate (the old device-fingerprint trial-abuse check was **removed** — `functions/src/user_trial_onboarding.ts` has none). One operator can farm unlimited free premium via throwaway accounts. | **RISK** — referral abuse / incentivised-install policy exposure |
| **PayFast — price/plan change** | `functions/src/payfast/{plans.ts,payfast.service.ts,payfast.ts}` contain **zero** referral references (grep). | **PASS** |
| **PayFast — ITN validation change** | `validateItn` / signature / amount checks untouched by referral. | **PASS** |
| **Play — plan/product/price change** | `PlayBillingService`, `subscription_pricing`, `plans.ts` read **no** referral field (grep). | **PASS** |
| **Play — `validateGooglePlayPurchase`** | Does not read referral. (The referral *grant* reuses `writeEntitlement` — the same writer — but adds no product/price/plan logic.) | **PASS** |
| **Entitlement coupling** | `functions/src/referral.ts:5,394` calls `writeEntitlement(...)` on the referrer's `users/{uid}`. This is a *new writer* of premium fields, not a change to the entitlement contract. It sets `isPremium:true`, `premiumExpiry`, `subscriptionStatus:'active'`, and defaults `subscriptionSource` to `'google_play'` when the account had none (`referral.ts:399`). | **PASS with note** — behaviour change is *entitlement grants*, not billing |
| **POPIA — referrer sees referred user PII** | `referral_conversions` read is party-scoped in rules (`firestore.rules:921-926`); **no UI lists conversions** (`getConversionsForCurrentUser` has zero call sites). | **PASS** |
| **POPIA — referred user email/name/payment exposure** | The conversion doc stores only uids + code + tier + status. No email/name/payment is ever copied. | **PASS** |
| **POPIA — anonymised count only** | The only per-user referral surface is the share widget (own code). No counterparty data is surfaced. | **PASS** |
| **Anti-abuse — self-referral** | Client rejects (`referral_repository.dart:435-439`), rules reject (`firestore.rules:930`), backend rejects (`referral.ts:462-468`). | **PASS** |
| **Anti-abuse — valid-code check** | Code is validated against `referralCodes/{code}` **or** a `referral_profiles.referralCode` query (`referral_repository.dart:160-194`). An arbitrary string is **not** accepted. | **PASS** |
| **Anti-abuse — infinite reuse** | `markReferralCodeUsed` bumps `uses` but **nothing caps it**. A code can be redeemed by unlimited distinct accounts. The `referralCodeUsed` field frozen in rules (`firestore.rules:245-247`) is **never written** by any code — dead guard. | **FAIL / RISK** |
| **Anti-abuse — repeat reward for same referred user** | Backend rejects a 2nd grant for the same `referredUserId` (`referral.ts:481-500`). | **PASS** |

---

## 4. Play vs PayFast survival matrix

| Scenario | Play (Android install from store) | PayFast (web checkout) |
|----------|-----------------------------------|------------------------|
| Tap `https://jag-spoor.co.za/r/<CODE>` with app **installed** | ✅ App Link opens app; `getInitialLink()` caches code | ✅ Same handler (web build also runs `app_links_web`) |
| Tap link with app **not installed** | ⚠️ Browser shows `/r/index.html`; code shown + intent:// → Play. **Code is NOT carried through the Play install** (no Install Referrer / Play deferred deep link) → **code LOST** | ✅ Same web page; user copies code manually → survives |
| Signup **immediately** after link | ✅ `_pendingCode` in memory → prefilled | ✅ Prefilled |
| Signup **2 days later** (app closed between) | ✅ SharedPreferences `pending_referral_code` survives cold start | ✅ Survives |
| Signup after **browser → Play install** | 🔴 **Code LOST** (deferred deep link absent) | N/A (no install step) |
| Referral code during **PayFast WebView checkout** | N/A | ✅ Code already redeemed at signup; the PayFast flow does not touch referral, so nothing is lost or changed |
| Reward after Play purchase | ✅ Already granted at signup (independent of Play) | ✅ Already granted at signup (independent of PayFast) |
| Reward after PayFast checkout return | ✅ Unaffected — PayFast WebView return does not read/clear referral state | ✅ Unaffected |

**Key point:** the referral code is consumed at **signup**, long before any
Play or PayFast billing step. Neither billing flow reads or mutates referral
state, so neither can lose or alter the referral. The only loss path is
**browser → Play install** (no deferred deep link).

---

## 5. Detailed findings

### 5.1 Reward fires on signup, not on conversion (RISK)
`functions/src/referral.ts:440` triggers on `referral_conversions/{id}`
`onCreate`. The client writes that doc during registration
(`auth_screen.dart:397-410`), i.e. **before any payment**. The status doc
comment says the reward is "due (subject to the admin reward config + any
payout policy)" (`referral_conversion.dart:12-13`), but the backend grants
immediately. There is no subscription-activation trigger anywhere
(`functions/src/index.ts` has no referral/subscription trigger). **Result:** the
referrer is granted 30 free premium days as soon as a new account types their
code — no purchase needed.

### 5.2 The referred user is never rewarded (copy mismatch)
`extendReferrerEntitlement` (`referral.ts:359`) only touches `referrerId`.
Nothing writes to `referredUserId`. Yet the share prefix is
`'Join JagSpoor and get 1 month free!'` (`referral_link_service.dart:57`) and the
widget says "friends get a reward, and so do you"
(`referral_share_widget.dart:93`). This is a **misleading claim**.

### 5.3 Unbounded reuse (FAIL)
* `referralCodes/{code}.uses` is incremented but never checked against a cap.
* `referralCodeUsed` is frozen in `firestore.rules:245-247` and **never written
  by any code** (grep across `lib/`, `functions/`, `test/` finds only test
  fixtures) — a dead guard that gives a false sense of a per-user single-use
  limit.
* No per-account cap, no device/IP signal, and the trial-abuse device check was
  removed from the trial trigger.

### 5.4 Deferred deep link missing for Play installs (BROKEN)
`public/r/index.html` links to
`https://play.google.com/store/apps/details?id=za.co.jagspoor.app` with **no
`referrer=` parameter**, and no Play Install Referrer / deferred-deep-link SDK is
integrated (grep for `install_referrer` / `deferred` finds nothing). A user who
taps a referral link and installs from Play lands in the app with **no code**.

### 5.5 iOS AASA placeholder (BROKEN)
`public/.well-known/apple-app-site-association` still has
`"appID": "REPLACE_WITH_TEAM_ID.za.co.jagspoor.app"`. iOS Universal Links will
**not** verify until the real Team ID is filled in. Android assetlinks is
complete (real SHA-256 fingerprints present).

### 5.6 No referral visibility anywhere
* No admin "referred users" list in V1 or V2 (`admin_portal_v2_screen.dart` has
  zero referral refs; the V1 card only edits reward *amounts*).
* No referrer-facing "my referrals" screen — `getConversionsForCurrentUser`
  (`referral_repository.dart:467`) has **zero call sites**.
* So neither the referrer nor an admin can see who was referred. The only
  observable artefact is the referrer's silently-extended premium expiry.

### 5.7 `subscriptionSource` default is `'google_play'`
`referral.ts:399` sets `subscriptionSource: existingSource ||
SUBSCRIPTION_SOURCE_GOOGLE_PLAY` when an account had no source. This labels a
referral-granted extension as a Google Play subscription source on a web/PayFast
or free-tier account. It does not change price or ITN logic, but it is a
**data-labelling inaccuracy** worth flagging for Task 2B (do not "fix" inside
billing files).

---

## 6. Recommendation for Task 2B

Prioritised, minimal-surface fixes. **All fixes are client/referral-module or
new-code only.** None require touching billing.

| Pri | Fix | Where (proposed) |
|-----|-----|------------------|
| P0 | Gate the reward on a **qualifying action** (e.g. first paid subscription / first confirmed booking) instead of signup, OR explicitly document + accept a signup-time reward and remove any "conversion" implication. | New trigger or re-target of `onReferralConversionCreated`; **do not** edit entitlement.ts billing logic |
| P0 | Fix the **misleading copy** — either reward the referred user too, or change the copy to describe a referrer-only reward. | `referral_link_service.dart:57`, `referral_share_widget.dart:93`, `referral_share_composer.dart:58-63`, `public/r/index.html` |
| P0 | Add a **reuse cap** (max N redemptions per code / per account / per device) and enforce it; wire or delete the dead `referralCodeUsed` guard. | `referral_repository.dart` (redeem), `functions/src/referral.ts` (idempotency), rules |
| P1 | Add a **Play deferred deep link**: append `referrer=<code>` to the Play URL in `public/r/index.html` and integrate the Install Referrer SDK; or make the web landing page require the user to copy the code before install. | `public/r/index.html`, new plugin |
| P1 | Fill the **iOS Team ID** in the AASA. | `public/.well-known/apple-app-site-association` |
| P2 | Add **referrer-facing "My Referrals"** (anonymised counts only — POPIA) and/or an **admin referred-users view** in V2. | new widget + `getConversionsForCurrentUser` call site; V2 metrics |
| P2 | Correct the `subscriptionSource: 'google_play'` default for a referral grant. | `functions/src/referral.ts:399` (referral file only) |

### DO NOT TOUCH list (Task 2B)
* `functions/src/payfast/plans.ts`
* `functions/src/payfast/payfast.service.ts`
* `functions/src/payfast/payfast.ts`
* `lib/features/subscription/services/play_billing_service.dart`
* `functions/src/entitlement.ts` **billing/validation logic** — `validateGooglePlayPurchase`, `onGooglePlayRTDN`, `payfastITN`, `platformFromSource`, prices, trial lengths. (`writeEntitlement` may be **called** by referral code, but its contract must not change.)
* `functions/src/user_trial_onboarding.ts` (trial length / provisioning)
* `admin_config/pricing` / `admin_config/app_version` / any price or trial constant
* `firestore.rules` billing-related guards (subscriptionStatus / isPremium / premiumExpiry / hasActivePurchase change-detection)
* Anything that changes subscription price, plan, entitlement amounts, or trial duration.

---

## 7. Verification (this audit)

* `git status` — only `docs/fix-referral-audit/AUDIT.md` added.
* No source file modified. No merge. No deploy. Live untouched.
* Grep evidence: `referral` has **zero** matches in
  `functions/src/payfast/**`, `functions/src/entitlement.ts`,
  `functions/src/plans.ts`, `lib/features/billing/**`,
  `lib/features/subscription/**`, `lib/services/entitlement_service.dart`.

---

## 8. Conclusion

The referral **plumbing works** (generate → share → capture → redeem → grant).
The **policy and copy do not survive scrutiny**: a reward is granted on signup
with no payment and no cap, the referred user is promised a reward they never
receive, the dead `referralCodeUsed` guard suggests a limit that does not exist,
and Play-install deep linking is broken. Billing is **clean and untouched** and
must remain so in Task 2B.

AUDIT DONE — READY FOR FIX
