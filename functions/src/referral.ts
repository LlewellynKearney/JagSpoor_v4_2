import { logger } from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { auth, firestore } from "./firebase";
import { writeEntitlement, SUBSCRIPTION_SOURCE_GOOGLE_PLAY } from "./entitlement";

// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// JagSpoor referral system вЂ” Phase 1 backend module.
//
// Owns the server-side read/write surface for the three referral
// collections. The client (Flutter `ReferralRepository`) and the backend
// share the same collection + field contracts so either side can be the
// writer for a given document:
//
//   referral_profiles/{uid}        вЂ” user uid, unique referral code, banking
//                                    details (payout opt-in).
//   referral_conversions/{id}      вЂ” referrerId, referredUserId, referralCode,
//                                    subscriptionTier, status, rewardAmountZAR.
//   admin_config/referral_rewards  вЂ” dynamic hunter/outfitter reward amounts.
//
// Phase 1 ships the models + repository methods (read/write + admin config
// load). Phase 2 wires the subscription-activation trigger that finalises a
// conversion to `rewarded`/`rejected` and the payout/claim flow on top.
// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

/** Collection names вЂ” single source of truth shared with the Flutter client. */
export const REFERRAL_PROFILES_COLLECTION = "referral_profiles";
export const REFERRAL_CONVERSIONS_COLLECTION = "referral_conversions";
export const ADMIN_CONFIG_COLLECTION = "admin_config";
export const REFERRAL_REWARDS_DOC_ID = "referral_rewards";

/**
 * Default reward amounts (ZAR) — one month's subscription value at the
 * VAT-inclusive Admin Portal pricing (R34.99 hunter / R299.99 outfitter).
 * These mirror the Flutter `ReferralRewards` constants and are used ONLY as
 * the fallback when the dynamic `admin_config/referral_rewards` document is
 * absent. The live document is the source of truth for the reward
 * calculation.
 */
export const DEFAULT_HUNTER_REWARD_ZAR = 34.99;
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

/** Default reward mechanism вЂ” a premium / trial extension in days. */
export const DEFAULT_REWARD_TYPE = "extension_days";
export const DEFAULT_HUNTER_DAYS = 30;
export const DEFAULT_OUTFITTER_DAYS = 30;

// ────────────────────────────────────────────────────────────────────────────
// Play-compliance guard rails (Task 2B)
//
// Google Play's "Deceptive Behavior" + "User Ratings, Reviews, Installs"
// policies forbid (a) rewards for an install / signup / rating / review on
// its own, and (b) unbounded incentivised loops. Two server-side guards
// enforce the programme's limits:
//
//   1. MAX_CONVERSIONS_PER_CODE — a single referral code can reward at most
//      this many successful conversions (the "cap" — P0-1).
//   2. The engagement gate (P0-3) — a conversion only grants once the
//      referred user has genuinely engaged with the app: a VERIFIED email +
//      a COMPLETED profile + ONE real in-app action (see
//      QUALIFYING_ENGAGEMENT_ACTION). A raw install / signup never rewards.
// ────────────────────────────────────────────────────────────────────────────

/** Maximum successful (granted) conversions a single referral code may earn. */
export const MAX_CONVERSIONS_PER_CODE = 10;

/**
 * The single qualifying in-app action the referred user must complete before
 * the referrer is rewarded (P0-3). Chosen + documented: **creating their
 * first trophy** (`trophies` collection, owner field `ownerId`). It is a
 * self-serve, genuine-use action that requires the user to actually engage
 * with a core hunter feature — unlike an install, a signup, a rating or a
 * review, which Play forbids as reward triggers.
 */
export const QUALIFYING_ENGAGEMENT_ACTION = "first_trophy_created";

/** The `users/{uid}` field recording the code a user already consumed. */
export const REFERRAL_CODE_USED_FIELD = "referralCodeUsed";

