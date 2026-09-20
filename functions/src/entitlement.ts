import { logger } from "firebase-functions/v2";
import { onCall, HttpsError, onRequest } from "firebase-functions/v2/https";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { FieldValue } from "firebase-admin/firestore";
import { createHash } from "crypto";
import { google } from "googleapis";
import type { Request, Response } from "express";
import { firestore } from "./firebase";

// ────────────────────────────────────────────────────────────────────────────
// Entitlement model (secure, server-authoritative)
//
// Premium fields on `users/{uid}` (`isPremium`, `premiumExpiry`,
// `subscriptionSource`, `subscriptionProduct`, `subscriptionPlayPurchaseToken`,
// `payfastPaymentId`, `entitlementUpdatedAt`) are ONLY ever written by the
// Cloud Functions below. The Firestore rules forbid clients from writing
// these fields; the rules give users read access to their own document so the
// app can render the entitlement banner / gating.
//
// A dedicated `entitlements/{uid}` document mirrors the same state so the
// server owns a single, auditable source of truth that is not mixed with the
// user-editable profile document.
// ────────────────────────────────────────────────────────────────────────────

export const ENTITLEMENTS_COLLECTION = "entitlements";
export const SUBSCRIPTION_SOURCE_GOOGLE_PLAY = "google_play";
export const SUBSCRIPTION_SOURCE_PAYFAST = "payfast";
export const SUBSCRIPTION_SOURCE_TRIAL = "trial";

export const PACKAGE_NAME = "za.co.jagspoor.app";

/** Monthly Google Play subscription products (authoritative package id). */
export const GOOGLE_PLAY_PRODUCTS = [
  "jagspoor_hunter_monthly",
  "jagspoor_outfitter_monthly",
] as const;

/** Subscription source type stored on the entitlement. */
export type SubscriptionSource = string;

export interface WriteEntitlementInput {
  isPremium: boolean;
  premiumExpiry: Date | null;
  subscriptionSource: SubscriptionSource;
  subscriptionProduct?: string;
  subscriptionPlayPurchaseToken?: string;
  payfastPaymentId?: string;
  subscriptionStatus?: string;
  subscriptionTier?: string;
  subscriptionRenewalDate?: Date | null;
}

/**
 * Writes the premium entitlement onto `users/{uid}` AND mirrors it onto
 * `entitlements/{uid}`. Only Cloud Functions call this - never the client.
 */
export async function writeEntitlement(
  uid: string,
  fields: WriteEntitlementInput
): Promise<void> {
  if (!uid) {
    throw new Error("writeEntitlement requires a non-empty uid");
  }
  const now = FieldValue.serverTimestamp();
  const userPayload: Record<string, unknown> = {
    isPremium: fields.isPremium,
    premiumExpiry: fields.premiumExpiry,
    subscriptionSource: fields.subscriptionSource,
    entitlementUpdatedAt: now,
  };
  if (fields.subscriptionProduct) {
    userPayload.subscriptionProduct = fields.subscriptionProduct;
  }
  if (fields.subscriptionPlayPurchaseToken) {
    userPayload.subscriptionPlayPurchaseToken = fields.subscriptionPlayPurchaseToken;
  }
  if (fields.payfastPaymentId) {
    userPayload.payfastPaymentId = fields.payfastPaymentId;
  }
  if (fields.subscriptionStatus) {
    userPayload.subscriptionStatus = fields.subscriptionStatus;
  }
  if (fields.subscriptionTier) {
    userPayload.subscriptionTier = fields.subscriptionTier;
  }
  if (fields.subscriptionRenewalDate) {
    userPayload.subscriptionRenewalDate = fields.subscriptionRenewalDate;
  }

  const entitlementPayload: Record<string, unknown> = {
    userId: uid,
    isPremium: fields.isPremium,
    premiumExpiry: fields.premiumExpiry,
    subscriptionSource: fields.subscriptionSource,
    updatedAt: now,
  };
  if (fields.subscriptionProduct) {
    entitlementPayload.subscriptionProduct = fields.subscriptionProduct;
  }
  if (fields.payfastPaymentId) {
    entitlementPayload.payfastPaymentId = fields.payfastPaymentId;
  }

  await firestore().collection("users").doc(uid).set(userPayload, {
    merge: true,
  });
  await firestore().collection(ENTITLEMENTS_COLLECTION).doc(uid).set(
    entitlementPayload,
    { merge: true }
  );
  logger.info("entitlement written", {
    uid,
    isPremium: fields.isPremium,
    source: fields.subscriptionSource,
  });
}
// ────────────────────────────────────────────────────────────────────────────
// Google Play Developer API validation
// ────────────────────────────────────────────────────────────────────────────

