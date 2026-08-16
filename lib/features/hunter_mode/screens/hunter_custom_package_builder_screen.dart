import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../../core/services/payfast_checkout.dart';
import '../models/farm_config.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../services/pricelist_scanner_service.dart';
import '../widgets/booking_chat_thread.dart';

/// Hunter **Custom Package Builder** form.
///
/// Reached from [CustomPackageFarmSelectionScreen] with a farm + its active
/// scanned price list. Lets the hunter assemble a custom itinerary:
/// - Check-in / Check-out dates (+ derived hunting days).
/// - Number of hunters and observers.
/// - Species / trophies pulled directly from the farm's price list (with
///   sex/class and a quantity stepper).
/// - Lodging / catering / vehicle fee lines from the same price list.
///
/// All per-item prices use the price list's `hunterDisplayPriceZAR`, which
/// equals the item's base price (there is no platform commission / markup).
/// The hunter sees line-item prices and a grand total that simply reflects
/// the base booking cost — there is no "Platform Fee" row exposed to the
/// hunter.
///
/// On submit the request is written to the Firestore `bookings` collection
/// with `isCustomPackage: true` and `status: 'Pending Approval'`, the 25%
/// non-refundable deposit is computed (`total × 0.25`) and made payable via
/// the PayFast sandbox, and the standard [BookingChatThread] is embedded for
/// hunter↔outfitter negotiation.
class HunterCustomPackageBuilderScreen extends StatefulWidget {
  final ThemeController theme;

  /// Farm the custom package is being built against.
  final String farmId;
  final String farmName;

  /// Outfitter who owns the farm / price list.
  final String outfitterId;

  /// The scanned price list document id the items are drawn from.
  final String pricelistId;

  /// The full price list document (carries the `items` array).
  final Map<String, dynamic> pricelist;

  const HunterCustomPackageBuilderScreen({
    super.key,
    required this.theme,
    required this.farmId,
    required this.farmName,
    required this.outfitterId,
    required this.pricelistId,
    required this.pricelist,
  });

  @override
  State<HunterCustomPackageBuilderScreen> createState() =>
      _HunterCustomPackageBuilderScreenState();
}

