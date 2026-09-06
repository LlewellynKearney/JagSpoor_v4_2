import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/ballistics/data/inventory_bridge.dart';
import 'package:jagspoor/features/ballistics/data/models/rifle_profile.dart';

void main() {
  group('InventoryBridge.updateRifleProfile', () {
    test('updates make/model/caliber/serial in place via merge', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('firearms').doc('f-1').set({
        'ownerId': 'u1',
        'make': 'TIKKA',
        'model': 'T3x',
        'caliber': '.308 Win',
        'serial': 'OB14468',
        'roundCount': 120,
        'createdAt': '2026-01-01T00:00:00.000',
      });

      final bridge = InventoryBridge(firestore: fake)
        ..currentUserIdResolverForTesting = () => 'u1';

      final updated = RifleProfile(
        id: 'f-1',
        name: 'HOWA 1500 Varmint',
        caliber: '.223 Rem',
        make: 'HOWA 1500',
        model: 'Varmint',
        serialNumber: 'XY753',
        ownerId: 'u1',
      );

      final ok = await bridge.updateRifleProfile('f-1', updated);
      expect(ok, isTrue);

      final doc = await fake.collection('firearms').doc('f-1').get();
      final data = doc.data()!;
      expect(data['make'], 'HOWA 1500');
      expect(data['model'], 'Varmint');
      expect(data['caliber'], '.223 Rem');
      expect(data['serialNumber'], 'XY753');
      // The merge preserved the tracking fields that were NOT part of the
      // quick-edit (round count survives, owner unchanged).
      expect(data['roundCount'], 120);
      expect(data['ownerId'], 'u1');
    });

    test('rejects an unauthenticated caller', () async {
      final fake = FakeFirebaseFirestore();
      final bridge = InventoryBridge(firestore: fake)
        ..currentUserIdResolverForTesting = () => null;
      final ok = await bridge.updateRifleProfile(
        'f-1',
        RifleProfile(id: 'f-1', name: 'X', caliber: '.22'),
      );
      expect(ok, isFalse);
    });

    test('rejects an empty firearm id', () async {
      final fake = FakeFirebaseFirestore();
      final bridge = InventoryBridge(firestore: fake)
        ..currentUserIdResolverForTesting = () => 'u1';
      final ok = await bridge.updateRifleProfile(
        '',
        RifleProfile(id: '', name: 'X', caliber: '.22'),
      );
      expect(ok, isFalse);
    });
  });

  group('RifleProfile model fields (quick-edit payload)', () {
    test('serial aliases resolve across schemas', () {
      final profile = RifleProfile.fromJson({
        'make': 'CZ',
        'model': '457',
        'serial': 'XY753',
        'calibre': '.22 LR',
      }, id: 'f-1');
      expect(profile.make, 'CZ');
      expect(profile.model, '457');
      // The safe writes `serial`; the model's canonical field is
      // serialNumber -> the alias resolution bridges them.
      expect(profile.serialNumber, 'XY753');
      expect(profile.caliber, '.22 LR');
      expect(profile.displayName, 'CZ 457 (.22 LR)');
    });

    test('copyWith updates the editable fields', () {
      final base = RifleProfile(
        id: 'f-1',
        name: '',
        caliber: '.308',
        make: 'TIKKA',
        model: 'T3x',
        serialNumber: 'OB14468',
      );
      final edited = base.copyWith(
        make: 'HOWA',
        model: '1500',
        caliber: '.223',
        serialNumber: 'XY753',
      );
      expect(edited.make, 'HOWA');
      expect(edited.model, '1500');
      expect(edited.caliber, '.223');
      expect(edited.serialNumber, 'XY753');
      expect(base.make, 'TIKKA');
    });
  });
}