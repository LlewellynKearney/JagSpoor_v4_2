# TASK 2B — Referral: Play-compliant fixes (cap, engagement gate, Install Referrer, copy)

**Branch:** `fix/referral-audit` (base `main`). **NOT merged, NOT deployed.**
**Scope:** referral flow only. **Payment / billing code untouched.** **iOS OUT OF SCOPE.**

---

## Summary

The Task 2A audit found the referral plumbing worked but violated Google Play
policy in three ways: an uncapped reward loop, a dead `referralCodeUsed`
guard, and misleading share copy that promised a reward to the friend. This
task fixes all three, replaces the broken deferred-deep-link path with the
Google Play **Install Referrer Library 2.2**, and adds a manual code-entry
fallback.

No payment / billing / entitlement / price / trial-length file was touched.

---

## P0-1 — Cap infinite reuse (FIXED)

- **Per-code cap = 10** successful (granted) conversions per referral code.
  `MAX_CONVERSIONS_PER_CODE = 10` (`functions/src/referral.ts`). The pipeline
  counts the ALREADY-GRANTED conversions for the code (`grantedCountForCode`)
  **before** granting and rejects the 11th with `reject_reason: cap_reached`.
- **Dead `referralCodeUsed` guard fixed.** It is now:
  - **WRITTEN** on grant — the referred user's `users/{uid}` doc is stamped
    `referralCodeUsed: <CODE>` in the same transaction window as the reward.
  - **CHECKED** before granting — `hasConsumedReferralCode(userData)` rejects
    with `reject_reason: code_already_used` when the account already consumed
    a code, so an account can never reward twice.
- **Duplicate guard** — a conversion already finalised as granted, or a
  second granted conversion for the same `referredUserId`, rejects with
  `reject_reason: already_rewarded`.

## P0-2 — Misleading copy (FIXED)

All strings that promised the FRIEND a reward were removed. The programme
grants a reward ONLY to the referrer, and only after genuine engagement.

| Where | Before | After |
| --- | --- | --- |
| `lib/services/referral_link_service.dart` `sharePrefix` | `Join JagSpoor and get 1 month free!` | `Join JagSpoor — you earn 30 days of premium when a friend joins and becomes active!` |
| `lib/features/referral/services/referral_share_composer.dart` `buildShareMessage` | `Refer a friend and we both unlock rewards.` | `I earn 30 days of premium when you join and become active.` |
| `lib/features/referral/widgets/referral_share_widget.dart` | `Share your code — friends get a reward, and so do you.` | `Share your code — you earn 30 days of premium when a friend joins and becomes active.` |
| `public/r/index.html` (meta + body) | `...to unlock rewards.` | `...to get started.` |

Verified: `grep -rn "both get\|you both earn\|friends get a reward\|get 1 month free\|both unlock\|so do you" lib/ public/` → **0 matches**.

## P0-3 — Reward gated on GENUINE ENGAGEMENT (FIXED)

The reward is **NOT** granted on install or signup. A conversion created by
signup starts `pending` and is granted ONLY when the referred user satisfies
**all three** engagement signals:

1. **Email verified** (`auth().getUser(uid).emailVerified === true`).
2. **Profile complete** (`hasCompletedProfile` — first + last name, or a
   legacy multi-token `fullName`, plus a contact detail).
3. **One qualifying in-app action** — `QUALIFYING_ENGAGEMENT_ACTION =
   "first_trophy_created"` (the referred user created their first trophy;
   `trophies.where('ownerId' == uid).limit(1)`).

The single pure decision function `decideReferralGrant(...)` returns
`grant` / `pending` / `reject`; the shared `attemptReferralGrant(conversionId)`
applies it. Two new triggers re-run the pipeline when a signal arrives after
signup:

- `onReferredUserTrophyCreated` (`trophies/{trophyId}` created) — the
  qualifying action.
- `onReferredUserProfileUpdated` (`users/{userId}` updated) — profile
  completion.

`onReferralConversionCreated` runs the pipeline at signup; with no engagement
yet it records `pending` + the missing reasons and waits.

**Deliberately NOT gated on a purchase** (a "must pay" gate would be an
incentivized-purchase / Play Billing violation), and **no reward for a
rating/review or an install**.

---

## P1 — Play Install Referrer (FIXED)

Per <https://developer.android.com/google/play/installreferrer/library>:

- **Library 2.2** declared in `android/app/build.gradle.kts`:
  `implementation("com.android.installreferrer:installreferrer:2.2")` — the
  ONLY Play dependency added. **No Play Billing dependency was added**
  (billing is untouched).
- **Native bridge** in `MainActivity.kt` (`com.jagspoor/install_referrer`
  channel): `InstallReferrerClient.newBuilder(this).build()` →
  `startConnection()` → `onInstallReferrerSetupFinished()` →
  `getInstallReferrer()` (returns `installReferrer` + all four timestamps +
  `installVersion`) → **`endConnection()` is always called** once the value is
  read or on any failure.
