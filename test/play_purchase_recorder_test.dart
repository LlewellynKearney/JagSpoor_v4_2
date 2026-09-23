import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_purchase_recorder.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

/// Task 2 (v9.2): a Google Play purchase must land in Firestore —
/// `users/{uid}` (`subscriptionTier` / `subscriptionStatus: 'active'` /
/// `isPro: true`) AND one `purchases/{uid}_{productId}` document carrying
/// `uid`, `productId`, `purchaseToken` and `status`. Before this fix the
/// `purchases` collection was always empty because no write existed.
void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    PlayPurchaseRecorder.firestoreForTesting = fake;
    PlayPurchaseRecorder.currentUserIdResolverForTesting = () => 'uid-1';
    PlayPurchaseRecorder.purchaseStreamForTesting =
        const Stream<List<PurchaseDetails>>.empty();
  });

  tearDown(() {
    PlayPurchaseRecorder.resetTestSeams();
    PlayBillingService.resetTestSeams();
  });

  PurchaseDetails purchased(String productId, String token) => PurchaseDetails(
        productID: productId,
        purchaseID: 'pid-1',
        transactionDate: '${DateTime.now().millisecondsSinceEpoch}',
        status: PurchaseStatus.purchased,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'local',
          serverVerificationData: token,
          source: 'google_play',
        ),
      );

  group('constants', () {
    test('the purchases collection + active status are stable', () {
      expect(purchasesCollection, 'purchases');
      expect(purchaseStatusActive, 'active');
      expect(subscriptionStatusActive, 'active');
    });
  });

  group('recordPurchase', () {
    test('writes the hunter subscription state + purchase record', () async {
      final ok = await PlayPurchaseRecorder.instance.recordPurchase(
        productId: SubscriptionTier.hunter.playProductId,
        purchaseToken: 'tok-abc',
      );
      expect(ok, isTrue);

      final user = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(user['subscriptionTier'], 'hunter');
      expect(user['subscriptionStatus'], 'active');
      expect(user['isPro'], isTrue);
      expect(user['subscriptionProvider'], 'google_play_billing');

      final purchases = await fake.collection(purchasesCollection).get();
      expect(purchases.docs.length, 1);
      final data = purchases.docs.single.data();
      expect(data['uid'], 'uid-1');
      expect(data['productId'], SubscriptionTier.hunter.playProductId);
      expect(data['purchaseToken'], 'tok-abc');
      expect(data['status'], 'active');
      expect(data['tier'], 'hunter');
    });

    test('records the outfitter tier for the outfitter product', () async {
      await PlayPurchaseRecorder.instance.recordPurchase(
        productId: SubscriptionTier.outfitter.playProductId,
        purchaseToken: 'tok-out',
      );
      final user = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(user['subscriptionTier'], 'outfitter');
      final purchase = (await fake
              .collection(purchasesCollection)
              .doc('uid-1_${SubscriptionTier.outfitter.playProductId}')
              .get())
          .data()!;
      expect(purchase['tier'], 'outfitter');
    });

    test('is idempotent — a repeated delivery does not duplicate the record',
        () async {
      await PlayPurchaseRecorder.instance.recordPurchase(
        productId: SubscriptionTier.hunter.playProductId,
        purchaseToken: 'tok-1',
      );
      await PlayPurchaseRecorder.instance.recordPurchase(
        productId: SubscriptionTier.hunter.playProductId,
        purchaseToken: 'tok-2',
      );
      final purchases = await fake.collection(purchasesCollection).get();
      expect(purchases.docs.length, 1);
      // The latest token wins (a re-delivery refreshes the stored token).
      expect(purchases.docs.single.data()['purchaseToken'], 'tok-2');
    });

    test('no signed-in user -> nothing written, resolves false', () async {
      PlayPurchaseRecorder.currentUserIdResolverForTesting = () => null;
      final ok = await PlayPurchaseRecorder.instance.recordPurchase(
        productId: SubscriptionTier.hunter.playProductId,
        purchaseToken: 'tok',
      );
      expect(ok, isFalse);
      expect((await fake.collection(purchasesCollection).get()).docs, isEmpty);
    });

    test('a Firestore failure is swallowed (never throws)', () async {
      // Detach the injected store and let the real (uninitialised) Firebase
      // path fail — the recorder must report false rather than throwing.
      PlayPurchaseRecorder.firestoreForTesting = null;
      final ok = await PlayPurchaseRecorder.instance.recordPurchase(
        productId: SubscriptionTier.hunter.playProductId,
        purchaseToken: 'tok',
      );
      expect(ok, isFalse);
    });
  });

  group('purchase stream listener', () {
    test('records a purchase delivered on the stream', () async {
      final controller = StreamController<List<PurchaseDetails>>.broadcast();
      PlayPurchaseRecorder.purchaseStreamForTesting = controller.stream;
      PlayPurchaseRecorder.instance.startListening();
      expect(PlayPurchaseRecorder.instance.isListening, isTrue);

      controller.add([
        purchased(SubscriptionTier.hunter.playProductId, 'stream-tok'),
      ]);
      // Let the async listener drain.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final purchases = await fake.collection(purchasesCollection).get();
      expect(purchases.docs.length, 1);
      expect(purchases.docs.single.data()['purchaseToken'], 'stream-tok');

      await controller.close();
      await PlayPurchaseRecorder.instance.stopListening();
    });

    test('ignores a cancelled / pending purchase', () async {
      final controller = StreamController<List<PurchaseDetails>>.broadcast();
      PlayPurchaseRecorder.purchaseStreamForTesting = controller.stream;
      PlayPurchaseRecorder.instance.startListening();

      final cancelled = purchased(SubscriptionTier.hunter.playProductId, 'x');
      cancelled.status = PurchaseStatus.canceled;
      controller.add([cancelled]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((await fake.collection(purchasesCollection).get()).docs, isEmpty);
      await controller.close();
      await PlayPurchaseRecorder.instance.stopListening();
    });

    test('startListening attaches at most one listener', () {
      PlayPurchaseRecorder.instance.startListening();
      PlayPurchaseRecorder.instance.startListening();
      expect(PlayPurchaseRecorder.instance.isListening, isTrue);
    });
  });
}
