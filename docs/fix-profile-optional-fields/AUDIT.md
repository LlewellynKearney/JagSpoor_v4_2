# AUDIT — Hunter + Outfitter Profile Mandatory Fields

**Task:** 1A — Audit only (no code changes, no merge, no deploy).
**Branch:** `fix/profile-optional-fields` (base `main` @ `8080a74`).
**Date:** 2026-11-13.
**Scope:** find exactly which profile fields are mandatory, where the block
lives, and what depends on them. **No fixes in this task.**

---

## 0. Executive summary

- The "3 mandatory fields" are **First Name**, **Surname**, and **a contact
  detail (Phone OR Email)** — i.e. **4 physical fields** with the last two
  being a mutually-satisfying pair.
- The block is a **Hunter-only onboarding gate**. There is **NO Outfitter
  profile screen** and outfitters are **explicitly exempt** from this gate
  (`auth_screen.dart:230`, `splash_screen.dart:212`).
- The block exists in **two places that must agree**:
  1. **Form validators** on the Hunter Profile screen (blocks Save), and
  2. A **completeness gate** (`HunterProfileCompleteness`) that runs on
     signup / login / cold-launch / dashboard entry and **redirects** the
     hunter back to the profile screen (blocks Continue / blocks app use).
- **Firestore rules do NOT require any of these fields.** The `users/{userId}`
  write rule only freezes server-owned fields (entitlement, trial, role,
  device fingerprint, sensitive POPIA fields). A profile save with empty
  name / surname / phone / email is **permitted** by the rules.
- The message the user sees: *"Name, Surname, and a contact detail (phone or
  email) are mandatory. You cannot use the app until these are completed."*
  (`hunter_profile_screen.dart:746-748`) and the redirect snackbar *"Please
  complete your profile before continuing. Missing: …"*.

---

## 1. Mandatory fields table

| # | Field (UI label) | Firestore key(s) | Screen(s) | How marked mandatory | Block behaviour | Error text |
|---|---|---|---|---|---|---|
| 1 | **First Name** | `firstName` (write) · read aliases `first_name`, `name`, legacy `fullName` | **Hunter only** (`hunter_profile_screen.dart`) | `*` in label (`:761`) + `validator` (`:763-765`) + gate `hasFirstName` (`hunter_profile_completeness.dart:77-79,96`) | Blocks **Save** (`_saveProfile` → `validate()` `:467`); gate **redirects** to profile screen on signup/login/cold-launch/dashboard | `'First name is required'` (`:764`); gate snackbar `'Missing: Name.'` |
| 2 | **Surname** | `lastName` (write) · read aliases `last_name`, `surname`, legacy `fullName` with a space | **Hunter only** | `*` in label (`:772`) + `validator` (`:774-776`) + gate `hasLastName` (`hunter_profile_completeness.dart:85-88,97`) | Blocks **Save**; gate **redirects** | `'Surname is required'` (`:775`); gate snackbar `'Missing: Surname.'` |
| 3a | **Phone Number** | `phone` (write) · read aliases `phoneNumber`, `cellNumber`, `cell` | **Hunter only** | `*` in label (`:784`) + `validator` (`:787-794`) + gate `hasPhone` (`hunter_profile_completeness.dart:89-92`) | Blocks **Save** **only if Email is also empty** (paired validator); gate `hasAnyContactDetail` | `'Enter a phone number or an email'` (`:791`) |
| 3b | **Email Address** | `email` (write) | **Hunter only** | `*` in label (`:806`) + `validator` (`:809-821`) + gate `hasEmail` (`hunter_profile_completeness.dart:93`) | Blocks **Save** **only if Phone is also empty**; also format-validates | `'Enter an email or a phone number'` (`:813`) / `'Enter a valid email address'` (`:818`) |

**Net effect:** fields 1 + 2 are hard-required; field 3 is "phone OR email".
The user is **hard-blocked from the entire app** until 1 + 2 + (3a or 3b) are
saved to Firestore.

---

## 2. Are there MORE than 3 mandatory fields?

Yes — **4 physical fields** (First Name, Surname, Phone, Email), collapsed to
3 *requirements* because Phone and Email satisfy one shared requirement
(`hasAnyContactDetail`).

### All fields on the Hunter Profile form (for completeness)
The Hunter Profile screen has **many** form fields. Only the 4 above are
mandatory; every other field is optional (no validator):

