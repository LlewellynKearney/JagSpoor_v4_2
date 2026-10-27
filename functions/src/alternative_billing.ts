import { logger } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
// Import ONLY the androidpublisher surface (never the `googleapis` umbrella —
// see the note in entitlement.ts: the umbrella import blows the Firebase CLI's
// 10s trigger-discovery budget).
import { androidpublisher } from "@googleapis/androidpublisher";
import { GoogleAuth } from "google-auth-library";
import { firestore } from "./firebase";
import {
  PACKAGE_NAME,
  SUBSCRIPTION_SOURCE_PAYFAST_ALTERNATIVE,
  writeEntitlement,
} from "./entitlement";
import { PAYFAST_PLAN_CATALOG } from "./payfast/plans";

/**
 * Google Play **User Choice Billing** (alternative billing) reporting.
 *
 * ## Why this exists
 *
 * South Africa is enrolled in Play's alternative billing programme. A user may
 * choose to pay JagSpoor through PayFast instead of Google Play Billing, and
 * Google still invoices a (reduced) service fee for that transaction. To make
 * that invoicing possible the Play Billing Library issues an **external
 * transaction token**, and the app must report the resulting transaction to
 * the Play Developer API.
 *
 * The client (see `lib/features/billing/alternative_billing_service.dart`)
 * obtains the token and writes a row to `alternative_billing_reports`. This
 * module turns such a row into a real `externaltransactions.create` call.
 *
 * ## Where the fee number lives
 *
 * `transactionProgramCode` selects the fee programme on Google's side; the
 * exact code for this app's enrolment is configured via the
 * `PLAY_ALT_BILLING_PROGRAM_CODE` env var (see `.env.example`). When it is
 * unset the transaction is reported WITHOUT a program code and Google applies
 * the programme attached to the account — reporting still succeeds, which is
 * the important part. The rate itself is recorded on the report document for
 * bookkeeping.
 *
 * ## Deployment note
 *
 * The reporting call requires the Cloud Functions service account to hold the
 * Android Publisher permission on the `jagspoor` project (the same grant
 * `validateGooglePlayPurchase` already needs). No additional secret is
 * required unless a dedicated service-account key is used, in which case the
 * existing `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` variable applies.
 */

/** The collection the client writes alternative-billing transactions to. */
export const ALTERNATIVE_BILLING_REPORTS_COLLECTION =
  "alternative_billing_reports";

/**
 * Google Play's reduced service fee for alternative billing transactions, in
 * basis points (2600 = 26%). Mirrors
 * `alternativeBillingServiceFeeBasisPoints` on the client. Confirm the exact
 * rate in Play Console → Monetization → Alternative billing.
 */
export const ALTERNATIVE_BILLING_FEE_BASIS_POINTS = 2600;

/** A report row as stored by the client. */
export interface AlternativeBillingReport {
  userId?: string;
  tier?: string;
  billingCycle?: string;
  planId?: string;
  alternativeSku?: string;
  amountZar?: number;
  serviceFeeBasisPoints?: number;
  serviceFeeZar?: number;
  payfastTransactionId?: string | null;
  reportingToken?: string | null;
  status?: string;
  program?: string;
}

/** Result of a reporting attempt. */
export interface ReportOutcome {
  ok: boolean;
  /** A machine-readable reason when `ok` is false. */
  reason?: string;
  /** The external transaction id Google assigned, when the call succeeded. */
  externalTransactionId?: string;
}

/**
 * Whether a report row carries everything the Play Developer API needs.
 *
 * Pure so it is unit-testable without Firestore or the network.
 */
export function validateReportRow(
  row: AlternativeBillingReport | undefined | null
): { ok: boolean; reason?: string } {
  if (!row) return { ok: false, reason: "missing_report" };
  const token = (row.reportingToken ?? "").trim();
  if (!token) return { ok: false, reason: "no_reporting_token" };
  const userId = (row.userId ?? "").trim();
  if (!userId) return { ok: false, reason: "no_user" };
  const amount = row.amountZar;
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0) {
    return { ok: false, reason: "bad_amount" };
  }
  return { ok: true };
}

