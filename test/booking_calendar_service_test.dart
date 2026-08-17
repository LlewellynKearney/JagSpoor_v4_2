import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/booking_calendar_service.dart';

/// Unit tests for the pure [BookingCalendarEventBuilder] -- the date
/// resolution + event construction logic that powers the "Add Hunt to
/// Calendar" action surfaced to both hunter and outfitter once a booking
/// transitions to Confirmed.
///
/// The builder is pure (no Flutter / platform plugins), so every assertion
/// runs deterministically on the desktop test runner without a live device
/// calendar. The Firestore [Timestamp] path is exercised via the real
/// `cloud_firestore` [Timestamp] constructor (no emulator needed -- it is a
/// pure value type).
void main() {
  group('BookingCalendarEventBuilder.resolveDate', () {
    test('parses a Firestore Timestamp', () {
      final ts = Timestamp.fromDate(DateTime(2026, 9, 14, 6, 30));
      final resolved = BookingCalendarEventBuilder.resolveDate(ts);
      expect(resolved, DateTime(2026, 9, 14));
    });

    test('parses a plain YYYY-MM-DD string (no time / tz)', () {
      final resolved = BookingCalendarEventBuilder.resolveDate('2026-09-14');
      expect(resolved, DateTime(2026, 9, 14));
    });

    test('parses a full ISO-8601 timestamp down to midnight', () {
      final resolved = BookingCalendarEventBuilder.resolveDate(
        '2026-09-14T06:30:00Z',
      );
      // DateTime.tryParse parses to UTC; we collapse to Y/M/D in local terms.
      expect(resolved?.year, 2026);
      expect(resolved?.month, 9);
      expect(resolved?.day, 14);
    });

    test('trims whitespace before parsing', () {
      final resolved = BookingCalendarEventBuilder.resolveDate('  2026-09-14  ');
      expect(resolved, DateTime(2026, 9, 14));
    });

    test('returns null for empty / blank string', () {
      expect(BookingCalendarEventBuilder.resolveDate(''), isNull);
      expect(BookingCalendarEventBuilder.resolveDate('   '), isNull);
    });

    test('returns null for garbage / unparseable input', () {
      expect(BookingCalendarEventBuilder.resolveDate('not-a-date'), isNull);
    });

    test('returns null for null input', () {
      expect(BookingCalendarEventBuilder.resolveDate(null), isNull);
    });

    test('collapses a DateTime to midnight (drops time)', () {
      final resolved = BookingCalendarEventBuilder.resolveDate(
        DateTime(2026, 9, 14, 18, 45),
      );
      expect(resolved, DateTime(2026, 9, 14));
    });

    test('parses a num as milliseconds-since-epoch', () {
      final ms = DateTime(2026, 9, 14).millisecondsSinceEpoch;
      final resolved = BookingCalendarEventBuilder.resolveDate(ms);
      expect(resolved, DateTime(2026, 9, 14));
    });
  });

  group('BookingCalendarEventBuilder.resolveWindow', () {
    test('prefers confirmedStartDate over other aliases', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'confirmedStartDate': '2026-09-14',
        'checkInDate': '2026-10-01',
        'availabilityStart': '2026-08-01',
        'startDate': '2026-07-01',
        'huntDate': '2026-06-01',
        'confirmedEndDate': '2026-09-17',
      });
      expect(window, isNotNull);
      expect(window!.start, DateTime(2026, 9, 14));
      // end is the day AFTER the final hunt day (all-day inclusive).
      expect(window.end, DateTime(2026, 9, 18));
    });

    test('falls back to checkInDate when confirmedStartDate absent', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'checkInDate': '2026-10-01',
        'checkOutDate': '2026-10-05',
      });
      expect(window!.start, DateTime(2026, 10, 1));
      expect(window.end, DateTime(2026, 10, 6));
    });

    test('falls back to availabilityStart/End', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'availabilityStart': DateTime(2026, 11, 1),
        'availabilityEnd': DateTime(2026, 11, 3),
      });
      expect(window!.start, DateTime(2026, 11, 1));
      expect(window.end, DateTime(2026, 11, 4));
    });

    test('falls back to startDate / endDate', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'startDate': '2026-12-10',
        'endDate': '2026-12-12',
      });
      expect(window!.start, DateTime(2026, 12, 10));
      expect(window.end, DateTime(2026, 12, 13));
    });

    test('falls back to huntDate with no end (single-day window)', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'huntDate': '2026-09-20',
      });
      expect(window!.start, DateTime(2026, 9, 20));
      // end falls back to start, then +1 day -> single all-day event.
      expect(window.end, DateTime(2026, 9, 21));
    });

    test('returns null when no start date can be resolved', () {
      expect(BookingCalendarEventBuilder.resolveWindow({}), isNull);
      expect(
        BookingCalendarEventBuilder.resolveWindow({'packageName': 'P'}),
        isNull,
      );
    });

    test('clamps an end-before-start to a single-day window', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'confirmedStartDate': '2026-09-14',
        'confirmedEndDate': '2026-09-10', // before start
      });
      expect(window!.start, DateTime(2026, 9, 14));
      // end clamped to start, then +1 day.
      expect(window.end, DateTime(2026, 9, 15));
    });

    test('handles Firestore Timestamp values', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'confirmedStartDate': Timestamp.fromDate(DateTime(2026, 9, 14, 12)),
        'confirmedEndDate': Timestamp.fromDate(DateTime(2026, 9, 16, 12)),
      });
      expect(window!.start, DateTime(2026, 9, 14));
      expect(window.end, DateTime(2026, 9, 17));
    });
  });

  group('BookingCalendarEventBuilder.buildTitle', () {
    test('combines package name + farm name', () {
      expect(
        BookingCalendarEventBuilder.buildTitle({
          'packageName': 'Kudu Trophy Package',
          'farmName': 'Bosveld Ranch',
        }),
        'Kudu Trophy Package @ Bosveld Ranch',
      );
    });

    test('uses package name alone when farm absent', () {
      expect(
        BookingCalendarEventBuilder.buildTitle({'packageName': 'Springbok Hunt'}),
        'Springbok Hunt',
      );
    });

    test('defaults to "JagSpoor Hunt" when package name absent', () {
      expect(
        BookingCalendarEventBuilder.buildTitle({'farmName': 'Bosveld Ranch'}),
        'JagSpoor Hunt @ Bosveld Ranch',
      );
      expect(
        BookingCalendarEventBuilder.buildTitle({}),
        'JagSpoor Hunt',
      );
    });

    test('ignores blank/whitespace package + farm names', () {
      expect(
        BookingCalendarEventBuilder.buildTitle({
          'packageName': '   ',
          'farmName': '  ',
        }),
        'JagSpoor Hunt',
      );
    });
  });

  group('BookingCalendarEventBuilder.buildDescription', () {
    test('includes all populated fields', () {
      final desc = BookingCalendarEventBuilder.buildDescription({
        'packageName': 'Kudu Package',
        'farmName': 'Bosveld',
        'outfitterName': 'Bushveld Outfitters',
        'hunterName': 'J. Smith',
        'totalHunterPriceRands': 12500,
        'id': 'BK12345',
      });
      expect(desc, contains('Hunting trip booked via JagSpoor.'));
      expect(desc, contains('Package: Kudu Package'));
      expect(desc, contains('Farm: Bosveld'));
      expect(desc, contains('Outfitter: Bushveld Outfitters'));
      expect(desc, contains('Hunter: J. Smith'));
      expect(desc, contains('Total: R 12500.00'));
      expect(desc, contains('Booking ID: BK12345'));
    });

    test('falls back to basePriceRands when total absent', () {
      final desc = BookingCalendarEventBuilder.buildDescription({
        'basePriceRands': 9000,
      });
      expect(desc, contains('Total: R 9000.00'));
    });

    test('omits total when zero / absent', () {
      final desc = BookingCalendarEventBuilder.buildDescription({
        'packageName': 'P',
      });
      expect(desc, isNot(contains('Total:')));
      expect(desc, isNot(contains('Booking ID:')));
    });

    test('uses outfitterBusinessName alias when outfitterName absent', () {
      final desc = BookingCalendarEventBuilder.buildDescription({
        'outfitterBusinessName': 'Savanna Safaris',
      });
      expect(desc, contains('Outfitter: Savanna Safaris'));
    });

    test('uses bookingId alias when id absent', () {
      final desc = BookingCalendarEventBuilder.buildDescription({
        'bookingId': 'BK-XYZ',
      });
      expect(desc, contains('Booking ID: BK-XYZ'));
    });

    test('omits blank/whitespace values', () {
      final desc = BookingCalendarEventBuilder.buildDescription({
        'packageName': '  ',
        'farmName': '  ',
        'hunterName': '  ',
      });
      expect(desc, 'Hunting trip booked via JagSpoor.');
    });
  });

  group('BookingCalendarEventBuilder.buildLocation', () {
    test('returns farm name alone when no region', () {
      expect(
        BookingCalendarEventBuilder.buildLocation({'farmName': 'Bosveld'}),
        'Bosveld',
      );
    });

    test('appends district + province in parentheses', () {
      expect(
        BookingCalendarEventBuilder.buildLocation({
          'farmName': 'Bosveld',
          'district': 'Waterberg',
          'province': 'Limpopo',
        }),
        'Bosveld (Waterberg, Limpopo)',
      );
    });

    test('returns district when farm absent', () {
      expect(
        BookingCalendarEventBuilder.buildLocation({'district': 'Waterberg'}),
        'Waterberg',
      );
    });

    test('returns province when farm + district absent', () {
      expect(
        BookingCalendarEventBuilder.buildLocation({'province': 'Limpopo'}),
        'Limpopo',
      );
    });

    test('returns null when nothing is set', () {
      expect(BookingCalendarEventBuilder.buildLocation({}), isNull);
    });
  });

  group('BookingCalendarEventBuilder.buildEvent', () {
    test('returns null when no window can be resolved', () {
      expect(
        BookingCalendarEventBuilder.buildEvent({'packageName': 'P'}),
        isNull,
      );
    });

    test('builds a fully-populated all-day Event', () {
      final event = BookingCalendarEventBuilder.buildEvent({
        'packageName': 'Kudu Trophy Package',
        'farmName': 'Bosveld Ranch',
        'district': 'Waterberg',
        'province': 'Limpopo',
        'confirmedStartDate': '2026-09-14',
        'confirmedEndDate': '2026-09-17',
        'outfitterName': 'Bushveld Outfitters',
        'totalHunterPriceRands': 12500,
        'id': 'BK12345',
      });
      expect(event, isNotNull);
      expect(event!.title, 'Kudu Trophy Package @ Bosveld Ranch');
      expect(event.location, 'Bosveld Ranch (Waterberg, Limpopo)');
      expect(event.allDay, isTrue);
      expect(event.startDate, DateTime(2026, 9, 14));
      expect(event.endDate, DateTime(2026, 9, 18));
      expect(event.description, contains('Package: Kudu Trophy Package'));
      expect(event.description, contains('Total: R 12500.00'));
      expect(event.iosParams.reminder, const Duration(hours: 12));
    });
  });

  group('BookingCalendarService.buildEvent', () {
    test('delegates to the pure builder', () {
      final event = BookingCalendarService.instance.buildEvent({
        'packageName': 'Springbok Hunt',
        'confirmedStartDate': '2026-09-20',
      });
      expect(event, isNotNull);
      expect(event!.title, 'Springbok Hunt');
      expect(event.startDate, DateTime(2026, 9, 20));
      expect(event.endDate, DateTime(2026, 9, 21));
    });

    test('returns null for a booking with no dates', () {
      expect(
        BookingCalendarService.instance.buildEvent({'packageName': 'P'}),
        isNull,
      );
    });
  });
}
