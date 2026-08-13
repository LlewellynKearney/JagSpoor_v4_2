import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/ballistics/data/ballistics_engine.dart';

void main() {
  final eng = BallisticsEngine.instance;

  group('Atmosphere — ICAO air density', () {
    test('standard sea-level density ≈ 1.225 kg/m³', () {
      final rho = eng.airDensity(Atmosphere.standardSeaLevel);
      expect(rho, closeTo(1.225, 0.01));
    });

    test('density ratio at sea level standard ≈ 1.0', () {
      expect(eng.airDensityRatio(Atmosphere.standardSeaLevel),
          closeTo(1.0, 0.01));
    });

    test('higher altitude (lower station pressure) lowers air density', () {
      final seaLevel = eng.airDensityRatio(Atmosphere.standardSeaLevel);
      // High-altitude station: pressure drops with altitude (barometric), so a
      // 3000 m site reads ~700 hPa and thin air.
      final highAlt = eng.airDensityRatio(const Atmosphere(
        temperatureCelsius: 15.0,
        pressureHpa: 700.0,
        relativeHumidity: 0.0,
        altitudeMeters: 3000.0,
      ));
      expect(highAlt, lessThan(seaLevel));
      expect(highAlt, lessThan(0.75));
    });

    test('humidity reduces air density (moist air is lighter)', () {
      final dry = eng.airDensity(const Atmosphere(
        temperatureCelsius: 30.0,
        pressureHpa: 1013.25,
        relativeHumidity: 0.0,
        altitudeMeters: 0.0,
      ));
      final humid = eng.airDensity(const Atmosphere(
        temperatureCelsius: 30.0,
        pressureHpa: 1013.25,
        relativeHumidity: 100.0,
        altitudeMeters: 0.0,
      ));
      expect(humid, lessThan(dry));
    });

    test('lower pressure reduces air density', () {
      final std = eng.airDensity(const Atmosphere(
        temperatureCelsius: 15.0,
        pressureHpa: 1013.25,
        relativeHumidity: 0.0,
        altitudeMeters: 0.0,
      ));
      final lowP = eng.airDensity(const Atmosphere(
        temperatureCelsius: 15.0,
        pressureHpa: 900.0,
        relativeHumidity: 0.0,
        altitudeMeters: 0.0,
      ));
      expect(lowP, lessThan(std));
    });
  });

  group('Density altitude', () {
    test('standard sea-level density altitude ≈ 0 m', () {
      expect(eng.densityAltitude(Atmosphere.standardSeaLevel),
          closeTo(0.0, 50.0));
    });

    test('hot day raises density altitude above station altitude', () {
      final da = eng.densityAltitude(const Atmosphere(
        temperatureCelsius: 40.0,
        pressureHpa: 1013.25,
        relativeHumidity: 0.0,
        altitudeMeters: 0.0,
      ));
      expect(da, greaterThan(1000.0));
    });

    test('cold day lowers density altitude below station altitude', () {
      final da = eng.densityAltitude(const Atmosphere(
        temperatureCelsius: -20.0,
        pressureHpa: 1013.25,
        relativeHumidity: 0.0,
        altitudeMeters: 0.0,
      ));
      expect(da, lessThan(0.0));
    });

    test('high station altitude yields high density altitude', () {
      final da = eng.densityAltitude(const Atmosphere(
        temperatureCelsius: 15.0,
        pressureHpa: 1013.25,
        relativeHumidity: 0.0,
        altitudeMeters: 1500.0,
      ));
      expect(da, greaterThan(1000.0));
    });
  });

  group('Powder-temperature muzzle velocity correction', () {
    test('reference temp leaves muzzle velocity unchanged', () {
      final mv = eng.muzzleVelocityForPowderTemp(
        muzzleVelocityMs: 800,
        powderTempCelsius: 15.0,
        tempCoefficientFpsPerF: 1.5,
        referenceTempCelsius: 15.0,
      );
      expect(mv, closeTo(800.0, 1e-6));
    });

    test('hot powder raises muzzle velocity', () {
      final cold = eng.muzzleVelocityForPowderTemp(
        muzzleVelocityMs: 800,
        powderTempCelsius: 0.0,
        tempCoefficientFpsPerF: 1.5,
      );
      final hot = eng.muzzleVelocityForPowderTemp(
        muzzleVelocityMs: 800,
        powderTempCelsius: 40.0,
        tempCoefficientFpsPerF: 1.5,
      );
      expect(hot, greaterThan(cold));
      // 40°C delta × 1.8 °F/°C = 72°F × 1.5 fps/°F = 108 fps ≈ 32.9 m/s.
      expect(hot - cold, closeTo(32.9, 0.5));
    });
  });

  group('Trajectory table', () {
    final bullet = BulletProfile(
      muzzleVelocityMs: 820,
      ballisticCoefficient: 0.5,
      bulletWeightGrains: 175,
      zeroDistanceMeters: 100,
      scopeHeightMeters: 0.045,
    );

    test('produces a row per requested range step', () {
      final table = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        startMeters: 100,
        endMeters: 500,
        stepMeters: 100,
      );
      expect(table.length, 6);
      // First sampled row is the zero range → drop ≈ 0.
      expect(table.first.dropCm.abs(), lessThan(50));
      // Drop grows with range (positive = below LOS).
      expect(table.last.dropCm, greaterThan(50));
    });

    test('velocity decays monotonically with range', () {
      final table = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        startMeters: 100,
        endMeters: 1000,
        stepMeters: 100,
      );
      for (int i = 1; i < table.length; i++) {
        expect(table[i].velocityMs,
            lessThanOrEqualTo(table[i - 1].velocityMs + 0.5));
      }
    });

    test('energy decays with range and follows ½·m·v²', () {
      final table = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        startMeters: 200,
        endMeters: 600,
        stepMeters: 200,
      );
      final massKg = 175 / 7000 / 2.2046226218;
      for (final p in table) {
        final expected = 0.5 * massKg * p.velocityMs * p.velocityMs;
        expect(p.energyJoules, closeTo(expected, 1.0));
      }
      expect(table.last.energyJoules, lessThan(table.first.energyJoules));
    });

    test('zero range has near-zero drop', () {
      final table = eng.trajectoryTable(
        bullet: BulletProfile(
          muzzleVelocityMs: 820,
          ballisticCoefficient: 0.5,
          bulletWeightGrains: 175,
          zeroDistanceMeters: 200,
          scopeHeightMeters: 0.045,
        ),
        atmosphere: Atmosphere.standardSeaLevel,
        startMeters: 200,
        endMeters: 200,
        stepMeters: 100,
      );
      expect(table.first.dropCm.abs(), lessThan(5.0));
    });
  });

  group('G1 vs G7 drag curves', () {
    final bullet = BulletProfile(
      muzzleVelocityMs: 820,
      ballisticCoefficient: 0.5,
      bulletWeightGrains: 175,
      zeroDistanceMeters: 100,
      scopeHeightMeters: 0.045,
    );

    test('G1 and G7 produce different downrange velocity retention', () {
      final g1 = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        dragModel: DragModel.g1,
        startMeters: 100,
        endMeters: 800,
        stepMeters: 100,
      );
      final g7 = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        dragModel: DragModel.g7,
        startMeters: 100,
        endMeters: 800,
        stepMeters: 100,
      );
      // G7 (low-drag boat-tail) retains velocity better than G1 at range.
      expect(g7.last.velocityMs, greaterThan(g1.last.velocityMs));
    });

    test('G7 yields less drop than G1 at extended range', () {
      final g1 = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        dragModel: DragModel.g1,
        startMeters: 500,
        endMeters: 800,
        stepMeters: 100,
      );
      final g7 = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        dragModel: DragModel.g7,
        startMeters: 500,
        endMeters: 800,
        stepMeters: 100,
      );
      // Less drag → flatter trajectory → smaller drop (both positive at range).
      expect(g7.last.dropCm, lessThan(g1.last.dropCm));
    });
  });

  group('Atmospheric density altitude affects trajectory', () {
    final bullet = BulletProfile(
      muzzleVelocityMs: 820,
      ballisticCoefficient: 0.5,
      bulletWeightGrains: 175,
      zeroDistanceMeters: 100,
      scopeHeightMeters: 0.045,
    );

    test('thin air (high density altitude) → less drop, more velocity', () {
      final dense = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: Atmosphere.standardSeaLevel,
        startMeters: 300,
        endMeters: 800,
        stepMeters: 100,
      );
      final thin = eng.trajectoryTable(
        bullet: bullet,
        atmosphere: const Atmosphere(
          temperatureCelsius: 30.0,
          pressureHpa: 850.0,
          relativeHumidity: 10.0,
          altitudeMeters: 3000.0,
        ),
        startMeters: 300,
        endMeters: 800,
        stepMeters: 100,
      );
      // Less drag in thin air → higher retained velocity, less drop.
      expect(thin.last.velocityMs, greaterThan(dense.last.velocityMs));
      expect(thin.last.dropCm, lessThan(dense.last.dropCm));
    });
  });
}

