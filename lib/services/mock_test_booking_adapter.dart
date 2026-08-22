import 'external_booking_adapter.dart';

/// A fully deterministic, offline availability adapter for testing and local
/// simulation.
///
/// Lets developers and outfitters exercise the live date-availability flow
/// end-to-end (settings connectivity test, hunter booking availability strip,
/// slot verify / hold) without contacting any live external API.
///
/// Determinism: the default [MockTestBookingAdapter.deterministic] factory
/// blocks a date iff a stable FNV-1a hash of `'<seedKey>|yyyy-MM-dd'` is
/// divisible by [blockEveryNthDay] — the same seed always yields the same
/// calendar, on every device and every run (Dart's `String.hashCode` is NOT
/// stable across runs, so a local hash is used instead). An explicit
/// [blockedDates] set may also be supplied for hand-crafted fixtures.
class MockTestBookingAdapter extends ExternalBookingAdapter {
  /// Explicitly blocked dates (normalized to local midnight). When non-null,
  /// the deterministic pattern is bypassed entirely.
  final Set<DateTime>? blockedDates;

  /// Seed for the deterministic blocked-day pattern.
  final String seedKey;

  /// One in every N days is blocked in the deterministic pattern.
  final int blockEveryNthDay;

  /// Whether the simulated endpoint reports itself reachable.
  final bool connectionHealthy;

  /// Slots successfully held during this adapter's lifetime.
  final List<({DateTime start, DateTime end, String? reference})> heldSlots =
      [];

  /// Calendar days blocked by successful holds (applies in both explicit and
  /// deterministic modes so a held slot becomes unavailable afterwards).
  final Set<DateTime> _heldDays = {};

  MockTestBookingAdapter({
    Set<DateTime>? blockedDates,
    this.seedKey = 'mock',
    this.blockEveryNthDay = 5,
    this.connectionHealthy = true,
  }) : blockedDates = blockedDates?.map(normalizeBookingDate).toSet();

  /// Deterministic simulator keyed by [seedKey] (e.g. the outfitter's feed
  /// URL or uid), so every run produces the same blocked calendar.
  factory MockTestBookingAdapter.deterministic({
    String seedKey = 'mock',
    int blockEveryNthDay = 5,
    bool connectionHealthy = true,
  }) {
    return MockTestBookingAdapter(
      seedKey: seedKey,
      blockEveryNthDay: blockEveryNthDay,
      connectionHealthy: connectionHealthy,
    );
  }

  @override
  ExternalBookingSystemType get systemType => ExternalBookingSystemType.mock;

  /// Stable FNV-1a 32-bit hash — deterministic across runs and platforms.
  static int stableHash(String input) {
    var hash = 0x811C9DC5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  bool _isBlocked(DateTime day) {
    if (_heldDays.contains(day)) return true;
    final explicit = blockedDates;
    if (explicit != null) return explicit.contains(day);
    final key = '$seedKey|'
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final every = blockEveryNthDay <= 0 ? 1 : blockEveryNthDay;
    return stableHash(key) % every == 0;
  }

  @override
  Future<bool> testConnection() async => connectionHealthy;

  @override
  Future<Set<DateTime>> fetchUnavailableDates({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final blocked = <DateTime>{};
    for (final day in bookingDaysInRange(rangeStart, rangeEnd)) {
      if (_isBlocked(day)) blocked.add(day);
    }
    return blocked;
  }

  @override
  Future<bool> verifySlot({
    required DateTime start,
    required DateTime end,
  }) async {
    for (final day in bookingDaysInRange(start, end)) {
      if (_isBlocked(day)) return false;
    }
    return true;
  }

  /// Holds the slot in-memory when it is free. Held slots become unavailable
  /// to subsequent [verifySlot] / [holdSlot] calls on this instance, so the
  /// simulated state machine behaves like a real ERP hold.
  @override
  Future<bool> holdSlot({
    required DateTime start,
    required DateTime end,
    String? reference,
  }) async {
    final free = await verifySlot(start: start, end: end);
    if (!free) return false;
    for (final day in bookingDaysInRange(start, end)) {
      _heldDays.add(day);
    }
    heldSlots.add((start: start, end: end, reference: reference));
    return true;
  }
}
