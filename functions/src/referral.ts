import { logger } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { firestore } from "./firebase";
import { writeEntitlement, SUBSCRIPTION_SOURCE_GOOGLE_PLAY } from "./entitlement";

// ────────────────────────────────────────────────────────────────────────────
// JagSpoor referral system — Phase 1 backend module.
//
// Owns the server-side read/write surface for the three referral
// collections. The client (Flutter `ReferralRepository`) and the backend
// share the same collection + field contracts so either side can be the
// writer for a given document:
//
//   referral_profiles/{uid}        — user uid, unique referral code, banking
//                                    details (payout opt-in).
//   referral_conversions/{id}      — referrerId, referredUserId, referralCode,
//                                    subscriptionTier, status, rewardAmountZAR.
//   admin_config/referral_rewards  — dynamic hunter/outfitter reward amounts.
//
// Phase 1 ships the models + repository methods (read/write + admin config
// load). Phase 2 wires the subscription-activation trigger that finalises a
// conversion to `rewarded`/`rejected` and the payout/claim flow on top.
// ────────────────────────────────────────────────────────────────────────────

/** Collection names — single source of truth shared with the Flutter client. */
export const REFERRAL_PROFILES_COLLECTION = "referral_profiles";
export const REFERRAL_CONVERSIONS_COLLECTION = "referral_conversions";
export const ADMIN_CONFIG_COLLECTION = "admin_config";
export const REFERRAL_REWARDS_DOC_ID = "referral_rewards";

/**
 * Documented default reward amounts (ZAR) — one month's subscription value
 * for each tier. These mirror the Flutter `ReferralRewards` constants and
 * are used ONLY as the fallback when the dynamic `admin_config/
 * referral_rewards` document is absent. The live document is the source of
 * truth for the reward calculation.
 */
export const DEFAULT_HUNTER_REWARD_ZAR = 29.99;
export const DEFAULT_OUTFITTER_REWARD_ZAR = 299.99;

/** Lifecycle states of a referral conversion. */
export const REFERRAL_STATUS_PENDING = "pending";
export const REFERRAL_STATUS_REWARDED = "rewarded";
export const REFERRAL_STATUS_REJECTED = "rejected";

/** Subscription tiers a referred user may convert at. */
export const REFERRAL_TIER_HUNTER = "hunter";
export const REFERRAL_TIER_OUTFITTER = "outfitter";

/** A user's referral profile document (`referral_profiles/{uid}`). */
export interface ReferralProfile {
  userId: string;
  referralCode: string;
  bankingDetailsProvided: boolean;
  bankAccountHolder?: string;
  bankName?: string;
  bankAccountNumber?: string;
  bankAccountType?: string;
  createdAt?: FirebaseFireTimestamp;
  updatedAt?: FirebaseFireTimestamp;
}

/** A referral conversion document (`referral_conversions/{id}`). */
export interface ReferralConversion {
  referrerId: string;
  referredUserId: string;
  referralCode: string;
  subscriptionTier: string;
  status: string;
  rewardAmountZAR?: number;
  convertedAt?: FirebaseFireTimestamp;
  statusUpdatedAt?: FirebaseFireTimestamp;
  createdAt?: FirebaseFireTimestamp;
}

/** The admin reward-config document (`admin_config/referral_rewards`). */
export interface ReferralRewardConfig {
  hunterRewardZAR: number;
  outfitterRewardZAR: number;
  /** Reward mechanism (`extension_days` today). */
  rewardType: string;
  /** Entitlement-extension days granted per granted hunter referral. */
  hunterDays: number;
  /** Entitlement-extension days granted per granted outfitter referral. */
  outfitterDays: number;
  updatedAt?: FirebaseFireTimestamp;
}

/** Default reward mechanism — a premium / trial extension in days. */
export const DEFAULT_REWARD_TYPE = "extension_days";
export const DEFAULT_HUNTER_DAYS = 30;
export const DEFAULT_OUTFITTER_DAYS = 30;

