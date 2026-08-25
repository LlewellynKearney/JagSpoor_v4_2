import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jagspoor/features/subscription/services/payfast_service.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';

void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    SubscriptionStatusService.firestoreForTesting = fake;
    SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
  });

  tearDown(SubscriptionStatusService.resetTestSeams);

  group('UserSubscription.fromMap', () {
    test('null / empty map yields the empty state', () {
      const sub = UserSubscription();
      expect(sub.status, SubscriptionStatus.none);
      expect(sub.hasSubscription, isFalse);
      expect(sub.isActive, isFalse);
      expect(sub.isInTrial, isFalse);
      expect(UserSubscription.fromMap(null).status, SubscriptionStatus.none);
      expect(UserSubscription.fromMap(const {}).status, SubscriptionStatus.none);
    });

    test('hydrates an active subscription with a renewal date', () {
      final renewal = DateTime(2026, 9, 22);
      final sub = UserSubscription.fromMap({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'outfitter',
        'subscriptionRenewalDate': Timestamp.fromDate(renewal),
        'subscriptionPromoCode': 'LAUNCH25',
      });
      expect(sub.status, SubscriptionStatus.active);
      expect(sub.isActive, isTrue);
      expect(sub.tier, SubscriptionTier.outfitter);
      expect(sub.renewalDate, renewal);
      expect(sub.promoCode, 'LAUNCH25');
    });

    test('hydrates a trial subscription with a trial end date', () {
      final trialEnd = DateTime.now().add(const Duration(days: 12));
      final sub = UserSubscription.fromMap({
        'subscriptionStatus': 'trial',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt': Timestamp.fromDate(trialEnd),
      });
      expect(sub.isInTrial, isTrue);
      expect(sub.hasSubscription, isTrue);
      expect(sub.trialDaysRemaining(DateTime.now()), greaterThanOrEqualTo(11));
    });

    test('trialDaysRemaining is 0 when not in trial or expired', () {
      expect(const UserSubscription().trialDaysRemaining(DateTime.now()), 0);
      final expired = UserSubscription(
        status: SubscriptionStatus.trial,
        trialEndsAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(expired.trialDaysRemaining(DateTime.now()), 0);
    });

    test('tolerates ISO string + epoch date shapes', () {
      final sub = UserSubscription.fromMap({
        'subscriptionStatus': 'active',
        'subscriptionRenewalDate': '2026-09-22T00:00:00.000',
      });
      expect(sub.renewalDate, DateTime(2026, 9, 22));
      final epoch = UserSubscription.fromMap({
        'subscriptionRenewalDate': 1790035200000,
      });
      expect(epoch.renewalDate, isNotNull);
    });
  });

  group('SubscriptionStatusService', () {
    test('markTrialStarted writes the trial window + tier to users/{uid}', () async {
      final now = DateTime(2026, 8, 23, 10, 0);
      await SubscriptionStatusService.instance.markTrialStarted(
        tier: SubscriptionTier.outfitter,
        promoCode: 'LAUNCH25',
        now: now,
      );
      final snap = await fake.collection('users').doc('uid-1').get();
      final data = snap.data()!;
      expect(data['subscriptionStatus'], 'trial');
      expect(data['subscriptionTier'], 'outfitter');
      expect(data['subscriptionPromoCode'], 'LAUNCH25');
      final trialEnd = (data['subscriptionTrialEndsAt'] as Timestamp).toDate();
      expect(trialEnd.difference(now).inDays, 30);
      expect(data.containsKey('subscriptionUpdatedAt'), isTrue);
    });

    test('markTrialStarted rejects an unauthenticated caller', () {
      SubscriptionStatusService.currentUserIdResolverForTesting = () => null;
      expect(
        () => SubscriptionStatusService.instance
            .markTrialStarted(tier: SubscriptionTier.hunter),
        throwsStateError,
      );
    });

    test('watchMySubscription emits the stored state', () async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
      });
      final sub =
          await SubscriptionStatusService.instance.watchMySubscription().first;
      expect(sub.status, SubscriptionStatus.active);
      expect(sub.tier, SubscriptionTier.hunter);
    });

    test('watchMySubscription emits the empty state when unauthenticated', () async {
      SubscriptionStatusService.currentUserIdResolverForTesting = () => null;
      final sub =
          await SubscriptionStatusService.instance.watchMySubscription().first;
      expect(sub.status, SubscriptionStatus.none);
    });

    test('getMySubscription reads the stored state', () async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'cancelled',
      });
      final sub = await SubscriptionStatusService.instance.getMySubscription();
      expect(sub.status, SubscriptionStatus.cancelled);
    });
  });

  group('SubscriptionStatusService.cancelSubscription', () {
    test('rejects an unauthenticated caller', () {
      SubscriptionStatusService.currentUserIdResolverForTesting = () => null;
      expect(
        () => SubscriptionStatusService.instance.cancelSubscription(),
        throwsStateError,
      );
    });

    test('invokes the endpoint with the current uid and returns true on 2xx',
        () async {
      String? seenUid;
      SubscriptionStatusService.cancellationInvokerForTesting =
          (userId, idToken) async {
        seenUid = userId;
        return http.Response('{"result": "success"}', 200);
      };
      final ok = await SubscriptionStatusService.instance.cancelSubscription();
      expect(ok, isTrue);
      expect(seenUid, 'uid-1');
    });

    test('throws CancellationException when the endpoint rejects the request',
        () async {
      SubscriptionStatusService.cancellationInvokerForTesting =
          (userId, idToken) async => http.Response('error', 502);
      expect(
        () => SubscriptionStatusService.instance.cancelSubscription(),
        throwsA(isA<CancellationException>()),
      );
      // The subscription is NOT silently marked cancelled without the token
      // being terminated.
      final sub = await SubscriptionStatusService.instance.getMySubscription();
      expect(sub.status, isNot(SubscriptionStatus.cancelled));
    });

    test('falls back to an owner write when the endpoint is unreachable',
        () async {
      SubscriptionStatusService.cancellationInvokerForTesting =
          (userId, idToken) async => null;
      final ok = await SubscriptionStatusService.instance.cancelSubscription();
      expect(ok, isTrue);
      final snap = await fake.collection('users').doc('uid-1').get();
      expect(snap.data()!['subscriptionStatus'], 'cancelled');
      expect(snap.data()!.containsKey('subscriptionCancelledAt'), isTrue);
    });

    test('cancelSubscriptionUrl targets the us-central1 function', () {
      expect(
        SubscriptionStatusService.cancelSubscriptionUrl,
        'https://us-central1-jagspoor.cloudfunctions.net/cancelSubscription',
      );
    });
  });
}
