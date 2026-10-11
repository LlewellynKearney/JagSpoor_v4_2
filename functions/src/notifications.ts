import { logger } from "firebase-functions/v2";
import { onUserCreated } from "firebase-functions/v2/identity";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { firestore, auth } from "./firebase";
import { emailPass } from "./params";
import {
  notifyNewUser,
  notifyNewSubscription,
  DEFAULT_SUPPORT_EMAIL,
} from "./email";

// ────────────────────────────────────────────────────────────────────────────
// Support notifications for new users + new subscriptions
//
// Four triggers email support@jag-spoor.co.za (see email.ts for transport):
//
//   1. onUserCreate                  — Auth user().onCreate (new signup).
//   2. onSubscriptionCreate          — users/{uid}/subscriptions/{subId} onCreate.
//   3. onUserSubscriptionUpdated     — users/{uid} onUpdate where the account
//                                      becomes subscribed (subscriptionTier
//                                      goes empty → set, or isSubscribed /
//                                      isPremium / subscriptionStatus flips to
//                                      an active state).
//   4. onPricingCreated              — pricing/{docId} onCreate (fallback
//                                      billing location).
//
// Every handler is best-effort: a mail or lookup failure is logged and
// swallowed so it can never fail the Auth / Firestore write that produced it.
// ────────────────────────────────────────────────────────────────────────────

/** Subscription statuses that mean "this account is a paying subscriber". */
export const ACTIVE_SUBSCRIPTION_STATUSES = ["active", "subscribed", "premium"];

/** The recipient inbox (documented here so it is greppable in one place). */
export const SUPPORT_NOTIFICATION_EMAIL = DEFAULT_SUPPORT_EMAIL;

function normalize(value: unknown): string {
  return (value ?? "").toString().trim().toLowerCase();
}

/**
 * True when a `users/{uid}` document represents an active subscription.
 * Tolerates the multiple billing shapes the app + backend write
 * (`isSubscribed`, `isPremium`, `isPro`, or an active `subscriptionStatus`).
 */
export function isActiveSubscription(data: Record<string, unknown> | undefined): boolean {
  if (!data) return false;
  if (data.isSubscribed === true) return true;
  if (data.isPremium === true) return true;
  if (data.isPro === true) return true;
  return ACTIVE_SUBSCRIPTION_STATUSES.includes(normalize(data.subscriptionStatus));
}

/**
 * Pure decision for the users/{uid} onUpdate trigger.
 *
 * Fires when the account transitions INTO a subscribed state:
 *   • `isSubscribed` / `isPremium` / `isPro` / `subscriptionStatus` becomes
 *     active (and was not active before), OR
 *   • `subscriptionTier` changes from empty/absent to a real tier (the task's
 *     "subscriptionTier … changes from false to true" signal).
 *
 * A user who was already active before is never re-notified.
 */
export function becameSubscribed(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined
): boolean {
  if (!after) return false;
  if (isActiveSubscription(before)) return false;
  if (isActiveSubscription(after)) return true;
  const beforeTier = normalize(before?.subscriptionTier);
  const afterTier = normalize(after.subscriptionTier);
  return beforeTier === "" && afterTier !== "";
}

/** Formats a price value into a display string (R 34.99), never throwing. */
export function formatPrice(value: unknown, currencySymbol = "R"): string {
  if (value === null || value === undefined || value === "") return "";
  if (typeof value === "number" && Number.isFinite(value)) {
    return `${currencySymbol} ${value.toFixed(2)}`;
  }
  const raw = value.toString().trim();
  return raw;
}

/** Resolves the plan/tier label from a billing document. */
export function resolvePlan(data: Record<string, unknown>): string {
  for (const key of ["plan", "tier", "subscriptionTier", "productId", "product"]) {
    const value = data[key];
    if (value !== null && value !== undefined && value.toString().trim() !== "") {
      return value.toString().trim();
    }
  }
  return "";
}

/** Resolves a price from a billing document under any known alias. */
export function resolvePrice(data: Record<string, unknown>): string {
  for (const key of [
    "price",
    "amount",
    "amountZAR",
    "priceZAR",
    "monthlyPrice",
    "subscriptionPrice",
  ]) {
    if (data[key] !== undefined) {
      const formatted = formatPrice(data[key]);
      if (formatted) return formatted;
    }
  }
  return "";
}

/**
 * Best-effort user-email lookup: the `users/{uid}` document first, then the
 * Auth record. Returns "" when neither resolves.
 */
async function lookupUserEmail(uid: string, fallback = ""): Promise<string> {
  if (fallback && fallback.includes("@")) return fallback;
  if (!uid) return "";
  try {
    const snap = await firestore().collection("users").doc(uid).get();
    const email = ((snap.data() ?? {})["email"] ?? "").toString().trim();
    if (email) return email;
  } catch (err) {
    logger.warn("lookupUserEmail: users doc read failed", {
      uid,
      error: err instanceof Error ? err.message : String(err),
    });
  }
  try {
    const record = await auth().getUser(uid);
    return (record.email ?? "").toString().trim();
  } catch {
    return "";
  }
}

// ── 1. New user signup ───────────────────────────────────────────────────────

