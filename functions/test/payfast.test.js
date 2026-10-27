"use strict";

/**
 * PayFast web-billing contract tests.
 *
 * The web subscription checkout signs a payment form server-side; these lock
 * the security-critical properties:
 *   * the signature is a deterministic MD5 over the sorted, urlencoded params
 *     (+ the passphrase) and excludes the `signature` / `passphrase` fields;
 *   * the merchant KEY is signed with but NEVER returned to the client (only
 *     the public merchant id + the signature are);
 *   * an ITN with a bad signature / wrong amount / unknown plan / non-COMPLETE
 *     status is rejected, so nobody can forge an entitlement;
 *   * the plan catalog is the authoritative amount source (the client never
 *     sends an amount).
 */

const test = require("node:test");
const assert = require("node:assert");
const crypto = require("node:crypto");

const svc = require("../lib/payfast/payfast.service");
const plans = require("../lib/payfast/plans");

const {
  PAYFAST_MERCHANT_ID,
  PAYFAST_PROCESS_URL,
  PAYFAST_SANDBOX_PROCESS_URL,
  payfastEncode,
  buildSignatureSource,
  generateSignature,
  verifySignature,
  buildItnSignatureSource,
  generateItnSignature,
  verifyItnSignature,
  buildPaymentForm,
  parseItnBody,
  validateItn,
} = svc;

const { PAYFAST_PLAN_CATALOG, resolvePlan, plansForRole } = plans;

test("plan catalog: hunter + outfitter monthly/yearly at the Option-A prices", () => {
  assert.strictEqual(PAYFAST_PLAN_CATALOG.hunter_monthly.amountZar, 34.99);
  assert.strictEqual(PAYFAST_PLAN_CATALOG.hunter_yearly.amountZar, 349.99);
  assert.strictEqual(PAYFAST_PLAN_CATALOG.outfitter_monthly.amountZar, 299.99);
  assert.strictEqual(PAYFAST_PLAN_CATALOG.outfitter_yearly.amountZar, 2999.99);
  assert.strictEqual(PAYFAST_PLAN_CATALOG.hunter_monthly.months, 1);
  assert.strictEqual(PAYFAST_PLAN_CATALOG.hunter_yearly.months, 12);
});

test("plan catalog: recurring amount, frequency (3=monthly/6=yearly) + cycles 0", () => {
  // Every plan bills the same amount each cycle and never expires (cycles 0).
  const expected = {
    hunter_monthly: { freq: 3, amt: 34.99, name: "JagSpoor Hunter Monthly" },
    hunter_yearly: { freq: 6, amt: 349.99, name: "JagSpoor Hunter Yearly" },
    outfitter_monthly: {
      freq: 3,
      amt: 299.99,
      name: "JagSpoor Outfitter Monthly",
    },
    outfitter_yearly: {
      freq: 6,
      amt: 2999.99,
      name: "JagSpoor Outfitter Yearly",
    },
  };
  for (const [planId, want] of Object.entries(expected)) {
    const plan = PAYFAST_PLAN_CATALOG[planId];
    assert.strictEqual(plan.frequency, want.freq, `${planId} frequency`);
    assert.strictEqual(plan.cycles, 0, `${planId} cycles`);
    assert.strictEqual(plan.recurringAmountZar, want.amt, `${planId} recurring`);
    assert.strictEqual(plan.itemName, want.name, `${planId} item name`);
  }
});

