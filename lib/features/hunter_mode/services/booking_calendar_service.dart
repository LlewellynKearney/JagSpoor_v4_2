import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

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
///
/// The "Add Hunt to Calendar" button on the booking card resolves the hunt
/// window from the SAME raw booking map the UI card reads through
/// [BookingCalendarEventBuilder.resolveWindow]. When the booking document
/// itself does not carry the date fields (e.g. an older booking that did not
/// copy the package's availability at booking time), this service falls back
/// to the linked [packageId]'s `packages/{packageId}` document and re-resolves
/// the window from the package's `availabilityStart` / `availabilityEnd`
/// (plus the other supported date aliases) so the calendar action never
/// fails when the UI card is already displaying dates (or could).
class BookingCalendarService {
  BookingCalendarService._();

  static final BookingCalendarService instance = BookingCalendarService._();

  /// Test seam: inject a Firestore instance (e.g. `FakeFirebaseFirestore`)
  /// so the package-fallback fetch can be unit-tested without a live
  /// Firebase app. Defaults to the global instance.
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  FirebaseFirestore get _firestore =>
      firestoreForTesting ?? FirebaseFirestore.instance;

  /// Resolves the booking's [packageId], tolerating the `package_id` snake-
  /// case alias and the legacy `'CUSTOM_BUILT'` sentinel (which has no
  /// `packages` doc to fall back to -- returns null so the caller skips the
  /// fetch).
  static String? _resolvePackageId(Map<String, dynamic> booking) {
    final id = (booking['packageId'] as String?) ??
        (booking['package_id'] as String?) ??
        (booking['packageID'] as String?);
    if (id == null) return null;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    // Custom-built packages carry the sentinel 'CUSTOM_BUILT' -- there is no
    // `packages` doc to read, so do not attempt a fetch (it would 404).
    if (trimmed == 'CUSTOM_BUILT') return null;
    return trimmed;
  }

  /// Builds a native calendar [Event] from a raw booking document map.
  ///
  /// Returns `null` when the booking has no usable hunt window (no start
  /// date could be resolved from any of the supported field aliases) -- in
  /// that case the caller should surface a "no dates on file" message
  /// rather than launching an empty calendar event.
  ///
  /// This is the synchronous, package-fallback-FREE entry point. Use
  /// [buildEventWithPackageFallback] from the "Add to Calendar" action to
  /// also consult the linked package's availability dates when the booking
  /// document itself lacks date fields.
  Event? buildEvent(Map<String, dynamic> booking) {
    return BookingCalendarEventBuilder.buildEvent(booking);
  }

  /// Builds a native calendar [Event] from a raw booking document map,
  /// falling back to the linked package's availability window when the
  /// booking document itself carries no usable date fields.
  ///
  /// Resolution order:
  /// 1. [BookingCalendarEventBuilder.resolveWindow] on the raw booking map
  ///    (the SAME resolver the UI card uses, so the calendar event matches
  ///    the dates the hunter is already seeing on the card).
  /// 2. If (1) resolves -> build the event from the booking map.
  /// 3. If (1) is null AND the booking references a `packageId` -> fetch
  ///    `packages/{packageId}`, merge its date fields into a copy of the
  ///    booking map, and re-resolve. The event's title / description /
  ///    location still come from the booking (the package only contributes
  ///    dates), so the calendar entry stays tied to the booked trip.
  /// 4. Otherwise -> null (caller surfaces "no dates on file").
  Future<Event?> buildEventWithPackageFallback(
    Map<String, dynamic> booking,
  ) async {
    // (1) + (2): same resolver the UI card uses -> match the displayed dates.
    if (BookingCalendarEventBuilder.resolveWindow(booking) != null) {
      return BookingCalendarEventBuilder.buildEvent(booking);
    }
    // (3): fall back to the linked package's availability window.
    final packageId = _resolvePackageId(booking);
    if (packageId == null) return null;
    try {
      final doc = await _firestore.collection('packages').doc(packageId).get();
      if (!doc.exists) return null;
      final pkgData = doc.data() ?? const <String, dynamic>{};
      // Merge the package's date fields into a copy of the booking map so the
      // re-resolve picks them up. Booking fields take precedence (a
      // post-date-change confirmedStartDate on the booking wins over the
      // package's advertised availability), so package fields are only added
      // when the booking map does not already carry them.
      final merged = <String, dynamic>{...pkgData, ...booking};
      return BookingCalendarEventBuilder.buildEvent(merged);
    } catch (_) {
      // A Firestore error (offline / permissions / not-found) should not
      // crash the calendar action -- return null so the caller surfaces a
      // "no dates" message instead.
      return null;
    }
  }

