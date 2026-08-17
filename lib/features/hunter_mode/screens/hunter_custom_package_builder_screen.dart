import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/booking_status.dart';
import '../models/farm_game_price_entry.dart';
import '../models/farm_service_rate.dart';
import '../services/booking_calendar_service.dart';
import '../services/farm_game_price_list_manager.dart';
import '../widgets/booking_chat_thread.dart';

/// Hunter **Custom Package Builder** form.
///
/// Reached from [CustomPackageFarmSelectionScreen] with a farm + its outfitter
/// id. Lets the hunter assemble a custom itinerary by browsing the farm's
/// published game price list (`farm_pricelists` -- species + per-unit ZAR) and
/// itemized service rates (`farm_service_rates` -- bakkie / slaughtering /
/// coldroom / daily / accommodation / catering fees), selecting quantities,
/// and submitting a booking request.
///
/// The builder:
/// - Streams the farm's species price list + service rates reactively (so a
///   newly-added species or rate appears without a reload).
/// - Renders species rows with sex/class + horn/tusk badges and a quantity
///   stepper (capped at the outfitter's `qty`).
/// - Renders itemized service rows with the per-category unit semantics
///   ("Per vehicle per day", "Per night", etc.) and a quantity stepper.
/// - Computes a grand total = Σ(qty × unit price). There is no platform
///   commission / markup, so the hunter sees the base booking cost with no
///   "Platform Fee" row.
/// - On submit writes a `bookings` document with `isCustomPackage: true` and
///   `status: BookingStatus.pendingApproval`, then switches to a confirmation
///   view that embeds the standard [BookingChatThread] for negotiation and an
///   "ADD HUNT TO CALENDAR" button once the booking transitions to Confirmed /
///   Completed -- matching the Package Marketplace booking workflow exactly.
class HunterCustomPackageBuilderScreen extends StatefulWidget {
  final ThemeController theme;

  /// Farm the custom package is being built against.
  final String farmId;
  final String farmName;

  /// Outfitter who owns the farm / price list.
  final String outfitterId;

  const HunterCustomPackageBuilderScreen({
    super.key,
    required this.theme,
    required this.farmId,
    required this.farmName,
    required this.outfitterId,
  });

  @override
  State<HunterCustomPackageBuilderScreen> createState() =>
      _HunterCustomPackageBuilderScreenState();
}

