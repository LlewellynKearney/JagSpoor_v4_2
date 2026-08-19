import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jagspoor/core/widgets/contextual_info_icon.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/booking_status.dart';
import '../services/outfitter_analytics_service.dart';
import '../services/revenue_analytics_report_exporter.dart';

class OutfitterRevenueScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterRevenueScreen({super.key, required this.theme});

  @override
  State<OutfitterRevenueScreen> createState() => _OutfitterRevenueScreenState();
}

class _OutfitterRevenueScreenState extends State<OutfitterRevenueScreen> {
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _exportReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating revenue & analytics report…')),
    );
    try {
      await RevenueAnalyticsReportExporter().generateAndShare();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Revenue & analytics report exported and shared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          '📊 Enterprise Business Intelligence',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: widget.theme.backgroundColor,
        foregroundColor: widget.theme.textColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Export Revenue & Analytics Report',
            onPressed: _exportReport,
          ),
        ],
      ),
      body:
          _currentUserId == null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Please sign in to view analytics',
                      style: TextStyle(color: widget.theme.textColor),
                    ),
                  ],
                ),
              )
              : StreamBuilder<Map<String, dynamic>>(
                stream: _combinedAnalyticsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.green),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading analytics',
                            style: TextStyle(color: widget.theme.textColor),
                          ),
                        ],
                      ),
                    );
                  }

                  final data = snapshot.data ?? {};
                  final revenue = Map<String, double>.from(
                    data['revenue'] ?? {},
                  );
                  final enterprise = Map<String, int>.from(
                    data['enterprise'] ?? {},
                  );
                  final speciesRevenue = List<Map<String, dynamic>>.from(
                    data['speciesRevenue'] ?? [],
                  );
                  final farmRevenue = List<Map<String, dynamic>>.from(
                    data['farmRevenue'] ?? [],
                  );
                  final monthlyStats = List<Map<String, dynamic>>.from(
                    data['monthlyStats'] ?? [],
                  );

                  final grossEarnings = revenue['grossEarnings'] ?? 0.0;
                  final netEarnings = revenue['netEarnings'] ?? 0.0;
                  final totalBookings =
                      (revenue['totalBookings'] ?? 0.0).toInt();

                  final totalFarms = enterprise['totalFarms'] ?? 0;
                  final activeManagers = enterprise['activeManagers'] ?? 0;
                  final totalPackages = enterprise['totalPackages'] ?? 0;
                  final pendingBookings = enterprise['pendingBookings'] ?? 0;

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                        16, 16, 16, SafeBottomInset.of(context)),
                    children: [
                      // ═══════════════════════════════════════════
                      // TOP HEADER: Enterprise Overview Metrics
                      // ═══════════════════════════════════════════
                      _buildSectionHeader(
                        '🏢 Enterprise Overview',
                        Icons.business_rounded,
                        widget.theme,
                      ),
                      const SizedBox(height: 12),

                      // Top Metrics Row
                      Row(
                        children: [
                          Expanded(
                            child: _EnterpriseMetricCard(
                              title: 'Active Farms',
                              value: '$totalFarms',
                              icon: Icons.landscape_rounded,
                              color: Colors.brown,
                              theme: widget.theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _EnterpriseMetricCard(
                              title: 'Managers',
                              value: '$activeManagers',
                              icon: Icons.people_rounded,
                              color: Colors.purple,
                              theme: widget.theme,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _EnterpriseMetricCard(
                              title: 'Packages',
                              value: '$totalPackages',
                              icon: Icons.inventory_2_rounded,
                              color: Colors.orange,
                              theme: widget.theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _EnterpriseMetricCard(
                              title: 'Pending',
                              value: '$pendingBookings',
                              icon: Icons.pending_actions_rounded,
                              color: Colors.amber,
                              theme: widget.theme,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ═══════════════════════════════════════════
                      // CORE FINANCIAL CONTAINER GRID
                      // ═══════════════════════════════════════════
                      _buildSectionHeader(
                        '💰 Financial Performance',
                        Icons.account_balance_rounded,
                        widget.theme,
                      ),
                      const SizedBox(height: 12),

                      // Total Bookings Hero Banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF1B5E20).withValues(alpha: 0.9),
                              const Color(0xFF2E7D32).withValues(alpha: 0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total Approved Bookings',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '$totalBookings',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'FINANCIAL SUMMARY',
                              style: TextStyle(
                                color: widget.theme.accentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          ContextualInfoIcon(
                            title: 'Gross Revenue vs Net Earnings',
                            iconColor: widget.theme.accentColor,
                            description:
                                'The total collected from hunters across all earned bookings equals the outfitter\'s net earnings — there is no platform commission deducted. Only approved and completed bookings are counted.',
                            concepts: const [
                              ExplanationConcept(
                                label: 'Gross Revenue',
                                detail: 'Total paid by hunters across all earned bookings (the base booking cost).',
                              ),
                              ExplanationConcept(
                                label: 'Net Earnings',
                                detail: 'The amount the outfitter actually receives — equal to gross revenue (no platform fee is deducted).',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Financial Grid
                      Row(
                        children: [
                          Expanded(
                            child: _RevenueMetricCard(
                              title: 'Gross Revenue',
                              subtitle: 'ZAR',
                              value: grossEarnings,
                              icon: Icons.account_balance_wallet_rounded,
                              color: Colors.blue,
                              theme: widget.theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _RevenueMetricCard(
                              title: 'Net Earnings',
                              subtitle: 'ZAR',
                              value: netEarnings,
                              icon: Icons.payments_rounded,
                              color: Colors.green,
                              theme: widget.theme,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Net Earnings Highlight
                      _NetEarningsCard(value: netEarnings, theme: widget.theme),
                      const SizedBox(height: 24),

                      // ═══════════════════════════════════════════
                      // REVENUE STREAMS ANALYTICS
                      // ═══════════════════════════════════════════
                      _buildSectionHeader(
                        '📈 Revenue Streams Analytics',
                        Icons.pie_chart_rounded,
                        widget.theme,
                      ),
                      const SizedBox(height: 12),

                      // Species Revenue Breakdown
                      Container(
                        decoration: BoxDecoration(
                          color: widget.theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.pets_rounded,
                                    color: widget.theme.accentColor,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Species Revenue Breakdown',
                                    style: TextStyle(
                                      color: widget.theme.textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            if (speciesRevenue.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.pets_rounded,
                                        color: widget.theme.subtitleColor
                                            .withValues(alpha: 0.5),
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No species revenue data yet',
                                        style: TextStyle(
                                          color: widget.theme.subtitleColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ...speciesRevenue
                                  .take(5)
                                  .map(
                                    (item) => _SpeciesRevenueRow(
                                      species: item['species'] ?? 'Unknown',
                                      revenue:
                                          (item['revenue'] ?? 0).toDouble(),
                                      count: (item['count'] ?? 0).toInt(),
                                      theme: widget.theme,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Income per Farm Breakdown
                      Container(
                        decoration: BoxDecoration(
                          color: widget.theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.landscape_rounded,
                                    color: widget.theme.accentColor,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Income per Farm',
                                      style: TextStyle(
                                        color: widget.theme.textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  ContextualInfoIcon(
                                    title: 'Income per Farm',
                                    iconColor: widget.theme.accentColor,
                                    description:
                                        'Total ZAR revenue each farm has generated from earned bookings (payment-verified Confirmed + Completed bookings) associated with that farm.',
                                    concepts: const [
                                      ExplanationConcept(
                                        label: 'Per-farm revenue',
                                        detail:
                                            'Sum of booking totals (base price) for bookings whose farmId matches the farm. Farms with no earned bookings yet are listed at R 0.',
                                      ),
                                      ExplanationConcept(
                                        label: 'Unassigned / Other',
                                        detail:
                                            'Bookings without a farmId (or referencing a farm that no longer exists) roll up under Unassigned / Other.',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            if (farmRevenue.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.landscape_rounded,
                                        color: widget.theme.subtitleColor
                                            .withValues(alpha: 0.5),
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No farm revenue data yet',
                                        style: TextStyle(
                                          color: widget.theme.subtitleColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ...farmRevenue
                                  .take(8)
                                  .map(
                                    (item) => _FarmRevenueRow(
                                      farm: item['farm'] ?? 'Unknown Farm',
                                      revenue:
                                          (item['revenue'] ?? 0).toDouble(),
                                      bookings:
                                          (item['bookings'] ?? 0).toInt(),
                                      theme: widget.theme,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Monthly Booking Trends
                      Container(
                        decoration: BoxDecoration(
                          color: widget.theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    color: widget.theme.accentColor,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Monthly Booking Trends',
                                    style: TextStyle(
                                      color: widget.theme.textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            if (monthlyStats.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        color: widget.theme.subtitleColor
                                            .withValues(alpha: 0.5),
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No monthly data yet',
                                        style: TextStyle(
                                          color: widget.theme.subtitleColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ...monthlyStats
                                  .take(6)
                                  .map(
                                    (item) => _MonthlyTrendRow(
                                      month: item['month'] ?? 'N/A',
                                      bookings: (item['bookings'] ?? 0).toInt(),
                                      revenue:
                                          (item['revenue'] ?? 0).toDouble(),
                                      theme: widget.theme,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Summary Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: widget.theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Enterprise Summary',
                                  style: TextStyle(
                                    color: widget.theme.textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Net earnings of R ${netEarnings.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} represent total revenue from approved bookings paid by hunters (the full booking amount; no platform commission is deducted).',
                              style: TextStyle(
                                color: widget.theme.subtitleColor,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const CopyrightFooter(),
                    ],
                  );
                },
              ),
    );
  }

  Stream<Map<String, dynamic>> _combinedAnalyticsStream() async* {
    // Unauthenticated / un-resolved uid: yield a stable empty payload instead
    // of dereferencing `_currentUserId!` (which would throw a NullCheckException
    // into the StreamBuilder). The screen then renders the zero-state metrics
    // rather than an "Error loading analytics" banner.
    final uid = _currentUserId;
    if (uid == null) {
      yield const {
        'revenue': <String, double>{},
        'enterprise': <String, int>{},
        'speciesRevenue': <Map<String, dynamic>>[],
        'monthlyStats': <Map<String, dynamic>>[],
      };
      return;
    }

    final revenueStream =
        OutfitterAnalyticsService.instance.getRevenueSummaryStream(uid);

    await for (final revenue in revenueStream) {
      // Each auxiliary metric degrades independently to a zero / empty state
      // on failure (permissions, offline with no cache, missing index) so one
      // bad query never errors the whole dashboard stream.
      final farms = await _tryCount(_getFarmsData);
      final managers = await _tryCount(_getManagersData);
      final packages = await _tryCount(_getPackagesData);
      final pendingBookings = await _tryCount(_getPendingBookingsCount);
      final speciesData = await _tryList(_getSpeciesRevenueData);
      final farmRevenueData = await _tryList(_getFarmRevenueData);
      final monthlyData = await _tryList(_getMonthlyStatsData);

      yield {
        'revenue': revenue,
        'enterprise': {
          'totalFarms': farms,
          'activeManagers': managers,
          'totalPackages': packages,
          'pendingBookings': pendingBookings,
        },
        'speciesRevenue': speciesData,
        'farmRevenue': farmRevenueData,
        'monthlyStats': monthlyData,
      };
    }
  }

  /// Runs a count query, degrading to 0 on any failure (a failing metric
  /// must never take down the whole analytics stream).
  Future<int> _tryCount(Future<int> Function() query) async {
    try {
      return await query();
    } catch (_) {
      return 0;
    }
  }

  /// Runs a list query, degrading to an empty list on any failure.
  Future<List<Map<String, dynamic>>> _tryList(
      Future<List<Map<String, dynamic>>> Function() query) async {
    try {
      return await query();
    } catch (_) {
      return const [];
    }
  }

  Future<int> _getFarmsData() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('farms')
            .where('outfitterId', isEqualTo: _currentUserId)
            .get();
    return snapshot.docs.length;
  }

  Future<int> _getManagersData() async {
    // Farm managers are written to the `farm_managers` collection by
    // `OutfitterEnterpriseManager.assignManager` (stamped with the owning
    // outfitter's uid). The previous `managers` collection name matched no
    // documents, so the Managers card always showed 0.
    final snapshot =
        await FirebaseFirestore.instance
            .collection('farm_managers')
            .where('outfitterId', isEqualTo: _currentUserId)
            .get();
    return snapshot.docs.length;
  }

  Future<int> _getPackagesData() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('packages')
            .where('outfitterId', isEqualTo: _currentUserId)
            .where('status', isEqualTo: 'active')
            .get();
    return snapshot.docs.length;
  }

  Future<int> _getPendingBookingsCount() async {
    final uid = _currentUserId;
    if (uid == null) return 0;
    // Single-equality query (no composite-index dependency) + tolerant
    // client-side status match. A strict server-side
    // `status == 'Pending Approval'` silently misses pending bookings whose
    // status was written by an older app version with a case / spelling
    // variant ('pending', 'Pending', 'pending_approval'), so the Pending
    // card showed 0 even when un-reviewed requests existed.
    final snapshot =
        await FirebaseFirestore.instance
            .collection('bookings')
            .where('outfitterId', isEqualTo: uid)
            .get();
    return snapshot.docs
        .where((doc) =>
            BookingStatus.isPendingApproval(doc.data()['status'] as String?))
        .length;
  }

  Future<List<Map<String, dynamic>>> _getSpeciesRevenueData() async {
    final uid = _currentUserId;
    if (uid == null) return const [];
    return OutfitterAnalyticsService.instance.getSpeciesRevenueBreakdown(uid);
  }

  /// Aggregates the per-farm income (total ZAR revenue from earned
  /// bookings associated with each farmId) for the "Income per Farm"
  /// breakdown card. Reuses the same pure
  /// [RevenueAnalyticsReportExporter.aggregateFarmRevenue] aggregation the
  /// PDF export uses, so the on-screen card and the exported report always
  /// agree.
  Future<List<Map<String, dynamic>>> _getFarmRevenueData() async {
    final uid = _currentUserId;
    if (uid == null) return const [];

    final farmSnap = await FirebaseFirestore.instance
        .collection('farms')
        .where('outfitterId', isEqualTo: uid)
        .get();
    final farmNames = <String, String>{
      for (final f in farmSnap.docs)
        f.id: (f.data()['name'] ?? 'Unknown Farm') as String,
    };

    final earnedSnap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('outfitterId', isEqualTo: uid)
        .where('status',
            whereIn: OutfitterAnalyticsService.earnedBookingStatuses)
        .get();

    return RevenueAnalyticsReportExporter.aggregateFarmRevenue(
      earnedSnap.docs.map((d) => d.data()),
      farmNames,
    );
  }

  Future<List<Map<String, dynamic>>> _getMonthlyStatsData() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('bookings')
            .where('outfitterId', isEqualTo: _currentUserId)
            // Earned bookings only (excludes Pending Approval / Declined /
            // Cancelled). Mirrors the analytics-service earned-status set so
            // the monthly chart and the summary card agree.
            .where('status', whereIn: OutfitterAnalyticsService.earnedBookingStatuses)
            .get();

    final Map<String, Map<String, dynamic>> monthlyData = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final timestamp = data['bookingTimestamp'] as Timestamp?;
      if (timestamp != null) {
        final date = timestamp.toDate();
        final monthKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}';
        final monthName = _getMonthName(date.month);

        if (!monthlyData.containsKey(monthKey)) {
          monthlyData[monthKey] = {
            'month': monthName,
            'bookings': 0,
            'revenue': 0.0,
          };
        }
        monthlyData[monthKey]!['bookings'] =
            (monthlyData[monthKey]!['bookings'] as int) + 1;
        // Outfitter revenue = the booking total, which equals the base price
        // (there is no platform commission). The base price is preferred so
        // legacy marked-up totals do not overstate revenue.
        final basePrice =
            (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
        monthlyData[monthKey]!['revenue'] =
            (monthlyData[monthKey]!['revenue'] as double) + basePrice;
      }
    }

    final sortedKeys = monthlyData.keys.toList()..sort();
    return sortedKeys.map((k) => monthlyData[k]!).toList();
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    ThemeController theme,
  ) {
    return Row(
      children: [
        Icon(icon, color: theme.accentColor, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _RevenueMetricCard extends StatelessWidget {
  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final ThemeController theme;
  final String? subtitle;

  const _RevenueMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.theme,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: theme.subtitleColor, fontSize: 12),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                color: theme.subtitleColor.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'R ${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetEarningsCard extends StatelessWidget {
  final double value;
  final ThemeController theme;

  const _NetEarningsCard({required this.value, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D47A1).withValues(alpha: 0.9),
            const Color(0xFF1565C0).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_rounded,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Net Disbursed Earnings',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'R ${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Amount to be disbursed to your account',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnterpriseMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final ThemeController theme;

  const _EnterpriseMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(color: theme.subtitleColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeciesRevenueRow extends StatelessWidget {
  final String species;
  final double revenue;
  final int count;
  final ThemeController theme;

  const _SpeciesRevenueRow({
    required this.species,
    required this.revenue,
    required this.count,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.pets_rounded,
              color: Colors.green,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  species,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$count booking${count != 1 ? 's' : ''}',
                  style: TextStyle(color: theme.subtitleColor, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            'R ${revenue.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmRevenueRow extends StatelessWidget {
  final String farm;
  final double revenue;
  final int bookings;
  final ThemeController theme;

  const _FarmRevenueRow({
    required this.farm,
    required this.revenue,
    required this.bookings,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.brown.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.landscape_rounded,
              color: Colors.brown,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  farm,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$bookings earned booking${bookings != 1 ? 's' : ''}',
                  style: TextStyle(color: theme.subtitleColor, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            'R ${revenue.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyTrendRow extends StatelessWidget {
  final String month;
  final int bookings;
  final double revenue;
  final ThemeController theme;

  const _MonthlyTrendRow({
    required this.month,
    required this.bookings,
    required this.revenue,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: Colors.blue,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  month,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$bookings booking${bookings != 1 ? 's' : ''}',
                  style: TextStyle(color: theme.subtitleColor, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            'R ${revenue.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
