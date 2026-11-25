import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// `getCampsForHunter` query contract (Phase 7D).
///
/// The live camp rule gates a hunter read on
/// `request.auth.uid in resource.data.allowedHunterUids`, and Firestore rules
/// are not filters: the QUERY must constrain the same field. These tests pin
/// that contract — the `arrayContains` constraint, the fail-closed null uid,
/// and the client-side second defence.
void main() {
  const outfitterUid = 'outfitter-1';
  const hunterUid = 'hunter-1';
  const otherHunterUid = 'hunter-2';
  const farmId = 'farm-1';
  const campId = 'camp-1';

  VeldCarryRepository hunterRepo(FakeFirebaseFirestore firestore) =>
      VeldCarryRepository.forTesting(firestore: firestore);

  Camp camp({String id = campId, String name = 'North Camp'}) => Camp(
        id: id,
        farmId: farmId,
        name: name,
        totalSizeHa: 1000,
        province: 'Limpopo',
        district: 'Waterberg',
        veldType: 'Sweetveld',
        veldCondition: Camp.veldConditionGood,
        deptNormHaPerLsu: 10,
      );

  /// Seeds a camp carrying [allowed] as its `allowedHunterUids` allow-list.
  Future<void> seedCamp(
    FakeFirebaseFirestore firestore,
    Camp value, {
    required List<String> allowed,
  }) async {
    final data = Map<String, dynamic>.from(value.toMap());
    data[Camp.allowedHunterUidsField] = allowed;
    await firestore
        .collection(VeldCarryRepository.usersCollection)
        .doc(outfitterUid)
        .collection(VeldCarryRepository.farmsCollection)
        .doc(farmId)
        .collection(VeldCarryRepository.campsCollection)
        .doc(value.id)
        .set(data);
  }

  /// Seeds the booking the client-side gate requires, so a test isolates the
  /// ALLOW-LIST behaviour rather than the booking gate.
  Future<void> seedBooking(
    FakeFirebaseFirestore firestore, {
    String hunter = hunterUid,
    String status = BookingStatus.confirmed,
  }) async {
    await firestore.collection('bookings').doc('booking-$hunter').set({
      'hunterId': hunter,
      'outfitterId': outfitterUid,
      'farmId': farmId,
      'status': status,
    });
  }

  group('getCampsForHunter allowedHunterUids query', () {
    test('a hunter named in allowedHunterUids gets the camps', () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp(), allowed: const [hunterUid]);
      await seedBooking(firestore);

      final camps = await hunterRepo(firestore).getCampsForHunter(
        farmId,
        outfitterUid: outfitterUid,
        hunterUid: hunterUid,
      );

      expect(camps, hasLength(1));
      expect(camps.single.id, campId);
      expect(camps.single.name, 'North Camp');
    });

    test('a hunter NOT in allowedHunterUids gets an empty list', () async {
      final firestore = FakeFirebaseFirestore();
      // The hunter holds a confirmed booking, so only the allow-list can be
      // responsible for the empty result.
      await seedCamp(firestore, camp(), allowed: const [otherHunterUid]);
      await seedBooking(firestore);

      final camps = await hunterRepo(firestore).getCampsForHunter(
        farmId,
        outfitterUid: outfitterUid,
        hunterUid: hunterUid,
      );

      expect(camps, isEmpty);
    });

    test('a null / blank hunter uid fails closed with no query at all',
        () async {
      final firestore = FakeFirebaseFirestore();
      await seedCamp(firestore, camp(), allowed: const [hunterUid]);
      await seedBooking(firestore);

      final repo = hunterRepo(firestore);

      expect(
        await repo.getCampsForHunter(farmId, outfitterUid: outfitterUid),
        isEmpty,
        reason: 'a null uid must never fall back to an unconstrained read',
      );
      expect(
        await repo.getCampsForHunter(
          farmId,
          outfitterUid: outfitterUid,
          hunterUid: '   ',
        ),
        isEmpty,
        reason: 'a blank uid must never fall back to an unconstrained read',
      );
    });

    test('the query constrains allowedHunterUids with arrayContains', () {
      final source =
          File('lib/features/veld_carry/veld_carry_repository.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');

      // The Firestore constraint the camp rule requires.
      expect(
        source,
        contains(
          ".where(allowedHunterUidsField, arrayContains: hunter)",
        ),
      );
      // Fail-closed guard before the query is built.
      expect(source, contains("if (hunter.isEmpty) return const <Camp>[];"));
      // Second defence: the allow-list is re-checked client-side.
      expect(
        source,
        contains('.where((camp) => camp.allowedHunterUids.contains(hunter))'),
      );
    });
  });
}
