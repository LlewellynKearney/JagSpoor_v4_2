import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/rainfall_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';
import 'package:jagspoor/features/veld_carry/models/veld_alert.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_alerts_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_detail_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_map_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_gate.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_alerts.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_feature_flag.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_report.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Lists the veld camps of one farm.
///
/// Reached only through the flag-gated "Veld Carrying Capacity" entry point on
/// the farm card. Every capacity / usage / stocking number on this screen is
/// produced by `veld_carry_calculator.dart`.
class VeldCarryCampListScreen extends StatefulWidget {
  const VeldCarryCampListScreen({
    super.key,
    required this.farmId,
    this.farmName,
    this.theme,
    this.repository,
    this.flag,
  });

  final String farmId;
  final String? farmName;
  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: inject an enabled flag so the flag-gated AppBar actions (camp
  /// map / alerts / report / hunter-access sync) can be exercised in a widget
  /// test. Defaults to the process-wide flag, which is OFF for a normal build.
  @visibleForTesting
  final VeldCarryFeatureFlag? flag;

  @override
  State<VeldCarryCampListScreen> createState() =>
      _VeldCarryCampListScreenState();
}

/// One camp plus the LSU currently recorded against it.
class _CampRow {
  const _CampRow({
    required this.camp,
    required this.totalLsu,
    required this.totalGu,
    required this.totalBu,
    required this.capacityLsu,
  });

  final Camp camp;
  final double totalLsu;
  final double totalGu;
  final double totalBu;

  /// Year-round capacity: veld capacity plus the camp's ALL_YEAR planted
  /// areas.
  final double capacityLsu;

  double get usage => usagePct(totalLsu, capacityLsu);

  String get stocking => stockingStatus(usage);
}

class _VeldCarryCampListScreenState extends State<VeldCarryCampListScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<_CampRow> _rows = const [];

  /// Critical + warning count for the badge — recomputed on every load,
  /// never stored.
  int _alertCount = 0;
  bool _exporting = false;