  /// Builds the event (with the package fallback) and, when it resolves,
  /// hands it to `add_2_calendar` which opens the device's native calendar
  /// editor pre-populated with the hunt details. Returns whether a calendar
  /// event was launched (false when no dates could be resolved -- including
  /// the package fallback -- OR the calendar permission was denied -- OR the
  /// platform call rejected the event).
  ///
  /// **Runtime permission request**: on Android 6+ (API 23+) and iOS,
  /// calendar access is a "dangerous"/protected permission that requires a
  /// runtime grant in addition to the manifest/Info.plist declaration. This
  /// method requests `Permission.calendarFullAccess` (the non-deprecated
  /// successor to `Permission.calendar`; it covers BOTH `READ_CALENDAR` +
  /// `WRITE_CALENDAR` on Android and the iOS EKEventStore full-access
  /// entitlement) before handing off to `add_2_calendar`. If the permission
  /// is denied (or permanently denied), the method returns `false` so the
  /// caller surfaces its existing "Could not open your device calendar.
  /// Check that a calendar app is installed and permissions are granted."
  /// snackbar -- which accurately tells the user to grant the calendar
  /// permission rather than reporting a false-positive "no hunt dates"
  /// warning.
  ///
  /// The [booking] map is the SAME raw booking document the UI card reads
  /// through [BookingCalendarEventBuilder.resolveWindow], so the calendar
  /// event's dates match the dates displayed on the card. The package
  /// fallback guarantees the action never fails solely because the booking
  /// document did not copy the package's availability dates at booking time.
  Future<bool> addToCalendar(Map<String, dynamic> booking) async {
    final event = await buildEventWithPackageFallback(booking);
    if (event == null) return false;
    // Runtime calendar permission gate. Check the current status first; if
    // not already granted, issue a runtime request (mirrors the codebase's
    // license-scanner camera permission pattern).
    // `Permission.calendarFullAccess` maps to READ_CALENDAR +
    // WRITE_CALENDAR on Android (the manifest declares both) and the iOS
    // EKEventStore full-access entitlement. (The older
    // `Permission.calendar` is deprecated in permission_handler 11.x in
    // favour of `calendarFullAccess` / `calendarWriteOnly`; we use full
    // access because adding an event may require resolving the target
    // calendar before inserting.)
    var status = await Permission.calendarFullAccess.status;
    if (!status.isGranted) {
      status = await Permission.calendarFullAccess.request();
    }
    if (!status.isGranted) {
      // Permission denied (user declined the dialog, or permanently denied
      // -> they must grant from system settings). Returning false flows into
      // the caller's "Could not open your device calendar" snackbar, which
      // tells the user to check permissions -- the accurate UX.
      return false;
    }
    // Primary path: delegate to the `add_2_calendar` plugin's native
    // insertion. The plugin may return `false` (no calendar app could handle
    // the intent, or the insertion was rejected) or throw (a native
    // `SecurityException` / `ActivityNotFoundException` on Android 14/15/16
    // where the `content://com.android.calendar/events` content-provider
    // launch via `ACTION_VIEW` can be blocked without explicit authority
    // flags). On either failure, fall back to the web calendar so the hunter
    // can still save the trip.
    try {
      final launched = await Add2Calendar.addEvent2Cal(event);
      if (launched) return true;
      debugPrint('[BookingCalendar] Native addEvent2Cal returned false; '
          'falling back to web calendar.');
    } catch (e) {
      debugPrint('[BookingCalendar] Native addEvent2Cal threw: $e; '
          'falling back to web calendar.');
    }
    return _launchWebCalendarFallback(event);
  }

