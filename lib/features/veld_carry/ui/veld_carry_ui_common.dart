import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';

/// Shared presentation helpers for the Veld & Carrying Capacity UI.
///
/// Labels and colours only — every number rendered by the feature is produced
/// by `veld_carry_calculator.dart`, never here.

/// Human label for a camp's veld condition.
String veldConditionLabel(String condition) {
  switch (Camp.normalizeVeldCondition(condition)) {
    case Camp.veldConditionFair:
      return 'Fair';
    case Camp.veldConditionPoor:
      return 'Poor';
    default:
      return 'Good';
  }
}

/// Badge colour for a camp's veld condition.
Color veldConditionColor(String condition) {
  switch (Camp.normalizeVeldCondition(condition)) {
    case Camp.veldConditionFair:
      return const Color(0xFFB26A00);
    case Camp.veldConditionPoor:
      return const Color(0xFFB71C1C);
    default:
      return const Color(0xFF1B5E20);
  }
}

/// Human label for a stocking band returned by `stockingStatus()`.
String stockingStatusLabel(String status) {
  switch (status) {
    case stockingOptimal:
      return 'Optimal';
    case stockingOverstocked:
      return 'Overstocked';
    case stockingSeverelyOverstocked:
      return 'Severely overstocked';
    case stockingUnderstocked:
    default:
      return 'Understocked';
  }
}

/// Badge colour for a stocking band.
Color stockingStatusColor(String status) {
  switch (status) {
    case stockingOptimal:
      return const Color(0xFF1B5E20);
    case stockingOverstocked:
      return const Color(0xFFB26A00);
    case stockingSeverelyOverstocked:
      return const Color(0xFFB71C1C);
    case stockingUnderstocked:
    default:
      return const Color(0xFF1565C0);
  }
}

/// `1200` -> `1200 ha`, `1200.5` -> `1200.5 ha`.
String formatHectares(double hectares) {
  if (!hectares.isFinite) return '—';
  final rounded = hectares.roundToDouble();
  final text = (rounded - hectares).abs() < 0.05
      ? rounded.toInt().toString()
      : hectares.toStringAsFixed(1);
  return '$text ha';
}

/// `42.34` -> `42.3 LSU`.
String formatLsu(double lsu) {
  if (!lsu.isFinite) return '—';
  return '${lsu.toStringAsFixed(1)} LSU';
}

/// `25.04` -> `25.0%`.
String formatUsagePct(double pct) {
  if (!pct.isFinite) return '—';
  return '${pct.toStringAsFixed(1)}%';
}

/// Small rounded status pill used by the camp cards.
class VeldCarryBadge extends StatelessWidget {
  const VeldCarryBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.darkMode = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    final background = darkMode
        ? color.withValues(alpha: 0.28)
        : color.withValues(alpha: 0.14);
    final foreground = darkMode ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: darkMode ? 0.6 : 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section label used above grouped content on the veld screens.
class VeldCarrySectionLabel extends StatelessWidget {
  const VeldCarrySectionLabel({
    super.key,
    required this.label,
    required this.theme,
  });

  final String label;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: theme.isDarkMode ? Colors.white70 : const Color(0xFF4A3B32),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
