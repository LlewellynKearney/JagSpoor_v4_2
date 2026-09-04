"use strict";

// Unit tests for the automated 30-day free trial provisioning flow
// (functions/src/user_trial_onboarding.ts). These exercise the compiled
// pure helpers directly — no Firebase emulator is required.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "jagspoor-test";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const onboarding = require("../lib/user_trial_onboarding.js");

test("trial period is exactly 30 days", () => {
  assert.equal(onboarding.TRIAL_PERIOD_DAYS, 30);
  assert.equal(onboarding.TRIAL_PERIOD_MS, 30 * 24 * 60 * 60 * 1000);
});

test("trialEndsAtFrom returns exactly 30 days in the future", () => {
  const start = new Date(Date.UTC(2026, 7, 25, 10, 30, 0)); // 25 Aug 2026
  const end = onboarding.trialEndsAtFrom(start);
  assert.equal(end.getTime() - start.getTime(), 30 * 24 * 60 * 60 * 1000);
  assert.equal(end.toISOString(), "2026-09-24T10:30:00.000Z");
});

test("index.js entry point exports the auth onCreate trigger", () => {
  const index = require("../lib/index.js");
  assert.ok(index.initializeNewUserTrial, "initializeNewUserTrial exported");
  const trigger = index.initializeNewUserTrial.__trigger;
  assert.ok(trigger, "trigger metadata present");
});

test("the trigger writes the trialing state to users/{uid}", () => {
  // Structural contract: the handler merge-writes the trial state (this
  // assertion inspects the compiled source text).
  const compiled = fs.readFileSync(
    __dirname + "/../lib/user_trial_onboarding.js",
    "utf8"
  );
  assert.match(compiled, /subscriptionStatus: "trialing"/);
  assert.match(compiled, /trialEndsAt/);
  assert.match(compiled, /requiresPayment: false/);
  assert.match(compiled, /merge: true/);
});

test("the trigger preserves a pre-existing non-trial subscription status", () => {
  // Structural contract: an existing non-trial status short-circuits the
  // trial write so the trigger can never downgrade an account.
  const compiled = fs.readFileSync(
    __dirname + "/../lib/user_trial_onboarding.js",
    "utf8"
  );
  assert.match(
    compiled,
    /existingStatus !== "" && existingStatus !== "trialing"/
  );
});

test("no welcome-email or trial-abuse surface remains", () => {
  // The module must not reference any SMTP / nodemailer transport or the
  // device-fingerprint trial-abuse check anymore.
  const compiled = fs.readFileSync(
    __dirname + "/../lib/user_trial_onboarding.js",
    "utf8"
  );
  assert.doesNotMatch(compiled, /nodemailer/i);
  assert.doesNotMatch(compiled, /smtp/i);
  assert.doesNotMatch(compiled, /sendWelcomeEmail/);
  assert.doesNotMatch(compiled, /deviceFingerprint/i);
  assert.doesNotMatch(compiled, /isTrialAbuseExempt/);
  assert.doesNotMatch(compiled, /trialBlockedReason/);
});

test("ADMIN_EMAIL is the platform admin email", () => {
  assert.equal(onboarding.ADMIN_EMAIL, "admin@jag-spoor.co.za");
});

test("isAdminAccount excludes the admin email (case-insensitive)", () => {
  assert.equal(
    onboarding.isAdminAccount({ email: "admin@jag-spoor.co.za" }),
    true
  );
  assert.equal(
    onboarding.isAdminAccount({ email: "ADMIN@JAG-SPOOR.CO.ZA" }),
    true
  );
  assert.equal(
    onboarding.isAdminAccount({ email: "  admin@jag-spoor.co.za  " }),
    true
  );
});

test("isAdminAccount admits standard accounts", () => {
  assert.equal(onboarding.isAdminAccount({ email: "hunter@example.com" }), false);
  assert.equal(onboarding.isAdminAccount({ email: null }), false);
  assert.equal(onboarding.isAdminAccount({ email: "" }), false);
  assert.equal(onboarding.isAdminAccount({}), false);
});

test("the trigger bypasses trial assignment for the admin account", () => {
  // Structural contract: the handler short-circuits (returns) before any
  // trial write when the new user is the admin.
  const compiled = fs.readFileSync(
    __dirname + "/../lib/user_trial_onboarding.js",
    "utf8"
  );
  assert.match(compiled, /isAdminAccount\(user\)/);
  assert.match(compiled, /admin account excluded from trial/);
});
