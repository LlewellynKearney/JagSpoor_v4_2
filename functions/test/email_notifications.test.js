"use strict";

// Unit tests for the support email notification pipeline
// (functions/src/email.ts + functions/src/notifications.ts).
//
// These exercise the compiled pure helpers + the SMTP send path against an
// injected fake transport — no Firebase emulator or real socket is required.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "jagspoor-test";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const email = require("../lib/email.js");
const notifications = require("../lib/notifications.js");

const ROOT = path.resolve(__dirname, "..");

/** Strips comments so source assertions inspect real code only. */
function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
}

// ── Config resolution ────────────────────────────────────────────────────────

test("resolveEmailConfig defaults to the JagSpoor mailbox + support inbox", () => {
  const config = email.resolveEmailConfig({});
  assert.equal(config.host, "mail.jag-spoor.co.za");
  assert.equal(config.port, 465);
  assert.equal(config.secure, true);
  assert.equal(config.user, "support@jag-spoor.co.za");
  assert.equal(config.from, "support@jag-spoor.co.za");
  assert.equal(config.to, "support@jag-spoor.co.za");
  assert.equal(config.pass, "");
});

test("resolveEmailConfig honours EMAIL_* + SUPPORT_EMAIL overrides", () => {
  const config = email.resolveEmailConfig({
    EMAIL_USER: "notifications@jag-spoor.co.za",
    EMAIL_PASS: "super-secret",
    EMAIL_HOST: "smtp.gmail.com",
    EMAIL_PORT: "587",
    EMAIL_SECURE: "false",
    SUPPORT_EMAIL: "support@jag-spoor.co.za",
  });
  assert.equal(config.host, "smtp.gmail.com");
  assert.equal(config.port, 587);
  assert.equal(config.secure, false);
  assert.equal(config.user, "notifications@jag-spoor.co.za");
  assert.equal(config.pass, "super-secret");
  assert.equal(config.to, "support@jag-spoor.co.za");
});

test("EMAIL_SECURE defaults to true and only 'false' disables it", () => {
  assert.equal(email.resolveEmailConfig({}).secure, true);
  assert.equal(email.resolveEmailConfig({ EMAIL_SECURE: "FALSE" }).secure, false);
  assert.equal(email.resolveEmailConfig({ EMAIL_SECURE: "true" }).secure, true);
});

test("an invalid EMAIL_PORT falls back to 465", () => {
  assert.equal(email.resolveEmailConfig({ EMAIL_PORT: "abc" }).port, 465);
  assert.equal(email.resolveEmailConfig({ EMAIL_PORT: "-1" }).port, 465);
  assert.equal(email.resolveEmailConfig({ EMAIL_PORT: "0" }).port, 465);
});

test("SUPPORT_EMAIL wins over the EMAIL_TO alias", () => {
  const config = email.resolveEmailConfig({
    SUPPORT_EMAIL: "support@jag-spoor.co.za",
    EMAIL_TO: "someone-else@example.com",
  });
  assert.equal(config.to, "support@jag-spoor.co.za");
});

test("EMAIL_TO is used when SUPPORT_EMAIL is absent", () => {
  const config = email.resolveEmailConfig({ EMAIL_TO: "other@example.com" });
  assert.equal(config.to, "other@example.com");
});

// ── EMAIL_PASS secret wiring ─────────────────────────────────────────────────

test("currentEmailConfigWithSecret sources the password from the secret", () => {
  const prev = process.env.EMAIL_PASS;
  delete process.env.EMAIL_PASS;
  try {
    email.setPasswordResolverForTesting(() => "secret-from-param");
    const config = email.currentEmailConfigWithSecret();
    assert.equal(config.pass, "secret-from-param");
    assert.equal(config.user, "support@jag-spoor.co.za");
    assert.equal(config.host, "mail.jag-spoor.co.za");
    assert.equal(config.port, 465);
    assert.equal(config.secure, true);
  } finally {
    email.setPasswordResolverForTesting(null);
    if (prev === undefined) delete process.env.EMAIL_PASS;
    else process.env.EMAIL_PASS = prev;
  }
});

test("the secret wins over a plaintext EMAIL_PASS env value", () => {
  const prev = process.env.EMAIL_PASS;
  process.env.EMAIL_PASS = "plaintext-env-pass";
  try {
    email.setPasswordResolverForTesting(() => "secret-value");
    assert.equal(email.currentEmailConfigWithSecret().pass, "secret-value");
  } finally {
    email.setPasswordResolverForTesting(null);
    if (prev === undefined) delete process.env.EMAIL_PASS;
    else process.env.EMAIL_PASS = prev;
  }
});