  /// True while the manual `allowedHunterUids` sync is running.
  bool _syncingAccess = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _currentUid() {
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
        _error = 'You must be signed in to view veld camps.';
      });
      return;
    }

    try {
      final camps = await _repository.getCamps(uid, widget.farmId);
      final rows = <_CampRow>[];
      final stockByCamp = <String, List<StockEntry>>{};
      final rainfallByCamp = <String, List<RainfallEntry>>{};
      for (final camp in camps) {
        var stockLsu = 0.0;
        var stockGu = 0.0;
        var stockBu = 0.0;
        var planted = const <PlantedArea>[];
        try {
          final stock =
              await _repository.getStockEntries(uid, widget.farmId, camp.id);
          stockByCamp[camp.id] = stock;
          stockLsu = _sumCounted(stock, (e) => e.totalLsu);
          stockGu = _sumCounted(stock, (e) => e.totalGu);
          stockBu = _sumCounted(stock, (e) => e.totalBu);
        } catch (e) {
          // A stock read failure must not hide the camp itself; report the
          // camp with zero recorded LSU and log the cause.
          debugPrint(
            'VeldCarryCampListScreen: stock read failed for camp '
            '${camp.id}: $e',
          );
        }
        try {
          planted =
              await _repository.getPlantedAreas(uid, widget.farmId, camp.id);
        } catch (e) {
          debugPrint(
            'VeldCarryCampListScreen: planted read failed for camp '
            '${camp.id}: $e',
          );
        }
        try {
          rainfallByCamp[camp.id] =
              await _repository.getRainfallEntries(uid, widget.farmId, camp.id);
        } catch (e) {
          debugPrint(
            'VeldCarryCampListScreen: rainfall read failed for camp '
            '${camp.id}: $e',
          );
        }
        rows.add(
          _CampRow(
            camp: camp,
            totalLsu: stockLsu,
            totalGu: stockGu,
            totalBu: stockBu,
            capacityLsu: _capacityLsu(camp, planted),
          ),
        );
      }

      // Alerts are derived from the SAME records this screen already read (plus
      // the farm's permits), so the badge costs one extra read, not a second
      // pass over every camp. A permit read failure only drops the permit
      // alerts; the camp alerts still render.
      var alerts = const <VeldAlert>[];
      try {
        final permits = await _repository.getPermits(uid, widget.farmId);
        alerts = buildAlerts(
          camps: camps,
          stockByCamp: stockByCamp,
          permits: permits,
          rainfallByCamp: rainfallByCamp,
        );
      } catch (e) {
        debugPrint('VeldCarryCampListScreen: alert build failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _alertCount = criticalAndWarningCount(alerts);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load camps: $e';
      });
    }
  }

  /// Sum of the counted species' LSU — the calculator owns `totalLsu` on each
  /// row, so this is a plain sum, not a second formula.
  double _sumCounted(
    List<StockEntry> stock,
    double Function(StockEntry) selector,
  ) {
    var total = 0.0;
    for (final entry in stock) {
      if (entry.isCounted) total += selector(entry);
    }
    return total;
  }

  /// Year-round capacity: veld capacity plus the camp's ALL_YEAR planted
  /// areas. Seasonal plantings are reported separately and never inflate this
  /// figure.
  double _capacityLsu(Camp camp, List<PlantedArea> planted) {
    final effective =
        effectiveHaPerLsu(camp.deptNormHaPerLsu, camp.veldCondition);
    final veld = veldCapacityLsu(camp.totalSizeHa, effective);
    return yearRoundCapacityLsu(veld, planted);
  }

  Future<void> _openDetail(_CampRow row) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryCampDetailScreen(
          camp: row.camp,
          farmId: widget.farmId,
          farmName: widget.farmName,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    // The detail screen can add, edit or delete stock / planted areas, all of
    // which move the usage figure — always re-read on return.
    if (mounted) await _load();
  }

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryCampFormScreen(
          farmId: widget.farmId,
          farmName: widget.farmName,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _load();
    }
  }

  /// Opens the farm's alert list. The badge count is refreshed on return
  /// because the underlying records may have changed while it was open.
  Future<void> _openAlerts() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryAlertsScreen(
          farmId: widget.farmId,
          farmName: widget.farmName,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    if (mounted) await _load();
  }

  /// Opens the outfitter-only camp map. Re-read on return because a camp's
  /// location can be set or moved from the detail screen.
  Future<void> _openMap() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VeldCarryCampMapScreen(
          farmId: widget.farmId,
          farmName: widget.farmName,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    if (mounted) await _load();
  }

  /// Builds the whole-farm veld report and hands it to the OS share sheet
  /// through the app's existing branded PDF engine.
  Future<void> _exportFarmReport() async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to export a veld report.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final report = await _repository.getVeldReportForFarm(
        uid,
        Farm(id: widget.farmId, name: widget.farmName ?? ''),
      );
      await VeldReportPdfExporter().generateAndShare(report);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Veld report generated for ${report.farmName}.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      debugPrint('VeldCarryCampListScreen: report export failed: $e');
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not export the veld report: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Mirrors the farm's confirmed/completed bookings onto every camp as
  /// `allowedHunterUids`, so the go-live Firestore rule can gate a hunter read.
  ///
  /// MANUAL ONLY (Phase 7D): the shared booking-confirmation path
  /// (`PackageBookingManager.confirmPaymentReceived`) is deliberately NOT
  /// hooked — that file is read-only for this work, and a veld write from the
  /// booking path would run this feature's I/O from code that must stay dark
  /// while the flag is OFF. The outfitter runs the sync here instead (and can
  /// re-run it whenever a booking is confirmed).
  Future<void> _syncHunterAccess() async {
    if (_syncingAccess) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to sync hunter access.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _syncingAccess = true);
    try {
      final result = await _repository.syncAllowedHuntersForFarm(
        widget.farmId,
        outfitterUid: uid,
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Hunter access synced: ${result.summary}.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      debugPrint('VeldCarryCampListScreen: hunter access sync failed: $e');
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not sync hunter access: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _syncingAccess = false);
    }
  }

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
              'Veld Carrying Capacity',
              style: TextStyle(
                color: OutfitterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
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
          // Camp map — outfitter-only. Flag-gated like every other entry, so
          // with the feature flag off there is no icon and no Firestore read.
          VeldCarryGate(
            flag: widget.flag,
            builder: (context) => OutfitterActionChip(
              key: const ValueKey('veldFarmMapButton'),
              icon: Icons.map_outlined,
              tooltip: 'Camp map',
              iconColor: theme.accentColor,
              onPressed: _openMap,
            ),
          ),
          // Alerts entry + live critical/warning badge — flag-gated: renders
          // nothing (no icon, no space) while the feature flag is off.
          VeldCarryGate(
            flag: widget.flag,
            builder: (context) => VeldAlertCountBadge(
              count: _alertCount,
              child: OutfitterActionChip(
                key: const ValueKey('veldFarmAlertsButton'),
                icon: Icons.notifications_active_outlined,
                tooltip: _alertCount > 0
                    ? 'Veld alerts ($_alertCount need attention)'
                    : 'Veld alerts',
                iconColor: theme.accentColor,
                onPressed: _openAlerts,
              ),
            ),
          ),
          // Whole-farm veld report — flag-gated.
          VeldCarryGate(
            flag: widget.flag,
            builder: (context) => OutfitterActionChip(
              key: const ValueKey('veldFarmReportButton'),
              icon: _exporting
                  ? Icons.hourglass_top_rounded
                  : Icons.picture_as_pdf_rounded,
              tooltip: 'Export veld report (PDF)',
              iconColor: theme.accentColor,
              onPressed: _exporting ? null : _exportFarmReport,
            ),
          ),
          // Manual `allowedHunterUids` sync — outfitter-only, flag-gated. The
          // booking path is NOT hooked (see `_syncHunterAccess`), so this is the
          // one place the go-live rule's allow-list gets refreshed.
          VeldCarryGate(
            flag: widget.flag,
            builder: (context) => OutfitterActionChip(
              key: const ValueKey('veldSyncHunterAccessButton'),
              icon: _syncingAccess
                  ? Icons.hourglass_top_rounded
                  : Icons.group_add_outlined,
              tooltip: 'Sync hunter access (confirmed bookings)',
              iconColor: theme.accentColor,
              onPressed: _syncingAccess ? null : _syncHunterAccess,
            ),
          ),
          OutfitterActionChip(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh camps',
            iconColor: theme.accentColor,
            onPressed: _loading ? null : _load,
          ),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: theme.accentColor,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Camp',
          style: TextStyle(fontWeight: FontWeight.bold),
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
        children: [
          _errorState(theme, _error!),
        ],
      );
    }
    if (_rows.isEmpty) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [
          _emptyState(theme),
          const CopyrightFooter(),
        ],
      );
    }
    return ListView.builder(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      itemCount: _rows.length + 1,
      itemBuilder: (context, index) {
        if (index == _rows.length) return const CopyrightFooter();
        return _campCard(theme, _rows[index]);
      },
    );
  }

  Widget _campCard(ThemeController theme, _CampRow row) {
    final camp = row.camp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('veldCampCard_${camp.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openDetail(row),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: OutfitterUi.cardDecoration(theme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        camp.name.isEmpty ? 'Unnamed camp' : camp.name,
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: theme.accentColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatHectares(camp.totalSizeHa)} · '
                  '${camp.veldType.isEmpty ? 'Veld type not set' : camp.veldType}',
                  style: TextStyle(
                    color: OutfitterUi.subtitleColor(theme),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    VeldCarryBadge(
                      label: veldConditionLabel(camp.veldCondition),
                      color: veldConditionColor(camp.veldCondition),
                      icon: Icons.eco_rounded,
                      darkMode: theme.isDarkMode,
                    ),
                    VeldCarryBadge(
                      label: formatLsu(row.capacityLsu),
                      color: theme.accentColor,
                      icon: Icons.speed_rounded,
                      darkMode: theme.isDarkMode,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: OutfitterUi.subtitleColor(theme)
                      .withValues(alpha: 0.15),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.pie_chart_outline_rounded,
                      size: 16,
                      color: OutfitterUi.subtitleColor(theme),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Usage ${formatUsagePct(row.usage)}',
                      key: ValueKey('veldCampUsage_${camp.id}'),
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(theme),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    VeldCarryBadge(
                      label: stockingStatusLabel(row.stocking),
                      color: stockingStatusColor(row.stocking),
                      darkMode: theme.isDarkMode,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Recorded stock: ${formatLsu(row.totalLsu)} · '
                  'G ${formatLsu(row.totalGu)} / B ${formatLsu(row.totalBu)}',
                  style: TextStyle(
                    color: OutfitterUi.subtitleColor(theme),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(
            Icons.grass_rounded,
            size: 48,
            color: theme.accentColor.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'No camps yet — add your first camp',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A camp carries its own size, veld type and condition so the '
            'carrying capacity can be worked out per camp.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _openForm(),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'ADD CAMP',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(ThemeController theme, String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 44,
            color: Colors.red.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Text(
            'Unable to load camps',
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
            label: const Text(
              'RETRY',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
