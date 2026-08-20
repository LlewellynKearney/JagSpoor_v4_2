import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/farm_details.dart';
import '../models/package_pricing.dart';
import '../services/farm_details_resolver.dart';
import '../services/package_booking_manager.dart';
import '../services/photo_gallery_resolver.dart';
import 'outfitter_contact_card.dart';
import 'photo_gallery_strip.dart';

/// Standard Booking Details / Confirmation Sheet for a Trophy Registry stock
/// entry. Mirrors the package marketplace's booking confirmation sheet
/// exactly -- full item details, meta summary chips, the price breakdown,
/// the outfitter / farm manager contact card, the approval warning, the
/// sold-out banner, and the Cancel / BOOK action row.
///
/// On confirm it executes the standard booking process via
/// [PackageBookingManager.bookTrophyStock]: an atomic transaction that
/// creates the booking record (status: pending approval, routed through the
/// standard 'CUSTOM_BUILT' pipeline into the outfitter dashboard + hunter
/// "My Bookings") AND safely decrements the stock's available count.
class TrophyBookingConfirmationSheet extends StatefulWidget {
  /// The resolved trophy map (as built by the Trophy Registry browser):
  /// `id`, `farmId`, `farmName`, `province`, `town`, `species`, `available`,
  /// `pricePerTrophy`, `sex`, `outfitterId`, `imageUrl`, `trophyMeasurement`.
  final Map<String, dynamic> trophy;
  final ThemeController theme;

  /// Optional pre-resolved farm snapshot (the Trophy Registry browser joins
  /// `farms` docs). When omitted, the sheet resolves the farm details
  /// asynchronously from the trophy's `farmId` and updates reactively.
  final FarmDetails? farmDetails;

  const TrophyBookingConfirmationSheet({
    super.key,
    required this.trophy,
    required this.theme,
    this.farmDetails,
  });

  @override
  State<TrophyBookingConfirmationSheet> createState() =>
      _TrophyBookingConfirmationSheetState();
}

