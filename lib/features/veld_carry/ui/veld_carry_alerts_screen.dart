import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/veld_alert.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Outfitter-only alerts list for one farm.
///
/// Alerts are computed from live data on every load (`buildAlerts`) and are
/// **never stored**. Dismissing an alert hides it for this screen session only:
/// nothing is written to Firestore, so a dismissed alert reappears the next
/// time the screen is opened. That is deliberate for this phase — an outfitter
/// can silence a warning while working, but cannot permanently suppress a real
/// overstocking or expired-permit condition.
///
/// Rendered only inside `VeldCarryGate`, so with the feature flag OFF (the
/// default build) this screen cannot be reached.
class VeldCarryAlertsScreen extends StatefulWidget {
  const VeldCarryAlertsScreen({
    super.key,
    required this.farmId,
    this.farmName,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String farmId;
  final String? farmName;
  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryAlertsScreen> createState() => _VeldCarryAlertsScreenState();
}

class _VeldCarryAlertsScreenState extends State<VeldCarryAlertsScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<VeldAlert> _alerts = const [];

  /// Session-only dismissals — never persisted (see the class doc).
  final Set<String> _dismissedIds = <String>{};

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
        _error = 'You must be signed in to view veld alerts.';
      });
      return;
    }
    try {
      final alerts = await _repository.getAlertsForFarm(uid, widget.farmId);
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load veld alerts: $e';
      });
    }
  }

  void _dismiss(VeldAlert alert) {
    setState(() => _dismissedIds.add(alert.id));
  }

  void _restoreDismissed() {
    setState(_dismissedIds.clear);
  }

  List<VeldAlert> get _visible =>
      _alerts.where((a) => !_dismissedIds.contains(a.id)).toList();

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
              'Veld Alerts',
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
          OutfitterActionChip(
            key: const ValueKey('veldAlertsRefreshButton'),
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh alerts',
            iconColor: theme.accentColor,
            onPressed: _loading ? null : _load,
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
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: OutfitterUi.cardDecoration(theme),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.red.shade700),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: OutfitterUi.subtitleColor(theme)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('RETRY'),
                ),
              ],
            ),
          ),
          const CopyrightFooter(),
        ],
      );
    }

    final visible = _visible;
    final dismissedCount = _alerts.length - visible.length;

    return ListView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      children: [
        _summaryCard(theme, visible),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          _emptyState(theme)
        else
          for (final severity in VeldAlert.severities) ...[
            ..._severitySection(
              theme,
              severity,
              visible.where((a) => a.severity == severity).toList(),
            ),
          ],
        if (dismissedCount > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 16,
                color: OutfitterUi.subtitleColor(theme),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$dismissedCount dismissed this session — they reappear on '
                  'the next load.',
                  style: TextStyle(
                    color: OutfitterUi.subtitleColor(theme),
                    fontSize: 11,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('veldAlertsRestoreButton'),
                onPressed: _restoreDismissed,
                child: const Text('RESTORE'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Alerts are computed from live camps, stock, permits and rainfall — '
          'nothing is stored, and dismissals are session-only.',
          style: TextStyle(
            color: OutfitterUi.subtitleColor(theme),
            fontSize: 11,
          ),
        ),
        const CopyrightFooter(),
      ],
    );
  }

  Widget _summaryCard(ThemeController theme, List<VeldAlert> visible) {
    final critical = visible.where((a) => a.isCritical).length;
    final warning = visible.where((a) => a.isWarning).length;
    final info = visible.where((a) => !a.isCritical && !a.isWarning).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded, color: theme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              visible.isEmpty
                  ? 'No alerts — nothing needs your attention.'
                  : '$critical critical · $warning warning · $info info',
              style: TextStyle(
                color: OutfitterUi.titleColor(theme),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _severitySection(
    ThemeController theme,
    String severity,
    List<VeldAlert> alerts,
  ) {
    if (alerts.isEmpty) return const <Widget>[];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Row(
          children: [
            VeldCarryBadge(
              label: '${_severityLabel(severity).toUpperCase()} (${alerts.length})',
              color: _severityColor(severity),
              icon: _severityIcon(severity),
              darkMode: theme.isDarkMode,
            ),
          ],
        ),
      ),
      for (final alert in alerts) _alertCard(theme, alert),
    ];
  }

  Widget _alertCard(ThemeController theme, VeldAlert alert) {
    final color = _severityColor(alert.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: ValueKey('veldAlertCard_${alert.id}'),
        padding: const EdgeInsets.all(12),
        decoration: OutfitterUi.cardDecoration(theme).copyWith(
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_severityIcon(alert.severity), color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: TextStyle(
                      color: OutfitterUi.titleColor(theme),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.message,
                    style: TextStyle(
                      color: OutfitterUi.subtitleColor(theme),
                      fontSize: 12,
                    ),
                  ),
                  if (alert.isFarmWide)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Farm-wide',
                        style: TextStyle(
                          color: OutfitterUi.subtitleColor(theme),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('veldAlertDismiss_${alert.id}'),
              tooltip: 'Dismiss for this session',
              icon: Icon(Icons.close_rounded, size: 18, color: color),
              onPressed: () => _dismiss(alert),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 36, color: Colors.green.shade600),
          const SizedBox(height: 10),
          Text(
            'No veld alerts for this farm.',
            style: TextStyle(
              color: OutfitterUi.titleColor(theme),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Stocking, permits and rainfall are all within limits.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

String _severityLabel(String severity) {
  switch (severity) {
    case VeldAlert.severityCritical:
      return 'Critical';
    case VeldAlert.severityWarning:
      return 'Warning';
    case VeldAlert.severityInfo:
    default:
      return 'Info';
  }
}

Color _severityColor(String severity) {
  switch (severity) {
    case VeldAlert.severityCritical:
      return const Color(0xFFB71C1C);
    case VeldAlert.severityWarning:
      return const Color(0xFFB26A00);
    case VeldAlert.severityInfo:
    default:
      return const Color(0xFF1565C0);
  }
}

IconData _severityIcon(String severity) {
  switch (severity) {
    case VeldAlert.severityCritical:
      return Icons.error_rounded;
    case VeldAlert.severityWarning:
      return Icons.warning_amber_rounded;
    case VeldAlert.severityInfo:
    default:
      return Icons.info_outline_rounded;
  }
}

/// Wraps [child] with a small count bubble — nothing renders when [count] is 0,
/// so an entry point never shows an empty badge.
class VeldAlertCountBadge extends StatelessWidget {
  const VeldAlertCountBadge({
    super.key,
    required this.count,
    required this.child,
  });

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            key: const ValueKey('veldAlertCountBadge'),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFB71C1C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
