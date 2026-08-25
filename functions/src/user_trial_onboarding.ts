import { logger } from "firebase-functions/v2";
import * as functionsV1 from "firebase-functions/v1";
import { FieldValue } from "firebase-admin/firestore";
import * as nodemailer from "nodemailer";
import { firestore } from "./firebase";

// ────────────────────────────────────────────────────────────────────────────
// Automated 30-Day Free Trial & Welcome Email Flow
//
// A Firebase Auth `onCreate` trigger fires for every newly registered user
// (email/password AND Google sign-in alike). The handler:
//   1. Initializes the user's Firestore profile (`users/{uid}`) to
//      `subscriptionStatus: 'trialing'` with `trialEndsAt` exactly 30 days in
//      the future and `requiresPayment: false` (merge-write; an existing
//      non-trial subscription state is never clobbered).
//   2. Guards the trial with a **fail-closed device-level abuse check**:
//      the client stamps a hardware-backed `deviceFingerprint` (SHA-256 of
//      the Android ID / iOS identifierForVendor) on `users/{uid}` at
//      account-creation time; when another user doc already carries the same
//      fingerprint, the trial is BLOCKED (`subscriptionStatus: 'blocked'`,
//      `requiresPayment: true`, `trialBlockedReason`) so a malicious user
//      cannot spin up infinite trial accounts on the same physical device.
//      A missing fingerprint or a check error blocks as well (fail-closed).
//   3. Dispatches a welcome email over SMTP (Afrihost relay) informing the
//      user of the 30-day free trial period and its expiration date.
// ────────────────────────────────────────────────────────────────────────────

/** Free trial length, in days. */
export const TRIAL_PERIOD_DAYS = 30;

/** Free trial length, in milliseconds (exactly 30 days). */
export const TRIAL_PERIOD_MS = TRIAL_PERIOD_DAYS * 24 * 60 * 60 * 1000;

/**
 * Computes the trial expiration timestamp: exactly 30 days after `startedAt`.
 */
export function trialEndsAtFrom(startedAt: Date): Date {
  return new Date(startedAt.getTime() + TRIAL_PERIOD_MS);
}

// ── Device-level trial abuse prevention (fail-closed) ────────────────────────

/**
 * How long the trigger polls the `users/{uid}` doc for the client's
 * `deviceFingerprint` stamp before treating it as unavailable (fail-closed
 * block). The client writes the fingerprint immediately after
 * `createUserWithEmailAndPassword` / Google sign-in, so a short poll bridges
 * the auth onCreate / client write race window.
 */
export const FINGERPRINT_POLL_TIMEOUT_MS = 15000;

/** Poll interval between doc reads while awaiting the fingerprint stamp. */
export const FINGERPRINT_POLL_INTERVAL_MS = 1000;

/** Trial block reasons recorded on the user's profile. */
export const TRIAL_BLOCK_REASON_DUPLICATE = "duplicate_device_fingerprint";
export const TRIAL_BLOCK_REASON_UNSET = "fingerprint_unavailable";
export const TRIAL_BLOCK_REASON_ERROR = "duplicate_check_error";

const sleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * Polls the user's profile doc until the client's `deviceFingerprint` stamp
 * lands, up to `timeoutMs`. Returns the fingerprint, or an empty string when
 * the stamp never arrived (fail-closed block).
 */
export async function resolveDeviceFingerprint(
  readDoc: () => Promise<unknown>,
  options?: { timeoutMs?: number; intervalMs?: number }
): Promise<string> {
  const timeout = options?.timeoutMs ?? FINGERPRINT_POLL_TIMEOUT_MS;
  const interval = options?.intervalMs ?? FINGERPRINT_POLL_INTERVAL_MS;
  const startedAt = Date.now();
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snapshot: any = await readDoc();
    const data: any = snapshot?.data?.() ?? {};
    const fingerprint = (data["deviceFingerprint"] ?? "").toString().trim();
    if (fingerprint) return fingerprint;
    if (Date.now() - startedAt >= timeout) return "";
    await sleep(interval);
  }
}

/**
 * Whether ANY other user doc already carries this device fingerprint — the
 * same physical device already claimed (or attempted) its one free trial.
 * Any match is sufficient: a previous user on the device always went through
 * account creation and the trial check, so the device has exhausted its
 * single free trial.
 */
export async function otherUserHasDeviceFingerprint(
  usersRef: any,
  fingerprint: string,
  excludeUid: string
): Promise<boolean> {
  const snap = await usersRef
    .where("deviceFingerprint", "==", fingerprint)
    .limit(500)
    .get();
  return snap.docs.some((doc: any) => doc.id !== excludeUid);
}

// ── SMTP (Afrihost) configuration ────────────────────────────────────────────

