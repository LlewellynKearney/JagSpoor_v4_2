import { logger } from "firebase-functions/v2";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import {
  auth,
  firestore,
  getAdmin,
  describeCredential,
  resolveRuntimeServiceAccountEmail,
  type CredentialDiagnostic,
} from "./firebase";
import { ADMIN_EMAIL_ALLOW_LIST, isAdminRequest } from "./admin/kpis";

// ────────────────────────────────────────────────────────────────────────────
// Email-verification resend
//
// ## Why this exists
//
// Email-verification mails are dispatched by **Firebase Auth itself**
// (`User.sendEmailVerification()` on the client) — there is no Cloud Function
// in the send path, so the app cannot resend on behalf of an account it is not
// signed into. The admin portal needs to re-send to accounts that missed the
// mail.
//
// This module owns that admin-only surface:
//   * `resendVerificationEmail`        — one account.
//   * `resendVerificationEmailsBulk`   — a capped batch (see BULK_LIMIT).
//
// Both are admin-gated with the SAME authorization `isAdminRequest` used by
// `getAdminPortalKpis` (custom claim -> email allow-list -> `users/{uid}.role`),
// so a non-admin can never trigger a resend.
//
// ## Delivery — Firebase Auth's OWN sender (no custom SMTP)
//
// The mail is delivered by **Firebase Auth's built-in sender** through the
// Identity Toolkit endpoint `accounts:sendOobCode` — the SAME code path /
// template the client's `sendEmailVerification()` uses, so the resend and the
// original send look identical, and the custom SMTP dependency stays gone (the
// Afrihost mailbox rejected SMTP AUTH with `535 Incorrect authentication data`
// even with the correct password, so SMTP was a dead end — do NOT go back).
//
// ## Why the PUBLIC endpoint + a minted idToken (the INVALID_ID_TOKEN bug)
//
// `accounts:sendOobCode` with `requestType: "VERIFY_EMAIL"` authorizes on the
// TARGET USER's `idToken` — the caller must be the account itself. The ADMIN
// endpoint (`projects/{projectId}/accounts:sendOobCode`) looks like the right
// tool because it accepts a service-account OAuth token, but Firebase REJECTS a
// service-account token for `VERIFY_EMAIL` with `400 INVALID_ID_TOKEN`: a
// service account is not a user, so there is no user identity to verify. That
// was the live failure (`send failed: 400: INVALID_ID_TOKEN`).
//
// The send therefore MINTS a user idToken for the target account first:
//
//   1. `admin.auth().createCustomToken(uid)`            — a signed custom token
//   2. `accounts:signInWithCustomToken?key=<API_KEY>`   — exchange it for that
//      account's `idToken` (the standard "impersonate a user from a server"
//      flow; the custom token is what proves the server's authority)
//   3. `accounts:sendOobCode?key=<API_KEY>` with
//      `{requestType: "VERIFY_EMAIL", idToken}`         — the real send
//
// `?key=` is the PUBLIC Firebase Web API key. It is NOT a secret — it already
// ships in every client build (see `lib/firebase_options.dart`); it only
// identifies the project. The send still requires a valid user idToken, so the
// public key alone grants nothing.
//
// Fallback when no API key is configured server-side: `admin.auth()
// .generateEmailVerificationLink()` mints the SAME link the email would carry
// and returns it to the caller so the admin can deliver it — a real
// verification link, never SMTP.
//
// Every attempt writes the SAME audit trail the client writes
// (`verificationEmailSent` / `verificationEmailLastError` /
// `verificationEmailLastAttemptAt`) so the portal can show exactly which
// accounts are still pending after a run.
// ────────────────────────────────────────────────────────────────────────────

/** The `users/{uid}` audit-trail fields (mirrors the Flutter service). */
export const VERIFICATION_SENT_FIELD = "verificationEmailSent";
export const VERIFICATION_LAST_ERROR_FIELD = "verificationEmailLastError";
export const VERIFICATION_LAST_ATTEMPT_FIELD = "verificationEmailLastAttemptAt";

