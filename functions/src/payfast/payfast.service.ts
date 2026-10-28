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
 * - The ITN signature is verified (MD5 over the params **in the order PayFast
 *   sends them**, + passphrase — see `verifyItnSignature`) before any
 *   entitlement is granted, and the amount is re-checked against the plan.
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
 * Encodes a value exactly the way PHP's `urlencode()` does, which is what
 * PayFast's signature algorithm requires:
 *
 *  * a space becomes `+` (NOT `%20` — the single most common cause of a
 *    "Generated signature does not match submitted signature" 400, which the
 *    hosted checkout surfaces to the shopper as a generic 500-style error);
 *  * `~` is escaped to `%7E` (PHP's `urlencode` predates RFC 3986 and does not
 *    treat `~` as unreserved, unlike JS `encodeURIComponent`);
 *  * `!` `'` `(` `)` `*` are escaped as `%21` `%27` `%28` `%29` `%2A`.
 *
 * `encodeURIComponent` leaves all six of those characters literal, so each one
 * must be ENCODED here — not decoded. Getting the direction backwards (a
 * `%21` -> `!` style replacement) is a no-op on the escaped form and produces
 * a hash that PayFast rejects with "Generated signature does not match
 * submitted signature" (a 400 on `/eng/process`).
 *
 * The value is trimmed first, matching PayFast's own reference implementation
 * (`urlencode( trim( $val ) )`).
 */
