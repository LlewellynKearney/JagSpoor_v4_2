/// Centralized booking-status string constants for the off-platform booking
/// flow.
///
/// The booking lifecycle for an off-platform (direct) payment flow:
///
///   `pendingApproval`  -- hunter submits a booking request (default).
///        |
///        v  (outfitter approves)
///   `approvedAwaitingPayment` -- outfitter has accepted the request; the
///        |                       hunter must pay the outfitter directly
///        |                       (off-platform: cash / EFT / WhatsApp).
///        v  (outfitter verifies payment received)
///   `confirmed`  -- the outfitter has confirmed they received the direct
///        |          payment. This is the first **earned** revenue state.
///        v  (hunt concluded)
///   `completed`  -- the hunt has been delivered. Also an earned state.
///
/// Dead-end / cancelled states: `declined`, `cancelled`.
///
/// Only `confirmed` and `completed` count toward realized outfitter revenue
/// (see `BookingStatus.earnedStatuses`). `pendingApproval` and
/// `approvedAwaitingPayment` represent un-realized (pending) bookings and
/// must NOT count toward financial metrics.
class BookingStatus {
  BookingStatus._();

  /// Hunter-submitted request awaiting outfitter review. The default status
  /// for every newly-created booking.
  static const String pendingApproval = 'Pending Approval';

  /// Outfitter has approved the request; the hunter owes a direct
  /// (off-platform) payment. Revenue is NOT yet realized.
  static const String approvedAwaitingPayment = 'Awaiting Payment';

  /// Outfitter has verified receipt of the direct payment. The booking is
  /// locked in. Revenue IS realized.
  static const String confirmed = 'Confirmed';

  /// Hunt concluded / delivered. Terminal earned state.
  static const String completed = 'Completed';

  /// Outfitter rejected the request. Dead-end.
  static const String declined = 'Declined';

  /// Either party cancelled the booking. Dead-end.
  static const String cancelled = 'Cancelled';

  /// Statuses that represent **realized** outfitter revenue -- i.e. the
  /// outfitter has a confirmed claim on the booking amount. Used by the
  /// revenue summary / monthly chart `where('status', whereIn: ...)` query.
  ///
  /// `pendingApproval` and `approvedAwaitingPayment` are deliberately
  /// excluded: the payment has not been verified, so the revenue is not yet
  /// realized.
  static const List<String> earnedStatuses = [
    confirmed,
    completed,
  ];

  /// Statuses that represent an **active** booking the outfitter still needs
  /// to act on (either approve, or verify payment). Used by the booking
  /// dashboard's "incoming requests" / "awaiting payment" filters.
  static const List<String> activeRequestStatuses = [
    pendingApproval,
    approvedAwaitingPayment,
  ];

  /// Dead-end / terminal statuses that should be excluded from active
  /// request views and moved to the archived / completed view.
  static const List<String> archivedStatuses = [
    confirmed,
    completed,
    declined,
    cancelled,
  ];

  /// All valid booking status strings.
  static const List<String> allStatuses = [
    pendingApproval,
    approvedAwaitingPayment,
    confirmed,
    completed,
    declined,
    cancelled,
  ];

  /// Returns true if [status] counts toward realized outfitter revenue.
  static bool isEarned(String? status) =>
      status != null && earnedStatuses.contains(status);

  /// Returns true if [status] is an active request the outfitter must act on.
  static bool isActiveRequest(String? status) =>
      status != null && activeRequestStatuses.contains(status);

  /// Returns true if [status] is a dead-end / archived state.
  static bool isArchived(String? status) =>
      status != null && archivedStatuses.contains(status);

  // ==========================================
  // STATUS NORMALIZATION
  // ==========================================

