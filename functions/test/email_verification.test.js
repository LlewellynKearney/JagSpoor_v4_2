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
const evFirebase = require("../lib/firebase.js");
const audit = require("../lib/identify_missed_verification_users.js");

const SRC = path.resolve(__dirname, "..", "src");

function read(p) {
  return fs.readFileSync(p, "utf8");
}

/** Strips line + block comments so source assertions inspect real code only. */
function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
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

test("the resend delivers via Firebase Auth's built-in sender (accounts:sendOobCode)", () => {
  const src = stripComments(read(path.join(SRC, "email_verification.ts")));
  // The admin sendOobCode endpoint is the built-in sender.
  assert.ok(
    src.includes("/accounts:sendOobCode"),
    "must call the admin accounts:sendOobCode endpoint"
  );
  assert.match(src, /requestType:\s*"VERIFY_EMAIL"/);
  // It must NOT mint-only (returnOobLink / generateEmailVerificationLink
  // suppress the send, which is the opposite of a resend).
  assert.ok(
    !/generateEmailVerificationLink/.test(src),
    "must not use the mint-only generateEmailVerificationLink"
  );
  assert.ok(!/returnOobLink/.test(src), "must not suppress the send");
});

test("the built-in sender calls the ADMIN endpoint with a Bearer token + email", () => {
  assert.equal(
    ev.sendOobCodeEndpoint("jagspoor"),
    "https://identitytoolkit.googleapis.com/v1/projects/jagspoor/accounts:sendOobCode"
  );
  assert.equal(typeof ev.sendVerificationEmailViaFirebase, "function");
  assert.equal(typeof ev.setSendOobCodeFetchForTesting, "function");
  assert.equal(typeof ev.setAccessTokenResolverForTesting, "function");
  assert.equal(typeof ev.setSendOobCodeProjectIdForTesting, "function");
  assert.equal(typeof ev.isPermissionDeniedError, "function");
});

test("sendVerificationEmailViaFirebase POSTs VERIFY_EMAIL with no idToken", async () => {
  let captured = null;
  ev.setAccessTokenResolverForTesting(async () => "sa-token");
  ev.setSendOobCodeProjectIdForTesting("jagspoor");
  ev.setSendOobCodeFetchForTesting(async (url, init) => {
    captured = { url, init };
    return { ok: true, status: 200, text: async () => "{}" };
  });
  try {
    await ev.sendVerificationEmailViaFirebase("hunter@example.com");
  } finally {
    ev.setSendOobCodeFetchForTesting(null);
    ev.setAccessTokenResolverForTesting(null);
    ev.setSendOobCodeProjectIdForTesting(null);
  }
  assert.ok(captured, "the endpoint must be called");
  assert.equal(captured.init.method, "POST");
  assert.equal(captured.init.headers.Authorization, "Bearer sa-token");
  assert.equal(captured.init.headers["Content-Type"], "application/json");
  const body = JSON.parse(captured.init.body);
  assert.equal(body.requestType, "VERIFY_EMAIL");
  assert.equal(body.email, "hunter@example.com");
  // An admin send carries NO idToken (that is the whole point).
  assert.ok(!("idToken" in body), "the admin send must not send an idToken");
  assert.equal(captured.url, ev.sendOobCodeEndpoint("jagspoor"));
});

test("sendVerificationEmailViaFirebase throws a PERMISSION_DENIED on a 403", async () => {
  ev.setAccessTokenResolverForTesting(async () => "sa-token");
  ev.setSendOobCodeProjectIdForTesting("jagspoor");
  ev.setSendOobCodeFetchForTesting(async () => ({
    ok: false,
    status: 403,
    text: async () => "PERMISSION_DENIED",
  }));
  try {
    await assert.rejects(
      () => ev.sendVerificationEmailViaFirebase("hunter@example.com"),
      (err) => {
        assert.equal(err.status, "PERMISSION_DENIED");
        assert.equal(err.httpStatus, 403);
        return true;
      }
    );
  } finally {
    ev.setSendOobCodeFetchForTesting(null);
    ev.setAccessTokenResolverForTesting(null);
    ev.setSendOobCodeProjectIdForTesting(null);
  }
});

