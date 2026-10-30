"use strict";

/**
 * Admin Portal KPI aggregation contract tests (functions/src/admin/kpis.ts).
 *
 * The Admin Portal's headline metrics are computed server-side so they cannot
 * silently read 0 because a client query was denied by the party-scoped
 * Firestore rules. These tests exercise the compiled pure helpers directly —
 * no Firebase emulator, no Admin SDK, no network.
 *
 * Coverage:
 *   * the collection / status / platform constants the client mirrors;
 *   * `isActiveSubscription` — a trial is NOT a subscription, an expired
 *     premium is NOT a subscription, the nested mirror counts;
 *   * `platformOf` keeps `payfast_alternative` distinct from plain `payfast`;
 *   * `aggregateUserKpis` counts roles, subscribers by platform and tier;
 *   * `aggregateBookingKpis` counts active vs completed and sums realized
 *     revenue into the four windows (pending bookings never count as revenue);
 *   * `computeMrr` / `pricingFromConfig` derive the recurring revenue;
 *   * `resolveInstalls` prefers the installs collection and falls back to the
 *     registered-account count;
 *   * `isAdminRequest` mirrors the `isAdmin()` rule (claim / allow-list / doc);
 *   * the callable is exported from index.js with the documented region.
 */

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "jagspoor-test";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const kpis = require("../lib/admin/kpis.js");

const {
  USERS_COLLECTION,
  OUTFITTERS_COLLECTION,
  PACKAGES_COLLECTION,
  BOOKINGS_COLLECTION,
  TROPHY_STOCK_COLLECTION,
  INSTALLS_COLLECTION,
  ACTIVE_BOOKING_STATUSES,
  COMPLETED_BOOKING_STATUSES,
  EARNED_BOOKING_STATUSES,
  PLATFORM_GOOGLE_PLAY,
  PLATFORM_PAYFAST,
  PLATFORM_PAYFAST_ALTERNATIVE,
  platformOf,
  isActiveSubscription,
  tierOf,
  bookingRevenueOf,
  bookingDateOf,
  aggregateUserKpis,
  aggregateBookingKpis,
  computeMrr,
  pricingFromConfig,
  resolveInstalls,
  isAdminRequest,
} = kpis;

const NOW = new Date("2026-10-30T12:00:00.000Z");
const daysAgo = (n) => new Date(NOW.getTime() - n * 24 * 60 * 60 * 1000);

test("collection constants match the app schema", () => {
  assert.equal(USERS_COLLECTION, "users");
  assert.equal(OUTFITTERS_COLLECTION, "outfitters");
  assert.equal(PACKAGES_COLLECTION, "packages");
  assert.equal(BOOKINGS_COLLECTION, "bookings");
  assert.equal(TROPHY_STOCK_COLLECTION, "trophy_stock");
  assert.equal(INSTALLS_COLLECTION, "installs");
});

test("booking status groups", () => {
  assert.deepEqual(ACTIVE_BOOKING_STATUSES, [
    "pending approval",
    "awaiting payment",
    "confirmed",
  ]);
  assert.deepEqual(COMPLETED_BOOKING_STATUSES, ["completed"]);
  // Only payment-verified bookings are revenue.
  assert.deepEqual(EARNED_BOOKING_STATUSES, ["confirmed", "completed"]);
});

test("platformOf keeps payfast_alternative distinct", () => {
  assert.equal(platformOf({ subscriptionPlatform: "google_play" }), PLATFORM_GOOGLE_PLAY);
  assert.equal(platformOf({ subscriptionPlatform: "payfast" }), PLATFORM_PAYFAST);
  assert.equal(
    platformOf({ subscriptionPlatform: "payfast_alternative" }),
    PLATFORM_PAYFAST_ALTERNATIVE
  );
  // Falls back to the legacy `subscriptionSource` spelling.
  assert.equal(platformOf({ subscriptionSource: "google_play" }), PLATFORM_GOOGLE_PLAY);
  // Non-billing sources resolve to null.
  assert.equal(platformOf({ subscriptionSource: "trial" }), null);
  assert.equal(platformOf({}), null);
  assert.equal(platformOf(null), null);
});

