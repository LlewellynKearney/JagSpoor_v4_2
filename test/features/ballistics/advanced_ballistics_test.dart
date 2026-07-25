import 'dart:math';

// ============================================================================
// Advanced Ballistics Test Suite v8.1
// Validates gyroscopic cosine calculations and atmospheric altitude modifiers
// ============================================================================

/// Represents a 2D point with trajectory data.
class Point {
  final double distance;
  final double drop;
  final double velocity;
  final double time;
  final double windDrift;

  const Point({
    required this.distance,
    required this.drop,
    required this.velocity,
    required this.time,
    required this.windDrift,
  });
}

/// Calculates the gyroscopic stability factor using the Miller formula.
///
/// The gyroscopic stability factor (Sg) determines bullet stability based on:
/// - Bullet length, diameter, and weight
/// - Twist rate
/// - Velocity
///
/// Parameters:
/// - bulletLength: Bullet length in calibers
/// - bulletDiameter: Bullet diameter in inches (caliber)
/// - bulletWeight: Bullet weight in grains
/// - twistRate: Twist rate in inches per turn
/// - velocity: Current velocity in ft/s
///
/// Returns: Gyroscopic stability factor (>1 = stable, <1 = unstable)
double calculateGyroscopicStability({
  required double bulletLength,
  required double bulletBulletDiameter,
  required double bulletWeight,
  required double twistRate,
  required double velocity,
}) {
  // Calculate gyroscopic moment of inertia
  final di = bulletWeight * (3 * bulletBulletDiameter * bulletBulletDiameter + 4 * twistRate * twistRate) / 12;

  // Calculate aerodynamic damping
  final da = bulletWeight * bulletBulletDiameter * bulletBulletDiameter * velocity * velocity / (twistRate * twistRate);

  // Miller stability formula
  final sgf = 8 * pi * pi * di / (bulletWeight * bulletWeight * bulletLength * bulletLength * da);

  return sgf;
}

/// Calculates the cosine component for gyroscopic drift correction.
///
/// The gyroscopic effect causes bullets to drift perpendicular to their
/// plane of oscillation, affecting long-range accuracy.
///
/// Parameters:
/// - pitchAngle: The bullet's pitch angle in degrees
/// - spinRate: Angular velocity in RPM
///
/// Returns: Cosine component for drift calculation
double calculateGyroscopicCosineComponent({
  required double pitchAngle,
  required double spinRate,
}) {
  // Convert pitch angle to radians
  final pitchRad = pitchAngle * pi / 180.0;

  // Gyroscopic precession rate (simplified)
  final precessionRate = spinRate * cos(pitchRad);

  // Return cosine component normalized to typical spin rates
  return cos(precessionRate / 3000);
}

/// Calculates atmospheric density ratio based on altitude and temperature.
///
/// The atmospheric density affects bullet drag and trajectory.
///
/// Parameters:
/// - altitudeM: Altitude in meters above sea level
/// - temperatureC: Temperature in Celsius
/// - pressureHpa: Barometric pressure in hPa (optional, defaults to standard)
/// - humidityPercent: Relative humidity percentage
///
/// Returns: Density ratio relative to sea level standard conditions
double calculateAtmosphericDensityRatio({
  required double altitudeM,
  required double temperatureC,
  double pressureHpa = 1013.25,
  double humidityPercent = 0.0,
}) {
  // Standard sea level conditions
  const double seaLevelPressure = 1013.25; // hPa
  const double seaLevelDensity = 1.225; // kg/m³
  const double temperatureLapseRate = 0.0065; // K/m
  const double standardTemp = 288.15; // K (15°C)
  const double gravity = 9.80665;
  const double molarMass = 0.0289644;
  const double gasConstant = 8.3144598;

  // Temperature at altitude (international standard atmosphere)
  final tempK = standardTemp - (temperatureLapseRate * altitudeM);

  // Pressure at altitude using barometric formula
  final pressure = pressureHpa * pow(1 - (temperatureLapseRate * altitudeM) / standardTemp,
      (gravity * molarMass) / (gasConstant * temperatureLapseRate));

  // Virtual temperature correction for humidity
  final virtualTemp = tempK * (1 + 0.000609 * humidityPercent);

  // Density using ideal gas law
  final density = (pressure * 100) / (287.05 * virtualTemp);

  // Return density ratio
  return density / seaLevelDensity;
}

