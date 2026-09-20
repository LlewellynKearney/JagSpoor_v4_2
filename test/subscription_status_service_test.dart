import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';
import 'package:jagspoor/services/entitlement_service.dart';

void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    SubscriptionStatusService.firestoreForTesting = fake;
    SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
    EntitlementService.firestoreForTesting = fake;
    EntitlementService.currentUserIdResolverForTesting = () => 'uid-1';
  });

  tearDown(() {
    SubscriptionStatusService.resetTestSeams();
    EntitlementService.resetTestSeams();
  });

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
      expect(data['subscriptionStatus'], subscriptionStatusTrial);
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

  group('server-authoritative entitlement (EntitlementService)', () {
    test('reads isPremium + trial fields from users/{uid}', () async {
      await fake.collection('users').doc('uid-1').set({
        'isPremium': true,
        'premiumExpiry': Timestamp.fromDate(DateTime(2026, 12, 31)),
        'subscriptionSource': 'google_play',
        'trialStart': Timestamp.fromDate(DateTime(2026, 9, 1)),
        'trialEnd': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });
      final ent = await EntitlementService.instance.getMyEntitlement();
      expect(ent.isPremium, isTrue);
      expect(ent.isPremiumActive(DateTime(2026, 10, 15)), isTrue);
      expect(ent.subscriptionSource, 'google_play');
      expect(ent.isTrialActive(DateTime(2026, 9, 15)), isTrue);
      expect(ent.canAccessPremium(DateTime(2026, 9, 15)), isTrue);
    });

    test('an expired premium + expired trial blocks access', () async {
      await fake.collection('users').doc('uid-1').set({
        'isPremium': true,
        'premiumExpiry': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'trialEnd': Timestamp.fromDate(DateTime(2026, 6, 1)),
      });
      final ent = await EntitlementService.instance.getMyEntitlement();
      expect(ent.isPremiumActive(DateTime(2026, 9, 1)), isFalse);
      expect(ent.isTrialActive(DateTime(2026, 9, 1)), isFalse);
      expect(ent.canAccessPremium(DateTime(2026, 9, 1)), isFalse);
    });

    test('unauthenticated caller yields the empty entitlement', () async {
      EntitlementService.currentUserIdResolverForTesting = () => null;
      final ent = await EntitlementService.instance.getMyEntitlement();
      expect(ent.isPremium, isFalse);
      expect(ent.canAccessPremium(DateTime.now()), isFalse);
    });
  });

  group('subscription pricing contract', () {
    test('tiers map to the expected Play Billing product ids', () {
      expect(SubscriptionTier.hunter.playProductId, 'jagspoor_hunter_monthly');
      expect(SubscriptionTier.outfitter.playProductId, 'jagspoor_outfitter_monthly');
      expect(
        SubscriptionTier.fromPlayProductId('jagspoor_outfitter_monthly'),
        SubscriptionTier.outfitter,
      );
      expect(
        SubscriptionTier.fromPlayProductId('jagspoor_hunter_monthly'),
        SubscriptionTier.hunter,
      );
    });

    test('promo engine applies the catalog adjustments', () {
      expect(PromoCodeEngine.normalize('  jagspoor10 '), 'JAGSPOOR10');
      expect(PromoCodeEngine.isValid('jagspoor10'), isTrue);
      final adj = PromoCodeEngine.validate('LAUNCH25');
      expect(adj, isNotNull);
      expect(adj!.code, 'LAUNCH25');
      // 19.99 - 25% = 14.9925 (rounds to 14.99 for display).
      expect(adj.apply(19.99), closeTo(14.99, 0.01));
    });
  });

  group('TrialAssignmentPolicy', () {
    test('grants a 30 day trial to standard accounts', () {
      expect(trialDuration, const Duration(days: 30));
      expect(
        TrialAssignmentPolicy.isAdmin('uid-99', 'hunter@example.com'),
        isFalse,
      );
    });

    test('excludes the admin email from trial assignment', () {
      expect(
        TrialAssignmentPolicy.isAdmin('uid-admin', TrialAssignmentPolicy.adminEmail),
        isTrue,
      );
    });

    test('excludes a configured admin uid from trial assignment', () {
      TrialAssignmentPolicy.adminUid = 'uid-admin';
      addTearDown(() => TrialAssignmentPolicy.adminUid = null);
      expect(
        TrialAssignmentPolicy.isAdmin('uid-admin', 'admin@example.com'),
        isTrue,
      );
      expect(
        TrialAssignmentPolicy.isAdmin('uid-other', 'admin@example.com'),
        isFalse,
      );
    });
  });

  group('SubscriptionStatus.fromString', () {
    test('parses the backend legacy trialing status', () {
      expect(SubscriptionStatus.fromString('trialing'), SubscriptionStatus.trial);
      expect(SubscriptionStatus.fromString('trial'), SubscriptionStatus.trial);
      expect(SubscriptionStatus.fromString('active'), SubscriptionStatus.active);
      expect(SubscriptionStatus.fromString('cancelled'), SubscriptionStatus.cancelled);
      expect(SubscriptionStatus.fromString('none'), SubscriptionStatus.none);
      expect(SubscriptionStatus.fromString('unknown-value'), SubscriptionStatus.none);
    });
  });

  group('markTrialStarted canonical status', () {
    test('writes the canonical trialing status + 30 day window', () async {
      final now = DateTime(2026, 8, 23, 10, 0);
      await SubscriptionStatusService.instance.markTrialStarted(
        tier: SubscriptionTier.hunter,
        now: now,
      );
      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(data['subscriptionStatus'], subscriptionStatusTrial);
      expect(data['subscriptionStatus'], 'trialing');
      final trialEnd = (data['subscriptionTrialEndsAt'] as Timestamp).toDate();
      expect(trialEnd.difference(now).inDays, 30);
    });
  });

  group('server-authoritative entitlement (EntitlementService)', () {
    test('reads isPremium + trial fields from users/{uid}', () async {
      await fake.collection('users').doc('uid-1').set({
        'isPremium': true,
        'premiumExpiry': Timestamp.fromDate(DateTime(2026, 12, 31)),
        'subscriptionSource': 'google_play',
        'trialStart': Timestamp.fromDate(DateTime(2026, 9, 1)),
        'trialEnd': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });
      final ent = await EntitlementService.instance.getMyEntitlement();
      expect(ent.isPremium, isTrue);
      expect(ent.isPremiumActive(DateTime(2026, 10, 15)), isTrue);
      expect(ent.subscriptionSource, 'google_play');
      expect(ent.isTrialActive(DateTime(2026, 9, 15)), isTrue);
      expect(ent.canAccessPremium(DateTime(2026, 9, 15)), isTrue);
    });

    test('an expired premium + expired trial blocks access', () async {
      await fake.collection('users').doc('uid-1').set({
        'isPremium': true,
        'premiumExpiry': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'trialEnd': Timestamp.fromDate(DateTime(2026, 6, 1)),
      });
      final ent = await EntitlementService.instance.getMyEntitlement();
      expect(ent.isPremiumActive(DateTime(2026, 9, 1)), isFalse);
      expect(ent.isTrialActive(DateTime(2026, 9, 1)), isFalse);
      expect(ent.canAccessPremium(DateTime(2026, 9, 1)), isFalse);
    });

    test('unauthenticated caller yields the empty entitlement', () async {
      EntitlementService.currentUserIdResolverForTesting = () => null;
      final ent = await EntitlementService.instance.getMyEntitlement();
      expect(ent.isPremium, isFalse);
      expect(ent.canAccessPremium(DateTime.now()), isFalse);
    });
  });
}
