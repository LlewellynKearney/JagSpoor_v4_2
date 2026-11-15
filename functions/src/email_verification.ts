import { logger } from "firebase-functions/v2";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { credential } from "firebase-admin";
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
// The mail is delivered by **Firebase Auth's built-in sender** via the Identity
// Toolkit admin endpoint `projects/{projectId}/accounts:sendOobCode`. This is
// the SAME code path / template the client's `sendEmailVerification()` uses, so
// the resend and the original send are guaranteed to look identical — and it
// removes the custom SMTP dependency entirely (the Afrihost mailbox rejected the
// SMTP AUTH with `535 Incorrect authentication data` even with the correct
// password, so SMTP was a dead end).
//
// Why the admin endpoint and NOT the public key endpoint:
//   * `identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=…` (the client
//     path) requires a valid `idToken` for `VERIFY_EMAIL` — the caller must be
//     the account itself, which is exactly what the admin cannot supply.
//   * The ADMIN endpoint (`projects/{projectId}/accounts:sendOobCode`, called
//     with the runtime service-account OAuth token) sends the built-in template
//     WITHOUT an idToken, and needs the IAM permission
//     `firebaseauth.users.sendEmail` on the runtime service account (a one-time
//     grant — see `REQUIRED_AUTH_SEND_EMAIL_ROLE`).
//
// The Admin SDK's `generateEmailVerificationLink()` is deliberately NOT used: it
// sets `returnOobLink: true`, which MINTS a link and suppresses the send — the
// opposite of what a resend needs. The endpoint is called directly so the
// built-in sender actually fires.
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
 * The IAM permission the resend functions need on their service account to
 * make the built-in sender actually dispatch the mail.
 *
 * The admin `accounts:sendOobCode` endpoint authorizes on the IAM permission
 * `firebaseauth.users.sendEmail` (granted by `roles/firebaseauth.admin` or the
 * narrower `roles/identitytoolkit.admin`). When it is missing the endpoint
 * still mints the OOB code but returns `PERMISSION_DENIED` instead of sending,
 * so the resend must surface that as an actionable diagnostic.
 */
export const REQUIRED_AUTH_SEND_EMAIL_PERMISSION =
  "firebaseauth.users.sendEmail";

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
 * The email is a NON-SECRET identifier; the account is a deploy-time IAM
 * identity, not a credential.
 */
export const RESEND_SERVICE_ACCOUNT =
  "firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com";

/**
 * The shared `onCall` options for BOTH resend callables. Identical by
 * construction so the two functions can never be configured differently.
 *
 * NO `secrets` entry: the resend no longer authenticates to SMTP (the custom
 * mailbox path was a dead end), so the `EMAIL_PASS` secret is neither mounted
 * nor read here. Delivery goes through Firebase Auth's own sender.
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
      `Grant ${REQUIRED_AUTH_ADMIN_ROLE} (or the narrower ` +
      `${REQUIRED_AUTH_SEND_EMAIL_PERMISSION}) to this service account. ` +
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
 * True when an error is a permission/authorization failure for the built-in
 * sender — either the Admin SDK's `auth/insufficient-permission` or the raw
 * Identity Toolkit `PERMISSION_DENIED` the admin `accounts:sendOobCode`
 * endpoint returns when the runtime service account lacks
 * `firebaseauth.users.sendEmail`.
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
 * Resends the verification email to a SINGLE account.
 *
 * Admin-only. Delivers the mail through Firebase Auth's own sender (the
 * `accounts:sendOobCode` admin endpoint) and records the outcome on
 * `users/{uid}`.
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

  // Deliver via Firebase Auth's OWN sender. The admin `accounts:sendOobCode`
  // endpoint both MINTS the code AND sends the built-in template, so there is
  // no separate link-generation step (and no custom SMTP).
  try {
    await sendVerificationEmailViaFirebase(email);
    await recordOutcome(uid, { sent: true });
    logger.info("resendOne: verification email sent via Firebase sender", {
      uid,
      email,
    });
    return { uid, email, delivered: true, linkGenerated: true };
  } catch (err) {
    const reason = `send failed: ${describe(err)}`;
    const diagnostic = isPermissionDeniedError(err)
      ? await diagnosticFor(err)
      : undefined;
    if (diagnostic) {
      logger.error("resendOne: sendOobCode DENIED (IAM)", { uid, diagnostic });
    } else {
      logger.warn("resendOne: sendOobCode failed", { uid, reason });
    }
    await recordOutcome(uid, { sent: false, error: reason });
    return { uid, email, delivered: false, linkGenerated: false, reason, diagnostic };
  }
}

/**
 * The Identity Toolkit admin endpoint that both mints the OOB code AND sends
 * the Firebase Auth verification template — the server-side equivalent of the
 * client's `sendEmailVerification()`.
 *
 * The PUBLIC endpoint (`identitytoolkit.googleapis.com/v1/accounts:sendOobCode
 * ?key=…`) requires the target user's `idToken` for `VERIFY_EMAIL`, so an admin
 * cannot use it. The ADMIN endpoint below (`projects/{projectId}/…`) authorizes
 * on the caller's OAuth credential (the runtime service account) instead and
 * needs no idToken.
 */
