"use strict";

/**
 * Google Play **User Choice Billing** (alternative billing) contract tests.
 *
 * South Africa is enrolled in Play's alternative billing programme, so an
 * Android subscriber may pay through PayFast instead of Google Play Billing.
 * Play still invoices a reduced service fee for those transactions, which the
 * server reports to the Play Developer API. These tests lock:
 *
 *   * the platform resolution keeps `payfast_alternative` DISTINCT from plain
 *     `payfast` (the fee reconciliation depends on telling them apart) while
 *     both still resolve to the website-managed branch;
 *   * a report row missing a token / user / amount is never sent to Google;
 *   * the `externaltransactions.create` body carries the token, the ZAR
 *     amounts split into pre-tax + tax, and a PII-free transaction id;
 *   * the ITN's `custom_str4` marker drives the alternative-billing
 *     entitlement path;
 *   * the PayFast form always carries the marker field (so the signature
 *     covers it and a client cannot flip it).
 */

const test = require("node:test");
const assert = require("node:assert");

const alt = require("../lib/alternative_billing");
const entitlement = require("../lib/entitlement");
const svc = require("../lib/payfast/payfast.service");

const {
  ALTERNATIVE_BILLING_REPORTS_COLLECTION,
  ALTERNATIVE_BILLING_FEE_BASIS_POINTS,
  validateReportRow,
  buildExternalTransaction,
  externalSubscriptionTypeFor,
  externalSubscriptionIdFor,
  externalTransactionIdFor,
} = alt;

const { platformFromSource, SUBSCRIPTION_SOURCE_PAYFAST_ALTERNATIVE } =
  entitlement;

const VALID_ROW = {
  userId: "uid-1",
  tier: "hunter",
  billingCycle: "monthly",
  planId: "hunter_monthly",
  alternativeSku: "jagspoor_hunter_monthly_payfast",
  amountZar: 34.99,
  reportingToken: "tok_abc123",
  status: "reported",
};

test("constants", () => {
  assert.strictEqual(
    ALTERNATIVE_BILLING_REPORTS_COLLECTION,
    "alternative_billing_reports"
  );
  // 26% — the reduced alternative-billing service fee.
  assert.strictEqual(ALTERNATIVE_BILLING_FEE_BASIS_POINTS, 2600);
  assert.strictEqual(SUBSCRIPTION_SOURCE_PAYFAST_ALTERNATIVE, "payfast_alternative");
});

// ── platform resolution ────────────────────────────────────────────────────

test("platformFromSource keeps payfast_alternative distinct from payfast", () => {
  assert.strictEqual(
    platformFromSource("payfast_alternative"),
    "payfast_alternative"
  );
  assert.strictEqual(platformFromSource("PAYFAST_ALTERNATIVE"), "payfast_alternative");
  assert.strictEqual(platformFromSource("payfast"), "payfast");
  assert.strictEqual(platformFromSource("google_play"), "google_play");
  assert.strictEqual(platformFromSource("trial"), null);
  assert.strictEqual(platformFromSource(null), null);
});

// ── report row validation ──────────────────────────────────────────────────

test("validateReportRow accepts a complete row", () => {
  assert.deepStrictEqual(validateReportRow(VALID_ROW), { ok: true });
});

test("validateReportRow rejects a missing token", () => {
  const r = validateReportRow({ ...VALID_ROW, reportingToken: "" });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, "no_reporting_token");
});

test("validateReportRow rejects a missing user", () => {
  const r = validateReportRow({ ...VALID_ROW, userId: "" });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, "no_user");
});

test("validateReportRow rejects a bad amount", () => {
  for (const amountZar of [0, -5, NaN, undefined]) {
    const r = validateReportRow({ ...VALID_ROW, amountZar });
    assert.strictEqual(r.ok, false, `amount ${amountZar} should be rejected`);
    assert.strictEqual(r.reason, "bad_amount");
  }
});

