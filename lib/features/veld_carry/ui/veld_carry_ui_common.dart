import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
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

/// Human label for a planted feed type constant.
String plantedFeedTypeLabel(String feedType) {
  switch (feedType) {
    case PlantedArea.feedTypeLucerneIrrigated:
      return 'Lucerne (irrigated)';
    case PlantedArea.feedTypeLucerneDryland:
      return 'Lucerne (dryland)';
    case PlantedArea.feedTypeTeff:
      return 'Teff';
    case PlantedArea.feedTypeOats:
      return 'Oats';
    case PlantedArea.feedTypeOatsVetch:
      return 'Oats + vetch';
    case PlantedArea.feedTypeRyegrassPerennial:
      return 'Ryegrass (perennial)';
    case PlantedArea.feedTypeRyegrassAnnual:
      return 'Ryegrass (annual)';
    case PlantedArea.feedTypeKikuyuIrrigated:
      return 'Kikuyu (irrigated)';
    case PlantedArea.feedTypeKikuyuDryland:
      return 'Kikuyu (dryland)';
    case PlantedArea.feedTypeEragrostis:
      return 'Eragrostis';
    case PlantedArea.feedTypeSmutsFinger:
      return 'Smuts finger grass';
    case PlantedArea.feedTypeMaizeStover:
      return 'Maize stover';
    case PlantedArea.feedTypeSorghum:
      return 'Sorghum';
    case PlantedArea.feedTypeOtherCustom:
    default:
      return 'Other (custom)';
  }
}

/// Human label for a planted area: the custom name when the feed type is
/// `OTHER_CUSTOM`, otherwise the feed-type label.
String plantedFeedLabel(PlantedArea area) {
  if (area.feedType == PlantedArea.feedTypeOtherCustom) {
    final custom = (area.customName ?? '').trim();
    return custom.isEmpty ? 'Other (custom)' : custom;
  }
  return plantedFeedTypeLabel(area.feedType);
}

/// Human label for a planted season constant.
String plantedSeasonLabel(String season) {
  switch (PlantedArea.normalizeSeason(season)) {
    case PlantedArea.seasonSummer:
      return 'Summer';
    case PlantedArea.seasonWinter:
      return 'Winter';
    default:
      return 'All year';
  }
}

/// Human label for a [FarmPermit.permitTypes] constant.
String permitTypeLabel(String permitType) {
  switch (FarmPermit.normalizePermitType(permitType)) {
    case FarmPermit.permitTypeCae:
      return 'CAE (adequate enclosure)';
    case FarmPermit.permitTypeExemption:
      return 'Exemption';
    case FarmPermit.permitTypeTops:
      return 'TOPS';
    case FarmPermit.permitTypeCites:
      return 'CITES';
    case FarmPermit.permitTypePhLicence:
      return 'PH licence';
    case FarmPermit.permitTypeOutfitterReg:
      return 'Outfitter registration';
    case FarmPermit.permitTypePredatorCaptivity:
      return 'Predator captivity';
    case FarmPermit.permitTypePredatorFencing:
      return 'Predator fencing';
    case FarmPermit.permitTypeDangerousGameFencing:
      return 'Dangerous game fencing';
    case FarmPermit.permitTypeVet:
      return 'Veterinary';
    case FarmPermit.permitTypeTransport:
      return 'Transport';
    case FarmPermit.permitTypeGameMovement:
      return 'Game movement';
    case FarmPermit.permitTypeOther:
    default:
      return 'Other';
  }
}

/// Human label for a permit status constant.
String permitStatusLabel(String status) {
  switch ((status).trim().toLowerCase()) {
    case FarmPermit.permitStatusExpiringSoon:
      return 'Expiring soon';
    case FarmPermit.permitStatusExpired:
      return 'Expired';
    case FarmPermit.permitStatusNoExpiry:
      return 'No expiry';
    case FarmPermit.permitStatusValid:
    default:
      return 'Valid';
  }
}

/// Badge colour for a permit status constant.
Color permitStatusColor(String status) {
  switch ((status).trim().toLowerCase()) {
    case FarmPermit.permitStatusExpiringSoon:
      return const Color(0xFFB26A00);
    case FarmPermit.permitStatusExpired:
      return const Color(0xFFB71C1C);
    case FarmPermit.permitStatusNoExpiry:
      return const Color(0xFF1565C0);
    case FarmPermit.permitStatusValid:
    default:
      return const Color(0xFF1B5E20);
  }
}

/// Human label for a permit visibility constant.
String permitVisibilityLabel(String visibility) =>
    FarmPermit.normalizeVisibility(visibility) ==
            FarmPermit.visibilityHunterVisible
        ? 'Hunter visible'
        : 'Private';

/// `2026-11-23`, or `—` when the date is unknown.
String formatPermitDate(DateTime? date) {
  if (date == null) return '—';
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
