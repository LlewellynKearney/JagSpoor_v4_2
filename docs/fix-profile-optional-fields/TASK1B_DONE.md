# TASK 1B — DONE: Hunter profile fields made optional

**Branch:** `fix/profile-optional-fields` (base `main` @ `8080a74`, audit commit `4c0a283`).
**Date:** 2026-11-13.
**Scope:** make First Name / Surname / Phone / Email **optional** on the Hunter
Profile and remove the completeness gate that bounced hunters back to it.
Hunter-only; the Outfitter flow is untouched. Follows the AUDIT.md
Recommendation (§9) exactly.

**NOT done (by design):** no merge, no deploy, no `firestore.rules` change, no
payment/billing change, no Admin Portal V2 change, no outfitter profile screen.

---

## 1. What changed (file:line)

### 1.1 `lib/features/hunter_mode/hunter_profile_screen.dart`
| Line(s) | Before | After |
|---|---|---|
| 743 | `_buildSectionHeader('CONTACT INFORMATION *')` | `_buildSectionHeader('CONTACT INFORMATION')` (dropped `*`) |
| 745-747 | "Name, Surname, and a contact detail (phone or email) are mandatory. You cannot use the app until these are completed." | "Optional — helps the outfitter and JagSpoor reach you. You can add or change these at any time." |
| 759-762 | `'First Name *'` + `validator → 'First name is required'` | `'First Name'` + hint "Optional — enter your first name" + **no validator** |
| 767-770 | `'Surname *'` + `validator → 'Surname is required'` | `'Surname'` + hint "Optional — enter your surname" + **no validator** |
| 775-780 | `'Phone Number *'` + paired `validator → 'Enter a phone number or an email'` | `'Phone Number (optional)'` + hint "Optional — helps outfitters contact you" + **no validator** (kept `keyboardType: TextInputType.phone`) |
| 789-803 | `'Email Address *'` + paired + format validator | `'Email Address (optional)'` + **format-only** validator: `if (email.isNotEmpty && !regex.hasMatch(email)) return 'Enter a valid email address';` (empty allowed) |
| 475 | comment "Compose the full name from the **mandatory** first + last name fields." | comment reworded to "(optional)" |

- **Save unchanged in shape**: `_saveProfile` still calls
  `_formKey.currentState!.validate()` (line 467) — with the required validators
  gone it passes on empty and the write proceeds. The write still stamps all
  four Firestore keys (`'firstName': first`, `'lastName': last`,
  `'phone': …`, `'email': …`, lines ~487-493) — **no field deleted, no key
  renamed**. A filled value is still saved; an existing hunter keeps their
  values (no data loss).

### 1.2 `lib/features/hunter_mode/services/hunter_profile_completeness.dart`
- `HunterProfileStatus.isComplete` (line 113) → **always returns `true`** with
  a doc comment explaining the neutralisation + how to re-enable later.
  The class + method + the per-field flags (`hasFirstName` / `hasLastName` /
  `hasPhone` / `hasEmail` / `hasAnyContactDetail` / `missingSummary`) are
  **kept intact** so every call site keeps compiling and the gate can be
  re-enabled from one place. Class-level doc comment updated (lines 4-12).

### 1.3 The 4 gate call sites — redirects removed
| File | Line(s) | Change |
|---|---|---|
| `lib/features/auth/auth_screen.dart` | 225-232 | Hunter/dual onboarding redirect block removed (was `pushAndRemoveUntil(HunterProfileScreen)` + orange "complete your profile" snackbar). Replaced with an explanatory comment. Imports `hunter_profile_screen.dart` + `hunter_profile_completeness.dart` removed. |
| `lib/core/splash_screen.dart` | 207-214 | Cold-launch hunter/dual redirect removed. Same imports removed. |
| `lib/features/auth/role_selection_screen.dart` | 141-149 | Brand-new-hunter redirect removed. Removed `hunter_profile_screen.dart`, `hunter_profile_completeness.dart`, and the now-unused `app_theme.dart` import. |
| `lib/features/hunter_mode/hunter_dashboard.dart` | 108-118 | `_enforceProfileOnboarding` body removed → now an empty no-op (kept so the `initState` call at line 73 is unchanged). Removed the one-shot `_onboardingRedirected` field (was line 60) and the now-unused `package:firebase_auth` import. |

Net effect: **no code path pushes the Hunter Profile screen with
`pushAndRemoveUntil`**, so a hunter with an empty firstName/lastName/phone/email
can complete sign-up / sign-in / cold-launch / role selection and land on
`hunter_dashboard` with **no bounce**.

---

## 2. What was NOT changed (and why)

| Area | Status |
|---|---|
| `firestore.rules` | **Untouched.** The rules never required these fields (AUDIT §4). |
| Payment / billing (`lib/features/billing/`, `lib/features/subscription/`, `functions/src/payfast*`) | **Untouched.** |
| Admin Portal V2 (`lib/features/admin/**`, `admin_portal_v2_screen.dart`, `admin_user_metrics.dart`) | **Untouched.** V2 does not read firstName/lastName/phone/fullName (AUDIT §7). |
| Downstream readers (`hunter_contact_resolver.dart`, `hunter_contact_card.dart`, `outfitter_contact_card.dart`, `booking_calendar_service.dart`) | **Untouched.** Already null-tolerant (`?? ''` + `has*` guards). `grep -rn "firstName!\|lastName!\|phone!\|email!" lib/` → the only hit is `change_password_dialog.dart:70 user.email!` on the FirebaseAuth `User` object, unrelated to profile fields. |
| `idNumber` | **Untouched** — was never mandatory (AUDIT §2 note). |
| Outfitter flow | **Untouched** — there is no outfitter profile screen and outfitters were already exempt (AUDIT §6). |
| Other completeness checks in the gate | **None found.** The gate only ever covered these 4 fields (no non-profile checks exist), so nothing else was preserved. |
| Hunter Profile fields themselves | All still visible, editable, and saved if filled. |

