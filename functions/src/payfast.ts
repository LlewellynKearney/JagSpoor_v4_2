import crypto from "crypto";

/**
 * PayFast ITN (Instant Transaction Notification) verification.
 *
 * Flow (per PayFast documentation):
 *   1. Receive POST body (form-urlencoded) at the ITN endpoint.
 *   2. Build the signature string = sorted params (excluding `signature`)
 *      URL-encoded, then append the passphrase if configured.
 *   3. md5(signatureString) === received `signature` param.
 *   4. Forward the params back to PayFast's validate endpoint
 *      (https://www.payfast.co.za/eng/query/validate) with an extra
 *      `confirmation_response=fpsitnactive` appended to the payload, and
 *      expect a literal `VALID` response.
 *
 * Passphrase (the merchant's "pass phrase" set in the PayFast settings)
 * is read from environment variable `PAYFAST_PASSPHRASE` (optional but
 * recommended in production). When absent, no passphrase is appended.
 */

export interface PayFastItnParams {
  m_payment_id?: string; // merchant payment id (we store bookingId here)
  pf_payment_id?: string; // PayFast's unique payment id
  payment_status?: string; // COMPLETE | FAILED | PENDING | CANCELLED
  item_name?: string;
  item_description?: string;
  amount_gross?: string;
  amount_fee?: string;
  amount_net?: string;
  custom_str1?: string;
  custom_str2?: string;
  custom_str3?: string;
  custom_int1?: string;
  custom_int2?: string;
  custom_int3?: string;
  name_first?: string;
  name_last?: string;
  email_address?: string;
  merchant_id?: string;
  signature?: string; // the md5 signature we verify against
  [key: string]: string | undefined;
}

const VALIDATE_HOST = "www.payfast.co.za";
const VALIDATE_PATH = "/eng/query/validate";
const CONFIRMATION_TOKEN = "fpsitnactive";

function getPassphrase(): string {
  return process.env.PAYFAST_PASSPHRASE ?? "";
}

/**
 * Parses a PayFast ITN form-urlencoded POST body into a params object.
 * Values may arrive multiple times for array fields; we keep first value.
 */
export function parseItnBody(rawBody: string): PayFastItnParams {
  const params: PayFastItnParams = {};
  if (!rawBody) return params;
  for (const pair of rawBody.split("&")) {
    const eqIdx = pair.indexOf("=");
    if (eqIdx === -1) continue;
    const key = decodeURIComponent(pair.slice(0, eqIdx).replace(/\+/g, " "));
    const val = decodeURIComponent(pair.slice(eqIdx + 1).replace(/\+/g, " "));
    if (params[key] === undefined) {
      params[key] = val;
    }
  }
  return params;
}

/**
 * Builds the parameter string used for signature generation, matching
 * PayFast's rules:
 *   - exclude the `signature` field itself
 *   - sort remaining keys alphabetically
 *   - url-encode each key=value pair
 *   - join with `&`
 *   - if a passphrase is configured, append `&passphrase=<encoded>`
 */
export function buildSignatureString(
  params: PayFastItnParams,
  passphrase: string = getPassphrase()
): string {
  const keys = Object.keys(params)
    .filter((k) => k !== "signature")
    .sort();

  const parts: string[] = [];
  for (const key of keys) {
    const val = params[key];
    if (val === undefined || val === null || val === "") continue;
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(val))}`);
  }

  if (passphrase) {
    parts.push(`passphrase=${encodeURIComponent(passphrase)}`);
  }

  return parts.join("&");
}

/**
 * Computes the expected md5 signature for the given params.
 */
export function computeSignature(
  params: PayFastItnParams,
  passphrase: string = getPassphrase()
): string {
  const sigString = buildSignatureString(params, passphrase);
  return crypto.createHash("md5").update(sigString, "utf8").digest("hex");
}

/**
 * Verifies the signature attached to the ITN params.
 * Constant-time compare to avoid timing-attack leaks.
 */
export function verifySignature(
  params: PayFastItnParams,
  passphrase: string = getPassphrase()
): boolean {
  const received = params.signature;
  if (!received || typeof received !== "string") return false;

  const expected = computeSignature(params, passphrase);
  if (expected.length !== received.length) return false;

  try {
    return crypto.timingSafeEqual(
      Buffer.from(expected, "utf8"),
      Buffer.from(received, "utf8")
    );
  } catch {
    return false;
  }
}

export interface ItnValidationResult {
  valid: boolean;
  rawResponse: string;
}

/**
 * Calls PayFast's server-to-server validation endpoint.
 *
 * Sends the ITN parameter string back, with
 * `&confirmation_response=fpsitnactive` appended, as a POST body. PayFast
 * responds with a literal `VALID`.
 */
export async function validateWithPayFast(
  params: PayFastItnParams,
  passphrase: string = getPassphrase()
): Promise<ItnValidationResult> {
  const keys = Object.keys(params).sort();
  const parts: string[] = [];
  for (const key of keys) {
    const val = params[key];
    if (val === undefined || val === null || val === "") continue;
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(val))}`);
  }
  if (passphrase) {
    parts.push(`passphrase=${encodeURIComponent(passphrase)}`);
  }
  parts.push(`confirmation_response=${CONFIRMATION_TOKEN}`);

  const body = parts.join("&");
  const url = `https://${VALIDATE_HOST}${VALIDATE_PATH}`;
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
      redirect: "manual",
    });
    const text = await res.text();
    const valid = text.trim().toUpperCase() === "VALID";
    return { valid, rawResponse: text };
  } catch (err) {
    return {
      valid: false,
      rawResponse: `validation_request_failed: ${
        err instanceof Error ? err.message : String(err)
      }`,
    };
  }
}

/** Sentinel string returned to PayFast when the signature check passes. */
export const PAYFAST_CONFIRMATION_TOKEN = CONFIRMATION_TOKEN;
