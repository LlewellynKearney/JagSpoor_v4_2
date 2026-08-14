import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../services/pricelist_scanner_service.dart';
import 'hunter_custom_package_builder_screen.dart';

/// First step of the Custom Package Builder flow: lets the hunter pick which
/// outfitter farm to build a custom package against.
///
/// A farm is only eligible when its outfitter has published an **active**
/// scanned price list for it (so there are species/fees to price the custom
/// itinerary from). Farms without an active price list are filtered out — the
/// hunter cannot start a custom build against a farm with no pricing data.
///
/// Selecting a qualifying farm pushes [HunterCustomPackageBuilderScreen] with
/// the farm + its most recent active price list.
class CustomPackageFarmSelectionScreen extends StatefulWidget {
  final ThemeController theme;

  const CustomPackageFarmSelectionScreen({super.key, required this.theme});

  @override
  State<CustomPackageFarmSelectionScreen> createState() =>
      _CustomPackageFarmSelectionScreenState();
}

class _CustomPackageFarmSelectionScreenState
    extends State<CustomPackageFarmSelectionScreen> {
  final PricelistScannerService _pricelistService =
      PricelistScannerService.instance;

  bool _isLoading = true;
  String? _error;
  List<_FarmWithPricelist> _farms = [];

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Active price lists first — the catalog of bookable farms. Readable by
      // signed-in hunters (the scanned_pricelists read rule).
      final pricelists = await _pricelistService.getAllActivePricelists();

      // Index the most-recent active price list per farm (the list is already
      // ordered by createdAt desc, so first-seen wins).
      final byFarm = <String, Map<String, dynamic>>{};
      for (final pl in pricelists) {
        final farmId = pl['farmId'] as String?;
        if (farmId == null || farmId.isEmpty) continue;
        byFarm.putIfAbsent(farmId, () => pl);
      }
      final farmIds = byFarm.keys.toList();

      if (farmIds.isEmpty) {
        if (mounted) {
          setState(() {
            _farms = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Resolve farm documents for the farms that have a price list. Farms are
      // readable by any signed-in user (firestore.rules `farms` read).
      final farmsSnapshot = await FirebaseFirestore.instance
          .collection('farms')
          .where(FieldPath.documentId, whereIn: farmIds)
          .get();

      final farms = <_FarmWithPricelist>[];
      for (final doc in farmsSnapshot.docs) {
        final data = doc.data();
        final farmId = doc.id;
        final pricelist = byFarm[farmId];
        if (pricelist == null) continue;
        farms.add(_FarmWithPricelist(
          farmId: farmId,
          farmName: (data['name'] as String?) ?? 'Unnamed Farm',
          district: data['district'] as String?,
          province: data['province'] as String?,
          outfitterId: (pricelist['outfitterId'] as String?) ?? '',
          pricelistId: (pricelist['id'] as String?) ?? '',
          pricelist: pricelist,
          itemCount: (pricelist['totalItems'] as num?)?.toInt() ?? 0,
        ));
      }

      if (mounted) {
        setState(() {
          _farms = farms;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _openBuilder(_FarmWithPricelist farm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HunterCustomPackageBuilderScreen(
          theme: widget.theme,
          farmId: farm.farmId,
          farmName: farm.farmName,
          outfitterId: farm.outfitterId,
          pricelistId: farm.pricelistId,
          pricelist: farm.pricelist,
        ),
      ),
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
      body: RefreshIndicator(
        color: theme.accentColor,
        onRefresh: _loadFarms,
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeController theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Could not load farms',
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.subtitleColor, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadFarms,
                icon: const Icon(Icons.refresh),
                label: const Text('RETRY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_farms.isEmpty) {
      return ListView(
        // ListView so RefreshIndicator works on an empty list.
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
          Center(
            child: Column(
              children: [
                Icon(Icons.agriculture_rounded,
                    color: theme.accentColor.withValues(alpha: 0.5), size: 64),
                const SizedBox(height: 16),
                Text(
                  'No bookable farms yet',
                  style: TextStyle(
                      color: theme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Outfitters must publish an active price list for a farm '
                    'before you can build a custom package against it.',
                    style: TextStyle(color: theme.subtitleColor, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
      itemCount: _farms.length,
      itemBuilder: (context, index) {
        final farm = _farms[index];
        return _FarmCard(
          farm: farm,
          theme: theme,
          onTap: () => _openBuilder(farm),
        );
      },
    );
  }
}

class _FarmWithPricelist {
  final String farmId;
  final String farmName;
  final String? district;
  final String? province;
  final String outfitterId;
  final String pricelistId;
  final Map<String, dynamic> pricelist;
  final int itemCount;

  _FarmWithPricelist({
    required this.farmId,
    required this.farmName,
    this.district,
    this.province,
    required this.outfitterId,
    required this.pricelistId,
    required this.pricelist,
    required this.itemCount,
  });
}

class _FarmCard extends StatelessWidget {
  final _FarmWithPricelist farm;
  final ThemeController theme;
  final VoidCallback onTap;

  const _FarmCard({
    required this.farm,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.terrain_rounded,
                      color: theme.accentColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        farm.farmName,
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (farm.province != null &&
                              farm.province!.isNotEmpty)
                            _chip(Icons.map_outlined, farm.province!),
                          if (farm.district != null &&
                              farm.district!.isNotEmpty)
                            _chip(Icons.location_on_outlined, farm.district!),
                          _chip(Icons.price_check_rounded,
                              '${farm.itemCount} priced items'),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: theme.accentColor, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.subtitleColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: theme.subtitleColor, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