  /// Normalizes a raw booking `status` string to its canonical
  /// [BookingStatus] constant, tolerating the case + spelling variants that
  /// appear in legacy booking documents (e.g. `'pending'`, `'Pending'`,
  /// `'pending_approval'`, `'Approved'`, `'Pending Deposit'`, `'Paid'`).
  ///
  /// Comparison is case-insensitive with `_` / `-` treated as spaces. Returns
  /// the trimmed input unchanged when no canonical match is found (an
  /// unknown status is never silently remapped). Returns `null` for a null /
  /// blank input.
  static String? normalize(String? status) {
    final raw = status?.trim();
    if (raw == null || raw.isEmpty) return null;
    final key = raw.toLowerCase().replaceAll(RegExp(r'[_\-]'), ' ');
    switch (key) {
      case 'pending approval':
      case 'pending':
        return pendingApproval;
      case 'awaiting payment':
      case 'approved':
      case 'pending deposit':
      case 'pending payment':
        return approvedAwaitingPayment;
      case 'confirmed':
      case 'paid':
        return confirmed;
      case 'completed':
        return completed;
      case 'declined':
        return declined;
      case 'cancelled':
      case 'canceled':
        return cancelled;
      default:
        return raw;
    }
  }

  /// Returns true if [status] represents a hunter-submitted booking request
  /// that is still awaiting outfitter review (the "Pending" dashboard card
  /// state). Tolerates legacy case / spelling variants via [normalize] so a
  /// pending booking written by any app version increments the counter.
  static bool isPendingApproval(String? status) =>
      normalize(status) == pendingApproval;

  // ==========================================
  // STATE-MACHINE TRANSITION RULES
  // ==========================================
  // Pure validation helpers that encode the off-platform booking lifecycle
  // transitions. They mirror the guards in `PackageBookingManager
  // .confirmPaymentReceived` / `.approveBookingAndRequestDeposit` so the
  // state-machine contract is unit-testable without the Firestore emulator.

  /// Returns true if a booking in [currentStatus] can be **approved** (i.e.
  /// transitioned to `Awaiting Payment`). Only a `Pending Approval` booking
  /// can be approved.
  static bool canApprove(String? currentStatus) =>
      currentStatus == pendingApproval;

  /// Returns true if a booking in [currentStatus] can have its payment
  /// **verified** (i.e. transitioned to `Confirmed`). Only a booking in the
  /// `Awaiting Payment` state -- or the legacy `Approved` state (pre-payment-
  /// verification-flow bookings) -- can be confirmed. A booking that is
  /// already confirmed, completed, declined, cancelled, or still pending
  /// approval cannot be confirmed.
  static bool canConfirmPayment(String? currentStatus) =>
      currentStatus == approvedAwaitingPayment ||
      currentStatus == 'Approved';

  /// Returns true if a booking in [currentStatus] can be **cancelled**. A
  /// booking may be cancelled from any non-terminal state (pending approval,
  /// awaiting payment, or confirmed). Completed bookings cannot be cancelled
  /// (the hunt has already been delivered); declined bookings are already a
  /// dead-end.
  static bool canCancel(String? currentStatus) =>
      currentStatus == pendingApproval ||
      currentStatus == approvedAwaitingPayment ||
      currentStatus == confirmed ||
      currentStatus == 'Approved';

  /// Returns true if a booking in [currentStatus] can be **marked completed**
  /// (the hunt has been delivered). Only a `Confirmed` booking (payment
  /// verified) can be marked completed.
  static bool canComplete(String? currentStatus) =>
      currentStatus == confirmed;

  /// Hunter-facing badge label for a booking card. Maps each status to a
  /// short, human-readable label suitable for the "My Bookings" status badge.
  static String hunterBadgeLabel(String? status) {
    switch (status) {
      case pendingApproval:
        return 'Pending Outfitter Approval';
      case approvedAwaitingPayment:
        return 'Payment Required';
      case confirmed:
        return 'Confirmed';
      case completed:
        return 'Completed';
      case declined:
        return 'Declined';
      case cancelled:
        return 'Cancelled';
      default:
        return 'Pending Outfitter Approval';
    }
  }
}