test("validateReportRow rejects a missing row", () => {
  assert.strictEqual(validateReportRow(null).reason, "missing_report");
  assert.strictEqual(validateReportRow(undefined).reason, "missing_report");
});

// ── external transaction body ──────────────────────────────────────────────

test("buildExternalTransaction carries the token + subscription type", () => {
  const body = buildExternalTransaction(VALID_ROW, {
    transactionTime: new Date("2026-10-23T10:00:00.000Z"),
    externalSubscriptionId: "jagspoor_hunter_uid-1",
  });
  assert.strictEqual(
    body.recurringTransaction.externalTransactionToken,
    "tok_abc123"
  );
  assert.strictEqual(
    body.recurringTransaction.externalSubscription.subscriptionType,
    "SUBSCRIPTION_TYPE_MONTHLY"
  );
  assert.strictEqual(body.transactionTime, "2026-10-23T10:00:00.000Z");
  assert.strictEqual(body.userTaxAddress.regionCode, "ZA");
});

test("buildExternalTransaction splits the VAT-inclusive amount", () => {
  const body = buildExternalTransaction(VALID_ROW, {
    transactionTime: new Date(),
    externalSubscriptionId: "s",
  });
  // 34.99 incl VAT -> 30.426087 ex-VAT + 4.563913 VAT (Option A pricing).
  assert.strictEqual(body.originalPreTaxAmount.currency, "ZAR");
  const preTax = Number(body.originalPreTaxAmount.priceMicros) / 1e6;
  const tax = Number(body.originalTaxAmount.priceMicros) / 1e6;
  assert.ok(Math.abs(preTax - 34.99 / 1.15) < 0.000001, `preTax ${preTax}`);
  assert.ok(Math.abs(tax - 4.563913) < 0.000001, `tax ${tax}`);
  // The two components must reconstruct the amount the customer paid.
  assert.ok(Math.abs(preTax + tax - 34.99) < 0.000002, "parts must sum to 34.99");
});

test("buildExternalTransaction omits the program code when unset", () => {
  const body = buildExternalTransaction(VALID_ROW, {
    transactionTime: new Date(),
    externalSubscriptionId: "s",
  });
  assert.strictEqual("transactionProgramCode" in body, false);
});

test("buildExternalTransaction includes the program code when supplied", () => {
  const body = buildExternalTransaction(VALID_ROW, {
    transactionTime: new Date(),
    externalSubscriptionId: "s",
    programCode: 1234,
  });
  assert.strictEqual(body.transactionProgramCode, 1234);
});

test("externalSubscriptionTypeFor maps the billing cycle", () => {
  assert.strictEqual(
    externalSubscriptionTypeFor("monthly"),
    "SUBSCRIPTION_TYPE_MONTHLY"
  );
  assert.strictEqual(
    externalSubscriptionTypeFor("yearly"),
    "SUBSCRIPTION_TYPE_YEARLY"
  );
  assert.strictEqual(
    externalSubscriptionTypeFor("annual"),
    "SUBSCRIPTION_TYPE_YEARLY"
  );
  // An unknown cycle still reports (falls back to monthly).
  assert.strictEqual(
    externalSubscriptionTypeFor(undefined),
    "SUBSCRIPTION_TYPE_MONTHLY"
  );
});

test("externalSubscriptionIdFor groups per user + tier", () => {
  assert.strictEqual(
    externalSubscriptionIdFor(VALID_ROW),
    "jagspoor_hunter_uid-1"
  );
  assert.strictEqual(
    externalSubscriptionIdFor({ ...VALID_ROW, tier: "outfitter" }),
    "jagspoor_outfitter_uid-1"
  );
});

test("externalTransactionIdFor is PII-free, stable and within the length cap", () => {
  const id = externalTransactionIdFor("report-abc", VALID_ROW);
  assert.strictEqual(id, externalTransactionIdFor("report-abc", VALID_ROW));
  assert.ok(id.length >= 1 && id.length <= 63, `length was ${id.length}`);
  assert.ok(/^[a-zA-Z0-9_-]+$/.test(id), `id was ${id}`);
  // Google forbids PII (emails etc.) in this field.
  assert.ok(!id.includes("@"), "the id must not contain an email");
});