export interface SmtpConfig {
  host: string;
  port: number;
  secure: boolean;
  user: string;
  pass: string;
  from: string;
  fromName: string;
}

/**
 * Resolves the SMTP relay configuration from the environment.
 *
 * Defaults target the Afrihost relay (smtp.afrihost.co.za:587, STARTTLS).
 * Returns null when no credentials are configured so callers can skip the
 * email gracefully (dev / emulator environments).
 */
export function smtpConfigFromEnv(
  env: NodeJS.ProcessEnv = process.env
): SmtpConfig | null {
  const user = (env.SMTP_USER ?? "").trim();
  const pass = env.SMTP_PASS ?? "";
  if (!user || !pass) return null;
  return {
    host: (env.SMTP_HOST ?? "").trim() || "smtp.afrihost.co.za",
    port: parseInt(env.SMTP_PORT ?? "", 10) || 587,
    secure: (env.SMTP_SECURE ?? "").trim().toLowerCase() === "true",
    user,
    pass,
    from: (env.SMTP_FROM ?? "").trim() || "support@jag-spoor.co.za",
    fromName: (env.SMTP_FROM_NAME ?? "").trim() || "JagSpoor",
  };
}

// ── Welcome email content ────────────────────────────────────────────────────

/** Formats a date as "25 September 2026" (locale-independent). */
export function formatTrialDate(date: Date): string {
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  return `${date.getUTCDate()} ${months[date.getUTCMonth()]} ${date.getUTCFullYear()}`;
}

export interface WelcomeEmail {
  subject: string;
  text: string;
  html: string;
}

/**
 * Builds the welcome email informing the user of their 30-day free trial
 * period and its expiration date.
 */
export function buildWelcomeEmail(options: {
  displayName: string;
  trialEndsAt: Date;
}): WelcomeEmail {
  const name = options.displayName || "Hunter";
  const expiry = formatTrialDate(options.trialEndsAt);
  const subject = "Welcome to JagSpoor — Your 30-Day Free Trial Is Active!";
  const text = [
    `Hi ${name},`,
    "",
    "Welcome to JagSpoor!",
    "",
    `Your ${TRIAL_PERIOD_DAYS}-day free trial is now active. You have full ` +
      "access to every JagSpoor feature for the duration of the trial — no " +
      "payment is required.",
    "",
    `Your free trial expires on ${expiry}.`,
    "",
    "To keep your access after the trial, subscribe before the expiration " +
      "date from the Subscription screen in the app.",
    "",
    "Tight groupings,",
    "The JagSpoor Team",
    "support@jag-spoor.co.za",
  ].join("\n");
  const html = `
  <div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#212121">
    <h1 style="color:#795548;margin-bottom:4px">Welcome to JagSpoor</h1>
    <p style="font-size:16px">Hi ${name},</p>
    <p style="font-size:16px">
      Your <strong>${TRIAL_PERIOD_DAYS}-day free trial</strong> is now active.
      You have full access to every JagSpoor feature for the duration of the
      trial &mdash; no payment is required.
    </p>
    <p style="font-size:16px;background:#F4EFEA;border:1px solid #D6C8BC;border-radius:8px;padding:12px 16px">
      Your free trial expires on <strong>${expiry}</strong>.
    </p>
    <p style="font-size:16px">
      To keep your access after the trial, subscribe before the expiration
      date from the Subscription screen in the app.
    </p>
    <p style="font-size:16px">Tight groupings,<br/>The JagSpoor Team</p>
    <p style="font-size:12px;color:#5D4037">
      Questions? Contact <a href="mailto:support@jag-spoor.co.za">support@jag-spoor.co.za</a>
    </p>
  </div>`.trim();
  return { subject, text, html };
}

/**
 * Dispatches the welcome email via the configured SMTP (Afrihost) relay.
 *
 * The transporter factory is injectable for tests; the default builds a
 * nodemailer transport from the SMTP config.
 */
export async function sendWelcomeEmail(options: {
  to: string;
  displayName: string;
  trialEndsAt: Date;
  config: SmtpConfig;
  createTransport?: (config: SmtpConfig) => nodemailer.Transporter;
}): Promise<void> {
  const buildTransport =
    options.createTransport ??
    ((config: SmtpConfig): nodemailer.Transporter =>
      nodemailer.createTransport({
        host: config.host,
        port: config.port,
        secure: config.secure,
        auth: { user: config.user, pass: config.pass },
      }));
  const transporter = buildTransport(options.config);
  const email = buildWelcomeEmail({
    displayName: options.displayName,
    trialEndsAt: options.trialEndsAt,
  });
  await transporter.sendMail({
    from: `"${options.config.fromName}" <${options.config.from}>`,
    to: options.to,
    subject: email.subject,
    text: email.text,
    html: email.html,
  });
}

