import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_constants.dart';

void main() {
  group('permitStatus', () {
    test('a null expiry date is no_expiry', () {
      expect(permitStatus(null), 'no_expiry');
    });

    test('classifies expired / expiring_soon / valid', () {
      final now = DateTime.now();
      expect(permitStatus(now.subtract(const Duration(days: 5))), 'expired');
      expect(permitStatus(now.add(const Duration(days: 10))), 'expiring_soon');
      expect(permitStatus(now.add(const Duration(days: 365))), 'valid');
    });
  });

  test('all 18 calculator functions are callable without throwing', () {
    final planted = <PlantedArea>[
      PlantedArea(
        id: 'p1',
        campId: 'c1',
        feedType: PlantedArea.feedTypeTeff,
        areaHa: 20,
        haPerLsu: 1.5,
      ),
      PlantedArea(
        id: 'p2',
        campId: 'c1',
        feedType: PlantedArea.feedTypeLucerneIrrigated,
        areaHa: 10,
        haPerLsu: 1.0,
        season: PlantedArea.seasonSummer,
      ),
    ];

    expect(lsuPerAnimal(450), isA<double>());
    expect(guPerAnimal(450, 0.6), isA<double>());
    expect(buPerAnimal(450, 0.4), isA<double>());
    expect(totalWeightKg(10, 50), isA<double>());
    expect(totalLsu(10, 0.5), isA<double>());
    expect(totalGu(10, 0.3), isA<double>());
    expect(totalBu(10, 0.2), isA<double>());
    expect(effectiveHaPerLsu(10, 'fair'), isA<double>());
    expect(veldCapacityLsu(1000, 12), isA<double>());
    expect(plantedCapacityLsu(20, 1.5), isA<double>());
    expect(yearRoundCapacityLsu(80, planted), isA<double>());
    expect(seasonalBoostLsu(planted, PlantedArea.seasonSummer), isA<double>());
    expect(usagePct(50, 100), isA<double>());
    expect(headroomLsu(100, 50), isA<double>());
    expect(stockingStatus(50), isA<String>());
    expect(preyKgPerYear(4, 7), isA<double>());
    expect(preyAnimalsPerYear(5110, 50), isA<double>());
    expect(permitStatus(null), isA<String>());
  });

  test('core arithmetic behaves as documented', () {
    expect(totalWeightKg(10, 50), closeTo(500, 1e-9));
    expect(totalLsu(10, 0.5), closeTo(5, 1e-9));
    expect(totalGu(10, 0.3), closeTo(3, 1e-9));
    expect(totalBu(10, 0.2), closeTo(2, 1e-9));
    expect(lsuPerAnimal(450), closeTo(1.0, 1e-9));
    expect(effectiveHaPerLsu(10, 'fair'), closeTo(12.5, 1e-9));
    expect(effectiveHaPerLsu(10, 'poor'), closeTo(16.0, 1e-9));
    expect(veldCapacityLsu(1200, 12), closeTo(100, 1e-9));
    expect(plantedCapacityLsu(20, 2), closeTo(10, 1e-9));
    expect(usagePct(50, 200), closeTo(25, 1e-9));
    expect(headroomLsu(100, 40), closeTo(60, 1e-9));
    expect(preyKgPerYear(4, 7), closeTo(10220, 1e-9));
    expect(preyAnimalsPerYear(10220, 50), closeTo(204.4, 1e-9));
  });

  test('year-round and seasonal capacities separate the two feed pools', () {
    final planted = <PlantedArea>[
      PlantedArea(
        id: 'all-year',
        campId: 'c1',
        feedType: PlantedArea.feedTypeTeff,
        areaHa: 20,
        haPerLsu: 1.5,
      ),
      PlantedArea(
        id: 'summer',
        campId: 'c1',
        feedType: PlantedArea.feedTypeLucerneIrrigated,
        areaHa: 10,
        haPerLsu: 1.0,
        season: PlantedArea.seasonSummer,
      ),
    ];

    // Veld 80 + the ALL_YEAR area only (20 / 1.5).
    expect(yearRoundCapacityLsu(80, planted), closeTo(80 + 13.3333333, 1e-6));
    // Phase 1: seasonalBoostLsu reports SEASON-SPECIFIC plantings only — the
    // ALL_YEAR area already sits in yearRoundCapacityLsu, so it is excluded.
    expect(
      seasonalBoostLsu(planted, PlantedArea.seasonSummer),
      closeTo(10, 1e-6),
    );
    // Winter has no winter-specific planting, so the boost is zero.
    expect(
      seasonalBoostLsu(planted, PlantedArea.seasonWinter),
      closeTo(0, 1e-6),
    );
    // Asking for ALL_YEAR returns 0 (reported by yearRoundCapacityLsu).
    expect(
      seasonalBoostLsu(planted, PlantedArea.seasonAllYear),
      closeTo(0, 1e-6),
    );
  });

  test('guards zero and negative inputs instead of throwing', () {
    expect(lsuPerAnimal(0), 0.0);
    expect(lsuPerAnimal(-5), 0.0);
    expect(totalWeightKg(0, 50), 0.0);
    expect(totalLsu(-5, 1), 0.0);
    expect(plantedCapacityLsu(10, 0), 0.0);
    expect(veldCapacityLsu(10, 0), 0.0);
    expect(usagePct(10, 0), 0.0);
    expect(preyAnimalsPerYear(100, 0), 0.0);
    expect(preyKgPerYear(0, 7), 0.0);
    expect(headroomLsu(10, 20), closeTo(-10, 1e-9));
  });

  group('constants contract', () {
    test('9 provinces, each with a suggested ha/LSU norm', () {
      expect(VeldCarryConstants.provinces.length, 9);
      expect(VeldCarryConstants.provinceSuggestedHaPerLsu.length, 9);
      for (final province in VeldCarryConstants.provinces) {
        expect(
          VeldCarryConstants.provinceSuggestedHaPerLsu[province],
          isNotNull,
          reason: province,
        );
      }
      expect(
        VeldCarryConstants.provinceSuggestedHaPerLsu['Northern Cape'],
        33.3,
      );
      expect(VeldCarryConstants.provinceSuggestedHaPerLsu['Gauteng'], 6.0);
    });

    test('13 planted feeds and 9 veld types', () {
      expect(VeldCarryConstants.plantedFeedHaPerLsu.length, 13);
      expect(VeldCarryConstants.plantedFeedHaPerLsu['KIKUYU_IRRIGATED'], 0.20);
      expect(VeldCarryConstants.plantedFeedHaPerLsu['MAIZE_STOVER'], 3.0);
      expect(VeldCarryConstants.veldTypes.length, 9);
    });

    test('veld condition multipliers are good/fair/poor', () {
      expect(VeldCarryConstants.veldConditionMultipliers, {
        'good': 1.0,
        'fair': 1.25,
        'poor': 1.60,
      });
      expect(VeldCarryConstants.veldConditionMultiplier('poor'), 1.60);
      // Phase 1: an unknown / blank condition falls back to `fair` (1.25).
      expect(VeldCarryConstants.veldConditionMultiplier('unknown'), 1.25);
      expect(VeldCarryConstants.veldConditionMultiplier(''), 1.25);
    });

    test('predator intake, permit types and present-only species', () {
      expect(VeldCarryConstants.predatorDailyIntakeKg.length, 12);
      expect(VeldCarryConstants.predatorDailyIntakeKg['Lion'], 7.0);
      expect(VeldCarryConstants.predatorDailyIntakeKg['Honey Badger'], 1.0);
      expect(VeldCarryConstants.permitTypes.length, 13);
      expect(VeldCarryConstants.presentOnlySpecies, [
        'Baboon',
        'Vervet Monkey',
        'Porcupine',
        'Aardvark',
      ]);
    });

    test('lookup helpers are tolerant of case and unknown values', () {
      expect(VeldCarryConstants.suggestedHaPerLsuForProvince('limpopo'), 10.0);
      expect(VeldCarryConstants.suggestedHaPerLsuForProvince('Atlantis'),
          isNull);
      expect(VeldCarryConstants.plantedHaPerLsuFor('teff'), 1.5);
      expect(VeldCarryConstants.plantedHaPerLsuFor('OTHER_CUSTOM'), isNull);
      expect(VeldCarryConstants.predatorDailyIntakeFor('leopard'), 4.0);
      expect(VeldCarryConstants.predatorDailyIntakeFor('Dragon'), isNull);
    });
  });
}
