import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';
import 'package:jagspoor/features/hunter_mode/services/booking_activity_classifier.dart';

/// Tests for [BookingActivityClassifier] -- the pure split between the
/// hunter's active / upcoming hunts ("My Bookings" tab) and the past /
/// archived hunts ("Past Hunts" tab).
///
/// A booking is PAST when its status is terminal (Completed / Declined /
/// Cancelled, tolerant of legacy spellings) OR its hunt window's final day
/// has passed. Everything else (pending, awaiting payment, confirmed with
/// future dates, or no dates yet) stays ACTIVE.
void main() {
  // Fixed reference "today" so the date comparisons are deterministic.
  final now = DateTime(2026, 8, 19, 12, 0);

  Map<String, dynamic> booking({
    String? status,
    String? startDate,
    String? endDate,
  }) =>
      {
        if (status != null) 'status': status,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      };

  group('status-based archiving', () {
    test('Completed is past regardless of dates', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(status: 'Completed', startDate: '2027-01-01'),
          now: now,
        ),
        isTrue,
      );
    });

    test('Declined is past', () {
      expect(
        BookingActivityClassifier.isPastHunt(booking(status: 'Declined')),
        isTrue,
      );
    });

    test('Cancelled is past (and the American spelling too)', () {
      expect(
        BookingActivityClassifier.isPastHunt(booking(status: 'Cancelled')),
        isTrue,
      );
      expect(
        BookingActivityClassifier.isPastHunt(booking(status: 'canceled')),
        isTrue,
      );
    });

    test('legacy lowercase terminal spellings are past', () {
      for (final s in ['completed', 'declined', 'cancelled']) {
        expect(
          BookingActivityClassifier.isPastHunt(booking(status: s), now: now),
          isTrue,
          reason: '"$s" should archive via the tolerant normalize',
        );
      }
    });

    test('Pending Approval with no dates stays ACTIVE (still coordinating)',
        () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(status: BookingStatus.pendingApproval),
          now: now,
        ),
        isFalse,
      );
    });

    test('Awaiting Payment with no dates stays ACTIVE', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(status: BookingStatus.approvedAwaitingPayment),
          now: now,
        ),
        isFalse,
      );
    });

    test('legacy "pending" spelling with no dates stays ACTIVE', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(status: 'pending'),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('date-based archiving', () {
    test('a hunt whose final day has passed is past (Confirmed)', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(
            status: BookingStatus.confirmed,
            startDate: '2026-08-10',
            endDate: '2026-08-12',
          ),
          now: now,
        ),
        isTrue,
      );
    });

    test('a hunt with future dates is active (Confirmed)', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(
            status: BookingStatus.confirmed,
            startDate: '2026-09-01',
            endDate: '2026-09-05',
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('a hunt ending today is still ACTIVE (not yet past)', () {
      // The window end is calendar-exclusive (start of the day after the
      // final hunt day), so a hunt whose final day is today is not past yet.
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(
            status: BookingStatus.confirmed,
            startDate: '2026-08-18',
            endDate: '2026-08-19',
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('a hunt that ended yesterday is past', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(
            status: BookingStatus.approvedAwaitingPayment,
            startDate: '2026-08-15',
            endDate: '2026-08-18',
          ),
          now: now,
        ),
        isTrue,
      );
    });

    test('single-day hunt yesterday is past; today is active', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(startDate: '2026-08-18'),
          now: now,
        ),
        isTrue,
      );
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(startDate: '2026-08-19'),
          now: now,
        ),
        isFalse,
      );
    });

    test('resolves the window through the alias families (checkInDate)',
        () {
      expect(
        BookingActivityClassifier.isPastHunt(
          {
            'status': 'Confirmed',
            'checkInDate': '2026-08-01',
            'checkOutDate': '2026-08-05',
          },
          now: now,
        ),
        isTrue,
      );
    });

    test('a pending booking with PAST dates archives (stale request)', () {
      expect(
        BookingActivityClassifier.isPastHunt(
          booking(
            status: 'Pending Approval',
            startDate: '2026-01-01',
            endDate: '2026-01-05',
          ),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('isActiveHunt is the exact complement', () {
    test('complement for every representative case', () {
      final cases = <Map<String, dynamic>>[
        booking(status: 'Completed'),
        booking(status: 'Confirmed', startDate: '2027-01-01'),
        booking(status: 'Confirmed', startDate: '2026-01-01'),
        booking(status: 'Pending Approval'),
        booking(status: 'Declined'),
      ];
      for (final b in cases) {
        expect(
          BookingActivityClassifier.isActiveHunt(b, now: now),
          !BookingActivityClassifier.isPastHunt(b, now: now),
        );
      }
    });
  });
}