/**
 * onUserCreate
 *
 * Firebase Authentication `onUserCreated` trigger (**2nd gen**, the identity
 * provider). Fires once per newly created Auth user — email/password and
 * Google sign-in alike — and emails the support inbox with the new user's
 * email, uid, creation time and provider.
 *
 * Declares the EMAIL_PASS secret so the runtime can resolve the SMTP password
 * via `emailPass.value()` (see email.ts). The handler destructures the v1
 * `{ user }` compat shape, which the v2 identity provider also exposes.
 */
export const onUserCreate = onUserCreated(
  { region: "us-central1", secrets: [emailPass] },
  async (event) => {
    const user = event.data;
    const provider =
      user.providerData && user.providerData.length > 0
        ? user.providerData
            .map((p) => p.providerId)
            .filter((p): p is string => !!p)
            .join(", ")
        : "password";

    const createdAt = user.metadata?.creationTime
      ? new Date(user.metadata.creationTime)
      : new Date();

    try {
      await notifyNewUser({
        uid: user.uid,
        email: (user.email ?? "").toString(),
        displayName: (user.displayName ?? "").toString(),
        provider,
        createdAt,
      });
    } catch (err) {
      logger.error("onUserCreate: notification failed", {
        uid: user.uid,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);

// ── 2. users/{uid}/subscriptions/{subId} onCreate ────────────────────────────

/**
 * onSubscriptionCreate
 *
 * Firestore trigger (v2) on `users/{userId}/subscriptions/{subId}` — the
 * per-user subscriptions subcollection billing location. Emails the support
 * inbox with the user's email, uid, plan, price and the full document data.
 */
export const onSubscriptionCreate = onDocumentCreated(
  {
    document: "users/{userId}/subscriptions/{subId}",
    region: "us-central1",
    secrets: [emailPass],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = (snap.data() ?? {}) as Record<string, unknown>;
    const uid = event.params.userId;
    const docPath = `users/${uid}/subscriptions/${event.params.subId}`;

    try {
      const userEmail = await lookupUserEmail(uid, (data.email ?? "").toString());
      await notifyNewSubscription({
        uid,
        userEmail,
        plan: resolvePlan(data),
        price: resolvePrice(data),
        source: "users/{uid}/subscriptions onCreate",
        docPath,
        data,
      });
    } catch (err) {
      logger.error("onSubscriptionCreate: notification failed", {
        uid,
        docPath,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);

// ── 3. users/{uid} onUpdate (account becomes subscribed) ─────────────────────

/**
 * onUserSubscriptionUpdated
 *
 * Firestore trigger (v2) on `users/{userId}`. Emails the support inbox the
 * first time the account becomes subscribed — `subscriptionTier` goes from
 * empty to set, or `isSubscribed` / `isPremium` / `subscriptionStatus` flips
 * to an active state.
 *
 * A `supportSubscriptionNotified` marker is stamped onto the user document
 * after the first notification so a follow-on write (e.g. the purchase
 * recorder confirming `subscriptionStatus: 'active'` right after the tier was
 * set) cannot send a duplicate email.
 */
export const onUserSubscriptionUpdated = onDocumentUpdated(
  { document: "users/{userId}", region: "us-central1", secrets: [emailPass] },
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data() as Record<string, unknown> | undefined;
    const after = change.after.data() as Record<string, unknown> | undefined;
    if (!after) return;

    if (!becameSubscribed(before, after)) return;
    if (after.supportSubscriptionNotified === true) return;

    const uid = event.params.userId;
    try {
      const userEmail = await lookupUserEmail(uid, (after.email ?? "").toString());
      const result = await notifyNewSubscription({
        uid,
        userEmail,
        plan: resolvePlan(after),
        price: resolvePrice(after),
        source: "users/{uid} upgrade",
        docPath: `users/${uid}`,
        data: after,
      });
      if (result.sent) {
        // Best-effort dedupe marker (Admin SDK — bypasses the frozen-field
        // rules). A failure here only risks a duplicate email, never data loss.
        try {
          await firestore()
            .collection("users")
            .doc(uid)
            .set({ supportSubscriptionNotified: true }, { merge: true });
        } catch (err) {
          logger.warn("onUserSubscriptionUpdated: could not stamp dedupe marker", {
            uid,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    } catch (err) {
      logger.error("onUserSubscriptionUpdated: notification failed", {
        uid,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);

// ── 4. pricing/{docId} onCreate (fallback billing location) ──────────────────

/**
 * onPricingCreated
 *
 * Firestore trigger (v2) on the top-level `pricing/{docId}` collection — the
 * fallback billing location. Emails the support inbox with the plan, price and
 * full document data (plus the uid when the document carries one).
 */
export const onPricingCreated = onDocumentCreated(
  { document: "pricing/{docId}", region: "us-central1", secrets: [emailPass] },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = (snap.data() ?? {}) as Record<string, unknown>;
    const docId = event.params.docId;
    const uid = (data.uid ?? data.userId ?? data.user_id ?? "").toString().trim();

    try {
      const userEmail = uid
        ? await lookupUserEmail(uid, (data.email ?? "").toString())
        : (data.email ?? "").toString().trim();
      await notifyNewSubscription({
        uid: uid || "(not specified)",
        userEmail,
        plan: resolvePlan(data),
        price: resolvePrice(data),
        source: "pricing onCreate (fallback)",
        docPath: `pricing/${docId}`,
        data,
      });
    } catch (err) {
      logger.error("onPricingCreated: notification failed", {
        docId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);
