"use strict";

// Unit tests for the automated 30-day free trial & welcome email flow
// (functions/src/user_trial_onboarding.ts). These exercise the compiled
// pure helpers directly — no Firebase emulator is required.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "jagspoor-test";

const { test } = require("node:test");
const assert = require("node:assert/strict");

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

test("smtpConfigFromEnv defaults to the Afrihost relay", () => {
  const config = onboarding.smtpConfigFromEnv({
    SMTP_USER: "support@jag-spoor.co.za",
    SMTP_PASS: "secret",
  });
  assert.equal(config.host, "smtp.afrihost.co.za");
  assert.equal(config.port, 587);
  assert.equal(config.secure, false);
  assert.equal(config.user, "support@jag-spoor.co.za");
  assert.equal(config.pass, "secret");
  assert.equal(config.from, "support@jag-spoor.co.za");
  assert.equal(config.fromName, "JagSpoor");
});

test("smtpConfigFromEnv returns null when credentials are missing", () => {
  assert.equal(onboarding.smtpConfigFromEnv({}), null);
  assert.equal(onboarding.smtpConfigFromEnv({ SMTP_USER: "u" }), null);
  assert.equal(onboarding.smtpConfigFromEnv({ SMTP_PASS: "p" }), null);
});

test("smtpConfigFromEnv honors explicit overrides", () => {
  const config = onboarding.smtpConfigFromEnv({
    SMTP_HOST: "mail.example.co.za",
    SMTP_PORT: "465",
    SMTP_SECURE: "true",
    SMTP_USER: "u@example.co.za",
    SMTP_PASS: "p",
    SMTP_FROM: "noreply@example.co.za",
    SMTP_FROM_NAME: "Example",
  });
  assert.deepEqual(config, {
    host: "mail.example.co.za",
    port: 465,
    secure: true,
    user: "u@example.co.za",
    pass: "p",
    from: "noreply@example.co.za",
    fromName: "Example",
  });
});

test("formatTrialDate renders a locale-independent long date", () => {
  assert.equal(
    onboarding.formatTrialDate(new Date(Date.UTC(2026, 8, 24))),
    "24 September 2026"
  );
  assert.equal(
    onboarding.formatTrialDate(new Date(Date.UTC(2026, 0, 1))),
    "1 January 2026"
  );
});

test("welcome email informs the user of the 30-day trial + expiration", () => {
  const expiry = new Date(Date.UTC(2026, 8, 24)); // 24 September 2026
  const email = onboarding.buildWelcomeEmail({
    displayName: "Pieter",
    trialEndsAt: expiry,
  });
  assert.match(email.subject, /30-Day Free Trial/i);
  for (const body of [email.text, email.html]) {
    assert.match(body, /Pieter/);
    assert.match(body, /30-day free trial/i);
    assert.match(body, /24 September 2026/);
  }
});

test("welcome email falls back to a generic greeting without a name", () => {
  const email = onboarding.buildWelcomeEmail({
    displayName: "",
    trialEndsAt: new Date(Date.UTC(2026, 8, 24)),
  });
  assert.match(email.text, /Hi Hunter,/);
});

test("sendWelcomeEmail dispatches via the configured SMTP transport", async () => {
  const sent = [];
  let seenConfig = null;
  await onboarding.sendWelcomeEmail({
    to: "newuser@example.co.za",
    displayName: "Pieter",
    trialEndsAt: new Date(Date.UTC(2026, 8, 24)),
    config: {
      host: "smtp.afrihost.co.za",
      port: 587,
      secure: false,
      user: "support@jag-spoor.co.za",
      pass: "secret",
      from: "support@jag-spoor.co.za",
      fromName: "JagSpoor",
    },
    createTransport: (config) => {
      seenConfig = config;
      return { sendMail: async (msg) => sent.push(msg) };
    },
  });
  assert.equal(seenConfig.host, "smtp.afrihost.co.za");
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, "newuser@example.co.za");
  assert.equal(sent[0].from, '"JagSpoor" <support@jag-spoor.co.za>');
  assert.match(sent[0].subject, /30-Day Free Trial/i);
  assert.match(sent[0].text, /24 September 2026/);
  assert.match(sent[0].html, /24 September 2026/);
});

test("index.js entry point exports the auth onCreate trigger", () => {
  const index = require("../lib/index.js");
  assert.ok(index.initializeNewUserTrial, "initializeNewUserTrial exported");
  const trigger = index.initializeNewUserTrial.__trigger;
  assert.ok(trigger, "trigger metadata present");
});
