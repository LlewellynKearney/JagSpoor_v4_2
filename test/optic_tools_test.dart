import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/ballistics/data/models/optic_profile.dart';
import 'package:jagspoor/features/ballistics/data/models/rifle_profile.dart';
import 'package:jagspoor/features/ballistics/data/scope_calculator.dart';

void main() {
  group('OpticProfile', () {
    test('round-trips through JSON preserving all fields', () {
      const optic = OpticProfile(
        opticName: 'Vortex Razor HD',
        tubeDiameterMm: 34.0,
        heightOverBoreInches: 2.1,
        turretUnit: TurretUnit.mrad,
        clickValue: 0.1,
        focalPlane: FocalPlane.ffp,
        reticleType: 'Tactical Milling',
        nativeMagnification: 12.0,
        currentMagnification: 8.0,
      );
      final restored = OpticProfile.fromJson(optic.toJson());
      expect(restored.opticName, 'Vortex Razor HD');
      expect(restored.tubeDiameterMm, 34.0);
      expect(restored.heightOverBoreInches, 2.1);
      expect(restored.turretUnit, TurretUnit.mrad);
      expect(restored.clickValue, 0.1);
      expect(restored.focalPlane, FocalPlane.ffp);
      expect(restored.reticleType, 'Tactical Milling');
      expect(restored.nativeMagnification, 12.0);
      expect(restored.currentMagnification, 8.0);
    });

    test('parses tolerant turret-unit / focal-plane string variants', () {
      final optic = OpticProfile.fromJson({
        'turretUnit': 'Mil',
        'focalPlane': 'first focal plane',
      });
      expect(optic.turretUnit, TurretUnit.mrad);
      expect(optic.focalPlane, FocalPlane.ffp);
    });

    test('clickValueLabel renders common fractions', () {
      expect(const OpticProfile(clickValue: 0.25).clickValueLabel, '1/4 MOA');
      expect(const OpticProfile(clickValue: 0.125).clickValueLabel, '1/8 MOA');
      expect(
        const OpticProfile(
                turretUnit: TurretUnit.mrad, clickValue: 0.1)
            .clickValueLabel,
        '0.1 MRAD',
      );
    });
  });

  group('Zeroing click calculator', () {
    test('impact LOW + RIGHT → dial UP and LEFT (MOA 1/4 @ 100yd)', () {
      // 2.0" low, 1.0" right at 100 yards, 1/4 MOA clicks.
      final r = ScopeCalculator.calculateZeroingClicks(
        verticalInches: -2.0,
        horizontalInches: 1.0,
        distanceYards: 100,
        unit: TurretUnit.moa,
        clickValue: 0.25,
      );
      // 2" low @ 100yd ≈ 1.909 MOA → ~8 clicks UP
      expect(r.elevationDirection, 'UP');
      expect(r.windageDirection, 'LEFT');
      expect(r.elevation.clicks, closeTo(8, 1));
      expect(r.windage.clicks, closeTo(4, 1));
      expect(r.hasAdjustment, isTrue);
    });

    test('never reports a direction when already on target', () {
      final r = ScopeCalculator.calculateZeroingClicks(
        verticalInches: 0,
        horizontalInches: 0,
        distanceYards: 200,
        unit: TurretUnit.moa,
        clickValue: 0.25,
      );
      expect(r.elevation.clicks, 0);
      expect(r.windage.clicks, 0);
      expect(r.tacticalString, contains('NO ADJUSTMENT'));
    });

    test('MRAD scope yields fewer clicks for the same displacement', () {
      final moa = ScopeCalculator.calculateZeroingClicks(
        verticalInches: -3.6,
        horizontalInches: 0,
        distanceYards: 100,
        unit: TurretUnit.moa,
        clickValue: 0.25,
      );
      final mil = ScopeCalculator.calculateZeroingClicks(
        verticalInches: -3.6,
        horizontalInches: 0,
        distanceYards: 100,
        unit: TurretUnit.mrad,
        clickValue: 0.1,
      );
      // 3.6" at 100yd = 1 MRAD = 10 clicks (0.1 each); ≈ 3.44 MOA ≈ 14 clicks (0.25 each)
      expect(mil.elevation.clicks, 10);
      expect(moa.elevation.clicks, closeTo(14, 1));
      expect(mil.elevationDirection, 'UP');
    });
  });

  group('SFP scaling', () {
    test('SFP scales reticle value inversely with magnification', () {
      // Native 10x, shooting at 5x, 2 mil hold → true hold 4 mils.
      final r = ScopeCalculator.calculateSfpScaling(
        nativeMagnification: 10,
        currentMagnification: 5,
        nativeReticleValue: 2,
        unit: TurretUnit.mrad,
        focalPlane: FocalPlane.sfp,
      );
      expect(r.scalingFactor, 2.0);
      expect(r.trueReticleValue, 4.0);
      expect(r.isScaled, isTrue);
    });

    test('FFP never scales regardless of magnification', () {
      final r = ScopeCalculator.calculateSfpScaling(
        nativeMagnification: 10,
        currentMagnification: 4,
        nativeReticleValue: 3,
        unit: TurretUnit.mrad,
        focalPlane: FocalPlane.ffp,
      );
      expect(r.scalingFactor, 1.0);
      expect(r.trueReticleValue, 3.0);
      expect(r.isScaled, isFalse);
    });

    test('SFP at native magnification reports no scaling', () {
      final r = ScopeCalculator.calculateSfpScaling(
        nativeMagnification: 10,
        currentMagnification: 10,
        nativeReticleValue: 2,
        unit: TurretUnit.mrad,
        focalPlane: FocalPlane.sfp,
      );
      expect(r.isScaled, isFalse);
      expect(r.trueReticleValue, 2.0);
    });
  });

  group('Turret tracking error', () {
    test('perfect tracking → 0% error, excellent quality', () {
      // 5 MOA dialed @ 100yd → expect 5.235" displacement; measure exactly that.
      final r = ScopeCalculator.calculateTrackingError(
        dialedValue: 5,
        measuredDisplacementInches: 5 * 1.047,
        distanceYards: 100,
        unit: TurretUnit.moa,
      );
      expect(r.trackingErrorPercent, lessThan(0.01));
      expect(r.trackingQuality, TrackingQuality.excellent);
    });

    test('measures % tracking error and bands quality', () {
      // 5 MRAD @ 100yd → expect 18.0". Measure 17.1" (5% low) → 5% error.
      final r = ScopeCalculator.calculateTrackingError(
        dialedValue: 5,
        measuredDisplacementInches: 17.1,
        distanceYards: 100,
        unit: TurretUnit.mrad,
      );
      expect(r.expectedDisplacementInches, closeTo(18.0, 0.01));
      expect(r.trackingErrorPercent, closeTo(5.0, 0.1));
      expect(r.trackingQuality, TrackingQuality.fair);
    });

    test('zero dialed value does not divide by zero', () {
      final r = ScopeCalculator.calculateTrackingError(
        dialedValue: 0,
        measuredDisplacementInches: 0,
        distanceYards: 100,
        unit: TurretUnit.moa,
      );
      expect(r.trackingErrorPercent, 0.0);
      expect(r.expectedDisplacementInches, 0.0);
    });
  });

  group('RifleProfile optic linkage', () {
    test('hydrates embedded optic map and survives legacy docs', () {
      final legacy = RifleProfile.fromJson({'name': 'Old Rifle', 'caliber': '.308'});
      expect(legacy.optic, isNull);

      final withOptic = RifleProfile.fromJson({
        'name': 'Tactical',
        'caliber': '.308',
        'optic': {
          'opticName': 'NX8',
          'turretUnit': 'MRAD',
          'focalPlane': 'FFP',
          'clickValue': 0.1,
          'tubeDiameterMm': 30.0,
        },
      });
      expect(withOptic.optic, isNotNull);
      expect(withOptic.optic!.opticName, 'NX8');
      expect(withOptic.optic!.turretUnit, TurretUnit.mrad);
      expect(withOptic.optic!.focalPlane, FocalPlane.ffp);

      // Round-trip back to JSON keeps the optic map.
      final out = withOptic.toJson();
      expect(out['optic'], isA<Map>());
      expect((out['optic'] as Map)['turretUnit'], 'MRAD');
    });
  });

  group('OpticProfile firearm binding', () {
    test('firearmId defaults to empty for legacy optic specs', () {
      expect(const OpticProfile().firearmId, '');
      final fromLegacy = OpticProfile.fromJson({'opticName': 'Legacy'});
      expect(fromLegacy.firearmId, '');
    });

    test('round-trips firearmId through JSON', () {
      const optic = OpticProfile(opticName: 'Razor', firearmId: 'rifle_123');
      final out = optic.toJson();
      expect(out['firearmId'], 'rifle_123');
      final restored = OpticProfile.fromJson(out);
      expect(restored.firearmId, 'rifle_123');
    });

    test('copyWith updates firearmId without touching other fields', () {
      const base = OpticProfile(opticName: 'NX8', clickValue: 0.1);
      final bound = base.copyWith(firearmId: 'rifle_abc');
      expect(bound.firearmId, 'rifle_abc');
      expect(bound.opticName, 'NX8');
      expect(bound.clickValue, 0.1);
    });

    test('hydrated optic carries the host firearm id', () {
      final rifle = RifleProfile.fromJson({
        'make': 'Tikka',
        'model': 'T3x',
        'caliber': '.308 Win',
        'optic': {
          'opticName': 'Viper',
          'firearmId': 'rifle_xyz',
        },
      });
      expect(rifle.optic, isNotNull);
      expect(rifle.optic!.firearmId, 'rifle_xyz');
    });
  });

  group('RifleProfile display name (optic-link dropdown label)', () {
    test('formats make + model + calibre per spec', () {
      final rifle = RifleProfile.fromJson({
        'make': 'Tikka',
        'model': 'T3x',
        'caliber': '.308 Win',
      });
      expect(rifle.displayName, 'Tikka T3x (.308 Win)');
    });

    test('falls back to brand/manufacturer when make is absent', () {
      final brand = RifleProfile.fromJson({
        'brand': 'Sako',
        'model': 'S20',
        'caliber': '6.5 CM',
      });
      expect(brand.displayName, 'Sako S20 (6.5 CM)');
    });

    test('renders em-dash when calibre is unknown', () {
      final noCal = RifleProfile.fromJson({'make': 'Remington', 'model': '700'});
      expect(noCal.displayName, 'Remington 700 (—)');
    });

    test('falls back to name then generic when make/model absent', () {
      final withName = RifleProfile.fromJson({'name': 'Old Rifle', 'caliber': '.308'});
      expect(withName.displayName, 'Old Rifle (.308)');

      final bare = RifleProfile.fromJson({'caliber': '.300'});
      expect(bare.displayName, 'Unnamed firearm (.300)');

      final empty = RifleProfile(id: 'x', name: '', caliber: '');
      expect(empty.displayName, 'Unnamed firearm (—)');
    });

    test('serial alias is tolerated (firearm safe persists "serial")', () {
      final rifle = RifleProfile.fromJson({
        'make': 'CZ',
        'model': '557',
        'caliber': '7x57',
        'serial': 'SN-12345',
      });
      expect(rifle.serialNumber, 'SN-12345');
    });
  });
}