test("a throwing/empty secret resolver falls back to the env password", () => {
  const prev = process.env.EMAIL_PASS;
  process.env.EMAIL_PASS = "env-fallback-pass";
  try {
    email.setPasswordResolverForTesting(() => {
      throw new Error("secret not mounted");
    });
    assert.equal(email.currentEmailConfigWithSecret().pass, "env-fallback-pass");
    email.setPasswordResolverForTesting(() => "");
    assert.equal(email.currentEmailConfigWithSecret().pass, "env-fallback-pass");
  } finally {
    email.setPasswordResolverForTesting(null);
    if (prev === undefined) delete process.env.EMAIL_PASS;
    else process.env.EMAIL_PASS = prev;
  }
});

test("sendSupportEmail skips (no throw) when no password is resolvable", async () => {
  const prev = process.env.EMAIL_PASS;
  delete process.env.EMAIL_PASS;
  try {
    email.setPasswordResolverForTesting(() => "");
    const result = await email.notifyNewUser({
      uid: "uid-x",
      email: "x@example.com",
      displayName: "",
      provider: "password",
      createdAt: new Date("2026-10-11T00:00:00.000Z"),
    });
    assert.equal(result.sent, false);
    assert.match(result.reason, /EMAIL_PASS/);
  } finally {
    email.setPasswordResolverForTesting(null);
    if (prev === undefined) delete process.env.EMAIL_PASS;
    else process.env.EMAIL_PASS = prev;
  }
});

// ── Message builders ─────────────────────────────────────────────────────────

test("buildSubject prefixes every notification with [JagSpoor]", () => {
  const subject = email.buildSubject(email.EmailNotificationKind.NewUser, "New user: a@b.co");
  assert.equal(subject, "[JagSpoor] New user: a@b.co");
});

test("the new-user body carries email, uid, provider and time", () => {
  const body = email.buildUserSignupEmailBody({
    uid: "uid-123",
    email: "hunter@example.com",
    displayName: "Demo Hunter",
    provider: "google.com",
    createdAt: new Date("2026-10-11T12:00:00.000Z"),
  });
  assert.match(body, /hunter@example\.com/);
  assert.match(body, /uid-123/);
  assert.match(body, /google\.com/);
  assert.match(body, /Demo Hunter/);
  assert.match(body, /2026-10-11T12:00:00\.000Z/);
});

test("the new-user body tolerates missing optional fields", () => {
  const body = email.buildUserSignupEmailBody({
    uid: "uid-9",
    email: "",
    provider: "",
    createdAt: new Date("2026-01-01T00:00:00.000Z"),
  });
  assert.match(body, /\(none\)/);
  assert.match(body, /\(unknown\)/);
});

test("the subscription body carries email, uid, plan, price and full data", () => {
  const body = email.buildSubscriptionEmailBody({
    uid: "uid-42",
    userEmail: "hunter@example.com",
    plan: "hunter",
    price: "R 34.99",
    source: "users/{uid}/subscriptions onCreate",
    docPath: "users/uid-42/subscriptions/sub-1",
    data: { tier: "hunter", amount: 34.99, purchaseToken: "tok_abc" },
  });
  assert.match(body, /hunter@example\.com/);
  assert.match(body, /uid-42/);
  assert.match(body, /Plan:\s+hunter/);
  assert.match(body, /R 34\.99/);
  assert.match(body, /users\/uid-42\/subscriptions\/sub-1/);
  // Full document data (pretty-printed JSON) is included verbatim.
  assert.match(body, /purchaseToken/);
  assert.match(body, /tok_abc/);
});

test("formatDocument pretty-prints and never throws on circular data", () => {
  assert.match(email.formatDocument({ a: 1 }), /\n/);
  const circular = {};
  circular.self = circular;
  assert.doesNotThrow(() => email.formatDocument(circular));
});

// ── Subscription transition helpers ──────────────────────────────────────────

test("isActiveSubscription recognises every active billing shape", () => {
  assert.equal(notifications.isActiveSubscription({ isSubscribed: true }), true);
  assert.equal(notifications.isActiveSubscription({ isPremium: true }), true);
  assert.equal(notifications.isActiveSubscription({ isPro: true }), true);
  assert.equal(notifications.isActiveSubscription({ subscriptionStatus: "active" }), true);
  assert.equal(notifications.isActiveSubscription({ subscriptionStatus: "ACTIVE" }), true);
  assert.equal(notifications.isActiveSubscription({ subscriptionStatus: "trialing" }), false);
  assert.equal(notifications.isActiveSubscription({}), false);
  assert.equal(notifications.isActiveSubscription(undefined), false);
});

