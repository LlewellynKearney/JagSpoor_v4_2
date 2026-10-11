import { logger } from "firebase-functions/v2";
import nodemailer, { type Transporter, type SentMessageInfo } from "nodemailer";
import type SMTPTransport from "nodemailer/lib/smtp-transport";

// ────────────────────────────────────────────────────────────────────────────
// Support email notifications
//
// Transactional notifications to the JagSpoor support inbox
// (support@jag-spoor.co.za) for two business events:
//   • a new user signs up (Auth onCreate), and
//   • a new subscription is recorded (users/{uid}/subscriptions/{subId},
//     a users/{uid} upgrade, or a top-level pricing doc).
//
// Transport is SMTP via nodemailer. Credentials are read from the Cloud
// Functions secrets / environment so nothing is hard-coded:
//
//   EMAIL_USER   — the SMTP username AND the default sender address.
//                  Defaults to support@jag-spoor.co.za.
//   EMAIL_PASS   — the SMTP password (REQUIRED to actually send).
//   EMAIL_HOST   — SMTP host. Defaults to mail.jag-spoor.co.za
//                  (set to smtp.gmail.com to switch providers later).
//   EMAIL_PORT   — SMTP port. Defaults to 465.
//   EMAIL_SECURE — "true"/"false". Defaults to true (implicit TLS on 465).
//   SUPPORT_EMAIL / EMAIL_TO — the recipient inbox. Defaults to
//                  support@jag-spoor.co.za.
//
// `SUPPORT_EMAIL` is the destination; `EMAIL_USER` doubles as the default
// sender so the two are deliberately separate knobs.
//
// Nothing here throws out of the send path: a notification failure must
// never fail the Auth / Firestore trigger that produced it. The caller
// (notifications.ts) logs and swallows.
// ────────────────────────────────────────────────────────────────────────────

/** The default support inbox / sender address. */
export const DEFAULT_SUPPORT_EMAIL = "support@jag-spoor.co.za";

/** Default SMTP host (the JagSpoor mailbox on Afrihost). */
export const DEFAULT_SMTP_HOST = "mail.jag-spoor.co.za";

/** Default SMTP port (implicit TLS). */
export const DEFAULT_SMTP_PORT = 465;

/** Default TLS mode for port 465. */
export const DEFAULT_SMTP_SECURE = true;

/** The subject prefix so support inbox rules can file these automatically. */
export const EMAIL_SUBJECT_PREFIX = "[JagSpoor]";

/** Notification event kinds (used for the subject line + tests). */
export enum EmailNotificationKind {
  NewUser = "new_user",
  NewSubscription = "new_subscription",
}

/** Resolved, immutable email configuration for one send. */
export interface EmailConfig {
  host: string;
  port: number;
  secure: boolean;
  user: string;
  pass: string;
  from: string;
  to: string;
}

/** Minimal view of the environment this module reads. */
export interface EmailEnv {
  EMAIL_USER?: string;
  EMAIL_PASS?: string;
  EMAIL_HOST?: string;
  EMAIL_PORT?: string;
  EMAIL_SECURE?: string;
  SUPPORT_EMAIL?: string;
  EMAIL_TO?: string;
}

/** Metadata for a "new user" notification. */
export interface NewUserNotification {
  uid: string;
  email: string;
  displayName?: string;
  provider: string;
  createdAt: Date;
}

/**
 * Metadata for a "new subscription" notification.
 *
 * `price` is a pre-formatted display string (e.g. "R 34.99 / month") — the
 * functions layer never does currency maths, it reports what the billing
 * record says.
 */
export interface SubscriptionNotification {
  uid: string;
  userEmail: string;
  plan: string;
  price?: string;
  source: string;
  docPath: string;
  data: Record<string, unknown>;
}

// ── Configuration resolution (pure) ──────────────────────────────────────────

function trim(value: string | undefined): string {
  return (value ?? "").toString().trim();
}

/**
 * Resolves the email configuration from an environment object. Pure and
 * side-effect free so it can be unit-tested without touching `process.env`.
 */
export function resolveEmailConfig(env: EmailEnv): EmailConfig {
  const user = trim(env.EMAIL_USER) || DEFAULT_SUPPORT_EMAIL;
  const pass = trim(env.EMAIL_PASS);
  const host = trim(env.EMAIL_HOST) || DEFAULT_SMTP_HOST;

  const rawPort = trim(env.EMAIL_PORT);
  const parsedPort = Number.parseInt(rawPort, 10);
  const port = Number.isFinite(parsedPort) && parsedPort > 0 ? parsedPort : DEFAULT_SMTP_PORT;

  const rawSecure = trim(env.EMAIL_SECURE).toLowerCase();
  const secure = rawSecure === "" ? DEFAULT_SMTP_SECURE : rawSecure !== "false";

  const to = trim(env.SUPPORT_EMAIL) || trim(env.EMAIL_TO) || DEFAULT_SUPPORT_EMAIL;

  return { host, port, secure, user, pass, from: user, to };
}

/** Reads the live configuration from `process.env`. */
export function currentEmailConfig(): EmailConfig {
  return resolveEmailConfig(process.env as EmailEnv);
}

// ── SMTP transport (lazy, memoised) ──────────────────────────────────────────

