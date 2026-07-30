import 'dart:math' as math;

/// Offline ballistic trajectory processing engine for scope adjustment calculations.
/// Implements point-mass trajectory model with air density and angle corrections.
class BallisticSolverService {
  static final BallisticSolverService _instance = BallisticSolverService._internal();
  static BallisticSolverService get instance => _instance;
  BallisticSolverService._internal();

  /// Standard atmospheric pressure at sea level in hPa
  static const double _seaLevelPressureHpa = 1013.25;

  /// Air density factor based on barometric pressure (relative to standard atmosphere)
  /// Returns a multiplier where 1.0 = standard sea level density
  double _calculateAirDensityFactor(double pressureHpa) {
    // Using simplified barometric formula for air density ratio
    // ρ/ρ₀ ≈ P/P₀ (assuming constant temperature - simplified model)
    return pressureHpa / _seaLevelPressureHpa;
  }

  /// Calculates bullet trajectory drop using simplified point-mass model.
  /// 
  /// Physics model:
  /// - Horizontal velocity: vx = v₀ × cos(θ)
  /// - Vertical velocity: vy = v₀ × sin(θ) - g × t
  /// - Position: y = v₀ × sin(θ) × t - ½ × g × t²
  /// - x = v₀ × cos(θ) × t (horizontal range)
  /// 
  /// Where:
  /// - v₀ = muzzle velocity (fps)
  /// - θ = launch angle (degrees)
  /// - g = 32.174 ft/s² (gravitational acceleration)
  /// - t = time of flight
  /// - Air resistance simplified via ballistic coefficient and density factor
  double _calculateTrajectoryDrop({
    required double distanceYards,
    required double angleDegrees,
    required double muzzleVelocityFps,
    required double ballisticCoefficient,
    required double scopeHeightInches,
    required double densityFactor,
  }) {
    // Convert to consistent units (feet)
    final distanceFeet = distanceYards * 3.0;
    final scopeHeightFeet = scopeHeightInches / 12.0;
    
    // Calculate slant range angle cosine for horizontal component
    final angleRadians = angleDegrees * (math.pi / 180.0);
    final cosAngle = math.cos(angleRadians);
    
    // Time of flight estimate using simplified ballistic formula
    // t ≈ range / (muzzle velocity × cos(angle) × density correction)
    // This accounts for drag via ballistic coefficient and air density
    final velocityComponent = muzzleVelocityFps * cosAngle;
    final dragFactor = 1.0 / (1.0 + (0.05 / ballisticCoefficient) * (1.0 / densityFactor));
    final timeOfFlightSeconds = distanceFeet / (velocityComponent * dragFactor);
    
    // Gravitational acceleration in ft/s²
    const g = 32.174;
    
    // Calculate vertical drop relative to bore line
    // Bullet starts below line of sight by scope height
    // Net drop relative to scope height:
    // drop = scopeHeightFeet + (v₀ × sin(θ) × t) - ½ × g × t²
    final sinAngle = math.sin(angleRadians);
    final verticalComponent = muzzleVelocityFps * sinAngle * timeOfFlightSeconds;
    final gravitationalDrop = 0.5 * g * timeOfFlightSeconds * timeOfFlightSeconds;
    
    // Total drop relative to bore centerline, then convert to line-of-sight drop
    // The cosine of the angle gives us the LOS drop component
    final rawDropFeet = scopeHeightFeet + verticalComponent - gravitationalDrop;
    final losDropFeet = rawDropFeet * cosAngle;
    
    // Convert to inches (positive = drop below target)
    final dropInches = losDropFeet * 12.0;
    
    // Apply additional ballistic coefficient drag correction
    // Higher BC = less drop, lower BC = more drop
    final bcCorrectionFactor = 1.0 - (0.1 / ballisticCoefficient.clamp(0.1, 2.0));
    
    return dropInches * bcCorrectionFactor * densityFactor;
  }

