import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/booking_status.dart';
import '../models/farm_details.dart';
import '../models/farm_game_price_entry.dart';
import '../models/farm_service_rate.dart';
import '../services/booking_availability_service.dart';
import '../services/farm_game_price_list_manager.dart';
import '../widgets/booking_availability_strip.dart';
import '../widgets/photo_gallery_strip.dart';
import '../widgets/hunter_scaffold.dart';

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
///   view matching the Package Marketplace booking workflow exactly.
class HunterCustomPackageBuilderScreen extends StatefulWidget {
  final ThemeController theme;

  /// Farm the custom package is being built against.
  final String farmId;

  /// Full farm snapshot (name / location / size / contact / photos). Used to
  /// render the farm header panel at the top of the builder page.
  final FarmDetails farmDetails;

  /// Outfitter who owns the farm / price list.
  final String outfitterId;

  /// Convenience accessor: the farm's display name (legacy callers used
  /// `farmName`).
  String get farmName => farmDetails.displayName;

  /// Test seam: override the availability lookup of the embedded
  /// [BookingAvailabilityStrip] (avoids Firestore + network in widget tests).
  final Future<BookingAvailability> Function()? availabilityLoader;

  const HunterCustomPackageBuilderScreen({
    super.key,
    required this.theme,
    required this.farmId,
    required this.farmDetails,
    required this.outfitterId,
    this.availabilityLoader,
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

  /// The hunt window the hunter picked on the interactive availability
  /// strip. A submission CANNOT proceed without a selection — this is the
  /// required date-selection mechanism (the strip respects the outfitter's
  /// manual blackout dates / external ERP integration in real time).
  BookingDateSelection? _selectedWindow;

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

  // Stable streams cached once in initState. The manager's stream getters
  // build a FRESH OfflineStreamGuard broadcast controller + a FRESH Firestore
  // .snapshots() subscription on EVERY call, so calling them inline inside
  // build() (as the previous version did) re-created both streams on every
  // State rebuild (e.g. each qty-stepper setState). The outer StreamBuilder's
  // builder returns an INNER StreamBuilder whose `stream` was also re-created
  // each outer emission, so the inner StreamBuilder re-subscribed -> reset to
  // ConnectionState.waiting -> the loading guard fired -> a re-build loop that
  // never let the screen settle on real data (and on some device / timing
  // combos left the body painting nothing visible between AppBar and footer).
  // Caching the streams stabilises the StreamBuilders so they stay subscribed
  // for the screen's lifetime (the documented project pattern -- see
  // ballistic_calc_screen / scope_tools_bottom_sheet). They are re-assignable
  // (not `final`) so the error-state RETRY action can re-subscribe on demand.
  late Stream<List<FarmGamePriceEntry>> _speciesStream;
  late Stream<FarmServiceRates> _ratesStream;

  @override
  void initState() {
    super.initState();
    // Cache the streams once so build() never re-creates them. Both getters
    // are hunter-readable (no owner-scoped filter) and null-uid-safe (return
    // Stream.empty() / Stream.value(empty) for an unauthenticated caller).
    _initStreams();
  }

  void _initStreams() {
    _speciesStream =
        _priceListManager.getFarmPriceListStreamForHunter(widget.farmId);
    _ratesStream = _priceListManager.getFarmServiceRatesStream(widget.farmId);
  }

  /// Re-subscribes both price-list streams after a stream error surfaced in
  /// the error-state banner. Rebuilding the streams (fresh `.snapshots()`
  /// subscriptions) + `setState` lets the `StreamBuilder`s retry cleanly.
  void _retryStreams() {
    setState(_initStreams);
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
        'hornTuskUnit': e.hornTuskUnit,
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

  /// The outfitter id this custom package is booked against. Prefers the id
  /// resolved by the farm-selection screen; falls back to the `outfitterId`
  /// stamped on the streamed `farm_pricelists` entries themselves (every
  /// price-list doc carries it) so a stale/blank farm-card id never produces
  /// an orphaned booking the outfitter cannot see.
  String _resolvedOutfitterId() {
    if (widget.outfitterId.isNotEmpty) return widget.outfitterId;
    for (final entry in _speciesItems) {
      if (entry.outfitterId.isNotEmpty) return entry.outfitterId;
    }
    return '';
  }

  Future<void> _submitBooking() async {
    if (_totalLineCount == 0) {
      _showError('Please add at least one species or service line.');
      return;
    }
    // Gate: the hunter MUST pick the hunt window on the interactive
    // availability strip (the submit button is disabled without one; this
    // guard is defense-in-depth).
    final selection = _selectedWindow;
    if (selection == null) {
      _showError('Please select your hunt dates on the availability strip.');
      return;
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showError('Please log in to continue');
      return;
    }
    final outfitterId = _resolvedOutfitterId();
    if (outfitterId.isEmpty) {
      _showError('This farm\'s price list does not identify its outfitter. '
          'Please go back and re-select the farm.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // Verify the SELECTED hunt window against BOTH the local booking state
      // machine and the outfitter's availability source (manual
      // outfitter-managed dates or the external integration). A conflict does
      // not hard-block (the outfitter's approval is the real gate), but the
      // hunter is warned before submitting.
      final slotFree = await BookingAvailabilityService.instance.verifySlot(
        outfitterId: outfitterId,
        start: selection.start,
        end: selection.end,
      );
      if (!slotFree && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: HunterUi.cardColor(widget.theme),
            title: Text(
              'Date Conflict Detected',
              style: TextStyle(color: HunterUi.titleColor(widget.theme)),
            ),
            content: Text(
              'Some dates in the selected hunt window are already '
              'unavailable (local bookings or the outfitter\'s availability '
              'calendar). Submit the booking request anyway?',
              style: TextStyle(color: HunterUi.subtitleColor(widget.theme)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('SUBMIT ANYWAY'),
              ),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _isSubmitting = false);
          return;
        }
      }

      final selectedItems = _collectSelectedSpecies();
      final lodgingCatering = _collectSelectedFees();
      final total = _grandTotal;

      final bookingId = await _priceListManager.submitCustomPackageBooking(
        farmId: widget.farmId,
        farmName: widget.farmName,
        outfitterId: outfitterId,
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

  /// Handles the hunter's tap-selection on the interactive availability
  /// strip: stores the [BookingDateSelection] and mirrors it onto the
  /// check-in / check-out dates written onto the booking document.
  void _onWindowSelected(BookingDateSelection? selection) {
    setState(() {
      _selectedWindow = selection;
      _checkIn = selection?.start;
      _checkOut = selection?.end;
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

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    // Guard: an empty/blank farmId means the route args are invalid (deep
    // link, stale farm card, direct navigation). Never subscribe to the
    // price-list streams; show a clear error + a way back instead of a
    // blank screen.
    if (widget.farmId.isEmpty) {
      return _buildInvalidFarmScaffold(theme);
    }
    return HunterScaffold(
      theme: theme,
      appBar: AppBar(
        title: Text(
          widget.farmName.isEmpty ? 'Custom Package Builder' : widget.farmName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: HunterUi.titleColor(theme),
        elevation: 0,
        actions: [
          AppInfoIconButton(
            screenKey: AppScreenHelpScripts.hunterCustomPackageBuilder,
            iconColor: theme.accentColor,
          ),
        ],
      ),
      body: SafeArea(
        top: true,
        child: _createdBookingId == null
            ? _buildBuilderView(theme)
            : _buildConfirmationView(theme),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: CopyrightFooter.tight(),
      ),
    );
  }

  /// Full-screen error state for an invalid (empty / blank) [farmId]. Shows a
  /// clear message and a way back to the farm-selection list instead of a
  /// blank loading screen.
  Widget _buildInvalidFarmScaffold(ThemeController theme) {
    return HunterScaffold(
      theme: theme,
      appBar: AppBar(
        title: const Text(
          'Custom Package Builder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: HunterUi.titleColor(theme),
        elevation: 0,
        actions: [
          AppInfoIconButton(
            screenKey: AppScreenHelpScripts.hunterCustomPackageBuilder,
            iconColor: theme.accentColor,
          ),
        ],
      ),
      body: SafeArea(
        top: true,
        child: _StateBanner(
          icon: Icons.error_outline_rounded,
          message: 'Invalid farm reference',
          detail: 'The selected farm could not be identified. Return to the '
              'farm list and choose a valid farm to build a custom package.',
          theme: theme,
          actionLabel: 'BACK TO FARM SELECTION',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      ),
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
      stream: _speciesStream,
      builder: (context, speciesSnapshot) {
        return StreamBuilder<FarmServiceRates>(
          stream: _ratesStream,
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
              return _LoadingView(theme: theme);
            }
            if (speciesSnapshot.hasError || ratesSnapshot.hasError) {
              return _StateBanner(
                icon: Icons.cloud_off,
                message: 'Could not load this farm\'s price list.',
                detail: '${speciesSnapshot.error ?? ratesSnapshot.error}',
                theme: theme,
                actionLabel: 'RETRY',
                onAction: _retryStreams,
                secondaryActionLabel: 'BACK TO FARM SELECTION',
                onSecondaryAction: () => Navigator.of(context).maybePop(),
              );
            }
            _speciesItems = speciesSnapshot.data ?? const [];
            final rates = ratesSnapshot.data;
            _feeItems = rates?.configuredRates ?? const [];

            if (_speciesItems.isEmpty && _feeItems.isEmpty) {
              return _StateBanner(
                icon: Icons.price_check_outlined,
                message: 'No price lists published for this farm yet',
                detail: 'The outfitter has not published any game prices or '
                    'service rates for this farm yet. Please check back '
                    'later or contact the outfitter.',
                theme: theme,
                actionLabel: 'BACK TO FARM SELECTION',
                onAction: () => Navigator.of(context).maybePop(),
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
        _buildFarmHeader(theme),
        const SizedBox(height: 16),
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

  /// Prominent farm header shown at the top of the builder page: the farm's
  /// full photo gallery (every photo the outfitter uploaded at registration,
  /// tap to view full screen) plus the farm detail chips (province,
  /// district / town, size, contact number, registration number).
  Widget _buildFarmHeader(ThemeController theme) {
    final farm = widget.farmDetails;
    final chips = farm.infoChips;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HunterUi.cardColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.agriculture_rounded,
                  color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  farm.displayName,
                  style: TextStyle(
                    color: HunterUi.titleColor(theme),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (icon, label) in chips)
                  _farmChip(theme, icon, label),
              ],
            ),
          ],
          if (farm.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            PhotoGalleryStrip(
              urls: farm.photoUrls,
              theme: theme,
              height: 170,
            ),
          ],
        ],
      ),
    );
  }

  Widget _farmChip(ThemeController theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.accentColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: HunterUi.subtitleColor(theme), fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// The hunt-window card: the interactive live availability strip is the
  /// REQUIRED date-selection mechanism. It renders real-time available date
  /// slots respecting the outfitter's manual blackout dates (manual mode) or
  /// the connected external ERP / iCal / mock integration, merged with the
  /// local JagSpoor booking state machine. The hunter taps an available
  /// (green) start date + an end date; blocked (red) days are not
  /// selectable. The custom package request cannot be submitted until a
  /// window is selected.
  Widget _buildDatesCard(ThemeController theme) {
    // The strip resolves availability against the outfitter's booking-sync
    // config; prefer the route arg, fall back to the price-list-stamped id
    // (the same resolution the submit path uses).
    final outfitterId = widget.outfitterId.isNotEmpty
        ? widget.outfitterId
        : _resolvedOutfitterId();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HunterUi.cardColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(theme, 'Hunt Window', Icons.event_rounded),
          const SizedBox(height: 4),
          Text(
            'Required — pick your hunting dates below.',
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          if (outfitterId.isEmpty)
            Text(
              'Live availability is unavailable until this farm\'s outfitter '
              'can be identified.',
              style: TextStyle(
                color: HunterUi.subtitleColor(theme),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            BookingAvailabilityStrip(
              outfitterId: outfitterId,
              theme: theme,
              // 28 days so multi-week hunts fit in the strip.
              dayCount: 28,
              availabilityLoader: widget.availabilityLoader,
              onSelectionChanged: _onWindowSelected,
            ),
          if (_huntingDays > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$_huntingDays hunting day${_huntingDays != 1 ? 's' : ''} '
                'selected (${_toIsoDate(_checkIn!)} → ${_toIsoDate(_checkOut!)})',
                style: TextStyle(
                    color: HunterUi.subtitleColor(theme), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPartyCard(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HunterUi.cardColor(theme),
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
              style: TextStyle(color: HunterUi.titleColor(theme), fontSize: 14)),
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
                      color: HunterUi.titleColor(theme),
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
            color: onTap != null ? theme.accentColor : HunterUi.subtitleColor(theme),
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
        color: HunterUi.cardColor(theme),
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
                          color: HunterUi.subtitleColor(theme), fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Grand Total (incl. all fees):',
                      style: TextStyle(
                          color: HunterUi.titleColor(theme),
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
          // The hunt-window selection is REQUIRED: the submit button stays
          // disabled until the hunter picks dates on the availability strip.
          if (_totalLineCount > 0 && _selectedWindow == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded,
                      size: 14, color: Colors.amber.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Select your hunt dates on the availability strip above '
                      'to enable submission.',
                      style: TextStyle(
                        color: Colors.amber.shade700,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_totalLineCount == 0 ||
                      _isSubmitting ||
                      _selectedWindow == null)
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
  //  CONFIRMATION VIEW (status — marketplace parity)
  // ---------------------------------------------------------------------------

  Widget _buildConfirmationView(ThemeController theme) {
    final status =
        (_bookingDoc?['status'] as String?) ?? BookingStatus.pendingApproval;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, SafeBottomInset.of(context)),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HunterUi.cardColor(theme),
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
                    color: HunterUi.titleColor(theme),
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Your custom package request for ${widget.farmName} has been '
                'sent to the outfitter for review. Use the contact details on '
                'your booking card to arrange payment directly with the outfitter.',
                textAlign: TextAlign.center,
                style: TextStyle(color: HunterUi.subtitleColor(theme), fontSize: 13),
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
        color: HunterUi.cardColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.accentColor
              : HunterUi.titleColor(theme).withValues(alpha: 0.1),
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
                    color: HunterUi.titleColor(theme),
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
                      color: isSelected ? theme.accentColor : HunterUi.subtitleColor(theme),
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
        style: TextStyle(color: HunterUi.subtitleColor(theme), fontSize: 10),
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
                color: HunterUi.titleColor(theme),
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
            color: onTap != null ? theme.accentColor : HunterUi.subtitleColor(theme),
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
        color: HunterUi.cardColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.accentColor
              : HunterUi.titleColor(theme).withValues(alpha: 0.1),
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
                    color: HunterUi.titleColor(theme),
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${rate.unitLabel} · ${rate.quantityNoun}',
                  style: TextStyle(
                      color: HunterUi.subtitleColor(theme), fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  'R ${unitPrice.toStringAsFixed(0)} / unit'
                  '${qty > 0 ? '  ·  line R ${lineTotal.toStringAsFixed(0)}' : ''}',
                  style: TextStyle(
                      color: isSelected ? theme.accentColor : HunterUi.subtitleColor(theme),
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
                        color: HunterUi.titleColor(theme),
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
            color: onTap != null ? theme.accentColor : HunterUi.subtitleColor(theme),
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
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });
  final IconData icon;
  final String message;
  final String detail;
  final ThemeController theme;

  /// Optional primary action (e.g. 'BACK TO FARM SELECTION' / 'RETRY').
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional secondary (text) action rendered below the primary one.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: HunterUi.subtitleColor(theme)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: HunterUi.titleColor(theme),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: HunterUi.subtitleColor(theme), fontSize: 13),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null)
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(
                  secondaryActionLabel!,
                  style: TextStyle(color: HunterUi.subtitleColor(theme)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Loading state for the builder view. Rendered while either reactive stream
/// is still awaiting its first emission (and has no data yet). Extracted to a
/// dedicated widget so the loading branch is a single, always-visible,
/// always-`Center`-painted widget -- never an empty `Container` / `SizedBox`
/// that could leave the body blank between the AppBar and the footer.
class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.theme});
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
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
              style: TextStyle(color: HunterUi.subtitleColor(theme), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