| Field | Firestore key | Mandatory? |
|---|---|---|
| First Name | `firstName` | **YES** |
| Surname | `lastName` | **YES** |
| Phone Number | `phone` | **YES (or Email)** |
| Alternative Field/Radio Contact | `altContact` | No |
| Email Address | `email` | **YES (or Phone)** |
| Home Address | `address` | No |
| Hunting Farm/Camp Name | `farmName` | No |
| Latitude / Longitude | `latitude` / `longitude` | No |
| Blood Type | `bloodType` (private doc) | No |
| Allergies | `allergies` (private doc) | No |
| Medical Aid | `medicalAid` (private doc) | No |
| Emergency Contact | `emergencyContact` (private doc) | No |
| SA ID Number | `idNumber` (private doc) | No |
| Dedicated Hunter Status Number | `hunterStatus` (private doc) | No |
| Active Provincial Permit Numbers | `provincialPermits` (private doc) | No |
| Basic First Aid Certified | `hasFirstAid` (private doc) | No |
| Dark Mode / Unit preference / Battery saver | prefs | No |

**Note:** the `idNumber` field is **NOT mandatory** despite being commonly
assumed — it has no `validator` (`hunter_profile_screen.dart:925-930`) and is
not part of the completeness gate.

---

## 3. Where the block lives (exact locations)

### 3a. Form validators (blocks Save) — `lib/features/hunter_mode/hunter_profile_screen.dart`
```
743   _buildSectionHeader('CONTACT INFORMATION *'),
745-748  Text('Name, Surname, and a contact detail (phone or email) are mandatory. You cannot use the app until these are completed.')
761   'First Name *'          validator → 'First name is required'      (:763-765)
772   'Surname *'             validator → 'Surname is required'         (:774-776)
784   'Phone Number *'        validator → 'Enter a phone number or an email'   (:787-794)
806   'Email Address *'       validator → 'Enter an email or a phone number'   (:809-821)
        (email also format-validated: 'Enter a valid email address' :818)

466-467  Future<void> _saveProfile() { if (!_formKey.currentState!.validate()) return; … }
1032     Save button onPressed: _isLoading ? null : _saveProfile
```
The `Form` is keyed `_formKey` (`:40`, `:623-624`). A failed `validate()`
returns early, so **nothing is written** and the field errors render inline.