export function sendOobCodeEndpoint(projectId: string): string {
  return (
    `https://identitytoolkit.googleapis.com/v1/projects/${projectId}` +
    `/accounts:sendOobCode`
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

/** Resolves an OAuth access token for the sender (the runtime SA's token). */
export type AccessTokenResolver = () => Promise<string | null>;

/** Test seam: override the access-token resolver. */
let accessTokenResolverForTesting: AccessTokenResolver | null = null;

/** Test seam: override the access-token resolver (null = use the SDK). */
export function setAccessTokenResolverForTesting(
  resolver: AccessTokenResolver | null
): void {
  accessTokenResolverForTesting = resolver;
}

/**
 * The OAuth access token used to call the admin sendOobCode endpoint. Defaults
 * to the Admin SDK credential — the SAME identity `initializeApp()` uses — so
 * the call is authorized as the function's runtime service account.
 */
async function resolveSenderAccessToken(): Promise<string> {
  if (accessTokenResolverForTesting) {
    const token = await accessTokenResolverForTesting();
    if (!token) throw new Error("no access token from the resolver");
    return token;
  }
  const app = getAdmin();
  const cred = app.options.credential ?? credential.applicationDefault();
  const token = await cred.getAccessToken();
  if (!token?.access_token) {
    throw new Error("could not obtain an OAuth access token for the sender");
  }
  return token.access_token;
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

/**
 * Sends the Firebase Auth email-verification template to `email` through the
 * built-in sender (admin `accounts:sendOobCode`). Throws on any non-2xx so the
 * caller can record the reason + build a diagnostic.
 *
 * Uses the runtime service account's OAuth token — obtained from the Admin
 * SDK's credential (`app.options.credential ?? applicationDefault()`), which is
 * the SAME identity `initializeApp()` uses. No explicit credential is passed to
 * `initializeApp()` (see `firebase.ts`).
 */
export async function sendVerificationEmailViaFirebase(
  email: string
): Promise<void> {
  const token = await resolveSenderAccessToken();
  const url = sendOobCodeEndpoint(resolveProjectId());
  const doFetch: SendOobCodeFetch =
    sendOobCodeFetchForTesting ??
    ((u, init) => fetch(u, init) as unknown as ReturnType<SendOobCodeFetch>);

  const res = await doFetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ requestType: "VERIFY_EMAIL", email }),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    // Surface the Identity Toolkit status so a PERMISSION_DENIED becomes an
    // actionable diagnostic (missing firebaseauth.users.sendEmail).
    throw Object.assign(new Error(text || `HTTP ${res.status}`), {
      status: res.status === 403 ? "PERMISSION_DENIED" : undefined,
      code: res.status,
      httpStatus: res.status,
    });
  }
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
