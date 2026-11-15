import { logger } from "firebase-functions/v2";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { auth, firestore } from "./firebase";
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
  { region: "us-central1", maxInstances: 10, secrets: [emailPass] },
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
  { region: "us-central1", maxInstances: 10, secrets: [emailPass] },
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
    logger.warn("resendOne: user lookup failed", { uid, reason });
    await recordOutcome(uid, { sent: false, error: reason });
    return { uid, email, delivered: false, linkGenerated: false, reason };
  }

  // Mint a fresh verification link (this is the part that needs the Admin SDK).
  let link = "";
  try {
    link = await auth().generateEmailVerificationLink(email);
  } catch (err) {
    const reason = `link generation failed: ${describe(err)}`;
    logger.error("resendOne: generateEmailVerificationLink failed", {
      uid,
      reason,
    });
    await recordOutcome(uid, { sent: false, error: reason });
    return { uid, email, delivered: false, linkGenerated: false, reason };
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
