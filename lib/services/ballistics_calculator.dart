import 'dart:math';

class Point {
  final double distance;
  final double drop;
  final double velocity;
  final double time;
  final double windDrift;

  Point({
    required this.distance,
    required this.drop,
    required this.velocity,
    required this.time,
    required this.windDrift,
  });
}

/// Calculates bullet trajectory using standard G1 ballistic equations.
///
/// Parameters:
/// - bc: Ballistic coefficient (G1)
/// - mv: Muzzle velocity (ft/s)
/// - zero: Zero distance (yards)
/// - windMph: Wind speed (mph)
/// - angleDeg: Firing angle (degrees, positive for uphill)
///
/// Returns: List of trajectory points at 25-yard intervals
List<Point> calcTrajectory({
  required double bc,
  required double mv,
  required double zero,
  required double windMph,
  required double angleDeg,
}) {
  // Input validation
  if (bc <= 0) {
    throw ArgumentError('Ballistic coefficient must be greater than 0');
  }
  if (mv < 500 || mv > 4000) {
    throw ArgumentError('Muzzle velocity must be between 500 and 4000 ft/s');
  }
  if (zero < 25 || zero > 300) {
    throw ArgumentError('Zero distance must be between 25 and 300 yards');
  }

  const double gravity = 32.174; // ft/s²
  const double airDensity = 0.075; // lb/ft³ at sea level
  const int stepSize = 25; // yards
  const int maxDistance = 1000; // yards

  List<Point> trajectory = [];

  // Convert angle to radians
  final double angleRad = angleDeg * pi / 180.0;

  // Initial conditions
  double x = 0.0; // horizontal distance (yards)
  double y = 0.0; // vertical position (inches relative to line of sight)
  double vx = mv * cos(angleRad); // horizontal velocity (ft/s)
  double vy = mv * sin(angleRad); // vertical velocity (ft/s)
  double t = 0.0; // time (s)

  // Wind drift calculation
  final double windFps = windMph * 5280.0 / 3600.0; // Convert mph to ft/s
  double windDrift = 0.0;

  // Calculate trajectory
  for (int distYards = 0; distYards <= maxDistance; distYards += stepSize) {
    // Convert distance to feet
    final double targetDistFt = distYards * 3.0;

    // Integrate until we reach the target distance
    while (x * 3.0 < targetDistFt && x * 3.0 < maxDistance * 3.0) {
      final double v = sqrt(vx * vx + vy * vy);
      final double mach = v / 1120.0; // Speed of sound ~1120 ft/s

      // G1 drag coefficient function (simplified)
      final double dragCoeff = _getG1DragCoefficient(mach);

      // Retardation (deceleration) due to drag
      final double retardation =
          (dragCoeff * airDensity * v * v) / (2 * bc * 1.0);

      // Update velocities (Euler integration)
      final double dt = 0.01; // Time step (s)
      final double ax = -(retardation * vx / v);
      final double ay = -gravity - (retardation * vy / v);

      vx += ax * dt;
      vy += ay * dt;

      // Update position
      final double dx = vx * dt; // ft
      final double dy = vy * dt; // ft

      x += dx / 3.0; // Convert ft to yards
      y += dy * 12.0; // Convert ft to inches
      t += dt;

      // Wind drift accumulation (simplified)
      windDrift += (windFps - vx) * dt * 12.0 * (1.0 / v); // inches
    }

    // Calculate drop relative to zero distance
    double drop = y;

    trajectory.add(
      Point(
        distance: distYards.toDouble(),
        drop: drop,
        velocity: sqrt(vx * vx + vy * vy),
        time: t,
        windDrift: windDrift,
      ),
    );

    // Reset for next iteration (simplified approach)
    // In a full implementation, you'd continue from current state
    if (distYards < maxDistance) {
      x = distYards.toDouble();
    }
  }

  // Apply zero correction (shift all points so zero distance has 0 drop)
  final int zeroIndex = trajectory.indexWhere((p) => p.distance == zero);
  final Point zeroPoint = zeroIndex >= 0
      ? trajectory[zeroIndex]
      : trajectory[0];
  final double zeroDrop = zeroPoint.drop;

  return trajectory
      .map(
        (p) => Point(
          distance: p.distance,
          drop: p.drop - zeroDrop,
          velocity: p.velocity,
          time: p.time,
          windDrift: p.windDrift,
        ),
      )
      .toList();
}

/// G1 drag coefficient as a function of Mach number
/// Simplified approximation of the G1 standard drag function
double _getG1DragCoefficient(double mach) {
  if (mach < 0.0) return 0.0;

  // G1 drag coefficient approximation (simplified)
  // Based on standard G1 drag curve
  if (mach < 0.7) {
    return 0.2 + 0.1 * mach;
  } else if (mach < 1.0) {
    return 0.27 + 0.3 * (mach - 0.7);
  } else if (mach < 1.2) {
    return 0.36 + 0.5 * (mach - 1.0);
  } else if (mach < 1.5) {
    return 0.46 + 0.2 * (mach - 1.2);
  } else if (mach < 2.0) {
    return 0.52 + 0.1 * (mach - 1.5);
  } else {
    return 0.57 - 0.05 * (mach - 2.0);
  }
}

/// Returns formatted point data for a specific distance.
///
/// Parameters:
/// - bc: Ballistic coefficient (G1)
/// - mv: Muzzle velocity (ft/s)
/// - zero: Zero distance (yards)
/// - windMph: Wind speed (mph)
/// - angleDeg: Firing angle (degrees)
/// - distance: Target distance (yards)
///
/// Returns: Formatted string "Drop: x.xx in, Drift: x.xx in, Vel: xxxx fps"
String getPointData({
  required double bc,
  required double mv,
  required double zero,
  required double windMph,
  required double angleDeg,
  required double distance,
}) {
  final trajectory = calcTrajectory(
    bc: bc,
    mv: mv,
    zero: zero,
    windMph: windMph,
    angleDeg: angleDeg,
  );

  // Find the point closest to the requested distance
  Point? targetPoint;
  double minDiff = double.infinity;

  for (final point in trajectory) {
    final diff = (point.distance - distance).abs();
    if (diff < minDiff) {
      minDiff = diff;
      targetPoint = point;
    }
  }

  if (targetPoint == null) {
    throw ArgumentError(
      'Could not find trajectory data for distance $distance yards',
    );
  }

  return 'Drop: ${targetPoint.drop.abs().toStringAsFixed(2)} in, Drift: ${targetPoint.windDrift.abs().toStringAsFixed(2)} in, Vel: ${targetPoint.velocity.toStringAsFixed(0)} fps';
}
