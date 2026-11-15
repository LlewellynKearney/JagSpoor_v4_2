# Identify users who missed their verification email

**Task:** list (do NOT send to) the accounts that never received their email
verification mail, so an admin can resend from the Admin Portal V2.

**Branch:** `fix/email-verification-not-sending`

---

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

### What was broken (3 concrete gaps)

| # | Gap | Consequence |
|---|-----|-------------|
| 1 | `sendVerificationEmail()` swallowed every failure (`debugPrint` only) | No way to know which account failed |
| 2 | Nothing ever wrote a send-status flag to `users/{uid}` | Admin portal (reads Firestore) had no signal at all |
| 3 | `emailVerified` was never mirrored to `users/{uid}` | Admin portal could not tell verified from unverified |
| 4 | No server-side resend existed | App can only resend for the *signed-in* user; an admin cannot resend for someone else (needs the Admin SDK `generateEmailVerificationLink`) |

## 2. Fix

* **Client** (`EmailVerificationService`): every send now writes an audit trail
  on `users/{uid}` — `verificationEmailSent`, `verificationEmailLastError`,
  `verificationEmailLastAttemptAt` — and `checkVerified()` mirrors
  `emailVerified`.
* **Server** (`functions/src/email_verification.ts`): two admin-only callables,
  `resendVerificationEmail` (one account) and `resendVerificationEmailsBulk`
  (capped batch, `BULK_LIMIT = 50`). They mint a fresh link via the Admin SDK
  `generateEmailVerificationLink()` and deliver it from the support mailbox
  (`sendSupportEmail`), then update the same audit flags.
* **Admin Portal V2 → Users tab**: new **Email Verification** card with a
  per-row **RESEND** button and a **RESEND TO ALL UNVERIFIED (N)** bulk action
  behind a confirmation dialog. Admin-only (disabled for non-admins; the server
  re-checks privileges).

## 3. Identify the missed users (list only — sends nothing)

The script performs **read-only** Firestore + Auth reads and writes a local CSV.
It **never sends email** — resending is done from the Admin Portal V2 UI.

```bash
cd functions
npm run build
node lib/identify_missed_verification_users.js --out /tmp/missed.csv
```

It selects accounts where:

```
emailVerified == false
AND verificationEmailSent is not true   # missing OR explicitly false
```

`emailVerified` is taken from the **Firebase Auth user** (authoritative) and
falls back to the `users/{uid}.emailVerified` mirror when no Auth record exists.

### Output CSV columns

```
Email, Created Date, Name, Role, emailVerified, verificationEmailSent
```

### Equivalent Firestore query (Console)

The predicate is `emailVerified != true AND verificationEmailSent != true`. In
the Firebase Console → Firestore → `users`, filter:

* `emailVerified` `==` `false`  → then remove rows where
  `verificationEmailSent == true`; **or** use the Admin SDK, which can express
  the two-field filter directly.

> The `!=` operators require a single-field index (auto-created); no composite
> index is needed for this two-equality filter in the Admin SDK.

## 4. Resend to the missed users

1. Open **Admin Portal V2 → Users**.
2. In the **Email Verification** card, review the list (email + status).
3. Click **RESEND** on a row, or **RESEND TO ALL UNVERIFIED (N)**.
4. The bulk action confirms first ("Resend to X users?") and processes at most
   **50 per run** (quota protection). Re-run to drain a larger list.

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

## 5. Missed-user count

Run the script in a credentialed environment to get the live number; the
result is printed to stdout (`Missed verification emails: N account(s).`) and
written to the `--out` CSV. It cannot be computed from this sandbox (no Firebase
credentials — `firebase projects:list` is unauthenticated here).
