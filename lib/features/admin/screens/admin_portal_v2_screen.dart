import 'package:flutter/material.dart';

import '../../../core/layout/web_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../hunter_mode/models/booking_status.dart';
import '../models/admin_operational_metrics.dart';
import '../models/admin_revenue_metrics.dart';
import '../models/admin_user_metrics.dart';
import '../services/admin_analytics_service.dart';
import '../services/admin_auth_guard.dart';
import '../services/admin_operational_metrics_service.dart';
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

  /// Task 4: the package / booking snapshot, fetched ONCE alongside the users.
  AdminOperationalData _operational = const AdminOperationalData();
  AdminPackageMetrics _packageMetrics = const AdminPackageMetrics();
  AdminBookingMetrics _bookingMetrics = const AdminBookingMetrics();

  /// Task 5: the subscription-revenue snapshot, aggregated from the SAME user
  /// records (no extra Firestore read). A point-in-time snapshot that ignores
  /// the date filter.
  AdminRevenueMetrics _revenueMetrics = const AdminRevenueMetrics();

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
      // Task 4: the operational snapshot (packages / bookings / farms /
      // outfitters). The user emails parsed above are reused so `users` is
      // never read a second time.
      final userEmailByUid = <String, String>{
        for (final r in records)
          if (r.email.isNotEmpty) r.uid: r.email,
      };
      final operational = await AdminOperationalMetricsService.instance
          .fetchData(userEmailByUid: userEmailByUid);
      if (!mounted) return;
      setState(() {
        _records = records;
        _recordsLoaded = true;
        _metrics = AdminUserMetrics.aggregate(records, filter: _filter);
        _operational = operational;
        _packageMetrics = operational.packageMetrics();
        _bookingMetrics = operational.bookingMetrics();
        _revenueMetrics = AdminRevenueMetrics.aggregate(records);
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
                            const SizedBox(height: 24),
                            _buildSectionHeader('Packages'),
                            _buildPackageGrid(),
                            _buildProvinceBreakdown(),
                            _buildZeroBookingTable(),
                            const SizedBox(height: 24),
                            _buildSectionHeader('Bookings'),
                            _buildBookingGrid(),
                            _buildBookingStatusBreakdown(),
                            _buildStuckPendingTable(),
                            _buildTopOutfittersTable(),
                            _buildOperationalNote(),
                            const SizedBox(height: 24),
                            _buildSectionHeader('Revenue'),
                            _buildRevenueGrid(),
                            _buildPlanSplit(),
                            _buildProviderSplit(),
                            _buildPipelineCard(),
                            _buildChurnedTable(),
                            _buildRevenueNote(),
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

  // ==========================================================================
  // TASK 4 — PACKAGES
  // ==========================================================================

  /// The package-level KPI grid: Total / Active / Sold Out / Draft-Archived.
  Widget _buildPackageGrid() {
    final m = _packageMetrics;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _metricCard(
          Icons.inventory_2_outlined,
          'Total Packages',
          m.totalPackages,
          key: const ValueKey('adminV2CardTotalPackages'),
        ),
        _metricCard(
          Icons.check_circle_outline,
          'Active',
          m.activePackages,
          key: const ValueKey('adminV2CardActivePackages'),
        ),
        _metricCard(
          Icons.remove_shopping_cart_outlined,
          'Sold Out',
          m.soldOutPackages,
          key: const ValueKey('adminV2CardSoldOutPackages'),
        ),
        _metricCard(
          Icons.inventory_outlined,
          'Draft / Archived',
          m.draftArchivedPackages,
          key: const ValueKey('adminV2CardDraftArchivedPackages'),
        ),
        _metricCard(
          Icons.storefront_outlined,
          'Outfitters With 0 Packages',
          m.outfittersWithZeroPackages,
          key: const ValueKey('adminV2CardOutfittersZeroPackages'),
        ),
      ],
    );
  }

  /// Active packages per province (the nine SA provinces + Unknown). Rendered
  /// as a compact key/value list so every bucket is visible and reconciles.
  Widget _buildProvinceBreakdown() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('adminV2ProvinceBreakdown'),
        decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.theme.textColor.withAlpha(15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Packages Per Province',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in _packageMetrics.provinceBreakdown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      entry.value.toString(),
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Active packages with zero bookings (title + outfitter email + days live).
  Widget _buildZeroBookingTable() {
    final rows = _packageMetrics.zeroBookingPackages;
    return _tableCard(
      key: const ValueKey('adminV2ZeroBookingTable'),
      title: 'Packages With 0 Bookings',
      emptyLabel: 'Every active package has at least one booking.',
      headers: const ['Title', 'Outfitter', 'Days Live'],
      rows: [
        for (final r in rows)
          [
            r.title,
            r.outfitterEmail.isEmpty ? '—' : r.outfitterEmail,
            r.daysLive.toString(),
          ],
      ],
    );
  }

  // ==========================================================================
  // TASK 4 — BOOKINGS
  // ==========================================================================

  /// The booking-level KPI grid: Total / Conversion / Stuck Pending / Avg Days.
  Widget _buildBookingGrid() {
    final m = _bookingMetrics;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _metricCard(
          Icons.event_note_outlined,
          'Total Booking Requests',
          m.totalBookings,
          key: const ValueKey('adminV2CardTotalBookings'),
        ),
        _metricCard(
          Icons.percent_rounded,
          'Requests → Confirmed',
          null,
          valueLabel: m.conversionLabel,
          key: const ValueKey('adminV2CardBookingConversion'),
        ),
        _metricCard(
          Icons.hourglass_disabled_outlined,
          'Stuck Pending >7d',
          m.stuckPending.length,
          key: const ValueKey('adminV2CardStuckPending'),
        ),
        _metricCard(
          Icons.timelapse_rounded,
          'Avg Days To Confirm',
          null,
          valueLabel: m.avgDaysLabel,
          key: const ValueKey('adminV2CardAvgDaysToConfirm'),
        ),
      ],
    );
  }

  /// The six booking-status counts.
  Widget _buildBookingStatusBreakdown() {
    final byStatus = _bookingMetrics.byStatus;
    const statuses = [
      BookingStatus.pendingApproval,
      BookingStatus.approvedAwaitingPayment,
      BookingStatus.confirmed,
      BookingStatus.completed,
      BookingStatus.declined,
      BookingStatus.cancelled,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('adminV2BookingStatusBreakdown'),
        decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.theme.textColor.withAlpha(15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bookings By Status',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            for (final s in statuses)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s,
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      (byStatus[s] ?? 0).toString(),
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bookings stuck in Pending Approval > 7 days.
  Widget _buildStuckPendingTable() {
    final rows = _bookingMetrics.stuckPending;
    return _tableCard(
      key: const ValueKey('adminV2StuckPendingTable'),
      title: 'Stuck Pending > 7 Days',
      emptyLabel: 'No booking has been pending for more than 7 days.',
      headers: const ['Booking', 'Hunter', 'Outfitter', 'Package', 'Days'],
      rows: [
        for (final r in rows)
          [
            r.id,
            r.hunterEmail.isEmpty ? '—' : r.hunterEmail,
            r.outfitterEmail.isEmpty ? '—' : r.outfitterEmail,
            r.packageTitle.isEmpty ? '—' : r.packageTitle,
            r.daysStuck.toString(),
          ],
      ],
    );
  }

  /// The top five outfitters by booking count.
  Widget _buildTopOutfittersTable() {
    final rows = _bookingMetrics.topOutfitters;
    return _tableCard(
      key: const ValueKey('adminV2TopOutfittersTable'),
      title: 'Top 5 Outfitters By Bookings',
      emptyLabel: 'No bookings yet.',
      headers: const ['Outfitter', 'Total', 'Confirmed', 'Conv.'],
      rows: [
        for (final r in rows)
          [
            r.name.isNotEmpty
                ? r.name
                : (r.email.isNotEmpty ? r.email : r.outfitterId),
            r.total.toString(),
            r.confirmed.toString(),
            r.conversionLabel,
          ],
      ],
    );
  }

  /// Clarifies that the package / booking figures are snapshots and that no
  /// booking AMOUNT is shown (JagSpoor does not take booking payment in-app).
  Widget _buildOperationalNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: widget.theme.subtitleColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Package & booking figures are snapshots "as of now" and ignore '
              'the date filter. Booking payment is handled off-platform '
              '(EFT / cash), so no booking amount is reported as revenue. '
              'Computed client-side from ${_operational.packages.length} '
              'package${_operational.packages.length == 1 ? '' : 's'} + '
              '${_operational.bookings.length} booking'
              '${_operational.bookings.length == 1 ? '' : 's'}.',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TASK 5 — REVENUE (subscription only)
  // ==========================================================================

  /// The revenue KPI grid: Total MRR / Hunter MRR / Outfitter MRR / ARR.
  Widget _buildRevenueGrid() {
    final m = _revenueMetrics;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _metricCard(
          Icons.payments_outlined,
          'Total MRR',
          null,
          valueLabel: m.totalMrrLabel,
          key: const ValueKey('adminV2CardTotalMrr'),
        ),
        _metricCard(
          Icons.calendar_month_outlined,
          'ARR',
          null,
          valueLabel: m.arrLabel,
          key: const ValueKey('adminV2CardArr'),
        ),
        _metricCard(
          Icons.person_outline,
          'Hunter MRR',
          null,
          valueLabel: m.hunterMrrLabel,
          key: const ValueKey('adminV2CardHunterMrr'),
        ),
        _metricCard(
          Icons.business_outlined,
          'Outfitter MRR',
          null,
          valueLabel: m.outfitterMrrLabel,
          key: const ValueKey('adminV2CardOutfitterMrr'),
        ),
      ],
    );
  }

  /// The MRR plan split: the four plan buckets with count + MRR contribution.
  Widget _buildPlanSplit() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('adminV2PlanSplit'),
        decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.theme.textColor.withAlpha(15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MRR By Plan',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            for (final row in _revenueMetrics.planSplit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row.label} × ${row.count}',
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      row.mrrLabel,
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            if (_revenueMetrics.unknownPlanActiveSubscribers > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Unknown plan (unpriced): '
                  '${_revenueMetrics.unknownPlanActiveSubscribers} active '
                  'subscriber'
                  '${_revenueMetrics.unknownPlanActiveSubscribers == 1 ? '' : 's'}',
                  style:
                      TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The PayFast vs Play (vs User Choice / Unknown) provider split.
  Widget _buildProviderSplit() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('adminV2ProviderSplit'),
        decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.theme.textColor.withAlpha(15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PayFast vs Play Split',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            for (final row in _revenueMetrics.providerSplit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      '${row.count}  ·  ${row.percentLabel}',
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The pipeline (trial value) card — clearly labelled as NOT realized
  /// revenue.
  Widget _buildPipelineCard() {
    final m = _revenueMetrics;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('adminV2PipelineCard'),
        decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.theme.accentColor.withAlpha(60)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded,
                    color: widget.theme.accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PIPELINE — If all trials convert',
                    style: TextStyle(
                      color: widget.theme.subtitleColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              m.pipelineLabel,
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '(Trial Active Hunters × ${formatAdminZar(kHunterMonthlyZar)}) + '
              '(Trial Active Outfitters × '
              '${formatAdminZar(kOutfitterMonthlyZar)})  ·  '
              '${m.trialActiveHunters} hunter'
              '${m.trialActiveHunters == 1 ? '' : 's'} + '
              '${m.trialActiveOutfitters} outfitter'
              '${m.trialActiveOutfitters == 1 ? '' : 's'}',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// The churned (cancelled) accounts list: email + plan + cancellation date.
  Widget _buildChurnedTable() {
    final rows = _revenueMetrics.churned;
    return _tableCard(
      key: const ValueKey('adminV2ChurnedTable'),
      title: 'Churned (Cancelled) — ${_revenueMetrics.churnedCount}',
      emptyLabel: 'No cancelled subscriptions.',
      headers: const ['Email', 'Plan', 'Cancelled'],
      rows: [
        for (final r in rows)
          [
            r.email.isEmpty ? '—' : r.email,
            r.planLabel,
            r.cancelledAtLabel,
          ],
      ],
    );
  }

  /// Clarifies that only SUBSCRIPTION revenue is reported and that no booking
  /// amount is counted (booking payment is off-platform).
  Widget _buildRevenueNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: widget.theme.subtitleColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Subscription revenue only (snapshot "as of now", ignores the '
              'date filter). Booking payment is handled off-platform '
              '(EFT / cash), so no booking amount is reported as revenue. '
              'Prices: hunter R34.99/mo · R349.99/yr (MRR R29.17) · outfitter '
              'R299.99/mo · R2999.99/yr (MRR R250.00).',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// A titled table card. Renders the [emptyLabel] when [rows] is empty so a
  /// zero state is explicit (never a blank card).
  Widget _tableCard({
    required Key key,
    required String title,
    required String emptyLabel,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: key,
        decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.theme.textColor.withAlpha(15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text(
                emptyLabel,
                style: TextStyle(
                  color: widget.theme.subtitleColor,
                  fontSize: 12,
                ),
              )
            else
              Table(
                columnWidths: {
                  for (var i = 0; i < headers.length; i++)
                    i: i == 0 ? const FlexColumnWidth(2) : const FlexColumnWidth(),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: widget.theme.textColor.withAlpha(12),
                  ),
                ),
                children: [
                  TableRow(
                    children: [
                      for (final h in headers)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            h,
                            style: TextStyle(
                              color: widget.theme.accentColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final row in rows)
                    TableRow(
                      children: [
                        for (final cell in row)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              cell,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.theme.textColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
          ],
        ),
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
