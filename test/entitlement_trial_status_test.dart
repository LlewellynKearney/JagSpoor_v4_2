import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/services/entitlement_service.dart';

/// Regression coverage for TODO #5: a brand-new account with a VALID trial in
/// Firestore was shown the "Premium Access Required — Your free trial has
/// ended" paywall on first install.
///
/// Root cause: [UserEntitlement.fromMap] never read `subscriptionStatus` and
/// only looked at `trialEnd` / `trialEndsAt`, so the canonical new-user field
/// `subscriptionTrialEndsAt` (written by the Auth `onCreate` trial trigger +
/// `markTrialStarted`) resolved to null → `isTrialActive` false →
/// `canAccessPremium` false → instant paywall.
void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    EntitlementService.firestoreForTesting = fake;
    EntitlementService.currentUserIdResolverForTesting = () => 'uid-1';
  });

  tearDown(() => EntitlementService.resetTestSeams());

  /// The exact document shape of the reported account (Ocker Fourie,
  /// uid qzV9jsLYvdSyl1wmeplQD807sdG2) — `subscriptionStatus: 'trialing'`
  /// with `subscriptionTrialEndsAt` as a Firestore Timestamp.
  Map<String, dynamic> ockerDoc() => {
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt': Timestamp.fromDate(DateTime(2026, 10, 21)),
        'subscriptionProvider': 'google_play_billing',
        'deviceFingerprint':
            '7f67c778478f6f5be19305998c2e598facce7733d09f4026a7e210ec3a9dd2d3',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 21)),
      };

  group("Ocker's doc passes the premium gate (TODO #5)", () {
    test('fromMap reads subscriptionStatus + subscriptionTrialEndsAt', () {
      final ent = UserEntitlement.fromMap(ockerDoc());
      expect(ent.subscriptionStatus, 'trialing');
      expect(ent.trialEnd, DateTime(2026, 10, 21));
    });

    test('isTrialActive + canAccessPremium are true inside the window', () {
      final ent = UserEntitlement.fromMap(ockerDoc());
      final now = DateTime(2026, 9, 21, 18, 35); // first-install timestamp
      expect(ent.isTrialActive(now), isTrue);
      expect(ent.canAccessPremium(now), isTrue);
      expect(ent.trialDaysRemaining(now), greaterThan(0));
    });

    test('EntitlementService reads the doc and grants access', () async {
      await fake.collection('users').doc('uid-1').set(ockerDoc());
      final ent = await EntitlementService.instance.getMyEntitlement();
      expect(ent.canAccessPremium(DateTime(2026, 9, 21, 18, 35)), isTrue);
    });
  });

  group('status-string tolerance', () {
    test("accepts 'trial', 'trialing' and 'trialling'", () {
      for (final status in ['trial', 'trialing', 'trialling', 'TRIALING']) {
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

  group('trial-end field-name aliases', () {
    test('resolves every documented trial-end spelling', () {
      final end = DateTime(2026, 10, 21);
      for (final key in [
        'subscriptionTrialEndsAt',
        'trialEnd',
        'trialEndsAt',
        'subscriptionTrialEnd',
        'subscription_trial_ends_at',
        'trial_end',
        'trial_ends_at',
      ]) {
        final ent = UserEntitlement.fromMap({
          'subscriptionStatus': 'trialing',
          key: Timestamp.fromDate(end),
        });
        expect(ent.trialEnd, end, reason: 'field "$key" should resolve');
        expect(ent.isTrialActive(DateTime(2026, 9, 21)), isTrue);
      }
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