- **Share link for non-installed users** now goes to Play with the referrer:
  `ReferralLinkService.buildPlayStoreReferrerUrl(code)` →
  `https://play.google.com/store/apps/details?id=za.co.jagspoor.app&referrer=referral_<CODE>`
  (URL-encoded). The website landing page (`public/r/index.html`) sets this
  URL on the "Download on Google Play" button and preserves it in the Android
  `intent://` fallback.
- **Dart service** `lib/services/install_referrer_service.dart` reads the
  referrer on the FIRST Android launch (guarded by a `SharedPreferences`
  flag; the referrer is available for 90 days), parses `referral_<CODE>`
  (`ReferralLinkService.parseInstallReferrer`), validates it against
  `referralCodes/{code}` and caches it via `ReferralLinkHandler` for signup.
  Android-only + never throws.
- **Manual code entry fallback** (sideload / already-installed / referrer
  unavailable / iOS): the signup form's referral field is validated against
  `referralCodes/{code}` "before acceptance" via
  `ReferralRepository.checkReferralCode(code)`, with inline valid/invalid
  feedback. Hint: "Have a referral code? Enter it here".

## P1 — iOS: SKIPPED (OUT OF SCOPE)

The iOS deferred link is **NOT implemented**. No AASA / Apple Team ID /
`AppleProvider` / iOS file was touched — `public/.well-known/
apple-app-site-association` still carries the `REPLACE_WITH_TEAM_ID`
placeholder. An iOS user uses **manual code entry only**. Documented in the
`referral_link_service.dart` doc comment.

## P2 — Admin V2 read-only metric (ADDED)

A read-only **"Referred Users"** count card (`adminV2CardReferredUsers`) on
the Admin Portal V2 dashboard: the total number of `referral_conversions`
documents. **Aggregate only — no PII** (no referrer/referred uid, email or
name is surfaced). Added via `AdminUserMetricsService.fetchReferredUsersCount()`
(a read on the referral collection). It does **not** touch any billing file —
**not skipped**.

---

## Tests

**Backend (`functions`, node:test) — 190/190 pass** (`npm test`), incl. new:
- Cap: `exceedsReferralCap(10) === true`; `decideReferralGrant` with
  `grantedCountForCode: 10` → `reject` / `cap_reached`. The 11th does not grant.
- Guard: `hasConsumedReferralCode`; a duplicate → `already_rewarded`; a
  consumed code → `code_already_used`.
- Gate: signup alone → `pending` (missing `email_not_verified` +
  `no_qualifying_action`); full engagement → `grant`.
- Action: `QUALIFYING_ENGAGEMENT_ACTION === "first_trophy_created"` and is NOT
  install/signup/review.
- Exports + compiled-source contracts (live guard + cap + engagement gate).

**Flutter — new/changed suites pass** (full suite: all pass except the
documented pre-existing `trial_onboarding_functions_contract_test`):
- `test/install_referrer_url_test.dart` (NEW) — Play URL with `referrer=`,
  parse `referral_<CODE>`, invalid/blank rejected, round-trip, malformed
  escape safe.
- `test/install_referrer_service_test.dart` (NEW) — Android-only no-op,
  parse+validate+cache, invalid code rejected, read-once, channel
  PlatformException degrades, real mocked channel call.
- `test/referral_code_check_test.dart` (NEW) — manual code validation:
  valid / case-insensitive / unknown / inactive / blank / legacy-profile.
- Copy assertions updated in `referral_link_service_test`,
  `referral_share_composer_test`, `referral_share_sheet_test`.

**Copy contract:** no `both get` / `you both earn` / `friends get a reward` /
`1 month free` strings remain.

**`tsc`** — clean. **`flutter analyze`** on every changed file — 0 errors,
0 warnings.

---

## Manual test steps

**Cap + guard (backend)**
1. Seed 10 granted `referral_conversions` for one code. Create an 11th with a
   fully-engaged referred user → conversion becomes `rejected`
   (`cap_reached`); referrer's entitlement is unchanged.
2. Create a conversion for a referred user whose `users/{uid}` already has
   `referralCodeUsed` → `rejected` (`code_already_used`).
3. Create a duplicate conversion for an already-granted `referredUserId` →
   `rejected` (`already_rewarded`).

**Engagement gate**
4. Sign up with a referral code → conversion is `pending` (no reward yet).
   `users/{uid}` is NOT stamped `referralCodeUsed`.
5. Verify the email + complete the profile → still `pending` (no action yet).
6. Create the first trophy → the conversion flips to `granted`, the referrer's
   `premiumExpiry` extends by the reward days, and `users/{uid}` is stamped
   `referralCodeUsed: <CODE>`.

**Install Referrer (Android device)**
7. From another device tap a share link → landing page → "Download on Google
   Play" (URL carries `&referrer=referral_<CODE>`).
8. Install + open the app → the signup referral field is pre-filled with the
   code (read on first launch via the Install Referrer API).

**Manual fallback**
9. Sideload / already-installed: open signup, type an invalid code → inline
   "We could not find that referral code."; type a valid one → green "code
   applied".

**iOS**
10. iOS is NOT supported for deferred linking — the code must be typed
    manually on signup.

---

TASK 2B DONE
