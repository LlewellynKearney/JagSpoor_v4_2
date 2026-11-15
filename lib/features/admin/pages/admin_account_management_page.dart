import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/admin_analytics_service.dart';
import '../services/admin_kpi_service.dart';
import '../services/media_storage_analytics.dart';
import '../services/subscription_config_service.dart';
import '../services/usage_analytics_service.dart';
import '../widgets/media_storage_charts.dart';
import '../widgets/referral_rewards_admin_card.dart';
import '../screens/bulk_csv_import_screen.dart';
import '../screens/create_user_screen.dart';

/// The Admin Portal V2 **Account Management** tab.
///
/// Absorbs the ORIGINAL Admin Portal's unique operator actions and control
/// planes now that the old portal is retired and `/admin` / `/admin_dashboard`
/// redirect to V2:
///   - **Create User** + **Bulk CSV Import** (the two unique account-provisioning
///     actions) — each opens its standalone screen.
///   - Entity Overview (registered users / outfitters / hunters / packages /
///     bookings / trophies).
///   - Financial Analytics (daily / weekly / monthly / yearly gross + net).
///   - Subscription Revenue control plane (admin-configured hunter/outfitter
///     amounts) + the derived MRR / ARR.
///   - Referral Rewards configuration card.
///   - Feature Usage by role (Hunter vs. Outfitter).
///   - Media & Storage footprint.
///   - User Engagement metrics.
///
/// READ/WRITE scope is unchanged from the old portal: the only writes are the
/// admin-controlled config saves (subscription amounts, referral rewards), which
/// target `admin_config/*` (admin-write per `firestore.rules`). No billing /
/// payment code is touched.
class AdminAccountManagementPage extends StatefulWidget {
  final ThemeController theme;

  const AdminAccountManagementPage({super.key, required this.theme});

  @override
  State<AdminAccountManagementPage> createState() =>
      _AdminAccountManagementPageState();
}

