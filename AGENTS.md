# JagSpoor — Agent Memory

## Backend / Firebase infrastructure (added 2026-08-11)

- A `functions/` Cloud Functions source tree now exists (TypeScript, `firebase-functions` v2 API,
  Node 22 runtime). Build: `cd functions && npx tsc` → emits `functions/lib/`.
- Two exported functions in `functions/src/index.ts`:
  - `payfastITNHandler` — HTTPS `onRequest`, public invoker, region `us-central1`.
    Validates PayFast ITN md5 signature (constant-time compare), calls PayFast's
    `validate` endpoint server-to-server, then on `payment_status==COMPLETE` updates
    `bookings/{m_payment_id}` → `status:'Paid'`, `paymentTimestamp`, `payfastpfPaymentId`.
    Reads `PAYFAST_PASSPHRASE` env var for signature generation.
  - `adminCreateOutfitter` — `onCall`, region `us-central1`. Requires caller
    `auth.token.admin == true`. Creates a new Auth user (Admin SDK, does NOT log out
    caller), writes `/outfitters/{uid}` doc, sets `{ role:'outfitter' }` custom claims.
    Rolls back Auth user on doc/claims failure.
- PayFast crypto helpers live in `functions/src/payfast.ts` (signature build/compute/verify,
  `validateWithPayFast` using global `fetch`).
- `firebase.json` now has a `functions` block (`source: functions`, `runtime: nodejs22`).

## Firestore security rules (hardened 2026-08-11)

- `firestore.rules` rewritten with ownership scoping:
  - `firearms`, `trophies`, `ammunition`, `records`: owner-scoped via `isOwnerOf(field)`.
  - `bookings`: read = hunter OR outfitter party; create = hunter; status field update =
    outfitter only (`statusUpdateAllowed()`); other field updates = any party (status frozen).
    Nested `bookings/{id}/chats` restricted to booking parties.
  - `packages`: read for any signed-in; create/update/delete only if `outfitterId == auth.uid`.
  - `outfitters/{uid}`: read for signed-in; create = admin; update/delete = admin or owner.
  - `animals`: public read preserved; write = admin only.
  - Default deny remains.

## Firestore indexes

- `firestore.indexes.json` now includes `bookings` composites:
  `outfitterId ASC + bookingTimestamp DESC` and `hunterId ASC + bookingTimestamp DESC`.

## Environment constraints (this sandbox)

- `firebase-tools` v15.26.0 installed locally (`npx firebase-tools`); NOT global.
- **No Firebase credentials available** — `FIREBASE_TOKEN`/service account absent;
  `firebase projects:list` returns 401 "No OAuth tokens found". Deployment must be run
  in an environment with `firebase login` or `FIREBASE_TOKEN` set.
- **No Java/JVM** — Firestore emulator cannot run here, so `@firebase/rules-unit-testing`
  cannot execute; rules were validated structurally (JSON valid, default-deny present,
  `tsc` clean) but not via emulator integration tests.
- PayFast signature logic was unit-tested in isolation (round-trip + tamper detection pass).

## Deploy command (when credentials available)

```bash
cd /workspace/project/JagSpoor_v4_2
(cd functions && npm install && npm run build)
npx firebase-tools deploy --only functions,firestore:rules,firestore:indexes
# Set PayFast passphrase: npx firebase-tools functions:set PAYFAST_PASSPHRASE=...
```

## Flutter SDK & analyze (this sandbox)

- Flutter SDK installed at `/home/openhands/flutter` (version 3.29.1 stable, Dart 3.7.0 —
  matches the CI pin in `.github/workflows/build-and-deploy.yml` and satisfies `sdk: ^3.6.0`).
  Add to PATH: `export PATH="$HOME/flutter/bin:$PATH"`.
- `flutter pub get` succeeds (148 outdated but constraint-incompatible packages — expected).
- `flutter analyze` result: **303 issues, 0 errors** — 17 warnings + 286 infos. Breakdown:
  - Warnings: `unused_local_variable` (9), `invalid_null_aware_operator` (1 in
    `lib/features/ballistics/presentation/scope_tools_bottom_sheet.dart:355`), plus
    unused imports/elements/fields.
  - Infos dominated by `avoid_print` (220, mostly debug `print()` calls), plus
    `non_constant_identifier_names` (16), `curly_braces_in_flow_control_structures` (14),
    `unnecessary_const` (13), `use_build_context_synchronously` (5, in outfitter
    presentation screens), `deprecated_member_use` (3 — `withOpacity`, `androidProvider`,
    `appleProvider` in `lib/main.dart` + `role_selection_screen.dart`).
  - Production `lib/` ≈ 94 issues; `test/` ≈ 209 issues. No analyzer errors block the build.
