import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/external_booking_adapter.dart';
import '../services/booking_availability_service.dart';
import 'hunter_scaffold.dart';

/// Real-time, interactive date-slot availability strip for the hunter package
/// booking flow.
///
/// Queries BOTH the local JagSpoor booking state machine and the outfitter's
/// configured availability source (via [BookingAvailabilityService]):
///
/// - **Manual mode** — the outfitter hand-manages a blocked-date list in the
///   Farm Control Panel; hunters may select any date NOT explicitly blocked.
/// - **External ERP / iCal / Mock mode** — blocked dates are pulled live from
///   the connected integration (or the mock simulator).
///
/// When [onSelectionChanged] is supplied the strip is fully interactive:
/// tapping an available (green) day starts / extends a booking window (tap 1
/// = start, tap 2 = end, further taps restart); blocked (red) days are not
/// selectable. The selected [BookingDateSelection] is reported to the parent
/// so the booking flow submits the hunter-chosen hunt window.
class BookingAvailabilityStrip extends StatefulWidget {
  /// The outfitter whose availability is resolved.
  final String outfitterId;

  final ThemeController theme;

  /// First day of the strip (defaults to today).
  final DateTime? rangeStart;

  /// Number of calendar days rendered (defaults to 14).
  final int dayCount;

  /// Enables tap-to-select date windows and reports the selection.
  final ValueChanged<BookingDateSelection?>? onSelectionChanged;

  /// Optional pre-selected window start (e.g. the package's advertised
  /// availability start).
  final DateTime? initialStart;

  /// Optional pre-selected window end (e.g. the package's advertised
  /// availability end).
  final DateTime? initialEnd;

  /// Test seam: override the availability lookup (avoids Firestore + network
  /// in widget tests).
  final Future<BookingAvailability> Function()? availabilityLoader;

  const BookingAvailabilityStrip({
    super.key,
    required this.outfitterId,
    required this.theme,
    this.rangeStart,
    this.dayCount = 14,
    this.onSelectionChanged,
    this.initialStart,
    this.initialEnd,
    this.availabilityLoader,
  });

  @override
  State<BookingAvailabilityStrip> createState() =>
      _BookingAvailabilityStripState();
}

class _BookingAvailabilityStripState extends State<BookingAvailabilityStrip> {
  late Future<BookingAvailability> _future;

  /// The hunter-selected hunt window (null = no selection / render-only).
  DateTime? _selectionStart;
  DateTime? _selectionEnd;

  bool get _isSelectable => widget.onSelectionChanged != null;

  BookingDateSelection? get _selection {
    if (_selectionStart == null) return null;
    return BookingDateSelection.range(
      _selectionStart!,
      _selectionEnd ?? _selectionStart!,
    );
  }

  @override
  void initState() {
    super.initState();
    final start = normalizeBookingDate(widget.rangeStart ?? DateTime.now());
    final end = start.add(Duration(days: widget.dayCount - 1));
    _future = widget.availabilityLoader?.call() ??
        BookingAvailabilityService.instance.getAvailability(
          outfitterId: widget.outfitterId,
          rangeStart: start,
          rangeEnd: end,
        );
    if (widget.initialStart != null) {
      _selectionStart = normalizeBookingDate(widget.initialStart!);
      _selectionEnd = widget.initialEnd != null
          ? normalizeBookingDate(widget.initialEnd!)
          : _selectionStart;
    }
  }