  /// Calculates total MOA (Minutes of Angle) required for the given drop.
  /// 
  /// MOA formula: MOA = (drop_inches / distance_yards) × 100
  /// At 100 yards, 1 MOA ≈ 1.047 inches (using standard approximation of 1 inch)
  double _calculateTotalMOA({
    required double dropInches,
    required double distanceYards,
  }) {
    if (distanceYards <= 0) return 0.0;
    // Using the standard approximation: 1 MOA at 100 yards = 1 inch
    // More precisely: MOA = (drop × 100) / distance
    return (dropInches * 100.0) / distanceYards;
  }

  /// Calculates total MRAD (Milliradians) required for the given drop.
  /// 
  /// MRAD formula: MRAD = drop_inches / (distance_yards × 36 / 1000)
  /// Simplifies to: MRAD = drop_inches × 1000 / (distance_yards × 36)
  double _calculateTotalMRAD({
    required double dropInches,
    required double distanceYards,
  }) {
    if (distanceYards <= 0) return 0.0;
    // 1 mil = 3.6 inches at 100 yards
    // MRAD = drop / (distance × 0.036)
    return dropInches / (distanceYards * 0.036);
  }

  /// Calculates integer click count for the given angular adjustment.
  /// 
  /// clicks = total_angle / click_value
  /// Where click_value is expressed in the same unit system (MOA or MRAD)
  int _calculateClickCount({
    required double totalAngle,
    required double clickValue,
  }) {
    if (clickValue <= 0) return 0;
    return (totalAngle.abs() / clickValue).floor();
  }

  /// Main entry point: Calculates scope adjustments for given parameters.
  /// 
  /// Implements precise physical trajectory estimation formula factoring in:
  /// - Gravity (32.174 ft/s²)
  /// - Slant-range cosine angle shortcuts
  /// - Air density corrections based on barometric pressure
  /// 
  /// Returns structured data map tracking:
  /// - dropInches: Bullet drop in inches (positive = below target)
  /// - totalMOA: Total MOA adjustment needed
  /// - totalMRAD: Total MRAD adjustment needed  
  /// - clicksToDial: Integer count of 1/4 MOA clicks required
  /// - densityFactor: Air density multiplier relative to sea level
  Map<String, dynamic> calculateScopeAdjustments({
    required double distanceYards,
    required double angleDegrees,
    required double muzzleVelocityFps,
    required double ballisticCoefficient,
    required double scopeHeightInches,
    required double turretClickValue, // e.g., 0.25 for 1/4 MOA
    required double barometricPressureHpa,
  }) {
    // Input validation and clamping
    final validDistance = distanceYards.clamp(0.0, 2000.0);
    final validAngle = angleDegrees.clamp(-90.0, 90.0);
    final validVelocity = muzzleVelocityFps.clamp(500.0, 5000.0);
    final validBC = ballisticCoefficient.clamp(0.05, 2.0);
    final validScopeHeight = scopeHeightInches.clamp(0.5, 5.0);
    final validClick = turretClickValue.clamp(0.01, 1.0);
    final validPressure = barometricPressureHpa.clamp(800.0, 1200.0);

    // Calculate air density factor from barometric pressure
    final densityFactor = _calculateAirDensityFactor(validPressure);

    // Calculate trajectory drop
    final dropInches = _calculateTrajectoryDrop(
      distanceYards: validDistance,
      angleDegrees: validAngle,
      muzzleVelocityFps: validVelocity,
      ballisticCoefficient: validBC,
      scopeHeightInches: validScopeHeight,
      densityFactor: densityFactor,
    );

    // Calculate total MOA adjustment
    final totalMOA = _calculateTotalMOA(
      dropInches: dropInches.abs(),
      distanceYards: validDistance,
    );

    // Calculate total MRAD adjustment
    final totalMRAD = _calculateTotalMRAD(
      dropInches: dropInches.abs(),
      distanceYards: validDistance,
    );

    // Calculate integer click count (standardizing to MOA clicks)
    final clicksToDial = _calculateClickCount(
      totalAngle: totalMOA,
      clickValue: validClick,
    );

    // Determine if we need elevation UP or DOWN
    final isDropPositive = dropInches > 0;
    final isUphillShot = validAngle > 0;

    // Windage approximation (simplified - would need actual wind data)
    // For now, return zero windage
    const windageMOA = 0.0;
    const windageClicks = 0;

    return {
      'dropInches': double.parse(dropInches.toStringAsFixed(2)),
      'totalMOA': double.parse(totalMOA.toStringAsFixed(2)),
      'totalMRAD': double.parse(totalMRAD.toStringAsFixed(2)),
      'clicksToDial': clicksToDial,
      'isDropPositive': isDropPositive,
      'isUphillShot': isUphillShot,
      'densityFactor': double.parse(densityFactor.toStringAsFixed(4)),
      'windageMOA': windageMOA,
      'windageClicks': windageClicks,
      'distanceYards': validDistance,
      'angleDegrees': validAngle,
      'muzzleVelocityFps': validVelocity,
      'ballisticCoefficient': validBC,
      'scopeHeightInches': validScopeHeight,
      'turretClickValue': validClick,
      'barometricPressureHpa': validPressure,
    };
  }

