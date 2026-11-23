import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Phase 2 repository contract tests.
///
/// No real Firebase is touched: the ownership guard, the path builders and
/// the write-payload rule are pure, and the one Firestore-dependent path is
/// asserted to fail loudly (never silently) when Firestore is unavailable.
void main() {
  Camp buildCamp({
    String id = 'camp-1',
    String farmId = 'farm-1',
    double? lat,
    double? lng,
  }) {
    return Camp(
      id: id,
      farmId: farmId,
      name: 'North Camp',
      totalSizeHa: 1200,
      province: 'Limpopo',
      district: 'Waterberg',
      nearestTown: 'Lephalale',
      lat: lat,
      lng: lng,
      locationAccuracyM: lat == null ? null : 8.5,
      locationUpdatedAt: lat == null ? null : DateTime(2026, 11, 20, 9, 15),
      locationSource:
          lat == null ? Camp.locationSourceManual : Camp.locationSourceGps,
      veldType: 'Sweetveld',
      veldCondition: Camp.veldConditionFair,
      deptNormHaPerLsu: 12,
      rainfallMmPerYear: 480,
      notes: 'North camp',
      createdAt: DateTime(2026, 1, 15, 10, 30),
      updatedAt: DateTime(2026, 2, 1, 8, 0),
    );
  }

  group('requireOwnership guard', () {
    test('accepts the signed-in uid', () {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      expect(() => repo.requireOwnership('uid-1'), returnsNormally);
    });

    test('rejects a different outfitter uid', () {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      expect(
        () => repo.requireOwnership('uid-2'),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });

    test('rejects when no user is signed in', () {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => null,
      );
      expect(
        () => repo.requireOwnership('uid-1'),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });

    test('rejects an empty signed-in uid', () {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => '',
      );
      expect(
        () => repo.requireOwnership(''),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });
  });

  group('storage paths', () {
    test('camps live under users/{uid}/farms/{farmId}/veldCamps', () {
      expect(
        VeldCarryRepository.campPath('uid-1', 'farm-1', 'camp-1'),
        'users/uid-1/farms/farm-1/veldCamps/camp-1',
      );
    });

    test('camp children hang off the camp document', () {
      final camp = VeldCarryRepository.campPath('uid-1', 'farm-1', 'camp-1');
      expect(
        VeldCarryRepository.stockPath('uid-1', 'farm-1', 'camp-1', 'kudu'),
        '$camp/stock/kudu',
      );
      expect(
        VeldCarryRepository.plantedAreaPath('uid-1', 'farm-1', 'camp-1', 'a1'),
        '$camp/plantedAreas/a1',
      );
      expect(
        VeldCarryRepository.predatorPath('uid-1', 'farm-1', 'camp-1', 'p1'),
        '$camp/predators/p1',
      );
    });

    test('permits are farm-wide, not camp-scoped', () {
      expect(
        VeldCarryRepository.permitPath('uid-1', 'farm-1', 'permit-1'),
        'users/uid-1/farms/farm-1/permits/permit-1',
      );
    });

    test('no new top-level collection is introduced', () {
      expect(VeldCarryRepository.usersCollection, 'users');
      expect(VeldCarryRepository.farmsCollection, 'farms');
      expect(VeldCarryRepository.campsCollection, 'veldCamps');
      expect(
        VeldCarryRepository.campPath('uid-1', 'farm-1', 'camp-1'),
        startsWith('users/uid-1/farms/farm-1/'),
      );
    });
  });

  group('write payload (updatedAt now, createdAt only when new)', () {
    final now = DateTime(2026, 11, 23, 6, 30);

    test('new document keeps createdAt and stamps updatedAt', () {
      final base = buildCamp().toMap();
      final payload = VeldCarryRepository.buildUpsertPayload(
        base: base,
        isNew: true,
        now: now,
      );
      expect(payload.containsKey('createdAt'), isTrue);
      expect(payload['updatedAt'], isA<Timestamp>());
      expect(
        (payload['updatedAt'] as Timestamp).toDate(),
        now,
      );
    });

    test('existing document drops createdAt so edits never move it', () {
      final base = buildCamp().toMap();
      final payload = VeldCarryRepository.buildUpsertPayload(
        base: base,
        isNew: false,
        now: now,
      );
      expect(payload.containsKey('createdAt'), isFalse);
      expect(payload['updatedAt'], isA<Timestamp>());
      expect((payload['updatedAt'] as Timestamp).toDate(), now);
    });

    test('the base map is not mutated', () {
      final base = buildCamp().toMap();
      final before = Map<String, dynamic>.from(base);
      VeldCarryRepository.buildUpsertPayload(
        base: base,
        isNew: false,
        now: now,
      );
      expect(base, equals(before));
    });
  });

  group('Camp model round-trip', () {
    test('preserves the internal location fields', () {
      final camp = buildCamp(lat: -23.6667, lng: 27.7);
      final parsed = Camp.fromMap(camp.toMap(), id: camp.id);
      expect(parsed.lat, -23.6667);
      expect(parsed.lng, 27.7);
      expect(parsed.locationAccuracyM, 8.5);
      expect(parsed.locationSource, Camp.locationSourceGps);
      expect(parsed.locationUpdatedAt, camp.locationUpdatedAt);
      expect(parsed, equals(camp));
    });

    test('never writes lat/lng keys when no location is set', () {
      final map = buildCamp().toMap();
      expect(map.containsKey('lat'), isFalse);
      expect(map.containsKey('lng'), isFalse);
      expect(map['locationSource'], Camp.locationSourceManual);
    });

    test('null-safe parsing tolerates string numbers and missing dates', () {
      final parsed = Camp.fromMap({
        'farmId': 'farm-9',
        'name': 'Kalahari Camp',
        'totalSizeHa': '2500.5',
        'province': 'Northern Cape',
        'district': 'Kgalagadi',
        'veldType': 'Kalahari / Thornveld',
        'deptNormHaPerLsu': '33.3',
      }, id: 'camp-9');
      expect(parsed.id, 'camp-9');
      expect(parsed.totalSizeHa, 2500.5);
      expect(parsed.deptNormHaPerLsu, 33.3);
      expect(parsed.veldCondition, Camp.veldConditionGood);
      expect(parsed.lat, isNull);
    });
  });

  group('id generation', () {
    test('produces non-empty unique ids', () {
      final first = VeldCarryRepository.newId();
      final second = VeldCarryRepository.newId();
      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(first, isNot(second));
    });
  });

  group('validation happens before any Firestore call', () {
    test('saveCamp rejects a blank camp id', () async {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      await expectLater(
        repo.saveCamp('uid-1', buildCamp(id: '   ')),
        throwsA(isA<VeldCarryRepositoryException>()),
      );
    });

    test('saveCamp rejects a blank farmId', () async {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      await expectLater(
        repo.saveCamp('uid-1', buildCamp(farmId: '')),
        throwsA(isA<VeldCarryRepositoryException>()),
      );
    });

    test('saveCamp enforces ownership before anything else', () async {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      await expectLater(
        repo.saveCamp('someone-else', buildCamp()),
        throwsA(isA<VeldCarryOwnershipException>()),
      );
    });
  });

  group('Firestore failures are rethrown, never swallowed', () {
    test('getCamps throws when Firestore is unavailable', () async {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      await expectLater(
        repo.getCamps('uid-1', 'farm-1'),
        throwsA(isA<VeldCarryRepositoryException>()),
      );
    });

    test('getPermits throws when Firestore is unavailable', () async {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      await expectLater(
        repo.getPermits('uid-1', 'farm-1'),
        throwsA(isA<VeldCarryRepositoryException>()),
      );
    });

    test('getCamps rejects a blank farmId', () async {
      final repo = VeldCarryRepository.forTesting(
        currentUserIdResolver: () => 'uid-1',
      );
      await expectLater(
        repo.getCamps('uid-1', '  '),
        throwsA(isA<VeldCarryRepositoryException>()),
      );
    });
  });
}
