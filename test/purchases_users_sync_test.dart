import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/subscription/services/play_purchase_recorder.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/services/entitlement_service.dart';

/// Regression suite for the reported bug: "users collection not synced from
/// purchases collection".
///
/// The `purchases` collection is the durable record of what Google Play
/// actually charged for, so on app start / auth-state change the app must
/// reconcile it into the entitlement:
///
///   1. read `purchases` where `uid == currentUid` and `status == 'active'`;
///   2. when an active row exists, drive the SERVER-authoritative entitlement
///      write (`validateGooglePlayPurchase`) so `users/{uid}` reflects
///      `subscriptionStatus: 'active'` + `hasActivePurchase: true`;
///   3. treat `purchases` as a source of truth on the paywall so a subscriber
///      is never asked to pay twice while the mirror catches up.
///
/// The entitlement fields themselves are frozen in `firestore.rules` (server
/// owned), so these tests assert the client drives the server path — never
/// that it writes `subscriptionStatus` itself.
void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    PlayPurchaseRecorder.firestoreForTesting = fake;
    PlayPurchaseRecorder.currentUserIdResolverForTesting = () => 'uid-1';
    PlayPurchaseRecorder.purchaseStreamForTesting =
        const Stream<List<PurchaseDetails>>.empty();
    EntitlementService.firestoreForTesting = fake;
    EntitlementService.currentUserIdResolverForTesting = () => 'uid-1';
  });

  tearDown(() {
    PlayPurchaseRecorder.resetTestSeams();
    EntitlementService.resetTestSeams();
  });

  /// Seeds a `purchases` row. `productId` defaults to a real product so the
  /// row is verifiable; pass `''` to seed the junk shape.
  Future<void> seedPurchase({
    required String id,
    String uid = 'uid-1',
    String productId = 'jagspoor_hunter_monthly',
    String token = 'tok-1',
    String status = 'active',
  }) async {
    await fake.collection('purchases').doc(id).set({
      'uid': uid,
      'productId': productId,
      'purchaseToken': token,
      'status': status,
      'tier': SubscriptionTier.fromPlayProductId(productId).key,
    });
  }

  group('reconcileEntitlementFromPurchases', () {
    test('no signed-in user -> none (no Firestore read, no throw)', () async {
      PlayPurchaseRecorder.currentUserIdResolverForTesting = () => null;
      final result =
          await PlayPurchaseRecorder.instance.reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isFalse);
      expect(result.premiumGranted, isFalse);
    });

    test('no active purchase row -> none (does not grant)', () async {
      // Only a cancelled row exists — it must never unlock premium.
      await seedPurchase(id: 'uid-1_x', status: 'cancelled');
      final result =
          await PlayPurchaseRecorder.instance.reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isFalse);
    });

    test('an active purchase for ANOTHER uid is ignored', () async {
      await seedPurchase(id: 'uid-2_y', uid: 'uid-2');
      final result =
          await PlayPurchaseRecorder.instance.reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isFalse);
    });

    test('an active row drives the server-authoritative entitlement grant',
        () async {
      await seedPurchase(id: 'uid-1_${SubscriptionTier.hunter.playProductId}');

      // Capture the server call instead of hitting the network.
      String? calledProduct;
      String? calledToken;
      EntitlementService.premiumSetterForTesting = ({
        required String productId,
        String? purchaseToken,
      }) async {
        calledProduct = productId;
        calledToken = purchaseToken;
        return true;
      };

      final result = await PlayPurchaseRecorder.instance
          .reconcileEntitlementFromPurchases();

      expect(result.hasActivePurchase, isTrue);
      expect(result.productId, SubscriptionTier.hunter.playProductId);
      expect(result.premiumGranted, isTrue);
      // The Play token from the purchases row is what gets re-validated.
      expect(calledProduct, SubscriptionTier.hunter.playProductId);
      expect(calledToken, 'tok-1');
    });

    test('the client never writes the frozen entitlement fields itself',
        () async {
      await seedPurchase(id: 'uid-1_${SubscriptionTier.hunter.playProductId}');
      EntitlementService.premiumSetterForTesting = ({
        required String productId,
        String? purchaseToken,
      }) async =>
          true;

      await PlayPurchaseRecorder.instance.reconcileEntitlementFromPurchases();

      // The sync must not touch users/{uid} directly — that write is
      // server-owned (PERMISSION_DENIED for a client) and would also be a
      // forgery vector.
      final user = (await fake.collection('users').doc('uid-1').get()).data();
      expect(user, isNull,
          reason: 'the reconcile path must not write users/{uid} locally');
    });

    test('a server rejection leaves premiumGranted false (retry next launch)',
        () async {
      await seedPurchase(id: 'uid-1_${SubscriptionTier.hunter.playProductId}');
      EntitlementService.premiumSetterForTesting = ({
        required String productId,
        String? purchaseToken,
      }) async =>
          false;

      final result = await PlayPurchaseRecorder.instance
          .reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isTrue);
      expect(result.premiumGranted, isFalse);
    });

    test('JUNK rows (blank productId) never grant entitlement', () async {
      // The reported junk document shape: an active row with no productId.
      await seedPurchase(
        id: 'V8amh1XcS5YeokFLZ5v9hoRp6Oo2_',
        productId: '',
      );

      var serverCalled = false;
      EntitlementService.premiumSetterForTesting = ({
        required String productId,
        String? purchaseToken,
      }) async {
        serverCalled = true;
        return true;
      };

      final result = await PlayPurchaseRecorder.instance
          .reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isFalse,
          reason: 'an unverifiable row must not unlock premium');
      expect(serverCalled, isFalse,
          reason: 'a blank-productId row must never be sent for verification');
    });

    test('JUNK rows (blank token) never grant entitlement', () async {
      await seedPurchase(id: 'junk', token: '');
      var serverCalled = false;
      EntitlementService.premiumSetterForTesting = ({
        required String productId,
        String? purchaseToken,
      }) async {
        serverCalled = true;
        return true;
      };
      final result = await PlayPurchaseRecorder.instance
          .reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isFalse);
      expect(serverCalled, isFalse);
    });

    test('a usable row is chosen when junk + valid rows coexist', () async {
      await seedPurchase(id: 'junk', productId: '');
      await seedPurchase(
        id: 'uid-1_${SubscriptionTier.outfitter.playProductId}',
        productId: SubscriptionTier.outfitter.playProductId,
      );
      EntitlementService.premiumSetterForTesting = ({
        required String productId,
        String? purchaseToken,
      }) async =>
          true;

      final result = await PlayPurchaseRecorder.instance
          .reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isTrue);
      expect(result.productId, SubscriptionTier.outfitter.playProductId);
    });

    test('the newest active row wins (client-side ordering, no index)',
        () async {
      await seedPurchase(
        id: 'uid-1_hunter',
        productId: SubscriptionTier.hunter.playProductId,
        token: 'old',
      );
      await fake.collection('purchases').doc('uid-1_hunter').set(
        {'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1))},
        SetOptions(merge: true),
      );
      await seedPurchase(
        id: 'uid-1_outfitter',
        productId: SubscriptionTier.outfitter.playProductId,
        token: 'new',
      );
      await fake.collection('purchases').doc('uid-1_outfitter').set(
        {'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 1))},
        SetOptions(merge: true),
      );

      String? token;
      EntitlementService.premiumSetterForTesting = ({
        required String productId,
        String? purchaseToken,
      }) async {
        token = purchaseToken;
        return true;
      };

      final result = await PlayPurchaseRecorder.instance
          .reconcileEntitlementFromPurchases();
      expect(result.productId, SubscriptionTier.outfitter.playProductId);
      expect(token, 'new');
    });

    test('a read failure resolves none rather than throwing', () async {
      PlayPurchaseRecorder.firestoreForTesting = null; // uninitialised Firebase
      final result =
          await PlayPurchaseRecorder.instance.reconcileEntitlementFromPurchases();
      expect(result.hasActivePurchase, isFalse);
    });
  });

  group('recordPurchase junk guard', () {
    test('refuses to write a row with a blank productId', () async {
      final ok = await PlayPurchaseRecorder.instance.recordPurchase(
        productId: '',
        purchaseToken: 'tok',
      );
      expect(ok, isFalse);
      expect((await fake.collection('purchases').get()).docs, isEmpty);
    });

    test('still writes a valid row', () async {
      final ok = await PlayPurchaseRecorder.instance.recordPurchase(
        productId: SubscriptionTier.hunter.playProductId,
        purchaseToken: 'tok',
      );
      expect(ok, isTrue);
      expect((await fake.collection('purchases').get()).docs.length, 1);
    });
  });

  group('syncEntitlementFromPurchases', () {
    test('is fire-and-forget and never throws without Firebase', () async {
      PlayPurchaseRecorder.firestoreForTesting = null;
      await PlayPurchaseRecorder.instance.syncEntitlementFromPurchases();
      // Reaching here without an exception is the contract.
    });

    test('attaches the purchase listener', () async {
      // A fresh process has no listener; the sync must attach it.
      PlayPurchaseRecorder.resetTestSeams();
      PlayPurchaseRecorder.firestoreForTesting = fake;
      PlayPurchaseRecorder.currentUserIdResolverForTesting = () => 'uid-1';
      PlayPurchaseRecorder.purchaseStreamForTesting =
          const Stream<List<PurchaseDetails>>.empty();

      expect(PlayPurchaseRecorder.instance.isListening, isFalse);
      await PlayPurchaseRecorder.instance.syncEntitlementFromPurchases();
      expect(PlayPurchaseRecorder.instance.isListening, isTrue);
    });
  });

  group('UserEntitlement.hasActivePurchase', () {
    test('fromMap reads the server-owned mirror flag', () {
      final ent = UserEntitlement.fromMap(const {
        'hasActivePurchase': true,
        'subscriptionStatus': 'active',
      });
      expect(ent.hasActivePurchase, isTrue);
    });

    test('grants premium access even with no local premiumExpiry', () {
      final ent = UserEntitlement.fromMap(const {'hasActivePurchase': true});
      expect(ent.isPremiumActive(DateTime(2030)), isTrue);
      expect(ent.canAccessPremium(DateTime(2030)), isTrue);
    });

    test('is false by default (no false positives)', () {
      expect(const UserEntitlement().hasActivePurchase, isFalse);
      expect(const UserEntitlement().isPremiumActive(DateTime(2030)), isFalse);
    });

    test('the entitlements/{uid} mirror also carries the flag', () {
      final ent =
          UserEntitlement.fromEntitlementMirror(const {'hasActivePurchase': true});
      expect(ent.hasActivePurchase, isTrue);
    });

    test('mergePremiumMirror takes the flag from either document', () {
      final users = UserEntitlement.fromMap(const {'hasActivePurchase': true});
      final mirror = UserEntitlement.fromEntitlementMirror(const {});
      expect(users.mergePremiumMirror(mirror).hasActivePurchase, isTrue);

      final usersNoFlag = UserEntitlement.fromMap(const {});
      final mirrorFlagged =
          UserEntitlement.fromEntitlementMirror(const {'hasActivePurchase': true});
      expect(usersNoFlag.mergePremiumMirror(mirrorFlagged).hasActivePurchase,
          isTrue);
    });
  });
}
