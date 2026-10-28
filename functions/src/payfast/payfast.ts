/**
 * PayFast Cloud Functions endpoints (web / non-Play billing).
 *
 *   createPayFastPayment  — callable, authenticated. Resolves the plan
 *                           server-side and returns the signed PayFast form
 *                           data the web client posts to the hosted checkout.
 *   payfastNotify         — onRequest, public. The ITN webhook: verifies the
 *                           signature + amount and grants the entitlement.
 *   payfastReturn         — onRequest, public. Redirects the browser back into
 *                           the app on success.
 *   payfastCancel         — onRequest, public. Redirects the browser back into
 *                           the app on cancel.
 *
 * The merchant key + passphrase are Cloud Functions secrets — see
 * `PAYFAST_MERCHANT_KEY_SECRET` / `PAYFAST_PASSPHRASE_SECRET` in params.ts.
 */

import { logger } from "firebase-functions/v2";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import type { Request, Response } from "express";
import { writeEntitlement, SUBSCRIPTION_SOURCE_PAYFAST } from "../entitlement";
import {
  grantAlternativeBillingEntitlement,
  recordAlternativeBillingFromItn,
} from "../alternative_billing";
import {
  buildPaymentForm,
  parseItnBody,
  validateItn,
  merchantKeyFromEnv,
  passphraseFromEnv,
  isSandbox,
} from "./payfast.service";
import {
  PAYFAST_PLAN_CATALOG,
  resolvePlan,
  plansForRole,
} from "./plans";
import {
  payfastMerchantKey,
  payfastPassphrase,
  PAYFAST_MERCHANT_KEY_SECRET_NAME,
  PAYFAST_PASSPHRASE_SECRET_NAME,
} from "../params";

/**
 * The web app's base URL. The PayFast return/cancel redirects land back here.
 *
 * The URL deliberately carries NO `#` fragment. Both values are submitted as
 * signed form fields, and a fragment makes the signed string fragile: the
 * browser drops everything after `#` when the checkout is opened as a GET URL,
 * so PayFast recomputes a different hash and rejects the checkout with
 * "Generated signature does not match submitted signature".
 */
export const WEB_APP_BASE_URL = "https://jag-spoor.co.za";

/** The ITN notify URL PayFast should POST to. */
export const PAYFAST_NOTIFY_URL =
  "https://us-central1-jagspoor.cloudfunctions.net/payfastNotify";

/** The success route the app navigates to after a completed checkout. */
export const PAYFAST_SUCCESS_URL = `${WEB_APP_BASE_URL}/subscription/success`;

/** The cancel route the app navigates to when the user abandons checkout. */
export const PAYFAST_CANCEL_URL = `${WEB_APP_BASE_URL}/subscription/cancel`;

interface CreatePaymentRequest {
  role?: string;
  planId?: string;
  billingCycle?: string;
  /**
   * True when the checkout was started from Google Play's User Choice Billing
   * flow on Android (the user actively chose PayFast over Play Billing). It is
   * carried through to the ITN as `custom_str4` so the entitlement records
   * `payfast_alternative` and the Play service fee stays reconcilable.
   */
  alternativeBilling?: boolean;
}

interface CreatePaymentResponse {
  processUrl: string;
  fields: Record<string, string>;
  merchantPaymentId: string;
  planId: string;
  amount: number;
}

/**
 * createPayFastPayment
 *
 * Authenticated callable. The client sends `{role, planId, billingCycle}`;
 * the server resolves the plan + amount from the catalog and returns the
 * signed form the browser posts to PayFast. The merchant key is used
 * server-side to sign but is NEVER returned to the client (only the public
 * `merchant_id` + the MD5 signature are).
 */
