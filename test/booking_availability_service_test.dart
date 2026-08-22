import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/booking_availability_service.dart';
import 'package:jagspoor/services/external_booking_adapter.dart';
import 'package:jagspoor/services/mock_test_booking_adapter.dart';

/// Tests for the merged (local state machine + external ERP) availability
/// resolution that drives the hunter booking flow's date slots.
void main() {
  // Construct a FakeFirebaseFirestore FIRST so the mock FieldValuePlatform
  // binds before any FieldValue.serverTimestamp() is realised.
  FakeFirebaseFirestore();

  BookingAvailabilityService service(
    FirebaseFirestore fake, {
    String? uid,
    ExternalBookingAdapter? Function(ExternalBookingConfig)? adapterFactory,
  }) {
    return BookingAvailabilityService.forTesting(
      firestore: fake,
      currentUserIdResolver: () => uid,
      adapterFactory: adapterFactory,
    );
  }

  Future<void> seedBooking(
    FirebaseFirestore fake, {
    required String outfitterId,
    required String hunterId,
    String status = 'Pending Approval',
    DateTime? start,
    DateTime? end,
  }) async {
    await fake.collection('bookings').add({
      'outfitterId': outfitterId,
      'hunterId': hunterId,
      'status': status,
      if (start != null) 'startDate': Timestamp.fromDate(start),
      if (end != null) 'endDate': Timestamp.fromDate(end),
    });
  }

  group('config persistence', () {
    test('loadConfig returns the manual default for a missing user doc',
        () async {
      final fake = FakeFirebaseFirestore();
      final config = await service(fake, uid: 'u1').loadConfig('outfitter-1');
      expect(config.systemType, ExternalBookingSystemType.manual);
      expect(config.feedUrl, isEmpty);
    });

    test('saveConfig writes bookingSync onto the outfitter users doc',
        () async {
      final fake = FakeFirebaseFirestore();
      await service(fake, uid: 'outfitter-1').saveConfig(
        const ExternalBookingConfig(
          systemType: ExternalBookingSystemType.ical,
          feedUrl: 'https://lodge.example.com/cal.ics',
        ),
      );
      final doc = await fake.collection('users').doc('outfitter-1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['bookingSync']['type'], 'ical');
      expect(doc.data()!['bookingSync']['feedUrl'],
          'https://lodge.example.com/cal.ics');
    });

    test('saveConfig rejects an unauthenticated caller', () async {
      final fake = FakeFirebaseFirestore();
      expect(
        () => service(fake, uid: null)
            .saveConfig(const ExternalBookingConfig()),
        throwsException,
      );
    });

    test('loadConfig resolves a saved mock configuration', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('users').doc('outfitter-1').set({
        'bookingSync': {'type': 'mock', 'feedUrl': ''},
      });
      final config = await service(fake, uid: 'hunter-1').loadConfig(
        'outfitter-1',
      );
      expect(config.systemType, ExternalBookingSystemType.mock);
    });
  });

  group('getAvailability', () {
    test('unauthenticated caller sees no local bookings (external only)',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-1',
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 22),
      );
      final availability = await service(fake, uid: null).getAvailability(
        outfitterId: 'outfitter-1',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(availability.localBlockedDates, isEmpty);
      expect(availability.blockedDates, isEmpty);
    });

    test('a hunter sees their own active booking dates blocked', () async {
      final fake = FakeFirebaseFirestore();
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-1',
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 23),
      );
      final availability =
          await service(fake, uid: 'hunter-1').getAvailability(
        outfitterId: 'outfitter-1',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(
        availability.localBlockedDates,
        {
          DateTime(2026, 8, 21),
          DateTime(2026, 8, 22),
          DateTime(2026, 8, 23),
        },
      );
    });

    test('terminal bookings (declined/cancelled/completed) do not block',
        () async {
      final fake = FakeFirebaseFirestore();
      for (final status in const ['Declined', 'Cancelled', 'Completed']) {
        await seedBooking(
          fake,
          outfitterId: 'outfitter-1',
          hunterId: 'hunter-1',
          status: status,
          start: DateTime(2026, 8, 21),
          end: DateTime(2026, 8, 22),
        );
      }
      final availability =
          await service(fake, uid: 'hunter-1').getAvailability(
        outfitterId: 'outfitter-1',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(availability.localBlockedDates, isEmpty);
    });

    test('the outfitter caller sees ALL of their bookings blocked', () async {
      final fake = FakeFirebaseFirestore();
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-1',
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 21),
      );
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-2',
        status: 'Confirmed',
        start: DateTime(2026, 8, 25),
        end: DateTime(2026, 8, 25),
      );
      final availability =
          await service(fake, uid: 'outfitter-1').getAvailability(
        outfitterId: 'outfitter-1',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(
        availability.localBlockedDates,
        {DateTime(2026, 8, 21), DateTime(2026, 8, 25)},
      );
    });

    test('a hunter does NOT see another hunter\'s bookings (party scope)',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-2',
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 21),
      );
      final availability =
          await service(fake, uid: 'hunter-1').getAvailability(
        outfitterId: 'outfitter-1',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(availability.localBlockedDates, isEmpty);
    });

    test('external adapter dates merge with the local state machine',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-1',
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 21),
      );
      final adapter = MockTestBookingAdapter(
        blockedDates: {DateTime(2026, 8, 25)},
      );
      final availability = await service(
        fake,
        uid: 'hunter-1',
        adapterFactory: (_) => adapter,
      ).getAvailability(
        outfitterId: 'outfitter-1',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(
        availability.blockedDates,
        {DateTime(2026, 8, 21), DateTime(2026, 8, 25)},
      );
      expect(availability.externalBlockedDates, {DateTime(2026, 8, 25)});
      expect(availability.externalReachable, isTrue);
    });

    test('an external fetch failure degrades gracefully (local still works)',
        () async {
      final fake = FakeFirebaseFirestore();
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-1',
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 21),
      );
      final availability = await service(
        fake,
        uid: 'hunter-1',
        adapterFactory: (_) => _ThrowingAdapter(),
      ).getAvailability(
        outfitterId: 'outfitter-1',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(availability.externalReachable, isFalse);
      expect(availability.localBlockedDates, {DateTime(2026, 8, 21)});
      expect(availability.blockedDates, {DateTime(2026, 8, 21)});
    });
  });

  group('verifySlot', () {
    test('false when a local booking occupies any day of the slot', () async {
      final fake = FakeFirebaseFirestore();
      await seedBooking(
        fake,
        outfitterId: 'outfitter-1',
        hunterId: 'hunter-1',
        start: DateTime(2026, 8, 21),
        end: DateTime(2026, 8, 22),
      );
      final s = service(fake, uid: 'hunter-1');
      expect(
        await s.verifySlot(
          outfitterId: 'outfitter-1',
          start: DateTime(2026, 8, 20),
          end: DateTime(2026, 8, 21),
        ),
        isFalse,
      );
      expect(
        await s.verifySlot(
          outfitterId: 'outfitter-1',
          start: DateTime(2026, 8, 23),
          end: DateTime(2026, 8, 24),
        ),
        isTrue,
      );
    });

    test('false when the external adapter blocks the slot', () async {
      final fake = FakeFirebaseFirestore();
      final s = service(
        fake,
        uid: 'hunter-1',
        adapterFactory: (_) =>
            MockTestBookingAdapter(blockedDates: {DateTime(2026, 8, 21)}),
      );
      expect(
        await s.verifySlot(
          outfitterId: 'outfitter-1',
          start: DateTime(2026, 8, 21),
          end: DateTime(2026, 8, 21),
        ),
        isFalse,
      );
    });
  });
}

/// An adapter whose fetches always fail (simulates an unreachable ERP).
class _ThrowingAdapter extends ExternalBookingAdapter {
  @override
  ExternalBookingSystemType get systemType => ExternalBookingSystemType.ical;

  @override
  Future<bool> testConnection() async => false;

  @override
  Future<Set<DateTime>> fetchUnavailableDates({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    throw Exception('unreachable');
  }

  @override
  Future<bool> verifySlot({required DateTime start, required DateTime end}) =>
      throw Exception('unreachable');

  @override
  Future<bool> holdSlot({
    required DateTime start,
    required DateTime end,
    String? reference,
  }) async =>
      false;
}
