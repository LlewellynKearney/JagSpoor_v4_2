import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';

/// Tests for the outfitter Enterprise dashboard "Managers" and "Pending"
/// count fixes.
///
/// Task 1 (Managers card showed 0): the dashboard queried the nonexistent
/// `managers` collection instead of `farm_managers` (the collection
/// `OutfitterEnterpriseManager.assignManager` writes to). Locked in via a
/// structural source-contract test (the Firestore emulator cannot run in
/// this sandbox -- see AGENTS.md environment constraints).
///
/// Task 2 (Pending card showed 0): the dashboard used a strict server-side
/// `status == 'Pending Approval'` equality match, which silently missed
/// pending bookings whose status was written with a legacy case / spelling
/// variant. `BookingStatus.normalize` + `isPendingApproval` now provide a
/// tolerant single source of truth, unit-tested here without Firestore.
void main() {
  group('BookingStatus.normalize', () {
    test('passes canonical statuses through unchanged', () {
      expect(BookingStatus.normalize('Pending Approval'),
          BookingStatus.pendingApproval);
      expect(BookingStatus.normalize('Awaiting Payment'),
          BookingStatus.approvedAwaitingPayment);
      expect(BookingStatus.normalize('Confirmed'), BookingStatus.confirmed);
      expect(BookingStatus.normalize('Completed'), BookingStatus.completed);
      expect(BookingStatus.normalize('Declined'), BookingStatus.declined);
      expect(BookingStatus.normalize('Cancelled'), BookingStatus.cancelled);
    });

    test('maps lowercase / mixed-case "pending" variants to Pending Approval',
        () {
      for (final variant in [
        'pending',
        'Pending',
        'PENDING',
        'pending approval',
        'pending_approval',
        'pending-approval',
        'Pending_Approval',
      ]) {
        expect(BookingStatus.normalize(variant), BookingStatus.pendingApproval,
            reason: '"$variant" should normalize to Pending Approval');
      }
    });

    test('maps legacy approved / deposit variants to Awaiting Payment', () {
      for (final variant in [
        'Approved',
        'approved',
        'Pending Deposit',
        'pending_deposit',
        'Pending Payment',
      ]) {
        expect(BookingStatus.normalize(variant),
            BookingStatus.approvedAwaitingPayment,
            reason: '"$variant" should normalize to Awaiting Payment');
      }
    });

    test('maps legacy "Paid" to Confirmed', () {
      expect(BookingStatus.normalize('Paid'), BookingStatus.confirmed);
      expect(BookingStatus.normalize('paid'), BookingStatus.confirmed);
    });

    test('normalizes the American "canceled" spelling', () {
      expect(BookingStatus.normalize('Canceled'), BookingStatus.cancelled);
    });

    test('returns null for null / blank input', () {
      expect(BookingStatus.normalize(null), isNull);
      expect(BookingStatus.normalize(''), isNull);
      expect(BookingStatus.normalize('   '), isNull);
    });

    test('trims surrounding whitespace', () {
      expect(BookingStatus.normalize('  Pending Approval  '),
          BookingStatus.pendingApproval);
    });

    test('returns an unknown status trimmed + unchanged (never remapped)', () {
      expect(BookingStatus.normalize('Something Else'), 'Something Else');
      expect(BookingStatus.normalize('  Refunded  '), 'Refunded');
    });
  });

  group('BookingStatus.isPendingApproval', () {
    test('true for the canonical pending status', () {
      expect(BookingStatus.isPendingApproval('Pending Approval'), isTrue);
    });

    test('true for legacy case / spelling variants', () {
      for (final variant in ['pending', 'Pending', 'pending_approval']) {
        expect(BookingStatus.isPendingApproval(variant), isTrue,
            reason: '"$variant" must increment the Pending card counter');
      }
    });

    test('false for every non-pending status', () {
      for (final status in [
        'Awaiting Payment',
        'Approved',
        'Confirmed',
        'Completed',
        'Declined',
        'Cancelled',
        'Paid',
      ]) {
        expect(BookingStatus.isPendingApproval(status), isFalse,
            reason: '"$status" must NOT increment the Pending card counter');
      }
    });

    test('false for null / blank input', () {
      expect(BookingStatus.isPendingApproval(null), isFalse);
      expect(BookingStatus.isPendingApproval(''), isFalse);
    });
  });

  group('outfitter_revenue_screen.dart count-query contract', () {
    // Run from the project root (flutter test sets the CWD to the package
    // root).
    final source = File(
            'lib/features/hunter_mode/screens/outfitter_revenue_screen.dart')
        .readAsStringSync();

    test('managers count queries the farm_managers collection', () {
      expect(source.contains("collection('farm_managers')"), isTrue,
          reason: 'assignManager writes to farm_managers -- the dashboard '
              'must read the same collection');
    });

    test('managers count does NOT query the wrong managers collection', () {
      expect(source.contains("collection('managers')"), isFalse,
          reason: 'the nonexistent managers collection always returned 0');
    });

    test('pending count filters bookings by outfitterId', () {
      expect(
        source.contains(
            ".collection('bookings')\n            .where('outfitterId'"),
        isTrue,
        reason: 'the Pending card must only count the signed-in outfitter\'s '
            'bookings',
      );
    });

    test('pending count uses the tolerant BookingStatus.isPendingApproval '
        'match', () {
      expect(source.contains('BookingStatus.isPendingApproval'), isTrue,
          reason: 'a strict status equality match silently misses legacy '
              'pending status spellings');
    });

    test('auxiliary metrics degrade independently (no single-metric stream '
        'failure)', () {
      expect(source.contains('_tryCount('), isTrue);
      expect(source.contains('_tryList('), isTrue);
    });
  });
}