export const createPayFastPayment = onCall(
  {
    region: "us-central1",
    maxInstances: 20,
    secrets: [payfastMerchantKey, payfastPassphrase],
  },
  async (req): Promise<CreatePaymentResponse> => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in to start a PayFast checkout."
      );
    }
    const data = (req.data ?? {}) as CreatePaymentRequest;
    const plan = resolvePlan(data);
    if (!plan) {
      throw new HttpsError(
        "invalid-argument",
        "Unknown plan — expected a hunter/outfitter monthly or yearly plan."
      );
    }

    const merchantKey = merchantKeyFromEnv();
    if (!merchantKey) {
      logger.error(
        "createPayFastPayment: PAYFAST_MERCHANT_KEY secret not configured"
      );
      throw new HttpsError(
        "failed-precondition",
        "PayFast is not configured yet. Please try again later."
      );
    }

    const passphrase = passphraseFromEnv();
    const email = (req.auth?.token?.email as string | undefined) ?? undefined;
    const form = buildPaymentForm({
      userId: uid,
      role: plan.role,
      planId: plan.planId,
      amount: plan.amountZar,
      // Recurring subscription: the same amount is billed each month (freq 3)
      // or year (freq 6) until the subscriber cancels (cycles 0).
      recurringAmount: plan.recurringAmountZar,
      frequency: plan.frequency,
      cycles: plan.cycles,
      itemName: plan.itemName,
      returnUrl: PAYFAST_SUCCESS_URL,
      cancelUrl: PAYFAST_CANCEL_URL,
      notifyUrl: PAYFAST_NOTIFY_URL,
      merchantKey,
      passphrase,
      sandbox: isSandbox(),
      email,
      alternativeBilling: data.alternativeBilling === true,
    });

    logger.info("createPayFastPayment: form built", {
      uid,
      planId: plan.planId,
      amount: plan.amountZar,
      recurringAmount: form.fields.recurring_amount,
      frequency: form.fields.frequency,
      cycles: form.fields.cycles,
      processUrl: form.processUrl,
      merchantPaymentId: form.merchantPaymentId,
      sandbox: isSandbox(),
      alternativeBilling: data.alternativeBilling === true,
      // The MD5 is a public value (it travels in the form), so logging it is
      // safe and is the quickest way to diff a rejected checkout against the
      // "Generated signature does not match submitted signature" 400.
      signature: form.fields.signature,
    });

    return {
      processUrl: form.processUrl,
      fields: form.fields,
      merchantPaymentId: form.merchantPaymentId,
      planId: plan.planId,
      amount: plan.amountZar,
    };
  }
);

/**
 * payfastNotify
 *
 * The ITN webhook (public, POST from PayFast). Verifies the MD5 signature +
 * the paid amount against the plan catalog, then writes the server-authoritative
 * entitlement (`users/{uid}` + `entitlements/{uid}`) via [writeEntitlement].
 *
 * Always answers 200 for a well-formed but non-actionable notification so
 * PayFast does not retry endlessly; a signature failure answers 403.
 */
