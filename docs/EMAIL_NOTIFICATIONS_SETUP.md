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
| `EMAIL_USER` | `support@jag-spoor.co.za` | SMTP username **and** the default `From` address. |
| `EMAIL_PASS` | *(unset)* | SMTP password. **Required** to send. Set as a secret. |
| `EMAIL_HOST` | `mail.jag-spoor.co.za` | SMTP host. Set to `smtp.gmail.com` to switch providers later. |
| `EMAIL_PORT` | `465` | SMTP port (465 implicit TLS / 587 STARTTLS). |
| `EMAIL_SECURE` | `true` | `false` selects STARTTLS (use with port 587). |
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
