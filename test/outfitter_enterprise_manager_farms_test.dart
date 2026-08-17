import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/outfitter_enterprise_manager.dart';

/// Regression tests for the Outfitter Price List -> Hunter Custom Package
/// Builder data pipeline (the "empty pipeline" fix).
///
/// Locks in the contract that `getMyFarms` resolves WITHOUT requiring the
/// missing 3-field composite index `(outfitterId, status, createdAt)`. The
/// query must filter on `outfitterId` + `orderBy(createdAt)` only -- the
/// `status == 'active'` filter is applied CLIENT-SIDE by the screen -- so the
/// existing deployed `(outfitterId ASC, createdAt DESC)` index covers it.
void main() {
  late FakeFirebaseFirestore fake;
  String? currentUid = 'outfitter-1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    currentUid = 'outfitter-1';
  });

  OutfitterEnterpriseManager manager() =>
      OutfitterEnterpriseManager.forTesting(
        firestore: fake,
        currentUserIdResolver: () => currentUid,
      );

  Future<void> seedFarm({
    required String id,
    required String outfitterId,
    required String name,
    String? status,
    DateTime? createdAt,
  }) async {
    final data = <String, dynamic>{
      'outfitterId': outfitterId,
      'name': name,
      if (status != null) 'status': status,
      'createdAt': createdAt ?? DateTime(2026, 1, 1),
    };
    await fake.collection('farms').doc(id).set(data);
  }

  group('getMyFarms (Outfitter Price List farm dropdown source)', () {
    test('returns the outfitter\'s own farms', () async {
      await seedFarm(id: 'farm-a', outfitterId: 'outfitter-1', name: 'Farm A');
      await seedFarm(id: 'farm-b', outfitterId: 'outfitter-1', name: 'Farm B');
      // Another outfitter's farm must NOT appear.
      await seedFarm(id: 'farm-x', outfitterId: 'outfitter-2', name: 'Farm X');

      final snap = await manager().getMyFarms();

      final ids = snap.docs.map((d) => d.id).toList();
      expect(ids, containsAll(['farm-a', 'farm-b']));
      expect(ids, isNot(contains('farm-x')));
    });

    test('returns active AND inactive farms (status filtered client-side)',
        () async {
      // The key regression: `getMyFarms` no longer applies a server-side
      // `.where('status', isEqualTo: 'active')` filter (that required the
      // missing 3-field composite index). Both active + inactive farms are
      // returned; the screen filters active client-side. An inactive farm
      // MUST still be returned by the query itself (the screen decides).
      await seedFarm(
          id: 'farm-active', outfitterId: 'outfitter-1', name: 'Active',
          status: 'active');
      await seedFarm(
          id: 'farm-inactive', outfitterId: 'outfitter-1', name: 'Inactive',
          status: 'archived');

      final snap = await manager().getMyFarms();

      final ids = snap.docs.map((d) => d.id).toList();
      expect(ids, containsAll(['farm-active', 'farm-inactive']));
    });

    test('returns a farm with no status field (legacy-default-safe)',
        () async {
      // Farms created before the status field existed (or legacy docs) have
      // no `status` field. The screen treats `status == null` as active.
      await seedFarm(
          id: 'farm-legacy', outfitterId: 'outfitter-1', name: 'Legacy');

      final snap = await manager().getMyFarms();

      expect(snap.docs.map((d) => d.id).toList(), ['farm-legacy']);
    });

    test('orders by createdAt descending (newest first)', () async {
      await seedFarm(
          id: 'old', outfitterId: 'outfitter-1', name: 'Old',
          createdAt: DateTime(2025, 1, 1));
      await seedFarm(
          id: 'new', outfitterId: 'outfitter-1', name: 'New',
          createdAt: DateTime(2026, 6, 1));
      await seedFarm(
          id: 'mid', outfitterId: 'outfitter-1', name: 'Mid',
          createdAt: DateTime(2025, 12, 1));

      final snap = await manager().getMyFarms();

      expect(snap.docs.map((d) => d.id).toList(), ['new', 'mid', 'old']);
    });

    test('throws when unauthenticated', () async {
      currentUid = null;

      expect(() => manager().getMyFarms(), throwsA(isA<Exception>()));
    });

    test('returns empty when the outfitter has no farms', () async {
      await seedFarm(id: 'farm-x', outfitterId: 'outfitter-2', name: 'X');

      final snap = await manager().getMyFarms();

      expect(snap.docs, isEmpty);
    });
  });
}