class _HunterCustomPackageBuilderScreenState
    extends State<HunterCustomPackageBuilderScreen> {
  final PricelistScannerService _pricelistService =
      PricelistScannerService.instance;

  // Form state.
  DateTime? _checkIn;
  DateTime? _checkOut;
  int _hunterCount = 1;
  int _observerCount = 0;

  // Item rows (species) + fee rows (lodging/catering/...), each with qty.
  final Map<String, int> _quantities = {}; // keyed by item index id
  final List<Map<String, dynamic>> _speciesItems = [];
  final List<Map<String, dynamic>> _feeItems = [];

  // Submission state.
  bool _isSubmitting = false;
  String? _createdBookingId; // when set, switches to confirmation view

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    final items = widget.pricelist['items'] as List<dynamic>? ?? [];
    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final type = item['itemType'] as String? ?? 'species';
      final row = Map<String, dynamic>.from(item);
      row['_rowId'] = '${widget.pricelistId}_$i';
      if (type == 'fee') {
        _feeItems.add(row);
      } else {
        _speciesItems.add(row);
      }
    }
  }

  double _unitPrice(Map<String, dynamic> item) =>
      (item['hunterDisplayPriceZAR'] as num?)?.toDouble() ?? 0.0;

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
    for (final item in [..._speciesItems, ..._feeItems]) {
      final rowId = item['_rowId'] as String;
      final qty = _qty(rowId);
      if (qty > 0) {
        total += _unitPrice(item) * qty;
      }
    }
    return total;
  }

  int get _totalLineCount {
    var n = 0;
    for (final item in [..._speciesItems, ..._feeItems]) {
      if (_qty(item['_rowId'] as String) > 0) n++;
    }
    return n;
  }

  int get _huntingDays {
    if (_checkIn == null || _checkOut == null) return 0;
    final diff = _checkOut!.difference(_checkIn!).inDays;
    return diff > 0 ? diff : 0;
  }

  double get _deposit => _grandTotal * 0.25;

  String _formatZAR(double value) =>
      'R ${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  List<Map<String, dynamic>> _collectSelected(List<Map<String, dynamic>> rows) {
    final out = <Map<String, dynamic>>[];
    for (final item in rows) {
      final rowId = item['_rowId'] as String;
      final qty = _qty(rowId);
      if (qty <= 0) continue;
      final unit = _unitPrice(item);
      out.add({
        'name': item['name'] ?? item['displayLabel'] ?? 'Unknown',
        'displayLabel': item['displayLabel'] ?? item['name'],
        'speciesId': item['speciesId'],
        'speciesName': item['speciesName'],
        'sex': item['sex'],
        'sexLabel': item['sexLabel'],
        'trophySizeRange': item['trophySizeRange'],
        'itemType': item['itemType'],
        'feeType': item['feeType'],
        'quantity': qty,
        'unitPriceHunterZAR': unit,
        'lineTotal': unit * qty,
        'outfitterBasePrice': item['outfitterBasePrice'] ?? 0.0,
        'hunterDisplayPriceZAR': unit,
        if (item['quantityLimit'] != null)
          'quantityLimit': item['quantityLimit'],
      });
    }
    return out;
  }

  Future<void> _submitBooking() async {
    if (_totalLineCount == 0) {
      _showError('Please add at least one species or lodging/catering line.');
      return;
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showError('Please log in to continue');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final selectedItems = _collectSelected(_speciesItems);
      final lodgingCatering = _collectSelected(_feeItems);
      final total = _grandTotal;

      final bookingId = await _pricelistService.submitCustomPackageBooking(
        farmId: widget.farmId,
        farmName: widget.farmName,
        outfitterId: widget.outfitterId,
        pricelistId: widget.pricelistId,
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

  Future<void> _payDeposit() async {
    final bookingId = _createdBookingId;
    if (bookingId == null) return;
    // Route the deposit to the farm's attached PayFast merchant account when
    // one is configured; otherwise fall back to the platform default.
    FarmPayFastProfile? farmProfile;
    try {
      farmProfile =
          await OutfitterEnterpriseManager.instance.getFarmPayFastProfile(
              widget.farmId);
      if (!farmProfile.isConfigured) farmProfile = null;
    } catch (_) {
      farmProfile = null;
    }
    final ok = await PayfastCheckout.launchDeposit(
      bookingId: bookingId,
      amount: _deposit,
      itemName: 'JagSpoor Custom Package Deposit $bookingId',
      farmProfile: farmProfile,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open PayFast checkout')),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('⚠️ $message'), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ $message'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          '🦌 Custom Package Builder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: _createdBookingId != null
          ? _buildConfirmationView(theme)
          : _buildFormView(theme),
    );
  }

  // ── Confirmation view (post-submit): deposit + chat ───────────────────────
  Widget _buildConfirmationView(ThemeController theme) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
      children: [
        Icon(Icons.check_circle_rounded,
            color: Colors.green, size: 56),
        const SizedBox(height: 12),
        Text(
          'Request Submitted!',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: theme.textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Your custom package request for ${widget.farmName} has been sent to '
          'the outfitter for approval. You can negotiate details in the chat '
          'below; the 25% deposit becomes due once the outfitter approves.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.subtitleColor, fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Price summary (no platform-fee line shown to the hunter).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              _summaryRow(theme, 'Grand Total', _formatZAR(_grandTotal),
                  emphasize: true),
              const Divider(height: 20),
              _summaryRow(theme, '25% Deposit (due on approval)',
                  _formatZAR(_deposit)),
              const SizedBox(height: 4),
              _summaryRow(theme, 'Balance (settled with outfitter)',
                  _formatZAR(_grandTotal - _deposit)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 💳 PayFast deposit checkout.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.payment_rounded, color: Colors.white),
            label: Text(
                'Pay 25% Deposit (${_formatZAR(_deposit)}) via PayFast'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _payDeposit,
          ),
        ),
        const SizedBox(height: 20),

        // 💬 Standard booking chat thread.
        BookingChatThread(
          bookingId: _createdBookingId!,
          theme: theme,
          senderName:
              FirebaseAuth.instance.currentUser?.displayName ?? 'Hunter',
          initiallyExpanded: true,
        ),
        const SizedBox(height: 24),

        // Done — back to the farm selection / dashboard.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.check_rounded),
            label: const Text('DONE'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.accentColor,
              side: BorderSide(color: theme.accentColor.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(ThemeController theme, String label, String value,
      {bool emphasize = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize ? theme.textColor : theme.subtitleColor,
            fontSize: emphasize ? 15 : 13,
            fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: emphasize ? Colors.green : theme.textColor,
            fontSize: emphasize ? 18 : 14,
            fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Form view ─────────────────────────────────────────────────────────────
  Widget _buildFormView(ThemeController theme) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
            children: [
              _buildFarmHeader(theme),
              const SizedBox(height: 16),
              _buildDatesSection(theme),
              const SizedBox(height: 16),
              _buildPartySection(theme),
              const SizedBox(height: 16),
              _buildSectionTitle(
                  theme, Icons.pets_rounded, 'Species & Trophies'),
              if (_speciesItems.isEmpty)
                _emptyHint(theme, 'No species lines on this price list.')
              else
                ..._speciesItems.map((i) => _ItemQtyRow(
                      item: i,
                      qty: _qty(i['_rowId'] as String),
                      unitPrice: _unitPrice(i),
                      onChanged: (v) =>
                          _setQty(i['_rowId'] as String, v),
                      theme: theme,
                    )),
              const SizedBox(height: 16),
              _buildSectionTitle(
                  theme, Icons.hotel_rounded, 'Lodging & Catering'),
              if (_feeItems.isEmpty)
                _emptyHint(theme, 'No lodging/catering lines on this price list.')
              else
                ..._feeItems.map((i) => _ItemQtyRow(
                      item: i,
                      qty: _qty(i['_rowId'] as String),
                      unitPrice: _unitPrice(i),
                      onChanged: (v) =>
                          _setQty(i['_rowId'] as String, v),
                      theme: theme,
                    )),
              const SizedBox(height: 24),
            ],
          ),
        ),
        _buildBottomBar(theme),
      ],
    );
  }

  Widget _buildFarmHeader(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.terrain_rounded, color: theme.accentColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.farmName,
                  style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_speciesItems.length} species · ${_feeItems.length} fee lines',
                  style: TextStyle(color: theme.subtitleColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatesSection(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HUNT DATES',
            style: TextStyle(
                color: theme.subtitleColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dateChip(
                  theme: theme,
                  label: 'Check-in',
                  value: _checkIn,
                  onTap: () => _pickDate(isCheckIn: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dateChip(
                  theme: theme,
                  label: 'Check-out',
                  value: _checkOut,
                  onTap: () => _pickDate(isCheckIn: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_huntingDays > 0)
            Row(
              children: [
                Icon(Icons.event_available_rounded,
                    color: theme.accentColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  '$_huntingDays hunting day${_huntingDays != 1 ? 's' : ''}',
                  style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dateChip({
    required ThemeController theme,
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.event_rounded, color: theme.accentColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  Text(
                    value != null
                        ? '${value.day}/${value.month}/${value.year}'
                        : 'Select date',
                    style: TextStyle(
                        color: value != null
                            ? theme.textColor
                            : theme.subtitleColor,
                        fontSize: 13,
                        fontWeight: value != null
                            ? FontWeight.w600
                            : FontWeight.normal),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartySection(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _countStepper(
              theme: theme,
              label: 'Hunters',
              icon: Icons.person_rounded,
              value: _hunterCount,
              min: 1,
              onChanged: (v) => setState(() => _hunterCount = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _countStepper(
              theme: theme,
              label: 'Observers',
              icon: Icons.visibility_rounded,
              value: _observerCount,
              min: 0,
              onChanged: (v) => setState(() => _observerCount = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countStepper({
    required ThemeController theme,
    required String label,
    required IconData icon,
    required int value,
    required int min,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.accentColor, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _roundIconBtn(
              theme: theme,
              icon: Icons.remove_rounded,
              onTap: value > min ? () => onChanged(value - 1) : null,
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
            _roundIconBtn(
              theme: theme,
              icon: Icons.add_rounded,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _roundIconBtn({
    required ThemeController theme,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
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
            size: 20),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeController theme, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: theme.accentColor, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
        ],
      ),
    );
  }

  Widget _emptyHint(ThemeController theme, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(message,
          style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
    );
  }

  Widget _buildBottomBar(ThemeController theme) {
    final total = _grandTotal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          top: BorderSide(color: theme.accentColor.withValues(alpha: 0.3), width: 2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
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
                Text(
                  _formatZAR(total),
                  style: TextStyle(
                      color: theme.accentColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Deposit hint (no separate fee line shown to the hunter).
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('25% deposit due on approval',
                    style: TextStyle(
                        color: theme.subtitleColor, fontSize: 12)),
                Text(_formatZAR(_deposit),
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
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
      ),
    );
  }
}

/// A price-list line row with a quantity stepper + per-line total.
///
/// The unit price shown is the `hunterDisplayPriceZAR`, which equals the
/// item's base price (there is no platform commission), so no separate fee
/// row appears.
class _ItemQtyRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final int qty;
  final double unitPrice;
  final ValueChanged<int> onChanged;
  final ThemeController theme;

  const _ItemQtyRow({
    required this.item,
    required this.qty,
    required this.unitPrice,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ??
        item['displayLabel'] as String? ??
        'Unknown';
    final sexLabel = item['sexLabel'] as String? ?? '';
    final sizeRange = item['trophySizeRange'] as String? ?? '';
    final isSelected = qty > 0;
    final lineTotal = unitPrice * qty;
    final quantityLimit = _resolveQtyLimit(item);
    final atLimit = quantityLimit != null && qty >= quantityLimit;

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
                if (sexLabel.isNotEmpty || sizeRange.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (sexLabel.isNotEmpty)
                        _metaChip(sexLabel),
                      if (sizeRange.isNotEmpty) _metaChip(sizeRange),
                      if (quantityLimit != null)
                        _metaChip('max $quantityLimit'),
                    ],
                  ),
                ],
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
          _qtyStepper(atLimit: atLimit),
        ],
      ),
    );
  }

  /// Resolves the per-line quantity limit from the item map (int / num /
  /// numeric string). Returns `null` when unset (unlimited).
  static int? _resolveQtyLimit(Map<String, dynamic> item) {
    final v = item['quantityLimit'];
    if (v is int) return v > 0 ? v : null;
    if (v is num) return v.toInt() > 0 ? v.toInt() : null;
    if (v is String) {
      final n = int.tryParse(v);
      return (n != null && n > 0) ? n : null;
    }
    return null;
  }

  Widget _metaChip(String label) {
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

  Widget _qtyStepper({required bool atLimit}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(icon: Icons.remove_rounded, onTap: qty > 0 ? () => onChanged(qty - 1) : null),
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
        // Cap the '+' button at the per-line quantity limit so a hunter
        // cannot book more animals than the outfitter has available.
        _btn(
          icon: Icons.add_rounded,
          onTap: atLimit ? null : () => onChanged(qty + 1),
        ),
      ],
    );
  }

  Widget _btn({required IconData icon, required VoidCallback? onTap}) {
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

