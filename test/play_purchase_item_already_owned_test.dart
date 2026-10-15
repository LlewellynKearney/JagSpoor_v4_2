import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_purchase_recorder.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/services/entitlement_service.dart';

/// `BillingResponse.itemAlreadyOwned` is NOT a purchase failure — the user
/// already holds the subscription. Before this fix it was logged as
/// `PlayPurchaseRecorder purchase error: IAPError(... itemAlreadyOwned)` and
/// the entitlement was never linked, so a legitimate subscriber stayed locked
/// out.
///
/// The fix restores the existing purchase, acknowledges it, and grants the
/// premium entitlement server-side. These tests lock that behaviour end to
/// end, including the headline contract: **a purchase with itemAlreadyOwned
/// results in isPremium = true**.
void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    PlayPurchaseRecorder.firestoreForTesting = fake;
    PlayPurchaseRecorder.currentUserIdResolverForTesting = () => 'uid-1';
    PlayPurchaseRecorder.purchaseStreamForTesting =
        const Stream<List<PurchaseDetails>>.empty();
    PlayBillingService.pastPurchasesForTesting = () async => const [];
    // Keep the recovery path hermetic: the plugin's real restore / complete
    // calls are replaced so the tests exercise only our own orchestration.
    PlayBillingService.restoreForTesting = () async {};
    PlayBillingService.completePurchaseForTesting = (_) async {};
  });

  tearDown(() {
    PlayPurchaseRecorder.resetTestSeams();
    PlayBillingService.resetTestSeams();
    EntitlementService.resetTestSeams();
  });

  PurchaseDetails purchase(
    String productId, {
    required PurchaseStatus status,
    String token = 'tok-existing',
    IAPError? error,
  }) {
    final details = PurchaseDetails(
      productID: productId,
      purchaseID: 'pid-existing',
      transactionDate: '${DateTime.now().millisecondsSinceEpoch}',
      status: status,
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: token,
        source: 'google_play',
      ),
    );
    details.error = error;
    return details;
  }

  /// The exact error shape the reporter saw on device:
  /// `IAPError(code: purchase_error, source: google_play,
  ///  message: BillingResponse.itemAlreadyOwned)`.
  IAPError itemAlreadyOwnedError() => IAPError(
        source: 'google_play',
        code: PlayBillingErrors.purchaseErrorCode,
        message: 'BillingResponse.itemAlreadyOwned',
      );

  group('PlayBillingErrors.isItemAlreadyOwned', () {
    test('detects the exact reported IAPError', () {
      expect(PlayBillingErrors.isItemAlreadyOwned(itemAlreadyOwnedError()),
          isTrue);
    });

    test('is case-insensitive and tolerant of spelling variants', () {
      for (final message in <String>[
        'BillingResponse.itemAlreadyOwned',
        'billingresponse.itemalreadyowned',
        'ITEM_ALREADY_OWNED',
        'item already owned',
        '7',
      ]) {
        expect(
          PlayBillingErrors.isItemAlreadyOwnedMessage(message),
          isTrue,
          reason: 'expected "$message" to be detected as itemAlreadyOwned',
        );
      }
    });

    test('does not mis-classify other billing errors', () {
      for (final message in <String>[
        'BillingResponse.developerError',
        'BillingResponse.serviceUnavailable',
        'BillingResponse.itemUnavailable',
        '17',
        '',
      ]) {
        expect(
          PlayBillingErrors.isItemAlreadyOwnedMessage(message),
          isFalse,
          reason: 'expected "$message" NOT to be itemAlreadyOwned',
        );
      }
      expect(PlayBillingErrors.isItemAlreadyOwned(null), isFalse);
    });

    test('also inspects the error details field', () {
      final error = IAPError(
        source: 'google_play',
        code: PlayBillingErrors.purchaseErrorCode,
        message: 'purchase_error',
        details: 'ItemAlreadyOwned (response: 7)',
      );
      expect(PlayBillingErrors.isItemAlreadyOwned(error), isTrue);
    });
  });

  group('PlayPurchaseRecorder itemAlreadyOwned recovery', () {
    test('restores, acknowledges and grants premium instead of erroring',
        () async {
      // The store holds a live purchase for the hunter product.
      final existing = purchase(
        SubscriptionTier.hunter.playProductId,
        status: PurchaseStatus.purchased,
        token: 'tok-restored',
      );
      PlayBillingService.pastPurchasesForTesting = () async => [existing];

      // Capture the premium grant the recorder requests.
      final granted = <String>[];
      String? grantedToken;
      PlayPurchaseRecorder.premiumSetterForTesting =
          ({required String productId, String? purchaseToken}) async {
        granted.add(productId);
        grantedToken = purchaseToken;
        return true;
      };

      final controller = StreamController<List<PurchaseDetails>>.broadcast();
      PlayPurchaseRecorder.purchaseStreamForTesting = controller.stream;
      PlayPurchaseRecorder.instance.startListening();

      // The exact event the reporter saw: an error-status purchase carrying
      // the itemAlreadyOwned IAPError.
      controller.add([
        purchase(
          SubscriptionTier.hunter.playProductId,
          status: PurchaseStatus.error,
          error: itemAlreadyOwnedError(),
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // 1) The store was asked to replay prior purchases.
      expect(PlayBillingService.restoreCallsForTesting, greaterThanOrEqualTo(1));
      // 2) The existing purchase was acknowledged.
      expect(PlayBillingService.completedPurchasesForTesting, isNotEmpty);
      expect(
        PlayBillingService.completedPurchasesForTesting.last.productID,
        SubscriptionTier.hunter.playProductId,
      );
      // 3) Premium was granted for the hunter product with the restored token.
      expect(granted, [SubscriptionTier.hunter.playProductId]);
      expect(grantedToken, 'tok-restored');
      // 4) The transaction was recorded.
      final purchases = await fake.collection(purchasesCollection).get();
      expect(purchases.docs.length, 1);
      expect(purchases.docs.single.data()['purchaseToken'], 'tok-restored');

      await controller.close();
      await PlayPurchaseRecorder.instance.stopListening();
    });

    test('itemAlreadyOwned results in isPremium = true', () async {
      // End-to-end: recover an already-owned subscription, then read the
      // entitlement through the SAME server-authoritative path the app uses.
      final existing = purchase(
        SubscriptionTier.hunter.playProductId,
        status: PurchaseStatus.purchased,
        token: 'tok-premium',
      );
      PlayBillingService.pastPurchasesForTesting = () async => [existing];

      // Wire the premium grant to the real EntitlementService.setPremium, with
      // its verifier stubbed to simulate the Cloud Function granting premium
      // (it writes the server-owned fields the client cannot).
      EntitlementService.premiumSetterForTesting =
          ({required String productId, String? purchaseToken}) async {
        await fake.collection('entitlements').doc('uid-1').set({
          'userId': 'uid-1',
          'isPremium': true,
          'premiumExpiry': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30)),
          ),
          'subscriptionSource': SubscriptionSource.googlePlay,
        }, SetOptions(merge: true));
        return true;
      };
      EntitlementService.firestoreForTesting = fake;
      EntitlementService.currentUserIdResolverForTesting = () => 'uid-1';

      final controller = StreamController<List<PurchaseDetails>>.broadcast();
      PlayPurchaseRecorder.purchaseStreamForTesting = controller.stream;
      PlayPurchaseRecorder.instance.startListening();

      controller.add([
        purchase(
          SubscriptionTier.hunter.playProductId,
          status: PurchaseStatus.error,
          error: itemAlreadyOwnedError(),
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final entitlement = await EntitlementService.instance.getMyEntitlement();
      expect(entitlement.isPremium, isTrue,
          reason: 'itemAlreadyOwned must end with isPremium = true');
      expect(entitlement.isPremiumActive(DateTime.now()), isTrue);
      expect(entitlement.isGooglePlay, isTrue);

      await controller.close();
      await PlayPurchaseRecorder.instance.stopListening();
    });

    test('a genuine purchase error is still logged as an error', () async {
      final controller = StreamController<List<PurchaseDetails>>.broadcast();
      PlayPurchaseRecorder.purchaseStreamForTesting = controller.stream;
      PlayPurchaseRecorder.instance.startListening();

      controller.add([
        purchase(
          SubscriptionTier.hunter.playProductId,
          status: PurchaseStatus.error,
          error: IAPError(
            source: 'google_play',
            code: PlayBillingErrors.purchaseErrorCode,
            message: 'BillingResponse.developerError',
          ),
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // A non-itemAlreadyOwned error must NOT trigger a restore / grant.
      expect(PlayBillingService.restoreCallsForTesting, 0);
      expect(PlayBillingService.completedPurchasesForTesting, isEmpty);
      expect((await fake.collection(purchasesCollection).get()).docs, isEmpty);

      await controller.close();
      await PlayPurchaseRecorder.instance.stopListening();
    });

    test('itemAlreadyOwned with no live purchase does not grant premium',
        () async {
      // The store reports "already owned" but returns no purchase to restore.
      PlayBillingService.pastPurchasesForTesting = () async => const [];
      var granted = false;
      PlayPurchaseRecorder.premiumSetterForTesting =
          ({required String productId, String? purchaseToken}) async {
        granted = true;
        return true;
      };

      final controller = StreamController<List<PurchaseDetails>>.broadcast();
      PlayPurchaseRecorder.purchaseStreamForTesting = controller.stream;
      PlayPurchaseRecorder.instance.startListening();

      controller.add([
        purchase(
          SubscriptionTier.hunter.playProductId,
          status: PurchaseStatus.error,
          error: itemAlreadyOwnedError(),
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(PlayBillingService.restoreCallsForTesting, greaterThanOrEqualTo(1));
      expect(granted, isFalse,
          reason: 'nothing to restore -> no entitlement grant');
      expect(PlayBillingService.completedPurchasesForTesting, isEmpty);

      await controller.close();
      await PlayPurchaseRecorder.instance.stopListening();
    });
  });

  group('EntitlementService.setPremium', () {
    test('routes through the server verifier and reports the outcome',
        () async {
      String? seenProduct;
      EntitlementService.premiumSetterForTesting =
          ({required String productId, String? purchaseToken}) async {
        seenProduct = productId;
        return true;
      };
      final ok = await EntitlementService.instance.setPremium(
        productId: SubscriptionTier.outfitter.playProductId,
        purchaseToken: 'tok-1',
      );
      expect(ok, isTrue);
      expect(seenProduct, SubscriptionTier.outfitter.playProductId);
    });

    test('never writes premium state locally (server-authoritative)', () async {
      // With no seam installed and no token, setPremium must resolve false
      // without touching Firestore — the client cannot write the frozen
      // entitlement fields.
      EntitlementService.firestoreForTesting = fake;
      final ok = await EntitlementService.instance.setPremium(
        productId: SubscriptionTier.hunter.playProductId,
        purchaseToken: null,
      );
      expect(ok, isFalse);
      final users = await fake.collection('users').get();
      expect(users.docs, isEmpty,
          reason: 'setPremium must never write users/{uid} client-side');
    });
  });

  group('startup + source contracts', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll(
          '\r\n',
          '\n',
        );
    final recorder =
        File('lib/features/subscription/services/play_purchase_recorder.dart')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');

    test('startup attaches the listener BEFORE restoring purchases', () {
      final listenAt = main.indexOf(
        'PlayPurchaseRecorder.instance.startListening()',
      );
      final restoreAt = main.indexOf(
        'PlayBillingService.instance.restorePurchases()',
      );
      expect(listenAt, greaterThan(-1),
          reason: 'startup must attach the purchase listener');
      expect(restoreAt, greaterThan(-1),
          reason: 'startup must restore prior purchases');
      expect(listenAt, lessThan(restoreAt),
          reason: 'listen-before-restore: a restored purchase delivered on the '
              'stream must not be dropped');
    });

    test('the recorder logs itemAlreadyOwned as an informational recovery',
        () {
      // The old shape — an unconditional purchase-error log — must be gone for
      // the itemAlreadyOwned branch, replaced by the recovery path.
      expect(recorder, contains('subscription already owned, restoring'));
      expect(recorder, contains('_recoverAlreadyOwned'));
      expect(recorder, contains('PlayBillingErrors.isItemAlreadyOwned'));
    });
  });
}
