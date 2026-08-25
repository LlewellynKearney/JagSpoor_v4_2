import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/media_storage_analytics.dart';

/// Bar chart of daily photo upload volume across the platform's media
/// collections (oldest → newest).
class PhotoUploadTrendBarChart extends StatelessWidget {
  final ThemeController theme;
  final List<PhotoUploadPoint> points;

  const PhotoUploadTrendBarChart({
    super.key,
    required this.theme,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = points.fold<int>(0, (acc, p) => p.count > acc ? p.count : acc);
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
                final point = points[group.x];
                return BarTooltipItem(
                  '${point.day.day}/${point.day.month}: ${point.count} photos',
                  TextStyle(
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
                reservedSize: 28,
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
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  // Label the first, middle, and last day to avoid crowding.
                  if (index != 0 &&
                      index != points.length - 1 &&
                      index != points.length ~/ 2) {
                    return const SizedBox.shrink();
                  }
                  final day = points[index].day;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${day.day}/${day.month}',
                      style:
                          TextStyle(color: theme.subtitleColor, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].count.toDouble(),
                    width: points.length > 10 ? 8 : 14,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3)),
                    color: points[i].count == 0
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

/// Pie chart of the estimated Firebase Storage footprint share per media
/// collection, with a legend.
class StorageFootprintPieChart extends StatelessWidget {
  final ThemeController theme;
  final List<CollectionPhotoCount> byCollection;

  const StorageFootprintPieChart({
    super.key,
    required this.theme,
    required this.byCollection,
  });

  /// Fixed palette per registry order (dark + light theme safe).
  static const List<Color> _palette = [
    Color(0xFFC68B59),
    Color(0xFF7CB342),
    Color(0xFF42A5F5),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFFFFA726),
  ];

  @override
  Widget build(BuildContext context) {
    final total = byCollection.fold<int>(0, (acc, c) => acc + c.photoCount);
    final nonEmpty =
        byCollection.where((c) => c.photoCount > 0).toList(growable: false);
    if (total == 0 || nonEmpty.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'No photo uploads recorded yet.',
            style: TextStyle(color: theme.subtitleColor, fontSize: 12),
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 150,
          width: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 26,
              sections: [
                for (final c in nonEmpty)
                  PieChartSectionData(
                    value: c.photoCount.toDouble(),
                    color: _palette[
                        byCollection.indexOf(c) % _palette.length],
                    title: '${(c.photoCount / total * 100).round()}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    radius: 52,
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
              for (final c in nonEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _palette[
                              byCollection.indexOf(c) % _palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: theme.subtitleColor, fontSize: 11),
                        ),
                      ),
                      Text(
                        c.photoCount.toString(),
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
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
