import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/outfitter_analytics_service.dart';

/// Unit tests for the outfitter revenue summary's **earned-status filter**
/// contract (Item #9 part 2 — outfitter revenue summary protection).
///
/// The Firestore-backed stream cannot run in this sandbox (no emulator), so
/// these tests lock in the static `earnedBookingStatuses` set that the
/// `where('status', whereIn: ...)` query uses, plus the filter predicate the
/// dashboard mirrors. This guarantees the revenue summary counts every
/// confirmed booking state in the `Approved → Pending Deposit → Paid →
/// Completed` lifecycle and excludes the pre-approval / dead-end states.
void main() {
  group('OutfitterAnalyticsService.earnedBookingStatuses', () {
    test('includes every confirmed/earned booking state', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        containsAll(
          ['Approved', 'Pending Deposit', 'Paid', 'Completed'],
        ),
      );
    });

    test('excludes the pre-approval state', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        isNot(contains('Pending Approval')),
      );
    });

    test('excludes the dead-end states', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        isNot(anyOf(contains('Declined'), contains('Cancelled'))),
      );
    });

    test('contains exactly four earned statuses (no extras)', () {
      expect(OutfitterAnalyticsService.earnedBookingStatuses.length, 4);
    });

    test('the filter predicate admits an earned booking and rejects others', () {
      final earned = Set.from(OutfitterAnalyticsService.earnedBookingStatuses);
      bool isEarned(String status) => earned.contains(status);

      for (final s in ['Approved', 'Pending Deposit', 'Paid', 'Completed']) {
        expect(isEarned(s), isTrue, reason: '$s should count as earned');
      }
      for (final s in [
        'Pending Approval',
        'Declined',
        'Cancelled',
        '',
        'unknown',
      ]) {
        expect(isEarned(s), isFalse, reason: '$s should NOT count as earned');
      }
    });
  });
}
