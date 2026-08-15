import 'dart:ui';

import '../services/shot_group_analyzer_service.dart';

/// A persisted record of a single analyzed shot-group target session,
/// saved to the local SQLite `target_session_logs` table so a hunter can
/// review their historical precision diagnostics offline.
class TargetSessionLog {
  /// Stable unique id (UUID-ish) generated at save time.
  final String id;

  /// The Digital Firearm Safe doc id of the linked rifle (empty when none
  /// was selected).
  final String firearmId;

  /// Human-readable firearm label snapshot ("make model (calibre)") captured
  /// at save time so the log stays readable if the rifle is later edited /
  /// deleted.
  final String firearmLabel;

  /// Target distance value (numeric, in [distanceUnit]).
  final double distance;

  /// Distance unit the group was measured at.
  final DistanceUnit distanceUnit;

  /// Angular unit the analysis was expressed in.
  final AngularUnit angularUnit;

  /// Per-click turret value of the linked scope.
  final double clickValue;

  /// Number of shots in the group.
  final int shotCount;

  /// Extreme spread in millimetres (0 if the target was not calibrated).
  final double extremeSpreadMm;

  /// Extreme spread in inches.
  final double extremeSpreadInches;

  /// Extreme spread expressed in [angularUnit].
  final double extremeSpreadAngular;

  /// Mean radius in millimetres.
  final double meanRadiusMm;

  /// Mean radius expressed in [angularUnit].
  final double meanRadiusAngular;

  /// Center-of-impact horizontal offset from the aim point, in millimetres
  /// (right positive). 0 when no aim point was marked.
  final double offsetHorizontalMm;

  /// Center-of-impact vertical offset from the aim point, in millimetres
  /// (up positive). 0 when no aim point was marked.
  final double offsetVerticalMm;

  /// Suggested vertical turret correction (clicks, UP positive).
  final int suggestedUpClicks;

  /// Suggested horizontal turret correction (clicks, RIGHT positive).
  final int suggestedRightClicks;

  /// Precision category label (e.g. "Sub-MOA Precision").
  final String precisionCategory;

  /// Whether the scale reference was calibrated when the session was saved.
  final bool calibrated;

  /// Aim point in image pixel coordinates (null when none was marked).
  final Offset? aimPoint;

  /// ISO-8601 timestamp of when the session was saved.
  final String createdAt;

  const TargetSessionLog({
    required this.id,
    required this.firearmId,
    required this.firearmLabel,
    required this.distance,
    required this.distanceUnit,
    required this.angularUnit,
    required this.clickValue,
    required this.shotCount,
    required this.extremeSpreadMm,
    required this.extremeSpreadInches,
    required this.extremeSpreadAngular,
    required this.meanRadiusMm,
    required this.meanRadiusAngular,
    required this.offsetHorizontalMm,
    required this.offsetVerticalMm,
    required this.suggestedUpClicks,
    required this.suggestedRightClicks,
    required this.precisionCategory,
    required this.calibrated,
    required this.aimPoint,
    required this.createdAt,
  });

  /// Distance unit as a storage string.
  String get distanceUnitLabel =>
      distanceUnit == DistanceUnit.yards ? 'yards' : 'meters';

  /// Angular unit as a storage string.
  String get angularUnitLabel =>
      angularUnit == AngularUnit.moa ? 'MOA' : 'MIL';

  /// Serialize to the SQLite row map.
  Map<String, Object?> toMap() => {
        'id': id,
        'firearmId': firearmId,
        'firearmLabel': firearmLabel,
        'distance': distance,
        'distanceUnit': distanceUnitLabel,
        'angularUnit': angularUnitLabel,
        'clickValue': clickValue,
        'shotCount': shotCount,
        'extremeSpreadMm': extremeSpreadMm,
        'extremeSpreadInches': extremeSpreadInches,
        'extremeSpreadAngular': extremeSpreadAngular,
        'meanRadiusMm': meanRadiusMm,
        'meanRadiusAngular': meanRadiusAngular,
        'offsetHorizontalMm': offsetHorizontalMm,
        'offsetVerticalMm': offsetVerticalMm,
        'suggestedUpClicks': suggestedUpClicks,
        'suggestedRightClicks': suggestedRightClicks,
        'precisionCategory': precisionCategory,
        'calibrated': calibrated ? 1 : 0,
        'aimPointDx': aimPoint?.dx,
        'aimPointDy': aimPoint?.dy,
        'createdAt': createdAt,
      };

