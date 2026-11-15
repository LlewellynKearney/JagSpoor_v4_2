# Identify users who missed their verification email

**Task:** list (do NOT send to) the accounts that need their verification email,
split into the two buckets that require different actions.

**Branch:** `fix/email-verification-not-sending`

---

## 0. Why a single "unverified" count over-counts (the bug this fixes)

A raw `emailVerified == false AND verificationEmailSent != true` query counts
**every** account that never clicked the link — including people who are happily
**using** the app. In JagSpoor **role selection does NOT require a verified
email**, so an account with a role demonstrably got in: it received the email
(or bypassed the gate) and simply never clicked. Bulk re-sending to those would
**spam active users**.

The audit therefore splits the unverified set by role:

| Bucket | Predicate | Meaning | Action |
|--------|-----------|---------|--------|
| **1 — Unverified With Role** | `emailVerified != true` AND role is hunter/outfitter/admin | Received email, never clicked (active user) | **Reminder only** — do NOT bulk resend |
| **2 — Unverified No Role** | `emailVerified != true` AND role blank/`none`/`unassigned`/missing | Never completed signup, likely never got the email | **Resend targets** |

`bucket1 + bucket2 == the old single count` — no account is lost, they are just
routed to the right action.

## 1. Root cause (one sentence)

Verification emails stopped because the **send is entirely client-side**
(`User.sendEmailVerification()` in `lib/features/auth/services/email_verification_service.dart`)
and its failure was **swallowed by a bare `debugPrint`** — so any account whose
send failed (or that was created while the client could not reach Firebase Auth)
was silently left unverified with **no record anywhere** of the failure and no
admin path to re-send.

There is **no Cloud Function and no SMTP/SendGrid step** in the verification
path — the earlier Alternative Billing (PayFast / User Choice Billing) work did
not touch it (verified: `git log -S sendEmailVerification` shows only the
hosting commit; the billing commits touched `billing_service.dart`,
`alternative_billing*.ts`, `payfast/*` and version files only). The
verification mail is delivered by **Firebase Auth's own email service**, not by
the `EMAIL_PASS` SMTP path (that SMTP path only powers the *support-inbox*
notifications).

### What was broken (4 concrete gaps)

| # | Gap | Consequence |
|---|-----|-------------|
| 1 | `sendVerificationEmail()` swallowed every failure (`debugPrint` only) | No way to know which account failed |
| 2 | Nothing ever wrote a send-status flag to `users/{uid}` | Admin portal (reads Firestore) had no signal at all |
| 3 | `emailVerified` was never mirrored to `users/{uid}` | Admin portal could not tell verified from unverified |
| 4 | No server-side resend existed | App can only resend for the *signed-in* user; an admin cannot resend for someone else (needs the Admin SDK `generateEmailVerificationLink`) |

## 2. Fix

* **Credential (the "insufficient permission" bug)** —
  `functions/src/firebase.ts` initialized the Admin SDK with an **explicit
  credential**:

  ```ts
  admin.initializeApp({ credential: admin.credential.applicationDefault() });
  ```

  That form **honours a stray `GOOGLE_APPLICATION_CREDENTIALS`** (a limited
  service-account key left on the deploy machine / CI runner). The limited key —
  not the function's runtime service account — then becomes the identity, and
  every Auth Admin call fails with:

  > *Credential implementation provided to `initializeApp()` via the
  > "credential" property has insufficient permission to access the requested
  > resource.*

  The fix is to call `admin.initializeApp()` **with no arguments**, so the SDK
  uses Application Default Credentials, which inside the Cloud Functions runtime
  resolve to the function's own **runtime service account** (the identity Cloud
  Run runs the container as). That account already holds
  `roles/firebaseauth.admin` per the IAM audit. Every other
  `initializeApp()` call in `src/` was already argument-free; `firebase.ts` was
  the only offender.
* **Client** (`EmailVerificationService`): every send now writes an audit trail
  on `users/{uid}` — `verificationEmailSent`, `verificationEmailLastError`,
  `verificationEmailLastAttemptAt` — and `checkVerified()` mirrors
  `emailVerified`.
* **Server** (`functions/src/email_verification.ts`): two admin-only callables,
  `resendVerificationEmail` (one account) and `resendVerificationEmailsBulk`
  (capped batch, `BULK_LIMIT = 50`). They mint a fresh link via the Admin SDK
  `generateEmailVerificationLink()` and deliver it from the support mailbox
  (`sendSupportEmail`), then update the same audit flags.
* **Actionable errors** (`describeCredential()` + `buildResendDiagnostic()`):
  when an Auth Admin call is rejected for insufficient permission the callable
  throws a `failed-precondition` whose message names **the service account the
  function ran as**, its **credential source**, and the **missing role**
  (`roles/firebaseauth.admin`) — instead of the UI showing a bare "0 of N".
  The diagnostic contains only non-secret identifiers (the service-account
  email + project id), never key material.
