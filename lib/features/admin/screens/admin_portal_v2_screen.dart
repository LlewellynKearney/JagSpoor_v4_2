import 'package:flutter/material.dart';

import '../../../core/layout/web_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/admin_user_metrics.dart';
import '../services/admin_analytics_service.dart';
import '../services/admin_auth_guard.dart';
import '../services/admin_user_metrics_service.dart';
import '../widgets/admin_mode_switcher.dart';

/// Admin Portal V2 — the next-generation admin surface.
///
/// V2 fetches the `users` collection ONCE and aggregates locally, so the
/// date-range filter (Today / 7d / 30d / All Time) re-runs the aggregation
/// without another Firestore read. The filter applies ONLY to the New Users
/// metric; the trial / subscription figures are point-in-time snapshots
/// ("as of now").
///
/// Trial / premium activity is COMPUTED from the stored fields
/// (`trialEndsAt` / `trialStart` / `subscriptionStatus` / `premiumExpiry`)
/// using the same resolution as `entitlement_service.dart` — the stored
/// `isTrialActive` / `isPremiumActive` / `trialEndDate` fields do not exist.
class AdminPortalV2Screen extends StatefulWidget {
  final ThemeController theme;

  const AdminPortalV2Screen({super.key, required this.theme});

  @override
  State<AdminPortalV2Screen> createState() => _AdminPortalV2ScreenState();
}

class _AdminPortalV2ScreenState extends State<AdminPortalV2Screen> {
  final AdminAuthGuard _guard = AdminAuthGuard.instance;

  /// The raw user records, fetched ONCE. Every filter change re-aggregates
  /// from this list locally — no further Firestore reads.
  List<AdminUserRecord> _records = const [];

  AdminDateFilter _filter = AdminDateFilter.allTime;

  AdminUserMetrics _metrics = const AdminUserMetrics();

  bool _loading = true;
  bool _authorized = false;
  String? _error;

