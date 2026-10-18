import { defineSecret } from "firebase-functions/params";

// ────────────────────────────────────────────────────────────────────────────
// Shared Cloud Functions parameters (secrets)
//
// `EMAIL_PASS` is the SMTP password used by every support-notification
// trigger. It is declared as a Cloud Functions *secret* so it is never read
// from the deployed plaintext environment and never committed:
//
//   firebase functions:secrets:set EMAIL_PASS
//
// Any trigger that may send mail must declare it in its options —
//
//   onUserCreated({ secrets: [emailPass] }, handler)
//
// — which both mounts the secret into the runtime AND is what the Firebase
// CLI reads to grant the function access. `emailPass.value()` then resolves
// the password at runtime (it throws during deployment, which is why it is
// only ever called inside a handler).
// ────────────────────────────────────────────────────────────────────────────

/** The SMTP password secret (see `firebase functions:secrets:set EMAIL_PASS`). */
export const emailPass = defineSecret("EMAIL_PASS");

/** The secret name, for tests + documentation. */
export const EMAIL_PASS_SECRET_NAME = "EMAIL_PASS";

// ────────────────────────────────────────────────────────────────────────────
// PayFast web-billing secrets
//
// The web (non-Play) subscription checkout signs its payment form with the
// PayFast merchant KEY and (optionally) a passphrase. Both are Cloud Functions
// *secrets* so they are never read from the deployed plaintext environment and
// never committed to git:
//
//   firebase functions:secrets:set PAYFAST_MERCHANT_KEY
//   firebase functions:secrets:set PAYFAST_PASSPHRASE
//
// The merchant ID (37584965) is PUBLIC — it is embedded in the payment form —
// so it lives as a constant in `payfast/payfast.service.ts`, never a secret.
// ────────────────────────────────────────────────────────────────────────────

/** The PayFast merchant key secret. NEVER returned to the client. */
export const payfastMerchantKey = defineSecret("PAYFAST_MERCHANT_KEY");

/** The PayFast passphrase secret (optional but recommended). */
export const payfastPassphrase = defineSecret("PAYFAST_PASSPHRASE");

/** Secret names, for tests + documentation. */
export const PAYFAST_MERCHANT_KEY_SECRET_NAME = "PAYFAST_MERCHANT_KEY";
export const PAYFAST_PASSPHRASE_SECRET_NAME = "PAYFAST_PASSPHRASE";