* **Admin Portal V2 → Users tab**: new **Email Verification** card with TWO
  counts and TWO actions:
  * **Resend to No Role (N)** — the ONLY bulk resend target (capped at 50/run,
    behind a "Resend to X no-role users?" confirm dialog).
  * **Remind Unverified With Role (M)** — opens a pre-filled support-mail draft
    (mailto, BCC) so the admin sends a gentle reminder, NOT a fresh
    verification link.
  Per-row **RESEND** stays available on both lists. Admin-only (disabled for
  non-admins; the server re-checks privileges). The old single
  "Resend to All Unverified (72)" button is **gone**.

## 3. Identify the missed users (list only — sends nothing)

The script performs **read-only** Firestore + Auth reads and writes two local
CSVs. It **never sends email** — resending is done from the Admin Portal V2 UI.

```bash
cd functions
npm run build
node lib/identify_missed_verification_users.js --out-dir /tmp
```

It selects accounts where:

```
emailVerified != true
AND verificationEmailSent is not true   # missing OR explicitly false
```

then splits them by role into the two buckets.

`emailVerified` is taken from the **Firebase Auth user** (authoritative) and
falls back to the `users/{uid}.emailVerified` mirror when no Auth record exists.

### Output (2 CSVs + 2 printed counts)

```
Bucket 1 — UNVERIFIED WITH ROLE:  M   → unverified-with-role.csv
Bucket 2 — UNVERIFIED NO ROLE:    N   → missed-no-role.csv
```

Both CSVs share the columns:

```
Email, Created Date, Name, Role, emailVerified, verificationEmailSent
```

### Equivalent Firestore query (Console)

The predicate is `emailVerified != true AND verificationEmailSent != true`. In
the Firebase Console → Firestore → `users`, filter `emailVerified == false` and
`verificationEmailSent != true`, then split on `role` (`== ''` / `== 'none'` /
`== 'unassigned'` for bucket 2; anything else for bucket 1).

## 4. Resend to the missed users

1. Open **Admin Portal V2 → Users**.
2. In the **Email Verification** card:
   * **No Role (N)** → **Resend to No Role (N)** (confirm dialog, max 50/run;
     re-run to drain a larger list). Per-row **RESEND** for a single account.
   * **Unverified With Role (M)** → **Remind Unverified With Role (M)** opens a
     pre-filled reminder email. These are active users — do NOT bulk resend.

### Deploy reminder

```bash
cd functions && npm ci && npm run build
npx firebase-tools deploy --only functions:resendVerificationEmail,resendVerificationEmailsBulk
```

The functions declare `secrets: [emailPass]`, so the deploying identity needs
`roles/secretmanager.secretAccessor` and the `EMAIL_PASS` secret must exist
(the same requirement as the other mail-sending triggers). If `EMAIL_PASS` is
unset the link is still minted (the account is recoverable) and the function
reports `delivered: false` with the reason recorded on `users/{uid}`.

## 5. Missed-user counts

Run the script in a credentialed environment to get the live numbers; both
counts are printed to stdout and written to the two CSVs. They cannot be
computed from this sandbox (no Firebase credentials — `firebase projects:list`
is unauthenticated here).

## 6. "Credential … has insufficient permission" troubleshooting

If the resend still returns that error, the function is running as an identity
that lacks **`roles/firebaseauth.admin`** ("Firebase Authentication Admin").
Both resend functions are now **pinned to the Admin SDK service account** in
code, so this should no longer happen — but the checks below remain useful if a
manual Cloud Run change or a stray key re-appears.

### 6.0 The pin (why the two functions can no longer drift)

`functions/src/email_verification.ts` exports ONE shared options factory and
BOTH callables use it:

```ts
export const RESEND_SERVICE_ACCOUNT =
  "firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com";

export function resendCallableOptions() {
  return {
    region: "us-central1",
    maxInstances: 10,
    secrets: [emailPass],
    serviceAccount: RESEND_SERVICE_ACCOUNT,   // <- pins BOTH functions
  };
}
```

`resendVerificationEmail` and `resendVerificationEmailsBulk` are both declared
with `onCall(resendCallableOptions(), …)`. The Firebase CLI writes
`serviceAccountEmail` onto each deployed Cloud Run revision from this option, so
**every deploy overwrites any manual change** and the two functions are always
identical. Previously the bulk function had been re-pointed by hand while the
singular one was left on the project's default compute account — that drift is
now structurally impossible, and a test asserts the two compiled endpoints carry
the same `serviceAccountEmail`.

### 6.1 Which service account does the function actually use?

The resend functions are **2nd gen**, so each is backed by a **Cloud Run
service**. Cloud Console → **Cloud Run → `resendverificationemail` (and
`resendverificationemailsbulk`) → Security → Service account**. That field is the
account that needs the role. With the pin in place it reads
`firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com`.

Equivalent CLI:

