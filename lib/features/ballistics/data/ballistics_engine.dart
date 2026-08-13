import 'dart:math' as math;

/// Selected standard drag model (drag function) used to compute the
/// retarding force on the bullet. [DragModel.g1] is the legacy Ingalls G1
/// curve (most published BCs are G1-referenced); [DragModel.g7] is the
/// low-drag boat-tail G7 curve used for VLD / long-range match bullets.
enum DragModel {
  /// G1 (Ingalls) — flat-base reference projectile. The default for most
  /// factory-published ballistic coefficients.
  g1,
  /// G7 — long boat-tail / VLD reference projectile. Use with G7-referenced
  /// BCs for materially better long-range predictions.
  g7,
}

/// Atmospheric / environmental conditions used to compute air density and
/// density altitude via the ICAO standard atmosphere (with humidity).
class Atmosphere {
  /// Ambient temperature in °C.
  final double temperatureCelsius;

  /// Absolute station barometric pressure in hPa (millibars).
  final double pressureHpa;

  /// Relative humidity (0–100 %).
  final double relativeHumidity;

  /// Shooting-site elevation above sea level, in metres.
  final double altitudeMeters;

  const Atmosphere({
    required this.temperatureCelsius,
    required this.pressureHpa,
    required this.relativeHumidity,
    required this.altitudeMeters,
  });

  /// ICAO standard atmosphere at sea level (15 °C, 1013.25 hPa, 0 % RH, 0 m).
  static const Atmosphere standardSeaLevel = Atmosphere(
    temperatureCelsius: 15.0,
    pressureHpa: 1013.25,
    relativeHumidity: 0.0,
    altitudeMeters: 0.0,
  );
}

/// A single row in the trajectory table output.
class TrajectoryPoint {
  /// Slant range to the target, in metres.
  final double rangeMeters;

  /// Bullet drop relative to the zero line, in centimetres
  /// (positive = below the line of sight).
  final double dropCm;

  /// Lateral wind drift, in centimetres (positive = downwind direction).
  final double windageCm;

  /// Remaining bullet velocity at this range, in m/s.
  final double velocityMs;

  /// Remaining kinetic energy at this range, in Joules
  /// (E = ½·m·v², m derived from [BulletProfile.bulletWeightGrains]).
  final double energyJoules;

  /// Time of flight to this range, in seconds.
  final double timeOfFlightSeconds;

  const TrajectoryPoint({
    required this.rangeMeters,
    required this.dropCm,
    required this.windageCm,
    required this.velocityMs,
    required this.energyJoules,
    required this.timeOfFlightSeconds,
  });
}

/// Static bullet/load parameters consumed by the trajectory integrator.
class BulletProfile {
  /// Muzzle velocity in metres per second.
  final double muzzleVelocityMs;

  /// Ballistic coefficient referenced against the selected [DragModel].
  final double ballisticCoefficient;

  /// Bullet weight in grains.
  final double bulletWeightGrains;

  /// Scope height over bore, in metres.
  final double scopeHeightMeters;

  /// Zero range (where drop = 0 relative to LOS), in metres.
  final double zeroDistanceMeters;

  /// Crosswind speed in m/s.
  final double crossWindMps;

  /// Barrel pitch (inclination) angle, in degrees.
  final double pitchAngleDegrees;

  /// Powder-temperature coefficient: fps change per °F of powder temperature.
  /// Typical smokeless powder ≈ 1.5 fps/°F.
  final double powderTempCoefficientFpsPerF;

  /// Powder temperature at firing time, in °C.
  final double powderTempCelsius;

  const BulletProfile({
    required this.muzzleVelocityMs,
    required this.ballisticCoefficient,
    required this.bulletWeightGrains,
    this.scopeHeightMeters = 0.045, // ~1.75"
    this.zeroDistanceMeters = 100.0,
    this.crossWindMps = 0.0,
    this.pitchAngleDegrees = 0.0,
    this.powderTempCoefficientFpsPerF = 1.5,
    this.powderTempCelsius = 15.0,
  });
}

/// Pure-dart ballistics engine: ICAO atmospheric density, G1/G7 drag models,
/// powder-temperature muzzle-velocity correction, and numerical point-mass
/// trajectory integration yielding drop / drift / velocity / energy.
///
/// All formulas follow the standard public-domain ballistics literature
/// (ICAO atmosphere, Tetens vapour-pressure, Mayevski–Ingalls G1/G7 drag
/// functions). No external dependencies.
class BallisticsEngine {
  BallisticsEngine._();
  static final BallisticsEngine instance = BallisticsEngine._();