test("becameSubscribed fires on a subscriptionTier false→true transition", () => {
  assert.equal(
    notifications.becameSubscribed({ subscriptionTier: "" }, { subscriptionTier: "hunter" }),
    true
  );
  assert.equal(
    notifications.becameSubscribed({}, { subscriptionTier: "outfitter" }),
    true
  );
  // Unchanged tier does not re-notify.
  assert.equal(
    notifications.becameSubscribed({ subscriptionTier: "hunter" }, { subscriptionTier: "hunter" }),
    false
  );
});

test("becameSubscribed fires on an isSubscribed false→true transition", () => {
  assert.equal(
    notifications.becameSubscribed({ isSubscribed: false }, { isSubscribed: true }),
    true
  );
  // Already subscribed → no duplicate.
  assert.equal(
    notifications.becameSubscribed({ isSubscribed: true }, { isSubscribed: true }),
    false
  );
});

test("becameSubscribed fires on a subscriptionStatus → active transition", () => {
  assert.equal(
    notifications.becameSubscribed({ subscriptionStatus: "trialing" }, { subscriptionStatus: "active" }),
    true
  );
  assert.equal(
    notifications.becameSubscribed({}, { subscriptionStatus: "active" }),
    true
  );
});

test("becameSubscribed never fires for an ordinary profile edit", () => {
  assert.equal(
    notifications.becameSubscribed(
      { displayName: "A", subscriptionTier: "hunter" },
      { displayName: "B", subscriptionTier: "hunter" }
    ),
    false
  );
  assert.equal(notifications.becameSubscribed(undefined, undefined), false);
});

test("formatPrice renders numbers + strings and blanks unknowns", () => {
  assert.equal(notifications.formatPrice(34.99), "R 34.99");
  assert.equal(notifications.formatPrice("R34.99"), "R34.99");
  assert.equal(notifications.formatPrice(null), "");
  assert.equal(notifications.formatPrice(undefined), "");
  assert.equal(notifications.formatPrice(""), "");
});

test("resolvePlan + resolvePrice honour the documented aliases", () => {
  assert.equal(notifications.resolvePlan({ plan: "hunter" }), "hunter");
  assert.equal(notifications.resolvePlan({ tier: "outfitter" }), "outfitter");
  assert.equal(notifications.resolvePlan({ subscriptionTier: "hunter" }), "hunter");
  assert.equal(notifications.resolvePlan({ productId: "jagspoor_hunter_monthly" }), "jagspoor_hunter_monthly");
  assert.equal(notifications.resolvePlan({}), "");

  assert.equal(notifications.resolvePrice({ price: 34.99 }), "R 34.99");
  assert.equal(notifications.resolvePrice({ amount: 299.99 }), "R 299.99");
  assert.equal(notifications.resolvePrice({ priceZAR: 34.99 }), "R 34.99");
  assert.equal(notifications.resolvePrice({}), "");
});

// ── Send path (injected transport) ───────────────────────────────────────────

test("sendSupportEmail skips (never throws) when EMAIL_PASS is unset", async () => {
  const previous = process.env.EMAIL_PASS;
  delete process.env.EMAIL_PASS;
  try {
    const result = await email.sendSupportEmail({
      kind: email.EmailNotificationKind.NewUser,
      detail: "test",
      body: "test body",
    });
    assert.equal(result.sent, false);
    assert.match(result.reason, /EMAIL_PASS/);
  } finally {
    if (previous !== undefined) process.env.EMAIL_PASS = previous;
  }
});

test("sendSupportEmail sends via the injected transport with the right envelope", async () => {
  const previous = process.env.EMAIL_PASS;
  process.env.EMAIL_PASS = "test-pass";

  const captured = [];
  const fakeTransport = {
    sendMail: async (options) => {
      captured.push(options);
      return { messageId: "fake-1" };
    },
  };
  email.setTransportFactoryForTesting(() => fakeTransport);
  try {
    const result = await email.notifyNewUser({
      uid: "uid-1",
      email: "hunter@example.com",
      provider: "password",
      createdAt: new Date("2026-10-11T00:00:00.000Z"),
    });
    assert.equal(result.sent, true);
    assert.equal(captured.length, 1);
    assert.match(captured[0].to, /support@jag-spoor\.co\.za/);
    assert.match(captured[0].from, /support@jag-spoor\.co\.za/);
    assert.match(captured[0].subject, /^\[JagSpoor\] New user:/);
    assert.match(captured[0].text, /hunter@example\.com/);
  } finally {
    email.setTransportFactoryForTesting(null);
    if (previous !== undefined) process.env.EMAIL_PASS = previous;
    else delete process.env.EMAIL_PASS;
  }
});

