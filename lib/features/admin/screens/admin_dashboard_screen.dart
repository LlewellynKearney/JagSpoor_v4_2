import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../subscription/services/play_billing_service.dart';
import '../../subscription/services/subscription_pricing.dart';
import '../services/admin_analytics_service.dart';
import '../services/admin_auth_guard.dart';
import '../services/media_storage_analytics.dart';
import '../services/subscription_config_service.dart';
import '../services/usage_analytics_service.dart';
import '../widgets/admin_mode_switcher.dart';
import '../widgets/media_storage_charts.dart';
import '../widgets/referral_rewards_admin_card.dart';
import 'create_user_screen.dart';
import 'bulk_csv_import_screen.dart';

/// Master Admin Analytics Dashboard.
///
/// Accessible only to users who pass [AdminAuthGuard]. Presents five reporting
/// sections:
///   - Entity Overview (counts of outfitters, hunters, packages, bookings,
///     trophies).
///   - Financial Analytics (daily/weekly/monthly/yearly gross booking revenue,
///     in ZAR).
///   - Subscription Revenue (admin-configured hunter/outfitter rates × the
///     current subscriber counts; manual input fields).
///   - Feature Usage (screen-view / feature-usage telemetry partitioned by
///     role — Hunter vs. Outfitter).
///   - User Engagement (registered users and active sessions).
///
/// Also provides entry points to manual account creation and bulk CSV import.
class AdminDashboardScreen extends StatefulWidget {
  final ThemeController theme;

  const AdminDashboardScreen({super.key, required this.theme});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminMetrics? _metrics;
  FinancialAnalytics? _financials;
  UsageAnalytics _usage = const UsageAnalytics(byRole: {});
  SubscriptionRevenue? _subscriptionRevenue;
  MediaStorageAnalytics? _mediaAnalytics;
  final TextEditingController _hunterSubController = TextEditingController();
  final TextEditingController _outfitterSubController = TextEditingController();
  bool _savingConfig = false;
  bool _loading = true;
  String? _error;
  final AdminAuthGuard _guard = AdminAuthGuard.instance;
  bool _authorized = false;

  /// Live Play-vs-admin price mismatch warnings (empty when aligned or when
  /// the Play catalog is unavailable).
  List<String> _priceDivergenceMessages = const [];