  // ---- Physical constants (SI unless noted) ----
  static const double _g = 9.80665; // gravity, m/s²
  static const double _gasConstantDryAir = 8.31446; // J/(mol·K)
  static const double _molarMassDryAir = 0.0289644; // kg/mol
  static const double _molarMassWaterVapour = 0.018016; // kg/mol
  static const double _hpaToPa = 100.0;
  static const double _grainsPerPound = 7000.0;
  static const double _poundsPerKg = 2.2046226218;
  static const double _fpsPerMps = 3.28084;
  static const double _celciusToFahrenheitK = 9.0 / 5.0;

  // ICAO standard-atmosphere references.
  static const double _icaoTempC = 15.0;
  static const double _icaoTempK = 288.15;
  static const double _icaoLapseRate = 0.0065; // K/m
  static const double _icaoSeaLevelDensity = 1.225; // kg/m³

  /// Air density (kg/m³) for the given atmosphere, using the ICAO model with
  /// a humidity correction (Tetens vapour pressure).
  ///
  /// ρ = (P_d·M_d + P_v·M_v) / (R·T)
  /// where P_d = dry-air pressure, P_v = water-vapour partial pressure.
  double airDensity(Atmosphere a) {
    final tempK = a.temperatureCelsius + 273.15;
    // Tetens: saturation vapour pressure (hPa) over water.
    final satVapourHpa = 6.1078 *
        math.pow(
            10.0,
            7.5 * a.temperatureCelsius / (a.temperatureCelsius + 237.3));
    final rh = a.relativeHumidity.clamp(0.0, 100.0) / 100.0;
    final vapourHpa = satVapourHpa * rh;
    final dryAirHpa = a.pressureHpa - vapourHpa;

    final paDry = dryAirHpa * _hpaToPa;
    final paVapour = vapourHpa * _hpaToPa;
    return (paDry * _molarMassDryAir + paVapour * _molarMassWaterVapour) /
        (_gasConstantDryAir * tempK);
  }

  /// Air-density ratio relative to the ICAO sea-level standard (1.0 = standard
  /// sea-level density). This is the multiplier used to scale drag.
  double airDensityRatio(Atmosphere a) {
    final rho = airDensity(a);
    return (rho / _icaoSeaLevelDensity).clamp(0.1, 2.0);
  }

  /// Density altitude (metres) — the altitude in the ICAO standard atmosphere
  /// that has the same air density as the given (non-standard) atmosphere.
  ///
  /// DA ≈ altitude + (T_std - T_actual) / lapseRate, refined by the density
  /// ratio. Uses the standard ISA pressure-altitude + temperature offset form.
  double densityAltitude(Atmosphere a) {
    // Standard temperature at the station altitude.
    final standardTempK =
        _icaoTempK - _icaoLapseRate * a.altitudeMeters;
    final actualTempK = a.temperatureCelsius + 273.15;
    // Temperature-offset density-altitude correction.
    final tempOffsetMeters =
        (actualTempK - standardTempK) / _icaoLapseRate;
    // Add a humidity contribution: moist air is less dense → higher DA.
    // Approximate the humidity density altitude bump via vapour pressure.
    final satVapourHpa = 6.1078 *
        math.pow(
            10.0,
            7.5 * a.temperatureCelsius / (a.temperatureCelsius + 237.3));
    final rh = a.relativeHumidity.clamp(0.0, 100.0) / 100.0;
    final vapourHpa = satVapourHpa * rh;
    // ~0.12 m DA per hPa of vapour pressure (empirical ICAO refinement).
    final humidityDaMeters = vapourHpa * 0.12 * 8.0;
    return a.altitudeMeters + tempOffsetMeters + humidityDaMeters;
  }

  /// Adjusted muzzle velocity accounting for powder temperature deviation
  /// from the reference (standard) temperature.
  ///
  /// ΔV = tempCoefficient · ΔT, where ΔT is in °F and the coefficient is in
  /// fps/°F. The result is returned in the same unit as [mvMs] (m/s).
  double muzzleVelocityForPowderTemp({
    required double muzzleVelocityMs,
    required double powderTempCelsius,
    required double tempCoefficientFpsPerF,
    double referenceTempCelsius = _icaoTempC,
  }) {
    final deltaC = powderTempCelsius - referenceTempCelsius;
    final deltaF = deltaC * _celciusToFahrenheitK;
    final deltaFps = tempCoefficientFpsPerF * deltaF;
    final deltaMs = deltaFps / _fpsPerMps;
    return (muzzleVelocityMs + deltaMs).clamp(0.0, 5000.0);
  }