/**
 * The maximum number of accounts a single bulk resend may address.
 *
 * Resending sends one mail per account; an unbounded batch could exhaust the
 * Identity Toolkit send quota and get the project throttled. The bulk action
 * processes at most this many accounts per run and reports the remainder.
 * Mirrors `kAdminVerificationResendBatchLimit` on the client.
 */
export const BULK_LIMIT = 50;

/** Result of one account's resend attempt. */
export interface ResendResult {
  uid: string;
  email: string;
  delivered: boolean;
  linkGenerated: boolean;
  reason?: string;
  /**
   * The HTTP status code `accounts:sendOobCode` answered with, when it was
   * reached. Logged (never the token) so a failure is diagnosable from the
   * portal instead of a bare "send failed". Absent when the send was never
   * attempted (no email on the account, lookup failure) or the failure
   * happened before the HTTP call.
   */
  statusCode?: number;
  /**
   * The verification link, present only on the no-API-key fallback path (the
   * send could not be performed, so the minted link is returned for the admin
   * to deliver). Absent on a normal send — the mail carries the link.
   */
  verificationLink?: string;
  /**
   * Present when the failure is a CREDENTIAL problem (the Auth Admin call was
   * rejected because the service account lacks a permission). Carries the
   * non-secret identity + the missing role so the admin UI can fix IAM instead
   * of staring at a bare "0 of N".
   */
  diagnostic?: ResendDiagnostic;
}

/** Actionable, non-secret context for a credential/permission failure. */
export interface ResendDiagnostic {
  /** Short machine-ish code, e.g. "insufficient-permission". */
  code: string;
  /** What went wrong, in one line. */
  message: string;
  /** The role that must be granted to `serviceAccount`. */
  missingRole: string;
  /** The service account the function ran as (non-secret identifier). */
  serviceAccount: string | null;
  /** Credential source: serviceAccountKey | computeMetadata | ... */
  credentialSource: string;
  /** True when the root cause is the explicit-credential bug. */
  explicitCredential: boolean;
  /** The raw credential class name (e.g. ServiceAccountCredential). */
  credentialClass: string;
  /** The Cloud Run service name (`K_SERVICE`) when known. */
  cloudRunService?: string | null;
}

/** The IAM role the resend functions need on their service account. */
export const REQUIRED_AUTH_ADMIN_ROLE = "roles/firebaseauth.admin";

/**
 * The IAM permission needed to mint a custom token for another account.
 *
 * Step 1 of the send (`admin.auth().createCustomToken(uid)`) authorizes on
 * `firebaseauth.users.get` (granted by `roles/firebaseauth.admin`). Kept as a
 * named constant so the diagnostic can name the exact permission.
 */
export const REQUIRED_AUTH_CUSTOM_TOKEN_PERMISSION =
  "firebaseauth.users.get";

/**
 * The public Firebase **Web API key** the `?key=` query parameter takes.
 *
 * NOT a secret: it is the same value that already ships in every client build
 * (see `lib/firebase_options.dart` — e.g. the web key
 * `AIzaSyC0yB1vwZMid1rixywPRWjWrhL6Ww--br0`). It only IDENTIFIES the project
 * to Identity Toolkit; the send still needs a valid user idToken, so the key
 * alone grants nothing.
 *
 * Resolution order (`resolveApiKey`):
 *   1. the `FIREBASE_API_KEY` env var (an operator override),
 *   2. the compiled-in project web key (the default below).
 *
 * Set `FIREBASE_API_KEY` in the Functions environment to override without a
 * code change.
 */
export const FIREBASE_WEB_API_KEY_DEFAULT =
  "AIzaSyC0yB1vwZMid1rixywPRWjWrhL6Ww--br0";

