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
