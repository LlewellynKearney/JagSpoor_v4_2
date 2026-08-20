import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/venison_transport_permit.dart';

/// Unit tests for [VenisonTransportPermit] dual-stamping + alias tolerance.
///
/// Locks in the hunter-side visibility fix: a permit doc may carry the
/// designated hunter's uid under `hunterId`, `userId`, or both; the model must
/// resolve all three shapes and always write BOTH aliases back so no consumer
/// (list query, rules check, details sheet) misses the hunter party.
void main() {
  VenisonTransportPermit buildPermit({
    String? hunterId,
    String? userId,
    String outfitterId = 'outfitter-1',
  }) {
    return VenisonTransportPermit(
      permitNumber: 'JSV-2026-0001',
      outfitterId: outfitterId,
      hunterId: hunterId,
      userId: userId,
      hunterName: 'Jan Hunter',
      hunterIdNumber: '9001010000000',
      hunterCell: '0820000000',
      hunterAddress: '1 Bush Rd',
      authorizedPersonName: 'Koos Outfitter',
      farmName: 'Bosveld Ranch',
      farmAddress: 'Farm 12',
      farmCell: '0830000000',
      speciesHuntedAndTransported: const [
        {'species': 'Impala', 'quantity': 2, 'sex': 'Ram'},
      ],
    );
  }

  group('fromMap alias tolerance', () {
    test('reads hunterId when only hunterId is stamped', () {
      final permit = VenisonTransportPermit.fromMap({
        'id': 'p1',
        'outfitterId': 'o1',
        'hunterId': 'hunter-1',
      });
      expect(permit.hunterId, 'hunter-1');
      expect(permit.userId, 'hunter-1'); // back-filled alias
      expect(permit.effectiveHunterId, 'hunter-1');
    });

    test('reads userId when only the legacy userId alias is stamped', () {
      final permit = VenisonTransportPermit.fromMap({
        'id': 'p2',
        'outfitterId': 'o1',
        'userId': 'hunter-2',
      });
      expect(permit.userId, 'hunter-2');
      expect(permit.hunterId, 'hunter-2'); // back-filled alias
      expect(permit.effectiveHunterId, 'hunter-2');
    });

    test('hunterId wins when both aliases are stamped', () {
      final permit = VenisonTransportPermit.fromMap({
        'id': 'p3',
        'outfitterId': 'o1',
        'hunterId': 'hunter-canonical',
        'userId': 'hunter-alias',
      });
      expect(permit.hunterId, 'hunter-canonical');
      expect(permit.userId, 'hunter-alias');
      expect(permit.effectiveHunterId, 'hunter-canonical');
    });

    test('no hunter alias stamped -> both null, effectiveHunterId null', () {
      final permit =
          VenisonTransportPermit.fromMap({'id': 'p4', 'outfitterId': 'o1'});
      expect(permit.hunterId, isNull);
      expect(permit.userId, isNull);
      expect(permit.effectiveHunterId, isNull);
    });

    test('timestamp + species fields still parse', () {
      final now = DateTime(2026, 8, 20, 10, 30);
      final permit = VenisonTransportPermit.fromMap({
        'id': 'p5',
        'outfitterId': 'o1',
        'hunterId': 'h1',
        'createdAt': Timestamp.fromDate(now),
        'speciesHuntedAndTransported': [
          {'species': 'Kudu', 'quantity': 1, 'sex': 'Bull'},
        ],
      });
      expect(permit.createdAt, now);
      expect(permit.speciesSummary, contains('Kudu'));
      expect(permit.speciesSummary, contains('Bull'));
    });
  });

  group('toMap dual-stamping', () {
    test('writes BOTH hunterId and userId aliases when hunterId is set', () {
      final map = buildPermit(hunterId: 'hunter-1').toMap();
      expect(map['hunterId'], 'hunter-1');
      expect(map['userId'], isNull); // no userId field -> not dual-stamped yet
      expect(map.containsKey('userId'), isFalse);
    });

    test('writes both aliases when both are set on the model', () {
      final map =
          buildPermit(hunterId: 'hunter-1', userId: 'hunter-1').toMap();
      expect(map['hunterId'], 'hunter-1');
      expect(map['userId'], 'hunter-1');
    });

    test('writes userId alias when only userId is set (legacy model)', () {
      final map = buildPermit(userId: 'hunter-9').toMap();
      expect(map.containsKey('hunterId'), isFalse);
      expect(map['userId'], 'hunter-9');
    });

    test('omits both aliases when neither is set (unsigned/unlinked permit)',
        () {
      final map = buildPermit().toMap();
      expect(map.containsKey('hunterId'), isFalse);
      expect(map.containsKey('userId'), isFalse);
      expect(map['outfitterId'], 'outfitter-1');
    });

    test('fromMap -> toMap round-trip preserves the dual-stamped aliases', () {
      final permit = buildPermit(hunterId: 'hunter-1', userId: 'hunter-1');
      final roundTripped = VenisonTransportPermit.fromMap({
        ...permit.toMap(),
        'id': 'p6',
      });
      expect(roundTripped.hunterId, 'hunter-1');
      expect(roundTripped.userId, 'hunter-1');
      expect(roundTripped.outfitterId, 'outfitter-1');
    });
  });
}
