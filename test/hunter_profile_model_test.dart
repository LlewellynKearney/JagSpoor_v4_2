import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/hunter_profile.dart';

/// Regression tests for the Hunter Profile serialization contract.
///
/// The profile screen writes the `users/{uid}` document map to
/// `SharedPreferences` via `jsonEncode`. Firestore stores `createdAt` /
/// `updatedAt` as [Timestamp] values, which `jsonEncode` cannot encode — the
/// root cause of the
/// "Converting object to an encodable object failed: Instance of 'Timestamp'"
/// crash. These tests lock the fix: every cache/JSON path must be
/// `jsonEncode`-safe, and only the Firestore write path may carry Timestamps.
void main() {
  group('parseTimestamp', () {
    test('null -> null', () {
      expect(parseTimestamp(null), isNull);
    });

    test('Firestore Timestamp -> DateTime', () {
      final local = DateTime(2026, 9, 5, 12, 30);
      final ts = Timestamp.fromDate(local);
      expect(parseTimestamp(ts)!.millisecondsSinceEpoch,
          local.millisecondsSinceEpoch);
    });

    test('DateTime passes through', () {
      final dt = DateTime(2026, 1, 2, 3, 4);
      expect(parseTimestamp(dt), dt);
    });

    test('ISO-8601 string -> DateTime', () {
      expect(
        parseTimestamp('2026-09-05T12:30:00.000Z'),
        DateTime.utc(2026, 9, 5, 12, 30),
      );
    });

    test('epoch int -> DateTime', () {
      final ms = DateTime.utc(2026, 9, 5).millisecondsSinceEpoch;
      expect(parseTimestamp(ms), DateTime.fromMillisecondsSinceEpoch(ms));
    });

    test('unparseable string -> null', () {
      expect(parseTimestamp('not-a-date'), isNull);
    });

    test('unsupported type -> null', () {
      expect(parseTimestamp(<String>['x']), isNull);
      expect(parseTimestamp(true), isNull);
    });
  });

  group('HunterProfile.fromMap', () {
    test('reads firstName / lastName / phoneNumber + timestamps', () {
      final created = DateTime(2026, 1, 1, 8);
      final updated = DateTime(2026, 2, 1, 9);
      final profile = HunterProfile.fromMap({
        'firstName': 'Llewellyn',
        'lastName': 'Kearney',
        'phone': '0845148289',
        'createdAt': Timestamp.fromDate(created),
        'updatedAt': Timestamp.fromDate(updated),
      });
      expect(profile.firstName, 'Llewellyn');
      expect(profile.lastName, 'Kearney');
      expect(profile.phoneNumber, '0845148289');
      expect(profile.createdAt!.millisecondsSinceEpoch,
          created.millisecondsSinceEpoch);
      expect(profile.updatedAt!.millisecondsSinceEpoch,
          updated.millisecondsSinceEpoch);
    });

    test('tolerates the surname / phoneNumber aliases', () {
      final profile = HunterProfile.fromMap({
        'firstName': 'Jane',
        'surname': 'Doe',
        'phoneNumber': '+27820001111',
      });
      expect(profile.lastName, 'Doe');
      expect(profile.phoneNumber, '+27820001111');
    });

    test('splits a legacy fullName into first + last', () {
      final profile = HunterProfile.fromMap({'fullName': 'Jane Doe'});
      expect(profile.firstName, 'Jane');
      expect(profile.lastName, 'Doe');
    });

    test('defaults unit preference + ambient flag', () {
      final profile = HunterProfile.fromMap(const {});
      expect(profile.unitPreference, 'metric');
      expect(profile.darkModeAmbient, isFalse);
      expect(profile.createdAt, isNull);
      expect(profile.updatedAt, isNull);
    });

    test('does not throw on a Timestamp-valued date field', () {
      expect(
        () => HunterProfile.fromMap({
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        }),
        returnsNormally,
      );
    });
  });

  group('HunterProfile.toJson (SharedPreferences cache shape)', () {
    test('contains NO Timestamp and is jsonEncode-safe', () {
      final profile = HunterProfile(
        firstName: 'Llewellyn',
        lastName: 'Kearney',
        phoneNumber: '0845148289',
        unitPreference: 'imperial',
        darkModeAmbient: true,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      final json = profile.toJson();

      // The core regression: jsonEncode must succeed.
      final encoded = jsonEncode(json);
      expect(encoded, contains('Llewellyn'));

      // No value in the map may be a Firestore type.
      for (final value in json.values) {
        expect(value, isNot(isA<Timestamp>()));
        expect(value, isNot(isA<FieldValue>()));
      }

      // Dates are ISO-8601 strings.
      expect(json['createdAt'], DateTime.utc(2026, 1, 1).toIso8601String());
      expect(json['updatedAt'], DateTime.utc(2026, 2, 1).toIso8601String());
      expect(json['unitPreference'], 'imperial');
      expect(json['darkModeAmbient'], isTrue);
    });

    test('omits null dates and round-trips through jsonEncode/fromJson', () {
      final profile = HunterProfile(firstName: 'A', lastName: 'B');
      final decoded = jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>;
      final restored = HunterProfile.fromJson(decoded);
      expect(restored.firstName, 'A');
      expect(restored.lastName, 'B');
      expect(restored.createdAt, isNull);
      expect(restored.updatedAt, isNull);
    });
  });

  group('HunterProfile.toFirestore (Firebase write shape)', () {
    test('encodes dates as Timestamps', () {
      final created = DateTime(2026, 1, 1, 8);
      final profile = HunterProfile(
        firstName: 'A',
        createdAt: created,
        updatedAt: DateTime(2026, 2, 1, 9),
      );
      final map = profile.toFirestore();
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());
      expect((map['createdAt'] as Timestamp).toDate().millisecondsSinceEpoch,
          created.millisecondsSinceEpoch);
    });

    test('uses serverTimestamp for updatedAt when requested', () {
      final map = HunterProfile(firstName: 'A')
          .toFirestore(serverTimestamp: true);
      expect(map['updatedAt'], isA<FieldValue>());
      expect(map.containsKey('createdAt'), isFalse);
    });
  });

  group('encodeProfileCache (raw map safety net)', () {
    test('converts Timestamp values to ISO strings', () {
      final local = DateTime(2026, 1, 1, 8);
      final safe = encodeProfileCache({
        'firstName': 'Llewellyn',
        'createdAt': Timestamp.fromDate(local),
      });
      expect(safe['createdAt'], isA<String>());
      expect(safe['createdAt'], local.toIso8601String());
    });

    test('drops FieldValue sentinels and nested Timestamps', () {
      final local = DateTime(2026, 3, 3, 6);
      final safe = encodeProfileCache({
        'updatedAt': FieldValue.serverTimestamp(),
        'nested': {
          'when': Timestamp.fromDate(local),
        },
      });
      expect(safe['updatedAt'], isNull);
      expect((safe['nested'] as Map)['when'], local.toIso8601String());
    });

    test('the resulting map is jsonEncode-safe (the crash regression)', () {
      // Simulates the exact failing payload: a users/{uid} doc carrying a
      // Timestamp. Before the fix jsonEncode threw; now it must succeed.
      final data = <String, dynamic>{
        'firstName': 'Llewellyn',
        'lastName': 'Kearney',
        'phone': '0845148289',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
      };
      expect(() => jsonEncode(data), throwsA(isA<JsonUnsupportedObjectError>()));
      final encoded = jsonEncode(encodeProfileCache(data));
      expect(encoded, contains('Kearney'));
    });
  });
}