/**
 * Builds the `externaltransactions.create` request body for a report row.
 *
 * Pure. Amounts are converted to micros (1/1,000,000 of the currency unit),
 * which is the representation the Play API expects. `transactionTime` is
 * required by the API; the caller supplies the report's timestamp (or now).
 *
 * The transaction is reported as a **recurring** external transaction keyed to
 * the user's external subscription, because JagSpoor's plans are
 * subscriptions (monthly / yearly), not one-time purchases.
 */
export function buildExternalTransaction(
  row: AlternativeBillingReport,
  opts: { transactionTime: Date; externalSubscriptionId: string; programCode?: number }
): Record<string, unknown> {
  const amount = row.amountZar ?? 0;
  const priceMicros = Math.round(amount * 1_000_000).toString();
  const body: Record<string, unknown> = {
    // The token Play issued for this transaction. This is what ties the
    // reported transaction to the alternative-billing flow the user completed.
    recurringTransaction: {
      externalTransactionToken: (row.reportingToken ?? "").trim(),
      externalSubscription: {
        subscriptionType: externalSubscriptionTypeFor(row.billingCycle),
      },
    },
    transactionTime: opts.transactionTime.toISOString(),
    // VAT-inclusive ZAR: the listed price IS the final charge (Option A), so
    // the pre-tax amount is derived by removing the 15% SA VAT.
    originalPreTaxAmount: {
      currency: "ZAR",
      priceMicros: Math.round((amount / 1.15) * 1_000_000).toString(),
    },
    originalTaxAmount: {
      currency: "ZAR",
      priceMicros: Math.round((amount - amount / 1.15) * 1_000_000).toString(),
    },
    userTaxAddress: {
      regionCode: "ZA",
    },
  };
  if (opts.programCode != null) {
    body.transactionProgramCode = opts.programCode;
  }
  return body;
}

/**
 * Maps a billing cycle to the Play `ExternalSubscription.subscriptionType`
 * value.
 *
 * Google's enum names are used verbatim; an unrecognised cycle falls back to
 * the monthly type so the transaction is still reported.
 */
export function externalSubscriptionTypeFor(cycle: string | undefined): string {
  const value = (cycle ?? "").trim().toLowerCase();
  if (value === "yearly" || value === "annual") {
    return "SUBSCRIPTION_TYPE_YEARLY";
  }
  return "SUBSCRIPTION_TYPE_MONTHLY";
}

/**
 * The external subscription id Google should group recurring transactions
 * under. One subscription per user+tier, so a monthly and a yearly purchase of
 * the same tier are treated as the same subscription series.
 */
export function externalSubscriptionIdFor(row: AlternativeBillingReport): string {
  const userId = (row.userId ?? "").trim();
  const tier = (row.tier ?? "hunter").trim().toLowerCase() || "hunter";
  return `jagspoor_${tier}_${userId}`;
}

/**
 * A stable, PII-free external transaction id.
 *
 * Google explicitly forbids storing personal data (emails etc.) in this field
 * and requires 1–63 chars of `[a-zA-Z0-9_-]`. A Firestore document id plus a
 * short hash of the PayFast reference satisfies both, and keeps the value
 * deterministic so a retry does not create a duplicate transaction.
 */
export function externalTransactionIdFor(
  reportId: string,
  row: AlternativeBillingReport
): string {
  const base = `js-alt-${(row.tier ?? "hunter").trim().toLowerCase() || "hunter"}-${reportId}`;
  const cleaned = base.replace(/[^a-zA-Z0-9_-]/g, "-");
  return cleaned.slice(0, 63);
}

/** Resolves an authenticated androidpublisher client (lazily). */
function androidPublisher() {
  const serviceAccountB64 = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
  const authOptions = serviceAccountB64
    ? {
        credentials: JSON.parse(
          Buffer.from(serviceAccountB64, "base64").toString("utf8")
        ),
      }
    : undefined;
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    ...authOptions,
  });
  return androidpublisher({ version: "v3", auth });
}

/** The optional Play alternative-billing programme code. */
export function programCodeFromEnv(): number | undefined {
  const raw = (process.env.PLAY_ALT_BILLING_PROGRAM_CODE ?? "").trim();
  if (!raw) return undefined;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}

/**
 * Reports one alternative-billing transaction to the Play Developer API.
 *
 * Returns a structured outcome rather than throwing so the caller (and the
 * operator) can see exactly why a row did not report. A `create` failure with
 * `alreadyExists` is treated as success — the transaction id is deterministic,
 * so a retry after a partial success must not be an error.
 */