test("a transport failure is reported, not thrown", async () => {
  const previous = process.env.EMAIL_PASS;
  process.env.EMAIL_PASS = "test-pass";
  email.setTransportFactoryForTesting(() => ({
    sendMail: async () => {
      throw new Error("smtp boom");
    },
  }));
  try {
    const result = await email.notifyNewSubscription({
      uid: "uid-1",
      userEmail: "hunter@example.com",
      plan: "hunter",
      price: "R 34.99",
      source: "test",
      docPath: "users/uid-1/subscriptions/s1",
      data: {},
    });
    assert.equal(result.sent, false);
    assert.match(result.reason, /smtp boom/);
  } finally {
    email.setTransportFactoryForTesting(null);
    if (previous !== undefined) process.env.EMAIL_PASS = previous;
    else delete process.env.EMAIL_PASS;
  }
});

// ── Wiring / structural contracts ────────────────────────────────────────────

test("index.js exports all four notification triggers + the inbox constant", () => {
  const index = require("../lib/index.js");
  for (const name of [
    "onUserCreate",
    "onSubscriptionCreate",
    "onUserSubscriptionUpdated",
    "onPricingCreated",
  ]) {
    assert.ok(index[name], `${name} must be exported`);
    // v1 auth triggers carry __trigger; v2 Firestore triggers carry __endpoint.
    assert.ok(
      index[name].__trigger || index[name].__endpoint,
      `${name} must carry trigger/endpoint metadata`
    );
  }
  assert.equal(index.SUPPORT_NOTIFICATION_EMAIL, "support@jag-spoor.co.za");
});

test("notifications.ts watches the expected document paths", () => {
  const src = stripComments(
    fs.readFileSync(path.join(ROOT, "src", "notifications.ts"), "utf8")
  );
  assert.match(src, /document:\s*"users\/\{userId\}\/subscriptions\/\{subId\}"/);
  assert.match(src, /document:\s*"users\/\{userId\}"/);
  assert.match(src, /document:\s*"pricing\/\{docId\}"/);
  // v2 identity provider (was the v1 `.auth.user().onCreate` chain).
  assert.match(src, /onUserCreated\s*\(/);
  assert.doesNotMatch(src, /\.auth\.user\(\)\s*\.onCreate/);
});

test("every mail-sending trigger declares the EMAIL_PASS secret", () => {
  const src = stripComments(
    fs.readFileSync(path.join(ROOT, "src", "notifications.ts"), "utf8")
  );
  // The four triggers must all mount the secret so emailPass.value() resolves.
  assert.equal(
    (src.match(/secrets:\s*\[emailPass\]/g) || []).length,
    4,
    "all four notification triggers declare secrets: [emailPass]"
  );
  const trial = stripComments(
    fs.readFileSync(path.join(ROOT, "src", "user_trial_onboarding.ts"), "utf8")
  );
  assert.match(trial, /onUserCreated\s*\(/);
  assert.match(trial, /secrets:\s*\[emailPass\]/);
  assert.doesNotMatch(trial, /functionsV1|firebase-functions\/v1/);

  const params = stripComments(
    fs.readFileSync(path.join(ROOT, "src", "params.ts"), "utf8")
  );
  assert.match(params, /defineSecret\("EMAIL_PASS"\)/);
});

test("email.ts defaults to the JagSpoor mailbox + support inbox", () => {
  const src = stripComments(fs.readFileSync(path.join(ROOT, "src", "email.ts"), "utf8"));
  assert.match(src, /DEFAULT_SUPPORT_EMAIL\s*=\s*"support@jag-spoor\.co\.za"/);
  assert.match(src, /DEFAULT_SMTP_HOST\s*=\s*"mail\.jag-spoor\.co\.za"/);
  assert.match(src, /DEFAULT_SMTP_PORT\s*=\s*465/);
  assert.match(src, /DEFAULT_SMTP_SECURE\s*=\s*true/);
  assert.match(src, /env\.EMAIL_USER/);
  assert.match(src, /env\.EMAIL_PASS/);
});

test("package.json depends on nodemailer + @types/nodemailer", () => {
  const pkg = require(path.join(ROOT, "package.json"));
  assert.ok(pkg.dependencies.nodemailer, "nodemailer must be a dependency");
  assert.ok(pkg.devDependencies["@types/nodemailer"], "@types/nodemailer must be a devDependency");
});

test("no real password is hard-coded anywhere in the sources", () => {
  for (const rel of ["src/email.ts", "src/notifications.ts", ".env.example"]) {
    const src = fs.readFileSync(path.join(ROOT, rel), "utf8");
    // EMAIL_PASS must only ever be read from the environment / documented as
    // a placeholder — never assigned a literal value.
    assert.ok(
      !/EMAIL_PASS\s*[:=]\s*["'][^"'<>]/i.test(src),
      `${rel} must not contain a literal EMAIL_PASS value`
    );
  }
});
