import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Read-only hunter view of a farm's veld information.
///
/// Hard privacy contract — this screen renders ONLY:
///
///  * farm name, camp name, size (ha), veld type, province + district;
///  * the capacity summary (total capacity LSU, current stock LSU, usage %,
///    stocking status);
///  * the counted stock as **species + count** (never a weight, never GU/BU);
///  * the present-only species as "Present, not counted";
///  * the `hunter_visible` permits as **type + expiry + status** only.
///
/// It NEVER renders GPS coordinates, the nearest town, permit numbers,
/// issuing authorities, attached files or private permits, and it NEVER calls
/// an ownership-gated repository method — every read goes through the
/// hunter-safe reads on [VeldCarryRepository].
///
/// Reached only from [VeldCarryHunterEntryTile] (inside `VeldCarryGate`), so
/// with the feature flag OFF none of this UI can appear.
class VeldCarryHunterViewScreen extends StatefulWidget {
  const VeldCarryHunterViewScreen({
    super.key,
    required this.outfitterUid,
    required this.farmId,
    this.farmName,
    this.campId,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  /// The farm's outfitter — the owner segment of the veld data path. The
  /// hunter already has this from the package document it may read.
  final String outfitterUid;

  final String farmId;
  final String? farmName;

  /// When set, the view opens straight into that camp. When null, every camp
  /// of the farm is listed.
  final String? campId;

  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in hunter's uid so widget tests can drive the
  /// screen against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryHunterViewScreen> createState() =>
      _VeldCarryHunterViewScreenState();
}

/// One camp plus the hunter-safe numbers derived from it.
class HunterCampVeldView {
  HunterCampVeldView({
    required this.camp,
    required this.stock,
    required this.planted,
  });

  final Camp camp;
  final List<StockEntry> stock;
  final List<PlantedArea> planted;

  /// Year-round capacity: veld capacity plus the ALL_YEAR planted areas.
  double get totalCapacityLsu {
    final effective =
        effectiveHaPerLsu(camp.deptNormHaPerLsu, camp.veldCondition);
    final veld = veldCapacityLsu(camp.totalSizeHa, effective);
    return yearRoundCapacityLsu(veld, planted);
  }

  /// Only counted species contribute — a present-only species adds 0 LSU.
  double get currentStockLsu {
    var total = 0.0;
    for (final entry in stock) {
      if (entry.isCounted) total += entry.totalLsu;
    }
    return total;
  }

  double get usage => usagePct(currentStockLsu, totalCapacityLsu);

  String get stocking => stockingStatus(usage);

  List<StockEntry> get countedStock =>
      stock.where((entry) => entry.isCounted).toList(growable: false);

  List<StockEntry> get presentOnlyStock =>
      stock.where((entry) => !entry.isCounted).toList(growable: false);
}

class _VeldCarryHunterViewScreenState extends State<VeldCarryHunterViewScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<HunterCampVeldView> _camps = const [];
  List<FarmPermit> _permits = const [];

  /// The signed-in hunter's uid — the identity the booking gate is checked
  /// against. Null when Firebase is unavailable (cold launch / widget tests
  /// without an override), in which case the gate fails closed.
  String? _currentUid() {
    final override = widget.currentUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // The hunter must hold a booking on this farm. A missing uid fails closed:
    // the repository returns no data rather than serving an unverified caller.
    final hunterUid = _currentUid();
    try {
      final camps = <Camp>[];
      final campId = widget.campId?.trim();
      if (campId != null && campId.isNotEmpty) {
        final camp = await _repository.getCampForHunter(
          widget.farmId,
          campId,
          outfitterUid: widget.outfitterUid,
          hunterUid: hunterUid,
        );
        if (camp != null) camps.add(camp);
      } else {
        camps.addAll(
          await _repository.getCampsForHunter(
            widget.farmId,
            outfitterUid: widget.outfitterUid,
            hunterUid: hunterUid,
          ),
        );
      }

      final views = <HunterCampVeldView>[];
      for (final camp in camps) {
        var stock = const <StockEntry>[];
        var planted = const <PlantedArea>[];
        try {
          stock = await _repository.getStockForHunter(
            widget.farmId,
            camp.id,
            outfitterUid: widget.outfitterUid,
            hunterUid: hunterUid,
          );
        } catch (e) {
          // A stock read failure must not hide the camp's veld basics.
          debugPrint('VeldCarryHunterView: stock read failed: $e');
        }
        try {
          planted = await _repository.getPlantedAreasForHunter(
            widget.farmId,
            camp.id,
            outfitterUid: widget.outfitterUid,
            hunterUid: hunterUid,
          );
        } catch (e) {
          debugPrint('VeldCarryHunterView: planted read failed: $e');
        }
        views.add(
          HunterCampVeldView(camp: camp, stock: stock, planted: planted),
        );
      }

      List<FarmPermit> permits = const [];
      try {
        permits = await _repository.getPermitsForHunter(
          widget.farmId,
          outfitterUid: widget.outfitterUid,
          hunterUid: hunterUid,
        );
      } catch (e) {
        debugPrint('VeldCarryHunterView: permit read failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _camps = views;
        _permits = permits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load veld information: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return HunterScaffold(
      theme: theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Veld & Carrying Capacity',
              style: TextStyle(
                color: HunterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (widget.farmName != null && widget.farmName!.isNotEmpty)
              Text(
                widget.farmName!,
                style: TextStyle(
                  color: HunterUi.subtitleColor(theme),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeController theme) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }
    if (_error != null) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [_messageCard(theme, 'Could not load veld information', _error!)],
      );
    }
    if (_camps.isEmpty) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [
          _messageCard(
            theme,
            'No veld information shared for this camp yet.',
            'The outfitter has not published veld or carrying-capacity '
                'details for this farm.',
          ),
          const CopyrightFooter(),
        ],
      );
    }

    return ListView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      children: [
        for (final view in _camps) ...[
          _campCard(theme, view),
          const SizedBox(height: 12),
        ],
        if (_permits.isNotEmpty) _permitsCard(theme),
        const SizedBox(height: 12),
        _privacyNote(theme),
        const CopyrightFooter(),
      ],
    );
  }

  Widget _campCard(ThemeController theme, HunterCampVeldView view) {
    final camp = view.camp;
    final location = [
      if (camp.province.isNotEmpty) camp.province,
      if (camp.district.isNotEmpty) camp.district,
    ].join(' · ');

    return Container(
      key: ValueKey('veldHunterCampCard_${camp.id}'),
      padding: const EdgeInsets.all(14),
      decoration: HunterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            camp.name.isEmpty ? 'Unnamed camp' : camp.name,
            style: TextStyle(
              color: HunterUi.titleColor(theme),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              VeldCarryBadge(
                label: formatHectares(camp.totalSizeHa),
                color: theme.accentColor,
                icon: Icons.crop_square_rounded,
                darkMode: theme.isDarkMode,
              ),
              if (camp.veldType.isNotEmpty)
                VeldCarryBadge(
                  label: camp.veldType,
                  color: const Color(0xFF33691E),
                  icon: Icons.landscape_rounded,
                  darkMode: theme.isDarkMode,
                ),
              if (location.isNotEmpty)
                VeldCarryBadge(
                  label: location,
                  color: const Color(0xFF1565C0),
                  icon: Icons.place_outlined,
                  darkMode: theme.isDarkMode,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _capacityGrid(theme, view),
          const SizedBox(height: 12),
          _stockSection(theme, view),
          if (view.presentOnlyStock.isNotEmpty) ...[
            const SizedBox(height: 12),
            _presentOnlySection(theme, view),
          ],
        ],
      ),
    );
  }

  Widget _capacityGrid(ThemeController theme, HunterCampVeldView view) {
    final tiles = <({String label, String value, String key})>[
      (
        label: 'Total Capacity',
        value: formatLsu(view.totalCapacityLsu),
        key: 'veldHunterCapacityLsu_${view.camp.id}',
      ),
      (
        label: 'Current Stock',
        value: formatLsu(view.currentStockLsu),
        key: 'veldHunterStockLsu_${view.camp.id}',
      ),
      (
        label: 'Usage',
        value: formatUsagePct(view.usage),
        key: 'veldHunterUsage_${view.camp.id}',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: VeldCarrySectionLabel(
                label: 'CAPACITY SUMMARY',
                theme: theme,
              ),
            ),
            VeldCarryBadge(
              key: ValueKey('veldHunterStocking_${view.camp.id}'),
              label: stockingStatusLabel(view.stocking),
              color: stockingStatusColor(view.stocking),
              darkMode: theme.isDarkMode,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 360 ? 1 : 3;
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tile.label,
                            style: TextStyle(
                              color: HunterUi.subtitleColor(theme),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tile.value,
                            key: ValueKey(tile.key),
                            style: TextStyle(
                              color: HunterUi.titleColor(theme),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _stockSection(ThemeController theme, HunterCampVeldView view) {
    final counted = view.countedStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VeldCarrySectionLabel(label: 'GAME COUNTED', theme: theme),
        const SizedBox(height: 8),
        if (counted.isEmpty)
          Text(
            'No game counted on this camp yet.',
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          )
        else
          for (final entry in counted)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hunterSpeciesLabel(entry.speciesName),
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.count}',
                    key: ValueKey(
                      'veldHunterStockCount_${view.camp.id}_${entry.id}',
                    ),
                    style: TextStyle(
                      color: HunterUi.titleColor(theme),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _presentOnlySection(ThemeController theme, HunterCampVeldView view) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VeldCarrySectionLabel(label: 'PRESENT (NOT COUNTED)', theme: theme),
        const SizedBox(height: 8),
        for (final entry in view.presentOnlyStock)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hunterPresentOnlyLabel(entry.speciesName),
                    style: TextStyle(
                      color: HunterUi.subtitleColor(theme),
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '0 LSU',
                  style: TextStyle(
                    color: HunterUi.subtitleColor(theme),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _permitsCard(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: HunterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeldCarrySectionLabel(label: 'SHARED PERMITS', theme: theme),
          const SizedBox(height: 4),
          Text(
            'Only permit type, expiry and status are shared.',
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          for (final permit in _permits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          permitTypeLabel(permit.permitType),
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Expires ${formatPermitDate(permit.expiryDate)}',
                          style: TextStyle(
                            color: HunterUi.subtitleColor(theme),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  VeldCarryBadge(
                    key: ValueKey('veldHunterPermitStatus_${permit.id}'),
                    label: permitStatusLabel(permitStatus(permit.expiryDate)),
                    color: permitStatusColor(permitStatus(permit.expiryDate)),
                    darkMode: theme.isDarkMode,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _privacyNote(ThemeController theme) {
    return Row(
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: HunterUi.subtitleColor(theme),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Shared by the outfitter for planning only. Exact locations, '
            'stock weights and private permits are never shared.',
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageCard(ThemeController theme, String title, String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: HunterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(Icons.grass_rounded, size: 42, color: theme.accentColor),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HunterUi.titleColor(theme),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single hunter-facing entry point into [VeldCarryHunterViewScreen].
///
/// Renders NOTHING unless the farm has at least one veld camp, so a farm with
/// no published veld data shows no tile at all. Always wrap this in
/// `VeldCarryGate`: with the flag OFF it never mounts, so it performs no
/// Firestore read.
class VeldCarryHunterEntryTile extends StatefulWidget {
  const VeldCarryHunterEntryTile({
    super.key,
    required this.outfitterUid,
    required this.farmId,
    this.farmName,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String outfitterUid;
  final String farmId;
  final String? farmName;
  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in hunter's uid for the booking-gate probe.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryHunterEntryTile> createState() =>
      _VeldCarryHunterEntryTileState();
}

class _VeldCarryHunterEntryTileState extends State<VeldCarryHunterEntryTile> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _visible = false;

  /// The signed-in hunter's uid for the booking-gate probe (null when Firebase
  /// is unavailable — the gate then fails closed and no tile renders).
  String? _hunterUid() {
    final override = widget.currentUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant VeldCarryHunterEntryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.farmId != widget.farmId ||
        oldWidget.outfitterUid != widget.outfitterUid) {
      _check();
    }
  }

  Future<void> _check() async {
    if (widget.farmId.trim().isEmpty || widget.outfitterUid.trim().isEmpty) {
      return;
    }
    try {
      final camps = await _repository.getCampsForHunter(
        widget.farmId,
        outfitterUid: widget.outfitterUid,
        hunterUid: _hunterUid(),
      );
      if (!mounted) return;
      if (camps.isEmpty) return;
      setState(() => _visible = true);
    } catch (e) {
      // Fail closed: an unreadable farm shows no tile rather than a broken one.
      debugPrint('VeldCarryHunterEntryTile: camp check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = _theme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('veldHunterEntryTile'),
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VeldCarryHunterViewScreen(
                  outfitterUid: widget.outfitterUid,
                  farmId: widget.farmId,
                  farmName: widget.farmName,
                  theme: theme,
                  repository: widget.repository,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: HunterUi.cardDecoration(theme),
            child: Row(
              children: [
                Icon(Icons.grass_rounded, color: theme.accentColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Veld & Carrying Capacity',
                        style: TextStyle(
                          color: HunterUi.titleColor(theme),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Camps, capacity and permits shared by the outfitter',
                        style: TextStyle(
                          color: HunterUi.subtitleColor(theme),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.accentColor,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Species label for the hunter stock list (display name only).
String hunterSpeciesLabel(String speciesName) =>
    speciesDisplayName(speciesName);

/// "Baboon — Present, not counted".
String hunterPresentOnlyLabel(String speciesName) =>
    '${speciesDisplayName(speciesName)} — Present, not counted';
