import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Builds and launches a native device-calendar event for a finalized
/// (Confirmed / Completed) hunting booking.
///
/// When an outfitter verifies the hunter's direct (off-platform) payment,
/// the booking transitions to [BookingStatus.confirmed]. At that point both
/// the hunter and the outfitter can save the hunting dates, farm details,
/// and package title directly to their phone's native calendar via this
/// service so the trip appears alongside their other commitments with a
/// ready-made reminder.
///
/// The event-construction logic is split into a pure, Firebase-aware helper
/// ([BookingCalendarEventBuilder]) so it is fully unit-testable without a
/// live `add_2_calendar` plugin / device calendar.
class BookingCalendarService {
  BookingCalendarService._();

  static final BookingCalendarService instance = BookingCalendarService._();

  /// Builds a native calendar [Event] from a raw booking document map.
  ///
  /// Returns `null` when the booking has no usable hunt window (no start
  /// date could be resolved from any of the supported field aliases) -- in
  /// that case the caller should surface a "no dates on file" message
  /// rather than launching an empty calendar event.
  Event? buildEvent(Map<String, dynamic> booking) {
    return BookingCalendarEventBuilder.buildEvent(booking);
  }

  /// Builds the event and, when it resolves, hands it to `add_2_calendar`
  /// which opens the device's native calendar editor pre-populated with the
  /// hunt details. Returns whether a calendar event was launched (false when
  /// no dates could be resolved or the platform call rejected the event).
  Future<bool> addToCalendar(Map<String, dynamic> booking) async {
    final event = buildEvent(booking);
    if (event == null) return false;
    return Add2Calendar.addEvent2Cal(event);
  }
}

/// Pure, Firebase-aware builder that turns a raw booking document map into
/// an `add_2_calendar` [Event]. Exposed as a public class (with static
/// methods) so the date resolution + event construction can be unit-tested
/// without the plugin / a live device calendar.
class BookingCalendarEventBuilder {
  /// Resolves a [DateTime] (midnight, local) from a value that may be a
  /// Firestore [Timestamp], an ISO-8601 string, or a `DateTime`.
  static DateTime? resolveDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      final d = value.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      // Tolerate a plain `YYYY-MM-DD` (no time / timezone) as well as a
      // full ISO-8601 timestamp.
      final parsed = DateTime.tryParse(trimmed);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    if (value is num) {
      // Milliseconds-since-epoch.
      final d = DateTime.fromMillisecondsSinceEpoch(value.toInt());
      return DateTime(d.year, d.month, d.day);
    }
    return null;
  }

  /// Resolves the hunt start/end window from a booking document.
  ///
  /// Priority (start): `confirmedStartDate` (post-date-change-approval) ->
  /// `checkInDate` (custom package builder) -> `availabilityStart` ->
  /// `startDate` -> `huntDate`.
  /// Priority (end): `confirmedEndDate` -> `checkOutDate` ->
  /// `availabilityEnd` -> `endDate` (falls back to start when absent so the
  /// calendar event spans at least the hunt day).
  ///
  /// The returned `end` is normalized to the start of the day *after* the
  /// hunt's final day so the native calendar renders the full final day for
  /// an all-day event.
  static ({DateTime start, DateTime end})? resolveWindow(
    Map<String, dynamic> booking,
  ) {
    final start = resolveDate(booking['confirmedStartDate']) ??
        resolveDate(booking['checkInDate']) ??
        resolveDate(booking['availabilityStart']) ??
        resolveDate(booking['startDate']) ??
        resolveDate(booking['huntDate']);
    if (start == null) return null;
    final end = resolveDate(booking['confirmedEndDate']) ??
        resolveDate(booking['checkOutDate']) ??
        resolveDate(booking['availabilityEnd']) ??
        resolveDate(booking['endDate']) ??
        start;
    final normalizedEnd =
        end.isBefore(start) ? start : DateTime(end.year, end.month, end.day);
    return (
      start: DateTime(start.year, start.month, start.day),
      end: normalizedEnd.add(const Duration(days: 1)),
    );
  }

  /// Builds the [Event] title from the package name + farm name.
  static String buildTitle(Map<String, dynamic> booking) {
    final packageName = (booking['packageName'] as String?)?.trim();
    final farmName = (booking['farmName'] as String?)?.trim();
    final title = (packageName == null || packageName.isEmpty)
        ? 'JagSpoor Hunt'
        : packageName;
    return (farmName == null || farmName.isEmpty)
        ? title
        : '$title @ $farmName';
  }

  /// Builds a human-readable description block with the booking + farm
  /// details + party contact info.
  static String buildDescription(Map<String, dynamic> booking) {
    final packageName = (booking['packageName'] as String?)?.trim();
    final farmName = (booking['farmName'] as String?)?.trim();
    final totalPrice =
        (booking['totalHunterPriceRands'] as num?)?.toDouble() ??
            (booking['basePriceRands'] as num?)?.toDouble();
    final outfitterName =
        (booking['outfitterName'] as String?)?.trim() ??
            (booking['outfitterBusinessName'] as String?)?.trim();
    final hunterName = (booking['hunterName'] as String?)?.trim();
    final bookingId = (booking['id'] as String?)?.trim() ??
        (booking['bookingId'] as String?)?.trim();

    final lines = <String>['Hunting trip booked via JagSpoor.'];
    if (packageName != null && packageName.isNotEmpty) {
      lines.add('Package: $packageName');
    }
    if (farmName != null && farmName.isNotEmpty) {
      lines.add('Farm: $farmName');
    }
    if (outfitterName != null && outfitterName.isNotEmpty) {
      lines.add('Outfitter: $outfitterName');
    }
    if (hunterName != null && hunterName.isNotEmpty) {
      lines.add('Hunter: $hunterName');
    }
    if (totalPrice != null && totalPrice > 0) {
      lines.add('Total: R ${totalPrice.toStringAsFixed(2)}');
    }
    if (bookingId != null && bookingId.isNotEmpty) {
      lines.add('Booking ID: $bookingId');
    }
    return lines.join('\n');
  }

  /// Builds the calendar event location string (the farm name, if known).
  static String? buildLocation(Map<String, dynamic> booking) {
    final farmName = (booking['farmName'] as String?)?.trim();
    final district = (booking['district'] as String?)?.trim();
    final province = (booking['province'] as String?)?.trim();
    if (farmName != null && farmName.isNotEmpty) {
      final region = [district, province]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
      return region.isEmpty ? farmName : '$farmName ($region)';
    }
    if (district != null && district.isNotEmpty) return district;
    if (province != null && province.isNotEmpty) return province;
    return null;
  }

  /// Builds the native calendar [Event] from a raw booking map.
  ///
  /// Returns `null` when no hunt window can be resolved (the caller should
  /// surface a "no dates on file" message instead of launching an empty
  /// event).
  static Event? buildEvent(Map<String, dynamic> booking) {
    final window = resolveWindow(booking);
    if (window == null) return null;
    return Event(
      title: buildTitle(booking),
      description: buildDescription(booking),
      location: buildLocation(booking),
      startDate: window.start,
      endDate: window.end,
      allDay: true,
      iosParams: const IOSParams(reminder: Duration(hours: 12)),
      androidParams: const AndroidParams(),
    );
  }
}

