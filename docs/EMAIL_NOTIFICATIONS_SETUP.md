# Email Notifications Setup

JagSpoor emails the support inbox **support@jag-spoor.co.za** automatically
when two business events happen:

1. **A new user signs up** (Firebase Auth user creation).
2. **A new subscription is recorded** (any of the three billing locations
   below).

Delivery is SMTP via [nodemailer](https://nodemailer.com/), driven by four
Cloud Functions in `functions/src/notifications.ts` plus the 30-day trial
trigger in `functions/src/user_trial_onboarding.ts` — all **2nd gen**, all
mounting the `EMAIL_PASS` secret.

---

## 1. What gets sent

### New user — `onUserCreate`

A **2nd gen** Auth `onUserCreated` trigger (`firebase-functions/v2/identity`).
Fires once per newly created Auth user — email/password and Google sign-in
alike. (This replaced the 1st-gen `functions.auth.user().onCreate` chain,
which showed 0 invocations in the console; the v2 identity provider is the
supported user-creation event.)

Email contents:

| Field | Value |
| --- | --- |
| To | `support@jag-spoor.co.za` (override with `SUPPORT_EMAIL`) |
| Subject | `[JagSpoor] New user: <email>` |
| Email | the new user's address |
| User ID | the Firebase Auth `uid` |
| Provider | `password`, `google.com`, … |
| Display name | the Auth display name, if set |
| Created at | ISO-8601 creation timestamp |

### New subscription — three triggers

The app and backend record subscriptions in more than one place, so all three
are watched. Whichever fires first sends the mail:

| Trigger | Watches | Notes |
| --- | --- | --- |
| `onSubscriptionCreate` | `users/{userId}/subscriptions/{subId}` onCreate | The per-user subscriptions subcollection. |
| `onUserSubscriptionUpdated` | `users/{userId}` onUpdate | Fires the first time the account becomes subscribed — `subscriptionTier` goes from empty → set, or `isSubscribed` / `isPremium` / `subscriptionStatus` flips to an active state. |
| `onPricingCreated` | `pricing/{docId}` onCreate | The top-level pricing collection, as a fallback. |

Email contents:

| Field | Value |
| --- | --- |
| To | `support@jag-spoor.co.za` |
| Subject | `[JagSpoor] New subscription: <email> (<plan>)` |
| User email | from `users/{uid}.email`, else the Auth record |
| User ID | the `uid` (when the document carries one) |
| Plan | `plan` / `tier` / `subscriptionTier` / `productId` |
| Price | `price` / `amount` / `amountZAR` / `priceZAR` / `monthlyPrice` |
| Source + doc path | which billing location fired |
| Full document data | the entire document, pretty-printed JSON |

`onUserSubscriptionUpdated` stamps a `supportSubscriptionNotified: true`
marker onto `users/{uid}` after the first successful send, so a follow-on
write (for example the Play purchase recorder confirming
`subscriptionStatus: 'active'` right after the tier was set) cannot send a
duplicate email.

All four handlers are **best-effort**: a mail or lookup failure is logged and
swallowed, so it can never fail the Auth / Firestore write that produced it.

---

## 2. Set the SMTP password secret

The SMTP password is read from a **Cloud Functions secret** — never from a
file and never from git. Store it with the Firebase CLI:

```bash
# from the repository root
firebase functions:secrets:set EMAIL_PASS
# paste the mailbox password when prompted
```

The secret is declared once in `functions/src/params.ts`:

```ts
import { defineSecret } from "firebase-functions/params";
export const emailPass = defineSecret("EMAIL_PASS");
```

and **every mail-sending trigger mounts it** so the runtime can resolve the
value at send time:

```ts
export const onUserCreate = onUserCreated(
  { region: "us-central1", secrets: [emailPass] },
  async (event) => { /* … */ }
);
```

`functions/src/email.ts` resolves the password with `emailPass.value()`
(falling back to a plaintext `EMAIL_PASS` env value, then to a skip) — see
`currentEmailConfigWithSecret()`.

`EMAIL_USER` defaults to `support@jag-spoor.co.za` and doubles as the sender
address, so mail is sent **from** and **to** the support mailbox out of the
box.

Until `EMAIL_PASS` is set the triggers log
`support email skipped: EMAIL_PASS secret is not configured` and return
without sending — nothing breaks.

> If `onUserCreate` still shows 0 invocations after deploying, confirm the
> secret is bound: `firebase functions:secrets:get EMAIL_PASS` should list the
> version, and the deploy output should mention `EMAIL_PASS` for each trigger.

---

## 3. Optional configuration

Every value below has a working default. Set only what you need to change:

| Variable | Default | Purpose |
| --- | --- | --- |
| `EMAIL_USER` | `support@jag-spoor.co.za` | SMTP username **and** the default `From` address. Must be the **full mailbox address** (Afrihost cPanel rejects a bare local-part username). |
| `EMAIL_PASS` | *(unset)* | SMTP password. **Required** to send. Set as a secret. |
| `EMAIL_HOST` | `mail.jag-spoor.co.za` | SMTP host. Set to `smtp.gmail.com` to switch providers later. |
| `EMAIL_PORT` | `465` | SMTP port (465 implicit TLS / 587 STARTTLS). The TLS mode is derived **from the port** on the live path. |
| `EMAIL_SECURE` | `true` | Only honoured by the pure `resolveEmailConfig` helper. The live path derives `secure` from the port so a stale value cannot desync TLS. |
| `SUPPORT_EMAIL` | `support@jag-spoor.co.za` | The recipient inbox. |
| `EMAIL_TO` | *(unset)* | Recipient alias — used only when `SUPPORT_EMAIL` is absent. |

### Switching to Gmail later

No code change is needed — set the three overrides and re-deploy:

```bash
firebase functions:config:unset  # (legacy; not needed on v2)
# Edit functions/.env (gitignored) or set via the console:
#   EMAIL_HOST=smtp.gmail.com
#   EMAIL_PORT=587
#   EMAIL_SECURE=false
#   EMAIL_USER=<gmail address>
firebase functions:secrets:set EMAIL_PASS   # the Gmail app password
firebase deploy --only functions
```

> Gmail requires an **app password** (with 2-Step Verification enabled), not
> the account password.

---

## 4. Deploy

```bash
# from the repository root
cd functions && npm install          # installs nodemailer
cd ..
firebase deploy --only functions
```

The `functions` block in `firebase.json` runs `npm --prefix ./functions run
build` as a pre-deploy step, so the TypeScript is compiled automatically. The
runtime is Node 22.

To deploy only the notification + trial functions:

```bash
firebase deploy --only \
  functions:onUserCreate,functions:onSubscriptionCreate,functions:onUserSubscriptionUpdated,functions:onPricingCreated,functions:initializeNewUserTrial
```

> All five are **2nd gen** triggers and each declares `secrets: [emailPass]`.
> A v2 deploy that changes a function from 1st to 2nd gen replaces the old
> entry (the console shows it under the v2 runtime).

---

## 5. Test it

### Troubleshooting — `TS2305: Module "firebase-functions/v2/identity" has no exported member 'onUserCreated'`

If `npm run build` (or the deploy) reports this error — together with
`TS7006: Parameter 'event' implicitly has an 'any' type` — the
`functions/node_modules` tree is **stale**. The trigger lives in
`firebase-functions/v2/identity` in **every** published version (there is no
`firebase-functions/v2/auth` — importing from it fails with the same TS2305);
the error only appears when an **old `firebase-functions` 6.x** is installed
locally, because `onUserCreated` was added in **v7**.

Fix — reinstall from the lockfile so 7.4.0 is used:

```bash
cd functions
npm ci            # NOT `npm install` — this pins the exact lockfile version
npm run build     # must print 0 errors
```

`firebase.json` now runs `npm --prefix ./functions ci` in `predeploy`, so
`firebase deploy --only functions` reinstalls the correct version
automatically before building.

> Do **not** "fix" this by changing the import to `firebase-functions/v2/auth`
> — that module does not exist and the error will persist. The correct import
> is `firebase-functions/v2/identity` (see the official docs,
> <https://firebase.google.com/docs/functions/auth-events>).

---

### Troubleshooting — `535 Incorrect authentication data` on Afrihost

`Invalid login: 535 Incorrect authentication data` means the SMTP server
rejected the **AUTH** step. On Afrihost cPanel it is almost never the message
body — it is a host / port / TLS / username mismatch. The deployed config
(`currentEmailConfigWithSecret` in `functions/src/email.ts`) now:

- defaults the host to **`mail.jag-spoor.co.za`** (the cPanel mail host for
  `jag-spoor.co.za`);
- derives the TLS mode **from the port** — `465` → implicit TLS
  (`secure: true`), anything else (e.g. `587`) → STARTTLS — so a **stale
  `EMAIL_SECURE`** left over from a previous deploy can no longer desync the
  protocol and cause a 535;
- uses the **full mailbox address** (`support@jag-spoor.co.za`) as the SMTP
  username — cPanel rejects a bare local-part username.

Diagnose with the logs. Every send now logs:

- `Email config check` — the resolved `host` / `port` / `secure` / `user` /
  `to` **and `passLen`** (the password *length*, never the value). A
  `passLen: 0` means the secret did not resolve; an unexpectedly short value
  means a truncated secret.
- `smtp transport verified` — the handshake + AUTH probe (`transport.verify()`)
  succeeded **before** the real send.
- `smtp transport verify failed` / `support email failed` — carry the exact
  nodemailer `code`, `responseCode` and `response` (e.g. `EAUTH` / `535` /
  `535 Incorrect authentication data`) plus the connection context, so the
  server's own reply is visible instead of just "Invalid login".

```bash
firebase functions:log --only onUserCreate
```

Checklist when a 535 persists after `firebase functions:secrets:set EMAIL_PASS`:

1. **Confirm the secret version is deployed.** The log's `passLen` must be
   non-zero and match the real password length; re-run
   `firebase deploy --only functions` after updating the secret so the new
   version is mounted.
2. **Confirm the username.** `EMAIL_USER` must be the full
   `support@jag-spoor.co.za` (set it explicitly if you have overridden it).
3. **Try the other port.** If `465` still 535s, set `EMAIL_PORT=587`
   (STARTTLS) — or vice versa. No other change is needed: the TLS mode
   follows the port automatically.
4. **Verify the mailbox exists + the password works** by logging into
   `https://webmail.jag-spoor.co.za` (Afrihost cPanel webmail) with the same
   credentials. If webmail rejects it, the password/secret is wrong — not the
   code.
5. **Confirm the sender is authorised.** Some cPanel setups require the
   `From` address to equal the authenticated mailbox — the default already
   does (`from` = `EMAIL_USER`).

> Never put the password in `.env` committed to git. `EMAIL_PASS` is read
> from the Cloud Functions **secret** first, then a plaintext env value.

---

### Quick check — create a test user

1. Sign up a throwaway account in the app (email/password or Google).
2. Within a few seconds the support inbox receives
   `[JagSpoor] New user: <that address>`.
3. Complete a purchase (or write a `users/{uid}/subscriptions` document) and
   the inbox receives `[JagSpoor] New subscription: …`.

### Inspect the logs

```bash
firebase functions:log --only onUserCreate,onSubscriptionCreate,onUserSubscriptionUpdated,onPricingCreated
```

Successful sends log `support email sent` with the message id; a skipped send
logs the reason (for example a missing `EMAIL_PASS`).

### Local emulator

```bash
cd functions
cp .env.example .env          # fill EMAIL_USER / EMAIL_PASS locally (gitignored)
npm run serve                 # build + start the functions emulator
```

The Auth emulator can trigger `onUserCreate` locally, but the SMTP send still
needs a real mailbox password in `EMAIL_PASS`.

### Unit tests

The pure helpers (config resolution, message builders, subscription
transition logic) and the send path (against an injected fake transport) are
covered without any network access:

```bash
cd functions
npm test
```

---

## 6. Where the code lives

| File | Responsibility |
| --- | --- |
| `functions/src/email.ts` | SMTP config resolution, the nodemailer transport, the message builders and `sendSupportEmail`. |
| `functions/src/params.ts` | The shared `EMAIL_PASS` secret declaration (`defineSecret`). |
| `functions/src/notifications.ts` | The four triggers + the subscription-transition logic. |
| `functions/src/user_trial_onboarding.ts` | The 30-day trial trigger (also v2 + the secret). |
| `functions/src/index.ts` | Re-exports the triggers so the Firebase CLI discovers them. |
| `functions/test/email_notifications.test.js` | Unit tests. |
| `functions/.env.example` | Documented `EMAIL_*` variables. |

## 7. Security notes

- **No secrets in the repository.** `EMAIL_PASS` is read from the environment
  (a Cloud Functions secret) and is never written to a tracked file. The
  `functions/.gitignore` excludes `.env`, `.env.local`, `*.local` and service
  account JSON.
- The notification body includes the billing document's full data so support
  can reconcile a payment. Treat the support inbox as sensitive.
- The `supportSubscriptionNotified` dedupe marker is written with the Admin
  SDK (Cloud Functions), which bypasses the client Firestore rules — the
  client can neither read nor write it in a way that affects sending.
