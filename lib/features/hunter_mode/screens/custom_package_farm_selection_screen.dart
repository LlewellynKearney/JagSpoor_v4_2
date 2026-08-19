import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import 'hunter_custom_package_builder_screen.dart';

/// First step of the Custom Package Builder flow: lets the hunter pick which
/// outfitter farm to build a custom package against.
///
/// A farm is eligible when its outfitter has published a **game price list**
/// for it (`farm_pricelists` -- species + per-unit ZAR) and/or an itemized
/// **service-rate** configuration (`farm_service_rates` -- bakkie /
/// slaughtering / coldroom / daily / accommodation / catering fees). The
/// builder draws species lines from the price list and itemized-fee lines
/// from the service rates so the hunter can assemble a fully-priced custom
/// trip. Farms with neither are filtered out -- there is nothing to price.
///
/// Selecting a qualifying farm pushes [HunterCustomPackageBuilderScreen] with
/// the farm + its outfitter id so the builder can stream both collections.
class CustomPackageFarmSelectionScreen extends StatefulWidget {
  final ThemeController theme;

  const CustomPackageFarmSelectionScreen({super.key, required this.theme});

  @override
  State<CustomPackageFarmSelectionScreen> createState() =>
      _CustomPackageFarmSelectionScreenState();
}

class _CustomPackageFarmSelectionScreenState
    extends State<CustomPackageFarmSelectionScreen> {
  bool _isLoading = true;
  String? _error;
  List<_BookableFarm> _farms = [];

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
      // Discover bookable farms from the farm_pricelists collection (no owner
      // filter -- any signed-in hunter may read it per firestore.rules). Group
      // by farmId so each farm appears once even with many species entries.
      final pricelists = await FirebaseFirestore.instance
          .collection('farm_pricelists')
          .get();

      // farmId -> outfitterId (the first entry that carries a non-empty
      // outfitterId wins, so a farm with stale entries still resolves).
      final byFarm = resolveOutfittersByFarm(
        pricelists.docs.map((doc) => doc.data()),
      );
      final speciesCount = <String, int>{};
      for (final doc in pricelists.docs) {
        final data = doc.data();
        final farmId = (data['farmId'] as String?) ?? '';
        if (farmId.isEmpty) continue;
        speciesCount[farmId] = (speciesCount[farmId] ?? 0) + 1;
      }

      // Also consider farms that have a service-rate doc but no species
      // entries yet -- they are still bookable (lodging/catering only trip).
      final serviceRates = await FirebaseFirestore.instance
          .collection('farm_service_rates')
          .get();
      for (final doc in serviceRates.docs) {
        final outfitterId =
            (doc.data()['outfitterId'] as String?) ?? '';
        final existing = byFarm[doc.id];
        // Same prefer-non-empty rule as the price-list resolution: never
        // overwrite a known outfitter id, but backfill an empty one.
        if (existing == null || (existing.isEmpty && outfitterId.isNotEmpty)) {
          byFarm[doc.id] = outfitterId;
        }
        speciesCount.putIfAbsent(doc.id, () => 0);
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

      // Resolve farm documents. Farms are readable by any signed-in user.
      final farmsSnapshot = await FirebaseFirestore.instance
          .collection('farms')
          .where(FieldPath.documentId, whereIn: farmIds)
          .get();

      final farms = <_BookableFarm>[];
      for (final doc in farmsSnapshot.docs) {
        final data = doc.data();
        final farmId = doc.id;
        final outfitterId = byFarm[farmId] ?? '';
        farms.add(_BookableFarm(
          farmId: farmId,
          farmName: (data['name'] as String?) ?? 'Unnamed Farm',
          district: data['district'] as String?,
          province: data['province'] as String?,
          outfitterId: outfitterId,
          speciesCount: speciesCount[farmId] ?? 0,
          hasServiceRates: serviceRates.docs.any((d) => d.id == farmId),
        ));
      }
      // Farms with the most priced species first, then alphabetical.
      farms.sort((a, b) {
        final cmp = b.speciesCount.compareTo(a.speciesCount);
        if (cmp != 0) return cmp;
        return a.farmName.toLowerCase().compareTo(b.farmName.toLowerCase());
      });

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

  void _openBuilder(_BookableFarm farm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HunterCustomPackageBuilderScreen(
          theme: widget.theme,
          farmId: farm.farmId,
          farmName: farm.farmName,
          outfitterId: farm.outfitterId,
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
      bottomNavigationBar: const SafeArea(
        top: false,
        child: CopyrightFooter.tight(),
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
        padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
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
                    'Outfitters must publish a price list (species + service '
                    'rates) for a farm before you can build a custom package '
                    'against it.',
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

class _BookableFarm {
  final String farmId;
  final String farmName;
  final String? district;
  final String? province;
  final String outfitterId;
  final int speciesCount;
  final bool hasServiceRates;

  _BookableFarm({
    required this.farmId,
    required this.farmName,
    this.district,
    this.province,
    required this.outfitterId,
    required this.speciesCount,
    required this.hasServiceRates,
  });
}

class _FarmCard extends StatelessWidget {
  final _BookableFarm farm;
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        // Wrapped chip rows need vertical breathing room too --
                        // without runSpacing a second row of chips sits flush
                        // against the first (the awkward wrapping the layout
                        // cleanup targets).
                        runSpacing: 6,
                        children: [
                          if (farm.province != null &&
                              farm.province!.isNotEmpty)
                            _chip(Icons.map_outlined, farm.province!),
                          if (farm.district != null &&
                              farm.district!.isNotEmpty)
                            _chip(Icons.location_on_outlined, farm.district!),
                          _chip(Icons.pets_rounded,
                              '${farm.speciesCount} species'),
                          if (farm.hasServiceRates)
                            _chip(Icons.room_service_rounded,
                                'service rates'),
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
            style: TextStyle(color: theme.subtitleColor, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Resolves `farmId -> outfitterId` from raw `farm_pricelists` document maps.
///
/// The first entry that carries a NON-EMPTY `outfitterId` wins, so a farm
/// whose earliest-written price-list entry has a missing/blank `outfitterId`
/// still resolves to the real outfitter once any entry for the farm carries
/// one. (The previous `putIfAbsent` implementation kept the FIRST entry's
/// `outfitterId` even when it was empty, so the builder received a blank
/// outfitter id and wrote an orphaned booking the outfitter never saw.)
///
/// Entries with a missing/blank `farmId` are skipped. Pure function over the
/// document data maps -- unit-testable without Firestore.
Map<String, String> resolveOutfittersByFarm(
  Iterable<Map<String, dynamic>> priceListDocs,
) {
  final byFarm = <String, String>{};
  for (final data in priceListDocs) {
    final farmId = (data['farmId'] as String?) ?? '';
    if (farmId.isEmpty) continue;
    final outfitterId = (data['outfitterId'] as String?) ?? '';
    final existing = byFarm[farmId];
    if (existing == null || (existing.isEmpty && outfitterId.isNotEmpty)) {
      byFarm[farmId] = outfitterId;
    }
  }
  return byFarm;
}