export async function reportAlternativeBillingTransaction(opts: {
  reportId: string;
  row: AlternativeBillingReport;
  packageName?: string;
  transactionTime?: Date;
  programCode?: number;
}): Promise<ReportOutcome> {
  const validation = validateReportRow(opts.row);
  if (!validation.ok) {
    return { ok: false, reason: validation.reason };
  }
  const packageName = (opts.packageName ?? PACKAGE_NAME).trim();
  const externalTransactionId = externalTransactionIdFor(opts.reportId, opts.row);
  const body = buildExternalTransaction(opts.row, {
    transactionTime: opts.transactionTime ?? new Date(),
    externalSubscriptionId: externalSubscriptionIdFor(opts.row),
    programCode: opts.programCode ?? programCodeFromEnv(),
  });

  try {
    const api = androidPublisher();
    // NOTE: the generated client flattens the REST method name —
    // `externaltransactions.create` in the discovery document is exposed as
    // `createexternaltransaction` in @googleapis/androidpublisher.
    await api.externaltransactions.createexternaltransaction({
      parent: `applications/${packageName}`,
      externalTransactionId,
      requestBody: body as never,
    });
    return { ok: true, externalTransactionId };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    // A deterministic id means a retry after a partial success returns
    // ALREADY_EXISTS; that is a success for our purposes.
    if (/already.?exists|ALREADY_EXISTS|409/i.test(message)) {
      return { ok: true, externalTransactionId };
    }
    logger.error("alternative billing report failed", {
      reportId: opts.reportId,
      externalTransactionId,
      message,
    });
    return { ok: false, reason: `api:${message}` };
  }
}

/**
 * `reportAlternativeBillingTransaction` (callable).
 *
 * Invoked by the app after a PayFast payment completes on Android with the
 * User Choice Billing token. The caller may only report their OWN transaction
 * (the report document's `userId` must match the authenticated uid), and the
 * server re-reads the stored report rather than trusting client-supplied
 * amounts — so a tampered client cannot inflate or suppress a reported
 * transaction.
 *
 * On success the stored row moves to `status: 'reported'` and gains
 * `externalTransactionId` + `reportedAt`. On failure the row is left
 * `pending` (never deleted) so it stays visible for manual reconciliation.
 */
