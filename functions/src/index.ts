import { logger } from "firebase-functions/v2";
import {
  onCall,
  onRequest,
  HttpsError,
  type CallableRequest,
  type Request,
} from "firebase-functions/v2/https";
import type { Response } from "express";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { firestore, auth, getAdmin } from "./firebase";
import {
  parseItnBody,
  verifySignature,
  validateWithPayFast,
  parseSubscriptionPaymentId,
  cancelPayfastSubscriptionToken,
  PAYFAST_API_BASE,
} from "./payfast_subscription";

// Automated 30-day free trial initialization on Firebase Auth user creation
// (see user_trial_onboarding.ts).
export { initializeNewUserTrial } from "./user_trial_onboarding";

// ────────────────────────────────────────────────────────────────────────────
// 1. Admin: create outfitter account + document + custom claims
// ────────────────────────────────────────────────────────────────────────────

/**
 * adminCreateOutfitter
 *
 * Callable Cloud Function (https.onCall). Invoked from the mobile admin
 * client via the firebase_functions Flutter plugin:
 *
 *   FirebaseFunctions.instance
 *       .httpsCallable('adminCreateOutfitter')
 *       .call({'email': ..., 'password': ..., 'displayName': ...,
 *              'businessName': ..., 'farmIds': [...]});
 *
 * Because onCall runs authenticated in the caller's context (the admin's
 * Firebase ID token is attached automatically by the SDK), the current
 * mobile admin session is NOT logged out — we use the Admin SDK to create
 * a *separate* Auth user, leaving the caller's session untouched.
 *
 * Authorization: caller must carry a custom claim `admin: true`.
 *
 * Side effects:
 *   - Creates a new Firebase Auth user (email/password).
 *   - Writes /outfitters/{newUid} document with role + profile.
 *   - Sets custom claims { role: 'outfitter' } on the new user.
 */
interface CreateOutfitterInput {
  email: string;
  password: string;
  displayName?: string;
  businessName?: string;
  farmIds?: string[];
  phoneNumber?: string;
}

interface CreateOutfitterOutput {
  uid: string;
  email: string;
  outfitterDocId: string;
  claims: { role: string };
}