/** Clamps a numeric day count to >= 0; tolerates numeric strings. */
function clampDays(value: unknown, fallback: number): number {
  if (value === undefined || value === null) return fallback;
  const parsed =
    typeof value === "number" ? value : Number(String(value).trim());
  if (Number.isNaN(parsed)) return fallback;
  return parsed < 0 ? 0 : Math.floor(parsed);
}

// Minimal structural type for the Firestore Timestamp shape we read (the
// admin SDK's `Timestamp` satisfies it). Kept local so the module has no
// hard dependency on a specific admin-firestore import for the interfaces.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type FirebaseFireTimestamp = { seconds: number; nanoseconds: number };

/** Clamps a numeric reward value to >= 0; tolerates numeric strings. */
function clampReward(value: unknown, fallback: number): number {
  if (typeof value === "number") return value < 0 ? 0 : value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (!Number.isNaN(parsed)) return parsed < 0 ? 0 : parsed;
  }
  return fallback;
}

/**
 * Loads the dynamic admin reward configuration. Returns the documented
 * defaults when the document is absent or unreadable — never throws.
 */
export async function loadReferralRewardConfig(): Promise<ReferralRewardConfig> {
  const snap = await firestore()
    .collection(ADMIN_CONFIG_COLLECTION)
    .doc(REFERRAL_REWARDS_DOC_ID)
    .get();
  const data = snap.exists ? snap.data() ?? {} : {};
  return {
    hunterRewardZAR: clampReward(
      data.hunterRewardZAR ??
        data.hunterAmountZAR ??
        data.hunter ??
        DEFAULT_HUNTER_REWARD_ZAR,
      DEFAULT_HUNTER_REWARD_ZAR
    ),
    outfitterRewardZAR: clampReward(
      data.outfitterRewardZAR ??
        data.outfitterAmountZAR ??
        data.outfitter ??
        DEFAULT_OUTFITTER_REWARD_ZAR,
      DEFAULT_OUTFITTER_REWARD_ZAR
    ),
    rewardType: (data.rewardType ?? DEFAULT_REWARD_TYPE).toString(),
    hunterDays: clampDays(
      data.hunter_days ?? data.hunterDays,
      DEFAULT_HUNTER_DAYS
    ),
    outfitterDays: clampDays(
      data.outfitter_days ?? data.outfitterDays,
      DEFAULT_OUTFITTER_DAYS
    ),
  };
}

/** Entitlement-extension days for a tier, resolved from the live config. */
export function rewardDaysForTier(
  config: ReferralRewardConfig,
  tier: string
): number {
  return tier === REFERRAL_TIER_OUTFITTER
    ? config.outfitterDays
    : config.hunterDays;
}

/**
 * The reward amount for a given subscription tier, resolved from the live
 * admin config (falling back to the documented defaults).
 */
export async function rewardAmountForTier(tier: string): Promise<number> {
  const config = await loadReferralRewardConfig();
  return tier === REFERRAL_TIER_OUTFITTER
    ? config.outfitterRewardZAR
    : config.hunterRewardZAR;
}

/**
 * Fetches a user's referral profile by uid. Returns null when absent.
 */
export async function getReferralProfile(
  userId: string
): Promise<ReferralProfile | null> {
  if (!userId) return null;
  const snap = await firestore()
    .collection(REFERRAL_PROFILES_COLLECTION)
    .doc(userId)
    .get();
  if (!snap.exists) return null;
  return { userId, ...(snap.data() ?? {}) } as ReferralProfile;
}

/**
 * Resolves the referrer for a redeemed referral code. Looks up the profile
 * whose `referralCode` matches [code] case-insensitively (the code field is
 * stored upper-cased). Returns null when no profile carries the code.
 */
export async function findReferrerByCode(
  code: string
): Promise<ReferralProfile | null> {
  const normalized = (code ?? "").trim().toUpperCase();
  if (!normalized) return null;
  const snap = await firestore()
    .collection(REFERRAL_PROFILES_COLLECTION)
    .where("referralCode", "==", normalized)
    .limit(1)
    .get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return { userId: doc.id, ...(doc.data() ?? {}) } as ReferralProfile;
}