/** Builds a nodemailer transport from a resolved config. */
export function buildTransport(config: EmailConfig): Transporter<SentMessageInfo> {
  const options: SMTPTransport.Options = {
    host: config.host,
    port: config.port,
    secure: config.secure,
    auth: { user: config.user, pass: config.pass },
  };
  return nodemailer.createTransport(options);
}

/** A transport factory — injectable so tests never open a real socket. */
export type TransportFactory = (config: EmailConfig) => Transporter<SentMessageInfo>;

let transportFactory: TransportFactory = buildTransport;

/**
 * Test seam: overrides (or, with `null`, restores) the transport factory.
 * Never used in production.
 */
export function setTransportFactoryForTesting(factory: TransportFactory | null): void {
  transportFactory = factory ?? buildTransport;
}

// ── Message builders (pure) ──────────────────────────────────────────────────

/** Renders any JSON-safe value for a plain-text report line. */
function formatValue(value: unknown): string {
  if (value === null || value === undefined) return "(none)";
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "object") {
    try {
      return JSON.stringify(value);
    } catch {
      return String(value);
    }
  }
  return String(value);
}

/** Pretty-prints a document for the "full document data" section. */
export function formatDocument(data: Record<string, unknown>): string {
  try {
    return JSON.stringify(data, null, 2);
  } catch {
    return String(data);
  }
}

/** The subject line for a notification. */
export function buildSubject(kind: EmailNotificationKind, detail: string): string {
  return `${EMAIL_SUBJECT_PREFIX} ${detail}`;
}

/** Plain-text body for a new-user signup notification. */
export function buildUserSignupEmailBody(meta: NewUserNotification): string {
  const lines = [
    "A new user has signed up for JagSpoor.",
    "",
    `Email:        ${meta.email || "(none)"}`,
    `User ID:      ${meta.uid || "(none)"}`,
    `Provider:     ${meta.provider || "(unknown)"}`,
    `Display name: ${meta.displayName || "(none)"}`,
    `Created at:   ${meta.createdAt.toISOString()}`,
    "",
    "— Sent automatically by the JagSpoor Cloud Functions.",
  ];
  return lines.join("\n");
}

/** Plain-text body for a new-subscription notification. */
export function buildSubscriptionEmailBody(meta: SubscriptionNotification): string {
  const lines = [
    "A new subscription has been recorded for JagSpoor.",
    "",
    `User email: ${meta.userEmail || "(none)"}`,
    `User ID:    ${meta.uid || "(none)"}`,
    `Plan:       ${meta.plan || "(unknown)"}`,
    `Price:      ${meta.price || "(not stated)"}`,
    `Source:     ${meta.source || "(unknown)"}`,
    `Doc path:   ${meta.docPath || "(unknown)"}`,
    "",
    "Full document data:",
    formatDocument(meta.data),
    "",
    "— Sent automatically by the JagSpoor Cloud Functions.",
  ];
  return lines.join("\n");
}

// ── Sending ──────────────────────────────────────────────────────────────────

export interface SupportEmail {
  kind: EmailNotificationKind;
  detail: string;
  body: string;
  to?: string;
}

export interface SendResult {
  sent: boolean;
  /** Why the send was skipped/failed (for logging) — never thrown. */
  reason?: string;
}

/**
 * Sends one support notification. NEVER throws: a missing password, an SMTP
 * outage or a transport error is logged and reported as `{sent:false}` so the
 * originating trigger can continue.
 */
export async function sendSupportEmail(email: SupportEmail): Promise<SendResult> {
  const config = currentEmailConfig();
  if (!config.pass) {
    logger.warn("support email skipped: EMAIL_PASS is not configured", {
      kind: email.kind,
      hint: "firebase functions:secrets:set EMAIL_PASS",
    });
    return { sent: false, reason: "EMAIL_PASS not configured" };
  }

  const to = trim(email.to) || config.to;
  try {
    const transport = transportFactory(config);
    const info = await transport.sendMail({
      from: `"JagSpoor" <${config.from}>`,
      to,
      subject: buildSubject(email.kind, email.detail),
      text: email.body,
    });
    logger.info("support email sent", {
      kind: email.kind,
      to,
      messageId: info?.messageId,
    });
    return { sent: true };
  } catch (err) {
    logger.error("support email failed", {
      kind: email.kind,
      to,
      error: err instanceof Error ? err.message : String(err),
    });
    return { sent: false, reason: err instanceof Error ? err.message : String(err) };
  }
}

/**
 * Builds + sends the new-user notification in one call.
 * Convenience wrapper used by the Auth onCreate trigger.
 */
export async function notifyNewUser(meta: NewUserNotification): Promise<SendResult> {
  return sendSupportEmail({
    kind: EmailNotificationKind.NewUser,
    detail: `New user: ${meta.email || meta.uid}`,
    body: buildUserSignupEmailBody(meta),
  });
}

/**
 * Builds + sends the new-subscription notification in one call.
 * Convenience wrapper used by the subscription triggers.
 */
export async function notifyNewSubscription(
  meta: SubscriptionNotification
): Promise<SendResult> {
  return sendSupportEmail({
    kind: EmailNotificationKind.NewSubscription,
    detail: `New subscription: ${meta.userEmail || meta.uid} (${meta.plan || "unknown"})`,
    body: buildSubscriptionEmailBody(meta),
  });
}
