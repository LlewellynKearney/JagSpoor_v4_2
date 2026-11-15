import { logger } from "firebase-functions/v2";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import {
  auth,
  firestore,
  describeCredential,
  resolveRuntimeServiceAccountEmail,
  type CredentialDiagnostic,
} from "./firebase";
import { emailPass } from "./params";
import {
  EmailNotificationKind,
  buildSubject,
  sendSupportEmail,
  type SendResult,
} from "./email";
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
// mail, which requires the Admin SDK's `generateEmailVerificationLink()`.
//
// This module owns that admin-only surface:
//   * `resendVerificationEmail`        — one account.
//   * `resendVerificationEmailsBulk`   — a capped batch (see BULK_LIMIT).
//
// Both are admin-gated with the SAME authorization `isAdminRequest` used by
// `getAdminPortalKpis` (custom claim -> email allow-list -> `users/{uid}.role`),
// so a non-admin can never trigger a resend.
//
// ## Delivery
//
// Firebase Auth's own template delivery cannot be forced from the Admin SDK —
// `generateEmailVerificationLink()` only MINTS the link. Two delivery paths:
//
//   1. SMTP (preferred when the mailbox secret is configured): the minted link
//      is emailed to the user from the support mailbox. This works for every
//      account and needs no client involvement.
//   2. Fallback: when SMTP is unavailable the link is still minted (so the
//      account is recoverable) and logged, and the function reports
//      `delivered: false` with the link status — the caller surfaces it.
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
 * Resending mints a link + sends a mail per account; an unbounded batch could
 * exhaust the SMTP / Auth quota and get the project throttled. The bulk action
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
 */
export function resendCallableOptions() {
  return {
    region: "us-central1" as const,
    maxInstances: 10,
    secrets: [emailPass],
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
    : `the function's runtime service account is missing the role; the ` +
      `function should be pinned to ${RESEND_SERVICE_ACCOUNT} (the Admin SDK ` +
      `account) via the serviceAccount deploy option`;
  return {
    code: (e?.code ?? "insufficient-permission").toString(),
    message:
      `Auth Admin call rejected: the credential has insufficient permission. ` +
      `Identity: ${identity} (source: ${cred.source}). ` +
      `Grant ${REQUIRED_AUTH_ADMIN_ROLE} to this service account. ` +
      `Likely root cause: ${rootCause}.`,
    missingRole: REQUIRED_AUTH_ADMIN_ROLE,
    serviceAccount: cred.serviceAccount ?? runtimeServiceAccount ?? null,
    credentialSource: cred.source,
    explicitCredential: cred.explicitCredential,
    credentialClass: cred.credentialClass,
    cloudRunService: cred.cloudRunService ?? null,
  };
}

/** Builds the verification email body for a minted link. */
export function buildVerificationEmailBody(
  email: string,
  link: string
): string {
  return [
    "Welcome to JagSpoor!",
    "",
    "Please confirm your email address to finish setting up your account.",
    "Open the link below in your browser to verify:",
    "",
    link,
    "",
    `This link was sent to ${email}. If you did not request it, you can`,
    "safely ignore this message.",
    "",
    "— The JagSpoor Team",
  ].join("\n");
}

/**
 * Resends the verification email to a SINGLE account.
 *
 * Admin-only. Mints a fresh Firebase Auth verification link and emails it from
 * the support mailbox; records the outcome on `users/{uid}`.
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
    // Sequential (not Promise.all) so the batch cannot open BULK_LIMIT
    // simultaneous SMTP connections — a burst is the fastest way to trip a
    // provider's rate limit.
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
    const diagnostic = isInsufficientPermissionError(err)
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

  // Mint a fresh verification link (this is the part that needs the Admin SDK).
  let link = "";
  try {
    link = await auth().generateEmailVerificationLink(email);
  } catch (err) {
    const reason = `link generation failed: ${describe(err)}`;
    const diagnostic = isInsufficientPermissionError(err)
      ? await diagnosticFor(err)
      : undefined;
    if (diagnostic) {
      logger.error("resendOne: generateEmailVerificationLink DENIED (IAM)", {
        uid,
        diagnostic,
      });
    } else {
      logger.error("resendOne: generateEmailVerificationLink failed", {
        uid,
        reason,
      });
    }
    await recordOutcome(uid, { sent: false, error: reason });
    return { uid, email, delivered: false, linkGenerated: false, reason, diagnostic };
  }

  // Deliver the minted link from the support mailbox.
  const send: SendResult = await sendSupportEmail({
    kind: EmailNotificationKind.NewUser,
    detail: `Verify your email — ${email}`,
    body: buildVerificationEmailBody(email, link),
    to: email,
  });

  if (send.sent) {
    await recordOutcome(uid, { sent: true });
    logger.info("resendOne: verification email sent", { uid, email });
    return { uid, email, delivered: true, linkGenerated: true };
  }

  // The link was minted but the mail was not sent (SMTP not configured /
  // failed). Record the failure with the send reason.
  const reason = send.reason ?? "email delivery failed";
  await recordOutcome(uid, { sent: false, error: reason });
  logger.warn("resendOne: link minted but not delivered", {
    uid,
    email,
    reason,
  });
  return {
    uid,
    email,
    delivered: false,
    linkGenerated: true,
    reason,
  };
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
