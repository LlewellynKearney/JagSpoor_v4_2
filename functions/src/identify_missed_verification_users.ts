/**
 * One-off audit: identify accounts that MISSED their verification email.
 *
 * ## What it does
 *
 * Lists every `users/{uid}` document where the account has NOT verified its
 * email AND has no confirmed verification send on record — i.e. the accounts
 * the Admin Portal V2 "Resend to All Unverified" action should target. It
 * writes a CSV:
 *
 *   Email, Created Date, Name, Role, emailVerified, verificationEmailSent
 *
 * ## What it does NOT do
 *
 * **It never sends an email.** This script only READS Firestore and writes a
 * local CSV. Resending is performed from the Admin Portal V2 UI (Users tab →
 * Email Verification card), which calls the admin-only
 * `resendVerificationEmail` / `resendVerificationEmailsBulk` Cloud Functions.
 * Keeping the listing and the sending separate means this script can be run
 * freely without any risk of a mass send.
 *
 * ## Why an Auth cross-check is included
 *
 * The authoritative `emailVerified` flag lives on the Firebase Auth user, not
 * on `users/{uid}` (the app mirrors it, but legacy / never-signed-in-since
 * accounts may have no mirror). The script cross-references the Auth user list
 * so the CSV reflects the TRUE verified state, and additionally flags accounts
 * that are unverified in Auth but never recorded a send.
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
 *   node lib/identify_missed_verification_users.js            # -> stdout summary + CSV
 *   node lib/identify_missed_verification_users.js --out /tmp/missed.csv
 *
 * No confirmation guard is needed because the script performs READ-ONLY
 * operations plus a local file write.
 */

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { writeFileSync } from "node:fs";

/** Collection holding the user profiles. */
export const USERS_COLLECTION = "users";

/** The `users/{uid}` audit-trail fields (mirror the Flutter service). */
export const VERIFICATION_SENT_FIELD = "verificationEmailSent";
export const VERIFICATION_LAST_ERROR_FIELD = "verificationEmailLastError";

/** The CSV header row. */
export const CSV_HEADER =
  "Email, Created Date, Name, Role, emailVerified, verificationEmailSent";

/** A row of the audit output. */
export interface MissedUserRow {
  email: string;
  createdDate: string;
  name: string;
  role: string;
  emailVerified: boolean;
  verificationEmailSent: boolean;
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

/** Whether a `users/{uid}` document represents a missed verification email. */
export function isMissedVerification(
  data: Record<string, unknown>,
  authEmailVerified: boolean | null
): boolean {
  // Prefer the Auth flag (authoritative); fall back to the Firestore mirror.
  const verified =
    authEmailVerified ?? (data.emailVerified === true);
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
    emailVerified: authEmailVerified ?? (data.emailVerified === true),
    verificationEmailSent: data[VERIFICATION_SENT_FIELD] === true,
  };
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
 * and returns the missed-verification rows.
 */
export async function collectMissedUsers(): Promise<MissedUserRow[]> {
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
  return rows;
}

async function main(): Promise<void> {
  initializeApp();
  const outIndex = process.argv.indexOf("--out");
  const outPath = outIndex >= 0 ? process.argv[outIndex + 1] : "";

  const rows = await collectMissedUsers();
  const csv = buildCsv(rows);

  console.log(
    `\nMissed verification emails: ${rows.length} account(s).\n` +
      `(emailVerified == false AND no successful verification send on record)\n`
  );
  console.log(csv);

  if (outPath) {
    writeFileSync(outPath, csv, "utf8");
    console.log(`\nCSV written to ${outPath}`);
  }
}

// Run only when invoked directly (not when imported by a test).
if (require.main === module) {
  main().catch((err) => {
    console.error("identify_missed_verification_users failed:", err);
    process.exit(1);
  });
}