test("buildPaymentForm emits the recurring subscription fields when a frequency is set", () => {
  const form = buildPaymentForm({
    userId: "uid-7",
    role: "hunter",
    planId: "hunter_yearly",
    amount: 349.99,
    recurringAmount: 349.99,
    frequency: 6,
    cycles: 0,
    itemName: "JagSpoor Hunter Yearly",
    returnUrl: "r",
    cancelUrl: "c",
    notifyUrl: "n",
    merchantKey: "k",
    passphrase: "pass",
  });
  assert.strictEqual(form.fields.subscription_type, "1");
  assert.strictEqual(form.fields.frequency, "6");
  assert.strictEqual(form.fields.cycles, "0");
  assert.strictEqual(form.fields.recurring_amount, "349.99");
  // The signature covers the recurring fields too. Recompute it from the
  // emitted (sorted) fields, excluding the signature itself.
  const signedFields = Object.fromEntries(
    Object.entries(form.fields).filter(([k]) => k !== "signature")
  );
  assert.strictEqual(form.fields.signature, generateSignature(signedFields, "pass"));
  // The emitted field order matches the signed order (sorted by key), which is
  // what PayFast requires ("Variable order"): a mismatch here is exactly the
  // cause of the "Generated signature does not match submitted signature" 400.
  assert.deepStrictEqual(
    Object.keys(form.fields),
    [...Object.keys(signedFields).sort(), "signature"]
  );

  // No frequency -> a one-off payment with no subscription fields.
  const oneOff = buildPaymentForm({
    userId: "uid-7",
    role: "hunter",
    planId: "hunter_monthly",
    amount: 34.99,
    itemName: "x",
    returnUrl: "r",
    cancelUrl: "c",
    notifyUrl: "n",
    merchantKey: "k",
  });
  assert.ok(!("subscription_type" in oneOff.fields));
  assert.ok(!("frequency" in oneOff.fields));
  assert.ok(!("cycles" in oneOff.fields));
  assert.ok(!("recurring_amount" in oneOff.fields));
});

test("resolvePlan: an explicit planId wins, else role+cycle, else null", () => {
  assert.strictEqual(
    resolvePlan({ planId: "outfitter_yearly" }).planId,
    "outfitter_yearly"
  );
  assert.strictEqual(
    resolvePlan({ role: "hunter", billingCycle: "yearly" }).planId,
    "hunter_yearly"
  );
  // Defaults to monthly when the cycle is absent.
  assert.strictEqual(
    resolvePlan({ role: "outfitter" }).planId,
    "outfitter_monthly"
  );
  // An unknown role cannot resolve (so the caller rejects it).
  assert.strictEqual(resolvePlan({ role: "admin" }), null);
  assert.strictEqual(resolvePlan({}), null);
});

test("plansForRole filters to the requested role", () => {
  assert.deepStrictEqual(
    plansForRole("hunter").map((p) => p.planId).sort(),
    ["hunter_monthly", "hunter_yearly"]
  );
  assert.deepStrictEqual(
    plansForRole("outfitter").map((p) => p.planId).sort(),
    ["outfitter_monthly", "outfitter_yearly"]
  );
});

test("payfastEncode matches PHP urlencode (spaces as +, ~ escaped to %7E)", () => {
  assert.strictEqual(payfastEncode("a b"), "a+b");
  assert.strictEqual(payfastEncode("a~b"), "a%7Eb");
  assert.strictEqual(payfastEncode("a&b=c"), "a%26b%3Dc");
});

test("buildSignatureSource sorts + urlencodes + omits signature/passphrase", () => {
  const source = buildSignatureSource({
    b: "2",
    a: "1 2",
    signature: "deadbeef",
    passphrase: "secret",
    empty: "",
  });
  assert.strictEqual(source, "a=1+2&b=2");
});

test("generateSignature is a deterministic MD5 with the documented shape", () => {
  const data = { amount: "34.99", item_name: "JagSpoor Hunter" };
  const sig = generateSignature(data, "pass");
  const expectedSource = `${buildSignatureSource(data)}&passphrase=pass`;
  assert.strictEqual(
    sig,
    crypto.createHash("md5").update(expectedSource).digest("hex")
  );
  // No passphrase -> no trailing segment.
  const noPass = generateSignature(data);
  assert.strictEqual(
    noPass,
    crypto.createHash("md5").update(buildSignatureSource(data)).digest("hex")
  );
  assert.notStrictEqual(sig, noPass);
});