  @override
  void dispose() {
    _hunterSubController.dispose();
    _outfitterSubController.dispose();
    super.dispose();
  }

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
          _error = 'Access denied. This portal is restricted to platform admins.';
        });
        return;
      }
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
      // Compare the live Play Console prices against the admin-configured
      // prices and surface a mismatch banner (the store is the charge truth).
      unawaited(_checkPriceDivergence(config));
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load analytics: $e';
      });
    }
  }

  /// Fetches the live Play catalog prices and reconciles each against the
  /// admin-configured `admin_config/pricing` amount under the Option A
  /// (VAT-inclusive listed price) model.
  ///
  /// Google Play quotes the catalog amount EXCLUDING VAT while the Admin
  /// control plane stores the VAT-INCLUSIVE final charge, so the catalog figure
  /// is grossed up by 15% before comparing (via [PlayPriceReconciliation]).
  /// Example: Play R30.43 excl → R34.99 incl == Admin R34.99 → NO warning.
  /// The banner is shown ONLY when the reconciled amounts differ by more than
  /// the documented 2-cent tolerance.
  ///
  /// Best-effort: a billing-unavailable / catalog-miss / error leaves the
  /// banner hidden (nothing to compare).
  Future<void> _checkPriceDivergence(SubscriptionConfig config) async {
    try {
      if (!await PlayBillingService.instance.isBillingSupported()) return;
      final products = await PlayBillingService.instance.loadProducts();
      final messages = <String>[];
      for (final tier in SubscriptionTier.values) {
        final product = products[tier];
        if (product == null) continue; // catalog miss — nothing to compare
        final adminPrice = tier == SubscriptionTier.outfitter
            ? config.outfitterSubscriptionZAR
            : config.hunterSubscriptionZAR;
        if (adminPrice <= 0) continue;
        final reconciliation = PlayPriceReconciliation.compare(
          playExVat: product.rawPrice,
          adminInclVat: adminPrice,
          currencySymbol: product.currencySymbol,
        );
        // Reconciled figures agree (30.43 * 1.15 == 34.99 within tolerance):
        // do NOT warn.
        if (reconciliation.matches) continue;
        messages.add(reconciliation.mismatchMessage);
      }
      if (!mounted) return;
      setState(() => _priceDivergenceMessages = messages);
    } catch (e) {
      debugPrint('AdminDashboardScreen: price divergence check failed: $e');
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
      unawaited(_checkPriceDivergence(config));
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
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          appBar: AppBar(
            title: const Text('🛡️ Admin Portal'),
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
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                            16, 8, 16, SafeBottomInset.of(context)),
                        children: [
                          AdminModeSwitcher(
                            theme: widget.theme,
                            activeMode: AdminMode.admin,
                          ),
                          _buildSectionHeader('Entity Overview'),
                          _buildEntityGrid(),
                          const SizedBox(height: 24),
                          _buildSectionHeader('Financial Analytics (ZAR)'),
                          _buildFinancialSection(),
                          const SizedBox(height: 24),
                          _buildSectionHeader('Subscription Revenue (ZAR)'),
                          if (_priceDivergenceMessages.isNotEmpty)
                            _buildPriceDivergenceBanner(),
                          _buildSubscriptionConfigCard(),
                          _buildSubscriptionRevenueCard(),
                          const SizedBox(height: 24),
                          _buildSectionHeader('Referral Rewards (ZAR)'),
                          ReferralRewardsAdminCard(
                            theme: widget.theme,
                            isAdmin: _authorized,
                          ),
                          const SizedBox(height: 24),
                          _buildSectionHeader('Feature Usage by Role'),
                          _buildFeatureUsageSection(),
                          const SizedBox(height: 24),
                          _buildSectionHeader('Media & Storage'),
                          _buildMediaStorageSection(),
                          const SizedBox(height: 24),
                          _buildSectionHeader('User Engagement'),
                          _buildEngagementRow(),
                          const SizedBox(height: 24),
                          _buildSectionHeader('Account Management'),
                          _buildManagementCards(),
                        ],
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

  // ── Entity Overview ──────────────────────────────────────────────────────
  Widget _buildEntityGrid() {
    final m = _metrics!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _metricCard(Icons.business, 'Outfitters', m.totalOutfitters),
        _metricCard(Icons.person_outline, 'Active Hunters', m.activeHunters),
        _metricCard(Icons.inventory_2_outlined, 'Listed Packages', m.listedPackages),
        _metricCard(Icons.book_online_rounded, 'Active Bookings', m.activeBookings),
        _metricCard(Icons.emoji_events_outlined, 'Total Trophies', m.totalTrophies),
        _metricCard(Icons.groups_outlined, 'Registered Users', m.registeredUsers),
      ],
    );
  }

  Widget _metricCard(IconData icon, String label, int value) {
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
                  style: TextStyle(
                    color: widget.theme.subtitleColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Text(
            _formatCount(value),
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

  // ── Financial Analytics ─────────────────────────────────────────────────
  Widget _buildFinancialSection() {
    final f = _financials!;
    return Column(
      children: [
        _financialRow(f.daily),
        _financialRow(f.weekly),
        _financialRow(f.monthly),
        _financialRow(f.yearly),
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
              child: _financialValue('Gross', p.grossBookingRevenue, Colors.green),
            ),
            Expanded(
              child: _financialValue('Net', p.outfitterNet, widget.theme.subtitleColor),
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
        Text(label, style: TextStyle(color: widget.theme.subtitleColor, fontSize: 10)),
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

  // ── Subscription Revenue ────────────────────────────────────────────────
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

  /// Warning banner shown when the live Play Console price, grossed up to its
  /// VAT-inclusive amount, differs from the admin-configured
  /// `admin_config/pricing` amount by more than the documented reconciliation
  /// tolerance ([priceDivergenceToleranceZAR]). The Play Console is the charge
  /// truth; the operator must align the base plan.
  Widget _buildPriceDivergenceBanner() {
    return Container(
      key: const ValueKey('adminPriceDivergenceBanner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PRICE DIVERGENCE',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final message in _priceDivergenceMessages)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                message,
                style: TextStyle(color: widget.theme.textColor, fontSize: 12),
              ),
            ),
        ],
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
            _subscriptionRow('MRR', revenue.monthlyRecurringRevenue),
            _subscriptionRow(
                'Daily estimate', revenue.dailyEstimate),
            _subscriptionRow(
                'Weekly estimate', revenue.weeklyEstimate),
            _subscriptionRow('ARR', revenue.annualProjection),
            const SizedBox(height: 4),
            Text(
              '${revenue.hunterCount} hunters × '
              'R ${revenue.config.hunterSubscriptionZAR.toStringAsFixed(2)} + '
              '${revenue.outfitterCount} outfitters × '
              'R ${revenue.config.outfitterSubscriptionZAR.toStringAsFixed(2)}',
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
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Feature usage by role ───────────────────────────────────────────────
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
              style: TextStyle(
                  color: widget.theme.subtitleColor, fontSize: 11),
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

  // ── Media & Storage ─────────────────────────────────────────────────────
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
                child: _metricCard(
                    Icons.photo_library_outlined,
                    'Photos Uploaded',
                    analytics.totalPhotos)),
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

  // ── User Engagement ─────────────────────────────────────────────────────
  Widget _buildEngagementRow() {
    final m = _metrics!;
    return Row(
      children: [
        Expanded(child: _metricCard(Icons.how_to_reg, 'Registered Users', m.registeredUsers)),
        const SizedBox(width: 12),
        Expanded(child: _metricCard(Icons.sensors, 'Active Sessions', m.activeSessions)),
      ],
    );
  }

  // ── Account Management entry points ─────────────────────────────────────
  Widget _buildManagementCards() {
    return Column(
      children: [
        _managementCard(
          icon: Icons.person_add_alt_1,
          title: 'Create User',
          description: 'Manually provision a single hunter or outfitter account.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateUserScreen(theme: widget.theme),
            ),
          ),
        ),
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

  String _formatCount(int value) {
    if (value >= 1000) {
      final k = value / 1000;
      return k == k.roundToDouble() ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
    }
    return value.toString();
  }
}