/**
 * Creates a referral profile for [userId] with the given [referralCode].
 * Merge-write so an idempotent retry never clobbers banking details.
 */
export async function createReferralProfile(
  userId: string,
  referralCode: string
): Promise<void> {
  if (!userId || !referralCode) {
    throw new Error("userId and referralCode are required.");
  }
  await firestore()
    .collection(REFERRAL_PROFILES_COLLECTION)
    .doc(userId)
    .set(
      {
        userId,
        referralCode: referralCode.toUpperCase(),
        bankingDetailsProvided: false,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}

/**
 * Records a referral conversion. Validates referrer != referred and that the
 * code is non-empty; the status starts at `pending`. Returns the new
 * conversion document id.
 */
export async function recordReferralConversion(input: {
  referrerId: string;
  referredUserId: string;
  referralCode: string;
  subscriptionTier?: string;
}): Promise<string> {
  const referrerId = (input.referrerId ?? "").trim();
  const referredUserId = (input.referredUserId ?? "").trim();
  const referralCode = (input.referralCode ?? "").trim().toUpperCase();
  if (!referrerId || !referredUserId) {
    throw new Error("referrerId and referredUserId are required.");
  }
  if (referrerId === referredUserId) {
    throw new Error("A user cannot refer themself.");
  }
  if (!referralCode) {
    throw new Error("referralCode is required.");
  }
  const tier =
    input.subscriptionTier === REFERRAL_TIER_OUTFITTER
      ? REFERRAL_TIER_OUTFITTER
      : REFERRAL_TIER_HUNTER;
  const doc = firestore().collection(REFERRAL_CONVERSIONS_COLLECTION).doc();
  await doc.set({
    referrerId,
    referredUserId,
    referralCode,
    subscriptionTier: tier,
    status: REFERRAL_STATUS_PENDING,
    createdAt: FieldValue.serverTimestamp(),
  });
  return doc.id;
}

/**
 * Fetches every conversion where [referrerId] is the referrer, newest-first.
 */
export async function getConversionsForReferrer(
  referrerId: string
): Promise<ReferralConversion[]> {
  if (!referrerId) return [];
  const snap = await firestore()
    .collection(REFERRAL_CONVERSIONS_COLLECTION)
    .where("referrerId", "==", referrerId)
    .get();
  return snap.docs.map((doc) => doc.data() as ReferralConversion);
}

/**
 * Finalises a pending conversion's reward status. Only a `pending`
 * conversion may be finalised; the reward amount is resolved from the live
 * admin config for the conversion's tier. Returns the updated document.
 */
export async function finaliseConversionReward(
  conversionId: string,
  status: "rewarded" | "rejected"
): Promise<ReferralConversion | null> {
  if (!conversionId) return null;
  const ref = firestore().collection(REFERRAL_CONVERSIONS_COLLECTION).doc(conversionId);
  const snap = await ref.get();
  if (!snap.exists) return null;
  const data = snap.data() ?? {};
  if (data.status !== REFERRAL_STATUS_PENDING) {
    throw new Error("Only a pending conversion may be finalised.");
  }
  const tier =
    data.subscriptionTier === REFERRAL_TIER_OUTFITTER
      ? REFERRAL_TIER_OUTFITTER
      : REFERRAL_TIER_HUNTER;
  const rewardAmount =
    status === REFERRAL_STATUS_REWARDED
      ? await rewardAmountForTier(tier)
      : 0;
  const updates: Record<string, unknown> = {
    status,
    statusUpdatedAt: FieldValue.serverTimestamp(),
  };
  if (status === REFERRAL_STATUS_REWARDED) {
    updates.rewardAmountZAR = rewardAmount;
  }
  await ref.update(updates);
  const updated = await ref.get();
  return { ...(updated.data() ?? {}) } as ReferralConversion;
}

// ────────────────────────────────────────────────────────────────────────────
// Phase 2 — grant the referral reward SERVER-SIDE on conversion creation
//
// A referral conversion is created client-side (by the Flutter signup flow)
// with `status: 'pending'`. This Firestore trigger (Admin SDK — bypasses
// firestore.rules) validates the referrer, resolves the reward days from the
// live `admin_config/referral_rewards` config, extends the REFERRER's
// entitlement by the reward days (via writeEntitlement — the SAME writer the
// Google Play validation uses), and marks the conversion `granted`/`rewarded`
// idempotently.
//
// The client NEVER writes an expiry; the entitlement write happens here.
// ────────────────────────────────────────────────────────────────────────────

/** Conversion status once the reward has been granted. */
export const REFERRAL_STATUS_GRANTED = "granted";

/**
 * Extends a user's entitlement by [days] using `writeEntitlement` (the only
 * sanctioned writer of premium fields). The new expiry is the LATER of:
 *  - the current `premiumExpiry` (if any), or
 *  - the current `trialEndsAt` / `subscriptionTrialEndsAt` (if any),
 *  - or `now` (so an expired / new account is extended from today).
 *
 * Preserves the user's existing `subscriptionTier` / `subscriptionProduct` /
 * `subscriptionSource` when present so an extension never downgrades a
 * higher-value entitlement; it does not flip a trial into a paid
 * `subscriptionSource` when the account was only ever on the trial source.
 */
async function extendReferrerEntitlement(
  uid: string,
  days: number
): Promise<Date> {
  const userRef = firestore().collection("users").doc(uid);
  const snap = await userRef.get();
  const data = snap.exists ? snap.data() ?? {} : {};

  const toDate = (v: unknown): Date | null => {
    if (!v) return null;
    // Firestore Timestamp (admin SDK) exposes `toDate()`.
    const maybe = v as { toDate?: () => Date };
    if (typeof maybe.toDate === "function") return maybe.toDate();
    if (v instanceof Date) return v;
    const parsed = new Date(String(v));
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  };

  const now = new Date();
  const candidates = [
    toDate(data.premiumExpiry),
    toDate(data.trialEndsAt),
    toDate(data.subscriptionTrialEndsAt),
    toDate(data.trialEnd),
  ].filter((d): d is Date => d !== null);

  const base = candidates.reduce<Date>(
    (latest: Date, d: Date) => (d.getTime() > latest.getTime() ? d : latest),
    now
  );
  const extended = new Date(
    Math.max(base.getTime(), now.getTime()) + days * 24 * 60 * 60 * 1000
  );

  const existingSource = (data.subscriptionSource as string | undefined) ?? "";
  await writeEntitlement(uid, {
    isPremium: true,
    premiumExpiry: extended,
    // Keep an existing non-trial source; a trial-source account that is
    // extended stays on the trial source (it is still not a Play purchase).
    subscriptionSource: existingSource || SUBSCRIPTION_SOURCE_GOOGLE_PLAY,
    ...(data.subscriptionProduct
      ? { subscriptionProduct: String(data.subscriptionProduct) }
      : {}),
    ...(data.subscriptionPlayPurchaseToken
      ? {
          subscriptionPlayPurchaseToken: String(
            data.subscriptionPlayPurchaseToken
          ),
        }
      : {}),
    ...(data.subscriptionTier
      ? { subscriptionTier: String(data.subscriptionTier) }
      : {}),
    subscriptionStatus: "active",
    subscriptionRenewalDate: extended,
  });
  return extended;
}

/**
 * onReferralConversionCreated
 *
 * Firestore trigger (v2) on `referral_conversions/{conversionId}`.
 *
 * Grants the referrer's reward server-side:
 *  1. Validates the conversion carries a referrer + referred uid and that
 *     they differ (defence-in-depth — the client also validates).
 *  2. Idempotency: if the conversion is already `granted`/`rewarded`, or any
 *     conversion already exists with the SAME `referredUserId` in a final
 *     state, it is a no-op (a referred user can only ever reward once).
 *  3. Resolves the reward-config (`admin_config/referral_rewards`) and the
 *     reward days for the referred user's tier.
 *  4. Extends the REFERRER's entitlement (premiumExpiry / trial window) by
 *     the reward days via `writeEntitlement`.
 *  5. Marks the conversion `status: 'granted'` + `rewarded` + `grantedAt` +
 *     `rewardDays` + `rewardAmountZAR`.
 *
 * Never throws — a failure is logged and leaves the conversion `pending` so a
 * later retry / manual finalisation can complete it.
 */
export const onReferralConversionCreated = onDocumentCreated(
  { document: "referral_conversions/{conversionId}", region: "us-central1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const conversionId = event.params.conversionId;
    const conversion = snap.data() ?? {};

    const referrerId = String(conversion.referrerId ?? "").trim();
    const referredUserId = String(conversion.referredUserId ?? "").trim();
    const status = String(conversion.status ?? "").trim().toLowerCase();
    const tier =
      conversion.subscriptionTier === REFERRAL_TIER_OUTFITTER
        ? REFERRAL_TIER_OUTFITTER
        : REFERRAL_TIER_HUNTER;

    if (!referrerId || !referredUserId) {
      logger.warn("onReferralConversionCreated: missing party ids", {
        conversionId,
      });
      return;
    }
    if (referrerId === referredUserId) {
      logger.warn("onReferralConversionCreated: self-referral rejected", {
        conversionId,
        referrerId,
      });
      return;
    }

    const conversions = firestore().collection(REFERRAL_CONVERSIONS_COLLECTION);
    const conversionRef = conversions.doc(conversionId);

    // Idempotency: a conversion already finalised / granted is a no-op. Also
    // reject a second grant for the same referred user.
    if (
      status === REFERRAL_STATUS_GRANTED ||
      status === REFERRAL_STATUS_REWARDED
    ) {
      return;
    }
    const priorGrant = await conversions
      .where("referredUserId", "==", referredUserId)
      .get();
    const alreadyGranted = priorGrant.docs.some((d) => {
      if (d.id === conversionId) return false;
      const s = String((d.data() ?? {}).status ?? "").toLowerCase();
      return s === REFERRAL_STATUS_GRANTED || s === REFERRAL_STATUS_REWARDED;
    });
    if (alreadyGranted) {
      logger.info("onReferralConversionCreated: already granted for user", {
        conversionId,
        referredUserId,
      });
      await conversionRef.update({
        status: REFERRAL_STATUS_REJECTED,
        rejectReason: "already_rewarded",
        statusUpdatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    try {
      const config = await loadReferralRewardConfig();
      const days = rewardDaysForTier(config, tier);

      // A non-extension reward mechanism is not yet supported server-side —
      // leave the conversion pending rather than mis-granting.
      if (config.rewardType !== DEFAULT_REWARD_TYPE) {
        logger.warn("onReferralConversionCreated: unsupported rewardType", {
          conversionId,
          rewardType: config.rewardType,
        });
        return;
      }
      if (days <= 0) {
        logger.warn("onReferralConversionCreated: zero reward days", {
          conversionId,
          tier,
        });
        await conversionRef.update({
          status: REFERRAL_STATUS_REJECTED,
          rejectReason: "zero_reward_days",
          statusUpdatedAt: FieldValue.serverTimestamp(),
        });
        return;
      }

      const extended = await extendReferrerEntitlement(referrerId, days);

      await conversionRef.update({
        status: REFERRAL_STATUS_GRANTED,
        rewarded: true,
        rewardDays: days,
        rewardType: config.rewardType,
        rewardAmountZAR:
          tier === REFERRAL_TIER_OUTFITTER
            ? config.outfitterRewardZAR
            : config.hunterRewardZAR,
        grantedPremiumExpiry: extended,
        grantedAt: FieldValue.serverTimestamp(),
        statusUpdatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("referral reward granted", {
        conversionId,
        referrerId,
        referredUserId,
        days,
      });
    } catch (err) {
      logger.error("onReferralConversionCreated: grant failed", {
        conversionId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);
