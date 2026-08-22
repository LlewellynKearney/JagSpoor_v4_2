import 'ical_booking_adapter.dart';
import 'mock_test_booking_adapter.dart';

/// The external booking / ERP system an outfitter uses to manage their live
/// availability calendar outside JagSpoor.
enum ExternalBookingSystemType {
  /// No external system — availability is managed manually inside JagSpoor
  /// (the local booking state machine is the only source of truth).
  manual,

  /// A standards-based iCalendar (`.ics`) feed URL (e.g. the outfitter's
  /// Google Calendar / Airbnb / lodge ERP availability export). Read-only.
  ical,

  /// A fully deterministic built-in simulator for testing and local
  /// development — no live external API is contacted.
  mock,
}

/// Classification of the external booking / ERP system an outfitter uses.
extension ExternalBookingSystemTypeX on ExternalBookingSystemType {
  String get id {
    switch (this) {
      case ExternalBookingSystemType.manual:
        return 'manual';
      case ExternalBookingSystemType.ical:
        return 'ical';
      case ExternalBookingSystemType.mock:
        return 'mock';
    }
  }

  String get label {
    switch (this) {
      case ExternalBookingSystemType.manual:
        return 'Manual (JagSpoor only)';
      case ExternalBookingSystemType.ical:
        return 'iCal Feed URL';
      case ExternalBookingSystemType.mock:
        return 'Mock Test (offline simulator)';
    }
  }

  static ExternalBookingSystemType fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'ical':
      case 'icalendar':
      case 'ics':
        return ExternalBookingSystemType.ical;
      case 'mock':
      case 'mock_test':
      case 'mocktest':
      case 'test':
        return ExternalBookingSystemType.mock;
      case 'manual':
      default:
        return ExternalBookingSystemType.manual;
    }
  }
}

/// The persisted booking-sync configuration for one outfitter.
///
/// Stored on the outfitter's `users/{uid}` document under the `bookingSync`
/// key (the `users` rules allow owner writes + signed-in reads, so an
/// outfitter manages their own config and a signed-in hunter can read it to
/// resolve live availability during booking).
class ExternalBookingConfig {
  final ExternalBookingSystemType systemType;

  /// The iCal feed URL (only meaningful when [systemType] is
  /// [ExternalBookingSystemType.ical]) or the mock simulator's seed key.
  final String feedUrl;

  /// The unavailable (blocked) calendar dates the outfitter manages by hand
  /// (only meaningful when [systemType] is
  /// [ExternalBookingSystemType.manual]). Dates are normalized to local
  /// midnight. Every non-listed date is bookable.
  final Set<DateTime> manualBlockedDates;

  const ExternalBookingConfig({
    this.systemType = ExternalBookingSystemType.manual,
    this.feedUrl = '',
    this.manualBlockedDates = const {},
  });

  static const ExternalBookingConfig manualDefault = ExternalBookingConfig();

  factory ExternalBookingConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return manualDefault;
    return ExternalBookingConfig(
      systemType: ExternalBookingSystemTypeX.fromString(
        (map['type'] ?? map['systemType']) as String?,
      ),
      feedUrl: (map['feedUrl'] as String? ?? '').trim(),
      manualBlockedDates: _parseManualBlockedDates(
        map['manualBlockedDates'],
      ),
    );
  }

  /// Parses the persisted `manualBlockedDates` list (ISO `yyyy-MM-dd`
  /// strings) into midnight-normalized [DateTime]s. Tolerates null / empty /
  /// malformed entries (they are skipped rather than throwing).
  static Set<DateTime> _parseManualBlockedDates(dynamic raw) {
    if (raw is! List) return const {};
    return raw
        .whereType<String>()
        .map(parseBookingDateKey)
        .whereType<DateTime>()
        .toSet();
  }

  /// Reads the `bookingSync` nested map off a raw `users/{uid}` document.
  factory ExternalBookingConfig.fromUserDoc(Map<String, dynamic>? userDoc) {
    final raw = userDoc?['bookingSync'];
    if (raw is Map) {
      return ExternalBookingConfig.fromMap(Map<String, dynamic>.from(raw));
    }
    return manualDefault;
  }

  Map<String, dynamic> toMap() => {
        'type': systemType.id,
        'feedUrl': feedUrl,
        'manualBlockedDates': manualBlockedDates
            .map(bookingDateKey)
            .toList()
          ..sort(),
      };

  ExternalBookingConfig copyWith({
    ExternalBookingSystemType? systemType,
    String? feedUrl,
    Set<DateTime>? manualBlockedDates,
  }) {
    return ExternalBookingConfig(
      systemType: systemType ?? this.systemType,
      feedUrl: feedUrl ?? this.feedUrl,
      manualBlockedDates: manualBlockedDates ?? this.manualBlockedDates,
    );
  }
}

