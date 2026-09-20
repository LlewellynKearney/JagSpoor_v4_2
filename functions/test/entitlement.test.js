"use strict";

// Unit tests for the billing & entitlement hardening module
// (functions/src/entitlement.ts). These exercise the compiled pure helpers
// directly — no Firebase emulator / Google Play API is required.

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "jagspoor-test";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const ent = require("../lib/entitlement.js");

test("entitlement constants are exported", () => {
  assert.equal(ent.ENTITLEMENTS_COLLECTION, "entitlements");
  assert.equal(ent.SUBSCRIPTION_SOURCE_GOOGLE_PLAY, "google_play");
  assert.equal(ent.SUBSCRIPTION_SOURCE_PAYFAST, "payfast");
  assert.equal(ent.SUBSCRIPTION_SOURCE_TRIAL, "trial");
  assert.equal(ent.PACKAGE_NAME, "za.co.jagspoor.app");
});

test("google play product ids match the app catalog", () => {
  assert.deepEqual([...ent.GOOGLE_PLAY_PRODUCTS].sort(), [
    "jagspoor_hunter_monthly",
    "jagspoor_outfitter_monthly",
  ]);
});

test("writeEntitlement rejects an empty uid", async () => {
  await assert.rejects(
    () =>
      ent.writeEntitlement("", {
        isPremium: true,
        premiumExpiry: new Date(),
        subscriptionSource: ent.SUBSCRIPTION_SOURCE_TRIAL,
      }),
    /non-empty uid/
  );
});

test("playStateError maps subscription states", () => {
  assert.equal(
    ent.playStateError(2),
    "The subscription has expired or was cancelled."
  );
  assert.equal(
    ent.playStateError(0),
    "The purchase could not be verified with Google Play."
  );
  assert.equal(ent.playStateError(1), null);
});

test("RTDN revocation types cover refunds/expirations but not simple cancellations", () => {
  assert.ok(ent.isRevocation(12)); // REVOKED (refund)
  assert.ok(ent.isRevocation(13)); // EXPIRED
  assert.ok(ent.isRevocation(9)); // PRODUCT_NOT_AVAILABLE
  assert.ok(!ent.isRevocation(3)); // CANCELED keeps paid-through access
  assert.ok(!ent.isRevocation(1));
});

test("parseRtdnMessage decodes a base64 subscription notification", () => {
  const raw = JSON.stringify({
    version: "1.0",
    packageName: ent.PACKAGE_NAME,
    eventTimeMillis: "1780000000000",
    subscriptionNotification: {
      notificationType: 12,
      purchaseToken: "token-rtdn-1",
      subscriptionId: "jagspoor_hunter_monthly",
    },
  });
  const parsed = ent.parseRtdnMessage(
    Buffer.from(raw).toString("base64")
  );
  assert.ok(parsed);
  assert.equal(parsed.notificationType, 12);
  assert.equal(parsed.purchaseToken, "token-rtdn-1");
  assert.equal(parsed.subscriptionId, "jagspoor_hunter_monthly");
});

test("parseRtdnMessage returns null for unparseable data", () => {
  assert.equal(ent.parseRtdnMessage("not-base64-!"), null);
  assert.equal(ent.parseRtdnMessage(""), null);
});

test("payfastSignatureMatches validates an MD5 signature", () => {
  const params = {
    m_payment_id: "A",
    amount_gross: "199",
    signature: "",
  };
  const passphrase = "jagspoor_test";
  const expected = require("crypto")
    .createHash("md5")
    .update("amount_gross=199&m_payment_id=A&passphrase=jagspoor_test")
    .digest("hex");
  params["signature"] = expected;
  assert.equal(ent.payfastSignatureMatches(params, passphrase), true);
});

test("payfastSignatureMatches rejects a tampered signature", () => {
  const params = {
    m_payment_id: "A",
    amount_gross: "200",
    signature: "0".repeat(32),
  };
  assert.equal(ent.payfastSignatureMatches(params, "secret"), false);
});

test("paymentPlanFrom validates amount against the published plan", () => {
  assert.deepEqual(ent.paymentPlanFrom("monthly", 199), {
    plan: "monthly",
    months: 1,
  });
  assert.deepEqual(ent.paymentPlanFrom("yearly", 399), {
    plan: "yearly",
    months: 12,
  });
  assert.equal(ent.paymentPlanFrom("monthly", 200), null);
});

test("payfastPaymentIdFor derives a stable opaque id", () => {
  const a = ent.payfastPaymentIdFor("HUNTER@EXAMPLE.COM", "pmid-1");
  const b = ent.payfastPaymentIdFor("hunter@example.com", "pmid-1");
  assert.equal(a, b);
  assert.match(a, /^[a-f0-9]{24}$/);
});

test("index.js entry point exports the entitlement functions", () => {
  const index = require("../lib/index.js");
  assert.ok(
    index.validateGooglePlayPurchase,
    "validateGooglePlayPurchase exported"
  );
  assert.ok(index.onGooglePlayRTDN, "onGooglePlayRTDN exported");
  assert.ok(index.payfastITN, "payfastITN exported");
  assert.ok(index.writeEntitlement, "writeEntitlement exported");
});