/** Reject reasons stamped on a conversion the backend declines to reward. */
export const REJECT_REASON_CAP_REACHED = "cap_reached";
export const REJECT_REASON_ALREADY_REWARDED = "already_rewarded";
export const REJECT_REASON_CODE_ALREADY_USED = "code_already_used";
export const REJECT_REASON_SELF_REFERRAL = "self_referral";

/** Re-exported for callers that prefer the audit's terminology. */
export const REFERRAL_CAP_PER_CODE = MAX_CONVERSIONS_PER_CODE;

/** Engagement-gate field names recorded on a pending conversion. */
export const ENGAGEMENT_FIELD = "engagement";
export const ENGAGEMENT_MET_FIELD = "engagementMet";

/**
 * True when `users/{uid}` carries a completed profile: a first name AND a
 * last name AND at least one contact detail (phone OR email). Mirrors the
 * Flutter `HunterProfileCompleteness` field-alias tolerance. Pure +
 * unit-testable.
 */
export function hasCompletedProfile(
  data: Record<string, unknown> | null | undefined
): boolean {
  const d = data ?? {};
  const trim = (v: unknown): string => String(v ?? "").trim();
  const fullName = trim(d.fullName);
  const hasFirstName =
    trim(d.firstName).length > 0 ||
    trim(d.first_name).length > 0 ||
    trim(d.name).length > 0 ||
    fullName.length > 0;
  const hasLastName =
    trim(d.lastName).length > 0 ||
    trim(d.last_name).length > 0 ||
    trim(d.surname).length > 0 ||
    (fullName.length > 0 && fullName.includes(" "));
  const hasContact =
    trim(d.phone).length > 0 ||
    trim(d.phoneNumber).length > 0 ||
    trim(d.cellNumber).length > 0 ||
    trim(d.cell).length > 0 ||
    trim(d.email).length > 0;
  return hasFirstName && hasLastName && hasContact;
}

/**
 * True when the user has already consumed a referral code (the dead guard
 * from the audit is now live): a non-empty `referralCodeUsed` on
 * `users/{uid}` means the account has already been counted as a referral, so
 * it may never reward again. Pure.
 */
export function hasConsumedReferralCode(
  data: Record<string, unknown> | null | undefined,
  code?: string
): boolean {
  const used = String((data ?? {})[REFERRAL_CODE_USED_FIELD] ?? "").trim();
  if (!used) return false;
  if (code === undefined) return true;
  return used.toUpperCase() === code.trim().toUpperCase();
}

/** True when the per-code conversion cap has been reached. Pure. */
export function exceedsReferralCap(
  grantedCount: number,
  max: number = MAX_CONVERSIONS_PER_CODE
): boolean {
  return grantedCount >= max;
}

/**
 * The reasons the engagement gate is not yet satisfied, given the three
 * signals. Empty array => the gate is satisfied. Pure + unit-testable.
 */
export function engagementMissingReasons(input: {
  emailVerified: boolean;
  profileComplete: boolean;
  actionCompleted: boolean;
}): string[] {
  const missing: string[] = [];
  if (!input.emailVerified) missing.push("email_not_verified");
  if (!input.profileComplete) missing.push("profile_incomplete");
  if (!input.actionCompleted) missing.push("no_qualifying_action");
  return missing;
}

/** True when every engagement signal is present. Pure. */
export function isEngagementSatisfied(input: {
  emailVerified: boolean;
  profileComplete: boolean;
  actionCompleted: boolean;
}): boolean {
  return engagementMissingReasons(input).length === 0;
}


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
 * defaults when the document is absent or unreadable вЂ” never throws.
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

// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Phase 2 вЂ” grant the referral reward SERVER-SIDE on conversion creation
//
// A referral conversion is created client-side (by the Flutter signup flow)
// with `status: 'pending'`. This Firestore trigger (Admin SDK вЂ” bypasses
// firestore.rules) validates the referrer, resolves the reward days from the
// live `admin_config/referral_rewards` config, extends the REFERRER's
// entitlement by the reward days (via writeEntitlement вЂ” the SAME writer the
// Google Play validation uses), and marks the conversion `granted`/`rewarded`
// idempotently.
//
// The client NEVER writes an expiry; the entitlement write happens here.
// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

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

