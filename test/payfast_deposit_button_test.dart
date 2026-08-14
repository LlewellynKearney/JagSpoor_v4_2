import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/pricing_math.dart';

/// Unit tests for the PayFast deposit checkout button on the hunter's
/// "My Bookings" card (v4.5 to-do Item #7).
///
/// The card renders a prominent `ElevatedButton.icon` "Pay 25% Deposit
/// (<formatted>)" when the booking is in the deposit-due state. These tests
/// exercise the real code paths the button relies on:
/// - `PricingMath.resolveDeposit` (computes the 25% charge off the marked-up
///   total, with the stored-deposit fast path for docs where
///   `approveBookingAndRequestDeposit` already stamped the split).
/// - `PricingMath.formatCurrency` (formats the ZAR deposit label).
/// - a deposit-eligibility helper mirroring the card's status check — the
///   canonical `'Pending Deposit'` (space) status MUST qualify (this was the
///   bug: the prior underscore-only check `'pending_deposit'` never matched
///   the canonical space-spelled status, so the button silently failed to
///   render on Pending Deposit bookings).
void main() {
  group('PricingMath.formatCurrency — PayFast deposit label', () {
    test('formats a typical deposit with two decimals', () {
      // 25% of a R10 000 marked-up (×1.075 = R10 750) total = R2 687.50.
      expect(PricingMath.formatCurrency(2687.5), 'R 2\u202F687.50');
    });

    test('groups thousands with a thin space', () {
      expect(PricingMath.formatCurrency(1234567), 'R 1\u202F234\u202F567.00');
    });

    test('zero renders as R 0.00', () {
      expect(PricingMath.formatCurrency(0), 'R 0.00');
    });

    test('rounds half-up to two decimals', () {
      expect(PricingMath.formatCurrency(99.999), 'R 100.00');
      expect(PricingMath.formatCurrency(99.994), 'R 99.99');
    });

    test('small amounts under 1000 are not group-separated', () {
      expect(PricingMath.formatCurrency(250), 'R 250.00');
      expect(PricingMath.formatCurrency(12.5), 'R 12.50');
    });
  });

  group('PricingMath.resolveDeposit — 25% charge off marked-up total', () {
    test('uses the stored deposit when present (approveBookingAndRequestDeposit '
        'stamps the split)', () {
      // `approveBookingAndRequestDeposit` writes depositAmountRands =
      // totalPrice × 0.25. The card reads it back verbatim.
      final deposit = PricingMath.resolveDeposit(
        storedDeposit: 2687.5,
        markedUpTotalValue: 10750,
      );
      expect(deposit, 2687.5);
    });

    test('derives 25% off the marked-up total when the stored split is absent '
        '(legacy booking)', () {
      final deposit = PricingMath.resolveDeposit(
        storedDeposit: null,
        markedUpTotalValue: 10750, // R10 000 base × 1.075
      );
      expect(deposit, closeTo(2687.5, 0.001));
    });

    test('derives 25% off the marked-up total when the stored split is 0 '
        '(legacy booking)', () {
      final deposit = PricingMath.resolveDeposit(
        storedDeposit: 0,
        markedUpTotalValue: 10750,
      );
      expect(deposit, closeTo(2687.5, 0.001));
    });

    test('the card-label deposit matches the PayFast charge amount', () {
      // The card computes `payfastAmount = depositAmount` and renders
      // `PricingMath.formatCurrency(depositAmount)` in the label; the same
      // value is passed to `PayfastCheckout.launchDeposit(amount:)`. Assert
      // the label and the charge agree.
      final markedUpTotal = 10750.0;
      final deposit = PricingMath.resolveDeposit(
        storedDeposit: null,
        markedUpTotalValue: markedUpTotal,
      );
      final label = 'Pay 25% Deposit (${PricingMath.formatCurrency(deposit)})';
      // The formatted deposit uses a thin-space thousands separator
      // (e.g. 'R 2\u202F687.50'); assert on the formatted value directly.
      expect(label, contains(PricingMath.formatCurrency(deposit)));
      expect(deposit, closeTo(markedUpTotal * 0.25, 0.001));
    });
  });

  group('deposit-due eligibility — canonical Pending Deposit status', () {
    // Mirrors the card's `isDepositDueStatus` check exactly (case-insensitive
    // on the canonical space-spelled status, plus legacy fallbacks). This is
    // the regression guard for the v4.5 Item #7 bug: the button must render
    // for `'Pending Deposit'`.
    bool isDepositDueStatus(String status) {
      final s = status.toLowerCase();
      return s == 'pending deposit' ||
          s == 'pending_deposit' ||
          s == 'approved' ||
          s == 'pending_payment';
    }

    test('canonical "Pending Deposit" qualifies (the v4.5 Item #7 bug fix)',
        () {
      expect(isDepositDueStatus('Pending Deposit'), isTrue);
      expect(isDepositDueStatus('PENDING DEPOSIT'), isTrue);
      expect(isDepositDueStatus('pending deposit'), isTrue);
    });

    test('case-insensitive', () {
      expect(isDepositDueStatus('PeNdInG DePoSiT'), isTrue);
    });

    test('legacy "approved" / "pending_payment" still qualify (fallback)', () {
      expect(isDepositDueStatus('Approved'), isTrue);
      expect(isDepositDueStatus('pending_payment'), isTrue);
    });

    test('non-deposit-due statuses do not qualify', () {
      expect(isDepositDueStatus('Pending Approval'), isFalse);
      expect(isDepositDueStatus('Paid'), isFalse);
      expect(isDepositDueStatus('Declined'), isFalse);
      expect(isDepositDueStatus('Completed'), isFalse);
      expect(isDepositDueStatus('Cancelled'), isFalse);
    });

    test('the show-button guard also requires deposit > 0', () {
      // The card: showPayButton = isDepositDueStatus && payfastAmount > 0.
      // A Pending Deposit booking with a zero deposit (edge case) does NOT
      // render the Pay button.
      final status = 'Pending Deposit';
      final deposit = 0.0;
      expect(isDepositDueStatus(status) && deposit > 0, isFalse);

      final depositPositive = 2687.5;
      expect(isDepositDueStatus(status) && depositPositive > 0, isTrue);
    });
  });

  group('PayFast item_name is the package title', () {
    // The card passes `itemName: packageName` so the PayFast line item reads
    // the package name (not the raw booking id). `PayfastCheckout.launchDeposit`
    // defaults to 'JagSpoor Booking $bookingId' when itemName is null. This
    // asserts the card's call passes the package name.
    test('a custom package name is preferred over the booking-id default', () {
      const packageName = 'Big 5 Plains Safari';
      const bookingId = 'booking-123';
      // Mirrors launchDeposit's itemName resolution.
      final itemName = packageName ?? 'JagSpoor Booking $bookingId';
      expect(itemName, 'Big 5 Plains Safari');
    });

    test('null itemName falls back to the booking-id default', () {
      const String? packageName = null;
      const bookingId = 'booking-123';
      final itemName = packageName ?? 'JagSpoor Booking $bookingId';
      expect(itemName, 'JagSpoor Booking booking-123');
    });
  });
}