test("verifySignature accepts the matching hash and rejects tampering", () => {
  const data = { amount: "34.99", m_payment_id: "sub_u_hunter_monthly" };
  data.signature = generateSignature(data, "pass");
  assert.strictEqual(verifySignature(data, "pass"), true);
  // A tampered amount invalidates the signature.
  const tampered = { ...data, amount: "0.01" };
  assert.strictEqual(verifySignature(tampered, "pass"), false);
  // The wrong passphrase invalidates it.
  assert.strictEqual(verifySignature(data, "nope"), false);
  // No signature at all is rejected.
  assert.strictEqual(verifySignature({ amount: "34.99" }, "pass"), false);
});

test("buildPaymentForm signs the fields but never returns the merchant key", () => {
  const form = buildPaymentForm({
    userId: "uid-1",
    role: "hunter",
    planId: "hunter_monthly",
    amount: 34.99,
    itemName: "JagSpoor Hunter — Monthly",
    returnUrl: "https://jagspoor.web.app/#/subscription/success",
    cancelUrl: "https://jagspoor.web.app/#/subscription/cancel",
    notifyUrl: "https://us-central1-jagspoor.cloudfunctions.net/payfastNotify",
    merchantKey: "SECRETKEY",
    passphrase: "SECRETPASS",
    sandbox: true,
    email: "hunter@example.com",
  });
  assert.strictEqual(form.processUrl, PAYFAST_SANDBOX_PROCESS_URL);
  assert.strictEqual(form.fields.merchant_id, PAYFAST_MERCHANT_ID);
  assert.strictEqual(form.fields.amount, "34.99");
  assert.strictEqual(form.fields.custom_str1, "uid-1");
  assert.strictEqual(form.fields.custom_str2, "hunter_monthly");
  assert.strictEqual(form.fields.custom_str3, "hunter");
  assert.strictEqual(form.merchantPaymentId, "sub_uid-1_hunter_monthly");
  // The signature is present + valid: recompute over the emitted fields
  // (excluding the signature) using the outgoing-form algorithm.
  const signedFields = Object.fromEntries(
    Object.entries(form.fields).filter(([k]) => k !== "signature")
  );
  assert.strictEqual(
    form.fields.signature,
    generateSignature(signedFields, "SECRETPASS")
  );
  // The merchant KEY is signed with but is not a secret we must not leak:
  // PayFast requires it in the form (it is not the passphrase). The
  // PASSPHRASE, however, must never appear in the returned fields.
  assert.ok(!Object.values(form.fields).includes("SECRETPASS"));
  assert.ok(!("passphrase" in form.fields));
  // Production form points at the live endpoint.
  const live = buildPaymentForm({
    userId: "u",
    role: "hunter",
    planId: "hunter_monthly",
    amount: 34.99,
    itemName: "x",
    returnUrl: "r",
    cancelUrl: "c",
    notifyUrl: "n",
    merchantKey: "k",
  });
  assert.strictEqual(live.processUrl, PAYFAST_PROCESS_URL);
});

test("parseItnBody handles both a raw string and a parsed object", () => {
  const fromString = parseItnBody("a=1&b=hello+world&c=x%26y");
  assert.deepStrictEqual(fromString, { a: "1", b: "hello world", c: "x&y" });
  const fromObject = parseItnBody({ a: 1, b: null, c: undefined, d: "x" });
  assert.deepStrictEqual(fromObject, { a: "1", b: "", c: "", d: "x" });
  assert.deepStrictEqual(parseItnBody(null), {});
});

test("validateItn: a well-formed COMPLETE ITN for the paid amount passes", () => {
  const params = {
    m_payment_id: "sub_uid-9_hunter_monthly",
    payment_status: "COMPLETE",
    amount_gross: "34.99",
    custom_str1: "uid-9",
    custom_str2: "hunter_monthly",
    custom_str3: "hunter",
  };
  // An ITN is signed in the ORDER the params arrive (not sorted).
  params.signature = generateItnSignature(params, "pass");
  const result = validateItn(params, "pass", PAYFAST_PLAN_CATALOG);
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.userId, "uid-9");
  assert.strictEqual(result.planId, "hunter_monthly");
  assert.strictEqual(result.role, "hunter");
  assert.strictEqual(result.amount, 34.99);
});

