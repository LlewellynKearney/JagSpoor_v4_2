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

  group('markTrialStarted (server-owned trial window — v9)', () {
    test('writes ONLY the client-owned tier/promo/provider metadata', () async {
      await SubscriptionStatusService.instance.markTrialStarted(
        tier: SubscriptionTier.hunter,
      );
      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(data['subscriptionTier'], 'hunter');
      expect(data['subscriptionProvider'], 'google_play_billing');
      // Every trial-window / status field is frozen (server-owned) — the
      // client write must not include any of them.
      for (final frozen in const [
        'subscriptionStatus',
        'trialEndsAt',
        'trialEnd',
        'trialStartedAt',
        'trialStart',
        'subscriptionTrialEndsAt',
        'subscriptionTrialStart',
      ]) {
        expect(data.containsKey(frozen), isFalse, reason: '$frozen is frozen');
      }
    });

    test('never writes the premium entitlement (rules-frozen) fields',
        () async {
      await SubscriptionStatusService.instance.markTrialStarted(
        tier: SubscriptionTier.hunter,
      );
      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      expect(data.containsKey('isPremium'), isFalse);
      expect(data.containsKey('subscriptionSource'), isFalse);
      expect(data.containsKey('premiumExpiry'), isFalse);
      expect(data.containsKey('entitlementUpdatedAt'), isFalse);
    });
  });

  group('trial schema migration (backfillTrialSchemaAliases — disabled v9)', () {
    test('is a no-op: never writes a frozen field', () async {
      await fake.collection('users').doc('uid-1').set(jannieDoc());
      final changed = await SubscriptionStatusService.instance
          .backfillTrialSchemaAliases();
      expect(changed, isFalse);
      final data = (await fake.collection('users').doc('uid-1').get()).data()!;
      // The doc is untouched — no alias backfill (all aliases are frozen).
      expect(data.containsKey('subscriptionTrialEndsAt'), isFalse);
    });

    test('readTrialState resolves the backend-schema window (read-only)',
        () async {
      await fake.collection('users').doc('uid-1').set(jannieDoc());
      final state = await SubscriptionStatusService.instance.readTrialState();
      expect(state.end, DateTime(2026, 10, 21));
    });

    test('readTrialState resolves the client-schema window (read-only)',
        () async {
      await fake.collection('users').doc('uid-1').set(ockerDoc());
      // The Ocker doc reads `subscriptionTrialEndsAt`; readTrialState resolves
      // it through the alias list without any write.
      final state = await SubscriptionStatusService.instance.readTrialState();
      expect(state.end, isNotNull);
    });

    test('readTrialState tolerates a doc with no trial timestamps', () async {
      await fake.collection('users').doc('uid-1').set({'role': 'hunter'});
      final state = await SubscriptionStatusService.instance.readTrialState();
      expect(state.start, isNull);
      expect(state.end, isNull);
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