/**
 * The service account BOTH resend functions are pinned to.
 *
 * The two functions were originally left on the project's default compute
 * service account (`<project-number>-compute@developer.gserviceaccount.com`),
 * which does NOT hold Firebase Authentication Admin. The bulk function was
 * later re-pointed at the Admin SDK account by hand — but the singular one was
 * missed, so the two drifted apart and only the bulk path worked. Pinning BOTH
 * to the SAME account here (via the `serviceAccount` deploy option) makes the
 * divergence impossible: the CLI applies this on every deploy, overwriting any
 * manual change.
 *
 * The account needs `roles/firebaseauth.admin` (mint the custom token + look
 * the user up). It does NOT need `firebaseauth.users.sendEmail` any more: the
 * mail is sent with the USER's idToken via the public endpoint, not with the
 * service account.
 *
 * The email is a NON-SECRET identifier; the account is a deploy-time IAM
 * identity, not a credential.
 */
export const RESEND_SERVICE_ACCOUNT =
  "firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com";

/**
 * The shared `onCall` options for BOTH resend callables. Identical by
 * construction so the two functions can never be configured differently.
 *
 * NO `secrets` entry: the resend authenticates with a minted USER idToken via
 * the public Identity Toolkit endpoint, so no SMTP credential (and no
 * `EMAIL_PASS` secret) is mounted or read here. Delivery goes through Firebase
 * Auth's own sender.
 */
export function resendCallableOptions() {
  return {
    region: "us-central1" as const,
    maxInstances: 10,
    serviceAccount: RESEND_SERVICE_ACCOUNT,
  };
}

/** True when an error is the Admin SDK "insufficient permission" Auth error. */
export function isInsufficientPermissionError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const e = err as { code?: string; message?: string };
  const code = (e.code ?? "").toString().toLowerCase();
  const message = (e.message ?? "").toString().toLowerCase();
  return (
    code.includes("insufficient-permission") ||
    message.includes("insufficient permission")
  );
}

/**
 * Builds the actionable diagnostic for a credential failure. Pure +
 * testable; takes the credential descriptor so a test can inject one.
 *
 * `runtimeServiceAccount` is the email resolved from the metadata server / env
 * (see `resolveRuntimeServiceAccountEmail`); when present it is used to NAME
 * the identity instead of the placeholder that told the operator to go find it
 * in the Cloud Run console.
 */
export function buildResendDiagnostic(
  err: unknown,
  cred: CredentialDiagnostic,
  runtimeServiceAccount?: string | null
): ResendDiagnostic {
  const e = err as { code?: string; message?: string };
  const identity =
    cred.serviceAccount ??
    runtimeServiceAccount ??
    (cred.source === "computeMetadata"
      ? "(runtime service account — resolve via Cloud Run console)"
      : "(unknown service account)");
  const rootCause = cred.explicitCredential
    ? "an explicit credential was passed to initializeApp() — remove it so " +
      "the function uses its runtime service account"
    : `the function's runtime service account is missing the role/permission; ` +
      `the function should be pinned to ${RESEND_SERVICE_ACCOUNT} (the Admin ` +
      `SDK account) via the serviceAccount deploy option`;
  return {
    code: (e?.code ?? "insufficient-permission").toString(),
    message:
      `Auth Admin call rejected: the credential has insufficient permission. ` +
      `Identity: ${identity} (source: ${cred.source}). ` +
      `Grant ${REQUIRED_AUTH_ADMIN_ROLE} (which includes ` +
      `${REQUIRED_AUTH_CUSTOM_TOKEN_PERMISSION}, needed to mint the user ` +
      `idToken the send requires) to this service account. ` +
      `Likely root cause: ${rootCause}.`,
    missingRole: REQUIRED_AUTH_ADMIN_ROLE,
    serviceAccount: cred.serviceAccount ?? runtimeServiceAccount ?? null,
    credentialSource: cred.source,
    explicitCredential: cred.explicitCredential,
    credentialClass: cred.credentialClass,
    cloudRunService: cred.cloudRunService ?? null,
  };
}

/**
 * True when an error is a permission/authorization failure — the Admin SDK's
 * `auth/insufficient-permission` (minting the custom token / looking the user
 * up), or a raw Identity Toolkit `PERMISSION_DENIED` (the project's Identity
 * Toolkit API is disabled, or the API key is restricted).
 */
