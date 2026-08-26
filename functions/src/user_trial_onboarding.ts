import { logger } from "firebase-functions/v2";
import * as functionsV1 from "firebase-functions/v1";
import { FieldValue } from "firebase-admin/firestore";
import { firestore } from "./firebase";

// ────────────────────────────────────────────────────────────────────────────
// Automated 30-Day Free Trial Provisioning
//
// A Firebase Auth `onCreate` trigger fires for every newly registered user
// (email/password AND Google sign-in alike). The handler initializes the
// user's Firestore profile (`users/{uid}`) to `subscriptionStatus:
// 'trialing'` with `trialEndsAt` exactly 30 days in the future and
// `requiresPayment: false` (merge-write; an existing non-trial subscription
// state is never clobbered).
// ────────────────────────────────────────────────────────────────────────────

/** Free trial length, in days. */
export const TRIAL_PERIOD_DAYS = 30;

/** Free trial length, in milliseconds (exactly 30 days). */
export const TRIAL_PERIOD_MS = TRIAL_PERIOD_DAYS * 24 * 60 * 60 * 1000;

/**
 * Computes the trial expiration timestamp: exactly 30 days after `startedAt`.
 */
export function trialEndsAtFrom(startedAt: Date): Date {
  return new Date(startedAt.getTime() + TRIAL_PERIOD_MS);
}

// ── Firebase Auth onCreate trigger ───────────────────────────────────────────

/**
 * initializeNewUserTrial
 *
 * Firebase Authentication user-creation trigger (v1 auth provider). Fires
 * once per newly created Auth user and initializes `users/{uid}` with the
 * 30-day free trial state (`subscriptionStatus: 'trialing'`, `trialEndsAt` =
 * now + 30 days, `requiresPayment: false`). An already-existing non-trial
 * `subscriptionStatus` (e.g. pre-provisioned billing state) is preserved so
 * the trigger can never downgrade an account.
 */
export const initializeNewUserTrial = functionsV1
  .region("us-central1")
  .auth.user()
  .onCreate(async (user) => {
    const uid = user.uid;
    const now = new Date();
    const trialEndsAt = trialEndsAtFrom(now);

    const userRef = firestore().collection("users").doc(uid);
    const snap = await userRef.get();
    const existingStatus = ((snap.data() ?? {})["subscriptionStatus"] ?? "")
      .toString()
      .trim();

    if (existingStatus !== "" && existingStatus !== "trialing") {
      // Pre-existing non-trial status preserved — no trial write needed.
      logger.info(
        "initializeNewUserTrial: existing subscription state preserved",
        { uid, subscriptionStatus: existingStatus }
      );
      return;
    }

    await userRef.set(
      {
        subscriptionStatus: "trialing",
        trialStartedAt: now,
        trialEndsAt,
        requiresPayment: false,
        subscriptionUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logger.info("initializeNewUserTrial: 30-day free trial initialized", {
      uid,
      trialEndsAt: trialEndsAt.toISOString(),
    });
  });