  /// True once the user documents have been fetched (so a filter change can
  /// re-aggregate locally instead of refetching).
  bool _recordsLoaded = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _authorized = await _guard.isCurrentUserAdmin();
      if (!_authorized) {
        setState(() {
          _loading = false;
          _error =
              'Access denied. This portal is restricted to platform admins.';
        });
        return;
      }
      final records = await AdminUserMetricsService.instance.fetchRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
        _recordsLoaded = true;
        _metrics = AdminUserMetrics.aggregate(records, filter: _filter);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load portal metrics: $e';
      });
    }
  }

  /// Re-runs the aggregation locally for the newly selected filter. No
  /// Firestore read — [AdminUserMetrics.aggregate] is pure.
  void _onFilterChanged(AdminDateFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      if (_recordsLoaded) {
        _metrics = AdminUserMetrics.aggregate(_records, filter: _filter);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          appBar: AppBar(
            title: const Text('🛡️ Admin Portal V2'),
            backgroundColor: widget.theme.backgroundColor,
            foregroundColor: widget.theme.textColor,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: _bootstrap,
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Sign out',
                onPressed: () async {
                  await AdminAnalyticsService.instance.signOut();
                  if (!mounted || !context.mounted) return;
                  Navigator.pushReplacementNamed(context, '/');
                },
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError()
                  : RefreshIndicator(
                      onRefresh: _bootstrap,
                      child: WebLayout.responsive(
                        context: context,
                        maxWidth: WebLayout.webDashboardMaxWidth,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              16, 8, 16, SafeBottomInset.of(context)),
                          children: [
                            AdminModeSwitcher(
                              theme: widget.theme,
                              activeMode: AdminMode.admin,
                            ),
                            _buildSectionHeader('Audience'),
                            _buildFilterBar(),
                            const SizedBox(height: 12),
                            _buildUserGrid(),
                            _buildUnknownPlanNote(),
                            _buildSnapshotNote(),
                          ],
                        ),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: widget.theme.accentColor),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.theme.textColor),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/'),
              child: const Text('Back to login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: widget.theme.accentColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// The date-range filter chips. Changing the filter re-aggregates locally.
  Widget _buildFilterBar() {
    return Wrap(
      key: const ValueKey('adminV2DateFilterBar'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in AdminDateFilter.values)
          ChoiceChip(
            key: ValueKey('adminV2Filter_${filter.name}'),
            label: Text(filter.label),
            selected: _filter == filter,
            onSelected: (_) => _onFilterChanged(filter),
            selectedColor: widget.theme.accentColor.withAlpha(60),
            labelStyle: TextStyle(
              color: _filter == filter
                  ? widget.theme.textColor
                  : widget.theme.subtitleColor,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: widget.theme.cardColor,
            side: BorderSide(color: widget.theme.textColor.withAlpha(20)),
          ),
      ],
    );
  }

  /// The user-level KPI grid: New Users (filter-dependent) + the five Task 3
  /// trial / subscription cards (point-in-time snapshots).
  Widget _buildUserGrid() {
    final m = _metrics;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _metricCard(
          Icons.person_add_alt_1_outlined,
          'New Users (${_filter.label})',
          m.newUsers,
          key: const ValueKey('adminV2CardNewUsers'),
        ),
        _metricCard(
          Icons.hourglass_top_rounded,
          'Trial Active',
          m.trialActive,
          key: const ValueKey('adminV2CardTrialActive'),
        ),
        _metricCard(
          Icons.timer_off_outlined,
          'Trial Expired — No Sub',
          m.trialExpiredNoSub,
          key: const ValueKey('adminV2CardTrialExpiredNoSub'),
        ),
        _metricCard(
          Icons.person_outline,
          'Subscribed Hunters',
          m.subscribedHunters,
          key: const ValueKey('adminV2CardSubscribedHunters'),
        ),
        _metricCard(
          Icons.business_outlined,
          'Subscribed Outfitters',
          m.subscribedOutfitters,
          key: const ValueKey('adminV2CardSubscribedOutfitters'),
        ),
        _metricCard(
          Icons.trending_up_rounded,
          'Trial → Paid Conversion',
          null,
          valueLabel: m.trialToPaidConversionLabel,
          key: const ValueKey('adminV2CardTrialToPaidConversion'),
        ),
      ],
    );
  }

  /// The "Unknown" plan bucket note. Shown only when at least one active
  /// subscriber is missing a plan (`subscriptionProduct`) — so the plan split
  /// reconciles instead of silently dropping those accounts.
  Widget _buildUnknownPlanNote() {
    final unknown = _metrics.unknownPlanSubscribers;
    if (unknown <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.help_outline, size: 14, color: widget.theme.subtitleColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Unknown plan: $unknown active subscriber'
              '${unknown == 1 ? '' : 's'} missing a subscriptionProduct.',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// Clarifies that the filter only affects New Users — the trial /
  /// subscription figures are snapshots.
  Widget _buildSnapshotNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: widget.theme.subtitleColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Trial & subscription figures are snapshots "as of now" — only '
              'New Users responds to the date filter. Computed client-side '
              'from ${_records.length} user document'
              '${_records.length == 1 ? '' : 's'}.',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// A metric card. A `null` [value] with a [valueLabel] renders the label
  /// (e.g. a percentage); a `null` [value] with no label renders a dash.
  Widget _metricCard(
    IconData icon,
    String label,
    int? value, {
    String? valueLabel,
    Key? key,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.theme.textColor.withAlpha(15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: widget.theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: widget.theme.subtitleColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Text(
            valueLabel ?? (value == null ? '—' : _formatCount(value)),
            style: TextStyle(
              color: widget.theme.textColor,
              fontWeight: FontWeight.bold,
              fontSize: 26,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int value) {
    if (value >= 1000) {
      final k = value / 1000;
      return k == k.roundToDouble() ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
    }
    return value.toString();
  }
}