class _HunterCustomPackageBuilderScreenState
    extends State<HunterCustomPackageBuilderScreen> {
  final FarmGamePriceListManager _priceListManager =
      FarmGamePriceListManager.instance;

  // Form state.
  DateTime? _checkIn;
  DateTime? _checkOut;
  int _hunterCount = 1;
  int _observerCount = 0;

  // Item rows (species) + fee rows (itemized services), each with qty.
  final Map<String, int> _quantities = {}; // keyed by stable row id
  List<FarmGamePriceEntry> _speciesItems = const [];
  List<FarmServiceRate> _feeItems = const [];

  // Submission state.
  bool _isSubmitting = false;
  String? _createdBookingId; // when set, switches to confirmation view
  // Cached booking document for the confirmation view (so the calendar +
  // status badge can render without re-fetching). Refreshed by the booking
  // stream subscription below once the booking is created.
  Map<String, dynamic>? _bookingDoc;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bookingSub;

  @override
  void initState() {
    super.initState();
    // The farm's price list + service rates are streamed reactively through
    // the manager's hunter-readable getters (no owner-scoped filter).
  }

  @override
  void dispose() {
    _bookingSub?.cancel();
    super.dispose();
  }

  double _unitPriceSpecies(FarmGamePriceEntry e) => e.priceZAR;
  double _unitPriceRate(FarmServiceRate r) => r.pricePerUnit;

  int _qty(String rowId) => _quantities[rowId] ?? 0;

  void _setQty(String rowId, int value) {
    setState(() {
      if (value <= 0) {
        _quantities.remove(rowId);
      } else {
        _quantities[rowId] = value;
      }
    });
  }

  double get _grandTotal {
    double total = 0;
    for (final e in _speciesItems) {
      final qty = _qty(_speciesRowId(e));
      if (qty > 0) total += _unitPriceSpecies(e) * qty;
    }
    for (final r in _feeItems) {
      final qty = _qty(_feeRowId(r));
      if (qty > 0) total += _unitPriceRate(r) * qty;
    }
    return total;
  }

  int get _totalLineCount {
    var n = 0;
    for (final e in _speciesItems) {
      if (_qty(_speciesRowId(e)) > 0) n++;
    }
    for (final r in _feeItems) {
      if (_qty(_feeRowId(r)) > 0) n++;
    }
    return n;
  }

  int get _huntingDays {
    if (_checkIn == null || _checkOut == null) return 0;
    final diff = _checkOut!.difference(_checkIn!).inDays;
    return diff > 0 ? diff : 0;
  }

  String _formatZAR(double value) =>
      'R ${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  static String _speciesRowId(FarmGamePriceEntry e) => 'sp_${e.id}';
  static String _feeRowId(FarmServiceRate r) => 'fee_${r.key}';

  List<Map<String, dynamic>> _collectSelectedSpecies() {
    final out = <Map<String, dynamic>>[];
    for (final e in _speciesItems) {
      final qty = _qty(_speciesRowId(e));
      if (qty <= 0) continue;
      final unit = _unitPriceSpecies(e);
      out.add({
        'name': e.speciesName,
        'displayLabel': e.speciesName,
        'speciesName': e.speciesName,
        'sex': e.gender,
        'sexLabel': e.gender,
        'hornTuskLength': e.hornTuskLength,
        'itemType': 'species',
        'feeType': null,
        'quantity': qty,
        'unitPriceHunterZAR': unit,
        'lineTotal': unit * qty,
        'outfitterBasePrice': unit,
        'hunterDisplayPriceZAR': unit,
        'quantityLimit': e.qty > 0 ? e.qty : null,
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _collectSelectedFees() {
    final out = <Map<String, dynamic>>[];
    for (final r in _feeItems) {
      final qty = _qty(_feeRowId(r));
      if (qty <= 0) continue;
      final unit = _unitPriceRate(r);
      out.add({
        'name': r.label,
        'displayLabel': r.label,
        'itemType': 'fee',
        'feeType': r.key,
        'feeUnitLabel': r.unitLabel,
        'quantityNoun': r.quantityNoun,
        'quantity': qty,
        'unitPriceHunterZAR': unit,
        'lineTotal': unit * qty,
        'outfitterBasePrice': unit,
        'hunterDisplayPriceZAR': unit,
      });
    }
    return out;
  }

  Future<void> _submitBooking() async {
    if (_totalLineCount == 0) {
      _showError('Please add at least one species or service line.');
      return;
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showError('Please log in to continue');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final selectedItems = _collectSelectedSpecies();
      final lodgingCatering = _collectSelectedFees();
      final total = _grandTotal;

      final bookingId = await _priceListManager.submitCustomPackageBooking(
        farmId: widget.farmId,
        farmName: widget.farmName,
        outfitterId: widget.outfitterId,
        pricelistId: 'farm_pricelists:${widget.farmId}',
        selectedItems: selectedItems,
        lodgingCatering: lodgingCatering,
        combinedTotalZAR: total,
        checkInDate: _checkIn != null ? _toIsoDate(_checkIn!) : null,
        checkOutDate: _checkOut != null ? _toIsoDate(_checkOut!) : null,
        huntingDays: _huntingDays,
        hunterCount: _hunterCount,
        observerCount: _observerCount,
      );

      if (mounted) {
        setState(() {
          _createdBookingId = bookingId;
          _isSubmitting = false;
        });
        // Subscribe to the booking doc so the confirmation view can render the
        // live status badge + surface the calendar button the instant the
        // outfitter confirms the direct payment.
        _bookingSub = FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .snapshots()
            .listen((snap) {
          if (!mounted) return;
          if (snap.exists) {
            final data = Map<String, dynamic>.from(snap.data() ?? const {});
            data['id'] = snap.id;
            setState(() => _bookingDoc = data);
          }
        });
        _showSuccess('Custom package request sent to the outfitter.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError('Failed to submit booking: $e');
      }
    }
  }

  String _toIsoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isCheckIn}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isCheckIn ? _checkIn : _checkOut) ??
          (isCheckIn ? now : (_checkIn ?? now)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = picked;
        if (_checkOut != null && _checkOut!.isBefore(picked)) {
          _checkOut = picked;
        }
      } else {
        _checkOut = picked;
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  /// Saves the finalized (Confirmed / Completed) booking's hunt dates, farm
  /// details, and package title to the device's native calendar via
  /// [BookingCalendarService]. Mirrors the marketplace's calendar hook.
  Future<void> _addToCalendar() async {
    final booking = _bookingDoc;
    if (booking == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched = await BookingCalendarService.instance.addToCalendar(booking);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(launched
              ? 'Hunt added to your calendar — check your calendar app.'
              : 'No hunt dates on file for this booking — the outfitter must '
                'confirm the dates first.'),
          backgroundColor: launched ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open calendar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _canAddToCalendar() {
    final status = (_bookingDoc?['status'] as String?)?.toLowerCase() ?? '';
    return status == 'confirmed' || status == 'completed';
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.farmName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: _createdBookingId == null
          ? _buildBuilderView(theme)
          : _buildConfirmationView(theme),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: CopyrightFooter.tight(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  BUILDER VIEW (species + service rates + dates + party + submit)
  // ---------------------------------------------------------------------------

  Widget _buildBuilderView(ThemeController theme) {
    return StreamBuilder<List<FarmGamePriceEntry>>(
      stream: _priceListManager.getFarmPriceListStreamForHunter(widget.farmId),
      builder: (context, speciesSnapshot) {
        return StreamBuilder<FarmServiceRates>(
          stream: _priceListManager.getFarmServiceRatesStream(widget.farmId),
          builder: (context, ratesSnapshot) {
            // Loading state: either stream is still awaiting its first
            // emission with no data yet. Without this branch the screen
            // renders blank (the builder's Column is empty) until the first
            // snapshot arrives -- which previously looked like a permanently
            // blank screen when a stream hung on a missing composite index.
            final speciesLoading =
                speciesSnapshot.connectionState == ConnectionState.waiting &&
                    !speciesSnapshot.hasData;
            final ratesLoading =
                ratesSnapshot.connectionState == ConnectionState.waiting &&
                    !ratesSnapshot.hasData;
            if (speciesLoading || ratesLoading) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: theme.accentColor),
                      const SizedBox(height: 16),
                      Text(
                        'Loading farm price list...',
                        style: TextStyle(
                            color: theme.subtitleColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (speciesSnapshot.hasError || ratesSnapshot.hasError) {
              return _StateBanner(
                icon: Icons.cloud_off,
                message: 'Could not load this farm\'s price list.',
                detail: '${speciesSnapshot.error ?? ratesSnapshot.error}',
                theme: theme,
              );
            }
            _speciesItems = speciesSnapshot.data ?? const [];
            final rates = ratesSnapshot.data;
            _feeItems = rates?.configuredRates ?? const [];

            if (_speciesItems.isEmpty && _feeItems.isEmpty) {
              return _StateBanner(
                icon: Icons.price_check_outlined,
                message: 'No pricing published yet',
                detail: 'This farm has not published a game price list or '
                    'service rates yet. Please check back later or contact '
                    'the outfitter.',
                theme: theme,
              );
            }

            return _buildBuilderBody(theme);
          },
        );
      },
    );
  }

  Widget _buildBuilderBody(ThemeController theme) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, SafeBottomInset.of(context)),
      children: [
        _buildDatesCard(theme),
        const SizedBox(height: 12),
        _buildPartyCard(theme),
        const SizedBox(height: 20),
        if (_speciesItems.isNotEmpty) ...[
          _sectionHeader(theme, 'Game Species & Trophies', Icons.pets_rounded),
          const SizedBox(height: 8),
          for (final e in _speciesItems)
            _SpeciesQtyRow(
              entry: e,
              qty: _qty(_speciesRowId(e)),
              unitPrice: _unitPriceSpecies(e),
              onChanged: (v) => _setQty(_speciesRowId(e), v),
              theme: theme,
            ),
          const SizedBox(height: 20),
        ],
        if (_feeItems.isNotEmpty) ...[
          _sectionHeader(theme, 'Itemized Service Rates',
              Icons.room_service_rounded),
          const SizedBox(height: 8),
          for (final r in _feeItems)
            _FeeQtyRow(
              rate: r,
              qty: _qty(_feeRowId(r)),
              unitPrice: _unitPriceRate(r),
              onChanged: (v) => _setQty(_feeRowId(r), v),
              theme: theme,
            ),
          const SizedBox(height: 20),
        ],
        _buildSubmitCard(theme),
      ],
    );
  }

  Widget _buildDatesCard(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(theme, 'Hunt Window', Icons.event_rounded),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  theme,
                  label: 'Check-in',
                  value: _checkIn,
                  onTap: () => _pickDate(isCheckIn: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateButton(
                  theme,
                  label: 'Check-out',
                  value: _checkOut,
                  onTap: () => _pickDate(isCheckIn: false),
                ),
              ),
            ],
          ),
          if (_huntingDays > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$_huntingDays hunting day${_huntingDays != 1 ? 's' : ''}',
                style: TextStyle(
                    color: theme.subtitleColor, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateButton(ThemeController theme,
      {required String label, DateTime? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: theme.subtitleColor, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              value == null
                  ? 'Select date'
                  : _toIsoDate(value),
              style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyCard(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(theme, 'Party Size', Icons.groups_rounded),
          const SizedBox(height: 10),
          _partyStepper(theme,
              label: 'Hunters', value: _hunterCount, min: 1,
              onChanged: (v) => setState(() => _hunterCount = v)),
          const SizedBox(height: 8),
          _partyStepper(theme,
              label: 'Observers', value: _observerCount, min: 0,
              onChanged: (v) => setState(() => _observerCount = v)),
        ],
      ),
    );
  }

  Widget _partyStepper(ThemeController theme,
      {required String label,
      required int value,
      required int min,
      required ValueChanged<int> onChanged}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(color: theme.textColor, fontSize: 14)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _roundBtn(theme, Icons.remove_rounded,
                onTap: value > min ? () => onChanged(value - 1) : null),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('$value',
                  style: TextStyle(
                      color: theme.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            _roundBtn(theme, Icons.add_rounded,
                onTap: () => onChanged(value + 1)),
          ],
        ),
      ],
    );
  }

  Widget _roundBtn(ThemeController theme, IconData icon,
      {required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: onTap != null
              ? theme.accentColor.withValues(alpha: 0.15)
              : theme.accentColor.withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: onTap != null ? theme.accentColor : theme.subtitleColor,
            size: 18),
      ),
    );
  }

  Widget _sectionHeader(ThemeController theme, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: theme.accentColor, size: 18),
        const SizedBox(width: 8),
        Text(label.toUpperCase(),
            style: TextStyle(
                color: theme.accentColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0)),
      ],
    );
  }

  Widget _buildSubmitCard(ThemeController theme) {
    final total = _grandTotal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_totalLineCount line${_totalLineCount != 1 ? 's' : ''} · '
                      '$_hunterCount hunter${_hunterCount != 1 ? 's' : ''}'
                      '${_observerCount > 0 ? ' · $_observerCount observer${_observerCount != 1 ? 's' : ''}' : ''}',
                      style: TextStyle(
                          color: theme.subtitleColor, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Grand Total (incl. all fees):',
                      style: TextStyle(
                          color: theme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Text(
                _formatZAR(total),
                style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_totalLineCount == 0 || _isSubmitting)
                  ? null
                  : _submitBooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentColor,
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    theme.accentColor.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2),
                    )
                  : const Text(
                      'Submit Custom Package Request',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  CONFIRMATION VIEW (chat + status + calendar — marketplace parity)
  // ---------------------------------------------------------------------------

  Widget _buildConfirmationView(ThemeController theme) {
    final status =
        (_bookingDoc?['status'] as String?) ?? BookingStatus.pendingApproval;
    final canAddToCalendar = _canAddToCalendar();
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, SafeBottomInset.of(context)),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _statusColor(status, theme).withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: _statusColor(status, theme), size: 48),
              const SizedBox(height: 12),
              Text(
                'Request Submitted!',
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Your custom package request for ${widget.farmName} has been '
                'sent to the outfitter for review. Use the chat below to '
                'negotiate details and arrange payment.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.subtitleColor, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(status, theme).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  BookingStatus.hunterBadgeLabel(status).toUpperCase(),
                  style: TextStyle(
                      color: _statusColor(status, theme),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Embedded hunter↔outfitter chat thread (negotiation), matching the
        // marketplace booking card's chat drawer.
        BookingChatThread(
          bookingId: _createdBookingId!,
          theme: theme,
          senderName: 'Hunter',
          initiallyExpanded: true,
        ),
        const SizedBox(height: 12),
        if (canAddToCalendar)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _addToCalendar,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.event_available_rounded, size: 20),
              label: const Text(
                'ADD HUNT TO CALENDAR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        if (!canAddToCalendar)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Once the outfitter confirms your direct payment, an "Add to '
              'Calendar" button will appear here so you can save the hunt '
              'dates to your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context)
                .popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_rounded),
            label: const Text('BACK TO DASHBOARD'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.accentColor,
              side: BorderSide(color: theme.accentColor),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Color _statusColor(String status, ThemeController theme) {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'completed':
        return Colors.green.shade700;
      case 'awaiting payment':
      case 'approved':
        return Colors.amber.shade700;
      case 'declined':
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return theme.accentColor;
    }
  }
}

/// A game-species price-list line row with a quantity stepper + per-line
/// total. The unit price is the farm's published per-animal ZAR (no platform
/// commission), so no separate fee row appears.
class _SpeciesQtyRow extends StatelessWidget {
  final FarmGamePriceEntry entry;
  final int qty;
  final double unitPrice;
  final ValueChanged<int> onChanged;
  final ThemeController theme;

  const _SpeciesQtyRow({
    required this.entry,
    required this.qty,
    required this.unitPrice,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final name = entry.speciesName;
    final isSelected = qty > 0;
    final lineTotal = unitPrice * qty;
    final limit = entry.qty > 0 ? entry.qty : null;
    final atLimit = limit != null && qty >= limit;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.accentColor
              : theme.textColor.withValues(alpha: 0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (entry.gender != 'Any' || entry.hornTuskLength.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (entry.gender != 'Any') _metaChip(theme, entry.gender),
                      if (entry.hornTuskLength.isNotEmpty)
                        _metaChip(theme, entry.hornTuskDisplayLabel),
                      if (limit != null) _metaChip(theme, 'max $limit'),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'R ${unitPrice.toStringAsFixed(0)} / animal'
                  '${qty > 0 ? '  ·  line R ${lineTotal.toStringAsFixed(0)}' : ''}',
                  style: TextStyle(
                      color: isSelected ? theme.accentColor : theme.subtitleColor,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _qtyStepper(theme, qty: qty, atLimit: atLimit, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _metaChip(ThemeController theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: theme.subtitleColor, fontSize: 10),
      ),
    );
  }

  Widget _qtyStepper(ThemeController theme,
      {required int qty, required bool atLimit, required ValueChanged<int> onChanged}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(theme, Icons.remove_rounded,
            onTap: qty > 0 ? () => onChanged(qty - 1) : null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '$qty',
            style: TextStyle(
                color: theme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
        ),
        _btn(theme, Icons.add_rounded,
            onTap: atLimit ? null : () => onChanged(qty + 1)),
      ],
    );
  }

  Widget _btn(ThemeController theme, IconData icon, {required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: onTap != null
              ? theme.accentColor.withValues(alpha: 0.15)
              : theme.accentColor.withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: onTap != null ? theme.accentColor : theme.subtitleColor,
            size: 18),
      ),
    );
  }
}

/// An itemized service-rate line row (bakkie / slaughtering / coldroom / daily
/// / accommodation / catering) with a quantity stepper + per-line total.
class _FeeQtyRow extends StatelessWidget {
  final FarmServiceRate rate;
  final int qty;
  final double unitPrice;
  final ValueChanged<int> onChanged;
  final ThemeController theme;

  const _FeeQtyRow({
    required this.rate,
    required this.qty,
    required this.unitPrice,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = qty > 0;
    final lineTotal = unitPrice * qty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.accentColor
              : theme.textColor.withValues(alpha: 0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rate.label,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${rate.unitLabel} · ${rate.quantityNoun}',
                  style: TextStyle(
                      color: theme.subtitleColor, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  'R ${unitPrice.toStringAsFixed(0)} / unit'
                  '${qty > 0 ? '  ·  line R ${lineTotal.toStringAsFixed(0)}' : ''}',
                  style: TextStyle(
                      color: isSelected ? theme.accentColor : theme.subtitleColor,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(theme, Icons.remove_rounded,
                  onTap: qty > 0 ? () => onChanged(qty - 1) : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('$qty',
                    style: TextStyle(
                        color: theme.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              _btn(theme, Icons.add_rounded, onTap: () => onChanged(qty + 1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(ThemeController theme, IconData icon, {required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: onTap != null
              ? theme.accentColor.withValues(alpha: 0.15)
              : theme.accentColor.withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: onTap != null ? theme.accentColor : theme.subtitleColor,
            size: 18),
      ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({
    required this.icon,
    required this.message,
    required this.detail,
    required this.theme,
  });
  final IconData icon;
  final String message;
  final String detail;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.subtitleColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.subtitleColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

