import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';
import 'package:jagspoor/services/entitlement_service.dart';

/// Regression coverage for TODO #5: a brand-new account with a VALID trial in
/// Firestore was shown the "Premium Access Required — Your free trial has
/// ended" paywall on first install.
///
/// Two signup paths wrote DIFFERENT schemas:
///  - the backend `initializeNewUserTrial` Auth `onCreate` trigger writes
///    `trialEndsAt` / `trialStart` / `subscriptionSource: 'trial'` /
///    `requiresPayment` (the "Jannie" doc); and
///  - the client `SubscriptionStatusService.markTrialStarted` wrote
///    `subscriptionTrialEndsAt` / `subscriptionProvider` (the "Ocker" doc).
///
/// `UserEntitlement.fromMap` only read `trialEnd` / `trialEndsAt` and never
/// read `subscriptionStatus`, so an Ocker-schema document resolved to no
/// trial window → `canAccessPremium` false → instant paywall. These tests lock
/// BOTH schemas to granted access.
void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    EntitlementService.firestoreForTesting = fake;
    EntitlementService.currentUserIdResolverForTesting = () => 'uid-1';
    SubscriptionStatusService.firestoreForTesting = fake;
    SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
  });

  tearDown(() {
    EntitlementService.resetTestSeams();
    SubscriptionStatusService.resetTestSeams();
  });

  /// The exact document shape of the reported BROKEN account (Ocker Fourie,
  /// uid qzV9jsLYvdSyl1wmeplQD807sdG2) — the client `markTrialStarted` schema
  /// (`subscriptionTrialEndsAt`, no `trialEndsAt`, no `requiresPayment`).
  Map<String, dynamic> ockerDoc() => {
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt': Timestamp.fromDate(DateTime(2026, 10, 21)),
        'subscriptionProvider': 'google_play_billing',
        'deviceFingerprint':
            '7f67c778478f6f5be19305998c2e598facce7733d09f4026a7e210ec3a9dd2d3',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 21)),
      };

  /// The exact document shape of a WORKING account (Jannie Bosch, uid
  /// ZTqCsp0AnsPScSj0juHeX3BSqeW2) — the backend trigger schema.
  Map<String, dynamic> jannieDoc() => {
        'trialEndsAt': Timestamp.fromDate(DateTime(2026, 10, 21)),
        'trialStartedAt': Timestamp.fromDate(DateTime(2026, 9, 21)),
        'trialEnd': Timestamp.fromDate(DateTime(2026, 10, 21)),
        'trialStart': Timestamp.fromDate(DateTime(2026, 9, 21)),
        'subscriptionSource': 'trial',
        'requiresPayment': false,
      };

  group('both historical signup schemas grant access (TODO #5)', () {
    test("Ocker's doc (client schema) passes the premium gate", () {
      final ent = UserEntitlement.fromMap(ockerDoc());
      expect(ent.subscriptionStatus, 'trialing');
      expect(ent.trialEnd, DateTime(2026, 10, 21));
      final now = DateTime(2026, 9, 21, 18, 35); // first-install timestamp
      expect(ent.isTrialActive(now), isTrue);
      expect(ent.canAccessPremium(now), isTrue);
      expect(ent.trialDaysRemaining(now), greaterThan(0));
    });

    test("Jannie's doc (backend schema) passes the premium gate", () {
      final ent = UserEntitlement.fromMap(jannieDoc());
      expect(ent.trialEnd, DateTime(2026, 10, 21));
      expect(ent.trialStart, DateTime(2026, 9, 21));
      expect(ent.requiresPayment, isFalse);
      expect(ent.isTrialActive(DateTime(2026, 9, 21)), isTrue);
      expect(ent.canAccessPremium(DateTime(2026, 9, 21)), isTrue);
    });

    test('EntitlementService grants access for both docs', () async {
      final now = DateTime(2026, 9, 21, 18, 35);
      await fake.collection('users').doc('uid-1').set(ockerDoc());
      expect(
        (await EntitlementService.instance.getMyEntitlement())
            .canAccessPremium(now),
        isTrue,
      );
      await fake.collection('users').doc('uid-1').set(jannieDoc());
      expect(
        (await EntitlementService.instance.getMyEntitlement())
            .canAccessPremium(now),
        isTrue,
      );
    });
  });

  group('status-string tolerance', () {
    test("accepts 'trial', 'trialing', 'trialling' and 'trial_active'", () {
      for (final status in [
        'trial',
        'trialing',
        'trialling',
        'trial_active',
        'TRIALING',
      ]) {
        final ent = UserEntitlement.fromMap({'subscriptionStatus': status});
        expect(
          ent.isTrialActive(DateTime(2026, 9, 21)),
          isTrue,
          reason: 'status "$status" should grant trial access',
        );
      }
    });

    test("accepts 'active' as a premium entitlement", () {
      final ent = UserEntitlement.fromMap({'subscriptionStatus': 'active'});
      expect(ent.isPremiumActive(DateTime(2026, 9, 21)), isTrue);
      expect(ent.canAccessPremium(DateTime(2026, 9, 21)), isTrue);
    });

    test('an expired trial blocks access even with a stale trialing status', () {
      final ent = UserEntitlement.fromMap({
        'subscriptionStatus': 'trialing',
        'subscriptionTrialEndsAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });
      expect(ent.isTrialActive(DateTime(2026, 9, 21)), isFalse);
      expect(ent.canAccessPremium(DateTime(2026, 9, 21)), isFalse);
    });

    test('an unknown status with no expiry fails closed', () {
      final ent = UserEntitlement.fromMap({'subscriptionStatus': 'cancelled'});
      expect(ent.canAccessPremium(DateTime(2026, 9, 21)), isFalse);
    });

    test('an expired premium with an active status mirror blocks access', () {
      final ent = UserEntitlement.fromMap({
        'subscriptionStatus': 'active',
        'premiumExpiry': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });
      expect(ent.isPremiumActive(DateTime(2026, 9, 21)), isFalse);
      expect(ent.canAccessPremium(DateTime(2026, 9, 21)), isFalse);
    });
  });

  group('requiresPayment flag (backend schema)', () {
    test('blocks trial access even with a valid future expiry', () {
      final ent = UserEntitlement.fromMap({
        ...jannieDoc(),
        'requiresPayment': true,
      });
      expect(ent.requiresPayment, isTrue);
      expect(ent.isTrialActive(DateTime(2026, 9, 21)), isFalse);
    });

    test('blocks the status-only and createdAt fallbacks', () {
      final statusOnly = UserEntitlement.fromMap({
        'subscriptionStatus': 'trialing',
        'requiresPayment': true,
      });
      expect(statusOnly.isTrialActive(DateTime(2026, 9, 21)), isFalse);

      final created = UserEntitlement.fromMap({
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 21)),
        'requiresPayment': true,
      });
      expect(created.isTrialActive(DateTime(2026, 9, 21)), isFalse);
    });
  });

  group('createdAt 30-day fallback', () {
    test('grants access for a doc with only createdAt inside the window', () {
      final ent = UserEntitlement.fromMap({
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 21)),
      });
      expect(ent.isTrialActive(DateTime(2026, 9, 21)), isTrue);
      expect(ent.isWithinCreationTrialWindow(DateTime(2026, 9, 21)), isTrue);
    });

    test('blocks access once the account is older than 30 days', () {
      final ent = UserEntitlement.fromMap({
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 21)),
      });
      expect(ent.isTrialActive(DateTime(2026, 11, 15)), isFalse);
    });

    test('a future createdAt is never treated as an active trial', () {
      final ent = UserEntitlement.fromMap({
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });
      expect(ent.isTrialActive(DateTime(2026, 9, 21)), isFalse);
    });

    test('no createdAt + no dates + no status fails closed', () {
      expect(
        UserEntitlement.fromMap(const {})
            .canAccessPremium(DateTime(2026, 9, 21)),
        isFalse,
      );
    });
  });

  group('trial-end field-name aliases', () {
    test('resolves every documented trial-end spelling', () {
      final end = DateTime(2026, 10, 21);
      for (final key in trialEndFieldAliases) {
        final ent = UserEntitlement.fromMap({
          'subscriptionStatus': 'trialing',
          key: Timestamp.fromDate(end),
        });
        expect(ent.trialEnd, end, reason: 'field "$key" should resolve');
        expect(ent.isTrialActive(DateTime(2026, 9, 21)), isTrue);
      }
    });
  });

  group('markTrialStarted writes BOTH schemas (unified creation path)', () {
    test('writes trialEndsAt + subscriptionTrialEndsAt + status', () async {
      final now = DateTime(2026, 9, 21, 10, 0);
      await SubscriptionStatusService.instance.markTrialStarted(
        tier: SubscriptionTier.hunter,
        now: now,
      );
      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      final end = now.add(trialDuration);

      // Backend-trigger schema.
      expect((data['trialEndsAt'] as Timestamp).toDate(), end);
      expect((data['trialEnd'] as Timestamp).toDate(), end);
      expect((data['trialStartedAt'] as Timestamp).toDate(), now);
      expect((data['trialStart'] as Timestamp).toDate(), now);
      // Client schema.
      expect((data['subscriptionTrialEndsAt'] as Timestamp).toDate(), end);
      expect((data['subscriptionTrialStart'] as Timestamp).toDate(), now);
      // Shared.
      expect(data['subscriptionStatus'], 'trialing');
      expect(data['subscriptionTier'], 'hunter');
      expect(data['subscriptionProvider'], 'google_play_billing');

      // The written doc passes the entitlement gate.
      expect(UserEntitlement.fromMap(data).canAccessPremium(now), isTrue);
    });

    test('never writes the server-owned (rules-frozen) fields', () async {
      await SubscriptionStatusService.instance.markTrialStarted(
        tier: SubscriptionTier.hunter,
      );
      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      // These are change-detected by firestore.rules and owned by the backend
      // trigger; a client write would be rejected.
      expect(data.containsKey('isPremium'), isFalse);
      expect(data.containsKey('subscriptionSource'), isFalse);
      expect(data.containsKey('premiumExpiry'), isFalse);
      expect(data.containsKey('entitlementUpdatedAt'), isFalse);
    });
  });

  group('trial schema migration (backfillTrialSchemaAliases)', () {
    test("backfills a Jannie-schema doc with the client-schema aliases",
        () async {
      await fake.collection('users').doc('uid-1').set(jannieDoc());
      final changed = await SubscriptionStatusService.instance
          .backfillTrialSchemaAliases();
      expect(changed, isTrue);

      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(data.containsKey('subscriptionTrialEndsAt'), isTrue);
      expect((data['subscriptionTrialEndsAt'] as Timestamp).toDate(),
          DateTime(2026, 10, 21));
      expect(data['subscriptionStatus'], 'trialing');
    });

    test("backfills an Ocker-schema doc with the backend-schema aliases",
        () async {
      await fake.collection('users').doc('uid-1').set(ockerDoc());
      final changed = await SubscriptionStatusService.instance
          .backfillTrialSchemaAliases();
      expect(changed, isTrue);

      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(data.containsKey('trialEndsAt'), isTrue);
      expect(data.containsKey('trialEnd'), isTrue);
      expect((data['trialEndsAt'] as Timestamp).toDate(), DateTime(2026, 10, 21));
    });

    test('is idempotent — a second run makes no further change', () async {
      await fake.collection('users').doc('uid-1').set(jannieDoc());
      expect(
        await SubscriptionStatusService.instance.backfillTrialSchemaAliases(),
        isTrue,
      );
      expect(
        await SubscriptionStatusService.instance.backfillTrialSchemaAliases(),
        isFalse,
      );
    });

    test('never touches the rules-frozen server-owned fields', () async {
      await fake.collection('users').doc('uid-1').set({
        ...jannieDoc(),
        'isPremium': false,
        'subscriptionSource': 'trial',
        'entitlementUpdatedAt': Timestamp.fromDate(DateTime(2026, 9, 21)),
      });
      await SubscriptionStatusService.instance.backfillTrialSchemaAliases();
      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(data['isPremium'], isFalse);
      expect(data['subscriptionSource'], 'trial');
    });

    test('does nothing when the doc has no trial timestamps at all', () async {
      await fake.collection('users').doc('uid-1').set({'role': 'hunter'});
      expect(
        await SubscriptionStatusService.instance.backfillTrialSchemaAliases(),
        isFalse,
      );
    });
  });

  group('UserSubscription is schema-tolerant (dashboard banner)', () {
    test("reads the backend schema's trialEndsAt", () {
      final sub = UserSubscription.fromMap(jannieDoc());
      expect(sub.trialEndsAt, DateTime(2026, 10, 21));
    });

    test("reads the client schema's subscriptionTrialEndsAt", () {
      final sub = UserSubscription.fromMap(ockerDoc());
      expect(sub.trialEndsAt, DateTime(2026, 10, 21));
      expect(sub.isInTrial, isTrue);
      expect(sub.hasSubscription, isTrue);
    });
  });

  group('device fingerprint never blocks a first trial (TODO #5)', () {
    test('a stamped fingerprint does not deny a valid trial', () {
      final ent = UserEntitlement.fromMap(ockerDoc());
      // The doc carries a fingerprint + a valid trial -> access is granted.
      expect(ockerDoc().containsKey('deviceFingerprint'), isTrue);
      expect(ent.canAccessPremium(DateTime(2026, 9, 21)), isTrue);
    });
  });
}
