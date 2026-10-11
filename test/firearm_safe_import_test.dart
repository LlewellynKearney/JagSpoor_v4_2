import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/firearm_safe/data/models/firearm.dart';
import 'package:jagspoor/features/firearm_safe/data/services/firearm_safe_repository.dart';

void main() {
  group('Firearm model', () {
    test('fromSaps maps the CFR fields + stamps fromSaps + statusDate', () {
      final firearm = Firearm.fromSaps(
        make: 'HOWA',
        calibre: '.338 WIN MAG',
        serial: 'F004574',
        appNo: '10654672',
        type: 'Section 16 Dedicated Hunting',
        status: 'Approved',
        statusDate: '2026/10/09',
        rawPayload: {'status': 'Approved'},
      );

      expect(firearm.make, 'HOWA');
      expect(firearm.calibre, '.338 WIN MAG');
      expect(firearm.serial, 'F004574');
      expect(firearm.appNo, '10654672');
      expect(firearm.type, 'Section 16 Dedicated Hunting');
      expect(firearm.status, 'Approved');
      expect(firearm.fromSaps, isTrue);
      expect(firearm.statusDate, DateTime(2026, 10, 9));
      expect(firearm.rawPayload, isNotNull);
      expect(firearm.hasSerial, isTrue);
    });

    test('fromSaps normalises the portal yyyy/MM/dd status date', () {
      final firearm = Firearm.fromSaps(
        make: 'HOWA',
        calibre: '.338 WIN MAG',
        serial: 'F004574',
        statusDate: '2026/10/09',
      );
      expect(firearm.statusDate, DateTime(2026, 10, 9));
    });

    test('displayName composes make + calibre + serial', () {
      final firearm = Firearm.fromSaps(
        make: 'HOWA',
        calibre: '.338 WIN MAG',
        serial: 'F004574',
      );
      expect(firearm.displayName, 'HOWA .338 WIN MAG (F004574)');
    });

    test('toJson dual-stamps the calibre + serial aliases', () {
      final firearm = Firearm.fromSaps(
        make: 'HOWA',
        calibre: '.338 WIN MAG',
        serial: 'F004574',
      );
      final json = firearm.toJson();
      expect(json['calibre'], '.338 WIN MAG');
      expect(json['caliber'], '.338 WIN MAG');
      expect(json['serial'], 'F004574');
      expect(json['serialNumber'], 'F004574');
      expect(json['fromSaps'], isTrue);
    });

    test('fromJson tolerates the calibre / serial / createdAt aliases', () {
      final firearm = Firearm.fromJson({
        'make': 'HOWA',
        'caliber': '.338 WIN MAG',
        'serialNumber': 'F004574',
        'createdAt': '2026-10-09T00:00:00.000',
      }, id: 'doc-1');
      expect(firearm.id, 'doc-1');
      expect(firearm.calibre, '.338 WIN MAG');
      expect(firearm.serial, 'F004574');
      expect(firearm.addedAt, DateTime(2026, 10, 9));
    });

    test('round-trips through toJson / fromJson', () {
      final firearm = Firearm.fromSaps(
        make: 'HOWA',
        calibre: '.338 WIN MAG',
        serial: 'F004574',
        appNo: '10654672',
        status: 'Approved',
        statusDate: '2026/10/09',
      );
      final restored = Firearm.fromJson(firearm.toJson(), id: 'doc-1');
      expect(restored.make, firearm.make);
      expect(restored.calibre, firearm.calibre);
      expect(restored.serial, firearm.serial);
      expect(restored.appNo, firearm.appNo);
      expect(restored.statusDate, firearm.statusDate);
      expect(restored.fromSaps, isTrue);
    });
  });

  group('FirearmSafeRepository', () {
    test('addFirearm writes an owner-scoped firearms doc', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirearmSafeRepository.forTesting(
        fake,
        uidResolver: () => 'hunter-1',
      );

      final id = await repo.addFirearm(
        Firearm.fromSaps(
          make: 'HOWA',
          calibre: '.338 WIN MAG',
          serial: 'F004574',
          appNo: '10654672',
        ),
      );
      expect(id, isNotNull);

      final doc = await fake.collection('firearms').doc(id).get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['ownerId'], 'hunter-1');
      expect(data['make'], 'HOWA');
      expect(data['calibre'], '.338 WIN MAG');
      expect(data['serial'], 'F004574');
      expect(data['appNo'], '10654672');
      expect(data['fromSaps'], isTrue);
    });

    test('existsBySerial is true after the firearm is added', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirearmSafeRepository.forTesting(
        fake,
        uidResolver: () => 'hunter-1',
      );
      await repo.addFirearm(
        Firearm.fromSaps(make: 'HOWA', calibre: '.338', serial: 'F004574'),
      );

      expect(await repo.existsBySerial('F004574'), isTrue);
      // Case-insensitive + whitespace tolerant.
      expect(await repo.existsBySerial('  f004574 '), isTrue);
      expect(await repo.existsBySerial('ZZZ999'), isFalse);
    });

    test('existsBySerial is false for a blank serial', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirearmSafeRepository.forTesting(
        fake,
        uidResolver: () => 'hunter-1',
      );
      expect(await repo.existsBySerial(''), isFalse);
    });

    test('existsBySerial only matches the signed-in user\'s own firearms',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('firearms').add({
        'ownerId': 'other-hunter',
        'serial': 'F004574',
      });
      final repo = FirearmSafeRepository.forTesting(
        fake,
        uidResolver: () => 'hunter-1',
      );
      expect(await repo.existsBySerial('F004574'), isFalse);
    });

    test('addFirearm rejects an unauthenticated caller (null uid)', () async {
      final fake = FakeFirebaseFirestore();
      final repo = FirearmSafeRepository.forTesting(
        fake,
        uidResolver: () => null,
      );
      expect(
        await repo.addFirearm(
          Firearm.fromSaps(make: 'HOWA', calibre: '.338', serial: 'F004574'),
        ),
        isNull,
      );
    });
  });
}