export const adminCreateOutfitter = onCall(
  { region: "us-central1", maxInstances: 10 },
  async (req: CallableRequest<CreateOutfitterInput>): Promise<CreateOutfitterOutput> => {
    // ── Authorization: caller must be an admin ───────────────────────
    const callerToken = req.auth;
    if (!callerToken || !callerToken.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Authentication required to create an outfitter account."
      );
    }
    if (callerToken.token?.admin !== true) {
      throw new HttpsError(
        "permission-denied",
        "Only users with the `admin` custom claim may create outfitters."
      );
    }

    // ── Validate input ────────────────────────────────────────────────
    const data = (req.data ?? {}) as Partial<CreateOutfitterInput>;
    const email = (data.email ?? "").toString().trim().toLowerCase();
    const password = (data.password ?? "").toString();
    const displayName = (data.displayName ?? "").toString().trim();
    const businessName = (data.businessName ?? "").toString().trim();
    const farmIds = Array.isArray(data.farmIds)
      ? data.farmIds.map((f) => String(f))
      : [];
    const phoneNumber = (data.phoneNumber ?? "").toString().trim() || undefined;

    if (!email || !email.includes("@")) {
      throw new HttpsError("invalid-argument", "A valid email is required.");
    }
    if (!password || password.length < 8) {
      throw new HttpsError(
        "invalid-argument",
        "Password is required and must be at least 8 characters."
      );
    }

    // ── Step 1: create the Auth user via Admin SDK ───────────────────
    // The caller's own session is unaffected — createUser provisions a
    // brand-new Auth record, not the caller's.
    let newUid: string;
    try {
      const created = await auth().createUser({
        email,
        password,
        displayName: displayName || undefined,
        phoneNumber: phoneNumber || undefined,
        emailVerified: false,
      });
      newUid = created.uid;
    } catch (err) {
      const code = err instanceof Error ? (err as { code?: string }).code : undefined;
      if (code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "A user with that email already exists.");
      }
      throw new HttpsError(
        "internal",
        `Failed to create Auth user: ${
          err instanceof Error ? err.message : String(err)
        }`
      );
    }

    // ── Step 2: set custom claims (role: outfitter) ───────────────────
    try {
      await auth().setCustomUserClaims(newUid, { role: "outfitter" });
    } catch (err) {
      // Best-effort cleanup so we don't leave an orphan Auth user.
      try {
        await auth().deleteUser(newUid);
      } catch {
        /* swallow */
      }
      throw new HttpsError(
        "internal",
        `Failed to set custom claims: ${
          err instanceof Error ? err.message : String(err)
        }`
      );
    }

    // ── Step 3: write the /outfitters/{uid} document ───────────────────
    const outfitRef = firestore().collection("outfitters").doc(newUid);
    try {
      await outfitRef.set({
        uid: newUid,
        email,
        displayName: displayName || null,
        businessName: businessName || null,
        role: "outfitter",
        farmIds,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        createdBy: callerToken.uid,
      });
    } catch (err) {
      // Rollback Auth user + claims to keep state consistent.
      try {
        await auth().deleteUser(newUid);
      } catch {
        /* swallow */
      }
      throw new HttpsError(
        "internal",
        `Failed to create outfitter document: ${
          err instanceof Error ? err.message : String(err)
        }`
      );
    }

    return {
      uid: newUid,
      email,
      outfitterDocId: newUid,
      claims: { role: "outfitter" },
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 3. FCM push notifications (chat messages + booking status updates)
// ────────────────────────────────────────────────────────────────────────────

/**
 * Normalizes a user's `fcmTokens` field into a flat string[].
 *
 * The client may store tokens either as an array (`string[]`) or as a map
 * keyed by token (`{ [token]: true }`). Both shapes are supported.
 */
function extractFcmTokens(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw.filter((t): t is string => typeof t === "string" && t.length > 0);
  }
  if (raw && typeof raw === "object") {
    return Object.keys(raw as Record<string, unknown>).filter(
      (t) => typeof t === "string" && t.length > 0
    );
  }
  return [];
}

/**
 * Sends an FCM multicast to the given tokens. Never throws — FCM failures
 * are logged so a downstream notification error can't crash a Firestore
 * trigger. Empty token lists are a no-op.
 */
