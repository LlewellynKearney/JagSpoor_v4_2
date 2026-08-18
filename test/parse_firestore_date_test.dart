// ============================================================================
// Safe Firestore Timestamp -> DateTime parsing — Unit Tests
//
// Validates `parseFirestoreDate` (lib/features/hunter_mode/models/
// package_pricing.dart) and the model `fromMap` round-trips that consume it
// (PackagePricing.fromMap + DateChangeRequest.fromMap), so the four
// package/booking date fields (availabilityStart, availabilityEnd, startDate,
// endDate) are safely deserialized whether they arrive as a Firestore
// `Timestamp`, an ISO `String`, a `DateTime`, or a `num`
// (milliseconds-since-epoch).
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/package_pricing.dart';

void main() {
  const startDateStr = '2026-08-21T00:00:00.000';
  const endDateStr = '2026-08-23T00:00:00.000';

  group('parseFirestoreDate (safe Timestamp -> DateTime conversion)', () {
    test('returns null for null', () {
      expect(parseFirestoreDate(null), isNull);
    });

    test('converts a Firestore Timestamp', () {
      final ts = Timestamp.fromDate(DateTime(2026, 8, 21, 5, 30));
      final result = parseFirestoreDate(ts);
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 8);
      expect(result.day, 21);
    });

    test('passes a DateTime through unchanged', () {
      final dt = DateTime(2026, 8, 21, 5, 30);
      expect(parseFirestoreDate(dt), dt);
    });

    test('parses an ISO-8601 string', () {
      final result = parseFirestoreDate(startDateStr);
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 8);
      expect(result.day, 21);
    });

    test('returns null for an unparseable string', () {
      expect(parseFirestoreDate('not-a-date'), isNull);
    });

    test('returns null for an empty string', () {
      expect(parseFirestoreDate(''), isNull);
    });

    test('converts a num (milliseconds-since-epoch, UTC)', () {
      final ms = DateTime.utc(2026, 8, 21).millisecondsSinceEpoch;
      final result = parseFirestoreDate(ms);
      expect(result, isNotNull);
      expect(result!.toUtc().year, 2026);
      expect(result.toUtc().month, 8);
      expect(result.toUtc().day, 21);
    });

    test('converts a double num (truncated to ms)', () {
      final ms = DateTime.utc(2026, 8, 23).millisecondsSinceEpoch;
      final result = parseFirestoreDate(ms.toDouble());
      expect(result, isNotNull);
      expect(result!.toUtc().day, 23);
    });

    test('returns null for an unsupported type (e.g. a List)', () {
      expect(parseFirestoreDate([2026, 8, 21]), isNull);
    });

    test('returns null for a bool', () {
      expect(parseFirestoreDate(true), isNull);
    });
  });

  group('PackagePricing.fromMap date round-trip (all input shapes)', () {
    PackagePricing roundTripAvailability(dynamic start, dynamic end) {
      final pricing = PackagePricing.fromMap({
        'mode': 'allInclusive',
        'allInclusivePrice': 5000.0,
        'availabilityStart': start,
        'availabilityEnd': end,
      });
      return pricing;
    }

    test('deserializes availabilityStart/End from Firestore Timestamp', () {
      final pricing = roundTripAvailability(
        Timestamp.fromDate(DateTime(2026, 8, 21)),
        Timestamp.fromDate(DateTime(2026, 8, 23)),
      );
      expect(pricing.availabilityStart, isNotNull);
      expect(pricing.availabilityStart!.year, 2026);
      expect(pricing.availabilityStart!.month, 8);
      expect(pricing.availabilityStart!.day, 21);
      expect(pricing.availabilityEnd!.day, 23);
    });

    test('deserializes availabilityStart/End from ISO strings', () {
      final pricing = roundTripAvailability(startDateStr, endDateStr);
      expect(pricing.availabilityStart!.day, 21);
      expect(pricing.availabilityEnd!.day, 23);
    });

    test('deserializes availabilityStart/End from DateTime', () {
      final pricing = roundTripAvailability(
        DateTime(2026, 8, 21),
        DateTime(2026, 8, 23),
      );
      expect(pricing.availabilityStart!.day, 21);
      expect(pricing.availabilityEnd!.day, 23);
    });

    test('tolerates a null availabilityStart (single-side availability)', () {
      final pricing = roundTripAvailability(null, Timestamp.fromDate(
          DateTime(2026, 8, 23)));
      expect(pricing.availabilityStart, isNull);
      expect(pricing.availabilityEnd, isNotNull);
      expect(pricing.availabilityEnd!.day, 23);
    });

    test('tolerates a null availabilityEnd', () {
      final pricing = roundTripAvailability(
          Timestamp.fromDate(DateTime(2026, 8, 21)), null);
      expect(pricing.availabilityStart, isNotNull);
      expect(pricing.availabilityEnd, isNull);
    });

    test('tolerates both dates null (no availability window)', () {
      final pricing = roundTripAvailability(null, null);
      expect(pricing.availabilityStart, isNull);
      expect(pricing.availabilityEnd, isNull);
    });

    test('does not throw on a malformed (unparseable) date string', () {
      final pricing = roundTripAvailability('garbage', 'also-garbage');
      expect(pricing.availabilityStart, isNull);
      expect(pricing.availabilityEnd, isNull);
    });
  });

  group('DateChangeRequest.fromMap date round-trip (all input shapes)', () {
    DateChangeRequest roundTrip(dynamic start, dynamic end, dynamic at) {
      return DateChangeRequest.fromMap({
        'reason': 'schedule conflict',
        'status': 'pending',
        'requestedStartDate': start,
        'requestedEndDate': end,
        'requestedAt': at,
      });
    }

    test('deserializes from Firestore Timestamps', () {
      final req = roundTrip(
        Timestamp.fromDate(DateTime(2026, 9, 1)),
        Timestamp.fromDate(DateTime(2026, 9, 3)),
        Timestamp.fromDate(DateTime(2026, 8, 18)),
      );
      expect(req.requestedStartDate!.day, 1);
      expect(req.requestedEndDate!.day, 3);
      expect(req.requestedAt!.day, 18);
      expect(req.reason, 'schedule conflict');
      expect(req.status, 'pending');
    });

    test('deserializes from ISO strings', () {
      final req = roundTrip(
        '2026-09-01T00:00:00.000',
        '2026-09-03T00:00:00.000',
        '2026-08-18T00:00:00.000',
      );
      expect(req.requestedStartDate!.day, 1);
      expect(req.requestedEndDate!.day, 3);
      expect(req.requestedAt!.day, 18);
    });

    test('tolerates null dates (no start/end/at)', () {
      final req = roundTrip(null, null, null);
      expect(req.requestedStartDate, isNull);
      expect(req.requestedEndDate, isNull);
      expect(req.requestedAt, isNull);
    });

    test('defaults status to pending when missing', () {
      final req = DateChangeRequest.fromMap({'reason': 'x'});
      expect(req.status, 'pending');
    });

    test('does not throw on malformed date strings', () {
      final req = roundTrip('bad', 'bad', 'bad');
      expect(req.requestedStartDate, isNull);
      expect(req.requestedEndDate, isNull);
      expect(req.requestedAt, isNull);
    });
  });
}
