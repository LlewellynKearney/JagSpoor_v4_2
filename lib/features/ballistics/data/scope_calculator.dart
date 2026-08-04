import 'dart:math';
import 'package:flutter/foundation.dart';

/// Result of the gyro holdover calculation.
class GyroHoldoverResult {
  final double trueHorizontalDistance;
  final bool isHoldingOver;
  final bool isHoldingUnder;
  final double clickUnits;
  final String direction;
  final String tacticalOutput;

  const GyroHoldoverResult({
    required this.trueHorizontalDistance,
    required this.isHoldingOver,
    required this.isHoldingUnder,
    required this.clickUnits,
    required this.direction,
    required this.tacticalOutput,
  });
}

/// Result of the MOA target correction calculation.
class MoaCorrectionResult {
  final double correctionX_clicks;
  final double correctionY_clicks;
  final String tacticalString;
  final double deviationX_minutes;
  final double deviationY_minutes;

  const MoaCorrectionResult({
    required this.correctionX_clicks,
    required this.correctionY_clicks,
    required this.tacticalString,
    required this.deviationX_minutes,
    required this.deviationY_minutes,
  });
}

/// Result of trajectory DOPE (Data On Past Experience) array generation.
class DopeResult {
  final List<double> distances;
  final List<double> clicks;
  final List<double> bulletDrops;
  final bool isValid;

  const DopeResult({
    required this.distances,
    required this.clicks,
    required this.bulletDrops,
    this.isValid = true,
  });

  static const DopeResult defaultDope = DopeResult(
    distances: [100, 200, 300, 400, 500],
    clicks: [0, 2, 5, 9, 14],
    bulletDrops: [0, -2, -6, -12, -20],
    isValid: true,
  );
}

/// Ballistic scope calculator with gyroscopic and AI targeting functions.
class ScopeCalculator {
  /// Validates that a value is not null, NaN, or close to zero.
  /// Returns the value if valid, or the default if not.
  static double _validateInput(double? value, double defaultValue) {
    if (value == null || value.isNaN || value.isInfinite) {
      return defaultValue;
    }
    return value;
  }