async function sendFcm(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  if (tokens.length === 0) return;
  try {
    const response = await getAdmin().messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data,
      android: { priority: "high" },
    });
    logger.info("FCM multicast sent", {
      title,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });
  } catch (err) {
    logger.error("FCM multicast failed", {
      title,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/** Maps a booking status string to a human-readable push body. */
function bookingStatusBody(newStatus: string): string {
  switch (newStatus.toLowerCase()) {
    case "pending approval":
      return "Your booking request was submitted and is awaiting outfitter approval.";
    case "awaiting payment":
    case "approved":
      return "Your booking was approved! Please arrange payment with the outfitter.";
    case "confirmed":
    case "paid":
      return "Payment confirmed — your booking is confirmed!";
    case "declined":
      return "Your booking has been declined.";
    case "cancelled":
      return "Your booking has been cancelled.";
    case "completed":
      return "Your booking is complete.";
    default:
      return `Your booking status is now ${newStatus}.`;
  }
}

/**
 * onNewChatMessage
 *
 * Firestore trigger (v2) on `bookings/{bookingId}/chats/{chatId}`.
 *
 * When a chat message is created it notifies the *other* party in the
 * booking (the recipient is whichever of hunterId/outfitterId did not send
 * the message). The recipient's FCM tokens are read from their
 * `users/{recipientId}` document.
 *
 * Push payload:
 *   - title: "New Message on JagSpoor"
 *   - body:  the message text (truncated to 100 chars)
 *   - data:  { bookingId, type: "chat" }
 */
export const onNewChatMessage = onDocumentCreated(
  { document: "bookings/{bookingId}/chats/{chatId}", region: "us-central1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const msg = snap.data();
    const senderId = (msg.senderId as string | undefined) ?? "";
    const text = (msg.text as string | undefined) ?? "";
    const bookingId = event.params.bookingId;

    if (!senderId) {
      logger.warn("onNewChatMessage: message has no senderId", { bookingId });
      return;
    }

    // Fetch the parent booking to resolve the two parties.
    const bookingSnap = await firestore()
      .collection("bookings")
      .doc(bookingId)
      .get();
    if (!bookingSnap.exists) {
      logger.warn("onNewChatMessage: parent booking not found", { bookingId });
      return;
    }
    const booking = bookingSnap.data() ?? {};
    const hunterId = (booking.hunterId as string | undefined) ?? "";
    const outfitterId = (booking.outfitterId as string | undefined) ?? "";

    // The recipient is the party that did not send the message.
    const recipientId = senderId === hunterId ? outfitterId : hunterId;
    if (!recipientId || recipientId === senderId) return;

    const userSnap = await firestore()
      .collection("users")
      .doc(recipientId)
      .get();
    if (!userSnap.exists) return;
    const tokens = extractFcmTokens((userSnap.data() ?? {}).fcmTokens);
    if (tokens.length === 0) {
      logger.info("onNewChatMessage: recipient has no FCM tokens", {
        bookingId,
        recipientId,
      });
      return;
    }

    const body = text.length > 100 ? `${text.substring(0, 97)}...` : text;
    await sendFcm(tokens, "New Message on JagSpoor", body, {
      bookingId,
      type: "chat",
    });
  }
);

/**
 * Fetches the FCM tokens for a user document id. Never throws — returns an
 * empty array when the doc does not exist or carries no tokens.
 */
async function tokensForUser(userId: string): Promise<string[]> {
  if (!userId) return [];
  const userSnap = await firestore().collection("users").doc(userId).get();
  if (!userSnap.exists) return [];
  return extractFcmTokens((userSnap.data() ?? {}).fcmTokens);
}

/**
 * onBookingCreated
 *
 * Firestore trigger (v2) on `bookings/{bookingId}`.
 *
 * A new booking document means a HUNTER just booked (or requested) a
 * package — notify the OUTFITTER so they can action the incoming request.
 *
 * Push payload:
 *   - title: "New Booking Request"
 *   - body:  e.g. "Bosveld Kudu Package was just booked by a hunter."
 *   - data:  { bookingId, type: "booking_new" }
 */
export const onBookingCreated = onDocumentCreated(
  { document: "bookings/{bookingId}", region: "us-central1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const booking = snap.data();
    const bookingId = event.params.bookingId;

    const outfitterId = (booking.outfitterId as string | undefined) ?? "";
    if (!outfitterId) return;

    const tokens = await tokensForUser(outfitterId);
    if (tokens.length === 0) {
      logger.info("onBookingCreated: outfitter has no FCM tokens", {
        bookingId,
        outfitterId,
      });
      return;
    }

    const packageName =
      (booking.packageName as string | undefined) ?? "a hunting package";
    await sendFcm(
      tokens,
      "New Booking Request",
      `A hunter just booked ${packageName}. Review the request on your booking dashboard.`,
      { bookingId, type: "booking_new" }
    );
  }
);

/**
 * onBookingUpdated
 *
 * Firestore trigger (v2) on `bookings/{bookingId}`.
 *
 * Two notification paths:
 *   1. STATUS change — the recipient is the "other" party:
 *        - if the hunter changed it (`updatedBy == hunterId`) → alert the outfitter
 *        - otherwise (outfitter or system) → alert the hunter.
 *      When `updatedBy` is absent, the hunter is alerted by default, since most
 *      status transitions (approval, decline) are outfitter/system initiated and
 *      the hunter is the interested party.
 *   2. DATE-CHANGE request — when `dateChangeRequestPending` flips to true the
 *      hunter modified the booking's hunt window → alert the outfitter.
 *
 * Push payload:
 *   - title: "Booking Status Update" (or "Date Change Requested")
 *   - body:  e.g. "Payment confirmed — your booking is confirmed!"
 *   - data:  { bookingId, type: "booking" } (or { bookingId, type: "date_change" })
 */
export const onBookingUpdated = onDocumentUpdated(
  { document: "bookings/{bookingId}", region: "us-central1" },
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const bookingId = event.params.bookingId;
    const hunterId = (after.hunterId as string | undefined) ?? "";
    const outfitterId = (after.outfitterId as string | undefined) ?? "";

    const beforeStatus = (before.status as string | undefined) ?? "";
    const afterStatus = (after.status as string | undefined) ?? "";

    // ── Path 1: status transition ──────────────────────────────────────
    if (beforeStatus !== afterStatus) {
      const actorId = (after.updatedBy as string | undefined) ?? "";
      const recipientId =
        actorId && actorId === hunterId ? outfitterId : hunterId;
      if (recipientId) {
        const tokens = await tokensForUser(recipientId);
        if (tokens.length === 0) {
          logger.info("onBookingUpdated: recipient has no FCM tokens", {
            bookingId,
            recipientId,
          });
        } else {
          await sendFcm(
            tokens,
            "Booking Status Update",
            bookingStatusBody(afterStatus),
            { bookingId, type: "booking" }
          );
        }
      }
    }

    // ── Path 2: hunter requested a date change → alert the outfitter ──
    const wasPending = before.dateChangeRequestPending === true;
    const isPending = after.dateChangeRequestPending === true;
    if (!wasPending && isPending && outfitterId) {
      const tokens = await tokensForUser(outfitterId);
      if (tokens.length > 0) {
        const packageName =
          (after.packageName as string | undefined) ?? "a booking";
        await sendFcm(
          tokens,
          "Date Change Requested",
          `A hunter requested new hunt dates for ${packageName}. Review the request on your booking dashboard.`,
          { bookingId, type: "date_change" }
        );
      }
    }
  }
);

/**
 * onPackageUpdated
 *
 * Firestore trigger (v2) on `packages/{packageId}`.
 *
 * Fires only when the package's `status` field changes (e.g. active →
 * sold_out after the last slot is booked, draft → active on publish,
 * active → archived). Notifies the owning OUTFITTER so they have a
 * real-time alert on inventory state changes — including the sold-out flip
 * driven by a hunter's booking transaction.
 *
 * Push payload:
 *   - title: "Package Status Update"
 *   - body:  e.g. "'Bosveld Kudu Package' is now Sold Out."
 *   - data:  { packageId, type: "package" }
 */
export const onPackageUpdated = onDocumentUpdated(
  { document: "packages/{packageId}", region: "us-central1" },
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const beforeStatus = (before.status as string | undefined) ?? "";
    const afterStatus = (after.status as string | undefined) ?? "";
    if (beforeStatus === afterStatus) return;

    const packageId = event.params.packageId;
    const outfitterId = (after.outfitterId as string | undefined) ?? "";
    if (!outfitterId) return;

    const tokens = await tokensForUser(outfitterId);
    if (tokens.length === 0) {
      logger.info("onPackageUpdated: outfitter has no FCM tokens", {
        packageId,
        outfitterId,
      });
      return;
    }

    const title = (after.title as string | undefined) ?? "Your package";
    const readableStatus =
      afterStatus === "sold_out"
        ? "Sold Out"
        : afterStatus.charAt(0).toUpperCase() + afterStatus.slice(1);

    await sendFcm(
      tokens,
      "Package Status Update",
      `'${title}' is now ${readableStatus}.`,
      { packageId, type: "package" }
    );
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 6. PayFast subscription billing — ITN (Instant Transaction Notification)
//    webhook that activates / cancels user subscriptions.
// ────────────────────────────────────────────────────────────────────────────

/**
 * The merchant passphrase used to verify ITN signatures. Read from the
 * PAYFAST_PASSPHRASE env var in production; falls back to the sandbox
 * passphrase bundled with the app for the sandbox integration.
 */
const PAYFAST_PASSPHRASE =
  process.env.PAYFAST_PASSPHRASE ?? "jagspoor_sandbox_2026";

/** PayFast server-to-server validation endpoint (sandbox vs production). */
const PAYFAST_VALIDATE_URL =
  process.env.PAYFAST_VALIDATE_URL ??
  "https://sandbox.payfast.co.za/eng/query/validate";

/**
 * payfastSubscriptionITN
 *
 * HTTPS onRequest webhook (public invoker) that receives PayFast Instant
 * Transaction Notifications for subscription payments. Flow:
 *   1. Parse the form-encoded ITN body (order preserved for the signature).
 *   2. Verify the MD5 signature with the merchant passphrase.
 *   3. Server-to-server validate the body with PayFast's validate endpoint.
 *   4. Resolve the subscriber from `m_payment_id` (`sub_{userId}_{tier}`).
 *   5. On `payment_status == COMPLETE`  -> users/{uid}.subscriptionStatus =
 *      "active", subscriptionTier, subscriptionRenewalDate (the ITN
 *      `billing_date`, else +30 days), subscriptionPromoCode.
 *      On FAILED / CANCELLED           -> subscriptionStatus = "cancelled".
 *
 * Responds 200 on success / ignored (non-subscription) notifications so
 * PayFast does not retry; 400 on malformed payloads; 403 on signature or
 * server-validation failures.
 */
export const payfastSubscriptionITN = onRequest(
  { region: "us-central1", invoker: "public", maxInstances: 10 },
  async (req: Request, res: Response) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const rawBody = (req.rawBody?.toString("utf8") ?? "") || "";
    if (!rawBody) {
      res.status(400).send("Empty ITN body");
      return;
    }

    const { ordered, map } = parseItnBody(rawBody);
    const receivedSignature = map["signature"] ?? "";

    // 1. MD5 signature verification (data integrity).
    if (!verifySignature(ordered, receivedSignature, PAYFAST_PASSPHRASE)) {
      logger.warn("payfastSubscriptionITN: signature mismatch", {
        mPaymentId: map["m_payment_id"],
      });
      res.status(403).send("Invalid signature");
      return;
    }

    // 2. Server-to-server validation with PayFast.
    const valid = await validateWithPayFast(rawBody, PAYFAST_VALIDATE_URL);
    if (!valid) {
      logger.warn("payfastSubscriptionITN: PayFast validation failed", {
        mPaymentId: map["m_payment_id"],
      });
      res.status(403).send("PayFast validation failed");
      return;
    }

    // 3. Resolve the subscriber (subscription-shaped m_payment_id only).
    const mPaymentId = map["m_payment_id"] ?? "";
    const { userId, tier: tierFromId } = parseSubscriptionPaymentId(mPaymentId);
    if (!userId) {
      logger.info("payfastSubscriptionITN: non-subscription ITN ignored", {
        mPaymentId,
      });
      res.status(200).send("Ignored");
      return;
    }
    const tier = map["custom_str2"] || tierFromId || "hunter";
    const promoCode = map["custom_str3"] ?? "";
    const paymentStatus = (map["payment_status"] ?? "").toUpperCase();

    const userRef = firestore().collection("users").doc(userId);

    if (paymentStatus === "COMPLETE") {
      // Renewal date: the ITN billing_date when present, else +30 days.
      let renewalDate: Date;
      const billingDateStr = map["billing_date"] ?? "";
      const parsed = new Date(billingDateStr);
      if (billingDateStr && !isNaN(parsed.getTime())) {
        renewalDate = parsed;
      } else {
        renewalDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      }
      await userRef.set(
        {
          subscriptionStatus: "active",
          subscriptionTier: tier,
          subscriptionRenewalDate: renewalDate,
          subscriptionPromoCode: promoCode,
          subscriptionPayfastPaymentId: map["pf_payment_id"] ?? "",
          // The recurring billing token used by the cancellation endpoint to
          // terminate future charges safely.
          subscriptionPayfastToken: map["token"] ?? "",
          subscriptionUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.info("payfastSubscriptionITN: subscription activated", {
        userId,
        tier,
        mPaymentId,
      });
      res.status(200).send("OK");
      return;
    }

    if (paymentStatus === "FAILED" || paymentStatus === "CANCELLED") {
      await userRef.set(
        {
          subscriptionStatus: "cancelled",
          subscriptionUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.info("payfastSubscriptionITN: subscription cancelled", {
        userId,
        paymentStatus,
        mPaymentId,
      });
      res.status(200).send("OK");
      return;
    }

    // Unknown / pending statuses are acknowledged without a state change.
    logger.info("payfastSubscriptionITN: unhandled payment_status", {
      userId,
      paymentStatus,
    });
    res.status(200).send("OK");
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 3. Subscription cancellation — safely terminate the recurring billing token
// ────────────────────────────────────────────────────────────────────────────

/** PayFast merchant id used by the cancellation endpoint (sandbox default). */
const PAYFAST_MERCHANT_ID = process.env.PAYFAST_MERCHANT_ID ?? "10053397";

/**
 * cancelSubscription
 *
 * HTTPS onRequest endpoint (public invoker; auth enforced via the Firebase
 * ID token). Flow:
 *   1. POST-only.
 *   2. `Authorization: Bearer <Firebase ID token>` verified with the Admin
 *      SDK; the body's `userId` must match the token's uid (an account may
 *      only cancel its own subscription).
 *   3. The stored `subscriptionPayfastToken` (persisted by the ITN handler
 *      on activation) is terminated server-to-server via PayFast's cancel
 *      API — fail-closed: the subscription is only marked cancelled when
 *      PayFast acknowledges the termination (or no token exists yet, e.g.
 *      inside the free trial before the first billing comes due).
 *   4. On success: users/{uid}.subscriptionStatus = "cancelled".
 */
export const cancelSubscription = onRequest(
  { region: "us-central1", invoker: "public", maxInstances: 10 },
  async (req: Request, res: Response) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    // 1. Authorization: Bearer Firebase ID token verified with the Admin SDK.
    const header = (req.headers.authorization ?? "").toString();
    const idToken = header.startsWith("Bearer ") ? header.substring(7) : "";
    let userIdFromToken: string | null = null;
    if (idToken) {
      try {
        const decoded = await getAdmin().auth().verifyIdToken(idToken);
        userIdFromToken = decoded.uid;
      } catch {
        userIdFromToken = null;
      }
    }
    if (!userIdFromToken) {
      res.status(401).send("Unauthorized");
      return;
    }

    // 2. Body: { userId } (JSON); the token's uid must match (own-account only).
    const body = (req.body ?? {}) as { userId?: string };
    const userId = (body.userId ?? "").toString().trim();
    if (!userId || userId !== userIdFromToken) {
      res.status(403).send("You may only cancel your own subscription");
      return;
    }

    // 3. Terminate the recurring billing token with PayFast (fail-closed).
    const userRef = firestore().collection("users").doc(userId);
    const snap = await userRef.get();
    const userData = snap.data() ?? {};
    const token = (userData["subscriptionPayfastToken"] ?? "").toString();
    let tokenTerminated = false;
    if (token) {
      tokenTerminated = await cancelPayfastSubscriptionToken(
        token,
        PAYFAST_MERCHANT_ID,
        PAYFAST_PASSPHRASE,
        PAYFAST_API_BASE
      );
      if (!tokenTerminated) {
        logger.warn("cancelSubscription: PayFast token termination failed", {
          userId,
        });
        res
          .status(502)
          .json({ result: "error", message: "Unable to confirm PayFast cancellation" });
        return;
      }
    }

    // 4. Mark the subscription cancelled on the user's profile.
    await userRef.set(
      {
        subscriptionStatus: "cancelled",
        subscriptionCancelledAt: new Date(),
        subscriptionUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    logger.info("cancelSubscription: subscription cancelled", {
      userId,
      tokenTerminated,
    });
    res.status(200).json({ result: "success", tokenTerminated });
  }
);

