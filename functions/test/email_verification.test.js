"use strict";

// Tests for the email-verification resend module
// (functions/src/email_verification.ts) + the identify-missed-users audit
// script (functions/src/identify_missed_verification_users.ts).
//
// Pure helpers + structural contracts only — no Firebase emulator, no network.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "jagspoor-test";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ev = require("../lib/email_verification.js");
const audit = require("../lib/identify_missed_verification_users.js");

const SRC = path.resolve(__dirname, "..", "src");

function read(p) {
  return fs.readFileSync(p, "utf8");
}

test("the resend callables + bulk limit are exported", () => {
  assert.equal(typeof ev.resendVerificationEmail, "function");
  assert.equal(typeof ev.resendVerificationEmailsBulk, "function");
  assert.equal(ev.BULK_LIMIT, 50);
});

test("the audit-trail field names match the Flutter service", () => {
  assert.equal(ev.VERIFICATION_SENT_FIELD, "verificationEmailSent");
  assert.equal(ev.VERIFICATION_LAST_ERROR_FIELD, "verificationEmailLastError");
  assert.equal(
    ev.VERIFICATION_LAST_ATTEMPT_FIELD,
    "verificationEmailLastAttemptAt"
  );
  // And the Flutter source spells them the same way.
  const dart = read(
    path.resolve(
      SRC,
      "..",
      "..",
      "lib",
      "features",
      "auth",
      "services",
      "email_verification_service.dart"
    )
  );
  for (const f of [
    "verificationEmailSent",
    "verificationEmailLastError",
    "verificationEmailLastAttemptAt",
  ]) {
    assert.ok(dart.includes(f), `Flutter service must reference ${f}`);
  }
});

test("the verification email body carries the minted link", () => {
  const body = ev.buildVerificationEmailBody(
    "hunter@example.com",
    "https://jagspoor.firebaseapp.com/__/auth/action?oobCode=abc"
  );
  assert.ok(body.includes("https://jagspoor.firebaseapp.com/__/auth/action"));
  assert.ok(body.includes("hunter@example.com"));
  assert.ok(/verify/i.test(body));
});

test("both callables are admin-gated via isAdminRequest", () => {
  const src = read(path.join(SRC, "email_verification.ts"));
  assert.ok(src.includes("isAdminRequest"), "must use the shared admin check");
  assert.ok(src.includes('new HttpsError(\n      "permission-denied"') ||
    src.includes('"permission-denied"'));
  // The admin allow-list is re-exported for the wiring assertion.
  assert.ok(Array.isArray(ev.ADMIN_EMAIL_ALLOW_LIST));
  assert.ok(ev.ADMIN_EMAIL_ALLOW_LIST.includes("admin@jag-spoor.co.za"));
});

test("the bulk callable caps the batch at BULK_LIMIT and processes sequentially", () => {
  const src = read(path.join(SRC, "email_verification.ts"));
  assert.ok(src.includes("requested.slice(0, BULK_LIMIT)"));
  // Sequential loop (no Promise.all burst) — a burst trips SMTP rate limits.
  assert.ok(src.includes("for (const uid of batch)"));
  assert.ok(!/Promise\.all\(\s*batch/.test(src));
});

test("the resend mints a link with generateEmailVerificationLink", () => {
  const src = read(path.join(SRC, "email_verification.ts"));
  assert.ok(src.includes("generateEmailVerificationLink"));
});

test("the module is exported from index.ts (deployable)", () => {
  const index = read(path.join(SRC, "index.ts"));
  assert.ok(index.includes("resendVerificationEmail"));
  assert.ok(index.includes("resendVerificationEmailsBulk"));
});

// ── identify-missed-users audit script ──────────────────────────────────────

test("the audit CSV header matches the required columns", () => {
  assert.equal(
    audit.CSV_HEADER,
    "Email, Created Date, Name, Role, emailVerified, verificationEmailSent"
  );
});

test("isMissedVerification: unverified + no send (Auth flag authoritative)", () => {
  assert.equal(
    audit.isMissedVerification({}, false),
    true,
    "unverified, no send record"
  );
  assert.equal(
    audit.isMissedVerification({ verificationEmailSent: true }, false),
    false,
    "a successful send excludes the account"
  );
  assert.equal(
    audit.isMissedVerification({}, true),
    false,
    "verified in Auth excludes the account"
  );
  // No Auth record -> falls back to the Firestore mirror.
  assert.equal(
    audit.isMissedVerification({ emailVerified: true }, null),
    false
  );
  assert.equal(
    audit.isMissedVerification({ emailVerified: false }, null),
    true
  );
});

test("the audit script NEVER sends email (read-only)", () => {
  const raw = read(path.join(SRC, "identify_missed_verification_users.ts"));
  // Strip block + line comments so prose mentioning "resend" is ignored.
  const src = raw
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/[^\n]*/g, "");
  assert.ok(!src.includes("sendSupportEmail"), "must not send");
  assert.ok(!src.includes("generateEmailVerificationLink"), "must not mint");
  assert.ok(!src.includes("resendVerification"), "must not resend");
  // It only reads Firestore + writes the two local CSVs.
  assert.ok(src.includes("writeFileSync"));
});

