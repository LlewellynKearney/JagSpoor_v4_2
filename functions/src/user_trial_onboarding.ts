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
//   2. Dispatches a welcome email over SMTP (Afrihost relay) informing the
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
 *   2. Sends the welcome email over the SMTP (Afrihost) relay. Email
 *      delivery is best-effort: an SMTP failure is logged and never fails
 *      the trigger (the trial state has already been committed).
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

    // 1. Initialize the 30-day free trial on the user's Firestore profile.
    const userRef = firestore().collection("users").doc(uid);
    const snap = await userRef.get();
    const existingStatus = ((snap.data() ?? {})["subscriptionStatus"] ?? "")
      .toString()
      .trim();
    if (existingStatus !== "" && existingStatus !== "trialing") {
      logger.info(
        "initializeNewUserTrial: existing subscription state preserved",
        { uid, subscriptionStatus: existingStatus }
      );
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

    // 2. Dispatch the welcome email (best-effort).
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
