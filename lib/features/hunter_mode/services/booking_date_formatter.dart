import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Pure date-resolution + date-range formatting helpers for booking + package
/// documents.
///
/// This is the single source of truth for how the hunt-window dates on a
/// booking (or the availability window on a package) are resolved and rendered
/// across every hunter / outfitter UI card, badge, and sheet.
///
/// The resolver is fully decoupled from any platform plugin / device calendar
/// integration — it is pure arithmetic over the raw document map and is
/// therefore unit-testable on the desktop test runner.
class BookingDateFormatter {
  BookingDateFormatter._();

  /// Resolves a [DateTime] (midnight, local) from a value that may be a
  /// Firestore [Timestamp], an ISO-8601 string, a [DateTime], or a `num`
  /// (milliseconds-since-epoch). Returns `null` for null / empty / unparseable
  /// input so a caller never throws on a missing or malformed date field.
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
      final parsed = DateTime.tryParse(trimmed);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    if (value is num) {
      final d = DateTime.fromMillisecondsSinceEpoch(value.toInt());
      return DateTime(d.year, d.month, d.day);
    }
    return null;
  }

  /// Exhaustive ordered list of date-field aliases the resolver accepts for
  /// the hunt START. Priority is top-to-bottom: a post-date-change-approval
  /// confirmed date wins, then the custom-package check-in, then the package
  /// availability window, then generic start/hunt fields. Both the canonical
  /// camelCase keys the app writes AND snake_case variants are accepted so a
  /// legacy / third-party-written doc can never defeat resolution purely on a
  /// key-spelling mismatch.
  static const List<String> startAliases = [
    'confirmedStartDate',
    'confirmed_start_date',
    'checkInDate',
    'check_in_date',
    'availabilityStart',
    'availability_start',
    'startDate',
    'start_date',
    'huntStart',
    'hunt_start',
    'huntDate',
    'hunt_date',
  ];

  /// Exhaustive ordered list of date-field aliases for the hunt END. Same
  /// rationale + priority mirroring [startAliases].
  static const List<String> endAliases = [
    'confirmedEndDate',
    'confirmed_end_date',
    'checkOutDate',
    'check_out_date',
    'availabilityEnd',
    'availability_end',
    'endDate',
    'end_date',
    'huntEnd',
    'hunt_end',
  ];

  /// Resolves the hunt start/end window from a booking (or package) document
  /// by scanning the exhaustive alias lists in priority order.
  ///
  /// **Dual-key guarantee**: this resolver treats `availabilityStart` and
  /// `startDate` (and `availabilityEnd` / `endDate`) as fully interchangeable.
  /// Whether the document is a booking (which carries BOTH key sets) or a
  /// package (which carries `availabilityStart`/`availabilityEnd`), the
  /// resolver finds the window under whichever alias is present.
  ///
  /// Returns `null` only when NO start alias resolves to a usable date. The
  /// end falls back to the start (single-day window) when no end alias
  /// resolves, so a one-day hunt always yields a valid window.
  ///
  /// The returned `end` is normalized to the start of the day *after* the
  /// hunt's final day so a caller rendering a range can subtract one day to
  /// display the real final hunt day.
  static ({DateTime start, DateTime end})? resolveWindow(
    Map<String, dynamic> booking,
  ) {
    DateTime? start;
    String? startKey;
    for (final alias in startAliases) {
      final resolved = resolveDate(booking[alias]);
      if (resolved != null) {
        start = resolved;
        startKey = alias;
        break;
      }
    }
    if (start == null) {
      debugPrint('[BookingDate] resolveWindow: no start date resolved. '
          'Scanned aliases (none matched): ${startAliases.join(", ")}. '
          'Raw booking keys: ${booking.keys.toList()}. '
          'Date-ish values: ${_dateishValues(booking)}.');
      return null;
    }
    DateTime? end;
    String? endKey;
    for (final alias in endAliases) {
      final resolved = resolveDate(booking[alias]);
      if (resolved != null) {
        end = resolved;
        endKey = alias;
        break;
      }
    }
    end ??= start; // Single-day window when no end alias resolves.
    final normalizedEnd =
        end.isBefore(start) ? start : DateTime(end.year, end.month, end.day);
    debugPrint('[BookingDate] resolveWindow: start=$start (key=$startKey), '
        'end=$end (key=$endKey) -> window ${DateTime(start.year, start.month, start.day)} '
        '.. ${normalizedEnd.add(const Duration(days: 1))}.');
    return (
      start: DateTime(start.year, start.month, start.day),
      end: normalizedEnd.add(const Duration(days: 1)),
    );
  }

  /// Returns a compact map of the booking's date-ish fields (non-null values
  /// under any of the start/end aliases) for the no-start-resolved debug log.
  static Map<String, dynamic> _dateishValues(Map<String, dynamic> booking) {
    final result = <String, dynamic>{};
    for (final alias in {...startAliases, ...endAliases}) {
      final v = booking[alias];
      if (v != null) result[alias] = v.toString();
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Date-range FORMATTING — the single source of truth for how hunt windows
  // + package availability windows render on every UI card / badge / sheet.
  //
  // Standard: `d MMM yyyy` (e.g. `21 Aug 2026`), joined by an en-dash for a
  // range (`21 Aug 2026 – 23 Aug 2026`). A single-day window renders as one
  // date (no spurious two-day range). Both the start and end ALWAYS carry the
  // full month + year, so a range that shares a month or year is never
  // clipped/ambiguous.
  // ─────────────────────────────────────────────────────────────────────

  /// The shared date formatter — `d MMM yyyy` (e.g. `21 Aug 2026`).
  static final DateFormat _dateFormatter = DateFormat('d MMM yyyy');

  /// Formats a single [date] as `d MMM yyyy` (e.g. `21 Aug 2026`).
  static String formatDate(DateTime date) => _dateFormatter.format(date);

  /// Formats a date range from a resolved [window] (the
  /// `({DateTime start, DateTime end})?` returned by [resolveWindow], where
  /// `end` is the calendar-exclusive day AFTER the hunt's final day).
  ///
  /// Returns `null` when [window] is null (no resolvable dates). For a
  /// single-day hunt (start == huntEnd) returns just the start date; for a
  /// multi-day hunt returns `start – end` with the real final hunt day
  /// (`window.end` minus 1 day).
  static String? formatWindow(
    ({DateTime start, DateTime end})? window,
  ) {
    if (window == null) return null;
    final huntEnd = window.end.subtract(const Duration(days: 1));
    if (window.start == huntEnd) return formatDate(window.start);
    return '${formatDate(window.start)} – ${formatDate(huntEnd)}';
  }

  /// Formats a date range from two raw [DateTime]s (e.g. a package's
  /// `availabilityStart` / `availabilityEnd`). Null-safe: a null [start]
  /// returns null; a null or pre-start [end] collapses to a single date.
  /// Use this for package-availability badges that don't run through
  /// [resolveWindow].
  static String? formatDateRange({
    required DateTime? start,
    DateTime? end,
  }) {
    if (start == null) return null;
    if (end == null || !end.isAfter(start)) return formatDate(start);
    if (start == end) return formatDate(start);
    return '${formatDate(start)} – ${formatDate(end)}';
  }
}