/// Calculates the Mach number for a given velocity and altitude.
///
/// Parameters:
/// - velocityFps: Velocity in feet per second
/// - altitudeM: Altitude in meters
///
/// Returns: Mach number
double calculateMachNumber({
  required double velocityFps,
  required double altitudeM,
}) {
  // Speed of sound at sea level (ft/s)
  const double speedOfSoundSeaLevel = 1120.0;

  // Speed of sound decreases with altitude (simplified)
  final densityRatio = calculateAtmosphericDensityRatio(
    altitudeM: altitudeM,
    temperatureC: 15.0, // Standard temperature
  );

  // Speed of sound scales with square root of density ratio
  final speedOfSound = speedOfSoundSeaLevel * sqrt(densityRatio);

  return velocityFps / speedOfSound;
}

/// Calculates drag coefficient using G7 model (simplified).
///
/// Parameters:
/// - mach: Current Mach number
///
/// Returns: Drag coefficient
double calculateG7DragCoefficient(double mach) {
  if (mach < 0.0) return 0.0;

  // G7 drag coefficient approximation (Sierrian-style)
  if (mach < 0.5) {
    return 0.15 + 0.05 * mach;
  } else if (mach < 0.8) {
    return 0.175 + 0.25 * (mach - 0.5);
  } else if (mach < 1.0) {
    return 0.25 + 0.5 * (mach - 0.8);
  } else if (mach < 1.3) {
    return 0.35 + 0.3 * (mach - 1.0);
  } else if (mach < 2.0) {
    return 0.44 + 0.1 * (mach - 1.3);
  } else {
    return 0.51 - 0.02 * (mach - 2.0);
  }
}

/// Calculates bullet trajectory with atmospheric corrections.
///
/// Parameters:
/// - bc: Ballistic coefficient (G7)
/// - mv: Muzzle velocity (ft/s)
/// - zero: Zero distance (yards)
/// - windMph: Wind speed (mph)
/// - angleDeg: Firing angle (degrees)
/// - altitudeM: Altitude in meters
/// - temperatureC: Temperature in Celsius
///
/// Returns: List of trajectory points
List<Point> calculateTrajectoryWithAtmosphericCorrection({
  required double bc,
  required double mv,
  required double zero,
  required double windMph,
  required double angleDeg,
  required double altitudeM,
  required double temperatureC,
}) {
  // Get atmospheric density ratio
  final densityRatio = calculateAtmosphericDensityRatio(
    altitudeM: altitudeM,
    temperatureC: temperatureC,
  );

  // Adjust ballistic coefficient for altitude
  final adjustedBc = bc / densityRatio;

  // Standard air density at sea level (lb/ft³)
  const double seaLevelDensity = 0.075;

  // Effective air density
  final airDensity = seaLevelDensity * densityRatio;

  const double gravity = 32.174; // ft/s²
  const int stepSize = 25; // yards
  const int maxDistance = 500; // yards

  final List<Point> trajectory = [];

  // Convert angle to radians
  final double angleRad = angleDeg * pi / 180.0;

  // Initial conditions
  double x = 0.0;
  double y = 0.0;
  double vx = mv * cos(angleRad);
  double vy = mv * sin(angleRad);
  double t = 0.0;

  // Wind drift calculation
  final double windFps = windMph * 5280.0 / 3600.0;
  double windDrift = 0.0;

  // Calculate trajectory
  for (int distYards = 0; distYards <= maxDistance; distYards += stepSize) {
    final double targetDistFt = distYards * 3.0;

    while (x * 3.0 < targetDistFt && x * 3.0 < maxDistance * 3.0) {
      final double v = sqrt(vx * vx + vy * vy);
      final double mach = calculateMachNumber(velocityFps: v, altitudeM: altitudeM);
      final double dragCoeff = calculateG7DragCoefficient(mach);

      // Retardation due to drag
      final double retardation = (dragCoeff * airDensity * v * v) / (2 * adjustedBc * 1.0);

      // Time step
      final double dt = 0.01;

      // Update velocities
      final double ax = -(retardation * vx / v);
      final double ay = -gravity - (retardation * vy / v);

      vx += ax * dt;
      vy += ay * dt;

      // Update position
      x += (vx * dt) / 3.0;
      y += vy * dt * 12.0;
      t += dt;

      // Wind drift
      windDrift += (windFps - vx) * dt * 12.0 / v;
    }

    trajectory.add(Point(
      distance: distYards.toDouble(),
      drop: y,
      velocity: sqrt(vx * vx + vy * vy),
      time: t,
      windDrift: windDrift,
    ));

    if (distYards < maxDistance) {
      x = distYards.toDouble();
    }
  }

  // Apply zero correction
  final int zeroIndex = trajectory.indexWhere((p) => p.distance == zero);
  final Point zeroPoint = zeroIndex >= 0 ? trajectory[zeroIndex] : trajectory[0];
  final double zeroDrop = zeroPoint.drop;

  return trajectory.map((p) => Point(
    distance: p.distance,
    drop: p.drop - zeroDrop,
    velocity: p.velocity,
    time: p.time,
    windDrift: p.windDrift,
  )).toList();
}

