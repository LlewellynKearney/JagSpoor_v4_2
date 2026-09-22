"use strict";

// Unit tests for the VAT-inclusive pricing seed module
// (functions/src/seed_pricing.ts). Exercises the compiled pure helpers —
// no Firebase emulator required (the write paths are operator-run only and
// guarded by SEED_CONFIRM).

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "jagspoor-test";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const seed = require("../lib/seed_pricing.js");

test("control-plane constants (Option A VAT-inclusive)", () => {
  assert.equal(seed.VAT_RATE_PERCENT, 15);
  assert.equal(seed.HUNTER_PRICE_INCL_ZAR, 34.99);
  assert.equal(seed.OUTFITTER_PRICE_INCL_ZAR, 299.99);
  assert.equal(seed.PRICING_CONFIG_PATH, "admin_config/pricing");
  assert.equal(seed.REFERRAL_REWARDS_PATH, "admin_config/referral_rewards");
});

test("exclusiveOf absorbs 15% VAT out of the inclusive charge", () => {
  assert.equal(seed.exclusiveOf(34.99), 30.43);
  assert.equal(seed.exclusiveOf(299.99), 260.86);
  // A non-round figure still rounds to whole cents.
  assert.equal(seed.exclusiveOf(149.99), 130.43);
});

test("vatOf returns the absorbed VAT component", () => {
  assert.equal(seed.vatOf(34.99), 4.56);
  assert.equal(seed.vatOf(299.99), 39.13);
});

test("displayPriceFor renders the incl.-VAT label", () => {
  assert.equal(seed.displayPriceFor(34.99), "R34.99/month incl. VAT");
  assert.equal(seed.displayPriceFor(299.99), "R299.99/month incl. VAT");
});

test("pricingSeedPayload carries both key families + the VAT breakdown", () => {
  const payload = seed.pricingSeedPayload();
  assert.equal(payload.hunter_monthly, 34.99);
  assert.equal(payload.outfitter_monthly, 299.99);
  assert.equal(payload.hunterSubscriptionZAR, 34.99);
  assert.equal(payload.outfitterSubscriptionZAR, 299.99);
  assert.equal(payload.vat, 15);
  assert.equal(payload.hunter_price_excl, 30.43);
  assert.equal(payload.hunter_price_incl, 34.99);
  assert.equal(payload.outfitter_price_excl, 260.86);
  assert.equal(payload.outfitter_price_incl, 299.99);
  assert.equal(payload.hunter_display_price, "R34.99/month incl. VAT");
  assert.equal(payload.outfitter_display_price, "R299.99/month incl. VAT");
});

test("referralRewardsSeedPayload mirrors one month's subscription value", () => {
  const payload = seed.referralRewardsSeedPayload();
  assert.equal(payload.hunter, 34.99);
  assert.equal(payload.outfitter, 299.99);
  assert.equal(payload.hunterRewardZAR, 34.99);
  assert.equal(payload.outfitterRewardZAR, 299.99);
  assert.equal(payload.rewardType, "extension_days");
  assert.equal(payload.hunter_days, 30);
  assert.equal(payload.outfitter_days, 30);
});

test("the pricing seed module is NOT re-exported from the functions index", () => {
  // It is an operator script, not a deployed Cloud Function.
  const index = require("../lib/index.js");
  assert.equal(index.seedPricingDoc, undefined);
  assert.equal(index.pricingSeedPayload, undefined);
});