  /// Retardation (drag deceleration, m/s²) at the given Mach number and
  /// velocity, for the selected drag model, scaled by [bc] and the air-density
  /// ratio. Uses the Mayevski–Ingalls G1 / G7 drag functions.
  ///
  /// a_drag = -densityRatio · G(M) · v² / BC  (G is the published drag
  /// function in 1/ft units; the BC carries the dimensional normalization).
  double _dragDeceleration({
    required DragModel dragModel,
    required double mach,
    required double velocityMs,
    required double bc,
    required double densityRatio,
  }) {
    final g = _dragFunctionValue(dragModel, mach);
    if (g <= 0 || bc <= 0) return 0.0;
    // Convert velocity to ft/s (the G tables are imperial) then back.
    final vFps = velocityMs * _fpsPerMps;
    // Published Ingalls/McCoy G values are tabulated ×1e4; retardation in
    // ft/s² = (G·1e-4)·v² / BC, with v in ft/s. The 1e-4 factor restores the
    // physical 1/ft units of the drag function.
    final aFps = 1e-4 * densityRatio * g * vFps * vFps / bc;
    return aFps / _fpsPerMps; // back to m/s²
  }

  /// Interpolated G1 / G7 drag-function value G(Mach).
  double _dragFunctionValue(DragModel model, double mach) {
    final table = model == DragModel.g7 ? _g7Table : _g1Table;
    if (table.isEmpty) return 0.0;
    if (mach <= table.first.mach) return table.first.value;
    if (mach >= table.last.mach) return table.last.value;
    for (int i = 0; i < table.length - 1; i++) {
      final lo = table[i];
      final hi = table[i + 1];
      if (mach >= lo.mach && mach <= hi.mach) {
        final t = (mach - lo.mach) / (hi.mach - lo.mach);
        return lo.value + t * (hi.value - lo.value);
      }
    }
    return table.last.value;
  }

  /// Speed of sound in air (m/s) for the given temperature, used to derive
  /// the Mach number for the drag tables.
  double speedOfSound(double temperatureCelsius) =>
      331.3 * math.sqrt(1.0 + temperatureCelsius / 273.15);

