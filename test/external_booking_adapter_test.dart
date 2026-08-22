import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/booking_availability_service.dart';
import 'package:jagspoor/services/external_booking_adapter.dart';
import 'package:jagspoor/services/ical_booking_adapter.dart';
import 'package:jagspoor/services/mock_test_booking_adapter.dart';

void main() {
  group('ExternalBookingConfig', () {
    test('manual default round-trips', () {
      const config = ExternalBookingConfig();
      expect(config.systemType, ExternalBookingSystemType.manual);
      expect(config.feedUrl, isEmpty);
      final restored = ExternalBookingConfig.fromMap(config.toMap());
      expect(restored.systemType, ExternalBookingSystemType.manual);
    });

    test('ical config round-trips with feed URL', () {
      const config = ExternalBookingConfig(
        systemType: ExternalBookingSystemType.ical,
        feedUrl: 'https://lodge.example.com/cal.ics',
      );
      final restored = ExternalBookingConfig.fromMap(config.toMap());
      expect(restored.systemType, ExternalBookingSystemType.ical);
      expect(restored.feedUrl, 'https://lodge.example.com/cal.ics');
    });

    test('fromUserDoc reads the bookingSync nested map', () {
      final config = ExternalBookingConfig.fromUserDoc({
        'bookingSync': {'type': 'mock', 'feedUrl': ''},
      });
      expect(config.systemType, ExternalBookingSystemType.mock);
    });

    test('fromUserDoc tolerates a missing bookingSync key', () {
      final config = ExternalBookingConfig.fromUserDoc({'role': 'outfitter'});
      expect(config.systemType, ExternalBookingSystemType.manual);
    });

    test('system type parsing accepts aliases + falls back to manual', () {
      expect(ExternalBookingSystemTypeX.fromString('ical'),
          ExternalBookingSystemType.ical);
      expect(ExternalBookingSystemTypeX.fromString('ICS'),
          ExternalBookingSystemType.ical);
      expect(ExternalBookingSystemTypeX.fromString('mock_test'),
          ExternalBookingSystemType.mock);
      expect(ExternalBookingSystemTypeX.fromString('erp'),
          ExternalBookingSystemType.manual);
      expect(ExternalBookingSystemTypeX.fromString(null),
          ExternalBookingSystemType.manual);
    });
  });

  group('ExternalBookingConfig manual blocked dates', () {
    test('defaults to an empty manual blocked set', () {
      const config = ExternalBookingConfig();
      expect(config.manualBlockedDates, isEmpty);
      expect(
        config.toMap()['manualBlockedDates'],
        isA<List>().having((l) => l.length, 'length', 0),
      );
    });

    test('manual blocked dates round-trip via toMap/fromMap', () {
      final config = ExternalBookingConfig(
        systemType: ExternalBookingSystemType.manual,
        manualBlockedDates: {
          DateTime(2026, 9, 3),
          DateTime(2026, 9, 5),
        },
      );
      final restored = ExternalBookingConfig.fromMap(config.toMap());
      expect(
        restored.manualBlockedDates,
        {DateTime(2026, 9, 3), DateTime(2026, 9, 5)},
      );
    });

    test('toMap serializes manual dates as sorted ISO yyyy-MM-dd keys', () {
      final config = ExternalBookingConfig(
        manualBlockedDates: {
          DateTime(2026, 9, 5),
          DateTime(2026, 9, 3),
        },
      );
      expect(
        config.toMap()['manualBlockedDates'],
        ['2026-09-03', '2026-09-05'],
      );
    });

    test('fromMap tolerates malformed / non-string entries', () {
      final config = ExternalBookingConfig.fromMap({
        'type': 'manual',
        'manualBlockedDates': ['2026-09-03', 'garbage', 42, null],
      });
      expect(config.manualBlockedDates, {DateTime(2026, 9, 3)});
    });

    test('fromMap tolerates a missing manualBlockedDates key', () {
      final config = ExternalBookingConfig.fromMap({'type': 'manual'});
      expect(config.manualBlockedDates, isEmpty);
    });

    test('copyWith carries the manual blocked dates', () {
      final config = ExternalBookingConfig(
        manualBlockedDates: {DateTime(2026, 9, 3)},
      ).copyWith(feedUrl: 'x');
      expect(config.feedUrl, 'x');
      expect(config.manualBlockedDates, {DateTime(2026, 9, 3)});
      // Overriding the set replaces it.
      final replaced = config.copyWith(manualBlockedDates: {DateTime(2026, 1, 1)});
      expect(replaced.manualBlockedDates, {DateTime(2026, 1, 1)});
    });
  });

  group('booking date key helpers', () {
    test('bookingDateKey emits ISO yyyy-MM-dd with zero padding', () {
      expect(bookingDateKey(DateTime(2026, 9, 3)), '2026-09-03');
      expect(bookingDateKey(DateTime(2026, 12, 25)), '2026-12-25');
      // Time-of-day is normalized away.
      expect(bookingDateKey(DateTime(2026, 9, 3, 14, 30)), '2026-09-03');
    });

    test('parseBookingDateKey parses ISO keys to midnight', () {
      expect(parseBookingDateKey('2026-09-03'), DateTime(2026, 9, 3));
      expect(parseBookingDateKey(' 2026-09-03 '), DateTime(2026, 9, 3));
    });

    test('parseBookingDateKey returns null for null / malformed input', () {
      expect(parseBookingDateKey(null), isNull);
      expect(parseBookingDateKey('not-a-date'), isNull);
      expect(parseBookingDateKey(''), isNull);
    });
  });

  group('BookingDateSelection', () {
    test('single-day selection (no end) has dayCount 1', () {
      final sel = BookingDateSelection(start: DateTime(2026, 9, 3));
      expect(sel.start, DateTime(2026, 9, 3));
      expect(sel.end, DateTime(2026, 9, 3));
      expect(sel.dayCount, 1);
    });

    test('range factory orders the endpoints (end >= start)', () {
      final sel = BookingDateSelection.range(
        DateTime(2026, 9, 10),
        DateTime(2026, 9, 5),
      );
      expect(sel.start, DateTime(2026, 9, 5));
      expect(sel.end, DateTime(2026, 9, 10));
      expect(sel.dayCount, 6);
    });

    test('endpoints are normalized to local midnight', () {
      final sel = BookingDateSelection.range(
        DateTime(2026, 9, 5, 14, 30),
        DateTime(2026, 9, 7, 9, 15),
      );
      expect(sel.start, DateTime(2026, 9, 5));
      expect(sel.end, DateTime(2026, 9, 7));
    });

    test('days enumerates the inclusive window', () {
      final sel = BookingDateSelection.range(
        DateTime(2026, 9, 5),
        DateTime(2026, 9, 7),
      );
      expect(sel.days.toList(), [
        DateTime(2026, 9, 5),
        DateTime(2026, 9, 6),
        DateTime(2026, 9, 7),
      ]);
    });

    test('toString renders the ISO window', () {
      final sel = BookingDateSelection.range(
        DateTime(2026, 9, 5),
        DateTime(2026, 9, 7),
      );
      expect(sel.toString(), 'BookingDateSelection(2026-09-05 -> 2026-09-07)');
    });
  });

  group('ExternalBookingAdapters.fromConfig', () {
    test('manual config resolves to no adapter', () {
      expect(
        ExternalBookingAdapters.fromConfig(const ExternalBookingConfig()),
        isNull,
      );
    });

    test('ical config without a feed URL resolves to no adapter', () {
      expect(
        ExternalBookingAdapters.fromConfig(const ExternalBookingConfig(
          systemType: ExternalBookingSystemType.ical,
        )),
        isNull,
      );
    });

    test('ical config with a feed URL builds an ICalBookingAdapter', () {
      final adapter = ExternalBookingAdapters.fromConfig(
        const ExternalBookingConfig(
          systemType: ExternalBookingSystemType.ical,
          feedUrl: 'https://lodge.example.com/cal.ics',
        ),
        fetcher: (url) async => 'BEGIN:VCALENDAR\nEND:VCALENDAR',
      );
      expect(adapter, isA<ICalBookingAdapter>());
    });

    test('mock config builds a deterministic MockTestBookingAdapter', () {
      final adapter = ExternalBookingAdapters.fromConfig(
        const ExternalBookingConfig(
          systemType: ExternalBookingSystemType.mock,
          feedUrl: 'lodge-42',
        ),
      );
      expect(adapter, isA<MockTestBookingAdapter>());
      expect((adapter as MockTestBookingAdapter).seedKey, 'lodge-42');
    });
  });

  group('ICalParser', () {
    const feed = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:booking-1@lodge
DTSTART;VALUE=DATE:20260821
DTEND;VALUE=DATE:20260824
SUMMARY:Booked — van der Merwe hunt
END:VEVENT
BEGIN:VEVENT
UID:booking-2@lodge
DTSTART:20260901T090000
DTEND:20260901T170000
SUMMARY:Day hunt
END:VEVENT
END:VCALENDAR
''';

    test('all-day event blocks DTSTART..DTEND-1 (DTEND exclusive)', () {
      final blocked = ICalParser.parseBlockedDates(feed);
      expect(blocked.contains(DateTime(2026, 8, 21)), isTrue);
      expect(blocked.contains(DateTime(2026, 8, 22)), isTrue);
      expect(blocked.contains(DateTime(2026, 8, 23)), isTrue);
      // RFC 5545: all-day DTEND is exclusive.
      expect(blocked.contains(DateTime(2026, 8, 24)), isFalse);
    });

    test('timed event blocks the calendar day it spans', () {
      final blocked = ICalParser.parseBlockedDates(feed);
      expect(blocked.contains(DateTime(2026, 9, 1)), isTrue);
      expect(blocked.contains(DateTime(2026, 9, 2)), isFalse);
    });

    test('an event with no DTEND blocks its start day only', () {
      const single = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261010
END:VEVENT
END:VCALENDAR
''';
      final blocked = ICalParser.parseBlockedDates(single);
      expect(blocked, {DateTime(2026, 10, 10)});
    });

    test('handles folded (continued) DTSTART lines per RFC 5545', () {
      const folded = 'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'DTSTART;VALUE=DATE:\n'
          ' 20261105\n'
          'DTEND;VALUE=DATE:20261107\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n';
      final blocked = ICalParser.parseBlockedDates(folded);
      expect(blocked.contains(DateTime(2026, 11, 5)), isTrue);
      expect(blocked.contains(DateTime(2026, 11, 6)), isTrue);
      expect(blocked.contains(DateTime(2026, 11, 7)), isFalse);
    });

    test('tolerates UTC (Z) date-times + timezone parameters', () {
      const utc = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART;TZID=Africa/Johannesburg:20261201T080000
DTEND:20261202T160000Z
END:VEVENT
END:VCALENDAR
''';
      final blocked = ICalParser.parseBlockedDates(utc);
      expect(blocked.contains(DateTime(2026, 12, 1)), isTrue);
      expect(blocked.contains(DateTime(2026, 12, 2)), isTrue);
    });

    test('range filter restricts the returned blocked dates', () {
      final blocked = ICalParser.parseBlockedDates(
        feed,
        rangeStart: DateTime(2026, 8, 22),
        rangeEnd: DateTime(2026, 8, 22),
      );
      expect(blocked, {DateTime(2026, 8, 22)});
    });

    test('malformed content yields an empty set (never throws)', () {
      expect(ICalParser.parseBlockedDates('not an ics file'), isEmpty);
      expect(ICalParser.parseBlockedDates(''), isEmpty);
    });
  });

  group('ICalBookingAdapter', () {
    const feed = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART;VALUE=DATE:20260821
DTEND;VALUE=DATE:20260823
END:VEVENT
END:VCALENDAR
''';

    ICalBookingAdapter adapter({
      String body = feed,
      int statusCode = 200,
      bool throwError = false,
      List<Uri>? captured,
    }) {
      return ICalBookingAdapter(
        feedUrl: 'https://lodge.example.com/cal.ics',
        fetcher: (url) async {
          captured?.add(url);
          if (throwError) throw Exception('network down');
          if (statusCode != 200) throw Exception('HTTP $statusCode');
          return body;
        },
      );
    }

    test('systemType is ical', () {
      expect(adapter().systemType, ExternalBookingSystemType.ical);
    });

    test('fetchUnavailableDates returns parsed feed dates in range', () async {
      final blocked = await adapter().fetchUnavailableDates(
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(blocked, {DateTime(2026, 8, 21), DateTime(2026, 8, 22)});
    });

    test('fetchUnavailableDates excludes out-of-range blocked dates', () async {
      final blocked = await adapter().fetchUnavailableDates(
        rangeStart: DateTime(2026, 9, 1),
        rangeEnd: DateTime(2026, 9, 30),
      );
      expect(blocked, isEmpty);
    });

    test('verifySlot is false when any day overlaps a blocked date', () async {
      final ok = await adapter().verifySlot(
        start: DateTime(2026, 8, 20),
        end: DateTime(2026, 8, 21),
      );
      expect(ok, isFalse);
      final free = await adapter().verifySlot(
        start: DateTime(2026, 8, 24),
        end: DateTime(2026, 8, 26),
      );
      expect(free, isTrue);
    });

    test('holdSlot is unsupported on a read-only iCal feed', () async {
      final held = await adapter().holdSlot(
        start: DateTime(2026, 8, 24),
        end: DateTime(2026, 8, 26),
      );
      expect(held, isFalse);
    });

    test('testConnection true for a valid VCALENDAR body', () async {
      expect(await adapter().testConnection(), isTrue);
    });

    test('testConnection false when the body is not a calendar', () async {
      expect(await adapter(body: '<html>oops</html>').testConnection(),
          isFalse);
    });

    test('testConnection false on network failure (no throw)', () async {
      expect(await adapter(throwError: true).testConnection(), isFalse);
    });

    test('the feed is fetched once and cached within the TTL', () async {
      final captured = <Uri>[];
      final a = adapter(captured: captured);
      await a.fetchUnavailableDates(
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      await a.fetchUnavailableDates(
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(captured, hasLength(1));
      expect(captured.single.toString(),
          'https://lodge.example.com/cal.ics');
    });
  });

  group('MockTestBookingAdapter', () {
    test('systemType is mock + testConnection defaults healthy', () async {
      final adapter = MockTestBookingAdapter();
      expect(adapter.systemType, ExternalBookingSystemType.mock);
      expect(await adapter.testConnection(), isTrue);
    });

    test('testConnection reflects the configured health flag', () async {
      expect(
        await MockTestBookingAdapter(connectionHealthy: false)
            .testConnection(),
        isFalse,
      );
    });

    test('explicit blocked dates drive availability exactly', () async {
      final adapter = MockTestBookingAdapter(
        blockedDates: {DateTime(2026, 8, 21), DateTime(2026, 8, 22)},
      );
      final blocked = await adapter.fetchUnavailableDates(
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(blocked, {DateTime(2026, 8, 21), DateTime(2026, 8, 22)});
      expect(
        await adapter.verifySlot(
          start: DateTime(2026, 8, 20),
          end: DateTime(2026, 8, 21),
        ),
        isFalse,
      );
      expect(
        await adapter.verifySlot(
          start: DateTime(2026, 8, 23),
          end: DateTime(2026, 8, 25),
        ),
        isTrue,
      );
    });

    test('deterministic factory yields a stable, reproducible calendar',
        () async {
      final a = MockTestBookingAdapter.deterministic(seedKey: 'lodge-42');
      final b = MockTestBookingAdapter.deterministic(seedKey: 'lodge-42');
      final rangeA = await a.fetchUnavailableDates(
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 9, 30),
      );
      final rangeB = await b.fetchUnavailableDates(
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 9, 30),
      );
      // Same seed -> identical blocked dates (stable hash, not hashCode).
      expect(rangeA, rangeB);
      // The 1-in-5 default pattern blocks a non-empty minority of days.
      expect(rangeA.length, greaterThan(3));
      expect(rangeA.length, lessThan(20));
      // A different seed yields a different calendar.
      final other = await MockTestBookingAdapter.deterministic(
        seedKey: 'other-lodge',
      ).fetchUnavailableDates(
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 9, 30),
      );
      expect(other, isNot(rangeA));
    });

    test('stableHash is run-stable and input-sensitive', () {
      expect(
        MockTestBookingAdapter.stableHash('lodge|2026-08-21'),
        MockTestBookingAdapter.stableHash('lodge|2026-08-21'),
      );
      expect(
        MockTestBookingAdapter.stableHash('lodge|2026-08-21'),
        isNot(MockTestBookingAdapter.stableHash('lodge|2026-08-22')),
      );
    });

    test('holdSlot succeeds on a free slot and then blocks it', () async {
      // Explicit empty block set bypasses the deterministic pattern so the
      // held-slot blocking is exercised in isolation.
      final adapter = MockTestBookingAdapter(blockedDates: {});
      final held = await adapter.holdSlot(
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 22),
        reference: 'booking-1',
      );
      expect(held, isTrue);
      expect(adapter.heldSlots, hasLength(1));
      // The held slot is now unavailable to subsequent calls.
      expect(
        await adapter.verifySlot(
          start: DateTime(2026, 8, 21),
          end: DateTime(2026, 8, 22),
        ),
        isFalse,
      );
      expect(
        await adapter.holdSlot(
          start: DateTime(2026, 8, 21),
          end: DateTime(2026, 8, 22),
        ),
        isFalse,
      );
      expect(adapter.heldSlots, hasLength(1));
    });

    test('holdSlot rejects a slot that overlaps a blocked date', () async {
      final adapter = MockTestBookingAdapter(
        blockedDates: {DateTime(2026, 8, 21)},
      );
      expect(
        await adapter.holdSlot(
          start: DateTime(2026, 8, 21),
          end: DateTime(2026, 8, 21),
        ),
        isFalse,
      );
      expect(adapter.heldSlots, isEmpty);
    });
  });

  group('BookingAvailability model', () {
    test('blockedDates unions the external + local sources', () {
      final availability = BookingAvailability(
        outfitterId: 'outfitter-1',
        externalBlockedDates: {DateTime(2026, 8, 21)},
        localBlockedDates: {DateTime(2026, 8, 22)},
        systemType: ExternalBookingSystemType.manual,
        externalReachable: true,
      );
      expect(
        availability.blockedDates,
        {DateTime(2026, 8, 21), DateTime(2026, 8, 22)},
      );
      expect(availability.isAvailable(DateTime(2026, 8, 21)), isFalse);
      expect(availability.isAvailable(DateTime(2026, 8, 23)), isTrue);
    });
  });
}
