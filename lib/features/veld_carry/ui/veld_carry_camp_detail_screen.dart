import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/predator_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_planted_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_predator_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_stock_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';

/// Everything recorded against one camp, plus its live carrying-capacity
/// summary.
///
/// Only reachable by tapping a camp on [VeldCarryCampListScreen], which is
/// itself reached solely through `VeldCarryGate` — so with the feature flag
/// OFF none of this UI can appear. Every number on this screen is produced by
/// `veld_carry_calculator.dart`.
class VeldCarryCampDetailScreen extends StatefulWidget {
  const VeldCarryCampDetailScreen({
    super.key,
    required this.camp,
    required this.farmId,
    this.farmName,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final Camp camp;
  final String farmId;
  final String? farmName;
  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryCampDetailScreen> createState() =>
      _VeldCarryCampDetailScreenState();
}

class _VeldCarryCampDetailScreenState extends State<VeldCarryCampDetailScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  late Camp _camp = widget.camp;

  bool _loading = true;
  String? _error;
  bool _deleting = false;

  List<StockEntry> _stock = const [];
  List<PlantedArea> _planted = const [];
  List<PredatorEntry> _predators = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _currentUid() {
    final override = widget.currentUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view this camp.';
      });
      return;
    }
    try {
      final stock =
          await _repository.getStockEntries(uid, widget.farmId, _camp.id);
      final planted =
          await _repository.getPlantedAreas(uid, widget.farmId, _camp.id);
      final predators =
          await _repository.getPredators(uid, widget.farmId, _camp.id);
      if (!mounted) return;
      setState(() {
        _stock = stock;
        _planted = planted;
        _predators = predators;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load camp records: $e';
      });
    }
  }

  // ── Capacity maths (calculator only) ─────────────────────────────────

  double get _effectiveHaPerLsu =>
      effectiveHaPerLsu(_camp.deptNormHaPerLsu, _camp.veldCondition);

  double get _veldCapacityLsu =>
      veldCapacityLsu(_camp.totalSizeHa, _effectiveHaPerLsu);

  /// Planted capacity from the ALL_YEAR areas only.
  ///
  /// `yearRoundCapacityLsu(0, areas)` sums the year-round planted areas and
  /// nothing else, so the planted share is never double-counted with the veld
  /// capacity.
  double get _plantedCapacityLsu => yearRoundCapacityLsu(0, _planted);

  double get _totalCapacityLsu => yearRoundCapacityLsu(_veldCapacityLsu, _planted);

  double get _stockLsu => _sumCounted((e) => e.totalLsu);
  double get _stockGu => _sumCounted((e) => e.totalGu);
  double get _stockBu => _sumCounted((e) => e.totalBu);

  double _sumCounted(double Function(StockEntry) selector) {
    var total = 0.0;
    for (final entry in _stock) {
      if (entry.isCounted) total += selector(entry);
    }
    return total;
  }

  double get _usage => usagePct(_stockLsu, _totalCapacityLsu);
  double get _headroom => headroomLsu(_totalCapacityLsu, _stockLsu);
  String get _stocking => stockingStatus(_usage);

  List<StockEntry> get _countedStock =>
      _stock.where((e) => e.isCounted).toList(growable: false);
  List<StockEntry> get _presentOnlyStock =>
      _stock.where((e) => !e.isCounted).toList(growable: false);

  // ── Navigation ───────────────────────────────────────────────────────

  Future<void> _openCampForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryCampFormScreen(
          farmId: widget.farmId,
          farmName: widget.farmName,
          existingCamp: _camp,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final uid = _currentUid();
    if (uid == null) return;
    try {
      final refreshed =
          await _repository.getCamp(uid, widget.farmId, _camp.id);
      if (!mounted) return;
      if (refreshed != null) setState(() => _camp = refreshed);
    } catch (e) {
      // The save already succeeded; a failed refresh only means the header is
      // stale, so keep the screen usable and log the cause.
      debugPrint('VeldCarryCampDetailScreen: camp refresh failed: $e');
    }
  }

  Future<void> _openStockForm({StockEntry? entry}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryStockFormScreen(
          farmId: widget.farmId,
          campId: _camp.id,
          existingEntry: entry,
          existingSpecies: _stock.map((e) => e.speciesName).toList(),
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _openPlantedForm({PlantedArea? area}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryPlantedFormScreen(
          farmId: widget.farmId,
          campId: _camp.id,
          existingArea: area,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _openPredatorForm({PredatorEntry? entry}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryPredatorFormScreen(
          farmId: widget.farmId,
          campId: _camp.id,
          existingEntry: entry,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  // ── Deletes ──────────────────────────────────────────────────────────

  Future<bool> _confirm(String title, String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteStock(StockEntry entry) async {
    final uid = _currentUid();
    if (uid == null) return;
    final confirmed = await _confirm(
      'Delete ${speciesDisplayName(entry.speciesName)}?',
      'This removes the species from the camp stock ledger.',
      'DELETE',
    );
    if (!confirmed) return;
    try {
      await _repository.deleteStockEntry(uid, widget.farmId, _camp.id, entry.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Could not delete stock entry: $e', Colors.red.shade700);
    }
  }

  Future<void> _deletePlanted(PlantedArea area) async {
    final uid = _currentUid();
    if (uid == null) return;
    final confirmed = await _confirm(
      'Delete planted area?',
      'This removes the planted area from the camp feed total.',
      'DELETE',
    );
    if (!confirmed) return;
    try {
      await _repository.deletePlantedArea(uid, widget.farmId, _camp.id, area.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Could not delete planted area: $e', Colors.red.shade700);
    }
  }

  Future<void> _deletePredator(PredatorEntry entry) async {
    final uid = _currentUid();
    if (uid == null) return;
    final confirmed = await _confirm(
      'Delete ${entry.predatorName}?',
      'This removes the predator record from the camp.',
      'DELETE',
    );
    if (!confirmed) return;
    try {
      await _repository.deletePredatorEntry(
          uid, widget.farmId, _camp.id, entry.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Could not delete predator: $e', Colors.red.shade700);
    }
  }

  /// Deletes the camp and every child record.
  ///
  /// Firestore never cascades a delete into subcollections, so the children are
  /// removed explicitly first. A child that cannot be removed is counted and
  /// reported to the operator — it is never silently left behind.
  Future<void> _deleteCamp() async {
    final uid = _currentUid();
    if (uid == null) return;
    final confirmed = await _confirm(
      'Delete camp "${_camp.name}"?',
      'This deletes the camp and all of its stock, planted areas and predator '
          'records. This cannot be undone.',
      'DELETE CAMP',
    );
    if (!confirmed) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _deleting = true);

    var orphaned = 0;
    Future<void> removeChild(Future<void> Function() remove) async {
      try {
        await remove();
      } catch (e) {
        orphaned++;
        debugPrint('VeldCarryCampDetailScreen: child delete failed: $e');
      }
    }

    try {
      for (final entry in _stock) {
        await removeChild(() =>
            _repository.deleteStockEntry(uid, widget.farmId, _camp.id, entry.id));
      }
      for (final area in _planted) {
        await removeChild(() => _repository
            .deletePlantedArea(uid, widget.farmId, _camp.id, area.id));
      }
      for (final entry in _predators) {
        await removeChild(() => _repository
            .deletePredatorEntry(uid, widget.farmId, _camp.id, entry.id));
      }
      await _repository.deleteCamp(uid, widget.farmId, _camp.id);
      if (!mounted) return;
      navigator.pop(true);
      if (orphaned > 0) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Camp deleted, but $orphaned child record(s) could not be '
              'removed — they will be cleaned up in Phase 6.',
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      } else {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Camp "${_camp.name}" deleted.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _snack('Could not delete camp: $e', Colors.red.shade700);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _camp.name.isEmpty ? 'Unnamed camp' : _camp.name,
              style: TextStyle(
                color: OutfitterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.farmName != null && widget.farmName!.isNotEmpty)
              Text(
                widget.farmName!,
                style: TextStyle(
                  color: OutfitterUi.subtitleColor(theme),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          OutfitterActionChip(
            key: const ValueKey('veldCampDeleteButton'),
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete camp',
            iconColor: theme.accentColor,
            onPressed: _deleting ? null : _deleteCamp,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: OutfitterBushveldBackground.stack(
        fallbackColor: theme.backgroundColor,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(theme),
          ),
        ),
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
        children: [_errorState(theme, _error!)],
      );
    }
    return ListView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      children: [
        _headerCard(theme),
        const SizedBox(height: 12),
        _summaryGrid(theme),
        const SizedBox(height: 16),
        _stockSection(theme),
        const SizedBox(height: 16),
        _plantedSection(theme),
        const SizedBox(height: 16),
        _predatorSection(theme),
        if (_presentOnlyStock.isNotEmpty) ...[
          const SizedBox(height: 16),
          _presentOnlySection(theme),
        ],
        const SizedBox(height: 20),
        _editCampButton(theme),
        const SizedBox(height: 8),
        const CopyrightFooter(),
      ],
    );
  }

  Widget _headerCard(ThemeController theme) {
    final location = [
      if (_camp.province.isNotEmpty) _camp.province,
      if (_camp.district.isNotEmpty) _camp.district,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              VeldCarryBadge(
                label: formatHectares(_camp.totalSizeHa),
                color: theme.accentColor,
                icon: Icons.crop_square_rounded,
                darkMode: theme.isDarkMode,
              ),
              VeldCarryBadge(
                label: veldConditionLabel(_camp.veldCondition),
                color: veldConditionColor(_camp.veldCondition),
                icon: Icons.eco_rounded,
                darkMode: theme.isDarkMode,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(theme, 'Location', location.isEmpty ? 'Not set' : location),
          _infoRow(
            theme,
            'Veld type',
            _camp.veldType.isEmpty ? 'Not set' : _camp.veldType,
          ),
          _infoRow(
            theme,
            'Department norm',
            _camp.deptNormHaPerLsu > 0
                ? '${_formatNumber(_camp.deptNormHaPerLsu)} ha/LSU'
                : 'Not set',
          ),
          _infoRow(
            theme,
            'Effective norm',
            _effectiveHaPerLsu > 0
                ? '${_formatNumber(_effectiveHaPerLsu)} ha/LSU'
                : 'Not set',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(ThemeController theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(ThemeController theme) {
    final tiles = <_SummaryTile>[
      _SummaryTile('Veld Capacity', formatLsu(_veldCapacityLsu)),
      _SummaryTile('Planted Capacity', formatLsu(_plantedCapacityLsu)),
      _SummaryTile('Total Capacity', formatLsu(_totalCapacityLsu)),
      _SummaryTile('Current Stock', formatLsu(_stockLsu)),
      _SummaryTile('Grazer Units', formatLsu(_stockGu)),
      _SummaryTile('Browser Units', formatLsu(_stockBu)),
      _SummaryTile('Usage', formatUsagePct(_usage)),
      _SummaryTile(
        'Headroom',
        _headroom < 0
            ? '${formatLsu(_headroom.abs())} over'
            : formatLsu(_headroom),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VeldCarrySectionLabel(label: 'CAPACITY SUMMARY', theme: theme),
              const Spacer(),
              VeldCarryBadge(
                key: const ValueKey('veldCampStockingBadge'),
                label: stockingStatusLabel(_stocking),
                color: stockingStatusColor(_stocking),
                darkMode: theme.isDarkMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 340 ? 1 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width: width,
                      child: _summaryTile(theme, tile.label, tile.value),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(ThemeController theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: OutfitterUi.cardColor(theme).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OutfitterUi.cardBorderColor(theme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _stockSection(ThemeController theme) {
    return _section(
      theme,
      title: 'STOCK',
      count: _countedStock.length,
      addKey: const ValueKey('veldCampAddStockButton'),
      onAdd: () => _openStockForm(),
      emptyText: 'No counted stock recorded yet.',
      children: [
        for (final entry in _countedStock)
          _listRow(
            theme,
            key: ValueKey('veldStockRow_${entry.id}'),
            title: speciesDisplayName(entry.speciesName),
            subtitle: '${entry.count} head · '
                '${formatLsu(entry.totalLsu)} · '
                'G ${formatLsu(entry.totalGu)} / B ${formatLsu(entry.totalBu)}',
            onEdit: () => _openStockForm(entry: entry),
            onDelete: () => _deleteStock(entry),
          ),
      ],
    );
  }

  Widget _plantedSection(ThemeController theme) {
    return _section(
      theme,
      title: 'PLANTED FEED',
      count: _planted.length,
      addKey: const ValueKey('veldCampAddPlantedButton'),
      onAdd: () => _openPlantedForm(),
      emptyText: 'No planted feed areas recorded yet.',
      children: [
        for (final area in _planted)
          _listRow(
            theme,
            key: ValueKey('veldPlantedRow_${area.id}'),
            title: plantedFeedLabel(area),
            subtitle: '${formatHectares(area.areaHa)} · '
                '${formatLsu(area.capacityLsu)} · '
                '${plantedSeasonLabel(area.season)}',
            onEdit: () => _openPlantedForm(area: area),
            onDelete: () => _deletePlanted(area),
          ),
      ],
    );
  }

  Widget _predatorSection(ThemeController theme) {
    return _section(
      theme,
      title: 'PREDATORS',
      count: _predators.length,
      addKey: const ValueKey('veldCampAddPredatorButton'),
      onAdd: () => _openPredatorForm(),
      emptyText: 'No predators recorded yet.',
      footnote: 'Predators do not count towards veld capacity.',
      children: [
        for (final entry in _predators)
          _listRow(
            theme,
            key: ValueKey('veldPredatorRow_${entry.id}'),
            title: entry.predatorName,
            subtitle: '${entry.count} · '
                '${entry.preyKgPerYear.toStringAsFixed(0)} kg prey/yr · '
                '${entry.preyAnimalsPerYear.toStringAsFixed(0)} animals/yr',
            onEdit: () => _openPredatorForm(entry: entry),
            onDelete: () => _deletePredator(entry),
          ),
      ],
    );
  }

  Widget _presentOnlySection(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeldCarrySectionLabel(
            label: 'PRESENT, NOT COUNTED — 0 LSU',
            theme: theme,
          ),
          const SizedBox(height: 4),
          Text(
            'Recorded for information only; never included in the totals.',
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in _presentOnlyStock)
            _listRow(
              theme,
              key: ValueKey('veldPresentOnlyRow_${entry.id}'),
              title: speciesDisplayName(entry.speciesName),
              subtitle: '${entry.count} present — 0 LSU',
              onEdit: () => _openStockForm(entry: entry),
              onDelete: () => _deleteStock(entry),
            ),
        ],
      ),
    );
  }

  Widget _section(
    ThemeController theme, {
    required String title,
    required int count,
    required Key addKey,
    required VoidCallback onAdd,
    required String emptyText,
    String? footnote,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VeldCarrySectionLabel(label: title, theme: theme),
              const SizedBox(width: 6),
              Text(
                '($count)',
                style: TextStyle(
                  color: OutfitterUi.subtitleColor(theme),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                key: addKey,
                onPressed: onAdd,
                icon: Icon(Icons.add_rounded, size: 18,
                    color: theme.accentColor),
                label: Text(
                  'Add',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 2),
            Text(
              footnote,
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (children.isEmpty)
            Text(
              emptyText,
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 12,
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }

  Widget _listRow(
    ThemeController theme, {
    required Key key,
    required String title,
    required String subtitle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: OutfitterUi.subtitleColor(theme),
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('${key.toString()}_edit'),
            onPressed: onEdit,
            icon: Icon(Icons.edit_rounded, size: 18, color: theme.accentColor),
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            key: ValueKey('${key.toString()}_delete'),
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded,
                size: 18, color: Colors.red.shade400),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _editCampButton(ThemeController theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        key: const ValueKey('veldCampEditButton'),
        onPressed: _openCampForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text(
          'EDIT CAMP',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _errorState(ThemeController theme, String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 44, color: Colors.red.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            'Unable to load camp records',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('RETRY',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile {
  const _SummaryTile(this.label, this.value);

  final String label;
  final String value;
}

String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