  /// Generates a full trajectory table (dope card) from [startMeters] to
  /// [endMeters] in [stepMeters] increments.
  ///
  /// Integrates the point-mass equations of motion with a fixed time step,
  /// applying the selected drag model and atmospheric density. Returns one
  /// [TrajectoryPoint] per requested range, plus the muzzle (range 0) row.
  List<TrajectoryPoint> trajectoryTable({
    required BulletProfile bullet,
    required Atmosphere atmosphere,
    DragModel dragModel = DragModel.g1,
    double startMeters = 50.0,
    double endMeters = 1000.0,
    double stepMeters = 50.0,
  }) {
    if (bullet.muzzleVelocityMs <= 0 || bullet.ballisticCoefficient <= 0) {
      return _emptyTable(startMeters, endMeters, stepMeters);
    }

    final densityRatio = airDensityRatio(atmosphere);
    final speedSound = speedOfSound(atmosphere.temperatureCelsius);
    final bc = bullet.ballisticCoefficient.clamp(0.05, 2.0);

    // Powder-temperature-corrected muzzle velocity.
    final mvMs = muzzleVelocityForPowderTemp(
      muzzleVelocityMs: bullet.muzzleVelocityMs,
      powderTempCelsius: bullet.powderTempCelsius,
      tempCoefficientFpsPerF: bullet.powderTempCoefficientFpsPerF,
    );

    final massKg = _grainsToKg(bullet.bulletWeightGrains);
    final pitchRad = bullet.pitchAngleDegrees * math.pi / 180.0;
    final cosPitch = math.cos(pitchRad);
    // Effective gravity along the bore line (incline correction).
    final gEff = _g * cosPitch;

    // Bore elevation required to zero the rifle at [zeroDistanceMeters].
    // The bullet leaves the bore at y=0 and must arrive at y=0 (on the LOS)
    // at the zero range, so the gravity drop over the (drag-corrected) time
    // of flight must be cancelled: vy = 0.5·g·t_zero. This elevation is folded
    // into the initial vertical velocity on top of any incline pitch.
    final tZero = _estimatedTimeOfFlight(
        bullet.zeroDistanceMeters, mvMs, bc, densityRatio, speedSound, dragModel);
    final boreElevRad = gEff * tZero / (2.0 * mvMs);

    // Integrate the trajectory with a small time step, sampling at the
    // requested range buckets. State: (x along-LOS horizontal, y vertical).
    double x = 0.0; // horizontal distance travelled (m)
    double y = 0.0; // vertical position (m), positive up
    double vx = mvMs * cosPitch; // horizontal velocity
    double vy = mvMs * (math.sin(pitchRad) + boreElevRad * cosPitch);
    double t = 0.0;
    double windage = 0.0; // lateral drift (m)

    const dt = 0.0005; // 0.5 ms integration step

    final buckets = <double>[];
    for (double r = startMeters; r <= endMeters + 1e-6; r += stepMeters) {
      buckets.add(r);
    }
    final out = <TrajectoryPoint>[];
    // Muzzle row.
    out.add(TrajectoryPoint(
      rangeMeters: 0,
      dropCm: 0,
      windageCm: 0,
      velocityMs: mvMs,
      energyJoules: 0.5 * massKg * mvMs * mvMs,
      timeOfFlightSeconds: 0,
    ));

    while (x < endMeters && buckets.isNotEmpty) {
      final v = math.sqrt(vx * vx + vy * vy);
      final mach = v / speedSound;
      final aDrag = _dragDeceleration(
        dragModel: dragModel,
        mach: mach,
        velocityMs: v,
        bc: bc,
        densityRatio: densityRatio,
      );
      // Drag opposes velocity; decompose along velocity vector.
      final dragAx = v > 0 ? -aDrag * vx / v : 0.0;
      final dragAy = v > 0 ? -aDrag * vy / v : 0.0;

      // Crosswind drift: lateral velocity approaches wind speed; drift = wind
      // component × time-of-flight (lateral drag is small vs axial).
      final lateralVx = bullet.crossWindMps;
      windage += lateralVx * dt;

      // Vertical: gravity acts down (effective along the bore line).
      final ax = dragAx;
      final ay = dragAy - gEff;

      vx += ax * dt;
      vy += ay * dt;
      // Velocity floor: drag must not reverse the bullet's forward motion.
      if (vx < 0.1) vx = 0.1;
      x += vx * dt;
      y += vy * dt;
      t += dt;

      // Sample at the next bucket boundary (interpolate for precision).
      while (buckets.isNotEmpty && x >= buckets.first) {
        final targetR = buckets.removeAt(0);
        // Fractional interpolation of the last step toward the bucket range.
        final prevX = x - vx * dt;
        final frac = (targetR - prevX) / (x - prevX + 1e-9);
        final sVy = vy;
        final sV = math.sqrt(vx * vx + sVy * sVy);
        final sX = targetR;
        final sY = y - vy * dt + vy * dt * frac;
        final sT = t - dt + dt * frac;
        final sWind = windage - lateralVx * dt + lateralVx * dt * frac;

        // Drop relative to the line of sight, sighted to zero at the zero
        // range (the bore-elevation / LOS angle is solved from that zero).
        final dropRelLosM = _dropRelativeToLos(
          sX,
          sY,
          bullet.zeroDistanceMeters,
          bullet.scopeHeightMeters,
        );
        final dropCm = dropRelLosM * 100.0;
        out.add(TrajectoryPoint(
          rangeMeters: sX,
          dropCm: double.parse(dropCm.toStringAsFixed(2)),
          windageCm: double.parse((sWind * 100.0).toStringAsFixed(2)),
          velocityMs: double.parse(sV.toStringAsFixed(1)),
          energyJoules:
              double.parse((0.5 * massKg * sV * sV).toStringAsFixed(1)),
          timeOfFlightSeconds: double.parse(sT.toStringAsFixed(3)),
        ));
      }
    }

    // Ensure the requested end bucket is present even if integration stopped
    // slightly short (very low BC / extreme range).
    while (buckets.isNotEmpty) {
      final r = buckets.removeAt(0);
      final last = out.last;
      out.add(TrajectoryPoint(
        rangeMeters: r,
        dropCm: last.dropCm,
        windageCm: last.windageCm,
        velocityMs: last.velocityMs,
        energyJoules: last.energyJoules,
        timeOfFlightSeconds: last.timeOfFlightSeconds,
      ));
    }

    return out;
  }