export function payfastEncode(value: string): string {
  return encodeURIComponent(String(value).trim())
    .replace(/%20/g, "+")
    .replace(/!/g, "%21")
    .replace(/'/g, "%27")
    .replace(/\(/g, "%28")
    .replace(/\)/g, "%29")
    .replace(/\*/g, "%2A")
    .replace(/~/g, "%7E");
}

/**
 * Builds the signature source string for the **hosted-checkout form**.
 *
 * PayFast signs the variables in the order they are submitted (see the
 * "Variable order" warning in Step 2 of the PayFast docs: *"The pairs must be
 * listed in the order in which they appear in the attributes description. Do
 * not use the API signature format, which uses alphabetical ordering!"*).
 *
 * [buildPaymentForm] therefore emits its fields in the alphabetically sorted
 * order this function produces, so the submitted order and the signed order are
 * identical. Empty values are dropped (`if($val !== '')` in PayFast's own
 * `generateSignature`) — but `cycles=0` is kept, because `"0" !== ""` in PHP.
 * The `signature` field is excluded; the passphrase (when configured) is
 * appended last.
 */
export function buildSignatureSource(
  data: Record<string, string>,
  passphrase?: string
): string {
  const source = Object.keys(data)
    .filter((k) => k !== "signature" && k !== "passphrase")
    .filter((k) => {
      const v = data[k];
      return v !== undefined && v !== null && String(v).trim() !== "";
    })
    .sort()
    .map((k) => `${k}=${payfastEncode(String(data[k]))}`)
    .join("&");
  const trimmedPass = (passphrase ?? "").trim();
  return trimmedPass === ""
    ? source
    : `${source}&passphrase=${payfastEncode(trimmedPass)}`;
}

/** Placeholder substituted for the passphrase value in a logged source. */
export const SIGNATURE_SOURCE_PASSPHRASE_MASK = "<redacted>";

/**
 * Masks the passphrase at the tail of a signature source string.
 *
 * [buildSignatureSource] appends the encoded passphrase as the final
 * `&passphrase=<value>` segment. That segment is the one part of the source
 * that must never reach a log, because the passphrase is a Cloud Functions
 * secret. Everything else is a public form value.
 *
 * The masked string stays structurally identical — same fields, same order,
 * same encoding, same segment count — so it is still diffable against a
 * recomputed source; only the secret value itself is replaced.
 */
export function redactSignatureSourcePassphrase(source: string): string {
  const marker = "&passphrase=";
  const idx = source.lastIndexOf(marker);
  if (idx === -1) return source;
  return `${source.slice(0, idx)}${marker}${SIGNATURE_SOURCE_PASSPHRASE_MASK}`;
}

/**
 * The signature source string hashed by the most recent [generateSignature]
 * call, with the passphrase value masked — see
 * [redactSignatureSourcePassphrase].
 *
 * A rejected checkout can only be diagnosed by diffing the string we hashed
 * against the one PayFast recomputes, because PayFast answers a bad MD5 with a
 * generic "Generated signature does not match submitted signature" and never
 * echoes its own source. This is the string that was actually hashed (not a
 * re-derivation from the emitted form), so it is the authoritative value to
 * compare.
 *
 * The MD5 is a public value (it travels in the form), so logging the hash is
 * safe; the passphrase is the only secret in the source and is masked.
 */
let lastSignatureSource: string | null = null;

/**
 * The signature source string hashed by the most recent [generateSignature],
 * passphrase masked. Returns null before the first call.
 */
export function getLastSignatureSource(): string | null {
  return lastSignatureSource;
}

/**
 * Generates the PayFast MD5 signature for a hosted-checkout form:
 *   md5( urlencoded query string [&passphrase=<passphrase>] )
 *
 * The passphrase is only appended when one is configured (PayFast allows
 * signing without a passphrase, but subscriptions require one).
 *
 * The source string is cached (passphrase masked) so `createPayFastPayment`
 * can log exactly what was hashed — see [getLastSignatureSource].
 */
export function generateSignature(
  data: Record<string, string>,
  passphrase?: string
): string {
  const source = buildSignatureSource(data, passphrase);
  lastSignatureSource = redactSignatureSourcePassphrase(source);
  return createHash("md5").update(source).digest("hex");
}

/**
 * Builds the signature source string for an **ITN** (Instant Transaction
 * Notification) exactly as PayFast computes it.
 *
 * An ITN is different from the outgoing form: PayFast signs the parameters
 * **in the order they arrive**, appends the raw passphrase (not urlencoded),
 * and excludes only the `signature` field. This mirrors the reference
 * implementation in PayFast's own PHP SDK
 * (`PaymentIntegrations/Notification::dataToString`) and the WooCommerce
 * gateway, which verifies with `sort = false` — *not* the sorted API format.
 *
 * Empty values are preserved here (unlike the outgoing form) because the ITN
 * contains whatever PayFast sent; dropping one would change the hash.
 */
export function buildItnSignatureSource(
  data: Record<string, string>,
  passphrase?: string
): string {
  let source = Object.keys(data)
    .filter((k) => k !== "signature")
    .map((k) => `${k}=${payfastEncode(String(data[k]))}`)
    .join("&");
  const rawPass = passphrase ?? "";
  if (rawPass !== "") {
    source += `&passphrase=${rawPass}`;
  }
  return source;
}

/**
 * Generates the MD5 hash PayFast publishes in an ITN's `signature` field.
 * Use [verifyItnSignature] to check one — never compare against
 * [generateSignature], which uses the outgoing-form (sorted) shape.
 */
export function generateItnSignature(
  data: Record<string, string>,
  passphrase?: string
): string {
  return createHash("md5")
    .update(buildItnSignatureSource(data, passphrase))
    .digest("hex");
}

/**
 * Verifies an ITN signature against the parameters in the order they were
 * received. Returns false when the notification carries no signature or the
 * recomputed hash does not match (MD5 hashes are public values, so a
 * lower-cased string compare is sufficient — no timing-attack concern).
 */
export function verifyItnSignature(
  data: Record<string, string>,
  passphrase?: string
): boolean {
  const provided = String(data["signature"] ?? "").toLowerCase();
  if (!provided) return false;
  return provided === generateItnSignature(data, passphrase);
}

/**
 * Backwards-compatible alias for [verifyItnSignature].
 *
 * The original implementation used the outgoing-form (sorted) algorithm, which
 * never matches a real ITN; keeping the name pointing at the correct ITN
 * verifier means every existing caller is fixed by this change.
 */
export function verifySignature(
  data: Record<string, string>,
  passphrase?: string
): boolean {
  return verifyItnSignature(data, passphrase);
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
  // Emit the fields in the SAME order the signature is computed over (sorted
  // by key). PayFast signs the variables in the order they are submitted
  // ("Variable order" — see buildSignatureSource), so the signed order and the
  // posted order must match or the checkout rejects the signature.
  const ordered: Record<string, string> = {};
  for (const key of Object.keys(fields).sort()) {
    ordered[key] = fields[key];
  }
  ordered.signature = generateSignature(fields, input.passphrase);
  return {
    processUrl: input.sandbox
      ? PAYFAST_SANDBOX_PROCESS_URL
      : PAYFAST_PROCESS_URL,
    fields: ordered,
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
 *
 * The signature check uses [verifyItnSignature] — the received-order algorithm
 * PayFast actually publishes in an ITN — NOT the sorted outgoing-form
 * signature produced by [generateSignature].
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
  if (!verifyItnSignature(params, passphrase)) {
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