export const payfastNotify = onRequest(
  {
    region: "us-central1",
    maxInstances: 20,
    secrets: [payfastMerchantKey, payfastPassphrase],
  },
  async (req: Request, res: Response) => {
    const method = (req.method ?? "GET").toUpperCase();
    if (method === "GET") {
      res.status(200).send("OK (PayFast ITN endpoint — POST expected)");
      return;
    }
    if (method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const passphrase = passphraseFromEnv();
    const params = parseItnBody(req.body);
    const validation = validateItn(params, passphrase, PAYFAST_PLAN_CATALOG);
    if (!validation.ok) {
      // A signature failure is a hard reject; anything else is acknowledged so
      // PayFast stops retrying a notification we can never action.
      if (validation.reason === "signature") {
        logger.warn("payfastNotify: signature mismatch");
        res.status(403).send("Signature mismatch");
        return;
      }
      logger.warn("payfastNotify: ignored", { reason: validation.reason });
      res.status(200).send(`OK (ignored: ${validation.reason})`);
      return;
    }

    const plan = PAYFAST_PLAN_CATALOG[validation.planId];
    const premiumExpiry = new Date(
      Date.now() + plan.months * 30 * 24 * 60 * 60 * 1000
    );
    const paymentId = (params["pf_payment_id"] ?? "").trim();

    // A User Choice Billing (alternative billing) payment is stamped with its
    // own platform so the Play service fee stays reconcilable. The entitlement
    // grant is otherwise identical.
    if (validation.alternativeBilling) {
      await grantAlternativeBillingEntitlement({
        userId: validation.userId,
        planId: validation.planId,
        role: validation.role,
        payfastPaymentId: paymentId || undefined,
      });
      // Record/refresh the `alternative_billing_reports` row from the ITN so a
      // completed User Choice Billing payment always has a reportable
      // transaction (idempotent — never duplicates the client-written row).
      const reportId = await recordAlternativeBillingFromItn({
        userId: validation.userId,
        planId: validation.planId,
        role: validation.role,
        amountZar: validation.amount,
        payfastTransactionId: paymentId || undefined,
      });
      logger.info("payfastNotify: alternative billing entitlement granted", {
        uid: validation.userId,
        planId: validation.planId,
        amount: validation.amount,
        months: plan.months,
        reportId,
      });
      res.status(200).send("OK");
      return;
    }

    await writeEntitlement(validation.userId, {
      isPremium: true,
      premiumExpiry,
      subscriptionSource: SUBSCRIPTION_SOURCE_PAYFAST,
      subscriptionPlatform: SUBSCRIPTION_SOURCE_PAYFAST,
      subscriptionProduct: validation.planId,
      subscriptionStatus: "active",
      subscriptionTier: validation.role || plan.role,
      subscriptionRenewalDate: premiumExpiry,
      payfastPaymentId: paymentId || undefined,
    });

    logger.info("payfastNotify: entitlement granted", {
      uid: validation.userId,
      planId: validation.planId,
      amount: validation.amount,
      months: plan.months,
    });
    res.status(200).send("OK");
  }
);

/**
 * payfastReturn
 *
 * The success redirect target. PayFast redirects the browser here after a
 * completed checkout; we bounce the user into the hash-routed app so the
 * subscription screen can show the success state (the authoritative grant is
 * the ITN, which arrives independently).
 */
export const payfastReturn = onRequest(
  { region: "us-central1", maxInstances: 10 },
  (req: Request, res: Response) => {
    const target = PAYFAST_SUCCESS_URL;
    logger.info("payfastReturn: redirecting", { target });
    res.redirect(302, target);
  }
);

/**
 * payfastCancel
 *
 * The cancel redirect target. PayFast redirects the browser here when the user
 * abandons the checkout; we bounce them back into the app's cancel state.
 */
export const payfastCancel = onRequest(
  { region: "us-central1", maxInstances: 10 },
  (req: Request, res: Response) => {
    const target = PAYFAST_CANCEL_URL;
    logger.info("payfastCancel: redirecting", { target });
    res.redirect(302, target);
  }
);

/**
 * getBillingPlans
 *
 * Authenticated callable returning the PayFast plan catalog for the caller's
 * role, so the web subscription UI can render the role-filtered plans from the
 * single server-side source of truth (no duplicated price literals).
 */
export const getBillingPlans = onCall(
  { region: "us-central1", maxInstances: 20 },
  (req): { plans: ReturnType<typeof plansForRole> } => {
    const role = ((req.data as { role?: string } | undefined)?.role ?? "hunter")
      .toString()
      .trim()
      .toLowerCase();
    return { plans: plansForRole(role) };
  }
);

/** Secret names re-exported for tests / documentation. */
export const PAYFAST_SECRET_NAMES = {
  merchantKey: PAYFAST_MERCHANT_KEY_SECRET_NAME,
  passphrase: PAYFAST_PASSPHRASE_SECRET_NAME,
};
