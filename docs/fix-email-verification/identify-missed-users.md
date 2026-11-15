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

* **Client** (`EmailVerificationService`): every send now writes an audit trail
  on `users/{uid}` — `verificationEmailSent`, `verificationEmailLastError`,
  `verificationEmailLastAttemptAt` — and `checkVerified()` mirrors
  `emailVerified`.
* **Server** (`functions/src/email_verification.ts`): two admin-only callables,
  `resendVerificationEmail` (one account) and `resendVerificationEmailsBulk`
  (capped batch, `BULK_LIMIT = 50`). They mint a fresh link via the Admin SDK
  `generateEmailVerificationLink()` and deliver it from the support mailbox
  (`sendSupportEmail`), then update the same audit flags.
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