/** The outcome of evaluating the referral grant pipeline for a conversion. */
export type ReferralGrantDecision =
  | { action: "grant" }
  | { action: "pending"; missing: string[] }
  | { action: "reject"; reason: string };

/**
 * The SINGLE, pure decision function for whether a referral conversion may
 * grant. Extracted so the whole policy (idempotency, the live
 * `referralCodeUsed` guard, the per-code cap, the zero-days guard and the
 * Play-compliance engagement gate) is unit-testable without Firestore.
 *
 * Precedence (first match wins):
 *   1. already granted (idempotency)              -> reject already_rewarded
 *   2. referred user already consumed a code      -> reject code_already_used
 *   3. per-code conversion cap reached            -> reject cap_reached
 *   4. zero / unsupported reward days             -> reject zero_reward_days
 *   5. engagement gate not satisfied              -> pending (+ missing)
 *   6. otherwise                                  -> grant
 */
export function decideReferralGrant(input: {
  alreadyGranted: boolean;
  codeAlreadyUsed: boolean;
  grantedCountForCode: number;
  rewardDays: number;
  emailVerified: boolean;
  profileComplete: boolean;
  actionCompleted: boolean;
  maxPerCode?: number;
}): ReferralGrantDecision {
  if (input.alreadyGranted) {
    return { action: "reject", reason: REJECT_REASON_ALREADY_REWARDED };
  }
  if (input.codeAlreadyUsed) {
    return { action: "reject", reason: REJECT_REASON_CODE_ALREADY_USED };
  }
  if (exceedsReferralCap(input.grantedCountForCode, input.maxPerCode)) {
    return { action: "reject", reason: REJECT_REASON_CAP_REACHED };
  }
  if (input.rewardDays <= 0) {
    return { action: "reject", reason: "zero_reward_days" };
  }
  const missing = engagementMissingReasons({
    emailVerified: input.emailVerified,
    profileComplete: input.profileComplete,
    actionCompleted: input.actionCompleted,
  });
  if (missing.length > 0) {
    return { action: "pending", missing };
  }
  return { action: "grant" };
}

/** True when a conversion doc is in a final (granted / rewarded) state. */
function isFinalGrantedStatus(status: unknown): boolean {
  const s = String(status ?? "").trim().toLowerCase();
  return s === REFERRAL_STATUS_GRANTED || s === REFERRAL_STATUS_REWARDED;
}

/**
 * Resolves the referred user's live email-verification state via the Admin
 * Auth SDK (authoritative - the `users/{uid}` doc does not track it).
 * Best-effort: an unavailable user record resolves to `false` (never rewards
 * an unverified account).
 */