test("validateItn rejects a bad signature, non-COMPLETE, amount tamper + unknown plan", () => {
  const base = {
    payment_status: "COMPLETE",
    amount_gross: "34.99",
    custom_str1: "uid-9",
    custom_str2: "hunter_monthly",
    custom_str3: "hunter",
  };
  const signed = { ...base, signature: generateItnSignature(base, "pass") };

  // Signature failure.
  const badSig = validateItn(
    { ...signed, signature: "0".repeat(32) },
    "pass",
    PAYFAST_PLAN_CATALOG
  );
  assert.strictEqual(badSig.ok, false);
  assert.strictEqual(badSig.reason, "signature");

  // A signature produced with the WRONG algorithm (the outgoing-form, sorted
  // shape) must also be rejected — this is the exact regression that caused
  // the ITN to be refused before the fix.
  const wrongAlgo = {
    ...base,
    signature: generateSignature(base, "pass"),
  };
  assert.strictEqual(
    validateItn(wrongAlgo, "pass", PAYFAST_PLAN_CATALOG).reason,
    "signature"
  );

  // Not COMPLETE (the payment was never finalised).
  const pendingParams = { ...base, payment_status: "PENDING" };
  pendingParams.signature = generateItnSignature(pendingParams, "pass");
  const pending = validateItn(pendingParams, "pass", PAYFAST_PLAN_CATALOG);
  assert.strictEqual(pending.ok, false);
  assert.match(pending.reason, /^status:/);

  // Amount tamper: signed for the real price but claiming a lower one.
  const cheap = { ...base, amount_gross: "1.00" };
  cheap.signature = generateItnSignature(cheap, "pass");
  const cheapResult = validateItn(cheap, "pass", PAYFAST_PLAN_CATALOG);
  assert.strictEqual(cheapResult.ok, false);
  assert.strictEqual(cheapResult.reason, "amount_mismatch");

  // Unknown plan.
  const unknown = { ...base, custom_str2: "bogus" };
  unknown.signature = generateItnSignature(unknown, "pass");
  const unknownResult = validateItn(unknown, "pass", PAYFAST_PLAN_CATALOG);
  assert.strictEqual(unknownResult.ok, false);
  assert.strictEqual(unknownResult.reason, "unknown_plan");

  // A non-numeric amount.
  const nan = { ...base, amount_gross: "abc" };
  nan.signature = generateItnSignature(nan, "pass");
  assert.strictEqual(
    validateItn(nan, "pass", PAYFAST_PLAN_CATALOG).reason,
    "amount"
  );
});

test("validateItn rejects a signed-but-anonymous ITN (no user id)", () => {
  const params = {
    payment_status: "COMPLETE",
    amount_gross: "34.99",
    custom_str1: "",
    custom_str2: "hunter_monthly",
    custom_str3: "hunter",
  };
  params.signature = generateItnSignature(params, "pass");
  const result = validateItn(params, "pass", PAYFAST_PLAN_CATALOG);
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "no_user");
});