  /// Deserialize from a SQLite row map.
  factory TargetSessionLog.fromMap(Map<String, Object?> map) {
    Offset? aim;
    final dx = map['aimPointDx'];
    final dy = map['aimPointDy'];
    if (dx is num && dy is num) {
      aim = Offset(dx.toDouble(), dy.toDouble());
    }
    return TargetSessionLog(
      id: (map['id'] as String?) ?? '',
      firearmId: (map['firearmId'] as String?) ?? '',
      firearmLabel: (map['firearmLabel'] as String?) ?? '',
      distance: (map['distance'] as num?)?.toDouble() ?? 0.0,
      distanceUnit: (map['distanceUnit'] as String?) == 'meters'
          ? DistanceUnit.meters
          : DistanceUnit.yards,
      angularUnit: (map['angularUnit'] as String?) == 'MIL'
          ? AngularUnit.mil
          : AngularUnit.moa,
      clickValue: (map['clickValue'] as num?)?.toDouble() ?? 0.25,
      shotCount:
          (map['shotCount'] as num?)?.toInt() ?? 0,
      extremeSpreadMm:
          (map['extremeSpreadMm'] as num?)?.toDouble() ?? 0.0,
      extremeSpreadInches:
          (map['extremeSpreadInches'] as num?)?.toDouble() ?? 0.0,
      extremeSpreadAngular:
          (map['extremeSpreadAngular'] as num?)?.toDouble() ?? 0.0,
      meanRadiusMm: (map['meanRadiusMm'] as num?)?.toDouble() ?? 0.0,
      meanRadiusAngular:
          (map['meanRadiusAngular'] as num?)?.toDouble() ?? 0.0,
      offsetHorizontalMm:
          (map['offsetHorizontalMm'] as num?)?.toDouble() ?? 0.0,
      offsetVerticalMm:
          (map['offsetVerticalMm'] as num?)?.toDouble() ?? 0.0,
      suggestedUpClicks:
          (map['suggestedUpClicks'] as num?)?.toInt() ?? 0,
      suggestedRightClicks:
          (map['suggestedRightClicks'] as num?)?.toInt() ?? 0,
      precisionCategory: (map['precisionCategory'] as String?) ?? '',
      calibrated: (map['calibrated'] as num?)?.toInt() == 1,
      aimPoint: aim,
      createdAt: (map['createdAt'] as String?) ?? '',
    );
  }

  /// Build a [TargetSessionLog] from a completed [ShotGroupAnalysis] plus
  /// the screen inputs that produced it.
  static TargetSessionLog fromAnalysis({
    required String id,
    required String createdAt,
    required ShotGroupAnalysis analysis,
    required double distance,
    required DistanceUnit distanceUnit,
    required AngularUnit angularUnit,
    required double clickValue,
    required String firearmId,
    required String firearmLabel,
    required int suggestedUpClicks,
    required int suggestedRightClicks,
  }) {
    return TargetSessionLog(
      id: id,
      firearmId: firearmId,
      firearmLabel: firearmLabel,
      distance: distance,
      distanceUnit: distanceUnit,
      angularUnit: angularUnit,
      clickValue: clickValue,
      shotCount: analysis.shots.length,
      extremeSpreadMm: analysis.extremeSpreadMm,
      extremeSpreadInches: analysis.extremeSpreadInches,
      extremeSpreadAngular: analysis.extremeSpreadAngular,
      meanRadiusMm: analysis.meanRadiusMm,
      meanRadiusAngular: analysis.meanRadiusAngular,
      offsetHorizontalMm: analysis.offsetHorizontalMm,
      offsetVerticalMm: analysis.offsetVerticalMm,
      suggestedUpClicks: suggestedUpClicks,
      suggestedRightClicks: suggestedRightClicks,
      precisionCategory: analysis.precisionCategory(angularUnit),
      calibrated: analysis.isCalibrated,
      aimPoint: analysis.aimPoint,
      createdAt: createdAt,
    );
  }
}