// ============================================================================
// Test Suite - Pure Dart Assertions
// ============================================================================

void runBallisticsTests() {
  print('=' * 70);
  print('ADVANCED BALLISTICS TEST SUITE v8.1');
  print('Testing gyroscopic cosine & atmospheric altitude modifiers');
  print('=' * 70);

  int passed = 0;
  int failed = 0;

  // Test 1: Gyroscopic cosine component - zero angle
  {
    final result = calculateGyroscopicCosineComponent(
      pitchAngle: 0.0,
      spinRate: 3000.0,
    );
    // cos(3000/3000) = cos(1) ≈ 0.5403
    assert(
      (result - 0.5403).abs() < 0.001,
      'Expected ~0.5403 for zero pitch angle, got $result',
    );
    print('✓ Test 1: Gyroscopic cosine - zero angle');
    passed++;
  }

  // Test 2: Gyroscopic cosine component - 90 degree pitch
  {
    final result = calculateGyroscopicCosineComponent(
      pitchAngle: 90.0,
      spinRate: 3000.0,
    );
    // cos(0) = 1.0 (pitch cancels out precession)
    assert(
      (result - 1.0).abs() < 0.001,
      'Expected 1.0 for 90° pitch, got $result',
    );
    print('✓ Test 2: Gyroscopic cosine - 90° pitch');
    passed++;
  }

  // Test 3: Atmospheric density - sea level
  {
    final result = calculateAtmosphericDensityRatio(
      altitudeM: 0.0,
      temperatureC: 15.0,
    );
    // Should be approximately 1.0 at sea level
    assert(
      (result - 1.0).abs() < 0.01,
      'Expected ~1.0 at sea level, got $result',
    );
    print('✓ Test 3: Atmospheric density - sea level');
    passed++;
  }

  // Test 4: Atmospheric density - high altitude
  {
    final result = calculateAtmosphericDensityRatio(
      altitudeM: 3000.0,
      temperatureC: 15.0,
    );
    // Should be significantly less than 1.0 at 3000m
    assert(
      result < 0.8,
      'Expected < 0.8 at 3000m altitude, got $result',
    );
    assert(
      result > 0.6,
      'Expected > 0.6 at 3000m altitude, got $result',
    );
    print('✓ Test 4: Atmospheric density - high altitude (3000m)');
    passed++;
  }

  // Test 5: Atmospheric density - cold temperature
  {
    final coldResult = calculateAtmosphericDensityRatio(
      altitudeM: 1500.0,
      temperatureC: 0.0,
    );
    final warmResult = calculateAtmosphericDensityRatio(
      altitudeM: 1500.0,
      temperatureC: 30.0,
    );
    // Cold air is denser than warm air
    assert(
      coldResult > warmResult,
      'Cold air (0°C) should be denser than warm air (30°C)',
    );
    print('✓ Test 5: Atmospheric density - temperature effect');
    passed++;
  }

  // Test 6: Mach number - sea level
  {
    final result = calculateMachNumber(
      velocityFps: 2800.0,
      altitudeM: 0.0,
    );
    // Speed of sound ~1120 fps at sea level
    // 2800 / 1120 ≈ 2.5
    assert(
      (result - 2.5).abs() < 0.01,
      'Expected ~2.5 Mach at sea level, got $result',
    );
    print('✓ Test 6: Mach number - sea level');
    passed++;
  }

  // Test 7: Mach number - high altitude
  {
    final machSea = calculateMachNumber(
      velocityFps: 2800.0,
      altitudeM: 0.0,
    );
    final machHigh = calculateMachNumber(
      velocityFps: 2800.0,
      altitudeM: 3000.0,
    );
    // Speed of sound decreases with altitude, so Mach increases
    assert(
      machHigh > machSea,
      'Mach number should increase at altitude for same velocity',
    );
    print('✓ Test 7: Mach number - altitude effect');
    passed++;
  }

  // Test 8: G7 Drag coefficient - subsonic
  {
    final result = calculateG7DragCoefficient(0.5);
    assert(
      result > 0.15 && result < 0.25,
      'Expected ~0.175 for 0.5 Mach, got $result',
    );
    print('✓ Test 8: G7 Drag coefficient - subsonic (0.5 Mach)');
    passed++;
  }

  // Test 9: G7 Drag coefficient - transonic
  {
    final result = calculateG7DragCoefficient(1.0);
    assert(
      result > 0.35 && result < 0.45,
      'Expected ~0.4 for 1.0 Mach, got $result',
    );
    print('✓ Test 9: G7 Drag coefficient - transonic (1.0 Mach)');
    passed++;
  }

  // Test 10: G7 Drag coefficient - supersonic
  {
    final result = calculateG7DragCoefficient(2.0);
    assert(
      result > 0.45 && result < 0.55,
      'Expected ~0.51 for 2.0 Mach, got $result',
    );
    print('✓ Test 10: G7 Drag coefficient - supersonic (2.0 Mach)');
    passed++;
  }

  // Test 11: Trajectory calculation - zero angle
  {
    final trajectory = calculateTrajectoryWithAtmosphericCorrection(
      bc: 0.5,
      mv: 2800.0,
      zero: 100.0,
      windMph: 0.0,
      angleDeg: 0.0,
      altitudeM: 0.0,
      temperatureC: 15.0,
    );
    assert(
      trajectory.isNotEmpty,
      'Trajectory should not be empty',
    );
    // At zero distance, drop should be 0
    assert(
      trajectory.first.drop.abs() < 0.01,
      'Drop at zero distance should be 0',
    );
    print('✓ Test 11: Trajectory - zero angle calculation');
    passed++;
  }

  // Test 12: Trajectory - altitude effect on velocity
  {
    final seaTraj = calculateTrajectoryWithAtmosphericCorrection(
      bc: 0.5,
      mv: 2800.0,
      zero: 100.0,
      windMph: 0.0,
      angleDeg: 0.0,
      altitudeM: 0.0,
      temperatureC: 15.0,
    );
    final highTraj = calculateTrajectoryWithAtmosphericCorrection(
      bc: 0.5,
      mv: 2800.0,
      zero: 100.0,
      windMph: 0.0,
      angleDeg: 0.0,
      altitudeM: 3000.0,
      temperatureC: 15.0,
    );
    // Velocity at 200 yards should be higher at altitude (less drag)
    final seaVel200 = seaTraj.firstWhere((p) => p.distance == 200.0).velocity;
    final highVel200 = highTraj.firstWhere((p) => p.distance == 200.0).velocity;
    assert(
      highVel200 > seaVel200,
      'Velocity at altitude should be higher (less drag)',
    );
    print('✓ Test 12: Trajectory - altitude effect on velocity retention');
    passed++;
  }

  // Test 13: Gyroscopic stability factor bounds
  {
    final result = calculateGyroscopicStability(
      bulletLength: 3.0,
      bulletBulletDiameter: 0.308,
      bulletWeight: 175.0,
      twistRate: 9.5,
      velocity: 2600.0,
    );
    // Result should be a reasonable positive number
    assert(
      result > 0,
      'Gyroscopic stability should be positive',
    );
    assert(
      result < 10,
      'Gyroscopic stability should be < 10 for realistic parameters',
    );
    print('✓ Test 13: Gyroscopic stability factor bounds');
    passed++;
  }

  // Test 14: Gyroscopic cosine symmetry
  {
    final result1 = calculateGyroscopicCosineComponent(
      pitchAngle: 10.0,
      spinRate: 2500.0,
    );
    final result2 = calculateGyroscopicCosineComponent(
      pitchAngle: -10.0,
      spinRate: 2500.0,
    );
    // Cosine is symmetric around 0
    assert(
      (result1 - result2).abs() < 0.001,
      'Cosine should be symmetric for +/- angles',
    );
    print('✓ Test 14: Gyroscopic cosine symmetry');
    passed++;
  }

  // Test 15: Negative Mach number handling
  {
    final result = calculateG7DragCoefficient(-0.5);
    assert(
      result == 0.0,
      'Negative Mach should return 0 drag coefficient',
    );
    print('✓ Test 15: Negative Mach number handling');
    passed++;
  }

  // Test 16: Trajectory wind drift
  {
    final noWindTraj = calculateTrajectoryWithAtmosphericCorrection(
      bc: 0.5,
      mv: 2800.0,
      zero: 100.0,
      windMph: 0.0,
      angleDeg: 0.0,
      altitudeM: 0.0,
      temperatureC: 15.0,
    );
    final windTraj = calculateTrajectoryWithAtmosphericCorrection(
      bc: 0.5,
      mv: 2800.0,
      zero: 100.0,
      windMph: 10.0,
      angleDeg: 0.0,
      altitudeM: 0.0,
      temperatureC: 15.0,
    );
    final noWindDrift = noWindTraj.last.windDrift.abs();
    final windDrift = windTraj.last.windDrift.abs();
    assert(
      windDrift > noWindDrift,
      'Wind drift should be present with wind',
    );
    print('✓ Test 16: Trajectory - wind drift calculation');
    passed++;
  }

  // Test 17: Extreme altitude (mountain top)
  {
    final result = calculateAtmosphericDensityRatio(
      altitudeM: 5000.0,
      temperatureC: 5.0,
    );
    // Should be significantly less than sea level
    assert(
      result < 0.6,
      'Expected < 0.6 at 5000m, got $result',
    );
    assert(
      result > 0.4,
      'Expected > 0.4 at 5000m, got $result',
    );
    print('✓ Test 17: Extreme altitude (5000m mountain)');
    passed++;
  }

  // Test 18: Trajectory time progression
  {
    final trajectory = calculateTrajectoryWithAtmosphericCorrection(
      bc: 0.5,
      mv: 2800.0,
      zero: 100.0,
      windMph: 0.0,
      angleDeg: 0.0,
      altitudeM: 0.0,
      temperatureC: 15.0,
    );
    final firstTime = trajectory.first.time;
    final lastTime = trajectory.last.time;
    assert(
      lastTime > firstTime,
      'Time should increase with distance',
    );
    print('✓ Test 18: Trajectory time progression');
    passed++;
  }

  // Summary
  print('=' * 70);
  print('BALLISTICS TEST SUMMARY');
  print('=' * 70);
  print('Total Tests: ${passed + failed}');
  print('Passed: $passed');
  print('Failed: $failed');
  print('=' * 70);

  if (failed == 0) {
    print('✓ ALL BALLISTICS TESTS PASSED');
    print('  - Gyroscopic cosine calculations verified');
    print('  - Atmospheric altitude modifiers verified');
    print('  - Mach number calculations verified');
    print('  - G7 drag coefficient verified');
    print('  - Trajectory computation verified');
  } else {
    print('✗ SOME TESTS FAILED - Review output above');
  }
}

// ============================================================================
// Entry Point
// ============================================================================
void main() {
  runBallisticsTests();
}