/// Normalizes a [DateTime] to local midnight (year/month/day) so date-level
/// availability comparisons are time-of-day independent.
DateTime normalizeBookingDate(DateTime d) => DateTime(d.year, d.month, d.day);

/// Formats a [DateTime] as an ISO `yyyy-MM-dd` date key (the persistence
/// shape for manually blocked dates).
String bookingDateKey(DateTime d) {
  final day = normalizeBookingDate(d);
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

/// Parses an ISO `yyyy-MM-dd` date key back to a midnight-normalized
/// [DateTime]. Returns `null` for null / malformed input.
DateTime? parseBookingDateKey(String? raw) {
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return null;
  return normalizeBookingDate(parsed);
}

/// Enumerates every calendar day in the inclusive range [start]..[end],
/// normalized to local midnight. Returns an empty iterable when
/// [end] is before [start].
Iterable<DateTime> bookingDaysInRange(DateTime start, DateTime end) sync* {
  var day = normalizeBookingDate(start);
  final last = normalizeBookingDate(end);
  while (!day.isAfter(last)) {
    yield day;
    day = day.add(const Duration(days: 1));
  }
}

/// Abstract contract for an external booking / ERP availability source.
///
/// Implementations translate an external availability system (an iCal feed, a
/// lodge ERP API, or a deterministic test simulator) into the date-level
/// availability model JagSpoor's booking flow consumes.
abstract class ExternalBookingAdapter {
  const ExternalBookingAdapter();

  /// The system this adapter talks to.
  ExternalBookingSystemType get systemType;

  /// Tests live connectivity to the external system. Returns `true` when the
  /// endpoint is reachable and yields a usable response.
  Future<bool> testConnection();

  /// Fetches the set of unavailable (blocked / booked) calendar dates within
  /// the inclusive range [rangeStart]..[rangeEnd]. Dates are normalized to
  /// local midnight.
  Future<Set<DateTime>> fetchUnavailableDates({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  });

  /// Verifies that every calendar day in the inclusive range [start]..[end]
  /// is available (no overlap with blocked dates).
  Future<bool> verifySlot({required DateTime start, required DateTime end});

  /// Attempts to place a hold on the inclusive slot [start]..[end].
  ///
  /// Returns `true` when the hold was accepted. Read-only systems (iCal
  /// feeds) cannot hold slots and return `false`; holds must then be placed
  /// through the source system itself.
  Future<bool> holdSlot({
    required DateTime start,
    required DateTime end,
    String? reference,
  });
}

/// Builds the concrete adapter for a persisted [ExternalBookingConfig].
///
/// Returns `null` for the `manual` system type (no external source) and for
/// an `ical` config without a feed URL.
abstract final class ExternalBookingAdapters {
  static ExternalBookingAdapter? fromConfig(
    ExternalBookingConfig config, {
    ICalFetch? fetcher,
  }) {
    switch (config.systemType) {
      case ExternalBookingSystemType.manual:
        return null;
      case ExternalBookingSystemType.ical:
        if (config.feedUrl.isEmpty) return null;
        return ICalBookingAdapter(feedUrl: config.feedUrl, fetcher: fetcher);
      case ExternalBookingSystemType.mock:
        return MockTestBookingAdapter.deterministic(
          seedKey: config.feedUrl.isEmpty ? 'mock' : config.feedUrl,
        );
    }
  }
}