  /// Handles a tap on a day slot when the strip is interactive.
  ///
  /// Tap 1 selects the window start; tap 2 selects the window end (any day
  /// after the start — an earlier tap restarts the window); a third tap
  /// restarts the window again. Blocked days cannot be selected.
  void _onDayTapped(DateTime day, BookingAvailability availability) {
    if (!_isSelectable) return;
    final normalized = normalizeBookingDate(day);
    if (!availability.isAvailable(normalized)) return;
    setState(() {
      if (_selectionStart == null ||
          (_selectionStart != null && _selectionEnd != null)) {
        // Start a fresh window.
        _selectionStart = normalized;
        _selectionEnd = null;
      } else if (normalized == _selectionStart) {
        // Tapping the start again turns it into a single-day window.
        _selectionEnd = normalized;
      } else if (normalized.isBefore(_selectionStart!)) {
        // Restart at the earlier day.
        _selectionStart = normalized;
        _selectionEnd = null;
      } else {
        _selectionEnd = normalized;
      }
    });
    widget.onSelectionChanged?.call(_selection);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_available_rounded,
                color: theme.accentColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'LIVE DATE AVAILABILITY',
                style: TextStyle(
                  color: HunterUi.subtitleColor(theme),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        if (_isSelectable) ...[
          const SizedBox(height: 4),
          Text(
            'Tap an available (green) start date, then an end date.',
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 10),
        FutureBuilder<BookingAvailability>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Checking live availability…',
                      style: TextStyle(
                        color: HunterUi.subtitleColor(theme),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return Text(
                'Live availability could not be checked — the outfitter '
                'confirms all dates on approval.',
                style: TextStyle(
                  color: HunterUi.subtitleColor(theme),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              );
            }
            final availability = snapshot.data!;
            final start =
                normalizeBookingDate(widget.rangeStart ?? DateTime.now());
            final days = List.generate(
              widget.dayCount,
              (i) => start.add(Duration(days: i)),
            );
            final blockedCount =
                days.where((d) => !availability.isAvailable(d)).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode indicator: tells the hunter where the availability
                // comes from (manual outfitter management vs. a live external
                // integration).
                Row(
                  children: [
                    Icon(
                      availability.isManualMode
                          ? Icons.edit_calendar_rounded
                          : Icons.sync_rounded,
                      size: 14,
                      color: theme.accentColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        availability.modeDescription,
                        style: TextStyle(
                          color: HunterUi.subtitleColor(theme),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: days.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) =>
                        _daySlot(days[i], availability, theme),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        blockedCount == 0
                            ? 'All dates shown are available.'
                            : '$blockedCount date(s) shown are unavailable '
                                '(local bookings + ${availability.isManualMode ? 'outfitter-managed dates' : 'external calendar'}).',
                        style: TextStyle(
                          color: blockedCount == 0
                              ? Colors.green
                              : Colors.amber.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!availability.externalReachable)
                      Tooltip(
                        message: 'External calendar unreachable — showing '
                            'local bookings only.',
                        child: Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: Colors.amber.shade700,
                        ),
                      ),
                  ],
                ),
                if (_isSelectable) ...[
                  const SizedBox(height: 6),
                  _selectionSummary(theme),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// Renders the current hunter-selected hunt window summary.
  Widget _selectionSummary(ThemeController theme) {
    final selection = _selection;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.date_range_rounded, size: 16, color: theme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              selection == null
                  ? 'No hunt window selected yet.'
                  : 'Selected: '
                      '${DateFormat('d MMM yyyy').format(selection.start)}'
                      '${selection.end == selection.start ? '' : ' – ${DateFormat('d MMM yyyy').format(selection.end)}'}'
                      ' (${selection.dayCount} day${selection.dayCount == 1 ? '' : 's'})',
              style: TextStyle(
                color: HunterUi.titleColor(theme),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (selection != null)
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectionStart = null;
                  _selectionEnd = null;
                });
                widget.onSelectionChanged?.call(null);
              },
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: HunterUi.subtitleColor(theme),
              ),
            ),
        ],
      ),
    );
  }

  Widget _daySlot(
    DateTime day,
    BookingAvailability availability,
    ThemeController theme,
  ) {
    final normalized = normalizeBookingDate(day);
    final available = availability.isAvailable(normalized);
    final isStart = _selectionStart == normalized;
    final isEnd = _selectionEnd == normalized;
    final inRange = _selectionStart != null &&
        _selectionEnd != null &&
        !normalized.isBefore(_selectionStart!) &&
        !normalized.isAfter(_selectionEnd!);
    final isSelected = isStart || isEnd;

    final baseColor = available ? Colors.green : Colors.red;
    final Color background;
    final Color border;
    final Color dayTextColor;
    final Color numberColor;
    if (isSelected) {
      // Selected endpoints: solid accent.
      background = theme.accentColor;
      border = theme.accentColor;
      dayTextColor = Colors.white;
      numberColor = Colors.white;
    } else if (inRange) {
      // Dates inside the selected window: accent wash.
      background = theme.accentColor.withValues(alpha: 0.35);
      border = theme.accentColor;
      dayTextColor = HunterUi.subtitleColor(theme);
      numberColor = theme.accentColor;
    } else {
      background = baseColor.withValues(alpha: 0.12);
      border = baseColor.withValues(alpha: 0.5);
      dayTextColor =
          available ? HunterUi.subtitleColor(theme) : Colors.red.shade700;
      numberColor = baseColor;
    }

    final slot = Container(
      width: 46,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: isSelected ? 2 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('EEE').format(day).toUpperCase(),
            style: TextStyle(
              color: dayTextColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${day.day}',
            style: TextStyle(
              color: numberColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    if (!_isSelectable) return slot;
    return GestureDetector(
      onTap: available ? () => _onDayTapped(day, availability) : null,
      child: slot,
    );
  }
}
