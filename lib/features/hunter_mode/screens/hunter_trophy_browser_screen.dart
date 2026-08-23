import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../widgets/trophy_booking_confirmation_sheet.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/shared/widgets/hunter_grid_container.dart';
import 'package:jagspoor/features/shared/widgets/hunter_media_card.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';

class HunterTrophyBrowserScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterTrophyBrowserScreen({super.key, required this.theme});

  @override
  State<HunterTrophyBrowserScreen> createState() =>
      _HunterTrophyBrowserScreenState();
}

class _HunterTrophyBrowserScreenState extends State<HunterTrophyBrowserScreen> {
  String? _selectedProvince;
  String _searchQuery = '';
  List<Map<String, dynamic>> _trophies = [];
  bool _isLoading = true;

  // South African provinces
  static const List<String> _provinces = [
    'All Provinces',
    'Limpopo',
    'Mpumalanga',
    'Gauteng',
    'North West',
    'Free State',
    'KwaZulu-Natal',
    'Eastern Cape',
    'Western Cape',
    'Northern Cape',
  ];

  @override
  void initState() {
    super.initState();
    _loadTrophies();
  }

  Future<void> _loadTrophies() async {
    setState(() => _isLoading = true);
    try {
      // Load from the dedicated outfitter trophy stock collection
      // (`trophy_stock`), distinct from the hunter's personal Digital Trophy
      // Room (`trophies`, scoped by `ownerId`).
      //
      // The stock documents carry ONLY a `farmId` (no denormalised farmName /
      // province) -- see `OutfitterEnterpriseManager.syncTrophyStock`. The
      // province filter therefore cannot run server-side on `trophy_stock`
      // (previously the filter matched ZERO documents for any specific
      // province because `province` does not exist there). We load all stock
      // with `availableCount > 0`, resolve the parent `farms` docs, and apply
      // the province filter client-side on the resolved location.
      final snapshot = await FirebaseFirestore.instance
          .collection(OutfitterEnterpriseManager.trophyStockCollection)
          .where('availableCount', isGreaterThan: 0)
          .get();

      // Resolve the parent farm documents (farmId -> farm data) so each card
      // displays the REAL farm name + location instead of the "Unknown Farm"
      // fallback. Mirrors the farm-resolution join the package marketplace
      // performs on `packages` -> `farms`.
      final farmIds = <String>{};
      for (final doc in snapshot.docs) {
        final trophyData = doc.data() as Map<String, dynamic>?;
        final farmId = (trophyData?['farmId'] as String?) ?? '';
        if (farmId.isNotEmpty) farmIds.add(farmId);
      }
      final farmDataById = <String, Map<String, dynamic>>{};
      if (farmIds.isNotEmpty) {
        try {
          final farmsSnapshot = await FirebaseFirestore.instance
              .collection('farms')
              .where(FieldPath.documentId, whereIn: farmIds.toList())
              .get();
          for (final farmDoc in farmsSnapshot.docs) {
            farmDataById[farmDoc.id] = farmDoc.data();
          }
        } catch (_) {
          // A farm lookup failure must never block the trophy list -- the
          // cards fall back to the raw ids / "Unknown Farm" placeholders.
        }
      }

      final provinceFilter = _selectedProvince;
      final bool filterByProvince = provinceFilter != null &&
          provinceFilter.isNotEmpty &&
          provinceFilter != 'All Provinces';

      final List<Map<String, dynamic>> loadedTrophies = [];

      for (final trophyDoc in snapshot.docs) {
        final trophyData = trophyDoc.data() as Map<String, dynamic>?;
        if (trophyData == null) continue;

        final farmId = (trophyData['farmId'] as String?) ?? '';
        final farmData = farmDataById[farmId];

        // Farm display name: prefer a denormalised `farmName` on the stock
        // doc (legacy), then the resolved `farms` doc's `name`, then the
        // fallback. This is what fixes "Unknown Farm" for stock docs that
        // only carry `farmId`.
        final farmName = resolveFarmName(trophyData, farmData);
        final province = resolveTrophyProvince(trophyData, farmData);
        final town = resolveTown(trophyData, farmData);

        // Client-side province filter (see the comment above -- the stock
        // collection has no `province` field to filter server-side).
        if (filterByProvince) {
          if (province.toLowerCase() != provinceFilter.toLowerCase()) {
            continue;
          }
        }

        loadedTrophies.add({
          'id': trophyDoc.id,
          'farmId': farmId,
          'farmName': farmName,
          'province': province,
          'town': town,
          'species': (trophyData['species'] as String?) ?? 'Unknown',
          'available': trophyData['availableCount'] ?? 0,
          'pricePerTrophy': trophyData['pricePerTrophyRands'] ?? 0.0,
          'sex': (trophyData['sex'] as String?) ?? 'Mixed',
          'outfitterId': (trophyData['outfitterId'] as String?) ?? '',
          'imageUrl': resolveImageUrl(trophyData),
          'trophyMeasurement': resolveMeasurement(trophyData),
          // Raw parent-farm snapshot for the confirmation sheet's FARM
          // DETAILS panel (name / location / size / contact / photos).
          if (farmData != null) 'farmData': farmData,
        });
      }

      setState(() {
        _trophies = loadedTrophies;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading trophies: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredTrophies {
    if (_searchQuery.isEmpty) return _trophies;
    return _trophies.where((t) {
      final species = (t['species'] as String).toLowerCase();
      final farm = (t['farmName'] as String).toLowerCase();
      final query = _searchQuery.toLowerCase();
      return species.contains(query) || farm.contains(query);
    }).toList();
  }

  /// Opens the standard Booking Details / Confirmation Sheet for a tapped
  /// trophy stock card -- the same flow the package marketplace + custom
  /// package builder use (full item details, outfitter contact info, pricing,
  /// then the atomic booking transaction on confirm). After a successful
  /// booking the stock list reloads so the card's availability count drops by
  /// one immediately.
  void _openBookingSheet(Map<String, dynamic> trophy) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TrophyBookingConfirmationSheet(
        trophy: trophy,
        theme: widget.theme,
      ),
    ).then((_) => _loadTrophies());
  }

  /// Rich-media trophy stock card: full-bleed trophy photo with the dark
  /// legibility gradient, an amber "TROPHY STOCK" tag, and frosted telemetry
  /// pills for availability / measurement / sex / price across the lower
  /// section. Tapping opens the standard booking confirmation sheet.
  Widget _buildTrophyCard(ThemeController theme, Map<String, dynamic> trophy) {
    final price = (trophy['pricePerTrophy'] as num?)?.toDouble() ?? 0.0;
    final available = (trophy['available'] as num?)?.toInt() ?? 0;
    final String imageUrl = trophy['imageUrl']?.toString().trim() ?? '';
    final measurement = (trophy['trophyMeasurement'] as num?)?.toDouble();
    final sex = (trophy['sex'] as String?)?.trim() ?? '';

    final priceText =
        'R ${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

    return HunterMediaCard(
      theme: theme,
      image: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
      fallbackIcon: Icons.emoji_events_rounded,
      title: trophy['species'] as String? ?? 'Unknown',
      subtitle: locationLabel(trophy),
      onTap: () => _openBookingSheet(trophy),
      topLeftPill: const HunterMediaPill(
        icon: Icons.emoji_events_rounded,
        label: 'TROPHY STOCK',
        amber: true,
      ),
      pills: [
        HunterMediaPill(
          icon:
              available > 0
                  ? Icons.inventory_2_rounded
                  : Icons.do_not_disturb_on_rounded,
          label: available > 0 ? '$available available' : 'Sold out',
          amber: available > 0,
          accentColor: available > 0 ? null : Colors.redAccent,
        ),
        if (measurement != null)
          HunterMediaPill(
            icon: Icons.straighten_rounded,
            label:
                '${measurement % 1 == 0 ? measurement.toStringAsFixed(0) : measurement.toStringAsFixed(1)}"',
          ),
        if (sex.isNotEmpty)
          HunterMediaPill(icon: Icons.pets_rounded, label: sex),
        HunterMediaPill(
          icon: Icons.payments_rounded,
          label: priceText,
          amber: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return HunterScaffold(
      theme: widget.theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: const Text(
          '🦌 Trophy Registry & Booking',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: HunterUi.titleColor(theme),
        elevation: 0,
        actions: [
          AppInfoIconButton(
            screenKey: AppScreenHelpScripts.hunterTrophyRegistry,
            iconColor: theme.accentColor,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HunterUi.cardColor(theme),
              border: Border(
                bottom: BorderSide(
                  color: theme.accentColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                // Search Field
                TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: TextStyle(color: theme.textColor),
                  decoration: InputDecoration(
                    hintText: 'Search species or farm...',
                    hintStyle: TextStyle(color: theme.subtitleColor),
                    prefixIcon: Icon(Icons.search, color: theme.accentColor),
                    filled: true,
                    fillColor: theme.backgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Province Filter
                Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: theme.accentColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: theme.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedProvince ?? 'All Provinces',
                            isExpanded: true,
                            dropdownColor: HunterUi.cardColor(theme),
                            style: TextStyle(color: theme.textColor),
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: theme.accentColor,
                            ),
                            items:
                                _provinces.map((province) {
                                  return DropdownMenuItem(
                                    value: province,
                                    child: Text(
                                      province,
                                      style: TextStyle(color: theme.textColor),
                                    ),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedProvince =
                                    value == 'All Provinces' ? null : value;
                              });
                              _loadTrophies();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Trophy List
          Expanded(
            child:
                _isLoading
                    ? const Center(
                      child: CircularProgressIndicator(color: Colors.green),
                    )
                    : _filteredTrophies.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.pets_rounded,
                            color: theme.subtitleColor.withValues(alpha: 0.5),
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No trophies available',
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Outfitters will load trophy stock soon',
                            style: TextStyle(color: theme.subtitleColor),
                          ),
                        ],
                      ),
                    )
                    : HunterGridContainer(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        SafeBottomInset.of(context),
                      ),
                      maxCrossAxisExtent: 320,
                      childAspectRatio: 0.95,
                      spacing: 14,
                      children: [
                        for (final trophy in _filteredTrophies)
                          _buildTrophyCard(theme, trophy),
                      ],
                    )
          ),
        ],
      ),
    );
  }
}

/// Resolves the display farm name for a trophy stock document.
///
/// Stock documents carry ONLY a `farmId` (see
/// `OutfitterEnterpriseManager.syncTrophyStock`) -- the farm's display name
/// must be looked up from the resolved `farms` document. A legacy
/// denormalised `farmName` on the stock doc (non-empty) wins; otherwise the
/// farm doc's `name`; otherwise the raw fallback the card renders when a
/// farm truly cannot be resolved. Pure function -- unit-testable without
/// Firestore.
String resolveFarmName(
  Map<String, dynamic> trophyData,
  Map<String, dynamic>? farmData,
) {
  final denormalised = (trophyData['farmName'] as String?)?.trim();
  if (denormalised != null && denormalised.isNotEmpty) return denormalised;
  final fromFarm = (farmData?['name'] as String?)?.trim();
  if (fromFarm != null && fromFarm.isNotEmpty) return fromFarm;
  return 'Unknown Farm';
}

/// Resolves the province for a trophy stock document: an explicit `province`
/// on the stock doc wins; otherwise the resolved farm doc's `province`.
String resolveTrophyProvince(
  Map<String, dynamic> trophyData,
  Map<String, dynamic>? farmData,
) {
  final onDoc = (trophyData['province'] as String?)?.trim();
  if (onDoc != null && onDoc.isNotEmpty) return onDoc;
  return (farmData?['province'] as String?)?.trim() ?? '';
}

/// Resolves the town/district locality for a trophy stock document: an
/// explicit `town` / `district` on the stock doc wins; otherwise the farm
/// doc's `town`, then the farm doc's `district` (the SA town-level locality
/// farms carry), mirroring the marketplace's town resolution.
String resolveTown(
  Map<String, dynamic> trophyData,
  Map<String, dynamic>? farmData,
) {
  final docTown = (trophyData['town'] as String?)?.trim();
  if (docTown != null && docTown.isNotEmpty) return docTown;
  final docDistrict = (trophyData['district'] as String?)?.trim();
  if (docDistrict != null && docDistrict.isNotEmpty) return docDistrict;
  final farmTown = (farmData?['town'] as String?)?.trim();
  if (farmTown != null && farmTown.isNotEmpty) return farmTown;
  return (farmData?['district'] as String?)?.trim() ?? '';
}

/// Resolves the farm location label rendered on the card, e.g.
/// "Bosveld Ranch • Waterberg, Limpopo". Omits empty parts so the label
/// never renders a dangling separator.
String resolveLocationLabel(
  Map<String, dynamic> trophyData,
  Map<String, dynamic>? farmData,
) {
  final farmName = resolveFarmName(trophyData, farmData);
  final town = resolveTown(trophyData, farmData);
  final province = resolveTrophyProvince(trophyData, farmData);
  final parts = [town, province].where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return farmName;
  return '$farmName • ${parts.join(', ')}';
}

/// Resolves a display image URL for the stock doc: an explicit `imageUrl`
/// wins; otherwise the first entry of the `trophyPhotoUrls` array (the field
/// `OutfitterEnterpriseManager.syncTrophyStock` actually writes); otherwise
/// an empty string (the card renders the placeholder).
String resolveImageUrl(Map<String, dynamic> trophyData) {
  final direct = (trophyData['imageUrl'] as String?)?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final photos = trophyData['trophyPhotoUrls'];
  if (photos is List) {
    for (final entry in photos) {
      final url = entry?.toString().trim() ?? '';
      if (url.isNotEmpty) return url;
    }
  }
  return '';
}

/// Resolves the trophy measurement in inches from the dual-alias fields the
/// stock doc writes (`trophyMeasurement` / `trophyLengthInches`). Tolerates
/// numeric + numeric-string storage. Returns null when absent.
double? resolveMeasurement(Map<String, dynamic> trophyData) {
  double? parse(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  return parse(trophyData['trophyMeasurement']) ??
      parse(trophyData['trophyLengthInches']);
}

/// Joins the card's pre-resolved location fields ("farm • town, province"),
/// omitting empty parts so the label never renders a dangling separator.
String locationLabel(Map<String, dynamic> trophy) {
  final farmName = (trophy['farmName'] as String?) ?? 'Unknown Farm';
  final parts = [
    (trophy['town'] as String?) ?? '',
    (trophy['province'] as String?) ?? '',
  ].where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return farmName;
  return '$farmName • ${parts.join(', ')}';
}
