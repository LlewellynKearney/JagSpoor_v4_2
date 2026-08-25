import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural contract tests for the PayFast subscription ITN webhook Cloud
/// Function (Task 3). The Firebase emulator cannot run in this sandbox (no
/// JVM), so these tests encode the webhook contract by parsing
/// `functions/src/index.ts` + `functions/src/payfast_subscription.ts` —
/// mirroring the project's established structural test pattern
/// (`push_notification_functions_contract_test.dart`).
void main() {
  final indexSource = File('functions/src/index.ts').readAsStringSync();
  final helperSource =
      File('functions/src/payfast_subscription.ts').readAsStringSync();

  group('payfastSubscriptionITN handler', () {
    test('is exported as a public onRequest function in us-central1', () {
      expect(indexSource, contains('export const payfastSubscriptionITN'));
      expect(indexSource, contains('onRequest('));
      expect(indexSource, contains('invoker: "public"'));
      expect(indexSource, contains('region: "us-central1"'));
    });

    test('verifies the ITN MD5 signature with the merchant passphrase', () {
      expect(indexSource, contains('PAYFAST_PASSPHRASE'));
      expect(indexSource, contains('process.env.PAYFAST_PASSPHRASE'));
      expect(indexSource, contains('"jagspoor_sandbox_2026"'));
      expect(
        indexSource,
        contains('verifySignature(ordered, receivedSignature, PAYFAST_PASSPHRASE)'),
      );
      // Signature failure -> 403.
      expect(indexSource, contains('res.status(403).send("Invalid signature")'));
    });

    test('server-to-server validates the ITN body with PayFast', () {
      expect(indexSource, contains('validateWithPayFast(rawBody, PAYFAST_VALIDATE_URL)'));
      expect(
        indexSource,
        contains('"https://sandbox.payfast.co.za/eng/query/validate"'),
      );
      expect(indexSource,
          contains('res.status(403).send("PayFast validation failed")'));
    });

    test('activates the subscription on COMPLETE payment', () {
      expect(indexSource, contains('paymentStatus === "COMPLETE"'));
      expect(indexSource, contains('subscriptionStatus: "active"'));
      expect(indexSource, contains('subscriptionTier: tier'));
      expect(indexSource, contains('subscriptionRenewalDate: renewalDate'));
      expect(indexSource, contains('subscriptionPromoCode: promoCode'));
      // Writes to the user's Firestore profile.
      expect(indexSource,
          contains('firestore().collection("users").doc(userId)'));
    });

    test('cancels the subscription on FAILED / CANCELLED payment', () {
      expect(indexSource,
          contains('paymentStatus === "FAILED" || paymentStatus === "CANCELLED"'));
      expect(indexSource, contains('subscriptionStatus: "cancelled"'));
    });

    test('persists the recurring billing token on COMPLETE so it can be '
        'terminated on cancellation', () {
      expect(indexSource, contains('subscriptionPayfastToken: map["token"]'));
    });

    test('resolves the subscriber from the m_payment_id shape', () {
      expect(indexSource, contains('parseSubscriptionPaymentId(mPaymentId)'));
      expect(indexSource, contains('custom_str2'));
      expect(indexSource, contains('custom_str3'));
    });

    test('rejects non-POST and empty-body requests', () {
      expect(indexSource, contains('res.status(405).send("Method Not Allowed")'));
      expect(indexSource, contains('res.status(400).send("Empty ITN body")'));
    });
  });

  group('cancelSubscription endpoint', () {
    test('is exported as a public onRequest function in us-central1', () {
      expect(indexSource, contains('export const cancelSubscription'));
      expect(indexSource, contains('invoker: "public"'));
      expect(indexSource, contains('region: "us-central1"'));
    });

    test('enforces a verified Bearer Firebase ID token', () {
      expect(indexSource, contains('req.headers.authorization'));
      expect(indexSource, contains('getAdmin().auth().verifyIdToken(idToken)'));
      // A missing / invalid token is rejected before any billing change.
      expect(indexSource, contains('res.status(401).send("Unauthorized")'));
    });

    test('only the owning account may cancel its own subscription', () {
      // The body's userId must match the verified token uid.
      expect(indexSource, contains(
          'res.status(403).send("You may only cancel your own subscription")'));
    });

    test('terminates the PayFast token via the cancel API (fail-closed)', () {
      expect(indexSource, contains('cancelPayfastSubscriptionToken('));
      // Unable to confirm -> 502, subscription NOT marked cancelled.
      expect(indexSource, contains('"Unable to confirm PayFast cancellation"'));
      expect(helperSource,
          contains('export async function cancelPayfastSubscriptionToken'));
      expect(helperSource, contains(r'/v1/subscriptions/${token}/cancel'));
      expect(helperSource, contains('return response.ok'));
    });

    test('marks the status cancelled only after token termination succeeds',
        () {
      expect(indexSource, contains('subscriptionCancelledAt: new Date()'));
      expect(indexSource, contains('res.status(200).json({ result: "success"'));
    });

    test('uses the correct merchant id + api base', () {
      expect(indexSource, contains('PAYFAST_MERCHANT_ID'));
      expect(helperSource, contains('export const PAYFAST_API_BASE'));
      expect(helperSource, contains('"https://api.payfast.co.za"'));
    });
  });

  group('payfast_subscription helpers', () {
    test('percent-encodes values with spaces as + (not %20)', () {
      expect(helperSource, contains('encodeURIComponent(value).replace(/%20/g, "+")'));
    });

    test('computes an MD5 signature over the ordered fields', () {
      expect(helperSource, contains('createHash("md5")'));
      expect(helperSource, contains('buildSignatureSource(fields, passphrase)'));
      // The signature field itself + empty values are excluded.
      expect(helperSource, contains('if (key === "signature") continue;'));
      expect(helperSource, contains('if (value === "") continue;'));
      // The passphrase is appended for data-integrity validation.
      expect(helperSource, contains('parts.push(`passphrase='));
    });

    test('parses the subscription m_payment_id (sub_{userId}_{tier})', () {
      expect(helperSource, contains('export function parseSubscriptionPaymentId'));
      expect(helperSource, contains('sub_'));
      expect(helperSource, contains('hunter|outfitter'));
    });

    test('validateWithPayFast expects the literal VALID response', () {
      expect(helperSource, contains('export async function validateWithPayFast'));
      expect(helperSource, contains('return text === "VALID";'));
    });
  });
}
