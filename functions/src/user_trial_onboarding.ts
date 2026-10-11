import { logger } from "firebase-functions/v2";
import { onUserCreated } from "firebase-functions/v2/identity";
import { FieldValue } from "firebase-admin/firestore";
import { firestore } from "./firebase";
import { emailPass } from "./params";

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
 * The platform admin email. Mirrors the client-side
 * `TrialAssignmentPolicy.adminEmail` so the trial bypass agrees with the
 * rest of the app's admin detection.
 */
export const ADMIN_EMAIL = "admin@jag-spoor.co.za";

/**
 * Whether a newly created Auth user belongs to the admin account. The admin
 * is excluded from the automatic trial so it keeps its fixed billing tiers.
 */
export function isAdminAccount(user: {
  uid?: string;
  email?: string | null;
}): boolean {
  const email = (user.email ?? "").toString().trim().toLowerCase();
  return email === ADMIN_EMAIL;
}

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
 * Firebase Authentication `onUserCreated` trigger (**2nd gen** identity
 * provider). Fires once per newly created Auth user and initializes
 * `users/{uid}` with the 30-day free trial state (`subscriptionStatus:
 * 'trialing'`, `trialEndsAt` = now + 30 days, `requiresPayment: false`). An
 * already-existing non-trial `subscriptionStatus` (e.g. pre-provisioned
 * billing state) is preserved so the trigger can never downgrade an account.
 *
 * Declares the EMAIL_PASS secret so the runtime mounts the mailbox password
 * (the support-notification trigger `onUserCreate` sends the welcome mail).
 */
export const initializeNewUserTrial = onUserCreated(
  { region: "us-central1", secrets: [emailPass] },
  async (event) => {
    const user = event.data;
    const uid = user.uid;

    // Admin accounts are excluded from the automatic trial so the platform
    // admin keeps its fixed billing tiers (mirrors the client-side
    // `TrialAssignmentPolicy` bypass).
    if (isAdminAccount(user)) {
      logger.info("initializeNewUserTrial: admin account excluded from trial", {
        uid,
      });
      return;
    }

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
        // Canonical trial status shared by the client `markTrialStarted`.
        subscriptionStatus: "trialing",
        // Backend-trigger schema (trialEndsAt / trialStart).
        trialStartedAt: now,
        trialEndsAt,
        trialStart: now,
        trialEnd: trialEndsAt,
        // Client `markTrialStarted` schema (subscriptionTrialEndsAt) — written
        // too so a doc provisioned by THIS trigger resolves under every
        // reader, regardless of which spelling it checks (TODO #5).
        subscriptionTrialEndsAt: trialEndsAt,
        subscriptionTrialStart: now,
        isPremium: false,
        subscriptionSource: "trial",
        requiresPayment: false,
        subscriptionUpdatedAt: FieldValue.serverTimestamp(),
        entitlementUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logger.info("initializeNewUserTrial: 30-day free trial initialized", {
      uid,
      trialEndsAt: trialEndsAt.toISOString(),
    });
  }
);
