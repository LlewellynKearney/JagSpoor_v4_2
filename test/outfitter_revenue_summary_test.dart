import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';
import 'package:jagspoor/features/hunter_mode/services/outfitter_analytics_service.dart';

/// Unit tests for the outfitter revenue summary's **earned-status filter**
/// contract under the off-platform booking lifecycle.
///
/// The Firestore-backed stream cannot run in this sandbox (no emulator), so
/// these tests lock in the static `earnedBookingStatuses` set that the
/// `where('status', whereIn: ...)` query uses, plus the filter predicate the
/// dashboard mirrors.
///
/// Off-platform booking lifecycle:
///   `Pending Approval` -> `Awaiting Payment` -> `Confirmed` -> `Completed`
///
/// Only `Confirmed` (payment verified) and `Completed` (hunt delivered) count
/// toward **realized** revenue. `Pending Approval` and `Awaiting Payment` are
/// explicitly excluded -- the payment has not yet been verified, so revenue is
/// not realized.
void main() {
  group('OutfitterAnalyticsService.earnedBookingStatuses', () {
    test('includes every payment-verified / delivered booking state', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        containsAll(
          [BookingStatus.confirmed, BookingStatus.completed],
        ),
      );
    });

    test('excludes the pre-approval state', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        isNot(contains(BookingStatus.pendingApproval)),
      );
    });

    test('excludes the awaiting-payment state (payment not yet verified)', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        isNot(contains(BookingStatus.approvedAwaitingPayment)),
      );
    });

    test('excludes the dead-end states', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        isNot(anyOf(
          contains(BookingStatus.declined),
          contains(BookingStatus.cancelled),
        )),
      );
    });

    test('contains exactly two earned statuses (no extras)', () {
      expect(OutfitterAnalyticsService.earnedBookingStatuses.length, 2);
    });

    test('equals BookingStatus.earnedStatuses (single source of truth)', () {
      expect(
        OutfitterAnalyticsService.earnedBookingStatuses,
        BookingStatus.earnedStatuses,
      );
    });

    test('the filter predicate admits an earned booking and rejects others', () {
      final earned = Set.from(OutfitterAnalyticsService.earnedBookingStatuses);
      bool isEarned(String status) => earned.contains(status);

      for (final s in [BookingStatus.confirmed, BookingStatus.completed]) {
        expect(isEarned(s), isTrue, reason: '$s should count as earned');
      }
      for (final s in [
        BookingStatus.pendingApproval,
        BookingStatus.approvedAwaitingPayment,
        BookingStatus.declined,
        BookingStatus.cancelled,
        '',
        'unknown',
      ]) {
        expect(isEarned(s), isFalse, reason: '$s should NOT count as earned');
      }
    });
  });

  group('BookingStatus lifecycle contract', () {
    test('allStatuses covers the full lifecycle', () {
      expect(BookingStatus.allStatuses, containsAll([
        BookingStatus.pendingApproval,
        BookingStatus.approvedAwaitingPayment,
        BookingStatus.confirmed,
        BookingStatus.completed,
        BookingStatus.declined,
        BookingStatus.cancelled,
      ]));
      expect(BookingStatus.allStatuses.length, 6);
    });

    test('isEarned is true only for Confirmed / Completed', () {
      expect(BookingStatus.isEarned(BookingStatus.confirmed), isTrue);
      expect(BookingStatus.isEarned(BookingStatus.completed), isTrue);
      expect(BookingStatus.isEarned(BookingStatus.pendingApproval), isFalse);
      expect(BookingStatus.isEarned(BookingStatus.approvedAwaitingPayment), isFalse);
      expect(BookingStatus.isEarned(BookingStatus.declined), isFalse);
      expect(BookingStatus.isEarned(BookingStatus.cancelled), isFalse);
      expect(BookingStatus.isEarned(null), isFalse);
      expect(BookingStatus.isEarned(''), isFalse);
    });

    test('isActiveRequest is true for pending + awaiting-payment', () {
      expect(BookingStatus.isActiveRequest(BookingStatus.pendingApproval), isTrue);
      expect(
        BookingStatus.isActiveRequest(BookingStatus.approvedAwaitingPayment),
        isTrue,
      );
      expect(BookingStatus.isActiveRequest(BookingStatus.confirmed), isFalse);
      expect(BookingStatus.isActiveRequest(BookingStatus.completed), isFalse);
      expect(BookingStatus.isActiveRequest(BookingStatus.declined), isFalse);
    });

    test('isArchived is true for confirmed / completed / declined / cancelled', () {
      expect(BookingStatus.isArchived(BookingStatus.confirmed), isTrue);
      expect(BookingStatus.isArchived(BookingStatus.completed), isTrue);
      expect(BookingStatus.isArchived(BookingStatus.declined), isTrue);
      expect(BookingStatus.isArchived(BookingStatus.cancelled), isTrue);
      expect(BookingStatus.isArchived(BookingStatus.pendingApproval), isFalse);
      expect(
        BookingStatus.isArchived(BookingStatus.approvedAwaitingPayment),
        isFalse,
      );
    });

    test('hunterBadgeLabel maps each status to a readable label', () {
      expect(
        BookingStatus.hunterBadgeLabel(BookingStatus.pendingApproval),
        'Pending Outfitter Approval',
      );
      expect(
        BookingStatus.hunterBadgeLabel(BookingStatus.approvedAwaitingPayment),
        'Payment Required',
      );
      expect(BookingStatus.hunterBadgeLabel(BookingStatus.confirmed), 'Confirmed');
      expect(BookingStatus.hunterBadgeLabel(BookingStatus.completed), 'Completed');
      expect(BookingStatus.hunterBadgeLabel(BookingStatus.declined), 'Declined');
      expect(BookingStatus.hunterBadgeLabel(BookingStatus.cancelled), 'Cancelled');
      // Unknown / null falls back to the pending-approval label.
      expect(
        BookingStatus.hunterBadgeLabel(null),
        'Pending Outfitter Approval',
      );
      expect(
        BookingStatus.hunterBadgeLabel('unknown'),
        'Pending Outfitter Approval',
      );
    });

    test('earnedStatuses does not overlap with activeRequestStatuses', () {
      final earned = Set.from(BookingStatus.earnedStatuses);
      final active = Set.from(BookingStatus.activeRequestStatuses);
      expect(earned.intersection(active), isEmpty);
    });
  });

  group('BookingStatus state-machine transition rules', () {
    /// The off-platform booking lifecycle:
    ///   Pending Approval --approve--> Awaiting Payment --verify payment-->
    ///   Confirmed --mark delivered--> Completed
    /// with Declined / Cancelled as dead-ends reachable from appropriate
    /// states.

    test('canApprove: only Pending Approval can be approved', () {
      expect(BookingStatus.canApprove(BookingStatus.pendingApproval), isTrue);
      expect(
        BookingStatus.canApprove(BookingStatus.approvedAwaitingPayment),
        isFalse,
      );
      expect(BookingStatus.canApprove(BookingStatus.confirmed), isFalse);
      expect(BookingStatus.canApprove(BookingStatus.completed), isFalse);
      expect(BookingStatus.canApprove(BookingStatus.declined), isFalse);
      expect(BookingStatus.canApprove(BookingStatus.cancelled), isFalse);
      expect(BookingStatus.canApprove(null), isFalse);
    });

    test('canConfirmPayment: only Awaiting Payment (or legacy Approved) can be confirmed', () {
      // The canonical post-approval awaiting-payment state can be confirmed.
      expect(
        BookingStatus.canConfirmPayment(BookingStatus.approvedAwaitingPayment),
        isTrue,
      );
      // Legacy 'Approved' bookings (pre-payment-verification flow) can be
      // confirmed (migrated forward to Confirmed).
      expect(BookingStatus.canConfirmPayment('Approved'), isTrue);
      // A pending-approval booking cannot be confirmed (must be approved first).
      expect(
        BookingStatus.canConfirmPayment(BookingStatus.pendingApproval),
        isFalse,
      );
      // An already-confirmed booking cannot be re-confirmed.
      expect(BookingStatus.canConfirmPayment(BookingStatus.confirmed), isFalse);
      expect(BookingStatus.canConfirmPayment(BookingStatus.completed), isFalse);
      expect(BookingStatus.canConfirmPayment(BookingStatus.declined), isFalse);
      expect(BookingStatus.canConfirmPayment(BookingStatus.cancelled), isFalse);
      expect(BookingStatus.canConfirmPayment(null), isFalse);
    });

    test('canCancel: cancellable from non-terminal states', () {
      expect(BookingStatus.canCancel(BookingStatus.pendingApproval), isTrue);
      expect(
        BookingStatus.canCancel(BookingStatus.approvedAwaitingPayment),
        isTrue,
      );
      expect(BookingStatus.canCancel(BookingStatus.confirmed), isTrue);
      expect(BookingStatus.canCancel('Approved'), isTrue);
      // Completed / declined / cancelled are terminal -- cannot be cancelled.
      expect(BookingStatus.canCancel(BookingStatus.completed), isFalse);
      expect(BookingStatus.canCancel(BookingStatus.declined), isFalse);
      expect(BookingStatus.canCancel(BookingStatus.cancelled), isFalse);
    });

    test('canComplete: only Confirmed can be marked Completed', () {
      expect(BookingStatus.canComplete(BookingStatus.confirmed), isTrue);
      expect(BookingStatus.canComplete(BookingStatus.pendingApproval), isFalse);
      expect(
        BookingStatus.canComplete(BookingStatus.approvedAwaitingPayment),
        isFalse,
      );
      expect(BookingStatus.canComplete(BookingStatus.completed), isFalse);
      expect(BookingStatus.canComplete('Approved'), isFalse);
    });

    test('full happy-path lifecycle: pending -> awaiting -> confirmed -> completed', () {
      // Each step's precondition is satisfied by the previous step's result.
      var current = BookingStatus.pendingApproval;
      expect(BookingStatus.canApprove(current), isTrue);
      current = BookingStatus.approvedAwaitingPayment;
      expect(BookingStatus.canConfirmPayment(current), isTrue);
      current = BookingStatus.confirmed;
      expect(BookingStatus.isEarned(current), isTrue); // revenue realized
      expect(BookingStatus.canComplete(current), isTrue);
      current = BookingStatus.completed;
      expect(BookingStatus.isEarned(current), isTrue); // still earned
      expect(BookingStatus.canComplete(current), isFalse); // terminal
    });

    test('revenue is NOT realized at the awaiting-payment stage', () {
      // The key invariant: a booking that is approved but not yet
      // payment-verified must NOT count toward revenue.
      expect(
        BookingStatus.isEarned(BookingStatus.approvedAwaitingPayment),
        isFalse,
      );
      // Only after the outfitter verifies payment (Confirmed) does it count.
      expect(BookingStatus.isEarned(BookingStatus.confirmed), isTrue);
    });
  });
}

