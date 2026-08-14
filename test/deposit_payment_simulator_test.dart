import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/deposit_payment_simulator.dart';
import 'package:jagspoor/core/services/payfast_checkout.dart';

/// Unit tests for the debug PayFast deposit payment simulator + return-URL
/// handler (v4.5 to-do Item #10).
///
/// Covers:
/// - The `DepositPaymentSimulator` pure decision/arithmetic contract (status
///   eligibility + the post-payment update map that mirrors the ITN handler's
///   state) — fully testable without the Firestore emulator.
/// - The `PayfastCheckout.buildReturnUrl` deep link shape the app-resume
///   listener detects.
void main() {
  group('DepositPaymentSimulator constants', () {
    test('paid status is the canonical "Paid"', () {
      expect(DepositPaymentSimulator.paidStatus, 'Paid');
    });

    test('PayFast payment status complete is "COMPLETE"', () {
      expect(DepositPaymentSimulator.payfastPaymentStatusComplete, 'COMPLETE');
    });

    test('deposit paid-at field is "depositPaidAt"', () {
      expect(DepositPaymentSimulator.depositPaidAtField, 'depositPaidAt');
    });

    test('deposit paid flag field is "depositPaid"', () {
      expect(DepositPaymentSimulator.depositPaidField, 'depositPaid');
    });

    test('deposit-due statuses include canonical + legacy spellings', () {
      expect(DepositPaymentSimulator.depositDueStatuses,
          contains('Pending Deposit'));
      expect(DepositPaymentSimulator.depositDueStatuses, contains('Approved'));
      expect(
          DepositPaymentSimulator.depositDueStatuses, contains('pending_payment'));
      expect(DepositPaymentSimulator.depositDueStatuses,
          contains('pending_deposit'));
    });
  });

  group('DepositPaymentSimulator.canSimulate (debug mode, test runner)', () {
    // The Flutter test runner executes in debug mode, so kDebugMode is true
    // here and the eligibility reflects the status check only.
    test('true for the canonical "Pending Deposit" status', () {
      expect(DepositPaymentSimulator.canSimulate('Pending Deposit'), isTrue);
    });

    test('true for the legacy "Approved" status', () {
      expect(DepositPaymentSimulator.canSimulate('Approved'), isTrue);
    });

    test('true for legacy snake-case spellings', () {
      expect(DepositPaymentSimulator.canSimulate('pending_deposit'), isTrue);
      expect(DepositPaymentSimulator.canSimulate('pending_payment'), isTrue);
    });

    test('case-insensitive', () {
      expect(DepositPaymentSimulator.canSimulate('PENDING DEPOSIT'), isTrue);
      expect(DepositPaymentSimulator.canSimulate('approved'), isTrue);
    });

    test('false for a non-deposit-due status', () {
      expect(DepositPaymentSimulator.canSimulate('Paid'), isFalse);
      expect(DepositPaymentSimulator.canSimulate('Pending Approval'), isFalse);
      expect(DepositPaymentSimulator.canSimulate('Declined'), isFalse);
      expect(DepositPaymentSimulator.canSimulate('Completed'), isFalse);
      expect(DepositPaymentSimulator.canSimulate('Cancelled'), isFalse);
    });

    test('false for null status', () {
      expect(DepositPaymentSimulator.canSimulate(null), isFalse);
    });
  });

  group('DepositPaymentSimulator.simulateUpdateMap (post-payment state)', () {
    final map = DepositPaymentSimulator.simulateUpdateMap();

    test('writes the canonical paid status', () {
      expect(map['status'], 'Paid');
    });

    test('writes the PayFast COMPLETE payment status', () {
      expect(map['paymentStatus'], 'COMPLETE');
    });

    test('sets the depositPaid flag true', () {
      expect(map[DepositPaymentSimulator.depositPaidField], isTrue);
    });

    test('does not contain the server-timestamp fields (added by the service)', () {
      // Timestamps require FieldValue.serverTimestamp() and are appended by
      // PackageBookingManager.simulateDepositPaid, not the pure helper.
      expect(map.containsKey('depositPaidAt'), isFalse);
      expect(map.containsKey('paymentTimestamp'), isFalse);
      expect(map.containsKey('updatedAt'), isFalse);
    });

    test('is a fresh map per call (no shared mutable state)', () {
      final a = DepositPaymentSimulator.simulateUpdateMap();
      final b = DepositPaymentSimulator.simulateUpdateMap();
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      a['status'] = 'Mutated';
      expect(b['status'], 'Paid'); // b unaffected
    });
  });

  group('PayfastCheckout.buildReturnUrl (custom-scheme deep link handler)', () {
    test('returns the jagspoor://payment-return custom scheme', () {
      final url = PayfastCheckout.buildReturnUrl('booking-123');
      expect(url, startsWith(PayfastCheckout.returnScheme));
      expect(url, startsWith('jagspoor://payment-return'));
      // No longer uses the deprecated/unconfigured page.link domain.
      expect(url.contains('jagspoor.page.link'), isFalse);
    });

    test('encodes the booking id + success status as query params', () {
      final bookingId = 'abc 123&special';
      final url = PayfastCheckout.buildReturnUrl(bookingId);
      final uri = Uri.parse(url);
      expect(uri.scheme, 'jagspoor');
      expect(uri.host, 'payment-return');
      expect(uri.queryParameters['booking_id'], bookingId);
      expect(uri.queryParameters['status'], 'success');
    });

    test('percent-encodes special characters', () {
      final url = PayfastCheckout.buildReturnUrl('a b/c');
      // Spaces and slashes in the booking id must be percent-encoded, not
      // literal, so they don't break the custom-scheme URI parsing.
      expect(url.contains(' '), isFalse);
      expect(url, contains('booking_id='));
      expect(url, contains('status=success'));
    });

    test('different booking ids produce different return urls', () {
      final a = PayfastCheckout.buildReturnUrl('booking-A');
      final b = PayfastCheckout.buildReturnUrl('booking-B');
      expect(a, isNot(equals(b)));
    });
  });

  group('Booking status transition contract (debug simulator)', () {
    // Encodes the contract the simulator + ITN handler enforce: a deposit-due
    // booking transitions to `Paid`, and a non-deposit-due booking does NOT.
    test('a Pending Deposit booking transitions to Paid', () {
      const before = 'Pending Deposit';
      expect(DepositPaymentSimulator.canSimulate(before), isTrue);
      final update = DepositPaymentSimulator.simulateUpdateMap();
      expect(update['status'], DepositPaymentSimulator.paidStatus);
    });

    test('a Paid booking cannot be simulated forward', () {
      const before = 'Paid';
      expect(DepositPaymentSimulator.canSimulate(before), isFalse);
    });

    test('a Pending Approval booking cannot be simulated forward', () {
      const before = 'Pending Approval';
      expect(DepositPaymentSimulator.canSimulate(before), isFalse);
    });

    test('the simulated status is terminal-ish (no further deposit-due)', () {
      // After simulation the status is Paid, which is not deposit-due, so a
      // second simulation attempt is correctly rejected by canSimulate.
      final simulated = DepositPaymentSimulator.simulateUpdateMap()['status']
          as String;
      expect(DepositPaymentSimulator.canSimulate(simulated), isFalse);
    });
  });
}