// ── Firebase Auth onCreate trigger ───────────────────────────────────────────

/**
 * initializeNewUserTrial
 *
 * Firebase Authentication user-creation trigger (v1 auth provider). Fires
 * once per newly created Auth user and:
 *   1. Initializes `users/{uid}` with the 30-day free trial state
 *      (`subscriptionStatus: 'trialing'`, `trialEndsAt` = now + 30 days,
 *      `requiresPayment: false`). An already-existing non-trial
 *      `subscriptionStatus` (e.g. pre-provisioned billing state) is
 *      preserved so the trigger can never downgrade an account.
 *      The trial init is gated by a fail-closed device-level abuse check:
 *      missing fingerprint, a duplicate fingerprint on another user doc, or
 *      a check error blocks the trial (`subscriptionStatus: 'blocked'` +
 *      `trialBlockedReason` + `requiresPayment: true`).
 *   2. Sends the welcome email over the SMTP (Afrihost) relay — skipped when
 *      the trial was blocked. Email delivery is best-effort: an SMTP failure
 *      is logged and never fails the trigger.
 */
export const initializeNewUserTrial = functionsV1
  .region("us-central1")
  .auth.user()
  .onCreate(async (user) => {
    const uid = user.uid;
    const email = (user.email ?? "").trim();
    const displayName = (user.displayName ?? "").trim();
    const now = new Date();
    const trialEndsAt = trialEndsAtFrom(now);

    // 1. Initialize the 30-day free trial on the user's Firestore profile —
    //    but only after the fail-closed device-level abuse check clears.
    const userRef = firestore().collection("users").doc(uid);
    const snap = await userRef.get();
    const existingStatus = ((snap.data() ?? {})["subscriptionStatus"] ?? "")
      .toString()
      .trim();

    // Fail-closed trial-abuse check. A non-trial pre-existing status (e.g.
    // pre-provisioned billing) is preserved without the check.
    let trialBlockedReason = "";
    let trialBlockedCheckErrorDetail = "";
    if (existingStatus !== "" && existingStatus !== "trialing") {
      logger.info(
        "initializeNewUserTrial: existing subscription state preserved",
        { uid, subscriptionStatus: existingStatus }
      );
    } else {
      const fingerprint = await resolveDeviceFingerprint(
        () => userRef.get()
      );
      if (!fingerprint) {
        trialBlockedReason = TRIAL_BLOCK_REASON_UNSET;
      } else {
        try {
          const hasDuplicate = await otherUserHasDeviceFingerprint(
            firestore().collection("users"),
            fingerprint,
            uid
          );
          if (hasDuplicate) {
            trialBlockedReason = TRIAL_BLOCK_REASON_DUPLICATE;
          }
        } catch (err) {
          // Fail-closed: an unverifiable check blocks the trial rather than
          // letting a possible abuser through.
          trialBlockedReason = TRIAL_BLOCK_REASON_ERROR;
          trialBlockedCheckErrorDetail =
            err instanceof Error ? err.message : String(err);
        }
      }
    }

    if (trialBlockedReason) {
      await userRef.set(
        {
          subscriptionStatus: "blocked",
          requiresPayment: true,
          trialBlockedReason,
          subscriptionUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.warn(
        "initializeNewUserTrial: free trial blocked (device abuse check)",
        {
          uid,
          trialBlockedReason,
          checkError: trialBlockedCheckErrorDetail,
        }
      );
      // Blocked accounts get no welcome email (do not promise a trial).
      return;
    }

    if (existingStatus !== "" && existingStatus !== "trialing") {
      // Pre-existing status preserved — no trial write needed.
    } else {
      await userRef.set(
        {
          subscriptionStatus: "trialing",
          trialStartedAt: now,
          trialEndsAt,
          requiresPayment: false,
          subscriptionUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.info("initializeNewUserTrial: 30-day free trial initialized", {
        uid,
        trialEndsAt: trialEndsAt.toISOString(),
      });
    }

    // 3. Dispatch the welcome email (best-effort).
    if (!email) {
      logger.warn(
        "initializeNewUserTrial: no email on the new user record; " +
          "skipping welcome email",
        { uid }
      );
      return;
    }
    const config = smtpConfigFromEnv();
    if (!config) {
      logger.warn(
        "initializeNewUserTrial: SMTP credentials not configured; " +
          "skipping welcome email",
        { uid }
      );
      return;
    }
    try {
      await sendWelcomeEmail({
        to: email,
        displayName,
        trialEndsAt,
        config,
      });
      logger.info("initializeNewUserTrial: welcome email dispatched", {
        uid,
        smtpHost: config.host,
      });
    } catch (err) {
      logger.error("initializeNewUserTrial: welcome email failed", {
        uid,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });
