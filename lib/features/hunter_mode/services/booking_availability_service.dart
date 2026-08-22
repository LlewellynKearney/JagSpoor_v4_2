import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../services/external_booking_adapter.dart';
import '../models/booking_status.dart';
import 'booking_date_formatter.dart';

/// The merged real-time availability of one outfitter over a date range.
class BookingAvailability {
  /// The outfitter this availability belongs to.
  final String outfitterId;

  /// Unavailable dates contributed by the outfitter-managed source: the
  /// manual blocked-date list in `manual` mode, or the external ERP /
  /// calendar adapter in `ical` / `mock` mode.
  final Set<DateTime> externalBlockedDates;

  /// Unavailable dates contributed by the local JagSpoor booking state
  /// machine (caller-visible active bookings with this outfitter).
  final Set<DateTime> localBlockedDates;

  /// The system type the outfitter configured (`manual` when none).
  final ExternalBookingSystemType systemType;

  /// Whether the external source was reachable this fetch. Always `true`
  /// for `manual` (the manual blocked-date list is local) and for the mock
  /// simulator's healthy default.
  final bool externalReachable;

  const BookingAvailability({
    required this.outfitterId,
    required this.externalBlockedDates,
    required this.localBlockedDates,
    required this.systemType,
    required this.externalReachable,
  });

  /// Union of every blocked date across both sources.
  Set<DateTime> get blockedDates =>
      {...externalBlockedDates, ...localBlockedDates};

  bool isAvailable(DateTime day) =>
      !blockedDates.contains(normalizeBookingDate(day));

  /// Human-readable description of the active sync mode, surfaced in the
  /// hunter booking flow so the hunter knows where the availability comes
  /// from.
  String get modeDescription {
    switch (systemType) {
      case ExternalBookingSystemType.manual:
        return 'Manually managed by the outfitter';
      case ExternalBookingSystemType.ical:
        return 'Live external calendar (iCal) sync';
      case ExternalBookingSystemType.mock:
        return 'Mock availability simulator';
    }
  }

  /// Whether the availability source is the outfitter's manual date list
  /// (`true`) or a live external integration (`false`).
  bool get isManualMode => systemType == ExternalBookingSystemType.manual;
}

/// An inclusive hunt-window selection made by the hunter on the interactive
/// booking availability strip. Both endpoints are midnight-normalized and
/// [end] is never before [start].
class BookingDateSelection {
  final DateTime start;
  final DateTime end;

  BookingDateSelection({required DateTime start, DateTime? end})
      : start = normalizeBookingDate(start),
        end = normalizeBookingDate(end ?? start);

  /// Creates a selection with the endpoints ordered (end >= start).
  factory BookingDateSelection.range(DateTime a, DateTime b) {
    final first = normalizeBookingDate(a);
    final second = normalizeBookingDate(b);
    return second.isBefore(first)
        ? BookingDateSelection(start: second, end: first)
        : BookingDateSelection(start: first, end: second);
  }

  /// Every calendar day covered by the selection (inclusive).
  Iterable<DateTime> get days => bookingDaysInRange(start, end);

  /// The number of calendar days covered (inclusive).
  int get dayCount => end.difference(start).inDays + 1;

  @override
  String toString() =>
      'BookingDateSelection(${bookingDateKey(start)} -> ${bookingDateKey(end)})';
}

/// Resolves an outfitter's real-time date availability by merging the local
/// JagSpoor booking state machine with the outfitter's configured external
/// booking / ERP adapter (iCal feed, mock simulator, or none).
///
/// Configuration is persisted on the outfitter's `users/{uid}` document under
/// the `bookingSync` key — the `users` Firestore rules allow the owner to
/// write it and any signed-in user (e.g. a hunter viewing the package) to
/// read it, so no rules change is required for the availability lookup.
///
/// Security note: the `bookings` collection is party-readable only, so the
/// local-state contribution intentionally covers the caller-visible bookings
/// (a hunter's own bookings with the outfitter; ALL bookings when the caller
/// IS the outfitter). Cross-hunter blocking is the responsibility of the
/// outfitter's external calendar (the iCal feed contains their real
/// bookings), which is exactly why the external sync exists.
class BookingAvailabilityService {
  BookingAvailabilityService._({
    this.firestoreForTesting,
    this.currentUserIdResolverForTesting,
    this.adapterFactoryForTesting,
  });

  static final BookingAvailabilityService _instance =
      BookingAvailabilityService._();
  static BookingAvailabilityService get instance => _instance;

  /// Test seam: inject a Firestore instance (e.g. `FakeFirebaseFirestore`).
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  /// Test seam: inject a uid resolver so the caller-scope logic is
  /// unit-testable without a signed-in user.
  @visibleForTesting
  String? Function()? currentUserIdResolverForTesting;

  /// Test seam: override adapter construction (avoids any network access).
  @visibleForTesting
  ExternalBookingAdapter? Function(ExternalBookingConfig config)?
      adapterFactoryForTesting;

  FirebaseFirestore get _firestore =>
      firestoreForTesting ?? FirebaseFirestore.instance;

  String? get _currentUserId {
    if (currentUserIdResolverForTesting != null) {
      return currentUserIdResolverForTesting!();
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  factory BookingAvailabilityService.forTesting({
    required FirebaseFirestore firestore,
    String? Function()? currentUserIdResolver,
    ExternalBookingAdapter? Function(ExternalBookingConfig config)?
        adapterFactory,
  }) {
    return BookingAvailabilityService._(
      firestoreForTesting: firestore,
      currentUserIdResolverForTesting: currentUserIdResolver,
      adapterFactoryForTesting: adapterFactory,
    );
  }

  ExternalBookingAdapter? _adapterFor(ExternalBookingConfig config) {
    final factory = adapterFactoryForTesting;
    if (factory != null) return factory(config);
    return ExternalBookingAdapters.fromConfig(config);
  }

  /// Loads the outfitter's persisted booking-sync configuration.
  Future<ExternalBookingConfig> loadConfig(String outfitterId) async {
    final doc =
        await _firestore.collection('users').doc(outfitterId).get();
    if (!doc.exists) return ExternalBookingConfig.manualDefault;
    return ExternalBookingConfig.fromUserDoc(doc.data());
  }

  /// Persists the signed-in outfitter's booking-sync configuration onto their
  /// own `users/{uid}` document (owner-writable per the Firestore rules).
  Future<void> saveConfig(ExternalBookingConfig config) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User must be authenticated to save booking sync');
    }
    await _firestore.collection('users').doc(uid).set({
      'bookingSync': config.toMap(),
      'bookingSyncUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Merges the local booking state machine with the outfitter-managed
  /// availability source over the inclusive range [rangeStart]..[rangeEnd].
  ///
  /// Mode-specific behaviour:
  /// - `manual`: the outfitter's hand-managed blocked-date list
  ///   ([ExternalBookingConfig.manualBlockedDates]) IS the outfitter source —
  ///   hunters may pick any date the outfitter has NOT explicitly blocked.
  /// - `ical` / `mock`: the connected external integration (or the mock
  ///   simulator) is queried live for blocked dates.
  ///
  /// In BOTH modes the local JagSpoor booking state machine is merged on
  /// top so already-booked dates are always unavailable; switching the
  /// outfitter between Manual and an external integration therefore
  /// restrictively re-enables or re-restricts the hunter's selectable
  /// dates accordingly.
  Future<BookingAvailability> getAvailability({
    required String outfitterId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final config = await _safeLoadConfig(outfitterId);

    var externalBlocked = <DateTime>{};
    var externalReachable = true;
    if (config.systemType == ExternalBookingSystemType.manual) {
      // Manual mode: the outfitter's own blocked-date list IS the source.
      // Dates already in the past or outside the range are still flagged
      // (harmless for the strip, keeps the model honest).
      externalBlocked = config.manualBlockedDates;
    } else {
      final adapter = _adapterFor(config);
      if (adapter != null) {
        try {
          externalBlocked = await adapter.fetchUnavailableDates(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
          );
        } catch (e) {
          debugPrint('[BookingAvailability] external fetch failed: $e');
          externalReachable = false;
        }
      }
    }

    final localBlocked = await _fetchLocalBlockedDates(
      outfitterId: outfitterId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );

    return BookingAvailability(
      outfitterId: outfitterId,
      externalBlockedDates: externalBlocked,
      localBlockedDates: localBlocked,
      systemType: config.systemType,
      externalReachable: externalReachable,
    );
  }

  /// Verifies the full inclusive slot [start]..[end] against BOTH the local
  /// booking state machine and the outfitter's external availability source.
  Future<bool> verifySlot({
    required String outfitterId,
    required DateTime start,
    required DateTime end,
  }) async {
    final availability = await getAvailability(
      outfitterId: outfitterId,
      rangeStart: start,
      rangeEnd: end,
    );
    for (final day in bookingDaysInRange(start, end)) {
      if (!availability.isAvailable(day)) return false;
    }
    return true;
  }

  Future<ExternalBookingConfig> _safeLoadConfig(String outfitterId) async {
    try {
      return await loadConfig(outfitterId);
    } catch (e) {
      debugPrint('[BookingAvailability] config load failed: $e');
      return ExternalBookingConfig.manualDefault;
    }
  }

  /// Local JagSpoor state machine: dates occupied by active bookings with
  /// this outfitter that the caller may legitimately read.
  ///
  /// The `bookings` rules are party-scoped, so the caller sees:
  /// - the outfitter themselves  -> every booking they own;
  /// - a hunter                    -> their own bookings with the outfitter.
  Future<Set<DateTime>> _fetchLocalBlockedDates({
    required String outfitterId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final uid = _currentUserId;
    if (uid == null) return <DateTime>{};

    final blocked = <DateTime>{};
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('bookings')
          .where('outfitterId', isEqualTo: outfitterId);
      if (uid != outfitterId) {
        query = query.where('hunterId', isEqualTo: uid);
      }
      final snapshot = await query.get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = BookingStatus.normalize(data['status'] as String?);
        // Terminal states free their dates again.
        if (status == BookingStatus.declined ||
            status == BookingStatus.cancelled ||
            status == BookingStatus.completed) {
          continue;
        }
        final window = BookingDateFormatter.resolveWindow(data);
        if (window == null) continue;
        // `window.end` is calendar-exclusive (the day AFTER the final hunt
        // day), so the occupied span ends the day before it.
        final occupiedEnd =
            window.end.subtract(const Duration(days: 1));
        for (final day in bookingDaysInRange(window.start, occupiedEnd)) {
          if (day.isBefore(normalizeBookingDate(rangeStart)) ||
              day.isAfter(normalizeBookingDate(rangeEnd))) {
            continue;
          }
          blocked.add(day);
        }
      }
    } catch (e) {
      debugPrint('[BookingAvailability] local bookings fetch failed: $e');
    }
    return blocked;
  }
}
