/**
 * One-off repair for the `purchases` -> `users/{uid}` entitlement sync.
 *
 * Two jobs, both idempotent and both safe to re-run:
 *
 *   1. JUNK CLEANUP — delete every `purchases` document whose `productId` (or
 *      `purchaseToken`) is blank. Such a row can never be verified against the
 *      Google Play Developer API, so it must never grant entitlement; it is
 *      pure noise (the reported duplicate `V8amh1XcS5YeokFLZ5v9hoRp6Oo2_` is
 *      exactly this shape).
 *
 *   2. USERS SYNC — for every uid that owns an ACTIVE (verifiable) purchase
 *      row, repair `users/{uid}`:
 *        - `subscriptionStatus: 'active'`
 *        - `hasActivePurchase: true`
 *      This is the server-side counterpart of the app's
 *      `PlayPurchaseRecorder.reconcileEntitlementFromPurchases`: it heals an
 *      account whose `users/{uid}` document was never mirrored from the
 *      `purchases` collection (a dropped purchase-stream delivery, an install
 *      that predates the recorder, or a failed Cloud Function round-trip).
 *      `premiumExpiry` is deliberately NOT invented here — the app's next
 *      launch drives `validateGooglePlayPurchase`, which re-validates the Play
 *      token and writes the authoritative expiry. The flag alone is enough to
 *      unlock access because it is server-owned (`firestore.rules` freezes a
 *      client write of it).
 *
 * This module is intentionally NOT exported from `src/index.ts`: it is a
 * standalone operator script, not a deployed Cloud Function.
 *
 * Run it (requires a credentialed environment — Application Default
 * Credentials or GOOGLE_APPLICATION_CREDENTIALS pointing at a service account
 * with the Firebase Admin / `clouddatastore.user` role):
 *
 *   cd functions
 *   npm run build
 *   SYNC_CONFIRM=yes node lib/sync_purchases.js
 *
 * The SYNC_CONFIRM guard is deliberate: the script DELETES documents, so it
 * must never run implicitly (e.g. as part of a deploy).
 */

import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/** Collection holding the Google Play transaction records. */
export const PURCHASES_COLLECTION = "purchases";

/** Collection holding the user profiles. */
export const USERS_COLLECTION = "users";

/** `purchases.status` value that means "Google Play charged for this". */
export const PURCHASE_STATUS_ACTIVE = "active";

/** The canonical `users/{uid}.subscriptionStatus` value for a subscriber. */
export const SUBSCRIPTION_STATUS_ACTIVE = "active";

/** A blank product id / token makes a purchase row unverifiable. */
export function isJunkPurchaseRow(data: Record<string, unknown>): boolean {
  const productId = (data.productId ?? "").toString().trim();
  const token = (data.purchaseToken ?? "").toString().trim();
  return productId === "" || token === "";
}

/** True when the row represents an active, verifiable purchase. */
export function isActivePurchaseRow(data: Record<string, unknown>): boolean {
  if (isJunkPurchaseRow(data)) return false;
  return (data.status ?? "").toString().trim().toLowerCase() ===
    PURCHASE_STATUS_ACTIVE;
}

/**
 * The `users/{uid}` repair payload for an account with a confirmed purchase.
 */
export function usersSyncPayload(): Record<string, unknown> {
  return {
    subscriptionStatus: SUBSCRIPTION_STATUS_ACTIVE,
    hasActivePurchase: true,
  };
}

export interface SyncSummary {
  junkDeleted: number;
  usersSynced: number;
  junkIds: string[];
  syncedUids: string[];
}

/**
 * Runs the cleanup + sync against the given Firestore instance. Returns a
 * summary so the caller can log exactly what changed.
 */
export async function syncPurchases(
  db: FirebaseFirestore.Firestore
): Promise<SyncSummary> {
  const summary: SyncSummary = {
    junkDeleted: 0,
    usersSynced: 0,
    junkIds: [],
    syncedUids: [],
  };

  const snap = await db.collection(PURCHASES_COLLECTION).get();

  // uid -> true for every account with at least one usable active purchase.
  const activeUids = new Set<string>();

  for (const doc of snap.docs) {
    const data = doc.data() ?? {};
    if (isJunkPurchaseRow(data)) {
      await doc.ref.delete();
      summary.junkDeleted += 1;
      summary.junkIds.push(doc.id);
      continue;
    }
    if (isActivePurchaseRow(data)) {
      const uid = (data.uid ?? "").toString().trim();
      if (uid !== "") activeUids.add(uid);
    }
  }

  for (const uid of activeUids) {
    await db
      .collection(USERS_COLLECTION)
      .doc(uid)
      .set(usersSyncPayload(), { merge: true });
    summary.usersSynced += 1;
    summary.syncedUids.push(uid);
  }

  return summary;
}

async function main(): Promise<void> {
  if (process.env.SYNC_CONFIRM !== "yes") {
    console.error(
      "Refusing to run: this script DELETES junk purchase rows and rewrites " +
        "users/{uid} entitlement fields. Re-run with SYNC_CONFIRM=yes."
    );
    process.exitCode = 1;
    return;
  }

  const app = getApps().length > 0 ? getApps()[0] : initializeApp();
  const db = getFirestore(app);

  const summary = await syncPurchases(db);
  console.log("purchases -> users sync complete", {
    junkDeleted: summary.junkDeleted,
    junkIds: summary.junkIds,
    usersSynced: summary.usersSynced,
    syncedUids: summary.syncedUids,
  });
}

if (require.main === module) {
  main().catch((err) => {
    console.error("sync_purchases failed", err);
    process.exitCode = 1;
  });
}
