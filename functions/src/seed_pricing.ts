/**
 * One-time seed for the VAT-inclusive `admin_config/pricing` control plane.
 *
 * **Option A pricing model**: the customer pays R34.99 / R299.99 per month and
 * that IS the final charge. South African VAT (15%) is *absorbed out of* that
 * amount rather than added on top, so:
 *
 *   hunter    : price_excl 30.43  -> price_incl 34.99  (vat 4.56)
 *   outfitter : price_excl 260.86 -> price_incl 299.99 (vat 39.13)
 *
 * The Google Play Console base plans must be configured as R34.99 / R299.99
 * INCLUDING VAT so that `ProductDetails.price` (the value the paywall shows)
 * matches this doc.
 *
 * This module is intentionally NOT exported from `src/index.ts`: it is a
 * standalone operator script, not a deployed Cloud Function.
 *
 * Run it (requires a credentialed environment — Application Default
 * Credentials or GOOGLE_APPLICATION_CREDENTIALS pointing at a service account
 * with the Firebase Admin role):
 *
 *   cd functions
 *   npm run build
 *   SEED_CONFIRM=yes node lib/seed_pricing.js
 *
 * The SEED_CONFIRM guard is deliberate: this doc drives the in-app display
 * price and the Admin Portal revenue figures, so it must never be written
 * implicitly (e.g. as part of a deploy).
 */

import { initializeApp, getApps } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

/** South African VAT rate (percent). */
export const VAT_RATE_PERCENT = 15;

/** Hunter tier — VAT-inclusive final monthly charge (ZAR). */
export const HUNTER_PRICE_INCL_ZAR = 34.99;

/** Outfitter tier — VAT-inclusive final monthly charge (ZAR). */
export const OUTFITTER_PRICE_INCL_ZAR = 299.99;

/** Control-plane doc path (matches `SubscriptionConfigService`). */
export const PRICING_CONFIG_PATH = "admin_config/pricing";

/** `admin_config/referral_rewards` — one month's value per tier. */
export const REFERRAL_REWARDS_PATH = "admin_config/referral_rewards";

/** Rounds to whole cents (avoids 30.430000000000003-style drift). */
function cents(value: number): number {
  return Math.round(value * 100) / 100;
}

/** The VAT-exclusive component of a VAT-inclusive amount. */
export function exclusiveOf(inclusive: number): number {
  return cents(inclusive / (1 + VAT_RATE_PERCENT / 100));
}

/** The VAT component of a VAT-inclusive amount. */
export function vatOf(inclusive: number): number {
  return cents(inclusive - exclusiveOf(inclusive));
}

/** `"R34.99/month incl. VAT"` display label. */
export function displayPriceFor(inclusive: number): string {
  return `R${inclusive.toFixed(2)}/month incl. VAT`;
}

/**
 * The pricing document payload (without the server timestamp). Writes BOTH
 * the canonical snake_case keys and the legacy camelCase aliases so every
 * reader (old or new build) resolves the same VAT-inclusive amount.
 */
export function pricingSeedPayload(): Record<string, unknown> {
  const hunterExcl = exclusiveOf(HUNTER_PRICE_INCL_ZAR);
  const outfitterExcl = exclusiveOf(OUTFITTER_PRICE_INCL_ZAR);
  return {
    hunter_monthly: HUNTER_PRICE_INCL_ZAR,
    outfitter_monthly: OUTFITTER_PRICE_INCL_ZAR,
    hunterSubscriptionZAR: HUNTER_PRICE_INCL_ZAR,
    outfitterSubscriptionZAR: OUTFITTER_PRICE_INCL_ZAR,
    vat: VAT_RATE_PERCENT,
    hunter_price_excl: hunterExcl,
    hunter_price_incl: HUNTER_PRICE_INCL_ZAR,
    outfitter_price_excl: outfitterExcl,
    outfitter_price_incl: OUTFITTER_PRICE_INCL_ZAR,
    hunter_display_price: displayPriceFor(HUNTER_PRICE_INCL_ZAR),
    outfitter_display_price: displayPriceFor(OUTFITTER_PRICE_INCL_ZAR),
  };
}

/** The referral-rewards payload (mirrors one month's subscription value). */
export function referralRewardsSeedPayload(): Record<string, unknown> {
  return {
    hunter: HUNTER_PRICE_INCL_ZAR,
    outfitter: OUTFITTER_PRICE_INCL_ZAR,
    hunterRewardZAR: HUNTER_PRICE_INCL_ZAR,
    outfitterRewardZAR: OUTFITTER_PRICE_INCL_ZAR,
    rewardType: "extension_days",
    hunter_days: 30,
    outfitter_days: 30,
  };
}

/** Writes the pricing control-plane doc. Returns the path written. */
export async function seedPricingDoc(): Promise<string> {
  if (getApps().length === 0) {
    initializeApp();
  }
  await getFirestore()
    .doc(PRICING_CONFIG_PATH)
    .set(
      {
        ...pricingSeedPayload(),
        updated_at: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return PRICING_CONFIG_PATH;
}

/**
 * Writes the referral-rewards doc so the reward amounts track the new
 * pricing. Returns the path written.
 */
export async function seedReferralRewardsDoc(): Promise<string> {
  if (getApps().length === 0) {
    initializeApp();
  }
  await getFirestore()
    .doc(REFERRAL_REWARDS_PATH)
    .set(
      {
        ...referralRewardsSeedPayload(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return REFERRAL_REWARDS_PATH;
}

/**
 * CLI entry point. Guarded by SEED_CONFIRM so an accidental
 * `node lib/seed_pricing.js` (or a build hook) cannot overwrite the live
 * control-plane pricing.
 */
async function main(): Promise<void> {
  if (process.env.SEED_CONFIRM !== "yes") {
    console.log(
      "Refusing to write. Re-run with SEED_CONFIRM=yes to update the " +
        "control-plane pricing to the VAT-inclusive Option A amounts.",
    );
    console.log("Pricing payload that WOULD be written:");
    console.log(JSON.stringify(pricingSeedPayload(), null, 2));
    console.log("Referral rewards payload that WOULD be written:");
    console.log(JSON.stringify(referralRewardsSeedPayload(), null, 2));
    return;
  }
  console.log(`Wrote ${await seedPricingDoc()}`);
  console.log(`Wrote ${await seedReferralRewardsDoc()}`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error("seed_pricing failed:", err);
    process.exitCode = 1;
  });
}