async function isReferredUserEmailVerified(uid: string): Promise<boolean> {
  try {
    const record = await auth().getUser(uid);
    return record.emailVerified === true;
  } catch (err) {
    logger.warn("referral: email-verification lookup failed", {
      uid,
      error: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}

/** True when the referred user has created at least one trophy (the action). */
async function hasQualifyingAction(uid: string): Promise<boolean> {
  try {
    const snap = await firestore()
      .collection("trophies")
      .where("ownerId", "==", uid)
      .limit(1)
      .get();
    return !snap.empty;
  } catch (err) {
    logger.warn("referral: qualifying-action lookup failed", {
      uid,
      error: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}

/**
 * Evaluates + applies the referral grant pipeline for a single conversion
 * document. Shared by every trigger (conversion created, qualifying action,
 * profile update) so the policy is enforced identically no matter which
 * signal arrives last.
 *
 * On GRANT it also writes the live `referralCodeUsed` guard onto the referred
 * user's `users/{uid}` document (the audit's dead guard, now wired) so the
 * account can never reward a second time.
 *
 * Never throws - a failure is logged and leaves the conversion pending.
 */
export async function attemptReferralGrant(
  conversionId: string
): Promise<void> {
  if (!conversionId) return;
  const conversions = firestore().collection(REFERRAL_CONVERSIONS_COLLECTION);
  const conversionRef = conversions.doc(conversionId);
  let conversion: Record<string, unknown>;
  try {
    const snap = await conversionRef.get();
    if (!snap.exists) return;
    conversion = (snap.data() ?? {}) as Record<string, unknown>;
  } catch (err) {
    logger.warn("referral: conversion read failed", {
      conversionId,
      error: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  const referrerId = String(conversion.referrerId ?? "").trim();
  const referredUserId = String(conversion.referredUserId ?? "").trim();
  const referralCode = String(conversion.referralCode ?? "").trim().toUpperCase();
  const status = String(conversion.status ?? "").trim().toLowerCase();
  const tier =
    conversion.subscriptionTier === REFERRAL_TIER_OUTFITTER
      ? REFERRAL_TIER_OUTFITTER
      : REFERRAL_TIER_HUNTER;

  if (!referrerId || !referredUserId) {
    logger.warn("referral: missing party ids", { conversionId });
    return;
  }
  if (referrerId === referredUserId) {
    logger.warn("referral: self-referral rejected", {
      conversionId,
      referrerId,
    });
    return;
  }
  // A conversion already finalised is a no-op (idempotent re-entry).
  if (isFinalGrantedStatus(status)) return;

  try {
    // -- Gather the signals ------------------------------------------------
    const userRef = firestore().collection("users").doc(referredUserId);
    const userSnap = await userRef.get();
    const userData = (userSnap.data() ?? {}) as Record<string, unknown>;

    const priorGrant = await conversions
      .where("referredUserId", "==", referredUserId)
      .get();
    const alreadyGranted = priorGrant.docs.some(
      (d) => d.id !== conversionId && isFinalGrantedStatus((d.data() ?? {}).status)
    );

    const codeAlreadyUsed = hasConsumedReferralCode(userData);

    // Per-code cap: count the conversions ALREADY granted for this code.
    const grantedForCode = await conversions
      .where("referralCode", "==", referralCode)
      .get();
    const grantedCountForCode = grantedForCode.docs.filter(
      (d) => d.id !== conversionId && isFinalGrantedStatus((d.data() ?? {}).status)
    ).length;

    const config = await loadReferralRewardConfig();
    const days =
      config.rewardType === DEFAULT_REWARD_TYPE
        ? rewardDaysForTier(config, tier)
        : 0;

    const emailVerified = await isReferredUserEmailVerified(referredUserId);
    const profileComplete = hasCompletedProfile(userData);
    const actionCompleted = await hasQualifyingAction(referredUserId);

    // -- Decide ------------------------------------------------------------
    const decision = decideReferralGrant({
      alreadyGranted,
      codeAlreadyUsed,
      grantedCountForCode,
      rewardDays: days,
      emailVerified,
      profileComplete,
      actionCompleted,
    });

    if (decision.action === "reject") {
      await conversionRef.update({
        status: REFERRAL_STATUS_REJECTED,
        rejectReason: decision.reason,
        statusUpdatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("referral: conversion rejected", {
        conversionId,
        reason: decision.reason,
      });
      return;
    }

    if (decision.action === "pending") {
      // Not yet eligible - record WHY and leave it pending so the next signal
      // (profile update / first trophy) re-evaluates it.
      await conversionRef.update({
        status: REFERRAL_STATUS_PENDING,
        [ENGAGEMENT_MET_FIELD]: false,
        [ENGAGEMENT_FIELD]: {
          emailVerified,
          profileComplete,
          actionCompleted,
          missing: decision.missing,
          qualifyingAction: QUALIFYING_ENGAGEMENT_ACTION,
        },
        statusUpdatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("referral: conversion pending engagement", {
        conversionId,
        missing: decision.missing,
      });
      return;
    }

    // -- Grant -------------------------------------------------------------
    const extended = await extendReferrerEntitlement(referrerId, days);

    // Wire the live guard: stamp the consumed code on the referred user so a
    // second conversion for the same account can never reward.
    try {
      await userRef.set(
        { [REFERRAL_CODE_USED_FIELD]: referralCode },
        { merge: true }
      );
    } catch (err) {
      logger.warn("referral: referralCodeUsed stamp failed", {
        referredUserId,
        error: err instanceof Error ? err.message : String(err),
      });
    }

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
      [ENGAGEMENT_MET_FIELD]: true,
      grantedAt: FieldValue.serverTimestamp(),
      statusUpdatedAt: FieldValue.serverTimestamp(),
    });
    logger.info("referral reward granted", {
      conversionId,
      referrerId,
      referredUserId,
      days,
      action: QUALIFYING_ENGAGEMENT_ACTION,
    });
  } catch (err) {
    logger.error("referral: grant pipeline failed", {
      conversionId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * onReferralConversionCreated
 *
 * Firestore trigger (v2) on `referral_conversions/{conversionId}`.
 *
 * The conversion is created by the Flutter signup flow with `status:
 * 'pending'`. This trigger runs the shared grant pipeline
 * ([attemptReferralGrant]) which - as of Task 2B - grants ONLY when the
 * referred user has genuinely engaged (verified email + completed profile +
 * a qualifying action). A raw signup therefore stays `pending`.
 *
 * Never throws.
 */
export const onReferralConversionCreated = onDocumentCreated(
  { document: "referral_conversions/{conversionId}", region: "us-central1" },
  async (event) => {
    if (!event.data) return;
    await attemptReferralGrant(event.params.conversionId);
  }
);

/**
 * onReferredUserTrophyCreated
 *
 * Firestore trigger (v2) on `trophies/{trophyId}`. Creating a trophy is the
 * QUALIFYING ENGAGEMENT ACTION (P0-3): when the referred user creates their
 * first trophy this re-runs the grant pipeline for any pending conversion
 * they own, so the reward fires on genuine engagement - never on the install
 * or the signup alone.
 */
export const onReferredUserTrophyCreated = onDocumentCreated(
  { document: "trophies/{trophyId}", region: "us-central1" },
  async (event) => {
    const data = event.data?.data() ?? {};
    const ownerId = String(data.ownerId ?? "").trim();
    if (!ownerId) return;
    try {
      const pending = await firestore()
        .collection(REFERRAL_CONVERSIONS_COLLECTION)
        .where("referredUserId", "==", ownerId)
        .where("status", "==", REFERRAL_STATUS_PENDING)
        .get();
      for (const doc of pending.docs) {
        await attemptReferralGrant(doc.id);
      }
    } catch (err) {
      logger.warn("onReferredUserTrophyCreated: pending lookup failed", {
        ownerId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);

/**
 * onReferredUserProfileUpdated
 *
 * Firestore trigger (v2) on `users/{userId}` update. Re-runs the grant
 * pipeline for any pending conversion owned by the updated user, so
 * completing the profile (one of the three engagement signals) can be the
 * signal that finally unlocks the reward.
 */
export const onReferredUserProfileUpdated = onDocumentUpdated(
  { document: "users/{userId}", region: "us-central1" },
  async (event) => {
    const userId = event.params.userId;
    if (!userId) return;
    try {
      const pending = await firestore()
        .collection(REFERRAL_CONVERSIONS_COLLECTION)
        .where("referredUserId", "==", userId)
        .where("status", "==", REFERRAL_STATUS_PENDING)
        .get();
      for (const doc of pending.docs) {
        await attemptReferralGrant(doc.id);
      }
    } catch (err) {
      logger.warn("onReferredUserProfileUpdated: pending lookup failed", {
        userId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
);