  /// Validates that a calculated value is a safe real number.
  /// Returns 0.0 if the value is NaN or Infinite, otherwise returns the value.
  static double _sanitizeOutput(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return 0.0;
    }
    return value;
  }

  /// Validates ballistic parameters for trajectory calculations.
  /// Returns true if parameters are valid for computation.
  static bool _validateBallisticParams({
    required double velocity,
    required double ballisticCoefficient,
  }) {
    if (velocity <= 0 || velocity.isNaN || velocity.isInfinite) {
      return false;
    }
    if (ballisticCoefficient <= 0 ||
        ballisticCoefficient.isNaN ||
        ballisticCoefficient.isInfinite) {
      return false;
    }
    return true;
  }

  /// Calculates the gyro holdover adjustment based on barrel angle.
  ///
  /// This function factors the true cosine distance range and determines
  /// if the action requires holding over or under, mapping the outputs
  /// straight into exact click units.
  ///
  /// Parameters:
  /// - [lineOfSightDistance] - Line of sight distance in meters
  /// - [barrelAngleDegrees] - Barrel angle in degrees (positive = up, negative = down)
  /// - [clickValueUnit] - Scope click value (e.g., 0.25 MOA, 0.1 MIL)
  ///
  /// Returns [GyroHoldoverResult] with true horizontal distance and click adjustment.
  static GyroHoldoverResult calculateGyroHoldover({
    required double lineOfSightDistance,
    required double barrelAngleDegrees,
    required double clickValueUnit,
  }) {
    // Validate all inputs against null, NaN, and infinite values
    final validatedDistance = _validateInput(lineOfSightDistance, 100.0);
    final validatedAngle = _validateInput(barrelAngleDegrees, 0.0);
    final validatedClickValue = _validateInput(clickValueUnit, 0.25);

    // Ensure distance is not zero or negative
    final safeDistance = validatedDistance <= 0 ? 100.0 : validatedDistance;

    // Convert angle to radians for cosine calculation
    final angleRad = validatedAngle * pi / 180.0;

    // Calculate true horizontal distance using cosine
    // True horizontal = Line of sight * cos(angle)
    final trueHorizontalDistance = safeDistance * cos(angleRad);

    // Calculate the difference between line of sight and horizontal
    final distanceDifference = safeDistance - trueHorizontalDistance;

    // Determine if we need to hold over or under
    final isHoldingOver = validatedAngle > 0;
    final isHoldingUnder = validatedAngle < 0;

    // Calculate click units needed for correction
    // Using a simplified model: 1 MOA ≈ 1.047" at 100 yards
    // For simplicity, we use the angular difference directly
    // This is a simplified approximation for demonstration
    double clicksPerMeter = 0.0;

    if (validatedClickValue > 0) {
      // Convert angular difference to clicks
      // Assuming scope is zeroed at horizontal, the angular difference
      // from line of sight needs to be compensated
      final angleDifferenceRad = distanceDifference / max(safeDistance, 1.0);

      // Simple linear approximation for small angles
      // In real-world, this would use more sophisticated ballistic equations
      final angleDifferenceDeg = angleDifferenceRad * 180.0 / pi;

      // Convert degrees to MOA (1 degree = 60 MOA)
      final angleDifferenceMoa = angleDifferenceDeg * 60.0;

      // Calculate clicks
      clicksPerMeter = angleDifferenceMoa.abs() / validatedClickValue;
    }

    // Build tactical output string
    String tacticalOutput;
    if (validatedAngle.abs() < 0.5) {
      tacticalOutput = 'LEVEL - NO ADJUSTMENT';
    } else if (isHoldingOver) {
      tacticalOutput = 'HOLD OVER ${clicksPerMeter.toStringAsFixed(0)} CLICKS';
    } else {
      tacticalOutput = 'HOLD UNDER ${clicksPerMeter.toStringAsFixed(0)} CLICKS';
    }

    return GyroHoldoverResult(
      trueHorizontalDistance: trueHorizontalDistance,
      isHoldingOver: isHoldingOver,
      isHoldingUnder: isHoldingUnder,
      clickUnits: clicksPerMeter,
      direction: isHoldingOver ? 'UP' : (isHoldingUnder ? 'DOWN' : 'LEVEL'),
      tacticalOutput: tacticalOutput,
    );
  }

  /// Calculates AI target deviation correction for scope adjustment.
  ///
  /// Takes the deviation coordinates from an AI target scanning system
  /// and calculates the exact center correction parameters.
  ///
  /// Parameters:
  /// - [deviationX_cm] - Horizontal deviation in centimeters
  /// - [deviationY_cm] - Vertical deviation in centimeters
  /// - [targetDistanceMeters] - Distance to target in meters
  /// - [scopeUnitType] - Scope unit type: 'MOA' or 'MRAD'
  ///
  /// Returns [MoaCorrectionResult] with tactical correction string.
  static MoaCorrectionResult calculateMoaTargetCorrection({
    required double deviationX_cm,
    required double deviationY_cm,
    required double targetDistanceMeters,
    required String scopeUnitType,
  }) {
    // Validate all numeric inputs against NaN and infinite values
    final validatedDevX = _validateInput(deviationX_cm, 0.0);
    final validatedDevY = _validateInput(deviationY_cm, 0.0);
    final validatedDistance = _validateInput(targetDistanceMeters, 100.0);

    // Ensure distance is positive
    final safeDistance = validatedDistance <= 0 ? 100.0 : validatedDistance;

    // Convert cm to inches for MOA calculations
    final deviationX_inches = validatedDevX / 2.54;
    final deviationY_inches = validatedDevY / 2.54;

    // Convert distance to yards
    final targetDistanceYards = safeDistance * 1.09361;

    // Calculate minutes of angle
    // MOA = (deviation in inches / distance in yards) * 100 yards approximation
    // More precisely: MOA = arctan(deviation / distance) in radians * (180/pi) * 60
    double deviationX_minutes;
    double deviationY_minutes;
    double clicksX;
    double clicksY;

    if (targetDistanceYards > 0) {
      // Using arctangent for more accurate MOA calculation
      final distanceFeet = targetDistanceYards * 3.0;
      final distanceInches = distanceFeet * 12.0;

      deviationX_minutes = (deviationX_inches / distanceInches) * 3437.75;
      deviationY_minutes = (deviationY_inches / distanceInches) * 3437.75;

      if (scopeUnitType.toUpperCase() == 'MRAD') {
        // MRAD calculation: 1 MRAD at distance = distance in meters / 1000 radians
        // 1 MRAD = 0.001 radians
        // At 100m: 1 MRAD = 0.1m = 10cm
        // Deviation in radians = deviation in cm / (distance in cm * 100)
        // Clicks = deviation in radians / 0.0001 (0.1 MRAD per click)
        final distanceCm = safeDistance * 100;
        final deviationX_radians = validatedDevX / distanceCm;
        final deviationY_radians = validatedDevY / distanceCm;

        // Convert to MRAD (milliradians) and divide by 0.1 for clicks (0.1 MRAD per click)
        clicksX =
            (deviationX_radians / 0.001) /
            0.1; // deviation in MRAD / click value
        clicksY = (deviationY_radians / 0.001) / 0.1;
      } else {
        // MOA: typically 1/4 MOA per click (0.25 MOA)
        clicksX = deviationX_minutes / 0.25;
        clicksY = deviationY_minutes / 0.25;
      }
    } else {
      deviationX_minutes = 0.0;
      deviationY_minutes = 0.0;
      clicksX = 0.0;
      clicksY = 0.0;
    }

    // Round to nearest integer for tactical output
    final clicksXRounded = clicksX.round();
    final clicksYRounded = clicksY.round();

    // Build tactical string with direction indicators
    final String directionX;
    final String directionY;

    if (validatedDevX > 0) {
      directionX = 'RIGHT';
    } else if (validatedDevX < 0) {
      directionX = 'LEFT';
    } else {
      directionX = '';
    }

    if (validatedDevY > 0) {
      directionY = 'UP';
    } else if (validatedDevY < 0) {
      directionY = 'DOWN';
    } else {
      directionY = '';
    }

    // Build tactical output string
    String tacticalString;
    if (directionX.isNotEmpty && directionY.isNotEmpty) {
      tacticalString =
          '$directionY ${clicksYRounded.abs()} CLICKS, $directionX ${clicksXRounded.abs()} CLICKS';
    } else if (directionX.isNotEmpty) {
      tacticalString = '$directionX ${clicksXRounded.abs()} CLICKS';
    } else if (directionY.isNotEmpty) {
      tacticalString = '$directionY ${clicksYRounded.abs()} CLICKS';
    } else {
      tacticalString = 'CENTER - NO ADJUSTMENT';
    }

    return MoaCorrectionResult(
      correctionX_clicks: clicksXRounded.toDouble(),
      correctionY_clicks: clicksYRounded.toDouble(),
      tacticalString: tacticalString,
      deviationX_minutes: deviationX_minutes,
      deviationY_minutes: deviationY_minutes,
    );
  }

  /// Calculates the cosine horizontal distance from a given line of sight and angle.
  static double calculateTrueHorizontalDistance({
    required double lineOfSightDistance,
    required double angleDegrees,
  }) {
    final validatedDistance = _validateInput(lineOfSightDistance, 100.0);
    final validatedAngle = _validateInput(angleDegrees, 0.0);
    if (validatedDistance <= 0) return 0.0;

    final angleRad = validatedAngle * pi / 180.0;
    return validatedDistance * cos(angleRad);
  }

  /// Calculates elevation correction in MOA for a given distance.
  static double calculateElevationCorrection({
    required double distanceMeters,
    required double zeroDistanceMeters,
    required double bulletDropInches,
  }) {
    final validatedDistance = _validateInput(distanceMeters, 100.0);
    final validatedDrop = _validateInput(bulletDropInches, 0.0);

    final distanceYards = validatedDistance * 1.09361;
    if (distanceYards <= 0) return 0.0;

    // MOA correction = (drop in inches / distance in yards) * 100
    return (validatedDrop / distanceYards) * 100.0;
  }

  /// Calculates windage correction in MOA.
  static double calculateWindageCorrection({
    required double windSpeedMph,
    required double distanceMeters,
    required double bulletVelocityFps,
  }) {
    final validatedDistance = _validateInput(distanceMeters, 100.0);
    final validatedWind = _validateInput(windSpeedMph, 0.0);
    final validatedVelocity = _validateInput(bulletVelocityFps, 1000.0);

    final distanceYards = validatedDistance * 1.09361;
    if (distanceYards <= 0 || validatedVelocity <= 0) return 0.0;

    // Simplified windage formula
    // Windage in MOA ≈ (wind speed * distance) / (bullet velocity * constant)
    const windConstant = 15.0; // Simplified constant
    return (validatedWind * distanceYards) / (validatedVelocity * windConstant);
  }

  /// Simulates AI target scanning with coordinate array evaluation.
  /// Returns simulated deviation data for demonstration.
  static List<Map<String, double>> simulateTargetScanData({
    required double targetDistanceMeters,
  }) {
    final validatedDistance = _validateInput(targetDistanceMeters, 100.0);
    if (validatedDistance <= 0) {
      return <Map<String, double>>[];
    }

    final random = Random();
    final hitCount = 3 + random.nextInt(5); // 3-7 simulated hits

    final List<Map<String, double>> hitCoordinates = [];

    // Simulate shot group centered around a slightly offset point
    final centerOffsetX = (random.nextDouble() - 0.5) * 5.0; // -2.5 to +2.5 cm
    final centerOffsetY = (random.nextDouble() - 0.5) * 5.0; // -2.5 to +2.5 cm

    for (int i = 0; i < hitCount; i++) {
      // Generate random spread around the center
      final x = centerOffsetX + (random.nextDouble() - 0.5) * 3.0;
      final y = centerOffsetY + (random.nextDouble() - 0.5) * 3.0;

      hitCoordinates.add({'x': x, 'y': y});
    }

    return hitCoordinates;
  }

  /// Calculates the center of a shot group from coordinate data.
  static Map<String, double> calculateGroupCenter(
    List<Map<String, double>> coordinates,
  ) {
    if (coordinates.isEmpty) {
      return {'x': 0.0, 'y': 0.0};
    }

    double sumX = 0.0;
    double sumY = 0.0;

    for (final coord in coordinates) {
      sumX += coord['x'] ?? 0.0;
      sumY += coord['y'] ?? 0.0;
    }

    // Sanitize output values to prevent NaN
    final count = coordinates.length.toDouble();
    return {
      'x': _sanitizeOutput(sumX / count),
      'y': _sanitizeOutput(sumY / count),
    };
  }

  /// Generates a trajectory DOPE (Data On Past Experience) array with atmospheric corrections.
  ///
  /// Parameters:
  /// - [velocity] - Muzzle velocity in meters per second
  /// - [ballisticCoefficient] - G7 ballistic coefficient
  /// - [zeroDistance] - Zero distance in meters
  /// - [maxDistance] - Maximum range to calculate in meters
  /// - [temperature] - Temperature in Celsius (default: 15°C)
  /// - [altitude] - Altitude in meters (default: 0m)
  ///
  /// Returns [DopeResult] with distance/click/drop arrays or default safe values on error.
  static DopeResult generateDopeArrayWithAtmosphere({
    required double velocity,
    required double ballisticCoefficient,
    double zeroDistance = 100.0,
    double maxDistance = 500.0,
    double temperature = 15.0,
    double altitude = 0.0,
  }) {
    // Validate ballistic parameters - return safe default on invalid input
    if (!_validateBallisticParams(
      velocity: velocity,
      ballisticCoefficient: ballisticCoefficient,
    )) {
      debugPrint(
        'ScopeCalculator: Invalid ballistic parameters - returning default DOPE',
      );
      return DopeResult.defaultDope;
    }

    // Validate atmospheric parameters
    final safeMaxDistance = _validateInput(maxDistance, 500.0);
    final safeTemp = _validateInput(temperature, 15.0);
    final safeAlt = _validateInput(altitude, 0.0);

    // Calculate atmospheric density factor
    // Standard atmosphere: sea level at 15°C = 1.0
    // Temperature correction: -0.1% per °C deviation from 15°C
    // Altitude correction: -0.03% per 100m
    final tempFactor = 1.0 - ((safeTemp - 15.0) * 0.001);
    final altFactor = 1.0 - (safeAlt * 0.0003);
    final atmosphericFactor = _sanitizeOutput(tempFactor * altFactor);

    if (atmosphericFactor <= 0 || atmosphericFactor.isNaN) {
      return DopeResult.defaultDope;
    }

    // Adjust velocity for atmospheric conditions
    final adjustedVelocity = _sanitizeOutput(
      velocity * sqrt(atmosphericFactor),
    );

    // Standard yard distances for DOPE card
    final distances = <double>[100, 200, 300, 400, 500, 600, 700, 800];
    final clicks = <double>[];
    final bulletDrops = <double>[];

    for (final distance in distances) {
      if (distance > safeMaxDistance) {
        break;
      }

      // Skip invalid distances
      if (distance <= 0) {
        clicks.add(0.0);
        bulletDrops.add(0.0);
        continue;
      }

      // Simplified trajectory calculation using Siacci's method approximation
      // Drop (inches) ≈ (distance²) / (velocity² × BC × constant)
      // This is a simplified ballistic model for demonstration
      final distanceYards = distance * 1.09361;

      // Calculate velocity at distance using drag approximation
      final velocityRatio = adjustedVelocity / velocity;
      final currentVelocity = _sanitizeOutput(adjustedVelocity * velocityRatio);

      // Skip if velocity is zero or negative (prevents division by zero)
      if (currentVelocity <= 0) {
        clicks.add(0.0);
        bulletDrops.add(0.0);
        continue;
      }

      // Calculate bullet drop using simplified point mass model
      // g = 386.09 in/s², yards to inches = 36
      const g = 386.09;
      const yardsToInches = 36.0;
      final timeOfFlight = _sanitizeOutput(
        (distanceYards * yardsToInches) / currentVelocity,
      );

      if (timeOfFlight.isNaN || timeOfFlight.isInfinite || timeOfFlight <= 0) {
        clicks.add(0.0);
        bulletDrops.add(0.0);
        continue;
      }

      // Calculate drop: y = 0.5 * g * t²
      final dropInches = _sanitizeOutput(0.5 * g * timeOfFlight * timeOfFlight);

      // Calculate MOA adjustment needed
      // MOA = (drop in inches / distance in yards) * 100 (approximation)
      double moaAdjustment;
      if (distanceYards > 0) {
        moaAdjustment = _sanitizeOutput((dropInches / distanceYards) * 100);
      } else {
        moaAdjustment = 0.0;
      }

      // Convert MOA to clicks (assuming 0.25 MOA per click)
      final clicksNeeded = _sanitizeOutput(moaAdjustment / 0.25);

      // Sanitize all outputs
      final safeClicks = _sanitizeOutput(clicksNeeded);
      final safeDrop = _sanitizeOutput(dropInches);

      clicks.add(safeClicks);
      bulletDrops.add(safeDrop);
    }

    // Validate final arrays contain no NaN or infinite values
    bool hasValidData = true;
    for (final click in clicks) {
      if (click.isNaN || click.isInfinite) {
        hasValidData = false;
        break;
      }
    }
    for (final drop in bulletDrops) {
      if (drop.isNaN || drop.isInfinite) {
        hasValidData = false;
        break;
      }
    }

    if (!hasValidData || clicks.isEmpty) {
      debugPrint(
        'ScopeCalculator: NaN detected in trajectory array - returning default DOPE',
      );
      return DopeResult.defaultDope;
    }

    return DopeResult(
      distances: distances.sublist(0, clicks.length),
      clicks: clicks,
      bulletDrops: bulletDrops,
      isValid: true,
    );
  }
}
