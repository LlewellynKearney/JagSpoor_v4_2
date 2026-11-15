/**
 * One-off audit: identify accounts that need their verification email.
 *
 * ## The two buckets (why a single "unverified" count over-counts)
 *
 * A raw `emailVerified == false AND verificationEmailSent != true` query counts
 * every account that never clicked the link — which includes people who are
 * happily USING the app. In JagSpoor **role selection does not require a
 * verified email**, so an account with a role demonstrably got in: it received
 * the email (or bypassed the gate) and simply never clicked. Those accounts
 * must NOT be bulk re-sent to (that would spam active users) — they get a
 * gentle REMINDER at most.
 *
 * The audit therefore splits the unverified set into two buckets by role:
 *
 *   1. UNVERIFIED WITH ROLE — `emailVerified == false`, role is hunter /
 *      outfitter / admin (anything non-blank). Label: "Unverified but active —
 *      received email, never clicked. Do NOT bulk resend, send a reminder
 *      only." -> `unverified-with-role.csv`
 *
 *   2. UNVERIFIED NO ROLE — `emailVerified == false`, role is blank / none /
 *      unassigned / missing. Label: "Never completed signup — likely never got
 *      the email. These are the resend targets." -> `missed-no-role.csv`
 *
 * Both buckets are subsets of the raw unverified set (bucket1 + bucket2 == the
 * old single count), so no account is lost — they are just routed to the right
 * action.
 *
 * ## What it does NOT do
 *
 * **It never sends an email.** This script only READS Firestore + Auth and
 * writes local CSVs. Sending is performed from the Admin Portal V2 UI (Users
 * tab -> Email Verification card), which calls the admin-only
 * `resendVerificationEmail` / `resendVerificationEmailsBulk` Cloud Functions.
 * Keeping listing and sending separate means this script can be run freely
 * without any risk of a mass send.
 *
 * ## Why an Auth cross-check is included
 *
 * The authoritative `emailVerified` flag lives on the Firebase Auth user, not
 * on `users/{uid}` (the app mirrors it, but legacy accounts may have no
 * mirror). The script cross-references the Auth user list so the CSV reflects
 * the TRUE verified state.
 *
 * This module is intentionally NOT exported from `src/index.ts`: it is a
 * standalone operator script, not a deployed Cloud Function.
 *
 * Run it (requires a credentialed environment — Application Default
 * Credentials or GOOGLE_APPLICATION_CREDENTIALS pointing at a service account
 * with the Firebase Admin / `firebaseauth.users.get` + `clouddatastore.user`
 * roles):
 *
 *   cd functions
 *   npm run build
 *   node lib/identify_missed_verification_users.js                 # -> stdout
 *   node lib/identify_missed_verification_users.js --out-dir /tmp  # -> 2 CSVs
 *
 * Outputs (default directory `./`):
 *   missed-no-role.csv        — bucket 2 (the resend targets)
 *   unverified-with-role.csv  — bucket 1 (reminder only)
 *
 * No confirmation guard is needed because the script performs READ-ONLY
 * operations plus local file writes.
 */

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/** Collection holding the user profiles. */
export const USERS_COLLECTION = "users";

/** The `users/{uid}` audit-trail fields (mirror the Flutter service). */
export const VERIFICATION_SENT_FIELD = "verificationEmailSent";
export const VERIFICATION_LAST_ERROR_FIELD = "verificationEmailLastError";

/** Role values that mean "no operational role was selected yet". */
export const NO_ROLE_VALUES = ["", "none", "unassigned", "unknown"];

/** The CSV header row (both buckets share it). */
export const CSV_HEADER =
  "Email, Created Date, Name, Role, emailVerified, verificationEmailSent";

/** Output file names for the two buckets. */
export const NO_ROLE_CSV_FILENAME = "missed-no-role.csv";
export const WITH_ROLE_CSV_FILENAME = "unverified-with-role.csv";

/** Operator-facing bucket labels. */
export const NO_ROLE_LABEL =
  "Never completed signup — likely never got email. These are the resend targets.";
export const WITH_ROLE_LABEL =
  "Unverified but active — received email, never clicked. Do NOT bulk resend, send a reminder only.";

/** A row of the audit output. */
export interface MissedUserRow {
  email: string;
  createdDate: string;
  name: string;
  role: string;
  emailVerified: boolean;
  verificationEmailSent: boolean;
}

/** The two buckets the unverified set is split into. */
export interface MissedUserBuckets {
  /** Bucket 2 — no role; the resend targets. */
  noRole: MissedUserRow[];
  /** Bucket 1 — has a role; reminder only. */
  withRole: MissedUserRow[];
}

/** RFC 4180 CSV escaping. */
export function csvEscape(value: string): string {
  const v = (value ?? "").toString();
  if (/[",\n\r]/.test(v)) {
    return `"${v.replace(/"/g, '""')}"`;
  }
  return v;
}

/** Formats a Firestore timestamp / Date / ISO string as `YYYY-MM-DD`. */
export function formatDate(value: unknown): string {
  if (!value) return "";
  let date: Date | null = null;
  if (value instanceof Date) {
    date = value;
  } else if (typeof value === "object" && value !== null) {
    const v = value as { toDate?: () => Date };
    if (typeof v.toDate === "function") date = v.toDate();
  } else if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) date = parsed;
  }
  if (!date) return "";
  const y = date.getUTCFullYear();
  const m = `${date.getUTCMonth() + 1}`.padStart(2, "0");
  const d = `${date.getUTCDate()}`.padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Composes the display name from first/last or the legacy `fullName`. */