test("isPermissionDeniedError catches the admin sendOobCode denial shape", () => {
  assert.equal(
    ev.isPermissionDeniedError({ status: "PERMISSION_DENIED" }),
    true
  );
  assert.equal(
    ev.isPermissionDeniedError({ message: "PERMISSION_DENIED: nope" }),
    true
  );
  assert.equal(
    ev.isPermissionDeniedError({
      code: "auth/insufficient-permission",
    }),
    true
  );
  assert.equal(ev.isPermissionDeniedError({ status: "INVALID_ARGUMENT" }), false);
  assert.equal(ev.isPermissionDeniedError(null), false);
});

test("the resend module has NO nodemailer / SMTP / EMAIL_PASS surface", () => {
  const raw = read(path.join(SRC, "email_verification.ts"));
  const src = stripComments(raw);
  for (const needle of [
    "nodemailer",
    "sendSupportEmail",
    "emailPass",
    "EMAIL_PASS",
    "secrets:",
    "SMTP",
  ]) {
    assert.ok(
      !src.includes(needle),
      `email_verification.ts must not reference ${needle} (custom SMTP removed)`
    );
  }
});

test("the resend callables surface the diagnostic (failed-precondition)", () => {
  const src = read(path.join(SRC, "email_verification.ts"));
  // The single resend throws failed-precondition on a diagnostic.
  assert.ok(/result\.diagnostic/.test(src));
  assert.ok(/"failed-precondition"/.test(src));
  // The bulk surfaces it when EVERY attempt failed.
  assert.ok(/diagnostics\.length === results\.length/.test(src));
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

// ────────────────────────────────────────────────────────────────────────────
// Credential fix: the Admin SDK MUST be initialized WITHOUT an explicit
// credential so it uses the function's runtime service account (the account
// that holds Firebase Authentication Admin). Passing
// `{ credential: admin.credential.applicationDefault() }` was the bug: it
// honours a stray GOOGLE_APPLICATION_CREDENTIALS limited key and every Auth
// Admin call then fails with "insufficient permission".
// ────────────────────────────────────────────────────────────────────────────

const { firebaseSrc, initCall } = (() => {
  const src = read(path.join(SRC, "firebase.ts"));
  // The actual (non-comment) initializeApp call in the wrapper.
  const initCall = src
    .split("\n")
    .filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*"))
    .find((l) => l.includes("initializeApp("));
  return { firebaseSrc: src, initCall: initCall || "" };
})();

test("firebase.ts initializes the Admin SDK with NO explicit credential", () => {
  assert.ok(
    /admin\.initializeApp\(\)/.test(initCall),
    `initializeApp must be argument-free, got: ${initCall.trim()}`
  );
  assert.ok(
    !/credential\s*:/.test(initCall),
    "the runtime initializeApp() must not pass a credential"
  );
});

test("firebase.ts does not pass admin.credential.applicationDefault() to initializeApp", () => {
  // The string may appear ONLY inside the read-only describeCredential()
  // classifier, never as a credential passed to initializeApp.
  const initLines = firebaseSrc
    .split("\n")
    .filter((l) => l.includes("initializeApp(") && !l.trim().startsWith("*"));
  for (const l of initLines) {
    assert.ok(
      !l.includes("applicationDefault"),
      `no initializeApp() call may use applicationDefault(): ${l.trim()}`
    );
  }
});

test("every module-level admin.initializeApp() in src is argument-free", () => {
  const files = ["admin/kpis.ts", "firebase.ts", "seed_pricing.ts",
    "seed_app_version.ts", "identify_missed_verification_users.ts",
    "sync_purchases.ts"];
  for (const f of files) {
    const src = read(path.join(SRC, f));
    const calls = src
      .split("\n")
      .filter((l) => /initializeApp\(/.test(l) && !l.trim().startsWith("*"));
    for (const c of calls) {
      assert.ok(
        /initializeApp\(\s*\)/.test(c),
        `${f}: initializeApp must be argument-free -> ${c.trim()}`
      );
    }
  }
});

test("describeCredential flags an explicit credential + its source", () => {
  const withKey = ev.buildResendDiagnostic(
    { code: "auth/insufficient-permission" },
    {
      explicitCredential: true,
      credentialClass: "ServiceAccountCredential",
      source: "serviceAccountKey",
      projectId: "jagspoor",
      serviceAccount: "limited-key@jagspoor.iam.gserviceaccount.com",
    }
  );
  assert.equal(withKey.explicitCredential, true);
  assert.equal(withKey.missingRole, ev.REQUIRED_AUTH_ADMIN_ROLE);
  assert.equal(ev.REQUIRED_AUTH_ADMIN_ROLE, "roles/firebaseauth.admin");
  assert.ok(
    withKey.message.includes("limited-key@jagspoor.iam.gserviceaccount.com"),
    "the diagnostic must name the service account actually used"
  );
  assert.ok(withKey.message.includes("roles/firebaseauth.admin"));
  assert.ok(/explicit credential/i.test(withKey.message));
});

test("buildResendDiagnostic names the runtime SA when source is computeMetadata", () => {
  const d = ev.buildResendDiagnostic(
    { code: "auth/insufficient-permission" },
    {
      explicitCredential: false,
      credentialClass: "ComputeEngineCredential",
      source: "computeMetadata",
      projectId: "jagspoor",
      serviceAccount: null,
    }
  );
  assert.equal(d.explicitCredential, false);
  assert.ok(/runtime service account/i.test(d.message));
  assert.ok(/missing the role/i.test(d.message));
});

test("isInsufficientPermissionError matches the Admin SDK error shape", () => {
  assert.equal(
    ev.isInsufficientPermissionError({
      code: "auth/insufficient-permission",
      message:
        "Credential implementation provided to initializeApp() via the " +
        '"credential" property has insufficient permission to access the ' +
        "requested resource.",
    }),
    true
  );
  assert.equal(ev.isInsufficientPermissionError({ code: "auth/user-not-found" }), false);
  assert.equal(ev.isInsufficientPermissionError(null), false);
  assert.equal(ev.isInsufficientPermissionError("nope"), false);
});

test("the resend callables surface the diagnostic (failed-precondition)", () => {
  const src = read(path.join(SRC, "email_verification.ts"));
  // The single resend throws failed-precondition on a diagnostic.
  assert.ok(/result\.diagnostic/.test(src));
  assert.ok(/"failed-precondition"/.test(src));
  // The bulk surfaces it when EVERY attempt failed.
  assert.ok(/diagnostics\.length === results\.length/.test(src));
});

// ────────────────────────────────────────────────────────────────────────────
// Both resend functions MUST run as the Admin SDK service account.
//
// The singular function was left on the project's default compute account
// (`<project-number>-compute@developer.gserviceaccount.com`) while the bulk
// one was re-pointed at `firebase-adminsdk-fbsvc@…` by hand, so the two drifted
// apart and only the bulk path could call the Auth Admin API. Pinning BOTH via
// the `serviceAccount` deploy option (one shared options object) makes the
// divergence impossible.
// ────────────────────────────────────────────────────────────────────────────

test("RESEND_SERVICE_ACCOUNT is the Admin SDK account", () => {
  assert.equal(
    ev.RESEND_SERVICE_ACCOUNT,
    "firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com"
  );
});

test("the shared resend options pin the Admin SDK service account", () => {
  const opts = ev.resendCallableOptions();
  assert.equal(opts.serviceAccount, ev.RESEND_SERVICE_ACCOUNT);
  assert.equal(opts.region, "us-central1");
  // The custom SMTP secret is NO LONGER mounted — delivery goes through the
  // Firebase Auth built-in sender, which needs no SMTP credential.
  assert.equal(
    opts.secrets,
    undefined,
    "the resend must not mount EMAIL_PASS (SMTP removed)"
  );
});

test("BOTH compiled resend callables run as the SAME pinned service account", () => {
  // The compiled endpoint is the source of truth the CLI deploys from — assert
  // against it directly (not just the source text) so a drift cannot slip
  // through.
  const one = ev.resendVerificationEmail.__endpoint;
  const bulk = ev.resendVerificationEmailsBulk.__endpoint;
  assert.equal(
    one.serviceAccountEmail,
    "firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com"
  );
  assert.equal(
    bulk.serviceAccountEmail,
    "firebase-adminsdk-fbsvc@jagspoor.iam.gserviceaccount.com"
  );
  // The two must be IDENTICAL — this is the anti-drift contract.
  assert.equal(one.serviceAccountEmail, bulk.serviceAccountEmail);
  assert.equal(one.serviceAccountEmail, ev.RESEND_SERVICE_ACCOUNT);
  // Neither may run as the default compute account.
  for (const ep of [one, bulk]) {
    assert.ok(
      !/-compute@developer\.gserviceaccount\.com$/.test(
        ep.serviceAccountEmail ?? ""
      ),
      `must not run as the compute default: ${ep.serviceAccountEmail}`
    );
  }
});

test("both callables declare the serviceAccount option (no drift possible)", () => {
  const src = read(path.join(SRC, "email_verification.ts"));
  // The two onCall() calls share ONE options factory, so they cannot differ.
  const usesSharedOptions =
    (src.match(/onCall\(\s*\n?\s*resendCallableOptions\(\)/g) || []).length;
  assert.equal(
    usesSharedOptions,
    2,
    "both callables must use the shared resendCallableOptions()"
  );
  // No inline options object survives (the old, drift-prone shape).
  assert.ok(!/onCall\(\s*\n?\s*\{\s*region:/.test(src));
});

// ────────────────────────────────────────────────────────────────────────────
// The diagnostic must NAME the runtime service account, resolved from the
// metadata server / env — not the "(runtime service account — resolve via
// Cloud Run console)" placeholder.
// ────────────────────────────────────────────────────────────────────────────

test("buildResendDiagnostic names the resolved runtime SA (no placeholder)", () => {
  const d = ev.buildResendDiagnostic(
    { code: "auth/insufficient-permission" },
    {
      explicitCredential: false,
      credentialClass: "ComputeEngineCredential",
      source: "computeMetadata",
      projectId: "jagspoor",
      serviceAccount: null,
      cloudRunService: "resendverificationemail",
    },
    "475471855344-compute@developer.gserviceaccount.com"
  );
  assert.ok(
    d.message.includes("475471855344-compute@developer.gserviceaccount.com"),
    "the diagnostic must name the exact runtime SA"
  );
  assert.ok(
    !/resolve via Cloud Run console/.test(d.message),
    "the placeholder must be gone when the SA is resolvable"
  );
  assert.equal(d.serviceAccount, "475471855344-compute@developer.gserviceaccount.com");
  assert.equal(d.cloudRunService, "resendverificationemail");
});

test("buildResendDiagnostic still explains the pinned-SDK account on failure", () => {
  const d = ev.buildResendDiagnostic(
    { code: "auth/insufficient-permission" },
    {
      explicitCredential: false,
      credentialClass: "ComputeEngineCredential",
      source: "computeMetadata",
      projectId: "jagspoor",
      serviceAccount: null,
    }
  );
  // No runtime SA supplied -> the placeholder remains as a last resort.
  assert.ok(/runtime service account/i.test(d.message));
  assert.ok(/firebase-adminsdk-fbsvc@jagspoor\.iam\.gserviceaccount\.com/.test(d.message));
});

test("resolveRuntimeServiceAccountEmail reads env first, then the metadata path", () => {
  const src = read(path.join(SRC, "firebase.ts"));
  assert.ok(src.includes("FUNCTION_IDENTITY"), "1st-gen identity env");
  assert.ok(src.includes("K_SERVICE"), "Cloud Run service name");
  assert.ok(
    src.includes("instance/service-accounts/default/email"),
    "metadata server email path"
  );
  assert.ok(src.includes("Metadata-Flavor"), "metadata header required");
});

test("resolveRuntimeServiceAccountEmail returns FUNCTION_IDENTITY when set", async () => {
  const prev = process.env.FUNCTION_IDENTITY;
  process.env.FUNCTION_IDENTITY = "runtime-sa@jagspoor.iam.gserviceaccount.com";
  try {
    const resolved = await evFirebase.resolveRuntimeServiceAccountEmail();
    assert.equal(resolved, "runtime-sa@jagspoor.iam.gserviceaccount.com");
  } finally {
    if (prev === undefined) delete process.env.FUNCTION_IDENTITY;
    else process.env.FUNCTION_IDENTITY = prev;
  }
});