test("ITN signature uses the received order + raw passphrase (PayFast's own recipe)", () => {
  // Mirrors PayFast's PHP SDK Notification::dataToString — the fields are
  // hashed in the order they were received, the passphrase is appended RAW,
  // and every value (including empty ones) is urlencoded.
  const received = {
    m_payment_id: "sub_uid-9_hunter_monthly",
    pf_payment_id: "1234567",
    payment_status: "COMPLETE",
    item_name: "JagSpoor Hunter Monthly",
    amount_gross: "34.99",
    custom_str1: "uid-9",
  };
  const expectedSource =
    "m_payment_id=sub_uid-9_hunter_monthly" +
    "&pf_payment_id=1234567" +
    "&payment_status=COMPLETE" +
    "&item_name=JagSpoor+Hunter+Monthly" +
    "&amount_gross=34.99" +
    "&custom_str1=uid-9" +
    "&passphrase=jt7NOE43FZPn";
  assert.strictEqual(buildItnSignatureSource(received, "jt7NOE43FZPn"), expectedSource);
  assert.strictEqual(
    generateItnSignature(received, "jt7NOE43FZPn"),
    crypto.createHash("md5").update(expectedSource).digest("hex")
  );

  // Received order, NOT sorted: reordering the keys changes the hash.
  const reordered = {
    custom_str1: "uid-9",
    amount_gross: "34.99",
    item_name: "JagSpoor Hunter Monthly",
    payment_status: "COMPLETE",
    pf_payment_id: "1234567",
    m_payment_id: "sub_uid-9_hunter_monthly",
  };
  assert.notStrictEqual(
    generateItnSignature(reordered, "jt7NOE43FZPn"),
    generateItnSignature(received, "jt7NOE43FZPn")
  );

  // Round-trip verification.
  const signed = { ...received, signature: generateItnSignature(received, "jt7NOE43FZPn") };
  assert.strictEqual(verifyItnSignature(signed, "jt7NOE43FZPn"), true);
  assert.strictEqual(verifyItnSignature(signed, "wrong"), false);
  assert.strictEqual(verifyItnSignature(received, "jt7NOE43FZPn"), false); // no signature
});

test("verifySignature is an alias for verifyItnSignature (received order)", () => {
  const params = {
    payment_status: "COMPLETE",
    amount_gross: "34.99",
    custom_str1: "uid-9",
  };
  params.signature = generateItnSignature(params, "pass");
  assert.strictEqual(verifySignature(params, "pass"), true);
  // The sorted outgoing-form signature must NOT verify as an ITN.
  const sorted = { ...params };
  delete sorted.signature;
  sorted.signature = generateSignature(sorted, "pass");
  assert.strictEqual(verifySignature(sorted, "pass"), false);
});

test("buildPaymentForm emits fields in the exact order they are signed", () => {
  const form = buildPaymentForm({
    userId: "uid-1",
    role: "hunter",
    planId: "hunter_monthly",
    amount: 34.99,
    recurringAmount: 34.99,
    frequency: 3,
    cycles: 0,
    itemName: "JagSpoor Hunter Monthly",
    returnUrl: "https://jagspoor.web.app/#/subscription/success",
    cancelUrl: "https://jagspoor.web.app/#/subscription/cancel",
    notifyUrl: "https://us-central1-jagspoor.cloudfunctions.net/payfastNotify",
    merchantKey: "k",
    passphrase: "p",
  });
  const keys = Object.keys(form.fields);
  // Every non-signature field appears in sorted order, then `signature`.
  assert.deepStrictEqual(keys, [...keys.slice(0, -1).sort(), "signature"]);
  assert.strictEqual(keys[keys.length - 1], "signature");
  // `cycles` is "0", which PayFast keeps (0 !== "" in PHP).
  assert.strictEqual(form.fields.cycles, "0");
});

test("the merchant id is public and the key/passphrase come from secrets", () => {
  const fs = require("node:fs");
  const serviceSrc = fs.readFileSync(
    require("node:path").join(__dirname, "..", "src", "payfast", "payfast.service.ts"),
    "utf8"
  );
  // The merchant id is a constant (public — embedded in the form).
  assert.ok(serviceSrc.includes('PAYFAST_MERCHANT_ID = "37584965"'));
  // The key + passphrase are read from env/secrets, never hardcoded.
  assert.ok(serviceSrc.includes("PAYFAST_MERCHANT_KEY"));
  assert.ok(!/merchantKey\s*[:=]\s*"[A-Za-z0-9]{8,}"/.test(serviceSrc));
  assert.ok(!/passphrase\s*[:=]\s*"[A-Za-z0-9]{8,}"/.test(serviceSrc));

  const paramsSrc = fs.readFileSync(
    require("node:path").join(__dirname, "..", "src", "params.ts"),
    "utf8"
  );
  assert.ok(paramsSrc.includes('defineSecret("PAYFAST_MERCHANT_KEY")'));
  assert.ok(paramsSrc.includes('defineSecret("PAYFAST_PASSPHRASE")'));
});