class _AdminAccountManagementPageState
    extends State<AdminAccountManagementPage> {
  AdminMetrics? _metrics;
  FinancialAnalytics? _financials;
  UsageAnalytics _usage = const UsageAnalytics(byRole: {});
  SubscriptionRevenue? _subscriptionRevenue;
  MediaStorageAnalytics? _mediaAnalytics;

  /// Server-computed KPIs from `getAdminPortalKpis` (null when the callable was
  /// unreachable — the page then renders the locally computed figures).
  AdminPortalKpis? _kpis;
  String? _kpiError;

  final TextEditingController _hunterSubController = TextEditingController();
  final TextEditingController _outfitterSubController = TextEditingController();
  bool _savingConfig = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _hunterSubController.dispose();
    _outfitterSubController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap({bool forceRefreshKpis = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AdminAnalyticsService.instance.fetchEntityMetrics(),
        AdminAnalyticsService.instance.fetchFinancialAnalytics(),
        UsageAnalyticsService.instance.fetchUsageAnalytics(),
        SubscriptionConfigService.instance.loadConfigOrDefaults(),
        MediaStorageAnalyticsService.instance.fetch(),
      ]);
      final metrics = results[0] as AdminMetrics;
      final config = results[3] as SubscriptionConfig;
      _hunterSubController.text = _formatAmount(config.hunterSubscriptionZAR);
      _outfitterSubController.text =
          _formatAmount(config.outfitterSubscriptionZAR);
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _financials = results[1] as FinancialAnalytics;
        _usage = results[2] as UsageAnalytics;
        _mediaAnalytics = results[4] as MediaStorageAnalytics;
        _subscriptionRevenue = SubscriptionConfigService.computeRevenue(
          config,
          hunterCount: metrics.activeHunters,
          outfitterCount: metrics.totalOutfitters,
        );
        _loading = false;
      });
      // Server-side KPIs — the authoritative figures. Best-effort.
      unawaited(_loadKpis(forceRefresh: forceRefreshKpis));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load account management data: $e';
      });
    }
  }

  Future<void> _loadKpis({bool forceRefresh = false}) async {
    try {
      final result =
          await AdminKpiService.instance.fetchKpis(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _kpis = result.kpis;
        _kpiError = result.fromServer ? null : result.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _kpiError = '$e');
    }
  }

  String _formatAmount(double v) => v <= 0
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2));

  Future<void> _saveSubscriptionConfig() async {
    setState(() => _savingConfig = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final config = SubscriptionConfig(
        hunterSubscriptionZAR:
            double.tryParse(_hunterSubController.text.trim()) ?? 0.0,
        outfitterSubscriptionZAR:
            double.tryParse(_outfitterSubController.text.trim()) ?? 0.0,
      );
      await SubscriptionConfigService.instance.saveConfig(config);
      if (!mounted) return;
      final metrics = _metrics;
      setState(() {
        _savingConfig = false;
        if (metrics != null) {
          _subscriptionRevenue = SubscriptionConfigService.computeRevenue(
            config,
            hunterCount: metrics.activeHunters,
            outfitterCount: metrics.totalOutfitters,
          );
        }
      });
      messenger?.showSnackBar(const SnackBar(
          content: Text('Subscription amounts saved.'),
          backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingConfig = false);
      messenger?.showSnackBar(SnackBar(
          content: Text('Could not save subscription config: $e'),
          backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('adminV2AccountManagementTab'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The provisioning actions do not depend on any fetched data, so they
        // render in every state (loading / error / loaded) — the operator can
        // always create a user or run a CSV import.
        _sectionHeader('Account Provisioning'),
        _buildProvisioningCards(),
        const SizedBox(height: 24),
        _buildDataSections(),
      ],
    );
  }

  /// The data-driven sections — loading spinner / error / loaded content.
  Widget _buildDataSections() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline,
                size: 40, color: widget.theme.accentColor),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.theme.textColor),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _bootstrap(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Entity Overview'),
        _buildEntityGrid(),
        _buildKpiSourceNote(),
        const SizedBox(height: 24),
        _sectionHeader('Financial Analytics (ZAR)'),
        _buildFinancialSection(),
        const SizedBox(height: 24),
        _sectionHeader('Subscription Revenue (ZAR)'),
        _buildSubscriptionConfigCard(),
        _buildSubscriptionRevenueCard(),
        const SizedBox(height: 24),
        _sectionHeader('Referral Rewards (ZAR)'),
        ReferralRewardsAdminCard(theme: widget.theme, isAdmin: true),
        const SizedBox(height: 24),
        _sectionHeader('Feature Usage by Role'),
        _buildFeatureUsageSection(),
        const SizedBox(height: 24),
        _sectionHeader('Media & Storage'),
        _buildMediaStorageSection(),
        const SizedBox(height: 24),
        _sectionHeader('User Engagement'),
        _buildEngagementRow(),
      ],
    );
  }

  Widget _sectionHeader(String title) {
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

  // ── Account provisioning entry points ────────────────────────────────────
  Widget _buildProvisioningCards() {
    return Column(
      children: [
        _managementCard(
          icon: Icons.person_add_alt_1,
          title: 'Create User',
          description:
              'Manually provision a single hunter or outfitter account.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateUserScreen(theme: widget.theme),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _managementCard(
          icon: Icons.upload_file,
          title: 'Bulk CSV Import',
          description: 'Import multiple accounts from a CSV file.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BulkCsvImportScreen(theme: widget.theme),
            ),
          ),
        ),
      ],
    );
  }

  Widget _managementCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      color: widget.theme.cardColor,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: widget.theme.textColor.withAlpha(15)),
      ),
      child: InkWell(
        onTap: onTap,
        splashColor: widget.theme.accentColor.withAlpha(30),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.theme.accentColor.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: widget.theme.accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        )),
                    const SizedBox(height: 2),
                    Text(description,
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: widget.theme.subtitleColor),
            ],
          ),
        ),
      ),
    );
  }

  // ── Entity Overview ──────────────────────────────────────────────────────
  Widget _buildEntityGrid() {
    final m = _metrics!;
    final kpis = _kpis;
    final outfitters = kpis?.totalOutfitters ?? m.totalOutfitters;
    final hunters = kpis?.totalHunters ?? m.activeHunters;
    final listed = kpis?.listedPackages ?? m.listedPackages;
    final bookings = kpis?.activeBookings ?? m.activeBookings;
    final trophies = kpis?.totalTrophies ?? m.totalTrophies;
    final users = kpis?.registeredUsers ?? m.registeredUsers;
    final installs = kpis?.totalInstalls;
    final totalSubs = kpis?.totalSubscribers;
    final payfastSubs = kpis?.payfastSubscribers;
    final googleSubs = kpis?.googleSubscribers;
    final otherSubs = kpis?.unknownSubscribers;
    final packages = kpis?.totalPackages;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _metricCard(Icons.business, 'Outfitters', outfitters),
        _metricCard(Icons.person_outline, 'Hunters', hunters),
        _metricCard(Icons.groups_outlined, 'Registered Users', users),
        _metricCard(
            Icons.download_for_offline_outlined, 'Total Installs', installs),
        _metricCard(Icons.card_membership, 'Total Subscribers', totalSubs),
        _metricCard(Icons.account_balance_wallet_outlined,
            'PayFast Subscribers', payfastSubs),
        _metricCard(Icons.play_circle_outline, 'Google Subscribers', googleSubs),
        _metricCard(Icons.help_outline, 'Other Subscribers', otherSubs),
        _metricCard(Icons.inventory_2_outlined, 'Total Packages', packages),
        _metricCard(Icons.visibility_outlined, 'Listed Packages', listed),
        _metricCard(Icons.book_online_rounded, 'Active Bookings', bookings),
        _metricCard(Icons.emoji_events_outlined, 'Total Trophies', trophies),
      ],
    );
  }

  Widget _buildKpiSourceNote() {
    final kpis = _kpis;
    final fromServer = kpis != null;
    final color = fromServer ? Colors.green : Colors.orange;
    final label = fromServer
        ? (kpis.installsMeasured
            ? 'Live KPIs from the server (installs measured)'
            : 'Live KPIs from the server (installs = registered accounts)')
        : 'Local estimates — ${_kpiError ?? 'server KPIs unavailable'}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            fromServer ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: TextStyle(color: color, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(IconData icon, String label, int? value) {
    return Container(
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
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: widget.theme.subtitleColor, fontSize: 12),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? '—' : _formatCount(value),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Financial Analytics ──────────────────────────────────────────────────
  Widget _buildFinancialSection() {
    final f = _financials!;
    final kpis = _kpis;
    final daily = kpis?.dailyRevenue ?? f.daily.grossBookingRevenue;
    final weekly = kpis?.weeklyRevenue ?? f.weekly.grossBookingRevenue;
    final monthly = kpis?.monthlyRevenue ?? f.monthly.grossBookingRevenue;
    final yearly = kpis?.yearlyRevenue ?? f.yearly.grossBookingRevenue;
    return Column(
      children: [
        _financialRow(
            FinancialPeriod(label: f.daily.label, grossBookingRevenue: daily)),
        _financialRow(FinancialPeriod(
            label: f.weekly.label, grossBookingRevenue: weekly)),
        _financialRow(FinancialPeriod(
            label: f.monthly.label, grossBookingRevenue: monthly)),
        _financialRow(FinancialPeriod(
            label: f.yearly.label, grossBookingRevenue: yearly)),
      ],
    );
  }

  Widget _financialRow(FinancialPeriod p) {
    return Card(
      color: widget.theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.theme.textColor.withAlpha(15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                p.label,
                style: TextStyle(
                  color: widget.theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: _financialValue(
                  'Gross', p.grossBookingRevenue, Colors.green),
            ),
            Expanded(
              child: _financialValue(
                  'Net', p.outfitterNet, widget.theme.subtitleColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _financialValue(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: widget.theme.subtitleColor, fontSize: 10)),
        Text(
          'R ${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // ── Subscription Revenue ─────────────────────────────────────────────────
  Widget _subscriptionInput({
    required String label,
    required TextEditingController controller,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: widget.theme.textColor, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: widget.theme.subtitleColor, fontSize: 12),
        prefixText: 'R ',
        prefixStyle:
            TextStyle(color: widget.theme.subtitleColor, fontSize: 12),
        filled: true,
        fillColor: widget.theme.cardColor,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildSubscriptionConfigCard() {
    return Card(
      color: widget.theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.theme.textColor.withAlpha(15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subscription amounts (per user / month)',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            _subscriptionInput(
                label: 'Hunter subscription (ZAR)',
                controller: _hunterSubController),
            const SizedBox(height: 10),
            _subscriptionInput(
                label: 'Outfitter subscription (ZAR)',
                controller: _outfitterSubController),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _savingConfig ? null : _saveSubscriptionConfig,
                icon: _savingConfig
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_savingConfig ? 'SAVING…' : 'SAVE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionRevenueCard() {
    final revenue = _subscriptionRevenue;
    if (revenue == null) return const SizedBox.shrink();
    final kpis = _kpis;
    final mrr = kpis?.mrr ?? revenue.monthlyRecurringRevenue;
    final arr = kpis?.arr ?? revenue.annualProjection;
    final daily = kpis == null ? revenue.dailyEstimate : kpis.mrr / 30.0;
    final weekly =
        kpis == null ? revenue.weeklyEstimate : kpis.mrr / 30.0 * 7.0;
    final hunterCount = kpis?.hunterSubscribers ?? revenue.hunterCount;
    final outfitterCount = kpis?.outfitterSubscribers ?? revenue.outfitterCount;
    final hunterPrice =
        kpis?.hunterPrice ?? revenue.config.hunterSubscriptionZAR;
    final outfitterPrice =
        kpis?.outfitterPrice ?? revenue.config.outfitterSubscriptionZAR;
    return Card(
      color: widget.theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.theme.textColor.withAlpha(15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _subscriptionRow('MRR', mrr),
            _subscriptionRow('Daily estimate', daily),
            _subscriptionRow('Weekly estimate', weekly),
            _subscriptionRow('ARR', arr),
            const SizedBox(height: 4),
            Text(
              '$hunterCount hunters × '
              'R ${hunterPrice.toStringAsFixed(2)} + '
              '$outfitterCount outfitters × '
              'R ${outfitterPrice.toStringAsFixed(2)}',
              style: TextStyle(
                color: widget.theme.subtitleColor,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subscriptionRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      color: widget.theme.subtitleColor, fontSize: 10))),
          Text(
            'R ${value.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Feature usage by role ────────────────────────────────────────────────
  Widget _buildFeatureUsageSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child: _usageCard(
                icon: Icons.person_outline,
                title: 'Hunters',
                summary: _usage.hunters)),
        const SizedBox(width: 12),
        Expanded(
            child: _usageCard(
                icon: Icons.business_outlined,
                title: 'Outfitters',
                summary: _usage.outfitters)),
      ],
    );
  }

  Widget _usageCard({
    required IconData icon,
    required String title,
    required RoleUsageSummary summary,
  }) {
    final entries = summary.breakdown(limit: 5);
    return Container(
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.theme.textColor.withAlpha(15)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: widget.theme.accentColor, size: 18),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      color: widget.theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              const Spacer(),
              Text(
                summary.total.toString(),
                style: TextStyle(
                  color: widget.theme.accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (entries.isEmpty)
            Text(
              'No usage recorded yet.',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 11),
            )
          else ...[
            ...entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: entry.name == UsageBreakdownEntry.otherName
                                  ? widget.theme.subtitleColor.withAlpha(160)
                                  : widget.theme.subtitleColor,
                              fontStyle:
                                  entry.name == UsageBreakdownEntry.otherName
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                              fontSize: 11),
                        ),
                      ),
                      Text(
                        '${entry.count} · ${entry.percent.toStringAsFixed(1)}%',
                        style: TextStyle(
                            color: widget.theme.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            Divider(height: 1, color: widget.theme.textColor.withAlpha(15)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                  ),
                ),
                Text(
                  '${summary.total} · 100.0%',
                  style: TextStyle(
                      color: widget.theme.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Media & Storage ──────────────────────────────────────────────────────
  Widget _buildMediaStorageSection() {
    final analytics = _mediaAnalytics;
    if (analytics == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _metricCard(Icons.photo_library_outlined,
                    'Photos Uploaded', analytics.totalPhotos)),
            const SizedBox(width: 12),
            Expanded(
                child: _metricCard(Icons.cloud_outlined, 'Est. Storage (MB)',
                    analytics.estimatedFootprintMb.round())),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: widget.theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.theme.textColor.withAlpha(15)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photo Upload Volume (last ${analytics.dailyTrend.length} days)',
                style: TextStyle(
                    color: widget.theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              const SizedBox(height: 10),
              PhotoUploadTrendBarChart(
                theme: widget.theme,
                points: analytics.dailyTrend,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: widget.theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.theme.textColor.withAlpha(15)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Storage Footprint by Collection (est.)',
                style: TextStyle(
                    color: widget.theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              const SizedBox(height: 10),
              StorageFootprintPieChart(
                theme: widget.theme,
                byCollection: analytics.byCollection,
              ),
              const SizedBox(height: 6),
              Text(
                '${analytics.totalDocsWithPhotos} documents carry photos · '
                '~${MediaStorageAggregator.averagePhotoBytes ~/ 1024} KB per photo',
                style: TextStyle(
                    color: widget.theme.subtitleColor, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── User Engagement ──────────────────────────────────────────────────────
  Widget _buildEngagementRow() {
    final m = _metrics!;
    final kpis = _kpis;
    final registered = kpis?.registeredUsers ?? m.registeredUsers;
    final sessions = m.activeSessions;
    final completed = kpis?.completedBookings;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _metricCard(
                    Icons.how_to_reg, 'Registered Users', registered)),
            const SizedBox(width: 12),
            Expanded(
                child: _metricCard(Icons.sensors, 'Active Sessions', sessions)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _metricCard(Icons.task_alt, 'Completed Bookings',
                    completed ?? m.activeBookings)),
            const SizedBox(width: 12),
            Expanded(
                child: _metricCard(Icons.card_membership, 'Subscribers',
                    kpis?.totalSubscribers)),
          ],
        ),
      ],
    );
  }

  String _formatCount(int value) {
    if (value >= 1000) {
      final k = value / 1000;
      return k == k.roundToDouble()
          ? '${k.toInt()}k'
          : '${k.toStringAsFixed(1)}k';
    }
    return value.toString();
  }
}
