import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/ballistics/data/models/optic_profile.dart';
import 'package:jagspoor/features/ballistics/data/models/rifle_profile.dart';
import 'package:jagspoor/features/ballistics/data/services/optic_log_service.dart';

void main() {
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
}