/**
 * Resolves an authenticated androidpublisher API client. On Google Cloud /
 * Cloud Functions the default service account is used. A service-account key
 * can also be provided via `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (base64).
 */
function androidPublisher() {
  const serviceAccountB64 = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
  const authOptions = serviceAccountB64
    ? { credentials: JSON.parse(Buffer.from(serviceAccountB64, "base64").toString("utf8")) }
    : undefined;
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    ...authOptions,
  });
  return google.androidpublisher({ version: "v3", auth });
}

/** Response shape of a successful Google Play subscriptionv2 purchase query. */
export interface PlayPurchaseInfo {
  productId: string;
  expiryTimeMs: number | null;
  state: number;
  autoRenewing: boolean;
  cancelReason: number | null;
  countryCode?: string;
}

/**
 * Queries the Google Play Developer API for a subscription purchase token.
 *
 * The googleapis androidpublisher `purchases.subscriptionsv2.get` returns a
 * rich SubscriptionPurchaseV2 object (see
 * https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2).
 * We extract the subset the entitlement + RTDN handler needs. On any API error
 * the error is re-thrown so the caller maps it to a user-facing message.
 */
export async function getPlayPurchaseInfo(
  packageName: string,
  productId: string,
  purchaseToken: string
): Promise<PlayPurchaseInfo> {
  const api = androidPublisher();
  try {
    const res = await api.purchases.subscriptionsv2.get({
      packageName,
      token: purchaseToken,
    });
    const data = res.data ?? {};
    const lineItems = Array.isArray(data.lineItems) ? data.lineItems : [];
    const lineItem = lineItems[0] ?? {};
    const expiryTimeRaw =
      lineItem.expiryTime != null ? String(lineItem.expiryTime) : null;
    const expiryTimeMs = expiryTimeRaw != null ? Date.parse(expiryTimeRaw) : null;
    const state = data.subscriptionState as string | undefined;
    const active =
      state === "SUBSCRIPTION_STATE_ACTIVE" ||
      state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" ||
      state === "SUBSCRIPTION_STATE_ON_HOLD";
    const cancelled =
      state === "SUBSCRIPTION_STATE_CANCELED" ||
      state === "SUBSCRIPTION_STATE_EXPIRED";

    return {
      productId,
      expiryTimeMs: expiryTimeMs != null && !Number.isNaN(expiryTimeMs) ? expiryTimeMs : null,
      state: active ? 1 : cancelled ? 2 : 0,
      autoRenewing: active,
      cancelReason: cancelled ? 1 : null,
      countryCode: "",
    };
  } catch (err) {
    logger.error("getPlayPurchaseInfo failed", { err });
    throw err;
  }
}

// ────────────────────────────────────────────────────────────────────────────
// validateGooglePlayPurchase - callable invoked by the Flutter app after a
// successful in_app_purchase. This is the SERVER-SIDE receipt validation:
// the client never sets isPremium itself.
// ────────────────────────────────────────────────────────────────────────────

interface ValidatePlayInput {
  purchaseToken?: string;
  productId?: string;
  packageName?: string;
}

/** Maps a Google Play subscription state to a human-readable error code. */
export function playStateError(state: number): string | null {
  if (state === 2) return "The subscription has expired or was cancelled.";
  if (state === 0) return "The purchase could not be verified with Google Play.";
  return null;
}

