import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/admin_operational_metrics.dart';

/// The shared palette for the Admin Portal V2 charts (dark + light safe).
const List<Color> kAdminChartPalette = [
  Color(0xFFC68B59),
  Color(0xFF7CB342),
  Color(0xFF42A5F5),
  Color(0xFFEF5350),
  Color(0xFFAB47BC),
  Color(0xFFFFA726),
  Color(0xFF26A69A),
];

/// A bar chart of new users per day over the trailing [days] window (oldest →
/// newest). The [series] is `date → count`, built by `adminNewUsersByDay`.
class AdminNewUsersBarChart extends StatelessWidget {
  final ThemeController theme;
  final List<MapEntry<DateTime, int>> series;

  const AdminNewUsersBarChart({
    super.key,
    required this.theme,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = series.fold<int>(0, (a, e) => e.value > a ? e.value : a);
    final maxY = (maxCount + 1).toDouble();
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4).ceilToDouble().clamp(1, maxY),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.textColor.withAlpha(15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final entry = series[group.x];
                return BarTooltipItem(
                  '${entry.key.day}/${entry.key.month}: ${entry.value} users',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: (maxY / 4).ceilToDouble().clamp(1, maxY),
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: TextStyle(color: theme.subtitleColor, fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.length) {
                    return const SizedBox.shrink();
                  }
                  final day = series[index].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${day.day}/${day.month}',
                      style: TextStyle(color: theme.subtitleColor, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: series[i].value.toDouble(),
                    width: 14,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
                    color: series[i].value == 0
                        ? theme.textColor.withAlpha(15)
                        : theme.accentColor,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A donut chart of booking counts per status, with a legend.
class AdminBookingsByStatusDonut extends StatelessWidget {
  final ThemeController theme;

  /// The six canonical statuses → counts (from `AdminBookingMetrics.byStatus`).
  final Map<String, int> byStatus;

  const AdminBookingsByStatusDonut({
    super.key,
    required this.theme,
    required this.byStatus,
  });

  @override
  Widget build(BuildContext context) {
    final entries = byStatus.entries
        .where((e) => e.value > 0)
        .toList(growable: false);
    final total = entries.fold<int>(0, (a, e) => a + e.value);
    if (total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'No bookings yet.',
            style: TextStyle(color: theme.subtitleColor, fontSize: 12),
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 160,
          width: 160,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 28,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value.toDouble(),
                    color: kAdminChartPalette[i % kAdminChartPalette.length],
                    title: '${(entries[i].value / total * 100).round()}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    radius: 54,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: kAdminChartPalette[
                              i % kAdminChartPalette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entries[i].key,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.subtitleColor,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        entries[i].value.toString(),
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A bar chart of active packages per province (nine provinces + Unknown).
class AdminPackagesPerProvinceBarChart extends StatelessWidget {
  final ThemeController theme;
  final List<MapEntry<String, int>> byProvince;

  const AdminPackagesPerProvinceBarChart({
    super.key,
    required this.theme,
    required this.byProvince,
  });

  /// Short label for a province on the x-axis (initials).
  static String shortLabel(String province) {
    if (province == kUnknownProvince) return '??';
    final parts = province.split(RegExp(r'[\s-]+'));
    if (parts.length == 1) return province.substring(0, 2).toUpperCase();
    return parts.map((p) => p.isEmpty ? '' : p[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = byProvince.fold<int>(0, (a, e) => e.value > a ? e.value : a);
    final maxY = (maxCount + 1).toDouble();
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4).ceilToDouble().clamp(1, maxY),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.textColor.withAlpha(15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final entry = byProvince[group.x];
                return BarTooltipItem(
                  '${entry.key}: ${entry.value}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: (maxY / 4).ceilToDouble().clamp(1, maxY),
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: TextStyle(color: theme.subtitleColor, fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= byProvince.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      shortLabel(byProvince[index].key),
                      style: TextStyle(color: theme.subtitleColor, fontSize: 8),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < byProvince.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: byProvince[i].value.toDouble(),
                    width: 14,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
                    color: byProvince[i].value == 0
                        ? theme.textColor.withAlpha(15)
                        : theme.accentColor,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
