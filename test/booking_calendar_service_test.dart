import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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

    // ── Exhaustive alias hardening (snake_case + huntStart/huntEnd) ──

    test('resolves snake_case availability_start / availability_end', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'availability_start': '2026-09-14',
        'availability_end': '2026-09-17',
      });
      expect(window!.start, DateTime(2026, 9, 14));
      expect(window.end, DateTime(2026, 9, 18));
    });

    test('resolves snake_case start_date / end_date', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'start_date': '2026-10-01',
        'end_date': '2026-10-03',
      });
      expect(window!.start, DateTime(2026, 10, 1));
      expect(window.end, DateTime(2026, 10, 4));
    });

    test('resolves snake_case check_in_date / check_out_date', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'check_in_date': '2026-11-05',
        'check_out_date': '2026-11-08',
      });
      expect(window!.start, DateTime(2026, 11, 5));
      expect(window.end, DateTime(2026, 11, 9));
    });

    test('resolves huntStart / huntEnd (camelCase)', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'huntStart': '2026-12-10',
        'huntEnd': '2026-12-12',
      });
      expect(window!.start, DateTime(2026, 12, 10));
      expect(window.end, DateTime(2026, 12, 13));
    });

    test('resolves snake_case hunt_start / hunt_end', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'hunt_start': '2026-12-10',
        'hunt_end': '2026-12-12',
      });
      expect(window!.start, DateTime(2026, 12, 10));
      expect(window.end, DateTime(2026, 12, 13));
    });

    test('resolves snake_case confirmed_start_date / confirmed_end_date', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'confirmed_start_date': '2026-09-14',
        'confirmed_end_date': '2026-09-17',
      });
      expect(window!.start, DateTime(2026, 9, 14));
      expect(window.end, DateTime(2026, 9, 18));
    });

    test('camelCase wins over snake_case when both are present '
        '(priority + canonical-key match)', () {
      // availabilityStart (camelCase) appears earlier in the alias list than
      // availability_start, and is the canonical key the app writes.
      final window = BookingCalendarEventBuilder.resolveWindow({
        'availabilityStart': '2026-09-14', // canonical
        'availability_start': '2026-01-01', // snake_case -- must NOT win
      });
      expect(window!.start, DateTime(2026, 9, 14));
    });

    test('start aliases priority order: confirmedStartDate > checkInDate > '
        'availabilityStart > startDate > huntStart > huntDate', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'confirmedStartDate': '2026-09-14',
        'checkInDate': '2026-10-01',
        'availabilityStart': '2026-08-01',
        'startDate': '2026-07-01',
        'huntStart': '2026-06-01',
        'huntDate': '2026-05-01',
      });
      expect(window!.start, DateTime(2026, 9, 14)); // confirmedStartDate wins
    });

    test('single-day window when a start resolves but no end alias matches '
        '(end falls back to start)', () {
      final window = BookingCalendarEventBuilder.resolveWindow({
        'huntStart': '2026-09-20',
        // no end alias present
      });
      expect(window!.start, DateTime(2026, 9, 20));
      expect(window.end, DateTime(2026, 9, 21)); // start + 1 day
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

  // ── Package fallback ────────────────────────────────────────────────────
  //
  // The "Add to Calendar" button's onPressed passes the SAME raw booking map
  // the UI card reads through resolveWindow. When the booking document itself
  // lacks date fields (an older booking that did not copy the package's
  // availability at booking time), the service must fall back to the linked
  // package's `packages/{packageId}` doc and re-resolve the window from the
  // package's availability dates so the calendar action never fails when the
  // UI card is already displaying dates (or could). These tests inject a
  // FakeFirebaseFirestore so the fallback fetch is exercised against a real
  // (fake) `packages` collection.

  group('BookingCalendarService.buildEventWithPackageFallback', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('uses the booking dates directly when the booking has date fields '
        '(no package fetch)', () async {
      // Seed a package that would also resolve -- we assert it is NOT read
      // (the booking's own dates win, matching the UI card).
      await fakeFirestore.collection('packages').doc('pkg-1').set({
        'packageName': 'Package Title',
        'availabilityStart':
            Timestamp.fromDate(DateTime(2026, 1, 1)),
        'availabilityEnd': Timestamp.fromDate(DateTime(2026, 1, 2)),
      });
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = fakeFirestore;
      try {
        final event = await svc.buildEventWithPackageFallback({
          'packageName': 'Booking Title',
          'farmName': 'Farm A',
          'packageId': 'pkg-1',
          'confirmedStartDate': '2026-09-14',
          'confirmedEndDate': '2026-09-17',
        });
        expect(event, isNotNull);
        // Booking title wins over the package title (booking fields take
        // precedence in the merged map).
        expect(event!.title, 'Booking Title @ Farm A');
        expect(event.startDate, DateTime(2026, 9, 14));
        expect(event.endDate, DateTime(2026, 9, 18));
      } finally {
        svc.firestoreForTesting = null;
      }
    });

    test('falls back to the package availability window when the booking has no date fields',
        () async {
      await fakeFirestore.collection('packages').doc('pkg-1').set({
        'packageName': 'Kudu Package',
        'farmName': 'Bosveld Ranch',
        'availabilityStart':
            Timestamp.fromDate(DateTime(2026, 9, 14)),
        'availabilityEnd':
            Timestamp.fromDate(DateTime(2026, 9, 17)),
      });
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = fakeFirestore;
      try {
        final event = await svc.buildEventWithPackageFallback({
          // Booking has NO date fields -- only the package reference.
          'packageId': 'pkg-1',
          'packageName': 'Kudu Package',
          'farmName': 'Bosveld Ranch',
        });
        expect(event, isNotNull,
            reason: 'The package fallback must resolve dates when the booking '
                'doc itself lacks them, so the calendar action never fails '
                'when the UI card could display dates.');
        expect(event!.startDate, DateTime(2026, 9, 14));
        expect(event.endDate, DateTime(2026, 9, 18));
      } finally {
        svc.firestoreForTesting = null;
      }
    });

    test('returns null when the booking has no dates AND no packageId', () async {
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = fakeFirestore;
      try {
        final event = await svc.buildEventWithPackageFallback({
          'packageName': 'No-Dates Booking',
        });
        expect(event, isNull);
      } finally {
        svc.firestoreForTesting = null;
      }
    });

    test('returns null when the booking references a packageId that does not exist',
        () async {
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = fakeFirestore;
      try {
        final event = await svc.buildEventWithPackageFallback({
          'packageId': 'missing-pkg',
          'packageName': 'Ghost Package',
        });
        expect(event, isNull);
      } finally {
        svc.firestoreForTesting = null;
      }
    });

    test('does NOT attempt a fetch for the CUSTOM_BUILT package sentinel',
        () async {
      // Custom-built packages carry 'CUSTOM_BUILT' -- there is no packages
      // doc, so the service must skip the fetch and return null (no dates)
      // rather than 404-ing.
      await fakeFirestore.collection('packages').doc('CUSTOM_BUILT').set({
        'availabilityStart':
            Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = fakeFirestore;
      try {
        final event = await svc.buildEventWithPackageFallback({
          'packageId': 'CUSTOM_BUILT',
          'packageName': 'Custom Trip',
        });
        expect(event, isNull,
            reason: 'CUSTOM_BUILT has no packages doc; the sentinel must '
                'short-circuit the fetch.');
        // Sanity: the CUSTOM_BUILT doc we seeded was NOT read (it would have
        // resolved a window otherwise).
        final seeded =
            await fakeFirestore.collection('packages').doc('CUSTOM_BUILT').get();
        expect(seeded.exists, isTrue);
      } finally {
        svc.firestoreForTesting = null;
      }
    });

    test('tolerates the package_id snake_case alias', () async {
      await fakeFirestore.collection('packages').doc('pkg-2').set({
        'availabilityStart':
            Timestamp.fromDate(DateTime(2026, 9, 20)),
        'availabilityEnd':
            Timestamp.fromDate(DateTime(2026, 9, 20)),
      });
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = fakeFirestore;
      try {
        final event = await svc.buildEventWithPackageFallback({
          'package_id': 'pkg-2', // snake_case alias
          'packageName': 'Alias Package',
        });
        expect(event, isNotNull);
        expect(event!.startDate, DateTime(2026, 9, 20));
        expect(event.endDate, DateTime(2026, 9, 21));
      } finally {
        svc.firestoreForTesting = null;
      }
    });

    test('package fallback does NOT fire when the booking has a start date '
        '(resolveWindow on the booking alone is non-null -> single-day event '
        'when the booking has no end)', () async {
      // The package fallback only fires when resolveWindow(booking) is null
      // (no resolvable start date on the booking). Here the booking has a
      // confirmedStartDate but no end -> resolveWindow(booking) returns a
      // single-day window (end falls back to start), so the service builds
      // the event from the BOOKING map directly and never reads the package.
      // This matches the UI card, which would also show a single-day event.
      await fakeFirestore.collection('packages').doc('pkg-3').set({
        'packageName': 'PACKAGE_TITLE',
        'farmName': 'PACKAGE_FARM',
        'availabilityStart':
            Timestamp.fromDate(DateTime(2026, 1, 1)),
        'availabilityEnd':
            Timestamp.fromDate(DateTime(2026, 9, 19)),
      });
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = fakeFirestore;
      try {
        final event = await svc.buildEventWithPackageFallback({
          'packageId': 'pkg-3',
          'packageName': 'BOOKING_TITLE',
          'farmName': 'BOOKING_FARM',
          'confirmedStartDate': '2026-09-14',
          // No confirmedEndDate -> booking single-day window (end = start).
        });
        expect(event, isNotNull);
        expect(event!.title, 'BOOKING_TITLE @ BOOKING_FARM');
        expect(event.startDate, DateTime(2026, 9, 14));
        // end = start (2026-09-14) + 1 day = 2026-09-15 -- the package's
        // availabilityEnd is NOT consulted because the booking's own start
        // already resolved a window.
        expect(event.endDate, DateTime(2026, 9, 15));
      } finally {
        svc.firestoreForTesting = null;
      }
    });

    test('a Firestore fetch error does not crash -- returns null', () async {
      // No Firestore app is initialized in the test runner for the global
      // instance, so a service WITHOUT the test seam falls through to
      // FirebaseFirestore.instance which throws [core/no-app]. The catch must
      // swallow it and return null (caller surfaces "no dates").
      final svc = BookingCalendarService.instance
        ..firestoreForTesting = null;
      final event = await svc.buildEventWithPackageFallback({
        'packageId': 'anything',
        'packageName': 'P',
      });
      expect(event, isNull);
    });
  });
}
