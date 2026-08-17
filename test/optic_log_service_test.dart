import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/ballistics/data/models/optic_profile.dart';
import 'package:jagspoor/features/ballistics/data/models/rifle_profile.dart';
import 'package:jagspoor/features/ballistics/data/services/optic_log_service.dart';

void main() {
  // Construct a FakeFirebaseFirestore FIRST, before any test touches
  // `FieldValue.serverTimestamp()` (the `OpticLogEntry.toMap` model test below
  // calls it). fake_cloud_firestore installs its mock `FieldValuePlatform` as
  // a side-effect of construction; if a production `FieldValue` is realised
  // first, the platform binds to `MethodChannelFieldValue` and later fakes
  // throw `type 'MethodChannelFieldValue' is not a subtype of type
  // 'MockFieldValuePlatform'`. Constructing one fake up-front pins the platform
  // for the whole process.
  FakeFirebaseFirestore();

  group('OpticLogEntry', () {
    test('toMap carries userId/firearmId/firearmLabel/optic/savedAt', () {
      final optic = OpticProfile.defaults.copyWith(
        opticName: 'Vortex Razor HD',
        clickValue: 0.1,
      );
      final entry = OpticLogEntry(
        userId: 'uid-1',
        firearmId: 'farm-doc-1',
        firearmLabel: 'Tikka T3x (.308 Win)',
        optic: optic,
        savedAt: DateTime(2026, 8, 17, 9, 30),
      );
      final map = entry.toMap();
      expect(map['userId'], 'uid-1');
      expect(map['firearmId'], 'farm-doc-1');
      expect(map['firearmLabel'], 'Tikka T3x (.308 Win)');
      expect((map['optic'] as Map)['opticName'], 'Vortex Razor HD');
      expect((map['optic'] as Map)['clickValue'], 0.1);
      // savedAt is a server-timestamp placeholder (FieldValue); verify the type
      // is a FieldValue and not a client DateTime so the doc lands with the
      // server's authoritative timestamp.
      expect(map['savedAt'], isA<FieldValue>());
    });

    test('fromMap round-trips all fields', () {
      final savedAt = Timestamp.fromDate(DateTime(2026, 8, 17, 9, 30));
      final entry = OpticLogEntry.fromMap({
        'userId': 'uid-2',
        'firearmId': 'farm-doc-2',
        'firearmLabel': 'Sako S20 (.300 Win Mag)',
        'optic': {
          'opticName': 'Nightforce NX8',
          'clickValue': 0.25,
          'turretUnit': 'moa',
          'focalPlane': 'ffp',
        },
        'savedAt': savedAt,
      }, id: 'log-2');
      expect(entry.id, 'log-2');
      expect(entry.userId, 'uid-2');
      expect(entry.firearmId, 'farm-doc-2');
      expect(entry.firearmLabel, 'Sako S20 (.300 Win Mag)');
      expect(entry.optic.opticName, 'Nightforce NX8');
      expect(entry.optic.clickValue, 0.25);
      expect(entry.savedAt, DateTime(2026, 8, 17, 9, 30));
    });

    test('fromMap tolerates missing optic map (defaults)', () {
      final entry = OpticLogEntry.fromMap({
        'userId': 'uid-3',
        'firearmId': 'farm-doc-3',
      }, id: 'log-3');
      expect(entry.optic, OpticProfile.defaults);
      // missing savedAt -> falls back to "now" (a valid DateTime), not null
      expect(entry.savedAt, isA<DateTime>());
    });

    test('fromMap tolerates missing firearmLabel via legacy alias', () {
      final entry = OpticLogEntry.fromMap({
        'userId': 'uid-4',
        'firearmId': 'farm-doc-4',
        'firearmName': 'Legacy Rifle Label',
      }, id: 'log-4');
      expect(entry.firearmLabel, 'Legacy Rifle Label');
    });

    test('fromMap tolerates empty data map', () {
      final entry = OpticLogEntry.fromMap({}, id: 'log-empty');
      expect(entry.id, 'log-empty');
      expect(entry.userId, '');
      expect(entry.firearmId, '');
      expect(entry.firearmLabel, 'Unknown firearm');
      expect(entry.optic, OpticProfile.defaults);
      expect(entry.savedAt, isA<DateTime>());
    });

    test('fromMap tolerates missing id (null)', () {
      final entry = OpticLogEntry.fromMap({'userId': 'uid-6'});
      expect(entry.id, isNull);
      expect(entry.userId, 'uid-6');
    });

    test('copyWith updates only the supplied fields', () {
      final entry = OpticLogEntry(
        userId: 'uid-5',
        firearmId: 'farm-doc-5',
        firearmLabel: 'Old',
        optic: OpticProfile.defaults,
        savedAt: DateTime(2026, 1, 1),
      );
      final updated = entry.copyWith(
        firearmLabel: 'New',
        optic: OpticProfile.defaults.copyWith(opticName: 'Updated'),
      );
      expect(updated.userId, 'uid-5');
      expect(updated.firearmId, 'farm-doc-5');
      expect(updated.firearmLabel, 'New');
      expect(updated.optic.opticName, 'Updated');
      expect(updated.savedAt, DateTime(2026, 1, 1));
    });
  });

  group('firearmLabelForOpticLog', () {
    test('uses RifleProfile.displayName', () {
      final rifle = RifleProfile(
        id: 'r1',
        name: '',
        caliber: '.308 Win',
        make: 'Tikka',
        model: 'T3x',
      );
      expect(firearmLabelForOpticLog(rifle), 'Tikka T3x (.308 Win)');
    });

    test('null rifle -> Unknown firearm', () {
      expect(firearmLabelForOpticLog(null), 'Unknown firearm');
    });

    test('empty make/model falls back to name then Unnamed firearm', () {
      final rifle = RifleProfile(id: 'r2', name: '', caliber: '');
      final label = firearmLabelForOpticLog(rifle);
      expect(label, 'Unnamed firearm (—)');
    });
  });

  // Regression for "Optic History showing empty after save". Two contracts:
  //  1. A log written by `logSave` (collection `optic_logs`, field `userId`
  //     == the caller's uid) must be returned by `getMyOpticLogsStream`
  //     (same collection, same `userId` filter) -- i.e. the save path and the
  //     query path use the SAME collection + user identifier, so a saved log
  //     is never dropped by a field/path mismatch.
  //  2. The query stream is wrapped in `OfflineStreamGuard.offlineResilient`,
  //     so a hard error emits the fallback `[]` AND completes (the old
  //     `.handleError` swallowed errors and never emitted -> the history
  //     hung on a spinner / appeared empty).
  group('OpticLogService.getMyOpticLogsStream (save <-> query alignment)', () {
    test('null uid -> empty stream (renders empty state, no throw)', () async {
      final service = OpticLogService.forTesting(
        firestore: FakeFirebaseFirestore(),
        currentUserIdResolver: () => null,
      );

      final result = await service.getMyOpticLogsStream().first;
      expect(result, const <OpticLogEntry>[]);
    });

    test('a log written by logSave is returned by getMyOpticLogsStream (same collection + userId)', () async {
      final fake = FakeFirebaseFirestore();
      const uid = 'user-123';
      final service = OpticLogService.forTesting(
        firestore: fake,
        currentUserIdResolver: () => uid,
      );

      // Write an audit entry exactly as the Optical Suite does on Save Optic.
      await service.logSave(
        firearmId: 'rifle-1',
        firearmLabel: 'Tikka T3x (.308 Win)',
        optic: OpticProfile.defaults.copyWith(opticName: 'Vortex Razor HD'),
      );

      // The history screen subscribes to this stream. It must surface the
      // just-saved entry -- proving the save path (optic_logs / userId: uid)
      // and the query path (optic_logs.where(userId == uid)) are aligned.
      final entries = await service.getMyOpticLogsStream().first;

      expect(entries, hasLength(1));
      expect(entries.first.userId, uid);
      expect(entries.first.firearmId, 'rifle-1');
      expect(entries.first.firearmLabel, 'Tikka T3x (.308 Win)');
      expect(entries.first.optic.opticName, 'Vortex Razor HD');
    });

    test('only the active user\'s logs are returned (owner-scoped, no cross-user leak)', () async {
      final fake = FakeFirebaseFirestore();
      // Seed a doc owned by a DIFFERENT user directly into the fake.
      await fake.collection('optic_logs').add({
        'userId': 'other-user',
        'firearmId': 'rifle-x',
        'firearmLabel': 'Other',
        'optic': OpticProfile.defaults.toJson(),
        'savedAt': Timestamp.now(),
      });
      // And one owned by the active user via logSave.
      final service = OpticLogService.forTesting(
        firestore: fake,
        currentUserIdResolver: () => 'me',
      );
      await service.logSave(
        firearmId: 'rifle-mine',
        firearmLabel: 'Mine',
        optic: OpticProfile.defaults,
      );

      final entries = await service.getMyOpticLogsStream().first;
      expect(entries, hasLength(1));
      expect(entries.first.userId, 'me');
      expect(entries.first.firearmId, 'rifle-mine');
    });

    test('returns logs sorted newest-first (client-side, no server orderBy)', () async {
      final fake = FakeFirebaseFirestore();
      final service = OpticLogService.forTesting(
        firestore: fake,
        currentUserIdResolver: () => 'u1',
      );

      // Seed three logs with controlled savedAt timestamps in NON-sorted
      // insertion order (middle, oldest, newest) directly into the fake so
      // the snapshot returns them in insertion order -- proving the
      // client-side sort (not the server) produces newest-first ordering.
      final base = DateTime(2026, 1, 1);
      await fake.collection('optic_logs').add({
        'userId': 'u1',
        'firearmId': 'r1',
        'firearmLabel': 'Mid',
        'optic': OpticProfile.defaults.toJson(),
        'savedAt': Timestamp.fromDate(base.add(const Duration(days: 5))),
      });
      await fake.collection('optic_logs').add({
        'userId': 'u1',
        'firearmId': 'r2',
        'firearmLabel': 'Oldest',
        'optic': OpticProfile.defaults.toJson(),
        'savedAt': Timestamp.fromDate(base),
      });
      await fake.collection('optic_logs').add({
        'userId': 'u1',
        'firearmId': 'r3',
        'firearmLabel': 'Newest',
        'optic': OpticProfile.defaults.toJson(),
        'savedAt': Timestamp.fromDate(base.add(const Duration(days: 10))),
      });

      final entries = await service.getMyOpticLogsStream().first;
      expect(entries, hasLength(3));
      // Newest first.
      expect(entries.map((e) => e.firearmLabel).toList(),
          ['Newest', 'Mid', 'Oldest']);
    });
  });
}