class _TrophyBookingConfirmationSheetState
    extends State<TrophyBookingConfirmationSheet> {
  bool _isLoading = false;

  /// The farm snapshot rendered by the header panel. Seeded from
  /// [TrophyBookingConfirmationSheet.farmDetails]; a missing or partial
  /// snapshot (e.g. no photos resolved yet) is asynchronously re-resolved
  /// from the trophy's `farmId` and updated once.
  FarmDetails? _farmDetails;
  bool _farmLoading = false;

  @override
  void initState() {
    super.initState();
    // Seed from an explicitly-passed snapshot, else the raw farm map the
    // Trophy Registry browser embeds under `farmData`.
    if (widget.farmDetails != null) {
      _farmDetails = widget.farmDetails;
    } else if (widget.trophy['farmData'] is Map<String, dynamic>) {
      _farmDetails = FarmDetails.fromMap(
          widget.trophy['farmData'] as Map<String, dynamic>);
    }
    if (_farmDetails == null || _farmDetails!.photoUrls.isEmpty) {
      _resolveFarmDetails();
    }
  }

  Future<void> _resolveFarmDetails() async {
    final farmId = (widget.trophy['farmId'] as String?) ?? '';
    if (farmId.isEmpty) return;
    setState(() => _farmLoading = true);
    try {
      final resolved =
          await FarmDetailsResolver.instance.resolveFarm(farmId);
      if (!mounted) return;
      setState(() {
        _farmDetails = resolved;
        _farmLoading = false;
      });
    } catch (e) {
      debugPrint('Farm details resolution failed: $e');
      if (!mounted) return;
      setState(() => _farmLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final trophy = widget.trophy;
    final species = (trophy['species'] as String?) ?? 'Unknown';
    final available = (trophy['available'] as num?)?.toInt() ?? 0;
    final price = (trophy['pricePerTrophy'] as num?)?.toDouble() ?? 0.0;
    final measurement = (trophy['trophyMeasurement'] as num?)?.toDouble();
    final soldOut = available <= 0;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.subtitleColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Row(
              children: [
                Icon(
                  Icons.pets_rounded,
                  color: theme.accentColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Trophy Details',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              species,
              style: TextStyle(color: theme.accentColor, fontSize: 14),
            ),
            const SizedBox(height: 12),

            // Trophy photo gallery — every photo the outfitter attached to
            // this trophy animal (trophyPhotoUrls), tap to view full screen.
            PhotoGalleryStrip(
              urls: resolveGalleryUrls(trophy),
              theme: theme,
              height: 170,
            ),
            if (resolveGalleryUrls(trophy).isNotEmpty)
              const SizedBox(height: 12),

            // Meta summary chips (species / sex / measurement / farm).
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metaChip(Icons.location_on_rounded,
                    _locationSummary(trophy)),
                _metaChip(Icons.wc_rounded,
                    (trophy['sex'] as String?) ?? 'Mixed'),
                if (measurement != null && measurement > 0)
                  _metaChip(Icons.straighten_rounded,
                      '${measurement.toStringAsFixed(1)}" trophy'),
                _metaChip(
                  Icons.confirmation_number_rounded,
                  available > 0 ? '$available available' : 'Sold out',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Parent farm details panel (name, location, size, contact,
            // registration) — resolved asynchronously when the browser's
            // farm join was incomplete.
            _buildFarmPanel(theme),
            const SizedBox(height: 16),

            // Item breakdown (the single trophy line).
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          color: theme.accentColor, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'TROPHY STOCK ITEM',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _breakdownLine(
                    label: species,
                    icon: Icons.pets_rounded,
                    detail:
                        '1 × R ${price.toStringAsFixed(2)} / trophy animal',
                    total: price,
                  ),
                  if (measurement != null && measurement > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Trophy measurement: ${measurement.toStringAsFixed(1)} inches',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Price Breakdown
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Price',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatZAR(price),
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Contact the outfitter / farm manager card (same widget the
            // package marketplace sheet uses).
            OutfitterContactCard(source: trophy, theme: theme),

            // Warning
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Booking request is sent for outfitter approval. On '
                      'approval the total price is due to confirm your trophy '
                      'hunt.',
                      style: TextStyle(
                        color: Colors.amber.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sold-out banner (defensive -- the browser only lists stock with
            // availability > 0, but a concurrent booking may have taken the
            // last animal since the list was loaded).
            if (soldOut)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.do_not_disturb_on_rounded,
                        color: Colors.red, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This trophy is no longer available. Please choose '
                        'another trophy or contact the outfitter about future '
                        'availability.',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.textColor,
                      side: BorderSide(
                        color: theme.accentColor.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed:
                        (_isLoading || soldOut) ? null : _confirmBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          soldOut ? Colors.grey : const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'BOOK THIS TROPHY',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The parent farm panel: farm name + full detail chips (province,
  /// district, town, size, contact number, registration number) + the farm's
  /// own photo gallery when available. Renders a slim loading indicator while
  /// the async resolution is in flight, and nothing when there is genuinely
  /// no farm info (the meta chips above already cover the fallback location).
  Widget _buildFarmPanel(ThemeController theme) {
    final farm = _farmDetails;
    if (farm == null) {
      if (!_farmLoading) return const SizedBox.shrink();
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading farm details...',
            style: TextStyle(color: theme.subtitleColor, fontSize: 12),
          ),
        ],
      );
    }
    final chips = farm.infoChips;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.agriculture_rounded,
                  color: theme.accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'FARM DETAILS',
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            farm.displayName,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (icon, label) in chips)
                  _metaChip(icon, label),
              ],
            ),
          ],
          if (farm.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            PhotoGalleryStrip(
              urls: farm.photoUrls,
              theme: theme,
              height: 120,
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.theme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: widget.theme.accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: widget.theme.subtitleColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownLine({
    required String label,
    required String detail,
    required double total,
    IconData icon = Icons.circle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: widget.theme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    color: widget.theme.subtitleColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'R ${total.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.green,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _locationSummary(Map<String, dynamic> trophy) {
    final farmName = (trophy['farmName'] as String?) ?? 'Unknown Farm';
    final town = (trophy['town'] as String?) ?? '';
    final province = (trophy['province'] as String?) ?? '';
    final parts = [town, province].where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return farmName;
    return '$farmName • ${parts.join(', ')}';
  }

  String _formatZAR(double value) =>
      'R ${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  Future<void> _confirmBooking() async {
    setState(() {
      _isLoading = true;
    });

    // Capture the messenger before the async gap so the snackbar still fires
    // if the sheet is dismissed mid-flight.
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final trophy = widget.trophy;
      final outfitterId = (trophy['outfitterId'] as String?) ?? '';
      if (outfitterId.isEmpty) {
        throw Exception('Invalid trophy: missing outfitter ID');
      }

      await PackageBookingManager.instance.bookTrophyStock(
        trophyId: (trophy['id'] as String?) ?? '',
        outfitterId: outfitterId,
        pricePerTrophyRands:
            (trophy['pricePerTrophy'] as num?)?.toDouble() ?? 0.0,
        species: trophy['species'] as String?,
        sex: trophy['sex'] as String?,
        trophyMeasurement:
            (trophy['trophyMeasurement'] as num?)?.toDouble(),
        farmId: trophy['farmId'] as String?,
        farmName: trophy['farmName'] as String?,
        district: trophy['town'] as String?,
        province: trophy['province'] as String?,
      );

      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('✅ Booking request submitted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Surface a clear "sold out" message when the transaction rejected the
      // booking due to no remaining stock.
      final soldOut = e is PackageSoldOutException;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(soldOut
              ? '❌ This trophy is no longer available.'
              : '❌ Booking failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