export function resolveName(data: Record<string, unknown>): string {
  const first = (data.firstName ?? data.first_name ?? "").toString().trim();
  const last = (
    data.lastName ??
    data.last_name ??
    data.surname ??
    ""
  ).toString().trim();
  const composed = [first, last].filter((p) => p).join(" ").trim();
  if (composed) return composed;
  return (data.fullName ?? data.full_name ?? data.name ?? "").toString().trim();
}

/**
 * Whether a `users/{uid}.role` value counts as a REAL (operational) role.
 * Blank / `none` / `unassigned` / `unknown` are treated as no role — those
 * accounts never finished role selection.
 */
export function hasRole(role: unknown): boolean {
  const r = (role ?? "").toString().trim().toLowerCase();
  return !NO_ROLE_VALUES.includes(r);
}

/**
 * Whether a `users/{uid}` document represents an unverified account with no
 * confirmed send on record (the raw "missed verification" set).
 */
export function isMissedVerification(
  data: Record<string, unknown>,
  authEmailVerified: boolean | null
): boolean {
  // Prefer the Auth flag (authoritative); fall back to the Firestore mirror.
  const verified = authEmailVerified ?? data.emailVerified === true;
  const sent = data[VERIFICATION_SENT_FIELD] === true;
  return !verified && !sent;
}

/** Builds one CSV row from a `users/{uid}` document + its Auth verified flag. */
export function toMissedRow(
  data: Record<string, unknown>,
  authEmailVerified: boolean | null
): MissedUserRow {
  return {
    email: (data.email ?? "").toString().trim().toLowerCase(),
    createdDate: formatDate(data.createdAt ?? data.created_at),
    name: resolveName(data),
    role: (data.role ?? "").toString().trim(),
    emailVerified: authEmailVerified ?? data.emailVerified === true,
    verificationEmailSent: data[VERIFICATION_SENT_FIELD] === true,
  };
}

/** Splits the raw unverified rows into the two role-based buckets. */
export function splitByRole(rows: MissedUserRow[]): MissedUserBuckets {
  const noRole: MissedUserRow[] = [];
  const withRole: MissedUserRow[] = [];
  for (const r of rows) {
    if (hasRole(r.role)) {
      withRole.push(r);
    } else {
      noRole.push(r);
    }
  }
  return { noRole, withRole };
}

/** Renders the CSV document (header + one line per row). */
export function buildCsv(rows: MissedUserRow[]): string {
  const lines = [CSV_HEADER];
  for (const r of rows) {
    lines.push(
      [
        csvEscape(r.email),
        csvEscape(r.createdDate),
        csvEscape(r.name),
        csvEscape(r.role),
        r.emailVerified ? "true" : "false",
        r.verificationEmailSent ? "true" : "false",
      ].join(", ")
    );
  }
  return lines.join("\n");
}

/**
 * Reads every `users/{uid}` document, cross-references the Auth verified flag,
 * and returns the unverified set split into the two role buckets.
 */
export async function collectMissedUsers(): Promise<MissedUserBuckets> {
  const db = getFirestore();
  const rows: MissedUserRow[] = [];

  const snap = await db.collection(USERS_COLLECTION).get();
  for (const doc of snap.docs) {
    const data = doc.data() as Record<string, unknown>;
    let authVerified: boolean | null = null;
    try {
      const user = await getAuth().getUser(doc.id);
      authVerified = user.emailVerified;
    } catch {
      // No Auth record (deleted / never created) — rely on the mirror.
      authVerified = null;
    }
    if (isMissedVerification(data, authVerified)) {
      rows.push(toMissedRow(data, authVerified));
    }
  }
  // Stable, useful ordering: newest first.
  rows.sort((a, b) => (a.createdDate < b.createdDate ? 1 : -1));
  return splitByRole(rows);
}

async function main(): Promise<void> {
  initializeApp();
  const dirIndex = process.argv.indexOf("--out-dir");
  const outDir = dirIndex >= 0 ? process.argv[dirIndex + 1] : ".";

  const { noRole, withRole } = await collectMissedUsers();
  const total = noRole.length + withRole.length;

  console.log(
    `\nUnverified accounts: ${total} total\n` +
      `  Bucket 1 — UNVERIFIED WITH ROLE:  ${withRole.length}\n` +
      `    ${WITH_ROLE_LABEL}\n` +
      `  Bucket 2 — UNVERIFIED NO ROLE:    ${noRole.length}\n` +
      `    ${NO_ROLE_LABEL}\n`
  );
  console.log(
    `(predicate: emailVerified != true AND verificationEmailSent != true)\n`
  );

  mkdirSync(outDir, { recursive: true });
  const noRolePath = join(outDir, NO_ROLE_CSV_FILENAME);
  const withRolePath = join(outDir, WITH_ROLE_CSV_FILENAME);
  writeFileSync(noRolePath, buildCsv(noRole), "utf8");
  writeFileSync(withRolePath, buildCsv(withRole), "utf8");
  console.log(`CSV written: ${noRolePath} (${noRole.length} rows)`);
  console.log(`CSV written: ${withRolePath} (${withRole.length} rows)`);
}

// Run only when invoked directly (not when imported by a test).
if (require.main === module) {
  main().catch((err) => {
    console.error("identify_missed_verification_users failed:", err);
    process.exit(1);
  });
}
