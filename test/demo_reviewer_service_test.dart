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
      expect(DemoReviewerConfig.role, 'dual');
      expect(DemoReviewerConfig.roles, containsAll(['hunter', 'outfitter']));
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

    test('stamps a complete dual-role profile + subscription', () async {
      await service.seedDemoData('demo-uid');

      final doc = await firestore.collection('users').doc('demo-uid').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      // Dual-role signals: primary role 'dual' + explicit role set + flag.
      expect(data['role'], 'dual');
      expect(data['isDualRole'], isTrue);
      expect(data['roles'], containsAll(['hunter', 'outfitter']));
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

    test('seeds a canonical outfitters/{uid} enterprise profile', () async {
      await service.seedDemoData('demo-uid');

      final doc = await firestore.collection('outfitters').doc('demo-uid').get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['outfitterId'], 'demo-uid');
      expect(data['role'], 'outfitter');
      expect(data['name'], 'JagSpoor Demo Outfitters');
      expect(data['province'], 'Limpopo');
      expect(data['verified'], isTrue);
    });

    test('seeds a registered farm owned by the reviewer', () async {
      await service.seedDemoData('demo-uid');

      final farms = await firestore
          .collection('farms')
          .where('outfitterId', isEqualTo: 'demo-uid')
          .get();
      expect(farms.docs.length, greaterThanOrEqualTo(1));
      final farm = farms.docs.first;
      expect(farm.data()['name'], 'Bosveld Demo Ranch');
      expect(farm.data()['province'], 'Limpopo');
      expect(farm.data()['status'], 'active');
    });

    test('seeds a farm service-rate card at farm_service_rates/{farmId}',
        () async {
      await service.seedDemoData('demo-uid');

      final farms = await firestore
          .collection('farms')
          .where('outfitterId', isEqualTo: 'demo-uid')
          .get();
      final farmId = farms.docs.first.id;
      final doc = await firestore
          .collection('farm_service_rates')
          .doc(farmId)
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['outfitterId'], 'demo-uid');
      final rates = doc.data()!['rates'] as Map<String, dynamic>;
      // The two headline showcase rates.
      expect(rates, contains('bakkie_vehicle'));
      expect(rates, contains('hunter_daily'));
      expect((rates['bakkie_vehicle'] as Map)['pricePerUnit'], 1450.0);
    });

    test('seeds trophy stock + a published package + a price list', () async {
      await service.seedDemoData('demo-uid');

      final stock = await firestore
          .collection('trophy_stock')
          .where('outfitterId', isEqualTo: 'demo-uid')
          .get();
      expect(stock.docs.length, greaterThanOrEqualTo(3));
      expect(
        stock.docs.any(
          (d) => (d.data()['species'] as String? ?? '') == 'Greater Kudu',
        ),
        isTrue,
      );

      final packages = await firestore
          .collection('packages')
          .where('outfitterId', isEqualTo: 'demo-uid')
          .get();
      expect(packages.docs.length, greaterThanOrEqualTo(1));
      final pkg = packages.docs.first.data();
      expect(pkg['title'], 'Waterberg Kudu Trophy Hunt (3 Nights)');
      expect(pkg['basePriceRands'], 24500.0);
      expect(pkg['status'], 'active');
      expect(pkg['availabilityStart'], isNotNull);

      final priceList = await firestore
          .collection('farm_pricelists')
          .where('outfitterId', isEqualTo: 'demo-uid')
          .get();
      expect(priceList.docs.length, greaterThanOrEqualTo(3));
    });

    test('seeds client bookings across the workflow stages', () async {
      await service.seedDemoData('demo-uid');

      final bookings = await firestore
          .collection('bookings')
          .where('outfitterId', isEqualTo: 'demo-uid')
          .get();
      expect(bookings.docs.length, greaterThanOrEqualTo(3));

      final statuses = bookings.docs.map((d) => d.data()['status']).toSet();
      expect(
        statuses,
        containsAll([
          'Pending Approval',
          'Awaiting Payment',
          'Confirmed',
        ]),
      );
      // Every booking is co-owned by the reviewer as the outfitter + a
      // separate client hunter, so the outfitter dashboard's booking query
      // (`outfitterId == uid`) + the isBookingOutfitter rule both admit it.
      expect(
        bookings.docs.every((d) => d.data()['hunterId'] != 'demo-uid'),
        isTrue,
      );
    });
  });

  group('DemoReviewerService dual-role resolution', () {
    test('seedDemoData profile resolves to AppRole.dual via the provider',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = DemoReviewerService.instance;
      service.injectForTesting(firestore: firestore, enabled: true);
      UserRoleProvider.instance.reset();
      try {
        await service.seedDemoData('demo-uid');
        UserRoleProvider.instance.injectForTesting(
          db: firestore,
          testUid: 'demo-uid',
          testEmail: DemoReviewerConfig.email,
        );
        final role = await UserRoleProvider.instance.resolveRole(forceRefresh: true);
        expect(role, AppRole.dual);
        expect(UserRoleProvider.instance.hasOutfitterAccess, isTrue);
        expect(UserRoleProvider.instance.hasHunterAccess, isTrue);
        expect(UserRoleProvider.instance.isDual, isTrue);
      } finally {
        service.resetForTesting();
        UserRoleProvider.instance.reset();
      }
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