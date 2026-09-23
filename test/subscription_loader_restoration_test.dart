import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Task 2 (v9.2): v9.1 deleted the subscription loader (`_loadSubscription` /
/// `restorePurchases`) from the hunter + outfitter dashboards while removing
/// the dashboard price labels. The side effect was that a Google Play purchase
/// was NEVER written to Firestore — the `purchases` collection stayed empty
/// and `users/{uid}` never mirror the purchased subscription, so a subscriber
/// (e.g. Stuart, b9HLbAlMOdg56AlXZWXW9Plpael1) stayed locked out.
///
/// These structural contracts lock the restoration so it cannot silently
/// regress again.
void main() {
  final hunter = File('lib/features/hunter_mode/hunter_dashboard.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final outfitter = File('lib/features/outfitter_mode/outfitter_dashboard.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final recorder =
      File('lib/features/subscription/services/play_purchase_recorder.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
  final screen = File('lib/features/subscription/subscription_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('subscription loader restored on the dashboards', () {
    test('hunter dashboard restores + listens for purchases in initState', () {
      expect(hunter, contains('_loadSubscription();'));
      expect(hunter, contains('PlayPurchaseRecorder.instance.startListening()'));
      expect(
        hunter,
        contains('PlayBillingService.instance.restorePurchases()'),
      );
      expect(
        hunter,
        contains('SubscriptionStatusService.instance.getMySubscription()'),
      );
    });

    test('outfitter dashboard restores + listens for purchases in initState',
        () {
      expect(outfitter, contains('_loadSubscription();'));
      expect(
        outfitter,
        contains('PlayPurchaseRecorder.instance.startListening()'),
      );
      expect(
        outfitter,
        contains('PlayBillingService.instance.restorePurchases()'),
      );
    });

    test('the restore call is guarded by a billing-supported check', () {
      // `restorePurchases` must not be attempted on a device without Play
      // Billing (it would log a platform error on every launch).
      expect(hunter, contains('isBillingSupported()'));
      expect(outfitter, contains('isBillingSupported()'));
    });
  });

  group('purchase writes reach Firestore', () {
    test('the recorder writes the users doc subscription fields', () {
      expect(recorder, contains("'subscriptionStatus': subscriptionStatusActive"));
      expect(recorder, contains("'isPro': true"));
      expect(recorder, contains("'subscriptionTier': tier.key"));
    });

    test('the recorder writes the purchases collection document', () {
      expect(recorder, contains("const String purchasesCollection = 'purchases';"));
      expect(recorder, contains("collection(purchasesCollection)"));
      expect(recorder, contains("'uid': uid"));
      expect(recorder, contains("'productId': productId"));
      expect(recorder, contains("'purchaseToken': purchaseToken"));
      expect(recorder, contains("'status': status"));
    });

    test('the subscription screen records the purchase after a success', () {
      expect(screen, contains('PlayPurchaseRecorder.instance.recordPurchase('));
      expect(screen, contains('purchase.productID'));
      expect(
        screen,
        contains('purchase.verificationData.serverVerificationData'),
      );
    });
  });
}
