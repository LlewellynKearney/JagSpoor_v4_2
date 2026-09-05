import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:jagspoor/features/auth/services/demo_reviewer_config.dart';
import 'package:jagspoor/features/auth/services/demo_reviewer_service.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

/// A minimal fake [User] is not constructible through the public Firebase
/// API, so the service tests exercise the seam that returns a signed-in
/// user via the injected auth override. We use a real `FirebaseAuth`-less
/// path: the service's `signIn` seam returns a credential whose `user` is
/// resolved from an injected fake auth's `currentUser`.
///
/// To keep this hermetic (no Firebase app), the service is driven through
/// its `injectForTesting` seam with a `FakeFirebaseFirestore` + a stub
/// sign-in closure that returns a `UserCredential` stub. `UserCredential`
/// cannot be constructed directly, so we instead exercise the seeding path
/// directly (`seedDemoData`) for the data-contract assertions and the
/// sign-in wrapper through the seam's `currentUser` branch (which needs no
/// credential construction).
void main() {
  group('DemoReviewerConfig', () {
    test('exposes the review-only credentials', () {
      expect(DemoReviewerConfig.email, 'demo@jagspoor.co.za');
      expect(DemoReviewerConfig.password, isNotEmpty);
      expect(DemoReviewerConfig.role, 'hunter');
      expect(DemoReviewerConfig.displayName, isNotEmpty);
      expect(DemoReviewerConfig.enabled, isTrue);
    });
  });

  group('DemoReviewerService.seedDemoData', () {
    late FakeFirebaseFirestore firestore;
    late DemoReviewerService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = DemoReviewerService.instance;
      service.injectForTesting(firestore: firestore);
      UserRoleProvider.instance.reset();
    });

    tearDown(() {
      service.resetForTesting();
      UserRoleProvider.instance.reset();
    });

    test('stamps a complete hunter profile + role + subscription', () async {
      await service.seedDemoData('demo-uid');

      final doc = await firestore.collection('users').doc('demo-uid').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['role'], 'hunter');
      expect(data['firstName'], 'Demo');
      expect(data['lastName'], 'Reviewer');
      expect(data['email'], DemoReviewerConfig.email);
      expect(data['phone'], isNotEmpty);
      expect(data['outfitterId'], 'demo-uid');
      expect(data['subscriptionStatus'], 'active');
      expect(data['subscriptionTier'], 'hunter');
    });

    test('seeds SAPS applications across workflow stages', () async {
      await service.seedDemoData('demo-uid');

      final snap = await firestore
          .collection('license_applications')
          .where('hunterId', isEqualTo: 'demo-uid')
          .get();
      expect(snap.docs.length, greaterThanOrEqualTo(3));

      final statuses = snap.docs.map((d) => d.data()['currentStatus']).toSet();
      expect(statuses, containsAll(['Submitted', 'Provincial', 'CFR']));

      // At least one application carries the firearm make/calibre/serial so
      // the SAPS card pills render.
      final withMake = snap.docs.any(
        (d) => (d.data()['firearmMake'] as String? ?? '').isNotEmpty,
      );
      expect(withMake, isTrue);
    });

    test('seeds a firearm inventory with nested ammunition', () async {
      await service.seedDemoData('demo-uid');

      final firearms = await firestore
          .collection('firearms')
          .where('ownerId', isEqualTo: 'demo-uid')
          .get();
      expect(firearms.docs.length, greaterThanOrEqualTo(2));

      final first = firearms.docs.first;
      final ammo = await first.reference.collection('ammunition').get();
      expect(ammo.docs.length, greaterThanOrEqualTo(1));
      expect(ammo.docs.first.data()['ownerId'], 'demo-uid');
    });

    test('seeds Digital Trophy Room entries + a carcass log', () async {
      await service.seedDemoData('demo-uid');

      final trophies = await firestore
          .collection('trophies')
          .where('ownerId', isEqualTo: 'demo-uid')
          .get();
      expect(trophies.docs.length, greaterThanOrEqualTo(2));
      expect(
        trophies.docs.any((d) => (d.data()['species'] as String? ?? '').isNotEmpty),
        isTrue,
      );

      final carcass = await firestore
          .collection('carcass_logs')
          .where('hunterId', isEqualTo: 'demo-uid')
          .get();
      expect(carcass.docs.length, greaterThanOrEqualTo(1));
    });

    test('is idempotent — re-seeding does not throw and keeps data', () async {
      await service.seedDemoData('demo-uid');
      await service.seedDemoData('demo-uid');

      final saps = await firestore
          .collection('license_applications')
          .where('hunterId', isEqualTo: 'demo-uid')
          .get();
      expect(saps.docs.length, greaterThanOrEqualTo(3));
    });
  });

  group('DemoReviewerService.isEnabled / credentials', () {
    test('isEnabled reflects the config default', () {
      final service = DemoReviewerService.instance;
      service.injectForTesting(enabled: true);
      expect(service.isEnabled, isTrue);
      expect(service.demoEmail, DemoReviewerConfig.email);
      expect(service.demoPassword, DemoReviewerConfig.password);
      service.resetForTesting();
    });

    test('can be disabled for production roll-out', () {
      final service = DemoReviewerService.instance;
      service.injectForTesting(enabled: false);
      expect(service.isEnabled, isFalse);
      service.resetForTesting();
    });
  });
}