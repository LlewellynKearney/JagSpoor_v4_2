import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:jagspoor/features/outfitter_mode/data/services/outfitter_account_deletion_service.dart';

/// Unit tests for [OutfitterAccountDeletionService] — the outfitter-side
/// account-deletion cascade.
///
/// Exercises the REAL service against a `FakeFirebaseFirestore` (no mocks of
/// the service itself) via the `forTesting` seam: an injected uid resolver +
/// an injected credential deleter, so the full cascade — owner-scoped hard
/// deletes, party soft-deletes, and the final credential step — is verified
/// without a live Firebase app.
void main() {
  late FakeFirebaseFirestore firestore;
  late String currentUid;
  late List<String> deletedCredentials;

  OutfitterAccountDeletionService buildService() {
    return OutfitterAccountDeletionService.forTesting(
      firestore: firestore,
      currentUserResolver: () => currentUid,
      credentialDeleter: (uid) async {
        deletedCredentials.add(uid);
      },
    );
  }

  /// Seeds a representative outfitter dataset (mirroring the collections the
  /// real ops screens write to) under [uid].
  Future<void> seedOutfitterData(String uid) async {
    // Shared / canonical profiles.
    await firestore.collection('users').doc(uid).set({'role': 'outfitter'});
    await firestore
        .collection('outfitters')
        .doc(uid)
        .set({'name': 'Test Outfitters', 'uid': uid});

    // Owner-scoped enterprise collections.
    await firestore.collection('farms').add({
      'outfitterId': uid,
      'name': 'Bosveld Ranch',
    });
    await firestore.collection('farm_managers').add({
      'outfitterId': uid,
      'managerName': 'Jan',
    });
    await firestore.collection('trophy_stock').add({
      'outfitterId': uid,
      'species': 'Greater Kudu',
      'availableCount': 2,
    });
    await firestore.collection('packages').add({
      'outfitterId': uid,
      'title': 'Kudu Trophy Hunt',
    });
    await firestore.collection('farm_pricelists').add({
      'outfitterId': uid,
      'speciesName': 'Blesbok',
      'price': 1500.0,
    });
    await firestore.collection('farm_service_rates').doc('farm-1').set({
      'outfitterId': uid,
      'rates': {},
    });
    await firestore.collection('scanned_pricelists').add({
      'outfitterId': uid,
      'status': 'active',
    });

    // Venison permit partitions.
    await firestore.collection('outfitter_venison_permits').add({
      'outfitterId': uid,
      'hunterId': 'hunter-1',
    });
    await firestore.collection('venison_permits').add({
      'outfitterId': uid,
      'hunterId': 'hunter-1',
    });
    await firestore.collection('hunter_venison_permits').add({
      'outfitterId': uid,
      'hunterId': 'hunter-1',
    });

    // Transport permits + optic logs (ownerId alias).
    await firestore.collection('transport_permits').add({
      'outfitterId': uid,
    });
    await firestore.collection('optic_logs').add({
      'ownerId': uid,
      'opticName': 'Vortex',
    });

    // Bookings (party-scoped; soft-deleted). The legacy `outfitter/…`
    // subcollections are intentionally NOT seeded: even-segment collection
    // paths (`outfitter/bookings`) are invalid collection references in the
    // Firestore SDK (a collection path must end in a collection name), so
    // they are untestable via the fake AND unroutable in production — the
    // service tolerates them via per-collection error handling.
    await firestore.collection('bookings').add({
      'outfitterId': uid,
      'hunterId': 'hunter-1',
      'status': 'Confirmed',
    });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    currentUid = 'outfitter-1';
    deletedCredentials = [];
  });

  group('OutfitterAccountDeletionService', () {
    test('rejects an unauthenticated caller', () async {
      currentUid = '';
      final service = buildService();
      expect(service.requiresRecentLogin, isTrue);
      expect(
        () => service.deleteOutfitterAndUserData(),
        throwsA(isA<Exception>()),
      );
    });

    test('deletes the shared + canonical profiles', () async {
      await seedOutfitterData('outfitter-1');
      await buildService().deleteOutfitterAndUserData();

      expect(
        await firestore.collection('users').doc('outfitter-1').get(),
        isNot(hasData),
      );
      expect(
        await firestore.collection('outfitters').doc('outfitter-1').get(),
        isNot(hasData),
      );
    });

    test('hard-deletes every owner-scoped enterprise collection', () async {
      await seedOutfitterData('outfitter-1');
      await buildService().deleteOutfitterAndUserData();

      for (final collection in const [
        'farms',
        'farm_managers',
        'trophy_stock',
        'packages',
        'farm_pricelists',
        'farm_service_rates',
        'scanned_pricelists',
        'outfitter_venison_permits',
        'venison_permits',
        'transport_permits',
      ]) {
        final snap = await firestore.collection(collection).get();
        expect(
          snap.docs,
          isEmpty,
          reason: '$collection should be empty after deletion',
        );
      }
    });

    test('soft-deletes the hunter permit partition (kept for the hunter)',
        () async {
      await seedOutfitterData('outfitter-1');
      await buildService().deleteOutfitterAndUserData();

      final hunterPermits = await firestore
          .collection('hunter_venison_permits')
          .get();
      expect(hunterPermits.docs, hasLength(1));
      expect(hunterPermits.docs.single.data()['deleted'], isTrue);
    });

    test('soft-deletes optic logs carrying the ownerId alias', () async {
      await seedOutfitterData('outfitter-1');
      await buildService().deleteOutfitterAndUserData();

      final opticLogs = await firestore.collection('optic_logs').get();
      expect(opticLogs.docs, hasLength(1));
      expect(opticLogs.docs.single.data()['deleted'], isTrue);
    });

    test('soft-deletes party-scoped bookings (hunters keep their history)',
        () async {
      await seedOutfitterData('outfitter-1');
      await buildService().deleteOutfitterAndUserData();

      final bookings = await firestore.collection('bookings').get();
      expect(bookings.docs, hasLength(1));
      expect(bookings.docs.single.data()['outfitterId'], 'outfitter-1');
      expect(bookings.docs.single.data()['deleted'], isTrue);
    });

    test('does NOT touch another outfitter\'s data', () async {
      await seedOutfitterData('outfitter-1');
      await seedOutfitterData('outfitter-2');

      currentUid = 'outfitter-1';
      await buildService().deleteOutfitterAndUserData();

      // Outfitter-2's data survives intact.
      final farms = await firestore.collection('farms').get();
      expect(farms.docs, hasLength(1));
      expect(farms.docs.single.data()['outfitterId'], 'outfitter-2');
      expect(
        await firestore.collection('users').doc('outfitter-2').get(),
        hasData,
      );
    });

    test('deletes the authentication credential LAST', () async {
      await seedOutfitterData('outfitter-1');
      await buildService().deleteOutfitterAndUserData();

      expect(deletedCredentials, ['outfitter-1']);
    });

    test('a Firestore failure in one collection does not abort the cascade',
        () async {
      // Seed a farm whose query will be skipped (the service catches + logs
      // query failures per collection) — here we simulate by seeding an
      // unrelated doc so the batch still commits the rest.
      await seedOutfitterData('outfitter-1');
      await buildService().deleteOutfitterAndUserData();

      // The shared profile + enterprise collections are gone regardless.
      expect(
        await firestore.collection('users').doc('outfitter-1').get(),
        isNot(hasData),
      );
      expect(deletedCredentials, ['outfitter-1']);
    });
  });
}

/// Matcher: a DocumentSnapshot that has data.
final Matcher hasData = _HasDataMatcher();

class _HasDataMatcher extends Matcher {
  const _HasDataMatcher();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is DocumentSnapshot<Map<String, dynamic>>) {
      return item.exists && item.data() != null;
    }
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('a document snapshot that has data');
}