test("externalTransactionIdFor sanitises + truncates hostile input", () => {
  const id = externalTransactionIdFor("a".repeat(80) + "@@bad", VALID_ROW);
  assert.ok(id.length <= 63, `length was ${id.length}`);
  assert.ok(/^[a-zA-Z0-9_-]+$/.test(id), `id was ${id}`);
});

// ── PayFast form carries the alternative-billing marker ────────────────────

test("buildPaymentForm always carries the custom_str4 marker", () => {
  const base = {
    userId: "uid-1",
    role: "hunter",
    planId: "hunter_monthly",
    amount: 34.99,
    itemName: "JagSpoor Hunter Monthly",
    returnUrl: "https://jagspoor.web.app/#/subscription/success",
    cancelUrl: "https://jagspoor.web.app/#/subscription/cancel",
    notifyUrl: "https://us-central1-jagspoor.cloudfunctions.net/payfastNotify",
    merchantKey: "test-key",
  };
  const standard = svc.buildPaymentForm({ ...base });
  assert.strictEqual(standard.fields.custom_str4, "standard");

  const altForm = svc.buildPaymentForm({ ...base, alternativeBilling: true });
  assert.strictEqual(altForm.fields.custom_str4, "alt_billing");
});

// ── ITN validation surfaces the marker ─────────────────────────────────────

test("validateItn reports alternativeBilling from custom_str4", () => {
  const passphrase = "pf-pass";
  const fields = {
    payment_status: "COMPLETE",
    custom_str1: "uid-1",
    custom_str2: "hunter_monthly",
    custom_str3: "hunter",
    custom_str4: "alt_billing",
    amount_gross: "34.99",
  };
  fields.signature = svc.generateSignature(fields, passphrase);
  const result = svc.validateItn(fields, passphrase, {
    hunter_monthly: { amountZar: 34.99 },
  });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.alternativeBilling, true);
});

test("validateItn reports alternativeBilling=false without the marker", () => {
  const passphrase = "pf-pass";
  const fields = {
    payment_status: "COMPLETE",
    custom_str1: "uid-1",
    custom_str2: "hunter_monthly",
    custom_str3: "hunter",
    amount_gross: "34.99",
  };
  fields.signature = svc.generateSignature(fields, passphrase);
  const result = svc.validateItn(fields, passphrase, {
    hunter_monthly: { amountZar: 34.99 },
  });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.alternativeBilling, false);
});

// ── structural contracts ───────────────────────────────────────────────────

test("the module is exported from the functions entry point", () => {
  const index = require("../lib/index");
  assert.strictEqual(
    typeof index.reportAlternativeBillingTransactionCallable,
    "function"
  );
  assert.strictEqual(
    typeof index.grantAlternativeBillingEntitlement,
    "function"
  );
});

test("the callable is registered and enforces ownership", () => {
  const src = require("fs").readFileSync(
    require("path").join(__dirname, "..", "src", "alternative_billing.ts"),
    "utf8"
  );
  assert.ok(src.includes("onCall("), "must be a callable");
  // A user may only report their own transaction.
  assert.ok(
    src.includes("You may only report your own transactions."),
    "must enforce report ownership"
  );
  assert.ok(
    src.includes("unauthenticated"),
    "must require authentication"
  );
});

test("reporting uses the real externaltransactions API surface", () => {
  const src = require("fs").readFileSync(
    require("path").join(__dirname, "..", "src", "alternative_billing.ts"),
    "utf8"
  );
  assert.ok(
    src.includes("externaltransactions.createexternaltransaction"),
    "must call the generated client's flattened method name"
  );
  assert.ok(
    !src.includes("createAlternativeBillingReportingToken"),
    "the non-existent BillingClient method must not be referenced"
  );
});