export const validateGooglePlayPurchase = onCall(
  { region: "us-central1", maxInstances: 20 },
  async (req: { auth?: { uid?: string | null } | null; data?: unknown }) => {
    const uid = req.auth?.uid ?? null;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in to verify a purchase.");
    }

    const input = (req.data ?? {}) as ValidatePlayInput;
    const purchaseToken = (input.purchaseToken ?? "").trim();
    const productId = (input.productId ?? "").trim();
    const packageName = (input.packageName ?? PACKAGE_NAME).trim();

    if (!purchaseToken) {
      throw new HttpsError("invalid-argument", "A purchase token is required.");
    }
    if (productId && !GOOGLE_PLAY_PRODUCTS.includes(productId as never)) {
      throw new HttpsError("invalid-argument", `Unknown product id '${productId}'.`);
    }

    let info: PlayPurchaseInfo;
    try {
      info = await getPlayPurchaseInfo(packageName, productId, purchaseToken);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      throw new HttpsError("unavailable", `Google Play verification failed: ${message}`);
    }

    const stateError = playStateError(info.state);
    if (stateError != null) {
      throw new HttpsError("failed-precondition", stateError);
    }

    const expiryMs =
      info.expiryTimeMs != null && info.expiryTimeMs > Date.now()
        ? info.expiryTimeMs
        : Date.now() + 31 * 24 * 60 * 60 * 1000;
    if (expiryMs <= Date.now()) {
      throw new HttpsError("failed-precondition", "This subscription has already expired.");
    }

    const premiumExpiry = new Date(expiryMs);
    const tier = productId === "jagspoor_outfitter_monthly" ? "outfitter" : "hunter";

    await writeEntitlement(uid, {
      isPremium: true,
      premiumExpiry,
      subscriptionSource: SUBSCRIPTION_SOURCE_GOOGLE_PLAY,
      subscriptionProduct: productId,
      subscriptionPlayPurchaseToken: purchaseToken,
      subscriptionStatus: "active",
      subscriptionTier: tier,
      subscriptionRenewalDate: premiumExpiry,
    });

    return {
      isPremium: true,
      premiumExpiry: premiumExpiry.toISOString(),
      subscriptionSource: SUBSCRIPTION_SOURCE_GOOGLE_PLAY,
      subscriptionProduct: productId,
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// onGooglePlayRTDN - Pub/Sub handler for Real-Time Developer Notifications
// (cancellations, refunds, expirations) received from the Play Developer
// Console. Revokes the entitlement when the subscription is no longer active.
// Wire a Pub/Sub topic in the Play Console -> Monetization setup -> Real-time
// developer notifications (topic receives from `androidpublisher.googleapis.com`,
// event `SUBSCRIPTION_NOTIFICATION`).
// ────────────────────────────────────────────────────────────────────────────

export const GOOGLE_PLAY_RTDN_TOPIC = "jagspoor-play-rtdn";

interface RtdnMessage {
  data?: string;
  attributes?: Record<string, string>;
}

interface SubscriptionNotificationPayload {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: {
    notificationType?: number;
    purchaseToken?: string;
    subscriptionId?: string;
  };
}

export function parseRtdnMessage(data: string): {
  notificationType: number;
  purchaseToken: string;
  subscriptionId: string;
} | null {
  try {
    const decoded = JSON.parse(
      Buffer.from(data, "base64").toString("utf8")
    ) as SubscriptionNotificationPayload;
    const sub = decoded.subscriptionNotification ?? {};
    const notificationType = sub.notificationType ?? -1;
    const purchaseToken = sub.purchaseToken ?? "";
    const subscriptionId = sub.subscriptionId ?? "";
    if (!purchaseToken || !subscriptionId) {
      return null;
    }
    return { notificationType, purchaseToken, subscriptionId };
  } catch (err) {
    logger.error("parseRtdnMessage failed", { err });
    return null;
  }
}

/**
 * Google Play RTDN notificationType codes that mean the user no longer has an
 * active, paid subscription:
 *   - 9  PRODUCT_NOT_AVAILABLE
 *   - 12 REVOKED (refund)
 *   - 13 EXPIRED
 * Types 3 (CANCELED) keep access until the paid-through date, so we do not
 * revoke immediately - premiumExpiry stays and the client's own expiry check
 * handles the end of the paid period.
 */
export const RTDN_REVOKE_TYPES = new Set([12, 13, 9]);

export function isRevocation(notificationType: number): boolean {
  return RTDN_REVOKE_TYPES.has(notificationType);
}

/**
 * Pub/Sub message handler. Because the payload only carries the purchase
 * token + subscription id (not the user uid), we resolve the user by
 * searching `users` for the matching `subscriptionPlayPurchaseToken`.
 */
export const onGooglePlayRTDN = onMessagePublished(
  { topic: GOOGLE_PLAY_RTDN_TOPIC, region: "us-central1" },
  async (event) => {
    const message = (event.data.message ?? {}) as RtdnMessage;
    const data = message.data ?? "";
    const parsed = parseRtdnMessage(data);
    if (!parsed) {
      logger.warn("onGooglePlayRTDN: unparseable message", { data });
      return;
    }
    const { notificationType, purchaseToken, subscriptionId } = parsed;

    if (!isRevocation(notificationType)) {
      logger.info("onGooglePlayRTDN: non-revocation event ignored", {
        notificationType,
      });
      return;
    }

    const userSnap = await firestore()
      .collection("users")
      .where("subscriptionPlayPurchaseToken", "==", purchaseToken)
      .limit(1)
      .get();
    if (userSnap.empty) {
      logger.warn("onGooglePlayRTDN: no user with matching purchase token", {
        purchaseToken,
      });
      return;
    }
    const uid = userSnap.docs[0].id;
    const current = userSnap.docs[0].data();
    if (
      current.subscriptionSource === SUBSCRIPTION_SOURCE_GOOGLE_PLAY &&
      (subscriptionId === "" || current.subscriptionProduct === subscriptionId)
    ) {
      await writeEntitlement(uid, {
        isPremium: false,
        premiumExpiry: null,
        subscriptionSource: SUBSCRIPTION_SOURCE_GOOGLE_PLAY,
        subscriptionProduct: subscriptionId,
        subscriptionStatus: "cancelled",
        subscriptionTier:
          (current.subscriptionTier as string | undefined) ?? undefined,
      });
      logger.info("onGooglePlayRTDN: entitlement revoked", {
        uid,
        notificationType,
      });
    }
  }
);

// ────────────────────────────────────────────────────────────────────────────
// payfastITN - server-side (website-only) Instant Transaction Notification
// webhook. JagSpoor deliberately does NOT embed PayFast in the Flutter app.
// Afrihost-hosted https://jagspoor.co.za/pricing calls PayFast; PayFast then
// POSTs the ITN to this endpoint. This function verifies the signature,
// validates the amount against the published plan, looks the user up by
// email, and grants the premium entitlement.
// ────────────────────────────────────────────────────────────────────────────

/** PayFast plans (ZAR) the ITN will accept. */
export const PAYFAST_PLANS: Record<string, number> = {
  monthly: 199, // R199 / month
  yearly: 399, // R399 / year (documented; adjust to the actual plan)
};

/**
 * Validates the PayFast ITN MD5 signature. The signature source is the
 * sorted param=value pairs (excluding `signature`/`passphrase`) with values
 * URL-decoded, joined by '&', then appended with '&passphrase=<passphrase>'.
 */
export function payfastSignatureMatches(
  params: Record<string, string>,
  passphrase: string
): boolean {
  const entries = Object.entries(params)
    .filter(([k]) => k !== "signature" && k !== "passphrase")
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${k}=${decodeURIComponent(v)}`)
    .join("&");
  const source = `${entries}&passphrase=${passphrase}`;
  const computed = createHash("md5").update(source).digest("hex");
  const provided = (params["signature"] ?? "").toLowerCase();
  return computed === provided;
}

/** Stable, opaque PayFast payment reference derived from email + payment id. */
export function payfastPaymentIdFor(
  email: string | undefined,
  merchantPaymentId: string | undefined
): string {
  const normalized = (email ?? "").trim().toLowerCase();
  const source = normalized || (merchantPaymentId ?? "").trim();
  return createHash("sha256").update(source).digest("hex").slice(0, 24);
}

/**
 * Pure helper: resolves the entitlement length + accepted amount from the
 * merchant payment id, and validates the ITN amount against the plan price.
 */
export function paymentPlanFrom(
  merchantPaymentId: string,
  amountZar: number
): { plan: "monthly" | "yearly"; months: number } | null {
  const normalized = (merchantPaymentId ?? "").toLowerCase();
  const yearly = normalized.includes("year") || normalized.includes("annual");
  const plan = yearly ? "yearly" : "monthly";
  const expected = PAYFAST_PLANS[plan];
  if (Math.abs(amountZar - expected) > 0.01) {
    return null;
  }
  return { plan, months: plan === "yearly" ? 12 : 1 };
}

interface PayfastItnBody {
  [key: string]: string;
}

/** PayFast ITN endpoint (website-only, public invoker, POST from PayFast). */
export const payfastITN = onRequest(
  { region: "us-central1", maxInstances: 20 },
  async (req: Request, res: Response) => {
    const method = (req.method ?? "GET").toUpperCase();
    if (method === "GET") {
      res.status(200).send("OK (ITN endpoint - POST from PayFast expected)");
      return;
    }
    if (method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const body = (req.body ?? {}) as PayfastItnBody;
    const passphrase = process.env.PAYFAST_PASSPHRASE ?? "";
    if (!passphrase) {
      logger.error("payfastITN: PAYFAST_PASSPHRASE not configured");
      res.status(500).send("ITN not configured - missing passphrase");
      return;
    }

    if (!payfastSignatureMatches(body, passphrase)) {
      logger.warn("payfastITN: signature mismatch");
      res.status(403).send("Signature mismatch");
      return;
    }

    const paymentStatus = (body["payment_status"] ?? "").toUpperCase();
    if (paymentStatus !== "COMPLETE") {
      res
        .status(200)
        .send("OK (no entitlement for status " + paymentStatus + ")");
      return;
    }

    const amount = parseFloat(body["amount_gross"] ?? "");
    const mPaymentId = body["m_payment_id"] ?? body["custom_str1"] ?? "";
    const email = body["email_address"] ?? body["custom_str2"] ?? "";
    if (Number.isNaN(amount) || !mPaymentId) {
      res.status(400).send("Invalid amount or payment id");
      return;
    }

    const plan = paymentPlanFrom(mPaymentId, amount);
    if (!plan) {
      logger.warn("payfastITN: amount/plan mismatch", { amount, mPaymentId });
      res.status(400).send("Amount does not match a known plan");
      return;
    }

    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail) {
      res.status(400).send("No billing email provided");
      return;
    }

    const userSnap = await firestore()
      .collection("users")
      .where("email", "==", normalizedEmail)
      .limit(1)
      .get();
    if (userSnap.empty) {
      logger.warn("payfastITN: no user for billing email", { email });
      res.status(404).send("No user found for the billing email");
      return;
    }
    const uid = userSnap.docs[0].id;
    const premiumExpiry = new Date(
      Date.now() + plan.months * 30 * 24 * 60 * 60 * 1000
    );
    const payfastPaymentId = payfastPaymentIdFor(email, mPaymentId);

    await writeEntitlement(uid, {
      isPremium: true,
      premiumExpiry,
      subscriptionSource: SUBSCRIPTION_SOURCE_PAYFAST,
      subscriptionProduct: plan.plan,
      payfastPaymentId,
      subscriptionStatus: "active",
      subscriptionTier: plan.plan === "yearly" ? "outfitter" : "hunter",
      subscriptionRenewalDate: premiumExpiry,
    });

    logger.info("payfastITN: entitlement granted", {
      uid,
      plan: plan.plan,
      months: plan.months,
      payfastPaymentId,
    });
    res.status(200).send("OK");
  }
);
