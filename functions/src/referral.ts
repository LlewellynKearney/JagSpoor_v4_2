import { FieldValue } from "firebase-admin/firestore";
import { firestore } from "./firebase";

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
export const DEFAULT_HUNTER_REWARD_ZAR = 19.99;
export const DEFAULT_OUTFITTER_REWARD_ZAR = 199.99;

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
  updatedAt?: FirebaseFireTimestamp;
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
  };
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
