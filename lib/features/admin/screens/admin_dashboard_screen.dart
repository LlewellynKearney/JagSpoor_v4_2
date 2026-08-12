import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/admin_analytics_service.dart';
import '../services/admin_auth_guard.dart';
import '../widgets/admin_mode_switcher.dart';
import 'create_user_screen.dart';
import 'bulk_csv_import_screen.dart';

/// Master Admin Analytics Dashboard.
///
/// Accessible only to users who pass [AdminAuthGuard]. Presents three reporting
/// sections:
///   - Entity Overview (counts of outfitters, hunters, packages, bookings,
///     trophies).
///   - Financial Analytics (daily/weekly/monthly/yearly gross booking revenue
///     vs. platform commission, in ZAR).
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
  bool _loading = true;
  String? _error;
  final AdminAuthGuard _guard = AdminAuthGuard.instance;
  bool _authorized = false;

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
      ]);
      setState(() {
        _metrics = results[0] as AdminMetrics;
        _financials = results[1] as FinancialAnalytics;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load analytics: $e';
      });
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
                  if (!mounted) return;
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
              child: _financialValue(
                  'Commission', p.platformCommission, widget.theme.accentColor),
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
