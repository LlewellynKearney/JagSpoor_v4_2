"use strict";

/**
 * Unit tests for the `purchases` -> `users/{uid}` repair script
 * (`functions/src/sync_purchases.ts`).
 *
 * Two contracts are locked here:
 *   1. Junk purchase rows (blank `productId` / `purchaseToken`) are DELETED —
 *      they can never be verified against the Google Play Developer API and
 *      must never grant entitlement.
 *   2. Every uid with an ACTIVE, verifiable purchase gets `users/{uid}`
 *      repaired to `subscriptionStatus: 'active'` + `hasActivePurchase: true`.
 *
 * The Firestore emulator cannot run in this sandbox, so the script's pure
 * helpers are asserted directly and the write/delete behaviour is exercised
 * through an injected fake Firestore.
 */

const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  PURCHASES_COLLECTION,
  USERS_COLLECTION,
  PURCHASE_STATUS_ACTIVE,
  SUBSCRIPTION_STATUS_ACTIVE,
  isJunkPurchaseRow,
  isActivePurchaseRow,
  usersSyncPayload,
  syncPurchases,
} = require("../lib/sync_purchases.js");

/** Minimal in-memory Firestore double covering only what the script uses. */
function fakeFirestore(seed) {
  const collections = new Map();
  const get = (name) => {
    if (!collections.has(name)) collections.set(name, new Map());
    return collections.get(name);
  };
  for (const [name, docs] of Object.entries(seed)) {
    const col = get(name);
    for (const [id, data] of Object.entries(docs)) col.set(id, { ...data });
  }
  const docRef = (colName, id) => ({
    id,
    ref: {
      delete: async () => {
        get(colName).delete(id);
      },
    },
  });
  return {
    collection(name) {
      return {
        get: async () => ({
          docs: [...get(name).entries()].map(([id, data]) => ({
            ...docRef(name, id),
            data: () => data,
          })),
        }),
        doc(id) {
          const col = get(name);
          return {
            set: async (payload, opts) => {
              const existing = opts && opts.merge ? col.get(id) || {} : {};
              col.set(id, { ...existing, ...payload });
            },
          };
        },
      };
    },
    _dump: (name) => get(name),
  };
}

test("constants are stable", () => {
  assert.equal(PURCHASES_COLLECTION, "purchases");
  assert.equal(USERS_COLLECTION, "users");
  assert.equal(PURCHASE_STATUS_ACTIVE, "active");
  assert.equal(SUBSCRIPTION_STATUS_ACTIVE, "active");
});

test("isJunkPurchaseRow flags blank productId / token", () => {
  assert.equal(
    isJunkPurchaseRow({ productId: "", purchaseToken: "tok" }),
    true
  );
  assert.equal(
    isJunkPurchaseRow({ productId: "p", purchaseToken: "" }),
    true
  );
  assert.equal(
    isJunkPurchaseRow({ productId: "  ", purchaseToken: "  " }),
    true
  );
  assert.equal(
    isJunkPurchaseRow({ productId: "p", purchaseToken: "tok" }),
    false
  );
});

test("isActivePurchaseRow requires active status AND verifiability", () => {
  assert.equal(
    isActivePurchaseRow({ status: "active", productId: "p", purchaseToken: "t" }),
    true
  );
  assert.equal(
    isActivePurchaseRow({ status: "cancelled", productId: "p", purchaseToken: "t" }),
    false
  );
  // Junk + active is still not usable.
  assert.equal(
    isActivePurchaseRow({ status: "active", productId: "", purchaseToken: "t" }),
    false
  );
});

test("usersSyncPayload marks the account subscribed", () => {
  assert.deepEqual(usersSyncPayload(), {
    subscriptionStatus: "active",
    hasActivePurchase: true,
  });
});

test("syncPurchases deletes junk rows and repairs users/{uid}", async () => {
  const db = fakeFirestore({
    purchases: {
      // The reported junk document (empty productId).
      V8amh1XcS5YeokFLZ5v9hoRp6Oo2_: {
        uid: "userA",
        productId: "",
        purchaseToken: "tok-junk",
        status: "active",
      },
      userA_jagspoor_hunter_monthly: {
        uid: "userA",
        productId: "jagspoor_hunter_monthly",
        purchaseToken: "tok-real",
        status: "active",
      },
      // A cancelled purchase for another user — no sync.
      userB_jagspoor_hunter_monthly: {
        uid: "userB",
        productId: "jagspoor_hunter_monthly",
        purchaseToken: "tok-b",
        status: "cancelled",
      },
    },
    users: {
      userA: { firstName: "A" },
    },
  });

  const summary = await syncPurchases(db);

  assert.equal(summary.junkDeleted, 1);
  assert.deepEqual(summary.junkIds, ["V8amh1XcS5YeokFLZ5v9hoRp6Oo2_"]);
  assert.equal(summary.usersSynced, 1);
  assert.deepEqual(summary.syncedUids, ["userA"]);

  // The junk row is gone; the real row survives.
  const purchases = db._dump("purchases");
  assert.equal(purchases.has("V8amh1XcS5YeokFLZ5v9hoRp6Oo2_"), false);
  assert.equal(purchases.has("userA_jagspoor_hunter_monthly"), true);

  // users/{userA} is repaired (merge — the profile fields survive).
  const userA = db._dump("users").get("userA");
  assert.equal(userA.subscriptionStatus, "active");
  assert.equal(userA.hasActivePurchase, true);
  assert.equal(userA.firstName, "A");

  // The cancelled-only user is NOT synced.
  assert.equal(db._dump("users").has("userB"), false);
});

test("syncPurchases is a no-op on an empty collection", async () => {
  const db = fakeFirestore({ purchases: {}, users: {} });
  const summary = await syncPurchases(db);
  assert.equal(summary.junkDeleted, 0);
  assert.equal(summary.usersSynced, 0);
});