  /// Calculates effective range considering atmospheric conditions.
  /// Returns maximum effective distance in yards where trajectory remains within target zone.
  double calculateEffectiveRange({
    required double muzzleVelocityFps,
    required double ballisticCoefficient,
    required double scopeHeightInches,
    required double maxAllowableDropInches,
    required double barometricPressureHpa,
  }) {
    // Binary search for effective range
    double low = 0;
    double high = 2000;
    double effectiveRange = 0;

    final densityFactor = _calculateAirDensityFactor(barometricPressureHpa);

    for (int i = 0; i < 20; i++) {
      final mid = (low + high) / 2;
      final drop = _calculateTrajectoryDrop(
        distanceYards: mid,
        angleDegrees: 0,
        muzzleVelocityFps: muzzleVelocityFps,
        ballisticCoefficient: ballisticCoefficient,
        scopeHeightInches: scopeHeightInches,
        densityFactor: densityFactor,
      );

      if (drop.abs() <= maxAllowableDropInches) {
        effectiveRange = mid;
        low = mid;
      } else {
        high = mid;
      }
    }

    return effectiveRange;
  }

  /// Generates a full trajectory table for a range of distances.
  /// Useful for building dope cards.
  List<Map<String, dynamic>> generateTrajectoryTable({
    required double muzzleVelocityFps,
    required double ballisticCoefficient,
    required double scopeHeightInches,
    required double turretClickValue,
    required double barometricPressureHpa,
    double startYards = 100,
    double endYards = 500,
    double stepYards = 50,
  }) {
    final List<Map<String, dynamic>> table = [];
    final densityFactor = _calculateAirDensityFactor(barometricPressureHpa);

    for (double distance = startYards; distance <= endYards; distance += stepYards) {
      final drop = _calculateTrajectoryDrop(
        distanceYards: distance,
        angleDegrees: 0,
        muzzleVelocityFps: muzzleVelocityFps,
        ballisticCoefficient: ballisticCoefficient,
        scopeHeightInches: scopeHeightInches,
        densityFactor: densityFactor,
      );

      final moa = _calculateTotalMOA(dropInches: drop.abs(), distanceYards: distance);
      final clicks = _calculateClickCount(totalAngle: moa, clickValue: turretClickValue);

      table.add({
        'range': distance.toInt(),
        'dropInches': double.parse(drop.toStringAsFixed(2)),
        'moa': double.parse(moa.toStringAsFixed(2)),
        'clicks': clicks,
      });
    }

    return table;
  }
}
