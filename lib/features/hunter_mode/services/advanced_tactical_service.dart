import 'dart:math' as math;

/// Central Bluetooth Rangefinder Core and AI Solunar Predictor service.
/// Provides forward GPS projection calculations and offline game movement forecasting.
class AdvancedTacticalService {
  static final AdvancedTacticalService instance = AdvancedTacticalService._internal();
  AdvancedTacticalService._internal();

  // Earth's radius in meters for spherical calculations
  static const double earthRadiusMeters = 6371000.0;

  // Conversion constants
  static const double yardsToMetersFactor = 0.9144;
  static const double degreesToRadiansFactor = math.pi / 180.0;
  static const double radiansToDegreesFactor = 180.0 / math.pi;

  // ==========================================
  // 1. COMPUTE FORWARD GPS GEO-PROJECTION
  // ==========================================

  /// Projects a target's GPS coordinates based on starting position, bearing, and distance.
  /// Uses spherical forward projection with trigonometric offsets to calculate
  /// the exact position where a laser-ranged target is located.
  ///
  /// Parameters:
  /// - [startLat]: Starting latitude in decimal degrees
  /// - [startLon]: Starting longitude in decimal degrees
  /// - [bearingDegrees]: Direction of travel/bearing in degrees (0-360)
  /// - [distanceYards]: Distance to target in yards
  ///
  /// Returns a Map with projected coordinates:
  /// - 'lat': Projected latitude in decimal degrees
  /// - 'lon': Projected longitude in decimal degrees
  ///
  /// Calculation uses the equirectangular projection formula for simplicity:
  /// x = Δλ × cos(φm)
  /// y = Δφ
  /// where d = √(x² + y²) is the angular distance
  Map<String, double> projectTargetCoordinates({
    required double startLat,
    required double startLon,
    required double bearingDegrees,
    required double distanceYards,
  }) {
    // Convert distance from yards to meters
    final distanceMeters = distanceYards * yardsToMetersFactor;

    // Convert starting coordinates to radians
    final lat1 = startLat * degreesToRadiansFactor;
    final lon1 = startLon * degreesToRadiansFactor;

    // Convert bearing to radians
    final bearingRadians = bearingDegrees * degreesToRadiansFactor;

    // Angular distance in radians
    final angularDistance = distanceMeters / earthRadiusMeters;

    // Calculate projected latitude using spherical projection formula
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearingRadians),
    );

    // Calculate projected longitude using spherical projection formula
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearingRadians) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );

    // Convert back to decimal degrees
    final projectedLat = lat2 * radiansToDegreesFactor;
    final projectedLon = lon2 * radiansToDegreesFactor;

    // Normalize longitude to -180 to 180 range
    final normalizedLon = ((projectedLon + 540) % 360) - 180;

    return {
      'lat': projectedLat,
      'lon': normalizedLon,
    };
  }

  /// Alternative projection using Haversine-based calculation for longer distances.
  /// More accurate for distances over 1km.
  Map<String, double> projectTargetCoordinatesHaversine({
    required double startLat,
    required double startLon,
    required double bearingDegrees,
    required double distanceYards,
  }) {
    // Convert distance from yards to meters
    final distanceMeters = distanceYards * yardsToMetersFactor;

    // Convert to radians
    final lat1 = startLat * degreesToRadiansFactor;
    final lon1 = startLon * degreesToRadiansFactor;
    final bearingRad = bearingDegrees * degreesToRadiansFactor;

    // Angular distance
    final angularDist = distanceMeters / earthRadiusMeters;

    // Spherical law of cosines projection
    final newLat = math.asin(
      math.sin(lat1) * math.cos(angularDist) +
          math.cos(lat1) * math.sin(angularDist) * math.cos(bearingRad),
    );

    final newLon = lon1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(angularDist) * math.cos(lat1),
          math.cos(angularDist) - math.sin(lat1) * math.sin(newLat),
        );

    return {
      'lat': newLat * radiansToDegreesFactor,
      'lon': ((newLon * radiansToDegreesFactor + 540) % 360) - 180,
    };
  }

  // ==========================================
  // 2. OFFLINE REAL-TIME GAME MOVEMENT FORECASTER
  // ==========================================

  /// Calculates game movement probability based on barometric pressure,
  /// solunar data, and weather conditions.
  ///
  /// This heuristic algorithm combines environmental factors that affect
  /// animal movement patterns:
  /// - Barometric pressure changes trigger feeding activity
  /// - Stable or rising pressure indicates good hunting conditions
  /// - Solunar periods align with peak feeding times
  ///
  /// Parameters:
  /// - [barometricPressureHpa]: Current barometric pressure in hectopascals (hPa)
  /// - [pressureDeltaLast3Hours]: Change in pressure over last 3 hours (hPa)
  /// - [moonPhasePercent]: Current moon phase as percentage (0-100)
  ///   - 0% = New Moon, 50% = Full Moon, 100% = New Moon
  /// - [isMajorSolunarWindow]: True if currently in major solunar transit
  ///   (moon overhead or underfoot)
  ///
  /// Returns probability as a percentage between 0.0% and 100.0%
  double calculateMovementProbability({
    required double barometricPressureHpa,
    required double pressureDeltaLast3Hours,
    required int moonPhasePercent,
    required bool isMajorSolunarWindow,
  }) {
    // Start with baseline probability
    double probability = 50.0;

    // Storm front detection: Rapidly dropping pressure indicates
    // incoming weather, which often triggers pre-storm feeding activity
    if (pressureDeltaLast3Hours < -2.0) {
      // Significant pressure drop - animals sense incoming weather
      probability += 25.0;
    } else if (pressureDeltaLast3Hours < -1.0) {
      // Moderate pressure drop
      probability += 12.0;
    }

    // Ideal pressure range for game movement (1010-1018 hPa)
    // Outside this range, animals tend to bed down
    if (barometricPressureHpa >= 1010 && barometricPressureHpa <= 1018) {
      // Sweet spot for hunting pressure
      probability += 15.0;
    } else if (barometricPressureHpa >= 1005 && barometricPressureHpa <= 1020) {
      // Acceptable range
      probability += 8.0;
    }

    // Solunar major transit window - peak feeding period
    if (isMajorSolunarWindow) {
      probability += 20.0;
    }

    // Clamp final probability between 0.0 and 100.0
    probability = probability.clamp(0.0, 100.0);

    return probability;
  }

  /// Simplified movement forecast returning a categorical rating.
  String getMovementForecastLabel({
    required double barometricPressureHpa,
    required double pressureDeltaLast3Hours,
    required int moonPhasePercent,
    required bool isMajorSolunarWindow,
  }) {
    final probability = calculateMovementProbability(
      barometricPressureHpa: barometricPressureHpa,
      pressureDeltaLast3Hours: pressureDeltaLast3Hours,
      moonPhasePercent: moonPhasePercent,
      isMajorSolunarWindow: isMajorSolunarWindow,
    );

    if (probability >= 80) {
      return 'EXCELLENT';
    } else if (probability >= 65) {
      return 'GOOD';
    } else if (probability >= 50) {
      return 'MODERATE';
    } else if (probability >= 35) {
      return 'LOW';
    } else {
      return 'POOR';
    }
  }

  /// Returns hunting recommendation based on current conditions.
  String getHuntingRecommendation({
    required double barometricPressureHpa,
    required double pressureDeltaLast3Hours,
    required int moonPhasePercent,
    required bool isMajorSolunarWindow,
  }) {
    final probability = calculateMovementProbability(
      barometricPressureHpa: barometricPressureHpa,
      pressureDeltaLast3Hours: pressureDeltaLast3Hours,
      moonPhasePercent: moonPhasePercent,
      isMajorSolunarWindow: isMajorSolunarWindow,
    );

    if (probability >= 80) {
      if (isMajorSolunarWindow) {
        return 'Prime conditions! Major solunar transit active with optimal pressure. Best hunting window.';
      }
      return 'Excellent conditions. Pressure stable and ideal. Excellent hunting opportunity.';
    } else if (probability >= 65) {
      return 'Good hunting conditions. Animals likely active. Consider dawn/dusk for best results.';
    } else if (probability >= 50) {
      return 'Moderate conditions. Animals may be less active. Focus on water sources and funnels.';
    } else if (probability >= 35) {
      return 'Low activity expected. Animals bedding down due to weather. May improve after frontal passage.';
    } else {
      return 'Poor conditions. Weather pressure unfavorable. Consider scouting or equipment maintenance.';
    }
  }
}