### 3b. Completeness gate (blocks Continue / app use) — `lib/features/hunter_mode/services/hunter_profile_completeness.dart`
```
class HunterProfileStatus:
  hasFirstName  (:63)   ← firstName / first_name / name / fullName
  hasLastName   (:64)   ← lastName / last_name / surname / fullName with space
  hasPhone      (:65)   ← phone / phoneNumber / cellNumber / cell
  hasEmail      (:66)   ← email
  hasAnyContactDetail (:103) = hasPhone || hasEmail
  isComplete    (:107)  = hasFirstName && hasLastName && hasAnyContactDetail
  missingSummary(:112)  = 'Missing: Name, Surname, Contact details.'
```
`statusFor(uid)` (`:40-53`) reads `users/{uid}` and **fails closed**: a missing
doc / fetch error / offline returns `const HunterProfileStatus()` (all false →
incomplete → redirect). This is intentional ("never silently admits an
incomplete hunter").

### 3c. Gate call sites (the redirect) — 4 places
| File | Line | Trigger | Behaviour |
|---|---|---|---|
| `lib/features/auth/auth_screen.dart` | 231-258 | Post sign-in/registration routing (hunter + dual) | `pushAndRemoveUntil(HunterProfileScreen)` + orange snackbar `'Please complete your profile before continuing. Missing: …'` |
| `lib/core/splash_screen.dart` | 213-225 | Cold launch (hunter + dual) | `pushAndRemoveUntil(HunterProfileScreen)` |
| `lib/features/auth/role_selection_screen.dart` | 147-160 | After a brand-new hunter picks the role | `pushAndRemoveUntil(HunterProfileScreen)` |
| `lib/features/hunter_mode/hunter_dashboard.dart` | 79, 123-144 | Dashboard `initState` (defense-in-depth) | `pushAndRemoveUntil(HunterProfileScreen)` |

The screen itself also self-detects gate entry (`_resolveOnboardingGate`
`:90-107`) so a back action returns to the dashboard instead of stranding the
user.

**Question asked — "does role selection / onboarding also block on these 3
fields?" — YES**, for `role == 'hunter'` only
(`role_selection_screen.dart:147`). Outfitter selection is **not** gated.

---

## 4. Firestore rules findings

**The rules do NOT require `firstName` / `lastName` / `phone` / `email` on
`users/{uid}` writes.** Verified: `grep -c "firstName\|lastName\|'phone'\|'email'"
firestore.rules` → **0**.

The `match /users/{userId}` block (`firestore.rules:130-300`):
```
130  match /users/{userId} {
131    allow read: if isSignedIn();
164    allow write: if isSignedIn() && request.auth.uid == userId
         && noSensitiveFieldAdded()                       // POPIA guard, lines 56-70
         && (deviceFingerprint unchanged)                 // trial-abuse, 166-168
         && (isPremium / premiumExpiry / subscriptionSource / subscriptionPlatform /
             subscriptionProduct / subscriptionPlayPurchaseToken / payfastPaymentId /
             entitlementUpdatedAt / trialEndsAt / trialEnd / subscriptionTrialEndsAt /
             trialStartedAt / trialStart / subscriptionTrialStart / subscriptionStatus /
             isPro / hasActivePurchase / createdAt / referralCodeUsed unchanged)
         && (role guard, 275-290)
         && (isDualRole / roles frozen, 291-299)
         && (subscriptionTier / nested subscription unchanged, 300-309);
300    allow delete: if isSignedIn() && request.auth.uid == userId;
```
- **No field-presence requirement** for name/phone/email. A profile write that
  omits or empties them passes the rules.
- `noSensitiveFieldAdded()` (lines 56-70) is a **change-detection** guard for
  the POPIA-sensitive fields (`bloodType`, `allergies`, `medicalAid`,
  `medicalAidNumber`, `medicalConditions`, `emergencyContact`, `hasFirstAid`,
  `idNumber`, `idPassportNumber`, `hunterStatus`, `provincialPermits`). These
  are meant to live in `users/{uid}/private/profile` (owner-only,
  `firestore.rules:311-320`). **This guard is orthogonal** to the 3 mandatory
  fields — it does not force them, and it does not block their absence.
- Structural check: braces balance 0, parens balance 0, 53 `match` blocks,
  default-deny intact.

**Conclusion:** the mandatory-field block is **100% client-side**. Removing the
validators + relaxing the gate requires **no Firestore rules change**.

---

## 5. Downstream readers that assume non-null

These read the 3 fields but all **already handle empty/null gracefully**
(empty-string defaults + fallbacks). No crash risk found, but they are listed
per the brief. **Do NOT change them in this task.**

| Reader | File:line | Reads | Empty behaviour |
|---|---|---|---|
| Hunter contact resolver | `hunter_contact_resolver.dart:59-75` | `firstName`, `name`, `lastName`, `surname`, `fullName`, `displayName`, `phone`/`phoneNumber`/`cellNumber`/`cell`, `email` | All default `''`; `HunterContact` exposes `has*` getters; composes name from parts, falls back to booking snapshot |
| Hunter contact card | `widgets/hunter_contact_card.dart:196-213` | `contact.fullName` | Falls back to `hunterId` → `'Unknown hunter'` |
| Outfitter booking dashboard | `screens/outfitter_booking_dashboard_screen.dart:521-537` | `users/{hunterId}.fullName` / `name` | Falls back to `hunterId` → `'Unknown hunter'` (`:549-551`) |
| Venison permit prefill | `services/venison_permit_manager.dart:416-419` | `fullName` / `name`, `phoneNumber`/`cellNumber`, `address` | `?? ''` — field simply stays blank on the permit form |
| Firearm renewal (SAPS 518a) prefill | `screens/firearm_renewal_screen.dart:113-119` | `fullName`/`name`, `surname`, `idNumber`, `phone`/`cell`, `address` | `?? ''` — prefilled as empty, user types it |
| SAPS tracker | `services/saps_tracker_service.dart:99,247` | `idNumber` (from `license_applications`, not `users`) | `?? ''` |
| Hunter contact resolver contract | `hunter_contact_resolver.dart:139-145` | `hasMandatoryProfile` mirrors the gate | Used only for the outfitter card's "contact unavailable" fallback |

**Key note:** no reader indexes or dereferences these fields in a way that
throws on null. They are all null-tolerant `?? ''` reads. So making the
profile fields optional will **not break any downstream reader** — worst case
a contact card shows "Unknown hunter" (which is already its designed
fallback).

---

## 6. Hunter vs Outfitter — same fields or different?

**Different — the gate is Hunter-only.**

- **Hunter:** the 3 mandatory fields block Save + redirect from
  signup/login/cold-launch/dashboard (`hunter_profile_screen.dart` + the 4
  gate call sites).
- **Outfitter:** **NOT gated**. There is **no outfitter profile screen** in
  the codebase (verified: `find` for `*outfitter*profile*` → nothing;
  `grep` for `EditProfile`/`My Profile`/`outfitter profile` → nothing). The
  outfitter "settings" is a bottom sheet (`outfitter_dashboard.dart:721`)
  containing Dark Mode / Change Password / Subscription / Privacy / Referral /
  Delete Account — **no name/phone/email form**.
- The comments at `auth_screen.dart:230` and `splash_screen.dart:212` state
  plainly: *"Admins and outfitters are not gated by this check."*
- The `outfitters/{uid}` doc (`businessName`, `displayName`, `contactName`)
  is written by the **admin** `adminCreateOutfitter` Cloud Function
  (`functions/src/index.ts:298-311`) or self-healed with `outfitterId` only
  (`auth_screen.dart:297-332`). It is **not** part of any onboarding gate.

**Implication for Task 1B:** the user-reported "stuck on Hunter **+** Outfitter
profile screens" is really a **Hunter-only** block. An outfitter cannot be
stuck on a profile screen that does not exist — an outfitter is stuck only in
the sense that the shared `users/{uid}` doc (used by `HunterContactResolver`
etc.) may lack a name/contact, but nothing gates them.

---

## 7. Admin Portal V2 — does it read these fields?

**No — V2 does NOT read `firstName` / `lastName` / `phone` / `fullName`.**
Verified: `grep -c "firstName\|lastName\|phone\|fullName"
lib/features/admin/models/admin_user_metrics.dart` → **0**.

- `AdminUserRecord.fromMap` (`admin_user_metrics.dart:284-352`) reads only
  `email`, `role`, `roles`, `isDualRole`, subscription/trial fields, and
  timestamps. Every field is defaulted (`?? ''`, `_toDate(...)`).
- `admin_users_page.dart` renders `r.email` (never a name).
- `admin_portal_v2_screen.dart:892-894` (Top Outfitters table) uses
  `r.name` — but that comes from the **`outfitters` collection**
  (`businessName`/`displayName`/`name`, `admin_operational_metrics_service.dart:203-207`),
  **not** from `users/{uid}`, and it already falls back to `email` →
  `outfitterId`.
- `admin_operational_metrics_service.dart` `_firstNonEmpty` (`:217-223`)
  tolerates all-empty → `''`.

**Conclusion:** V2 will **not crash** on empty profile fields. No V2 change
needed. (Confirmed per the brief's "V2 must not crash on empty" requirement —
it already does not.)

---

## 8. Tests that currently lock the mandatory behaviour (Task 1B must update)

| Test file | What it asserts |
|---|---|
| `test/hunter_profile_completeness_test.dart` | `isComplete` requires first + last + (phone or email); `missingSummary` strings; alias resolution |
| `test/hunter_contact_resolver_test.dart` | `hasMandatoryProfile` mirrors the gate |
| `test/popia_privacy_policy_test.dart` | (adjacent) POPIA field classification — unrelated to the 3 fields |

Task 1B must update `hunter_profile_completeness_test.dart` if the gate is
relaxed, and any widget test that taps Save expecting a blocked state.

---

## 9. Recommendation for Task 1B

**Goal:** make the 3 (4) fields optional so a user can save the profile and
reach the app without being blocked.

### 9.1 Validators to remove / relax — `hunter_profile_screen.dart`
| Line | Current | Change to |
|---|---|---|
| 761 | `'First Name *'` | `'First Name'` (drop `*`) |
| 763-765 | `validator → 'First name is required'` | **Remove** the validator (leave field free-text) |
| 772 | `'Surname *'` | `'Surname'` |
| 774-776 | `validator → 'Surname is required'` | **Remove** the validator |
| 784 | `'Phone Number *'` | `'Phone Number (optional)'` |
| 787-794 | paired `validator` (`'Enter a phone number or an email'`) | **Remove** (keep `keyboardType`) |
| 806 | `'Email Address *'` | `'Email Address (optional)'` |
| 809-821 | `validator` (paired + format) | **Keep the FORMAT check only** (a malformed email should still warn); **drop the paired requirement**. i.e. `if (email.isNotEmpty && !valid) return 'Enter a valid email address'; return null;` |
| 743 | `_buildSectionHeader('CONTACT INFORMATION *')` | `_buildSectionHeader('CONTACT INFORMATION')` (drop `*`) |
| 745-748 | *"Name, Surname, and a contact detail (phone or email) are mandatory. You cannot use the app until these are completed."* | Reword to something like *"These details are optional but help us reach you. You can add them at any time."* |
| 466-467 | `_saveProfile` `if (!validate()) return;` | **Keep** the `validate()` call (it still guards the email-format check + any other future validators). With the required validators gone it will pass on empty. |

### 9.2 Completeness gate — `hunter_profile_completeness.dart` + 4 call sites
Two options (recommend **A**):

- **Option A (recommended): neutralise the gate.** Make
  `HunterProfileStatus.isComplete` always `true` (or delete the redirect call
  sites). Simplest: change the 4 call sites
  (`auth_screen.dart:231-258`, `splash_screen.dart:213-225`,
  `role_selection_screen.dart:147-160`, `hunter_dashboard.dart:123-144`) to
  **not** redirect — or make `isComplete` return `true` unconditionally with a
  doc comment. Keeps the class for future use.
- **Option B: keep the gate but never block on it.** Leave `isComplete` as-is
  for analytics/diagnostics only, and remove the redirects.

**Recommendation:** Option A — remove the redirects and make `isComplete`
return `true`, so there is a single obvious place to re-enable the gate later.
Update `hunter_profile_completeness_test.dart` accordingly.

### 9.3 UI label to use instead of "mandatory"
- Section header: **`CONTACT INFORMATION`** (no `*`).
- Helper text: *"Optional — helps the outfitter and JagSpoor reach you."*
- Field labels: `First Name`, `Surname`, `Phone Number (optional)`,
  `Email Address (optional)`.
- Keep the **email format** validator (invalid → `'Enter a valid email address'`).

### 9.4 Null-checks needed downstream
**None required.** Every downstream reader already uses `?? ''` / `has*`
guards (see §5). No `!` (null-assertion) on these fields anywhere. Confirm in
Task 1B with `grep -rn "firstName!\|lastName!\|phone!\|email!" lib/` → expect 0.

### 9.5 Outfitter side
**No change needed** — there is no outfitter profile form and no outfitter
gate. Task 1B is effectively **Hunter-only** (plus the 4 gate call sites).

### 9.6 Firestore rules
**No change needed.** The rules never required these fields (§4).

### 9.7 Admin Portal V2
**No change needed.** V2 does not read these fields (§7).

---

## 10. Files to touch in Task 1B (summary)

| File | Change |
|---|---|
| `lib/features/hunter_mode/hunter_profile_screen.dart` | Remove 3 required validators, keep email-format; drop `*` from labels + header; reword helper text |
| `lib/features/hunter_mode/services/hunter_profile_completeness.dart` | `isComplete` → `true` (or leave + document) |
| `lib/features/auth/auth_screen.dart` (231-258) | Remove hunter onboarding redirect |
| `lib/core/splash_screen.dart` (213-225) | Remove hunter onboarding redirect |
| `lib/features/auth/role_selection_screen.dart` (147-160) | Remove hunter onboarding redirect |
| `lib/features/hunter_mode/hunter_dashboard.dart` (123-144) | Remove `_enforceProfileOnboarding` redirect |
| `test/hunter_profile_completeness_test.dart` | Update gate expectations |
| `test/hunter_contact_resolver_test.dart` | Update `hasMandatoryProfile` expectation if it mirrors the gate |

**No changes:** `firestore.rules`, admin V2, all downstream readers,
`hunter_contact_resolver.dart`, contact cards, booking flows.

---

AUDIT DONE — READY FOR FIX
