import 'package:http/http.dart' as http;

import 'external_booking_adapter.dart';

/// Fetches the raw text body of an iCal feed URL.
///
/// Injectable so tests exercise the real parsing pipeline without network
/// access (no HTTP mocks of the adapter itself).
typedef ICalFetch = Future<String> Function(Uri url);

/// Parses a standards-based iCalendar (RFC 5545) feed into the set of
/// blocked (unavailable) calendar dates.
///
/// Supported subset — the common availability-feed shapes exported by Google
/// Calendar, Airbnb, and lodge ERP systems:
/// - `BEGIN:VEVENT` … `END:VEVENT` blocks with `DTSTART` / `DTEND`.
/// - All-day dates (`DTSTART;VALUE=DATE:20260821`) and date-times
///   (`DTSTART:20260821T090000`, optional trailing `Z`; timezone parameters
///   are tolerated and the wall-clock date is used).
/// - RFC 5545 line unfolding (a continuation line begins with a space/tab).
///
/// Blocking semantics follow RFC 5545: `DTEND` on an all-day event is
/// EXCLUSIVE, so an event from 21–23 Aug blocks 21 + 22 Aug. A timed event
/// blocks every calendar day it spans. Recurrence rules (`RRULE`) are not
/// expanded; the base event window is used.
abstract final class ICalParser {
  static final RegExp _dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
  static final RegExp _dateTime =
      RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$');

  /// Parses [ics] text and returns every blocked calendar day (normalized to
  /// local midnight), optionally restricted to [rangeStart]..[rangeEnd]
  /// (inclusive).
  static Set<DateTime> parseBlockedDates(
    String ics, {
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) {
    final blocked = <DateTime>{};
    final lines = _unfold(ics);
    var inEvent = false;
    DateTime? eventStart;
    DateTime? eventEnd;

    void flushEvent() {
      final start = eventStart;
      if (start == null) return;
      // An event with no DTEND blocks its start day only; an all-day event's
      // DTEND is exclusive; a timed event spans to its end day inclusive.
      final end = eventEnd;
      final DateTime endDay;
      if (end == null) {
        endDay = normalizeBookingDate(start);
      } else if (_isAllDayRange(start, end)) {
        endDay = normalizeBookingDate(end).subtract(const Duration(days: 1));
      } else {
        endDay = normalizeBookingDate(end);
      }
      for (final day in bookingDaysInRange(start, endDay)) {
        blocked.add(day);
      }
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      final upper = line.toUpperCase();
      if (upper == 'BEGIN:VEVENT') {
        inEvent = true;
        eventStart = null;
        eventEnd = null;
        continue;
      }
      if (upper == 'END:VEVENT') {
        flushEvent();
        inEvent = false;
        continue;
      }
      if (!inEvent) continue;
      // Property name may carry parameters: DTSTART;VALUE=DATE:20260821
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).toUpperCase();
      final value = line.substring(colon + 1).trim();
      if (name == 'DTSTART' || name.startsWith('DTSTART;')) {
        eventStart = _parseDate(value);
      } else if (name == 'DTEND' || name.startsWith('DTEND;')) {
        eventEnd = _parseDate(value);
      }
    }
    if (inEvent) flushEvent(); // tolerate a truncated trailing VEVENT

    if (rangeStart == null || rangeEnd == null) return blocked;
    final startDay = normalizeBookingDate(rangeStart);
    final endDay = normalizeBookingDate(rangeEnd);
    return blocked
        .where((d) => !d.isBefore(startDay) && !d.isAfter(endDay))
        .toSet();
  }

  /// True when both values are midnight-normalized (an all-day event range).
  static bool _isAllDayRange(DateTime start, DateTime end) {
    return start.hour == 0 &&
        start.minute == 0 &&
        start.second == 0 &&
        end.hour == 0 &&
        end.minute == 0 &&
        end.second == 0;
  }

  /// RFC 5545 line unfolding: continuation lines start with a space or tab
  /// and are joined onto the previous logical line.
  static List<String> _unfold(String ics) {
    final logical = <String>[];
    for (final physical
        in ics.split(RegExp(r'\r\n|\r|\n'))) {
      if (physical.isEmpty) continue;
      if ((physical.startsWith(' ') || physical.startsWith('\t')) &&
          logical.isNotEmpty) {
        logical[logical.length - 1] += physical.substring(1);
      } else {
        logical.add(physical);
      }
    }
    return logical;
  }

  /// Parses a `DTSTART` / `DTEND` property value. Returns `null` when the
  /// value is not a recognizable date (the event is skipped, not fatal).
  static DateTime? _parseDate(String value) {
    final v = value.trim();
    var m = _dateOnly.firstMatch(v);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    m = _dateTime.firstMatch(v);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    }
    return null;
  }
}

/// Availability adapter backed by a standards-based iCalendar feed URL.
///
/// The feed is fetched over HTTPS and parsed on-device; blocked event dates
/// become unavailable booking dates. iCal feeds are read-only, so
/// [holdSlot] always returns `false` — holds must be placed through the
/// source calendar system itself.
class ICalBookingAdapter extends ExternalBookingAdapter {
  /// The iCal feed URL.
  final String feedUrl;

  /// How long a fetched feed is cached in memory before refetching.
  final Duration cacheTtl;

  final ICalFetch _fetcher;

  Set<DateTime>? _cachedBlocked;
  DateTime? _cachedAt;

  ICalBookingAdapter({
    required this.feedUrl,
    ICalFetch? fetcher,
    this.cacheTtl = const Duration(minutes: 2),
  }) : _fetcher = fetcher ?? _defaultFetch;

  @override
  ExternalBookingSystemType get systemType => ExternalBookingSystemType.ical;

  static Future<String> _defaultFetch(Uri url) async {
    final response = await http
        .get(url)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception(
        'iCal feed returned HTTP ${response.statusCode}',
      );
    }
    return response.body;
  }

  Future<Set<DateTime>> _loadBlocked({bool forceRefresh = false}) async {
    final cached = _cachedBlocked;
    final at = _cachedAt;
    if (!forceRefresh &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < cacheTtl) {
      return cached;
    }
    final body = await _fetcher(Uri.parse(feedUrl));
    final blocked = ICalParser.parseBlockedDates(body);
    _cachedBlocked = blocked;
    _cachedAt = DateTime.now();
    return blocked;
  }

  @override
  Future<bool> testConnection() async {
    try {
      final body = await _fetcher(Uri.parse(feedUrl));
      return body.toUpperCase().contains('BEGIN:VCALENDAR');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Set<DateTime>> fetchUnavailableDates({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final blocked = await _loadBlocked();
    final startDay = normalizeBookingDate(rangeStart);
    final endDay = normalizeBookingDate(rangeEnd);
    return blocked
        .where((d) => !d.isBefore(startDay) && !d.isAfter(endDay))
        .toSet();
  }

  @override
  Future<bool> verifySlot({
    required DateTime start,
    required DateTime end,
  }) async {
    final blocked = await _loadBlocked();
    for (final day in bookingDaysInRange(start, end)) {
      if (blocked.contains(day)) return false;
    }
    return true;
  }

  /// iCal feeds are read-only — a hold cannot be written back through a
  /// `.ics` URL. Always returns `false`; place holds through the source
  /// calendar system.
  @override
  Future<bool> holdSlot({
    required DateTime start,
    required DateTime end,
    String? reference,
  }) async {
    return false;
  }
}
