import 'package:flutter/foundation.dart' show kDebugMode;

/// Pure, dependency-free contract for the **debug** PayFast deposit payment
/// simulator (v4.5 to-do Item #10).
///
/// In `kDebugMode` only, the hunter's "My Bookings" card renders a secondary
/// debug action (`Simulate PayFast Deposit (Debug)`) for bookings awaiting the
/// 25% deposit. Tapping it calls
/// `PackageBookingManager.simulateDepositPaid(bookingId)` which writes the
/// booking document directly to the post-payment state — exactly the state the
/// deployed PayFast ITN handler (`functions/src/index.ts`) writes when a
/// `payment_status==COMPLETE` ITN is reconciled.
///
/// This class holds ONLY the pure decision/arithmetic logic (no Firestore /
/// Flutter imports beyond `kDebugMode`) so the booking-status-transition
/// contract is fully unit-testable without the Firestore emulator.
///
/// **Production security note**: the `bookings` Firestore rule only permits the
/// **outfitter** (or the Admin-SDK-backed ITN Cloud Function, which bypasses
/// rules entirely) to flip the `status` field. A hunter-triggered debug write
/// that flips `status` to `Paid` is therefore permission-denied under the
/// production rules. The simulator is gated behind `kDebugMode` (stripped from
/// release builds) and is intended for the outfitter/admin sandbox tester or a
/// locally-relaxed rules env — it is NOT a shipped production code path.
class DepositPaymentSimulator {
  DepositPaymentSimulator._();

  /// The canonical post-payment booking status (set by the ITN handler on
  /// `payment_status==COMPLETE`).
  static const String paidStatus = 'Paid';

  /// The PayFast ITN `payment_status` value that marks a completed payment.
  static const String payfastPaymentStatusComplete = 'COMPLETE';

  /// The Firestore field recording when the deposit was paid.
  static const String depositPaidAtField = 'depositPaidAt';

  /// The Firestore flag recording that the deposit has been paid.
  static const String depositPaidField = 'depositPaid';

  /// Booking statuses that are awaiting the 25% deposit and may therefore be
  /// simulated forward to `Paid`. The canonical post-approval state is
  /// `'Pending Deposit'` (space-separated); the legacy spellings are retained
  /// for older booking documents.
  static const List<String> depositDueStatuses = <String>[
    'Pending Deposit',
    'Approved',
    'pending_payment',
    'pending_deposit',
  ];

  /// Whether the debug simulator may run for a booking with [status].
  ///
  /// Returns `true` only when `kDebugMode` is active AND [status] (case-
  /// insensitive) is one of the deposit-due statuses. Release builds always
  /// return `false` so the simulator can never ship.
  static bool canSimulate(String? status) {
    if (!kDebugMode) return false;
    if (status == null) return false;
    final lower = status.toLowerCase();
    return depositDueStatuses.any((s) => s.toLowerCase() == lower);
  }

  /// The pure, timestamp-free update map the simulator writes to the booking
  /// document. Mirrors the fields the deployed ITN handler writes on a COMPLETE
  /// payment:
  /// - `status` -> `'Paid'`
  /// - `paymentStatus` -> `'COMPLETE'`
  /// - `depositPaid` -> `true`
  ///
  /// The caller (`PackageBookingManager.simulateDepositPaid`) appends the
  /// server-timestamp fields (`depositPaidAt`, `paymentTimestamp`, `updatedAt`)
  /// which require `FieldValue.serverTimestamp()` and so are NOT pure.
  static Map<String, dynamic> simulateUpdateMap() => <String, dynamic>{
        'status': paidStatus,
        'paymentStatus': payfastPaymentStatusComplete,
        depositPaidField: true,
      };
}
