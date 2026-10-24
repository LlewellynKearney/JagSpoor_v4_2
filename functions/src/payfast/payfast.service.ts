/**
 * PayFast payment service (web / non-Play billing).
 *
 * PayFast is South Africa's payment gateway. JagSpoor uses it for the **web**
 * checkout only — the Android app keeps Google Play Billing (Play policy
 * requires it for in-app digital goods). The Flutter web build calls the
 * `createPayFastPayment` callable, which returns the signed form data the
 * browser posts to PayFast's hosted checkout; PayFast then redirects the user
 * back and POSTs an ITN (Instant Transaction Notification) to `payfastNotify`.
 *
 * SECURITY
 * --------
 * - The merchant **key** (`PAYFAST_MERCHANT_KEY`) and **passphrase**
 *   (`PAYFAST_PASSPHRASE`) are read from Cloud Functions *secrets*
 *   (`defineSecret`), never from the client and never committed to git.
 * - The client sends only `{role, planId, billingCycle}` — the server resolves
 *   the amount from the plan catalog, so a tampered amount cannot be charged.
 * - The ITN signature is verified (MD5 over the sorted params + passphrase)
 *   before any entitlement is granted, and the amount is re-checked against
 *   the plan.
 */

import { createHash } from "crypto";

/** PayFast's production process URL (where the browser posts the form). */
export const PAYFAST_PROCESS_URL = "https://www.payfast.co.za/eng/process";

/** PayFast's sandbox process URL (used when PAYFAST_SANDBOX=true). */
export const PAYFAST_SANDBOX_PROCESS_URL =
  "https://sandbox.payfast.co.za/eng/process";

/**
 * PayFast's server-to-server validation endpoint. After an ITN arrives the
 * server posts the payload back here; PayFast replies `VALID` for a genuine
 * notification. Kept for parity with the legacy handler.
 */
export const PAYFAST_VALIDATE_URL =
  "https://www.payfast.co.za/eng/query/validate";

/** The JagSpoor merchant id (public — safe to embed in the form). */
export const PAYFAST_MERCHANT_ID = "37584965";

/**
 * Encodes a value the way PayFast expects for signature generation: PHP's
 * `urlencode` — spaces become `+`, and `~` is escaped to `%7E` (PHP's
 * urlencode does not treat `~` as an unreserved character, unlike JS
 * `encodeURIComponent`, which is why the extra replacements are required).
 */