```bash
gcloud run services describe resendverificationemail \
  --region us-central1 --format='value(spec.template.spec.serviceAccountName)'
```

### 6.1a The error names the identity itself

The credential diagnostic resolves the runtime service account from the
**metadata server** (`/compute/v1/instance/service-accounts/default/email`) and
the `FUNCTION_IDENTITY` / `K_SERVICE` env vars, so the failure message names the
exact service account rather than telling you to go look it up:

> Auth Admin call rejected: the credential has insufficient permission.
> Identity: firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com
> (source: computeMetadata). Grant roles/firebaseauth.admin to this service
> account.

When the identity genuinely cannot be resolved (e.g. a local emulator) the
message falls back to the placeholder — production always resolves it.

### 6.2 Grant the role to THAT account

```bash
gcloud projects add-iam-policy-binding jagspoor \
  --member="serviceAccount:<THE_CLOUD_RUN_SA_FROM_6.1>" \
  --role="roles/firebaseauth.admin"
```

### 6.3 Make sure no stray key is being picked up

The root-cause fix removed the explicit credential, but confirm the deploy
environment does not still export a key that ADC would pick up:

* **Locally / CI**: `echo "${GOOGLE_APPLICATION_CREDENTIALS:-<unset>}"` before
  deploying. If it points at a limited key, unset it — the deployed function
  uses its runtime service account, not the deployer's credentials, but the
  same variable leaking into a Cloud Run revision's env would hijack ADC.
* **Cloud Run env vars**: Cloud Console → the service → Variables — there must
  be **no** `GOOGLE_APPLICATION_CREDENTIALS`.

### 6.4 Verify

Re-run **Resend to No Role** from Admin Portal V2. The snackbar now shows the
exact identity + missing role on failure, e.g.:

> Auth Admin call rejected: the credential has insufficient permission.
> Identity: 1234567890-compute@developer.gserviceaccount.com (source:
> computeMetadata). Grant roles/firebaseauth.admin to this service account.

---

## 7. Follow-up fix — `400 INVALID_ID_TOKEN` on the send (2026-11-15)

### 7.1 The failure

Live log from the Admin Portal after the previous fix:

```
resendVerificationEmail: not delivered
email: info@jag-spoor.co.za, linkGenerated: false
reason: "send failed: 400: INVALID_ID_TOKEN"
```

### 7.2 Root cause

The send called the **admin** Identity Toolkit endpoint
(`projects/{projectId}/accounts:sendOobCode`) with the runtime **service
account's OAuth token**. For `requestType: "VERIFY_EMAIL"` that endpoint
authorizes on the **target user's `idToken`** — a service account is not a
user, so Firebase rejects the call with `400 INVALID_ID_TOKEN`. The
service-account token was simply the wrong credential for this endpoint.

### 7.3 Fix — mint a user idToken, then send with it

`functions/src/email_verification.ts` now performs the standard
"act as the user from a trusted server" flow:

1. `admin.auth().createCustomToken(uid)` — a signed custom token.
2. `POST accounts:signInWithCustomToken?key=<API_KEY>`
   `{token, returnSecureToken: true}` → that account's `idToken`.
3. `POST accounts:sendOobCode?key=<API_KEY>`
   `{requestType: "VERIFY_EMAIL", idToken}` — the real send.

`?key=` is the **public Firebase Web API key** (not a secret — it already
ships in every client build; see `lib/firebase_options.dart`). It only
identifies the project; the send still requires a valid user idToken.
`resolveApiKey()` reads `FIREBASE_API_KEY` from the environment first, then
falls back to the compiled-in project web key.

**Fallback (no API key configured):** `admin.auth()
.generateEmailVerificationLink()` mints the SAME link the email would carry
and returns it to the caller so the admin can deliver it. A real verification
link — never SMTP. SMTP stays removed; do not reintroduce it.

**IAM:** the pinned service account needs `roles/firebaseauth.admin` (to mint
the custom token / look the user up). It no longer needs
`firebaseauth.users.sendEmail`, because the mail is sent with the user's
idToken.

### 7.4 Diagnostics

The `accounts:sendOobCode` HTTP **status code** is logged on failure (never a
token) and surfaced in the portal:

* per-row: `sendOobCode 400: send failed: 400: INVALID_ID_TOKEN`
* bulk: `Resent to 0 of 12. (sendOobCode 400)`

`isInvalidIdTokenError()` names the service-account-token bug explicitly so a
recurrence is obvious.

### 7.5 Verify

Set `FIREBASE_API_KEY` (optional — the default already works) and deploy:

```bash
cd functions && npm run build && npm test
firebase deploy --only functions:resendVerificationEmail,resendVerificationEmailsBulk
```

Then re-run **Resend to No Role** (or a single RESEND) in Admin Portal V2.
The account should receive the Firebase verification email, and the audit
trail on `users/{uid}` should show `verificationEmailSent: true`.