test("isActiveSubscription — trial and expired premium are NOT subscriptions", () => {
  assert.equal(
    isActiveSubscription({ subscriptionStatus: "active" }, NOW),
    true
  );
  // The reported live case: a trialing account has not been charged.
  assert.equal(
    isActiveSubscription({ subscriptionStatus: "trialing" }, NOW),
    false
  );
  assert.equal(isActiveSubscription({}, NOW), false);
  assert.equal(isActiveSubscription(null, NOW), false);
  // Legacy flag + future expiry counts; expired does not.
  assert.equal(
    isActiveSubscription(
      { isPremium: true, premiumExpiry: new Date(NOW.getTime() + 86400000) },
      NOW
    ),
    true
  );
  assert.equal(
    isActiveSubscription(
      { isPremium: true, premiumExpiry: new Date(NOW.getTime() - 86400000) },
      NOW
    ),
    false
  );
  // The nested entitlement mirror counts on its own.
  assert.equal(
    isActiveSubscription({ subscription: { isActive: true } }, NOW),
    true
  );
  assert.equal(
    isActiveSubscription({ subscription: { status: "active" } }, NOW),
    true
  );
});

test("tierOf resolves the subscriber tier", () => {
  assert.equal(tierOf({ subscriptionTier: "outfitter" }), "outfitter");
  assert.equal(tierOf({ subscriptionProduct: "jagspoor_outfitter_monthly" }), "outfitter");
  assert.equal(tierOf({ subscriptionTier: "hunter" }), "hunter");
  assert.equal(tierOf({}), "hunter");
});

test("aggregateUserKpis counts roles, subscribers and the platform mix", () => {
  const users = [
    // 2 active Google Play subscribers (1 hunter, 1 outfitter).
    {
      uid: "a",
      role: "hunter",
      subscriptionStatus: "active",
      subscriptionPlatform: "google_play",
      subscriptionTier: "hunter",
      deviceFingerprint: "dev-1",
    },
    {
      uid: "b",
      role: "outfitter",
      subscriptionStatus: "active",
      subscriptionPlatform: "google_play",
      subscriptionTier: "outfitter",
      deviceFingerprint: "dev-2",
    },
    // 1 active PayFast subscriber.
    {
      uid: "c",
      role: "hunter",
      subscriptionStatus: "active",
      subscriptionPlatform: "payfast",
      subscriptionTier: "hunter",
      deviceFingerprint: "dev-1", // same device as `a` -> 1 distinct device
    },
    // A trialing account: a registered hunter, NOT a subscriber.
    { uid: "d", role: "hunter", subscriptionStatus: "trialing" },
    // A role-less account: registered, counted in no role bucket.
    { uid: "e" },
  ];

  const agg = aggregateUserKpis(users, NOW);
  assert.equal(agg.registeredUsers, 5);
  assert.equal(agg.totalHunters, 3);
  assert.equal(agg.totalOutfitters, 1);
  assert.equal(agg.totalSubscribers, 3);
  assert.equal(agg.googleSubscribers, 2);
  assert.equal(agg.payfastSubscribers, 1);
  assert.equal(agg.hunterSubscribers, 2);
  assert.equal(agg.outfitterSubscribers, 1);
  assert.equal(agg.distinctDevices, 2);
});

test("aggregateBookingKpis counts active/completed and sums realized revenue", () => {
  const bookings = [
    { status: "Pending Approval", totalHunterPriceRands: 9999, createdAt: daysAgo(1) },
    { status: "Awaiting Payment", totalHunterPriceRands: 9999, createdAt: daysAgo(1) },
    { status: "Confirmed", totalHunterPriceRands: 1000, createdAt: daysAgo(0) },
    { status: "Completed", totalHunterPriceRands: 2000, createdAt: daysAgo(3) },
    { status: "Completed", totalHunterPriceRands: 4000, createdAt: daysAgo(20) },
    { status: "Completed", totalHunterPriceRands: 8000, createdAt: daysAgo(200) },
    { status: "Declined", totalHunterPriceRands: 5000, createdAt: daysAgo(1) },
  ];

  const agg = aggregateBookingKpis(bookings, NOW);
  assert.equal(agg.activeBookings, 3); // pending + awaiting + confirmed
  assert.equal(agg.completedBookings, 3);
  // Only the earned (confirmed / completed) rows contribute revenue.
  assert.equal(agg.daily, 1000);
  assert.equal(agg.weekly, 3000); // 1000 + 2000
  assert.equal(agg.monthly, 7000); // + 4000
  assert.equal(agg.yearly, 15000); // + 8000
});

