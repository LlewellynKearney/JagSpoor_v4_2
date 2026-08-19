import '../models/booking_status.dart';
import 'booking_date_formatter.dart';

/// Pure classifier that splits a hunter's bookings into **active / upcoming
/// hunts** ("My Bookings") and **past / archived hunts** ("Past Hunts").
///
/// A booking is PAST (archived) when either:
/// - its status is terminal (`Completed`, `Declined`, or `Cancelled` —
///   tolerant of legacy case / spelling variants via
///   [BookingStatus.normalize]); or
/// - its hunt window's final day has already passed (the resolved window end
///   — calendar-exclusive — is not after today).
///
/// Everything else is ACTIVE: pending-approval / awaiting-payment /
/// confirmed bookings whose hunt dates are still in the future, and bookings
/// with no resolvable dates yet (still being coordinated).
///
/// The classifier is pure (no Firestore / platform dependencies) so the
/// split contract is fully unit-testable. The optional [now] parameter makes
/// the date comparison deterministic in tests.
class BookingActivityClassifier {
  BookingActivityClassifier._();

  /// Returns true when [booking] belongs in the "Past Hunts" archive.
  static bool isPastHunt(Map<String, dynamic> booking, {DateTime? now}) {
    final status = BookingStatus.normalize(booking['status'] as String?);
    if (status == BookingStatus.completed ||
        status == BookingStatus.declined ||
        status == BookingStatus.cancelled) {
      return true;
    }

    final window = BookingDateFormatter.resolveWindow(booking);
    if (window == null) {
      // No hunt dates on file — the booking is still being coordinated, so
      // it stays in the active list (never silently archived).
      return false;
    }

    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    // `window.end` is calendar-exclusive (the start of the day AFTER the
    // final hunt day), so the hunt is past once that day has been reached.
    return !window.end.isAfter(today);
  }

  /// Returns true when [booking] belongs in the active "My Bookings" list.
  static bool isActiveHunt(Map<String, dynamic> booking, {DateTime? now}) =>
      !isPastHunt(booking, now: now);
}
