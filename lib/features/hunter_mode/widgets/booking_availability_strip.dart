import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/external_booking_adapter.dart';
import '../services/booking_availability_service.dart';
import 'hunter_scaffold.dart';

/// Real-time date-slot availability strip for the hunter package booking
/// flow.
///
/// Queries BOTH the local JagSpoor booking state machine and the outfitter's
/// configured external booking / ERP availability service (via
/// [BookingAvailabilityService]) and renders the next [dayCount] calendar
/// days as green (available) / red (unavailable) date slots, so the hunter
/// sees live availability before submitting a booking request.
class BookingAvailabilityStrip extends StatefulWidget {
  /// The outfitter whose availability is resolved.
  final String outfitterId;

  final ThemeController theme;

  /// First day of the strip (defaults to today).
  final DateTime? rangeStart;

  /// Number of calendar days rendered (defaults to 14).
  final int dayCount;

  /// Test seam: override the availability lookup (avoids Firestore + network
  /// in widget tests).
  final Future<BookingAvailability> Function()? availabilityLoader;

  const BookingAvailabilityStrip({
    super.key,
    required this.outfitterId,
    required this.theme,
    this.rangeStart,
    this.dayCount = 14,
    this.availabilityLoader,
  });

  @override
  State<BookingAvailabilityStrip> createState() =>
      _BookingAvailabilityStripState();
}

class _BookingAvailabilityStripState extends State<BookingAvailabilityStrip> {
  late Future<BookingAvailability> _future;

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
                                '(local bookings + external calendar).',
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
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _daySlot(
    DateTime day,
    BookingAvailability availability,
    ThemeController theme,
  ) {
    final available = availability.isAvailable(day);
    final color = available ? Colors.green : Colors.red;
    return Container(
      width: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('EEE').format(day).toUpperCase(),
            style: TextStyle(
              color: available
                  ? HunterUi.subtitleColor(theme)
                  : Colors.red.shade700,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${day.day}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