test("aggregateBookingKpis tolerates the legacy revenue field spellings", () => {
  const agg = aggregateBookingKpis(
    [
      { status: "Confirmed", totalPriceZAR: 500, createdAt: daysAgo(0) },
      { status: "Completed", basePriceRands: 250, createdAt: daysAgo(0) },
    ],
    NOW
  );
  assert.equal(agg.daily, 750);
});

test("bookingDateOf falls back from bookingTimestamp to createdAt", () => {
  const ts = { toDate: () => daysAgo(2) };
  assert.equal(bookingDateOf({ bookingTimestamp: ts })?.getTime(), daysAgo(2).getTime());
  assert.equal(bookingDateOf({ createdAt: ts })?.getTime(), daysAgo(2).getTime());
  assert.equal(bookingDateOf({}), null);
});

test("bookingRevenueOf is zero for an unknown shape", () => {
  assert.equal(bookingRevenueOf({}), 0);
  assert.equal(bookingRevenueOf(null), 0);
  assert.equal(bookingRevenueOf({ totalHunterPriceRands: "1200" }), 1200);
});

test("computeMrr multiplies the subscriber mix by the configured prices", () => {
  // 14 hunters × R34.99 + 2 outfitters × R299.99 = R1089.84 (the live figure).
  assert.equal(computeMrr(14, 2, 34.99, 299.99), 1089.84);
  assert.equal(computeMrr(0, 0, 34.99, 299.99), 0);
  // Non-finite prices collapse to 0 rather than NaN.
  assert.equal(computeMrr(2, 1, Number.NaN, 299.99), 299.99);
});

test("pricingFromConfig reads the canonical keys and falls back", () => {
  assert.deepEqual(
    pricingFromConfig({ hunter_monthly: 34.99, outfitter_monthly: 299.99 }),
    { hunterPrice: 34.99, outfitterPrice: 299.99 }
  );
  assert.deepEqual(
    pricingFromConfig({ hunter_price_incl: 39.99, outfitter_price_incl: 349.99 }),
    { hunterPrice: 39.99, outfitterPrice: 349.99 }
  );
  assert.deepEqual(pricingFromConfig(null), { hunterPrice: 0, outfitterPrice: 0 });
});

test("resolveInstalls prefers the installs collection, else the account count", () => {
  assert.deepEqual(resolveInstalls(120, 25), {
    totalInstalls: 120,
    installsSource: "installs",
  });
  // No install beacons yet -> registered accounts is the honest proxy.
  assert.deepEqual(resolveInstalls(0, 25), {
    totalInstalls: 25,
    installsSource: "authUsers",
  });
});

test("isAdminRequest mirrors the isAdmin() rule sources", () => {
  // Custom claim.
  assert.equal(isAdminRequest({ uid: "u", token: { admin: true } }, null), true);
  // Bootstrap email allow-list.
  assert.equal(
    isAdminRequest({ uid: "u", token: { email: "admin@jag-spoor.co.za" } }, null),
    true
  );
  assert.equal(
    isAdminRequest({ uid: "u", token: { email: "ADMIN@JAG-SPOOR.CO.ZA" } }, null),
    true
  );
  // users/{uid}.role == 'admin' fallback.
  assert.equal(isAdminRequest({ uid: "u", token: {} }, "admin"), true);
  // A regular signed-in user is denied.
  assert.equal(isAdminRequest({ uid: "u", token: { email: "a@b.c" } }, "hunter"), false);
  assert.equal(isAdminRequest({ uid: "u", token: {} }, null), false);
  // No auth at all.
  assert.equal(isAdminRequest(null, "admin"), false);
  assert.equal(isAdminRequest({ token: { admin: true } }, null), false);
});

test("getAdminPortalKpis is exported as a callable from index.js", () => {
  const index = require("../lib/index.js");
  assert.ok(index.getAdminPortalKpis, "getAdminPortalKpis must be exported");
  // A v2 callable exposes its trigger metadata under `__endpoint`.
  const endpoint = index.getAdminPortalKpis.__endpoint;
  assert.ok(endpoint, "callable must expose __endpoint");
  assert.equal(endpoint.platform, "gcfv2");
});