---

## 3. Tests

### 3.1 Updated (the AUDIT §8 tests)
- `test/hunter_profile_completeness_test.dart` — rewritten to assert **optional**
  behaviour:
  - the per-field flags (`hasFirstName` / `hasLastName` / `hasPhone` /
    `hasEmail` / `hasAnyContactDetail`) still resolve correctly (aliases,
    legacy `fullName`, blank/whitespace), **and**
  - `isComplete` is `true` for a full profile, a names-only profile, a
    completely empty profile, and an all-blank/whitespace profile, **and**
  - `statusFor` admits a complete doc, an empty doc, a partial doc, a missing
    doc, and an empty uid (all `isComplete == true` — no bounce).
- `test/hunter_contact_resolver_test.dart` — **no change needed**: its
  `hasMandatoryProfile` assertion is derived from the *actual field presence*
  on the `HunterContact` model (`(hasFirstName || hasFullName) && … &&
  hasAnyContactDetail`), not from the neutralised gate, so it still holds. 28/28
  pass.

### 3.2 Added — `test/profile_optional_fields_test.dart` (NEW, 12 tests)
- **Form contract**: no required validators for first name / surname / phone;
  the email field keeps ONLY the format validator; labels drop `*` and mark
  phone/email "(optional)"; the section header drops `*`; the "mandatory /
  cannot use the app" copy is gone; Save still writes all four Firestore keys;
  Save still runs `validate()`.
- **Redirect removal** (the 4 call sites): each source file no longer contains
  `HunterProfileScreen(`, `HunterProfileCompleteness.instance`, or
  `statusFor(`; the dashboard's `_enforceProfileOnboarding` is an empty no-op
  and the `_onboardingRedirected` guard is gone.
- **No bounce (widget)**: `HunterDashboard` renders with an empty profile in
  the test env (no Firebase app) — the dashboard mounts and shows JAGSPOOR /
  HUNTER MODE / TACTICAL MODULES with no forced navigation to the profile
  screen.

> A full-screen `HunterProfileScreen` widget test is **not** feasible in this
> sandbox: its `initState` calls `FirebaseAuth.instance` (pre-existing, not
> introduced here) which throws `[core/no-app]` without a live Firebase app.
> The form contract is therefore verified structurally (the established repo
> pattern for source-locked contracts).

### 3.3 Verification (this sandbox)
- `flutter analyze lib test` → **0 errors, 0 warnings** (320 pre-existing
  info-level issues, unchanged baseline). The only issue inside a changed file
  is the documented pre-existing `deprecated_member_use` (`withOpacity`) at
  `role_selection_screen.dart:281` — on an **unmodified** line.
- `flutter test` (full suite, `LD_LIBRARY_PATH="$HOME/libs"`):
  **2551 passed, 1 failed** — the failure is the DOCUMENTED pre-existing
  `trial_onboarding_functions_contract_test` ("is a Firebase Auth
  user-creation trigger in us-central1"), proven pre-existing by stashing every
  change (`git stash -u`) and re-running it at clean HEAD (identical failure).
  No new failures; +12 vs the pre-change baseline (the new tests).
- `git diff --stat` → **no `firestore.rules`, no payment/billing file, no
  admin portal V2 file.** Only: the 6 lib files, the rewritten completeness
  test, and the new test. `pubspec.lock` drift from `pub get` reverted.
- Env: Flutter **3.44.9** (CI pin) at `/tmp/flutter_sdk_dl/flutter`; the
  `~/libs/libsqlite3.so -> /usr/lib/x86_64-linux-gnu/libsqlite3.so.0` symlink
  for the sqflite-FFI suites.

---

## 4. Manual test on Web

1. Run the app on Chrome: `flutter run -d chrome` (or build + serve
   `flutter build web --release`). The app uses hash routing (`/#/splash`).
2. **New hunter, empty profile:**
   - Register a fresh account (or sign in). Because the gate is removed you
     land on the Hunter dashboard immediately — you are **not** bounced to the
     profile screen.
   - Open the Hunter Profile (dashboard settings icon). Confirm the CONTACT
     INFORMATION section reads "Optional — helps the outfitter and JagSpoor
     reach you…" and the labels are `First Name`, `Surname`,
     `Phone Number (optional)`, `Email Address (optional)` — **no `*`**.
   - Leave all four empty and tap **SAVE PROFILE** → it succeeds (green "Profile
     saved successfully!" snackbar). No "First name is required" / "Surname is
     required" / "Enter a phone number or an email" errors.
3. **Email format still guarded:**
   - Type `not-an-email` into Email Address and Save → inline
     "Enter a valid email address". Clear it (or fix it) → Save succeeds.
4. **Existing hunter keeps values:**
   - On an account that already had a name/phone/email, open the profile →
     the fields are pre-filled with the stored values; Save → values persist
     (re-open to confirm).
5. **No redirect loop:** reload the browser tab on the dashboard with an empty
   profile → you stay on the dashboard (no bounce to the profile screen).

---

TASK 1B DONE