export const reportAlternativeBillingTransactionCallable = onCall(
  { region: "us-central1", maxInstances: 20 },
  async (req: { auth?: { uid?: string | null } | null; data?: unknown }) => {
    const uid = req.auth?.uid ?? null;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to report an alternative billing transaction."
      );
    }
    const input = (req.data ?? {}) as { reportId?: string };
    const reportId = (input.reportId ?? "").trim();
    if (!reportId) {
      throw new HttpsError("invalid-argument", "A reportId is required.");
    }

    const ref = firestore()
      .collection(ALTERNATIVE_BILLING_REPORTS_COLLECTION)
      .doc(reportId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "That report does not exist.");
    }
    const row = (snap.data() ?? {}) as AlternativeBillingReport;
    // Ownership: a user may only report their own transaction.
    if ((row.userId ?? "").trim() !== uid) {
      throw new HttpsError(
        "permission-denied",
        "You may only report your own transactions."
      );
    }

    const outcome = await reportAlternativeBillingTransaction({ reportId, row });
    if (!outcome.ok) {
      await ref.set(
        {
          status: "pending",
          lastReportError: outcome.reason ?? "unknown",
          lastReportAttemptAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      throw new HttpsError(
        "unavailable",
        `Google Play reporting failed: ${outcome.reason ?? "unknown"}`
      );
    }

    await ref.set(
      {
        status: "reported",
        externalTransactionId: outcome.externalTransactionId ?? null,
        reportedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("alternative billing reported", {
      reportId,
      uid,
      tier: row.tier,
      externalTransactionId: outcome.externalTransactionId,
    });

    return {
      ok: true,
      externalTransactionId: outcome.externalTransactionId ?? null,
      status: "reported",
    };
  }
);

/**
 * Grants the entitlement for a **verified** alternative-billing payment.
 *
 * Kept separate from the reporting call so the two concerns are independent:
 * reporting satisfies Google's invoicing requirement, while this grants the
 * subscriber their access. Called by `payfastNotify` when the ITN indicates the
 * payment originated from the User Choice Billing flow (`custom_str4`), which
 * is why the platform is stamped `payfast_alternative` rather than plain
 * `payfast`.
 */
export async function grantAlternativeBillingEntitlement(opts: {
  userId: string;
  planId: string;
  role: string;
  payfastPaymentId?: string;
}): Promise<void> {
  const plan = PAYFAST_PLAN_CATALOG[opts.planId];
  const months = plan?.months ?? 1;
  const premiumExpiry = new Date(Date.now() + months * 30 * 24 * 60 * 60 * 1000);
  await writeEntitlement(opts.userId, {
    isPremium: true,
    premiumExpiry,
    subscriptionSource: SUBSCRIPTION_SOURCE_PAYFAST_ALTERNATIVE,
    subscriptionPlatform: SUBSCRIPTION_SOURCE_PAYFAST_ALTERNATIVE,
    subscriptionProduct: opts.planId,
    subscriptionStatus: "active",
    subscriptionTier: opts.role || plan?.role || "hunter",
    subscriptionRenewalDate: premiumExpiry,
    payfastPaymentId: opts.payfastPaymentId || undefined,
  });
}

/**
 * Records (or updates) the `alternative_billing_reports` row for a completed
 * User Choice Billing payment, driven by the PayFast ITN.
 *
 * The app already writes a `pending` row when it launches the checkout (carrying
 * the Play-issued reporting token). This upsert makes the ITN the authority for
 * the payment half of that row — `payfastTransactionId`, `amountZar`, and the
 * `feeBps` / `serviceFeeZar` split — WITHOUT creating a duplicate:
 *
 *  * when a row already exists for the same user + plan (the normal case) it is
 *    updated in place, so the server-side reporter sees exactly one row;
 *  * when no row exists (a checkout started outside the app, or a client write
 *    that failed) a fresh `pending` row is created so the transaction stays
 *    visible for reporting;
 *  * a row the reporter has already accepted (`status: 'reported'`) is left
 *    untouched — re-writing it would discard the `externalTransactionId`
 *    Google assigned.
 *
 * Returns the document id, or null when the write failed. Never throws: the ITN
 * must always answer 200 once the entitlement has been granted.
 */
export async function recordAlternativeBillingFromItn(opts: {
  userId: string;
  planId: string;
  role: string;
  amountZar: number;
  payfastTransactionId?: string;
}): Promise<string | null> {
  const { userId, planId, role, amountZar } = opts;
  if (!userId || !planId) return null;
  const tier = (role || "hunter").trim().toLowerCase() || "hunter";
  const cycle = planId.trim().toLowerCase().endsWith("_yearly")
    ? "yearly"
    : "monthly";
  const feeBps = ALTERNATIVE_BILLING_FEE_BASIS_POINTS;
  const fee = Math.round(((amountZar * feeBps) / 10000) * 100) / 100;
  const payload: Record<string, unknown> = {
    userId,
    tier,
    billingCycle: cycle,
    planId,
    alternativeSku: `jagspoor_${planId}_payfast`,
    amountZar,
    // Written under BOTH spellings, matching the client writer: `feeBps` is the
    // operator-facing name, `serviceFeeBasisPoints` is what the reporter reads.
    serviceFeeBasisPoints: feeBps,
    feeBps,
    serviceFeeZar: fee,
    program: "user_choice_billing",
    ...(opts.payfastTransactionId
      ? { payfastTransactionId: opts.payfastTransactionId }
      : {}),
    updatedAt: FieldValue.serverTimestamp(),
  };
  try {
    const col = firestore().collection(ALTERNATIVE_BILLING_REPORTS_COLLECTION);
    const existing = await col
      .where("userId", "==", userId)
      .where("planId", "==", planId)
      .limit(1)
      .get();
    if (!existing.empty) {
      const doc = existing.docs[0];
      if (String(doc.get("status") ?? "") === "reported") return doc.id;
      await doc.ref.set(payload, { merge: true });
      return doc.id;
    }
    const ref = await col.add({
      ...payload,
      reportingToken: null,
      status: "pending",
      reportedAt: FieldValue.serverTimestamp(),
    });
    return ref.id;
  } catch (err) {
    logger.error("alternative billing ITN report write failed", {
      userId,
      planId,
      message: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}
