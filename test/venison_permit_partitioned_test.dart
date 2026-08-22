import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/venison_transport_permit.dart';
import 'package:jagspoor/features/hunter_mode/services/venison_permit_manager.dart';

/// Tests for the role-partitioned venison-permit collections:
/// `outfitter_venison_permits` (filterable by outfitterId) and
/// `hunter_venison_permits` (filterable by hunterId). Both partitions carry
/// the same document id so both roles independently view their issued
/// permits without permission conflicts.
void main() {
  // Construct a FakeFirebaseFirestore FIRST so the mock FieldValuePlatform
  // binds before any FieldValue.serverTimestamp() is realised.
  FakeFirebaseFirestore();

  VenisonPermitManager manager(FirebaseFirestore fake, String? uid) =>
      VenisonPermitManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => uid,
      );

  VenisonTransportPermit buildPermit({String? hunterId}) {
    return VenisonTransportPermit(
      permitNumber: 'JSV-2026-x',
      outfitterId: 'outfitter-1',
      hunterId: hunterId,
      hunterName: 'Jan Hunter',
      hunterIdNumber: '9001010000000',
      hunterCell: '0820000000',
      hunterAddress: '1 Bush Rd',
      authorizedPersonName: 'Koos Outfitter',
      farmName: 'Bosveld Ranch',
      farmAddress: 'Farm 12',
      farmCell: '0830000000',
      speciesHuntedAndTransported: const [
        {'species': 'Impala', 'quantity': 1},
      ],
    );
  }

  group('collection-name contract', () {
    test('the partitions + legacy collection are named as specified', () {
      expect(VenisonPermitManager.outfitterCollection,
          'outfitter_venison_permits');
      expect(
          VenisonPermitManager.hunterCollection, 'hunter_venison_permits');
      expect(VenisonPermitManager.legacyCollection, 'venison_permits');
    });
  });

  group('issueVenisonPermit dual-write', () {
    test('writes BOTH partitions under the same document id', () async {
      final fake = FakeFirebaseFirestore();
      final id = await manager(fake, 'outfitter-1')
          .issueVenisonPermit(permit: buildPermit(hunterId: 'hunter-1'));
      final outfitterDoc = await fake
          .collection(VenisonPermitManager.outfitterCollection)
          .doc(id)
          .get();
      final hunterDoc = await fake
          .collection(VenisonPermitManager.hunterCollection)
          .doc(id)
          .get();
      expect(outfitterDoc.exists, isTrue);
      expect(hunterDoc.exists, isTrue);
      expect(outfitterDoc.data()!['outfitterId'], 'outfitter-1');
      expect(outfitterDoc.data()!['hunterId'], 'hunter-1');
      expect(hunterDoc.data()!['hunterId'], 'hunter-1');
      expect(hunterDoc.data()!['outfitterId'], 'outfitter-1');
      // The legacy shared collection is no longer written.
      final legacy = await fake
          .collection(VenisonPermitManager.legacyCollection)
          .get();
      expect(legacy.docs, isEmpty);
    });

    test('writes only the outfitter partition when the hunter uid is unknown',
        () async {
      final fake = FakeFirebaseFirestore();
      final id = await manager(fake, 'outfitter-1')
          .issueVenisonPermit(permit: buildPermit());
      expect(
        (await fake
                .collection(VenisonPermitManager.outfitterCollection)
                .doc(id)
                .get())
            .exists,
        isTrue,
      );
      expect(
        (await fake
                .collection(VenisonPermitManager.hunterCollection)
                .doc(id)
                .get())
            .exists,
        isFalse,
      );
    });
  });

  group('role-partitioned reads', () {
    test('outfitter stream reads the outfitter partition by outfitterId',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake
          .collection(VenisonPermitManager.outfitterCollection)
          .add({'outfitterId': 'outfitter-1', 'permitNumber': 'JSV-1'});
      await fake
          .collection(VenisonPermitManager.outfitterCollection)
          .add({'outfitterId': 'outfitter-2', 'permitNumber': 'JSV-2'});
      final results = await manager(fake, 'outfitter-1')
          .getMyPermitsStream(isOutfitter: true)
          .first;
      expect(results, hasLength(1));
      expect(results.single.permitNumber, 'JSV-1');
    });

    test('hunter stream reads the hunter partition by hunterId', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection(VenisonPermitManager.hunterCollection).add({
        'outfitterId': 'outfitter-1',
        'hunterId': 'hunter-1',
        'userId': 'hunter-1',
        'permitNumber': 'JSV-1',
      });
      await fake.collection(VenisonPermitManager.hunterCollection).add({
        'outfitterId': 'outfitter-1',
        'hunterId': 'hunter-2',
        'permitNumber': 'JSV-2',
      });
      final results = await manager(fake, 'hunter-1')
          .getMyPermitsStream(isOutfitter: false)
          .first;
      expect(results, hasLength(1));
      expect(results.single.permitNumber, 'JSV-1');
    });

    test('partitions are isolated: outfitter docs do not leak into the '
        'hunter stream and vice versa', () async {
      final fake = FakeFirebaseFirestore();
      // A permit only in the outfitter partition (hunter uid unknown at
      // issue time) must NOT surface in any hunter stream.
      await fake.collection(VenisonPermitManager.outfitterCollection).add({
        'outfitterId': 'outfitter-1',
        'permitNumber': 'JSV-OUT',
      });
      // A permit only in the hunter partition must NOT surface in the
      // outfitter stream.
      await fake.collection(VenisonPermitManager.hunterCollection).add({
        'outfitterId': 'outfitter-1',
        'hunterId': 'hunter-1',
        'permitNumber': 'JSV-HUNT',
      });
      final hunterResults = await manager(fake, 'hunter-1')
          .getMyPermitsStream(isOutfitter: false)
          .first;
      expect(hunterResults.map((p) => p.permitNumber), ['JSV-HUNT']);
      final outfitterResults = await manager(fake, 'outfitter-1')
          .getMyPermitsStream(isOutfitter: true)
          .first;
      expect(outfitterResults.map((p) => p.permitNumber), ['JSV-OUT']);
    });
  });

  group('cross-partition consistency', () {
    test('updatePermitStatus propagates to both partitions', () async {
      final fake = FakeFirebaseFirestore();
      final id = await manager(fake, 'outfitter-1')
          .issueVenisonPermit(permit: buildPermit(hunterId: 'hunter-1'));
      await manager(fake, 'outfitter-1')
          .updatePermitStatus(permitId: id, newStatus: 'Voided');
      for (final collection in [
        VenisonPermitManager.outfitterCollection,
        VenisonPermitManager.hunterCollection,
      ]) {
        final doc = await fake.collection(collection).doc(id).get();
        expect(doc.data()!['status'], 'Voided', reason: collection);
      }
    });

    test('updatePermitStatus throws for an unknown permit id', () async {
      final fake = FakeFirebaseFirestore();
      expect(
        () => manager(fake, 'outfitter-1')
            .updatePermitStatus(permitId: 'missing', newStatus: 'Voided'),
        throwsException,
      );
    });

    test('deletePermit removes every partition copy', () async {
      final fake = FakeFirebaseFirestore();
      final id = await manager(fake, 'outfitter-1')
          .issueVenisonPermit(permit: buildPermit(hunterId: 'hunter-1'));
      await manager(fake, 'outfitter-1').deletePermit(id);
      for (final collection in [
        VenisonPermitManager.outfitterCollection,
        VenisonPermitManager.hunterCollection,
      ]) {
        final doc = await fake.collection(collection).doc(id).get();
        expect(doc.exists, isFalse, reason: collection);
      }
    });

    test('getPermitById resolves from the outfitter partition', () async {
      final fake = FakeFirebaseFirestore();
      final id = await manager(fake, 'outfitter-1')
          .issueVenisonPermit(permit: buildPermit(hunterId: 'hunter-1'));
      final permit = await manager(fake, 'outfitter-1').getPermitById(id);
      expect(permit, isNotNull);
      expect(permit!.permitNumber, 'JSV-2026-x');
    });

    test('getPermitById falls back to the legacy shared collection', () async {
      final fake = FakeFirebaseFirestore();
      final ref = await fake.collection(VenisonPermitManager.legacyCollection).add({
        'outfitterId': 'outfitter-1',
        'hunterId': 'hunter-1',
        'permitNumber': 'JSV-LEGACY',
      });
      final permit =
          await manager(fake, 'outfitter-1').getPermitById(ref.id);
      expect(permit, isNotNull);
      expect(permit!.permitNumber, 'JSV-LEGACY');
    });

    test('getPermitById returns null for an unknown id', () async {
      final fake = FakeFirebaseFirestore();
      expect(
        await manager(fake, 'outfitter-1').getPermitById('nope'),
        isNull,
      );
    });
  });
}
