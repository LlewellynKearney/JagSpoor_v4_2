import { createHash } from "crypto";

/**
 * PayFast subscription ITN (Instant Transaction Notification) helpers.
 *
 * The PayFast signature scheme: every posted field (in the order received,
 * excluding `signature` itself, excluding empty values) is concatenated as
 * `key=value` pairs joined with `&`, each value percent-encoded with spaces
 * as `+` (NOT `%20`), and the merchant passphrase appended as
 * `&passphrase=<encoded>`. The MD5 hex digest of that string is the
 * signature.
 */

/** PayFast percent-encoding: RFC 3986 with spaces as `+`. */
export function pfEncode(value: string): string {
  return encodeURIComponent(value).replace(/%20/g, "+");
}

/**
 * Builds the signature source string from the received ITN fields. The
 * entries are processed in insertion order (the order the ITN body was
 * parsed), skipping `signature` and empty values.
 */
export function buildSignatureSource(
  fields: Array<[string, string]>,
  passphrase?: string
): string {
  const parts: string[] = [];
  for (const [key, value] of fields) {
    if (key === "signature") continue;
    if (value === "") continue;
    parts.push(`${key}=${pfEncode(value)}`);
  }
  if (passphrase) {
    parts.push(`passphrase=${pfEncode(passphrase)}`);
  }
  return parts.join("&");
}

/** MD5 hex digest of the PayFast signature source. */
export function computeSignature(
  fields: Array<[string, string]>,
  passphrase?: string
): string {
  return createHash("md5")
    .update(buildSignatureSource(fields, passphrase))
    .digest("hex");
}

/** Verifies a received ITN signature against the expected MD5. */
export function verifySignature(
  fields: Array<[string, string]>,
  receivedSignature: string,
  passphrase?: string
): boolean {
  return computeSignature(fields, passphrase) === receivedSignature.toLowerCase();
}

/**
 * Parses an `application/x-www-form-urlencoded` ITN body into an ordered
 * field list (order preserved for signature verification) plus a lookup map.
 */
export function parseItnBody(body: string): {
  ordered: Array<[string, string]>;
  map: Record<string, string>;
} {
  const ordered: Array<[string, string]> = [];
  const map: Record<string, string> = {};
  for (const pair of body.split("&")) {
    if (!pair) continue;
    const eq = pair.indexOf("=");
    const rawKey = eq === -1 ? pair : pair.substring(0, eq);
    const rawValue = eq === -1 ? "" : pair.substring(eq + 1);
    const key = decodeURIComponent(rawKey.replace(/\+/g, " "));
    const value = decodeURIComponent(rawValue.replace(/\+/g, " "));
    ordered.push([key, value]);
    map[key] = value;
  }
  return { ordered, map };
}

/**
 * Server-to-server validation: posts the raw ITN body back to PayFast's
 * `validate` endpoint and expects the literal string `VALID`. Returns false
 * on any network / non-VALID outcome (fail-closed).
 */
export async function validateWithPayFast(
  body: string,
  validateUrl: string
): Promise<boolean> {
  try {
    const response = await fetch(validateUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
    const text = (await response.text()).trim();
    return text === "VALID";
  } catch {
    return false;
  }
}

/**
 * Extracts the subscriber user id + tier from the `m_payment_id` written by
 * the checkout payload (`sub_{userId}_{tier}`). Returns nulls when the id
 * does not match the subscription shape.
 */
export function parseSubscriptionPaymentId(mPaymentId: string): {
  userId: string | null;
  tier: string | null;
} {
  const match = /^sub_(.+)_(hunter|outfitter)$/.exec(mPaymentId);
  if (!match) return { userId: null, tier: null };
  return { userId: match[1], tier: match[2] };
}