export function payfastEncode(value: string): string {
  return encodeURIComponent(value)
    .replace(/%20/g, "+")
    .replace(/[!'()*~]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}

/**
 * Builds the canonical signature source string from a param map:
 * sorted by key, `key=urlencoded(value)` pairs joined with `&`, with the
 * `signature` / `passphrase` fields excluded. The passphrase is appended
 * afterwards by the caller when one is configured.
 */
export function buildSignatureSource(data: Record<string, string>): string {
  return Object.keys(data)
    .filter((k) => k !== "signature" && k !== "passphrase")
    .filter((k) => data[k] !== undefined && data[k] !== null && data[k] !== "")
    .sort()
    .map((k) => `${k}=${payfastEncode(String(data[k]))}`)
    .join("&");
}

/**
 * Generates the PayFast MD5 signature:
 *   md5( sorted urlencoded query string [&passphrase=<passphrase>] )
 *
 * The passphrase is only appended when one is configured (PayFast allows
 * signing without a passphrase).
 */
export function generateSignature(
  data: Record<string, string>,
  passphrase?: string
): string {
  const source = buildSignatureSource(data);
  const withPass =
    passphrase && passphrase.length > 0
      ? `${source}&passphrase=${payfastEncode(passphrase)}`
      : source;
  return createHash("md5").update(withPass).digest("hex");
}

/**
 * Verifies an ITN signature. Returns false when the notification carries no
 * signature or the recomputed hash does not match (constant-time-ish compare
 * by lower-casing both sides; MD5 hashes are public values so a timing attack
 * is not a practical concern, but we normalise case to be safe).
 */
export function verifySignature(
  data: Record<string, string>,
  passphrase?: string
): boolean {
  const provided = (data["signature"] ?? "").toLowerCase();
  if (!provided) return false;
  const expected = generateSignature(data, passphrase);
  return provided === expected;
}

/** Input accepted by [buildPaymentForm]. */
export interface CreatePaymentInput {
  /** The uid the entitlement will be granted to. */
  userId: string;
  /** `hunter` | `outfitter`. */
  role: string;
  /** Catalog plan id (`hunter_monthly`, …). */
  planId: string;
  /** ZAR amount (resolved server-side from the plan). */
  amount: number;
  /**
   * The recurring ZAR amount billed each cycle (PayFast `recurring_amount`).
   * Defaults to [amount] when omitted.
   */
  recurringAmount?: number;
  /**
   * PayFast `frequency` code for a recurring subscription: 3 = monthly,
   * 6 = yearly. Omitted -> a one-off payment (no `subscription_type`).
   */
  frequency?: number;
  /** PayFast `cycles` (0 = until cancelled). Only used with [frequency]. */
  cycles?: number;
  /** Item name shown on the checkout. */
  itemName: string;
  /** URL PayFast redirects to on success. */
  returnUrl: string;
  /** URL PayFast redirects to on cancel. */
  cancelUrl: string;
  /** URL PayFast POSTs the ITN to. */
  notifyUrl: string;
  /** PayFast merchant id (defaults to [PAYFAST_MERCHANT_ID]). */
  merchantId?: string;
  /** The merchant key secret (never logged, never returned to the client). */
  merchantKey: string;
  /** Optional passphrase secret. */
  passphrase?: string;
  /** When true, sign against the sandbox process URL. */
  sandbox?: boolean;
  /** Optional user email (prefills the PayFast checkout). */
  email?: string;
  /**
   * When true, the payment originated from Google Play's **User Choice
   * Billing** flow (the user chose PayFast over Play Billing on Android). It
   * is carried through as `custom_str4` so the ITN can stamp the entitlement
   * with `payfast_alternative` instead of plain `payfast`, keeping the
   * alternative-billing service fee reconcilable against the Play invoice.
   */
  alternativeBilling?: boolean;
}

export interface PaymentForm {
  /** The URL the browser should POST the form to. */
  processUrl: string;
  /** The signed form fields (`name` -> `value`), including `signature`. */
  fields: Record<string, string>;
  /** The merchant payment reference (PayFast `m_payment_id`). */
  merchantPaymentId: string;
}

/**
 * Builds the signed PayFast payment form the web client posts to the hosted
 * checkout. The returned `fields` include the merchant id, amount, item name,
 * the three redirect URLs and the MD5 `signature`.
 */
export function buildPaymentForm(input: CreatePaymentInput): PaymentForm {
  const merchantPaymentId = `sub_${input.userId}_${input.planId}`;
  const amount = input.amount.toFixed(2);
  const fields: Record<string, string> = {
    merchant_id: input.merchantId ?? PAYFAST_MERCHANT_ID,
    merchant_key: input.merchantKey,
    return_url: input.returnUrl,
    cancel_url: input.cancelUrl,
    notify_url: input.notifyUrl,
    name_first: "JagSpoor",
    // `email_address` prefills the payer email when known.
    ...(input.email ? { email_address: input.email } : {}),
    m_payment_id: merchantPaymentId,
    amount: amount,
    item_name: input.itemName,
    // Carry the uid + plan through the payment so the ITN can resolve the
    // entitlement even if the email lookup is ambiguous.
    custom_str1: input.userId,
    custom_str2: input.planId,
    custom_str3: input.role,
    // Marks a User Choice Billing (alternative billing) payment so the ITN
    // stamps `payfast_alternative` on the entitlement. Always present (the
    // signature covers it) so a tampered client cannot flip the flag.
    custom_str4: input.alternativeBilling === true ? "alt_billing" : "standard",
  };
  // Recurring subscription fields (PayFast `subscription_type=1`). The
  // recurring amount equals the first charge; `cycles=0` bills until the
  // subscriber cancels. Omitted when no `frequency` is supplied so a plan
  // without a billing cycle stays a one-off payment.
  if (input.frequency != null) {
    fields.subscription_type = "1";
    fields.frequency = String(input.frequency);
    fields.cycles = String(input.cycles ?? 0);
    fields.recurring_amount = (input.recurringAmount ?? input.amount).toFixed(2);
  }
  fields.signature = generateSignature(fields, input.passphrase);
  return {
    processUrl: input.sandbox
      ? PAYFAST_SANDBOX_PROCESS_URL
      : PAYFAST_PROCESS_URL,
    fields,
    merchantPaymentId,
  };
}

/**
 * Parses a PayFast ITN body into a flat `Record<string, string>`. The body may
 * arrive already parsed (the functions runtime parses `application/x-www-form-
 * urlencoded` into an object) or as a raw string (tests / a manual replay).
 */
export function parseItnBody(body: unknown): Record<string, string> {
  if (typeof body === "string") {
    const out: Record<string, string> = {};
    for (const pair of body.split("&")) {
      if (!pair) continue;
      const idx = pair.indexOf("=");
      const rawKey = idx === -1 ? pair : pair.slice(0, idx);
      const rawValue = idx === -1 ? "" : pair.slice(idx + 1);
      out[decodeURIComponent(rawKey.replace(/\+/g, " "))] = decodeURIComponent(
        rawValue.replace(/\+/g, " ")
      );
    }
    return out;
  }
  if (body && typeof body === "object") {
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(body as Record<string, unknown>)) {
      out[k] = v === undefined || v === null ? "" : String(v);
    }
    return out;
  }
  return {};
}

/** Result of validating an ITN against the plan catalog. */
export interface ItnValidation {
  ok: boolean;
  /** The uid carried in `custom_str1` (or resolved from the payment id). */
  userId: string;
  /** The plan id carried in `custom_str2`. */
  planId: string;
  /** The role carried in `custom_str3`. */
  role: string;
  /** Parsed gross amount. */
  amount: number;
  /**
   * True when the ITN carries the User Choice Billing marker
   * (`custom_str4 == "alt_billing"`), i.e. the user chose PayFast through
   * Google Play's alternative billing flow.
   */
  alternativeBilling: boolean;
  /** Reason the ITN was rejected (when `ok` is false). */
  reason?: string;
}

/**
 * Validates an ITN: signature, COMPLETE status, and amount against the plan
 * catalog. Pure (no Firestore) so it is unit-testable.
 */
export function validateItn(
  params: Record<string, string>,
  passphrase: string | undefined,
  plans: Record<string, { amountZar: number }>
): ItnValidation {
  const empty: ItnValidation = {
    ok: false,
    userId: "",
    planId: "",
    role: "",
    amount: 0,
    alternativeBilling: false,
    reason: "invalid",
  };
  if (!verifySignature(params, passphrase)) {
    return { ...empty, reason: "signature" };
  }
  const status = (params["payment_status"] ?? "").toUpperCase();
  if (status !== "COMPLETE") {
    return { ...empty, reason: `status:${status}` };
  }
  const planId = (params["custom_str2"] ?? "").trim();
  const userId = (params["custom_str1"] ?? "").trim();
  const role = (params["custom_str3"] ?? "").trim();
  // User Choice Billing marker. Present on every form we build, so its absence
  // simply means a standard (non-alternative) checkout.
  const alternativeBilling =
    (params["custom_str4"] ?? "").trim().toLowerCase() === "alt_billing";
  const amount = parseFloat(params["amount_gross"] ?? "");
  if (Number.isNaN(amount)) {
    return { ...empty, reason: "amount" };
  }
  const plan = plans[planId];
  if (!plan) {
    return {
      ...empty,
      planId,
      userId,
      role,
      amount,
      alternativeBilling,
      reason: "unknown_plan",
    };
  }
  if (Math.abs(amount - plan.amountZar) > 0.01) {
    return {
      ...empty,
      planId,
      userId,
      role,
      amount,
      alternativeBilling,
      reason: "amount_mismatch",
    };
  }
  if (!userId) {
    return { ...empty, planId, role, amount, alternativeBilling, reason: "no_user" };
  }
  return { ok: true, userId, planId, role, amount, alternativeBilling };
}

/**
 * Resolves the PayFast merchant key from the environment. In production this
 * is supplied by the `PAYFAST_MERCHANT_KEY` secret (mounted by `defineSecret`);
 * the value is never logged.
 */
export function merchantKeyFromEnv(): string {
  return (process.env.PAYFAST_MERCHANT_KEY ?? "").trim();
}

/** Resolves the PayFast passphrase from the environment (may be empty). */
export function passphraseFromEnv(): string {
  return (process.env.PAYFAST_PASSPHRASE ?? "").trim();
}

/** Whether the sandbox process URL should be used. */
export function isSandbox(): boolean {
  return (process.env.PAYFAST_SANDBOX ?? "").trim().toLowerCase() === "true";
}
