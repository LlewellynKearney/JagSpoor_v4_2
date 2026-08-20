import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/venison_transport_permit.dart';
import 'package:jagspoor/features/hunter_mode/services/venison_permit_manager.dart';

/// Unit tests for the hunter-side venison-permit visibility contract.
///
/// Locks in the visibility fix:
///  1. The hunter's permit stream matches permits stamped with EITHER
///     `hunterId == uid` OR the legacy `userId == uid` alias (Filter.or), so
///     permits written by any app version render for the designated hunter.
///  2. The stream no longer uses a server-side `.orderBy('createdAt')` (an
///     equality/OR + orderBy combo that required a composite index); entries
///     are sorted newest-first client-side.
///  3. `issueVenisonPermit` resolves + dual-stamps the hunter uid under BOTH
///     aliases so a hunter-self-issued permit (or a booking-linked permit) is
///     immediately visible to the hunter.
void main() {
  // Construct a FakeFirebaseFirestore FIRST so the mock `FieldValuePlatform`
  // binds before any `FieldValue.serverTimestamp()` is realised (mirrors the
  // `optic_log_service_test` isolation pattern).
  FakeFirebaseFirestore();

  VenisonPermitManager manager(FirebaseFirestore fake, String? uid) =>
      VenisonPermitManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => uid,
      );

  Future<void> seedPermit(
    FirebaseFirestore fake, {
    String? outfitterId,
    String? hunterId,
    String? userId,
    DateTime? createdAt,
  }) async {
    await fake.collection('venison_permits').add({
      'permitNumber': 'JSV-2026-x',
      'outfitterId': outfitterId ?? 'outfitter-1',
      if (hunterId != null) 'hunterId': hunterId,
      if (userId != null) 'userId': userId,
      'hunterName': 'Jan Hunter',
      'status': 'Issued',
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 8, 1)),
    });
  }

  group('getMyPermitsStream (hunter dual-alias matching)', () {
    test('null uid -> empty stream (no throw, no Firestore access)', () async {
      final fake = FakeFirebaseFirestore();
      final results =
          await manager(fake, null).getMyPermitsStream(isOutfitter: false).first;
      expect(results, isEmpty);
    });

    test('hunter sees a permit stamped with hunterId == uid', () async {
      final fake = FakeFirebaseFirestore();
      await seedPermit(fake, hunterId: 'hunter-1');
      final results = await manager(fake, 'hunter-1')
          .getMyPermitsStream(isOutfitter: false)
          .first;
      expect(results, hasLength(1));
      expect(results.single.hunterId, 'hunter-1');
    });

    test('hunter sees a legacy permit stamped ONLY with userId == uid',
        () async {
      final fake = FakeFirebaseFirestore();
      // Legacy shape: no hunterId at all, only the userId alias.
      await seedPermit(fake, userId: 'hunter-1');
      final results = await manager(fake, 'hunter-1')
          .getMyPermitsStream(isOutfitter: false)
          .first;
      expect(results, hasLength(1));
      expect(results.single.userId, 'hunter-1');
      // Alias tolerance back-fills hunterId from userId.
      expect(results.single.hunterId, 'hunter-1');
      expect(results.single.effectiveHunterId, 'hunter-1');
    });

    test('hunter does NOT see another hunter\'s permit', () async {
      final fake = FakeFirebaseFirestore();
      await seedPermit(fake, hunterId: 'hunter-2');
      await seedPermit(fake, userId: 'hunter-3');
      final results = await manager(fake, 'hunter-1')
          .getMyPermitsStream(isOutfitter: false)
          .first;
      expect(results, isEmpty);
    });

    test('a permit stamped with BOTH aliases renders exactly once (dedupe)',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedPermit(fake, hunterId: 'hunter-1', userId: 'hunter-1');
      final results = await manager(fake, 'hunter-1')
          .getMyPermitsStream(isOutfitter: false)
          .first;
      expect(results, hasLength(1));
    });

    test('permits are sorted newest-first client-side (no server orderBy)',
        () async {
      final fake = FakeFirebaseFirestore();
      // Seed oldest first to prove the client-side sort drives ordering.
      await seedPermit(fake, hunterId: 'hunter-1', createdAt: DateTime(2026, 1, 1));
      await seedPermit(fake, hunterId: 'hunter-1', createdAt: DateTime(2026, 8, 1));
      await seedPermit(fake, hunterId: 'hunter-1', createdAt: DateTime(2026, 4, 1));
      final results = await manager(fake, 'hunter-1')
          .getMyPermitsStream(isOutfitter: false)
          .first;
      expect(results, hasLength(3));
      expect(results[0].createdAt, DateTime(2026, 8, 1));
      expect(results[1].createdAt, DateTime(2026, 4, 1));
      expect(results[2].createdAt, DateTime(2026, 1, 1));
    });
  });

  group('getMyPermitsStream (outfitter)', () {
    test('outfitter sees permits they issued (outfitterId == uid)', () async {
      final fake = FakeFirebaseFirestore();
      await seedPermit(fake, outfitterId: 'outfitter-9', hunterId: 'hunter-1');
      await seedPermit(fake, outfitterId: 'outfitter-other');
      final results = await manager(fake, 'outfitter-9')
          .getMyPermitsStream(isOutfitter: true)
          .first;
      expect(results, hasLength(1));
      expect(results.single.outfitterId, 'outfitter-9');
    });
  });

  group('resolveHunterUid (issue-time hunter stamping)', () {
    test('explicit permit hunterId wins', () {
      expect(
        VenisonPermitManager.resolveHunterUid(
          permitHunterId: 'hunter-booked',
          issuerUid: 'outfitter-1',
          outfitterId: 'outfitter-1',
        ),
        'hunter-booked',
      );
    });

    test('hunter self-issue stamps the issuer uid (issuer != outfitter)', () {
      expect(
        VenisonPermitManager.resolveHunterUid(
          permitHunterId: null,
          issuerUid: 'hunter-1',
          outfitterId: 'outfitter-1',
        ),
        'hunter-1',
      );
    });

    test('outfitter issue without a booking context stamps nothing', () {
      expect(
        VenisonPermitManager.resolveHunterUid(
          permitHunterId: null,
          issuerUid: 'outfitter-1',
          outfitterId: 'outfitter-1',
        ),
        isNull,
      );
    });

    test('blank/whitespace permit hunterId falls through to the issuer rule',
        () {
      expect(
        VenisonPermitManager.resolveHunterUid(
          permitHunterId: '   ',
          issuerUid: 'hunter-1',
          outfitterId: 'outfitter-1',
        ),
        'hunter-1',
      );
    });
  });

  group('issueVenisonPermit dual-stamping', () {
    test('a booking-linked permit writes BOTH hunterId and userId aliases',
        () async {
      final fake = FakeFirebaseFirestore();
      final permit = VenisonTransportPermit(
        permitNumber: 'JSV-2026-1',
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-1',
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
      final id = await manager(fake, 'outfitter-1')
          .issueVenisonPermit(permit: permit);
      final doc =
          await fake.collection('venison_permits').doc(id).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['hunterId'], 'hunter-1');
      expect(doc.data()!['userId'], 'hunter-1');
      expect(doc.data()!['outfitterId'], 'outfitter-1');
    });

    test('a hunter self-issued permit stamps the hunter uid under both aliases',
        () async {
      final fake = FakeFirebaseFirestore();
      final permit = VenisonTransportPermit(
        permitNumber: 'JSV-2026-2',
        outfitterId: 'outfitter-1',
        hunterName: 'Jan Hunter',
        hunterIdNumber: '9001010000000',
        hunterCell: '0820000000',
        hunterAddress: '1 Bush Rd',
        authorizedPersonName: 'Koos Outfitter',
        farmName: 'Bosveld Ranch',
        farmAddress: 'Farm 12',
        farmCell: '0830000000',
        speciesHuntedAndTransported: const [
          {'species': 'Kudu', 'quantity': 1},
        ],
      );
      // The hunter (hunter-1) issues their own permit -- no prefill hunterId.
      final id =
          await manager(fake, 'hunter-1').issueVenisonPermit(permit: permit);
      final doc = await fake.collection('venison_permits').doc(id).get();
      expect(doc.data()!['hunterId'], 'hunter-1');
      expect(doc.data()!['userId'], 'hunter-1');
    });

    test('an outfitter-issued permit without a booking stamps no hunter uid',
        () async {
      final fake = FakeFirebaseFirestore();
      final permit = VenisonTransportPermit(
        permitNumber: 'JSV-2026-3',
        outfitterId: 'outfitter-1',
        hunterName: 'Jan Hunter',
        hunterIdNumber: '9001010000000',
        hunterCell: '0820000000',
        hunterAddress: '1 Bush Rd',
        authorizedPersonName: 'Koos Outfitter',
        farmName: 'Bosveld Ranch',
        farmAddress: 'Farm 12',
        farmCell: '0830000000',
        speciesHuntedAndTransported: const [
          {'species': 'Eland', 'quantity': 1},
        ],
      );
      final id = await manager(fake, 'outfitter-1')
          .issueVenisonPermit(permit: permit);
      final doc = await fake.collection('venison_permits').doc(id).get();
      expect(doc.data()!.containsKey('hunterId'), isFalse);
      expect(doc.data()!.containsKey('userId'), isFalse);
    });

    test('unauthenticated caller is rejected', () async {
      final fake = FakeFirebaseFirestore();
      final permit = VenisonTransportPermit(
        permitNumber: 'JSV-2026-4',
        outfitterId: 'outfitter-1',
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
      expect(
        () => manager(fake, null).issueVenisonPermit(permit: permit),
        throwsException,
      );
    });
  });
}
