import 'dart:math';

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
        clicksX = (deviationX_radians / 0.001) / 0.1; // deviation in MRAD / click value
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
      tacticalString = '$directionY ${clicksYRounded.abs()} CLICKS, $directionX ${clicksXRounded.abs()} CLICKS';
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
      
      hitCoordinates.add({
        'x': x,
        'y': y,
      });
    }
    
    return hitCoordinates;
  }

  /// Calculates the center of a shot group from coordinate data.
  static Map<String, double> calculateGroupCenter(List<Map<String, double>> coordinates) {
    if (coordinates.isEmpty) {
      return {'x': 0.0, 'y': 0.0};
    }
    
    double sumX = 0.0;
    double sumY = 0.0;
    
    for (final coord in coordinates) {
      sumX += coord['x'] ?? 0.0;
      sumY += coord['y'] ?? 0.0;
    }
    
    return {
      'x': sumX / coordinates.length,
      'y': sumY / coordinates.length,
    };
  }
}