  /// Drop (metres) relative to the line of sight at range [x].
  ///
  /// The line of sight is the straight sight line from the scope (at
  /// [scopeHeightMeters] above the bore) through the zero point at
  /// [zeroDistanceMeters]. It therefore has height
  /// `scopeHeight·(1 − x/zeroRange)` at range [x]. The bullet's integrated
  /// vertical position is [y]; drop below the LOS is `losHeight − y`.
  double _dropRelativeToLos(
    double x,
    double y,
    double zeroDistanceMeters,
    double scopeHeightMeters,
  ) {
    if (zeroDistanceMeters <= 0) return y;
    final losHeightAtX = scopeHeightMeters * (1.0 - x / zeroDistanceMeters);
    return losHeightAtX - y;
  }

  /// Estimated time of flight to a range under exponential drag decay.
  double _estimatedTimeOfFlight(
    double range,
    double mvMs,
    double bc,
    double densityRatio,
    double speedSound,
    DragModel dragModel,
  ) {
    // Average drag-corrected velocity via a simple exponential decay model.
    final decay = bc * 1500.0 / densityRatio;
    final vAtRange = mvMs * math.exp(-range / decay);
    final vAvg = (mvMs + vAtRange) / 2.0;
    return vAvg > 0 ? range / vAvg : range / mvMs;
  }

  List<TrajectoryPoint> _emptyTable(double start, double end, double step) {
    final out = <TrajectoryPoint>[];
    for (double r = start; r <= end + 1e-6; r += step) {
      out.add(TrajectoryPoint(
        rangeMeters: r,
        dropCm: 0,
        windageCm: 0,
        velocityMs: 0,
        energyJoules: 0,
        timeOfFlightSeconds: 0,
      ));
    }
    return out;
  }

  double _grainsToKg(double grains) =>
      grains / _grainsPerPound / _poundsPerKg;

  // ---- Standard drag-function tables (Mach, G) ----
  //
  // These are the classic Mayevski–Ingalls G1 (flat-base) and McCoy G7
  // (boat-tail) drag functions, expressed as retardation-per-BC values in
  // imperial units (ft/s² per (ft/s)² per 1/BC). Values are condensed from
  // the published standard tables at representative Mach bands.
  static const List<_DragEntry> _g1Table = [
    _DragEntry(0.00, 0.0000),
    _DragEntry(0.50, 0.0190),
    _DragEntry(0.70, 0.0225),
    _DragEntry(0.80, 0.0260),
    _DragEntry(0.85, 0.0300),
    _DragEntry(0.90, 0.0450),
    _DragEntry(0.95, 0.1050),
    _DragEntry(1.00, 0.1600),
    _DragEntry(1.05, 0.1800),
    _DragEntry(1.10, 0.1680),
    _DragEntry(1.20, 0.1400),
    _DragEntry(1.30, 0.1180),
    _DragEntry(1.40, 0.0990),
    _DragEntry(1.50, 0.0840),
    _DragEntry(1.60, 0.0730),
    _DragEntry(1.80, 0.0580),
    _DragEntry(2.00, 0.0470),
    _DragEntry(2.50, 0.0340),
    _DragEntry(3.00, 0.0260),
    _DragEntry(3.50, 0.0200),
    _DragEntry(4.00, 0.0160),
    _DragEntry(5.00, 0.0120),
  ];

  static const List<_DragEntry> _g7Table = [
    _DragEntry(0.00, 0.0000),
    _DragEntry(0.50, 0.0110),
    _DragEntry(0.70, 0.0140),
    _DragEntry(0.80, 0.0160),
    _DragEntry(0.85, 0.0180),
    _DragEntry(0.90, 0.0240),
    _DragEntry(0.95, 0.0600),
    _DragEntry(1.00, 0.0920),
    _DragEntry(1.05, 0.0980),
    _DragEntry(1.10, 0.0920),
    _DragEntry(1.20, 0.0780),
    _DragEntry(1.30, 0.0660),
    _DragEntry(1.40, 0.0560),
    _DragEntry(1.50, 0.0480),
    _DragEntry(1.60, 0.0420),
    _DragEntry(1.80, 0.0330),
    _DragEntry(2.00, 0.0270),
    _DragEntry(2.50, 0.0190),
    _DragEntry(3.00, 0.0140),
    _DragEntry(3.50, 0.0110),
    _DragEntry(4.00, 0.0090),
    _DragEntry(5.00, 0.0070),
  ];
}

class _DragEntry {
  final double mach;
  final double value;
  const _DragEntry(this.mach, this.value);
}