test("the audit splits into the two role buckets + names the CSVs", () => {
  assert.equal(audit.NO_ROLE_CSV_FILENAME, "missed-no-role.csv");
  assert.equal(audit.WITH_ROLE_CSV_FILENAME, "unverified-with-role.csv");
  // The labels carry the required operator wording.
  assert.ok(/never completed signup/i.test(audit.NO_ROLE_LABEL));
  assert.ok(/resend target/i.test(audit.NO_ROLE_LABEL));
  assert.ok(/do not bulk resend/i.test(audit.WITH_ROLE_LABEL));
  assert.ok(/reminder only/i.test(audit.WITH_ROLE_LABEL));
});

test("hasRole: blank / none / unassigned / unknown are NO role", () => {
  for (const v of ["", "  ", "none", "NONE", "unassigned", "unknown", null]) {
    assert.equal(audit.hasRole(v), false, `"${v}" must be no role`);
  }
  for (const v of ["hunter", "Outfitter", "admin", "dual"]) {
    assert.equal(audit.hasRole(v), true, `"${v}" must be a role`);
  }
});

test("splitByRole routes accounts to the right bucket (no loss)", () => {
  const rows = [
    { role: "" },
    { role: "none" },
    { role: "hunter" },
    { role: "outfitter" },
  ].map((r, i) => ({
    email: `u${i}@example.com`,
    createdDate: "2026-11-01",
    name: "",
    role: r.role,
    emailVerified: false,
    verificationEmailSent: false,
  }));
  const { noRole, withRole } = audit.splitByRole(rows);
  assert.equal(noRole.length, 2);
  assert.equal(withRole.length, 2);
  // The two buckets partition the input — nothing is dropped.
  assert.equal(noRole.length + withRole.length, rows.length);
  assert.ok(noRole.every((r) => !audit.hasRole(r.role)));
  assert.ok(withRole.every((r) => audit.hasRole(r.role)));
});

test("buildCsv escapes commas / quotes and formats the rows", () => {
  const csv = audit.buildCsv([
    {
      email: "a@example.com",
      createdDate: "2026-11-01",
      name: 'Kearney, "Don"',
      role: "hunter",
      emailVerified: false,
      verificationEmailSent: false,
    },
  ]);
  const lines = csv.split("\n");
  assert.equal(lines[0], audit.CSV_HEADER);
  assert.ok(lines[1].includes('"Kearney, ""Don"""'));
  assert.ok(lines[1].endsWith("false, false"));
});

test("formatDate handles a Firestore Timestamp-like + a Date + a string", () => {
  const fakeTimestamp = { toDate: () => new Date(Date.UTC(2026, 10, 15)) };
  assert.equal(audit.formatDate(fakeTimestamp), "2026-11-15");
  assert.equal(audit.formatDate(new Date(Date.UTC(2026, 0, 2))), "2026-01-02");
  assert.equal(audit.formatDate("2026-03-04T00:00:00.000Z"), "2026-03-04");
  assert.equal(audit.formatDate(null), "");
});

test("resolveName prefers first+last, then the legacy fullName", () => {
  assert.equal(
    audit.resolveName({ firstName: "Don", lastName: "Kearney" }),
    "Don Kearney"
  );
  assert.equal(audit.resolveName({ fullName: "Don Kearney" }), "Don Kearney");
  assert.equal(audit.resolveName({}), "");
});