  /// Graceful secondary fallback when the native calendar insertion fails or
  /// is rejected (Android 14/15/16 may block the
  /// `content://com.android.calendar/events` content-provider launch via
  /// `ACTION_VIEW` without explicit authority flags). Builds a Google
  /// Calendar web "TEMPLATE" URL pre-filled with the event details and
  /// launches it in the external browser via `url_launcher`. The user lands
  /// on a pre-populated "New event" form they can save to any signed-in
  /// calendar account.
  ///
  /// Returns whether the browser hand-off succeeded. Any failure is logged
  /// and reported as `false` so the caller surfaces its existing failure
  /// snackbar instead of crashing.
  Future<bool> _launchWebCalendarFallback(Event event) async {
    try {
      // Construct a safe Google Calendar web URL with pre-filled event
      // details as a reliable fallback.
      final title = Uri.encodeComponent(event.title);
      final description = Uri.encodeComponent(event.description ?? '');
      final location = Uri.encodeComponent(event.location ?? '');
      // Google Calendar `dates` param: YYYYMMDDTHHMMSS / YYYYMMDDTHHMMSS (UTC
      // 'Z' suffix optional). Strip the separators from the ISO-8601 string.
      final startDate =
          event.startDate.toIso8601String().replaceAll(RegExp(r'[-:]|\.\d+'), '');
      final endDate =
          event.endDate.toIso8601String().replaceAll(RegExp(r'[-:]|\.\d+'), '');

      final url = Uri.parse(
        'https://calendar.google.com/calendar/render?action=TEMPLATE'
        '&text=$title&details=$description&location=$location'
        '&dates=$startDate/$endDate',
      );

      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[BookingCalendar] Web calendar fallback failed: $e');
      return false;
    }
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

  /// Exhaustive ordered list of date-field aliases the resolver accepts for
  /// the hunt START. Priority is top-to-bottom: a post-date-change-approval
  /// confirmed date wins, then the custom-package check-in, then the package
  /// availability window, then generic start/hunt fields. Both the canonical
  /// camelCase keys the app writes (`availabilityStart`, `startDate`,
  /// `checkInDate`, `huntStart`, `huntDate`) AND snake_case variants
  /// (`availability_start`, `start_date`, `check_in_date`, `hunt_start`)
  /// are accepted so a legacy / third-party-written doc can never defeat
  /// resolution purely on a key-spelling mismatch.
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

  /// Resolves the hunt start/end window from a booking (or merged package)
  /// document by scanning the exhaustive alias lists in priority order.
  ///
  /// **Dual-key guarantee**: this resolver treats `availabilityStart` and
  /// `startDate` (and `availabilityEnd` / `endDate`) as fully interchangeable.
  /// Whether the document is a booking (which carries BOTH key sets, written
  /// by `PackageBookingManager.bookPackage` / `submitCustomPackageBooking`)
  /// or a package (which carries `availabilityStart`/`availabilityEnd` from
  /// `PackagePricing.toMap`), the resolver finds the window under whichever
  /// alias is present. A booking that contains `availabilityStart` uses it
  /// as the start; a booking that contains `startDate` treats it identically.
  ///
  /// Returns `null` only when NO start alias resolves to a usable date -- in
  /// that case the caller surfaces a "no dates on file" message. The end
  /// falls back to the start (single-day window) when no end alias resolves,
  /// so a one-day hunt always yields a valid window.
  ///
  /// The returned `end` is normalized to the start of the day *after* the
  /// hunt's final day so the native calendar renders the full final day for
  /// an all-day event.
  ///
  /// Emits debug logs of the raw keys/values found so a "No hunt dates on
  /// file" can be diagnosed instantly from the device logs.
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
      debugPrint('[BookingCalendar] resolveWindow: no start date resolved. '
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
    debugPrint('[BookingCalendar] resolveWindow: start=$start (key=$startKey), '
        'end=$end (key=$endKey) -> window ${DateTime(start.year, start.month, start.day)} '
        '.. ${normalizedEnd.add(const Duration(days: 1))}.');
    return (
      start: DateTime(start.year, start.month, start.day),
      end: normalizedEnd.add(const Duration(days: 1)),
    );
  }

  /// Returns a compact map of the booking's date-ish fields (non-null values
  /// under any of the start/end aliases) for the no-start-resolved debug log
  /// so a developer can see exactly what date data IS present when the
  /// resolver fails.
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
  // date (no spurious two-day range, no "From" prefix). Both the start and
  // end ALWAYS carry the full month + year, so a range that shares a month
  // or year is never clipped/ambiguous (the prior numeric shorthand
  // `21/8 – 23/8/2026` omitted the month on the start + used bare numbers).
  // ─────────────────────────────────────────────────────────────────────

  /// The shared date formatter — `d MMM yyyy` (e.g. `21 Aug 2026`).
  static final DateFormat _dateFormatter = DateFormat('d MMM yyyy');

  /// Formats a single [date] as `d MMM yyyy` (e.g. `21 Aug 2026`).
  static String formatDate(DateTime date) => _dateFormatter.format(date);

  /// Formats a date range from a resolved [window] (the `({DateTime start,
  /// DateTime end})?` returned by [resolveWindow], where `end` is the
  /// calendar-exclusive day AFTER the hunt's final day).
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

