import { logger } from "firebase-functions/v2";
import {
  onRequest,
  onCall,
  HttpsError,
  type CallableRequest,
} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import type { Request, Response } from "express";
import { type Firestore, FieldValue } from "firebase-admin/firestore";
import { firestore, auth, getAdmin } from "./firebase";
import {
  parseItnBody,
  verifySignature,
  validateWithPayFast,
  PAYFAST_CONFIRMATION_TOKEN,
} from "./payfast";

// ────────────────────────────────────────────────────────────────────────────
// 1. PayFast Instant Transaction Notification (ITN) handler
// ────────────────────────────────────────────────────────────────────────────

/**
 * payfastITNHandler
 *
 * HTTPS (onRequest) Cloud Function registered at:
 *   <region>-<project>.cloudfunctions.net/payfastITNHandler
 *
 * Receives a `application/x-www-form-urlencoded` POST from PayFast after a
 * payment is processed. Verifies the md5 signature, then performs a
 * server-to-server validation call back to PayFast's validate endpoint.
 * On a confirmed `COMPLETE` payment it updates the booking document.
 *
 * Booking linkage: the Flutter client passes the Firestore booking id as
 * `m_payment_id` when constructing the PayFast payment request; PayFast
 * echoes it back in the ITN unchanged.
 *
 * Environment variables:
 *   - PAYFAST_PASSPHRASE (optional): the merchant pass phrase. Set in
 *     Firebase console → Functions → Configuration.
 */
export const payfastITNHandler = onRequest(
  {
    region: "us-central1",
    maxInstances: 10,
    // PayFast sends form-urlencoded bodies; default Cloud Functions parser
    // handles it, but we set invocationType to public (no auth).
    invoker: "public",
  },
  async (req: Request, res: Response) => {
    // PayFast only uses POST. Reject everything else early.
    if (req.method !== "POST") {
      res.status(405).type("text/plain").send("Method Not Allowed");
      return;
    }

    // We deliberately read the *raw* body to guarantee byte-exact signature
    // verification. firebase-functions v2 exposes the raw body via
    // `req.rawBody` (a Buffer) when the content type is form-urlencoded.
    const rawReq = req as Request & { rawBody?: Buffer | string };
    const rawBody: string =
      rawReq.rawBody instanceof Buffer
        ? rawReq.rawBody.toString("utf8")
        : typeof req.body === "string"
          ? req.body
          : new URLSearchParams(req.body ?? "").toString();

    const params = parseItnBody(rawBody);

    // ── Step 1: signature verification ────────────────────────────────
    if (!verifySignature(params)) {
      logger.warn("PayFast ITN: signature verification failed", {
        m_payment_id: params.m_payment_id,
      });
      // Still 200 to stop PayFast retrying; but do not confirm.
      res.status(200).type("text/plain").send("signature_invalid");
      return;
    }

    // ── Step 2: server-to-server validation ────────────────────────────
    const validation = await validateWithPayFast(params);
    if (!validation.valid) {
      logger.warn("PayFast ITN: server validation failed", {
        m_payment_id: params.m_payment_id,
        raw: validation.rawResponse,
      });
      res.status(200).type("text/plain").send("validation_failed");
      return;
    }

    // ── Step 3: process the payment status ─────────────────────────────
    const bookingId = params.m_payment_id;
    const pfPaymentId = params.pf_payment_id;
    const itemName = params.item_name;
    const paymentStatus = (params.payment_status ?? "").toUpperCase();

    if (!bookingId) {
      logger.error("PayFast ITN: missing m_payment_id", { params });
      res.status(200).type("text/plain").send(PAYFAST_CONFIRMATION_TOKEN);
      return;
    }

    if (paymentStatus !== "COMPLETE") {
      logger.info("PayFast ITN: non-complete status, no booking update", {
        bookingId,
        paymentStatus,
      });
      // Confirm receipt so PayFast stops retrying.
      res.status(200).type("text/plain").send(PAYFAST_CONFIRMATION_TOKEN);
      return;
    }

    // ── Step 4: update the booking document to `Paid` ─────────────────
    try {
      const bookingRef = firestore().collection("bookings").doc(bookingId);
      const snap = await bookingRef.get();

      if (!snap.exists) {
        logger.error("PayFast ITN: booking not found", { bookingId });
        // Confirm anyway to halt retries; an orphan ITN should be logged.
        res.status(200).type("text/plain").send(PAYFAST_CONFIRMATION_TOKEN);
        return;
      }

      await bookingRef.update({
        status: "Paid",
        paymentTimestamp: FieldValue.serverTimestamp(),
        payfastpfPaymentId: pfPaymentId ?? null,
        itemName: itemName ?? null,
        paymentStatus,
        updatedAt: FieldValue.serverTimestamp(),
      });

      logger.info("PayFast ITN: booking marked Paid", {
        bookingId,
        pfPaymentId,
        itemName,
      });
    } catch (err) {
      logger.error("PayFast ITN: booking update failed", {
        bookingId,
        error: err instanceof Error ? err.message : String(err),
      });
      // Return 500 so PayFast retries the ITN; we want the write to land.
      res.status(500).type("text/plain").send("booking_update_failed");
      return;
    }

    // ── Step 5: confirm receipt to PayFast ─────────────────────────────
    res.status(200).type("text/plain").send(PAYFAST_CONFIRMATION_TOKEN);
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 2. Admin: create outfitter account + document + custom claims
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
    case "approved":
      return "Your booking has been approved!";
    case "paid":
      return "Your booking is now Paid!";
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
 * onBookingUpdated
 *
 * Firestore trigger (v2) on `bookings/{bookingId}`.
 *
 * Fires only when the `status` field changes between the before/after
 * snapshots. The recipient is the "other" party:
 *   - if the hunter changed it (`updatedBy == hunterId`) → alert the outfitter
 *   - otherwise (outfitter or system, e.g. the PayFast ITN webhook) → alert
 *     the hunter.
 * When `updatedBy` is absent, the hunter is alerted by default, since most
 * status transitions (approval, payment, decline) are outfitter/system
 * initiated and the hunter is the interested party.
 *
 * Push payload:
 *   - title: "Booking Status Update"
 *   - body:  e.g. "Your booking is now Paid!"
 *   - data:  { bookingId, type: "booking" }
 */
export const onBookingUpdated = onDocumentUpdated(
  { document: "bookings/{bookingId}", region: "us-central1" },
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const beforeStatus = (before.status as string | undefined) ?? "";
    const afterStatus = (after.status as string | undefined) ?? "";
    if (beforeStatus === afterStatus) return;

    const bookingId = event.params.bookingId;
    const hunterId = (after.hunterId as string | undefined) ?? "";
    const outfitterId = (after.outfitterId as string | undefined) ?? "";
    const actorId = (after.updatedBy as string | undefined) ?? "";

    const recipientId =
      actorId && actorId === hunterId ? outfitterId : hunterId;
    if (!recipientId) return;

    const userSnap = await firestore()
      .collection("users")
      .doc(recipientId)
      .get();
    if (!userSnap.exists) return;
    const tokens = extractFcmTokens((userSnap.data() ?? {}).fcmTokens);
    if (tokens.length === 0) {
      logger.info("onBookingUpdated: recipient has no FCM tokens", {
        bookingId,
        recipientId,
      });
      return;
    }

    await sendFcm(
      tokens,
      "Booking Status Update",
      bookingStatusBody(afterStatus),
      { bookingId, type: "booking" }
    );
  }
);