export function isPermissionDeniedError(err: unknown): boolean {
  if (isInsufficientPermissionError(err)) return true;
  if (!err || typeof err !== "object") return false;
  const e = err as { status?: string; code?: string | number; message?: string };
  if ((e.status ?? "").toString().toUpperCase() === "PERMISSION_DENIED") {
    return true;
  }
  if ((e.code ?? "").toString().toUpperCase() === "PERMISSION_DENIED") {
    return true;
  }
  return (e.message ?? "").toString().toLowerCase().includes("permission_denied");
}

/**
 * True when the failure is the service-account-token bug this fix removes:
 * Identity Toolkit rejected the credential with `INVALID_ID_TOKEN` because a
 * service account is not a user. Named so the portal can explain the cause
 * instead of showing a bare `400`.
 */
export function isInvalidIdTokenError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const e = err as { message?: string };
  return (e.message ?? "")
    .toString()
    .toUpperCase()
    .includes("INVALID_ID_TOKEN");
}

/**
 * Resends the verification email to a SINGLE account.
 *
 * Admin-only. Delivers the mail through Firebase Auth's own sender (the public
 * `accounts:sendOobCode` endpoint, authorized with a minted USER idToken) and
 * records the outcome on `users/{uid}`.
 */
export const resendVerificationEmail = onCall(
  resendCallableOptions(),
  async (req: CallableRequest<{ uid?: string }>): Promise<ResendResult> => {
    const caller = req.auth;
    if (!caller || !caller.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    await assertAdmin(caller);

    const uid = (req.data?.uid ?? "").toString().trim();
    if (!uid) {
      throw new HttpsError("invalid-argument", "A target uid is required.");
    }

    const result = await resendOne(uid);
    if (result.diagnostic) {
      // A credential/IAM problem: surface the actionable identity + missing
      // role to the caller (the audit trail was already written).
      throw new HttpsError("failed-precondition", result.diagnostic.message);
    }
    if (!result.delivered) {
      // Surface a hard failure to the caller so the UI can report it; a
      // partial (link minted, mail not sent) is still a 200 with
      // delivered:false so the audit trail stays accurate.
      logger.warn("resendVerificationEmail: not delivered", result);
    }
    return result;
  }
);

/**
 * Resends the verification email to a capped BATCH of accounts.
 *
 * Admin-only. The caller passes the uids to address (the portal computes the
 * missed-email set from the already-fetched records); the list is trimmed to
 * [BULK_LIMIT] so a single run can never exceed the quota. Returns per-account
 * results plus the number skipped by the cap.
 */
export const resendVerificationEmailsBulk = onCall(
  resendCallableOptions(),
  async (
    req: CallableRequest<{ uids?: string[] }>
  ): Promise<{
    results: ResendResult[];
    processed: number;
    skipped: number;
    limit: number;
  }> => {
    const caller = req.auth;
    if (!caller || !caller.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    await assertAdmin(caller);

    const requested = Array.isArray(req.data?.uids)
      ? req.data!.uids!.map((u) => (u ?? "").toString().trim()).filter(Boolean)
      : [];
    if (requested.length === 0) {
      throw new HttpsError("invalid-argument", "No target uids were provided.");
    }

    const batch = requested.slice(0, BULK_LIMIT);
    const skipped = requested.length - batch.length;

    const results: ResendResult[] = [];
    // Sequential (not Promise.all) so the batch cannot burst the Identity
    // Toolkit send quota — a concurrent flood is the fastest way to trip a
    // rate limit.
    for (const uid of batch) {
      results.push(await resendOne(uid));
    }

    logger.info("resendVerificationEmailsBulk complete", {
      processed: results.length,
      skipped,
      delivered: results.filter((r) => r.delivered).length,
    });

    // If EVERY attempt failed with the SAME credential problem, the caller
    // gets a bare "0 of N" — surface the actionable identity + missing role
    // instead so the admin fixes IAM rather than guessing.
    const diagnostics = results
      .map((r) => r.diagnostic)
      .filter((d): d is ResendDiagnostic => !!d);
    if (results.length > 0 && diagnostics.length === results.length) {
      logger.error("resendVerificationEmailsBulk: all attempts DENIED (IAM)", {
        diagnostic: diagnostics[0],
        attempted: results.length,
      });
      throw new HttpsError("failed-precondition", diagnostics[0].message);
    }

    return { results, processed: results.length, skipped, limit: BULK_LIMIT };
  }
);

/** Authorizes the caller as an admin (claim -> allow-list -> users doc role). */
async function assertAdmin(caller: CallableRequest["auth"]): Promise<void> {
  let usersDocRole: string | null = null;
  try {
    const doc = await firestore().collection("users").doc(caller!.uid).get();
    usersDocRole = ((doc.data() ?? {})["role"] ?? "").toString();
  } catch {
    /* treat as non-admin */
  }
  if (!isAdminRequest(caller, usersDocRole)) {
    throw new HttpsError(
      "permission-denied",
      "Admin privileges are required to resend verification emails."
    );
  }
}

/**
 * Memoised runtime service-account email.
 *
 * Resolved from the metadata server / env on the FIRST credential failure only
 * (the happy path never pays for it), then cached for the process lifetime —
 * the identity cannot change while the container is running.
 */
let runtimeServiceAccountCache: string | null | undefined;

/** Test seam: override the resolved runtime SA (null = "unknown"). */
export function setRuntimeServiceAccountForTesting(value: string | null): void {
  runtimeServiceAccountCache = value;
}

/** Test seam: reset the memoised runtime SA so it re-resolves. */
export function resetRuntimeServiceAccountForTesting(): void {
  runtimeServiceAccountCache = undefined;
}

async function runtimeServiceAccountEmail(): Promise<string | null> {
  if (runtimeServiceAccountCache !== undefined) {
    return runtimeServiceAccountCache;
  }
  runtimeServiceAccountCache = await resolveRuntimeServiceAccountEmail();
  return runtimeServiceAccountCache;
}

/**
 * Builds the credential diagnostic for an Auth Admin failure, naming the exact
 * runtime service account (resolved from the metadata server / env) instead of
 * the "resolve via Cloud Run console" placeholder.
 */
async function diagnosticFor(err: unknown): Promise<ResendDiagnostic> {
  const runtimeSa = await runtimeServiceAccountEmail();
  return buildResendDiagnostic(err, describeCredential(), runtimeSa);
}

/** Resends to one uid, recording the outcome. Never throws for a per-account
 * failure (a missing user / mail failure is reported in the result). */
async function resendOne(uid: string): Promise<ResendResult> {
  let email = "";
  try {
    const user = await auth().getUser(uid);
    email = (user.email ?? "").toString().trim();
    if (!email) {
      const reason = "account has no email address";
      await recordOutcome(uid, { sent: false, error: reason });
      return { uid, email, delivered: false, linkGenerated: false, reason };
    }
  } catch (err) {
    const reason = `lookup failed: ${describe(err)}`;
    const diagnostic = isPermissionDeniedError(err)
      ? await diagnosticFor(err)
      : undefined;
    if (diagnostic) {
      logger.error("resendOne: Auth Admin lookup DENIED (IAM)", {
        uid,
        diagnostic,
      });
    } else {
      logger.warn("resendOne: user lookup failed", { uid, reason });
    }
    await recordOutcome(uid, { sent: false, error: reason });
    return { uid, email, delivered: false, linkGenerated: false, reason, diagnostic };
  }

  // Deliver via Firebase Auth's OWN sender: mint a custom token for the uid,
  // exchange it for that account's idToken, then call the PUBLIC
  // `accounts:sendOobCode` endpoint with the idToken. The service-account OAuth
  // token is deliberately NOT used for the send — it yields
  // `400 INVALID_ID_TOKEN` (a service account is not a user).
  try {
    const outcome = await sendVerificationEmailViaFirebase(uid, email);
    if (outcome.verificationLink) {
      // No API key configured server-side: the send was impossible, so the
      // minted link is handed back for the admin to deliver. A real
      // verification link — never SMTP.
      const reason = "no API key configured — verification link returned";
      await recordOutcome(uid, { sent: false, error: reason });
      logger.warn("resendOne: no API key — link returned instead of a send", {
        uid,
        email,
      });
      return {
        uid,
        email,
        delivered: false,
        linkGenerated: true,
        reason,
        verificationLink: outcome.verificationLink,
      };
    }
    await recordOutcome(uid, { sent: true });
    logger.info("resendOne: verification email sent via Firebase sender", {
      uid,
      email,
      statusCode: outcome.statusCode,
    });
    return {
      uid,
      email,
      delivered: true,
      linkGenerated: true,
      statusCode: outcome.statusCode,
    };
  } catch (err) {
    // Log the sendOobCode RESPONSE CODE (never a token) so a failure is
    // diagnosable from the portal.
    const statusCode = httpStatusOf(err);
    const reason = `send failed: ${describe(err)}`;
    const diagnostic = isPermissionDeniedError(err)
      ? await diagnosticFor(err)
      : undefined;
    if (diagnostic) {
      logger.error("resendOne: sendOobCode DENIED (IAM)", {
        uid,
        statusCode,
        diagnostic,
      });
    } else {
      logger.warn("resendOne: sendOobCode failed", { uid, statusCode, reason });
    }
    await recordOutcome(uid, { sent: false, error: reason });
    return {
      uid,
      email,
      delivered: false,
      linkGenerated: false,
      reason,
      statusCode,
      diagnostic,
    };
  }
}

/** The HTTP status carried by a send-path error, when present. */
function httpStatusOf(err: unknown): number | undefined {
  if (!err || typeof err !== "object") return undefined;
  const e = err as { httpStatus?: unknown; code?: unknown };
  const direct = Number(e.httpStatus);
  if (Number.isFinite(direct) && direct > 0) return direct;
  const code = Number(e.code);
  if (Number.isFinite(code) && code >= 100 && code < 600) return code;
  return undefined;
}

/**
 * The PUBLIC Identity Toolkit endpoint that MINTS + SENDS the Firebase Auth
 * verification template — the server-side equivalent of the client's
 * `sendEmailVerification()`.
 *
 * `requestType: "VERIFY_EMAIL"` authorizes on the TARGET USER's `idToken`, so
 * the caller must be the account itself. A service-account OAuth token is
 * rejected with `400 INVALID_ID_TOKEN` (a service account is not a user) —
 * which is exactly the bug this endpoint pair fixes. See
 * [mintUserIdToken] for how the idToken is obtained.
 */
export function sendOobCodeEndpoint(apiKey: string): string {
  return (
    `https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode` +
    `?key=${apiKey}`
  );
}

/** The Identity Toolkit endpoint that exchanges a custom token for an idToken. */
export function signInWithCustomTokenEndpoint(apiKey: string): string {
  return (
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken` +
    `?key=${apiKey}`
  );
}

/** Injectable fetch seam so the send path is unit-testable without network. */
export type SendOobCodeFetch = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body: string;
  }
) => Promise<{ ok: boolean; status: number; text(): Promise<string> }>;

let sendOobCodeFetchForTesting: SendOobCodeFetch | null = null;

/** Test seam: override the fetch used to call the endpoint. */
export function setSendOobCodeFetchForTesting(
  fetchImpl: SendOobCodeFetch | null
): void {
  sendOobCodeFetchForTesting = fetchImpl;
}

/** Test seam: override the resolved project id. */
let sendOobCodeProjectIdForTesting: string | null = null;

/** Test seam: override the project id (null = use the runtime default). */
export function setSendOobCodeProjectIdForTesting(
  projectId: string | null
): void {
  sendOobCodeProjectIdForTesting = projectId;
}

/** Test seam: override the resolved public Web API key. */
let apiKeyForTesting: string | null | undefined;

/**
 * Test seam: override the API key.
 *
 * Pass a string to force a key, or `null` to simulate "no key configured"
 * (which exercises the `generateEmailVerificationLink` fallback). Call
 * [resetApiKeyForTesting] to restore the runtime resolution.
 */
export function setApiKeyForTesting(apiKey: string | null): void {
  apiKeyForTesting = apiKey;
}

/** Test seam: restore the runtime API-key resolution. */
export function resetApiKeyForTesting(): void {
  apiKeyForTesting = undefined;
}

/**
 * Resolves the public Firebase Web API key (`?key=`). NEVER a secret — it ships
 * in every client build; see [FIREBASE_WEB_API_KEY_DEFAULT].
 *
 * Returns null when nothing is configured, which routes the send to the
 * `generateEmailVerificationLink` fallback instead of failing.
 */
export function resolveApiKey(): string | null {
  if (apiKeyForTesting !== undefined) return apiKeyForTesting;
  const fromEnv = (process.env.FIREBASE_API_KEY ?? "").toString().trim();
  if (fromEnv) return fromEnv;
  const fallback = FIREBASE_WEB_API_KEY_DEFAULT.trim();
  return fallback.length > 0 ? fallback : null;
}

/** Test seam: override the custom-token minter. */
let customTokenMinterForTesting: ((uid: string) => Promise<string>) | null =
  null;

/** Test seam: override the custom-token minter (null = use the Admin SDK). */
export function setCustomTokenMinterForTesting(
  minter: ((uid: string) => Promise<string>) | null
): void {
  customTokenMinterForTesting = minter;
}

/**
 * Step 1 — mints a signed custom token for `uid` via the Admin SDK.
 *
 * The custom token is what proves the SERVER's authority over the account; it
 * is then exchanged for a real user idToken (step 2) which the public
 * `accounts:sendOobCode` endpoint accepts for `VERIFY_EMAIL`.
 */
export async function mintCustomToken(uid: string): Promise<string> {
  if (customTokenMinterForTesting) return customTokenMinterForTesting(uid);
  return auth().createCustomToken(uid);
}

/** Test seam: override the link minter used by the no-API-key fallback. */
let verificationLinkMinterForTesting: ((email: string) => Promise<string>) | null =
  null;

/** Test seam: override the verification-link minter (null = Admin SDK). */
export function setVerificationLinkMinterForTesting(
  minter: ((email: string) => Promise<string>) | null
): void {
  verificationLinkMinterForTesting = minter;
}

/**
 * Mints the SAME verification link the built-in email would carry.
 *
 * Used ONLY as the fallback when no API key is configured server-side: the
 * link is returned to the caller so the admin can deliver it. This is a real
 * Firebase verification link, never an SMTP send.
 */
export async function mintVerificationLink(email: string): Promise<string> {
  if (verificationLinkMinterForTesting) {
    return verificationLinkMinterForTesting(email);
  }
  return auth().generateEmailVerificationLink(email);
}

/**
 * Step 2 — exchanges a custom token for the account's `idToken`.
 *
 * `accounts:signInWithCustomToken` is the documented way to act as a user from
 * a trusted server. The returned idToken is short-lived and scoped to this
 * account.
 */
export async function mintUserIdToken(
  customToken: string,
  apiKey: string
): Promise<string> {
  const doFetch: SendOobCodeFetch =
    sendOobCodeFetchForTesting ??
    ((u, init) => fetch(u, init) as unknown as ReturnType<SendOobCodeFetch>);

  const res = await doFetch(signInWithCustomTokenEndpoint(apiKey), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw Object.assign(new Error(text || `HTTP ${res.status}`), {
      code: res.status,
      httpStatus: res.status,
      step: "signInWithCustomToken",
    });
  }

  const body = JSON.parse((await res.text()) || "{}") as {
    idToken?: string;
  };
  const idToken = (body.idToken ?? "").toString();
  if (!idToken) {
    throw Object.assign(new Error("signInWithCustomToken returned no idToken"), {
      code: 500,
      httpStatus: 500,
      step: "signInWithCustomToken",
    });
  }
  return idToken;
}

function resolveProjectId(): string {
  if (sendOobCodeProjectIdForTesting) return sendOobCodeProjectIdForTesting;
  const app = getAdmin();
  const fromOptions = (app.options.projectId ?? "").toString().trim();
  if (fromOptions) return fromOptions;
  const fromEnv =
    (process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT ?? "").toString().trim();
  if (fromEnv) return fromEnv;
  throw new Error("Unable to resolve the Firebase project id for sendOobCode.");
}

/** Outcome of a send attempt: delivered, or the minted link as a fallback. */
export interface SendVerificationOutcome {
  /** True when Identity Toolkit accepted the send (the mail is on its way). */
  delivered: boolean;
  /** The HTTP status `accounts:sendOobCode` answered with (never a token). */
  statusCode?: number;
  /** The minted link — present ONLY on the no-API-key fallback path. */
  verificationLink?: string;
}

/**
 * Sends the Firebase Auth email-verification template to the account `uid`.
 *
 * Uses the two-step "act as the user" flow: mint a custom token for the uid,
 * exchange it for that account's idToken, then call the PUBLIC
 * `accounts:sendOobCode` endpoint with the idToken. The service-account OAuth
 * token is NEVER used for the send — that is what produced
 * `400 INVALID_ID_TOKEN`.
 *
 * Throws on any non-2xx so the caller can record the reason + build a
 * diagnostic. The thrown error carries `httpStatus` (the sendOobCode status
 * code) but never a token.
 *
 * When no API key is configured, the send is impossible; instead of failing the
 * caller gets the minted verification LINK so the admin can deliver it (a real
 * verification link — never SMTP).
 */
export async function sendVerificationEmailViaFirebase(
  uid: string,
  email: string
): Promise<SendVerificationOutcome> {
  const apiKey = resolveApiKey();
  if (!apiKey) {
    const link = await mintVerificationLink(email);
    return { delivered: false, verificationLink: link };
  }

  const customToken = await mintCustomToken(uid);
  const idToken = await mintUserIdToken(customToken, apiKey);
  const url = sendOobCodeEndpoint(apiKey);
  const doFetch: SendOobCodeFetch =
    sendOobCodeFetchForTesting ??
    ((u, init) => fetch(u, init) as unknown as ReturnType<SendOobCodeFetch>);

  const res = await doFetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ requestType: "VERIFY_EMAIL", idToken }),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    // Surface the Identity Toolkit status code (never the token) so the portal
    // can show WHY the send failed.
    throw Object.assign(new Error(text || `HTTP ${res.status}`), {
      code: res.status,
      httpStatus: res.status,
      step: "sendOobCode",
    });
  }

  return { delivered: true, statusCode: res.status };
}

/** Writes the verification audit trail (best-effort; never throws). */
async function recordOutcome(
  uid: string,
  outcome: { sent: boolean; error?: string }
): Promise<void> {
  try {
    const payload: Record<string, unknown> = {
      [VERIFICATION_SENT_FIELD]: outcome.sent,
      [VERIFICATION_LAST_ATTEMPT_FIELD]: FieldValue.serverTimestamp(),
    };
    payload[VERIFICATION_LAST_ERROR_FIELD] = outcome.sent
      ? FieldValue.delete()
      : outcome.error ?? "unknown error";
    await firestore().collection("users").doc(uid).set(payload, {
      merge: true,
    });
  } catch (err) {
    logger.warn("resendOne: audit write failed", { uid, error: describe(err) });
  }
}

function describe(err: unknown): string {
  if (err && typeof err === "object") {
    const e = err as { code?: string; message?: string };
    if (e.message) {
      return e.code ? `${e.code}: ${e.message}` : e.message;
    }
  }
  return String(err);
}

/** Re-exported so tests can assert the admin allow-list wiring. */
export { ADMIN_EMAIL_ALLOW_LIST };
