import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/species_defaults.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';

/// Phase 1 real-formula tests. Weights/splits come from the authorised
/// fallback table in `species_defaults.dart` (see the FALLBACK header there).
PlantedArea _planted({
  required String id,
  required double areaHa,
  required double haPerLsu,
  String season = PlantedArea.seasonAllYear,
}) =>
    PlantedArea(
      id: id,
      campId: 'camp-1',
      feedType: PlantedArea.feedTypeTeff,
      areaHa: areaHa,
      haPerLsu: haPerLsu,
      season: season,
    );

void main() {
  group('lsuPerAnimal', () {
    test('450 kg reference steer is exactly 1.0 LSU', () {
      expect(lsuPerAnimal(450), closeTo(1.0, 1e-9));
    });

    test('zero and negative weights are 0 LSU', () {
      expect(lsuPerAnimal(0), 0.0);
      expect(lsuPerAnimal(-120), 0.0);
    });

    test('1800 kg scales metabolically to ~2.83 LSU', () {
      expect(lsuPerAnimal(1800), closeTo(2.83, 0.01));
    });

    test('non-finite weights are guarded to 0 LSU', () {
      expect(lsuPerAnimal(double.nan), 0.0);
      expect(lsuPerAnimal(double.infinity), 0.0);
    });
  });

  group('guPerAnimal / buPerAnimal', () {
    test('gu + bu equals lsu when the split sums to 1 (Impala 0.60/0.40)', () {
      final lsu = lsuPerAnimal(55);
      expect(
        guPerAnimal(55, 0.60) + buPerAnimal(55, 0.40),
        closeTo(lsu, 1e-12),
      );
    });

    test('gu + bu equals lsu for a browser split (Giraffe 0.05/0.95)', () {
      final lsu = lsuPerAnimal(1100);
      expect(
        guPerAnimal(1100, 0.05) + buPerAnimal(1100, 0.95),
        closeTo(lsu, 1e-12),
      );
    });

    test('fractions are clamped to 0..1', () {
      final lsu = lsuPerAnimal(100);
      expect(guPerAnimal(100, 1.8), closeTo(lsu, 1e-12));
      expect(buPerAnimal(100, -0.5), 0.0);
    });

    test('totals multiply the per-animal unit by the head count', () {
      expect(totalWeightKg(10, 55), closeTo(550, 1e-9));
      expect(totalLsu(10, 0.5), closeTo(5, 1e-9));
      expect(totalGu(10, 0.3), closeTo(3, 1e-9));
      expect(totalBu(10, 0.2), closeTo(2, 1e-9));
      expect(totalLsu(-3, 0.5), 0.0);
    });
  });

  group('effectiveHaPerLsu', () {
    test('poor veld is 1.60x the norm', () {
      expect(effectiveHaPerLsu(10, 'poor'), closeTo(16.0, 1e-9));
    });

    test('fair veld is 1.25x the norm', () {
      expect(effectiveHaPerLsu(10, 'fair'), closeTo(12.5, 1e-9));
    });

    test('good veld is 1.00x the norm', () {
      expect(effectiveHaPerLsu(10, 'good'), closeTo(10.0, 1e-9));
    });

    test('unknown veld condition falls back to fair (1.25x)', () {
      expect(effectiveHaPerLsu(10, 'unknown'), closeTo(12.5, 1e-9));
      expect(effectiveHaPerLsu(10, ''), closeTo(12.5, 1e-9));
    });
  });

  group('capacity', () {
    test('veld capacity divides hectares by the effective norm', () {
      expect(veldCapacityLsu(1000, 12.5), closeTo(80, 1e-9));
      expect(veldCapacityLsu(1000, 0), 0.0);
      expect(veldCapacityLsu(0, 12.5), 0.0);
    });

    test('planted capacity divides area by ha/LSU', () {
      expect(plantedCapacityLsu(20, 1.5), closeTo(13.3333333, 1e-6));
      expect(plantedCapacityLsu(20, 0), 0.0);
      expect(plantedCapacityLsu(0, 1.5), 0.0);
    });

    test('year-round capacity includes ALL_YEAR plantings only', () {
      final planted = <PlantedArea>[
        _planted(id: 'all-year', areaHa: 20, haPerLsu: 1.5),
        _planted(
          id: 'summer',
          areaHa: 10,
          haPerLsu: 1.0,
          season: PlantedArea.seasonSummer,
        ),
      ];
      // 80 veld + 13.333 ALL_YEAR; the SUMMER area is excluded.
      expect(yearRoundCapacityLsu(80, planted), closeTo(93.3333333, 1e-6));
      expect(yearRoundCapacityLsu(80, const []), closeTo(80, 1e-9));
      expect(yearRoundCapacityLsu(-5, const []), 0.0);
    });

    test('seasonal boost reports that season only and never ALL_YEAR', () {
      final planted = <PlantedArea>[
        _planted(id: 'all-year', areaHa: 20, haPerLsu: 1.5),
        _planted(
          id: 'summer',
          areaHa: 10,
          haPerLsu: 1.0,
          season: PlantedArea.seasonSummer,
        ),
        _planted(
          id: 'winter',
          areaHa: 6,
          haPerLsu: 1.2,
          season: PlantedArea.seasonWinter,
        ),
      ];
      // SUMMER excludes the ALL_YEAR area.
      expect(
        seasonalBoostLsu(planted, PlantedArea.seasonSummer),
        closeTo(10, 1e-9),
      );
      expect(
        seasonalBoostLsu(planted, PlantedArea.seasonWinter),
        closeTo(5, 1e-9),
      );
      // ALL_YEAR is reported by yearRoundCapacityLsu, so 0 here.
      expect(
        seasonalBoostLsu(planted, PlantedArea.seasonAllYear),
        0.0,
      );
    });
  });

  group('usagePct / headroomLsu / stockingStatus', () {
    test('usage is LSU as a percentage of capacity', () {
      expect(usagePct(50, 200), closeTo(25, 1e-9));
      expect(usagePct(100, 100), closeTo(100, 1e-9));
    });

    test('usage is 0 for a non-positive capacity and clamped at 999', () {
      expect(usagePct(50, 0), 0.0);
      expect(usagePct(50, -10), 0.0);
      expect(usagePct(5000, 100), closeTo(usagePctCeiling, 1e-9));
      expect(usagePct(-5, 100), 0.0);
    });

    test('headroom is capacity minus usage and may go negative', () {
      expect(headroomLsu(100, 40), closeTo(60, 1e-9));
      expect(headroomLsu(100, 130), closeTo(-30, 1e-9));
    });

    test('stocking bands break at 70 / 100 / 120', () {
      expect(stockingStatus(0), stockingUnderstocked);
      expect(stockingStatus(69), stockingUnderstocked);
      expect(stockingStatus(70), stockingOptimal);
      expect(stockingStatus(100), stockingOptimal);
      expect(stockingStatus(101), stockingOverstocked);
      expect(stockingStatus(120), stockingOverstocked);
      expect(stockingStatus(121), stockingSeverelyOverstocked);
      expect(stockingStatus(300), stockingSeverelyOverstocked);
    });
  });

  group('predator impact', () {
    test('prey kilograms per year multiply intake by 365', () {
      expect(preyKgPerYear(4, 7), closeTo(10220, 1e-9));
      expect(preyKgPerYear(0, 7), 0.0);
      expect(preyKgPerYear(4, 0), 0.0);
    });

    test('prey animals per year divides by average prey weight', () {
      expect(preyAnimalsPerYear(10220, 50), closeTo(204.4, 1e-9));
      expect(preyAnimalsPerYear(10220, 0), 0.0);
      expect(preyAnimalsPerYear(0, 50), 0.0);
    });
  });

  group('permitStatus', () {
    test('classifies no_expiry / expired / expiring_soon / valid', () {
      final now = DateTime.now();
      expect(permitStatus(null), 'no_expiry');
      expect(permitStatus(now.subtract(const Duration(days: 5))), 'expired');
      expect(permitStatus(now.add(const Duration(days: 10))), 'expiring_soon');
      expect(permitStatus(now.add(const Duration(days: 365))), 'valid');
    });

    test('the 30-day expiry window is the boundary', () {
      final now = DateTime.now();
      expect(permitStatus(now.add(const Duration(days: 30))), 'expiring_soon');
      expect(permitStatus(now.add(const Duration(days: 31))), 'valid');
    });
  });

  group('speciesDefaults (authorised fallback table)', () {
    test('the table carries 49 species and every one has a positive weight',
        () {
      expect(speciesDefaults, hasLength(49));
      for (final species in speciesDefaults) {
        expect(
          species.avgWeightKg,
          greaterThan(0),
          reason: '${species.speciesName} must carry an authorised weight',
        );
        expect(species.hasKnownWeight, isTrue);
        expect(species.isMissing, isFalse);
      }
    });

    test('every counted species has a grazer + browser split summing to 1', () {
      for (final species in speciesDefaults) {
        if (!species.isCounted) continue;
        if (species.speciesName == 'Aardvark') continue; // documented 0 / 0
        expect(
          species.grazerPct + species.browserPct,
          closeTo(1.0, 1e-9),
          reason: '${species.speciesName} split must sum to 1',
        );
      }
    });

    test('Aardvark is the single 0 / 0 exception and is not counted', () {
      final aardvark = speciesDefaults
          .firstWhere((species) => species.speciesName == 'Aardvark');
      expect(aardvark.grazerPct, 0.0);
      expect(aardvark.browserPct, 0.0);
      expect(aardvark.isCounted, isFalse);

      final exceptions = speciesDefaults
          .where((species) => !species.hasCompleteSplit)
          .map((species) => species.speciesName)
          .toList();
      expect(exceptions, ['Aardvark']);
    });

    test('baboon, vervet, porcupine and aardvark are present-only', () {
      for (final name in const [
        'Chacma Baboon',
        'Vervet Monkey',
        'Cape Porcupine',
        'Aardvark',
      ]) {
        final species = speciesDefaults
            .firstWhere((entry) => entry.speciesName == name);
        expect(species.isCounted, isFalse, reason: name);
      }
      expect(countedSpeciesDefaults, hasLength(speciesDefaults.length - 4));
    });

    test('the six omnivores are flagged', () {
      final omnivores = speciesDefaults
          .where((species) => species.isOmnivore)
          .map((species) => species.speciesName)
          .toList();
      expect(
        omnivores,
        unorderedEquals([
          'Chacma Baboon',
          'Vervet Monkey',
          'Cape Porcupine',
          'Aardvark',
          'Warthog',
          'Bushpig',
        ]),
      );
    });

    test('names normalise to the short UI label', () {
      expect(speciesDisplayName('Chacma Baboon'), 'Baboon');
      expect(speciesDisplayName('Cape Porcupine'), 'Porcupine');
      expect(speciesDisplayName('Vervet Monkey'), 'Vervet');
      expect(speciesDisplayName('Impala'), 'Impala');
      expect(speciesDisplayName(null), '');
      expect(
        speciesDefaultFor('Chacma Baboon')!.displayName,
        'Baboon',
      );
    });

    test('CSV spellings resolve to the canonical table entry', () {
      expect(speciesDefaultFor('Common Warthog')!.speciesName, 'Warthog');
      expect(speciesDefaultFor('Gemsbok (Oryx)')!.speciesName, 'Gemsbok');
      expect(speciesDefaultFor('Common Waterbuck')!.speciesName, 'Waterbuck');
      expect(speciesDefaultFor('Southern Bushbuck')!.speciesName, 'Bushbuck');
      expect(speciesDefaultFor('Southern Reedbuck')!.speciesName,
          'Reedbuck (Common)');
      expect(speciesDefaultFor('Natal Red Duiker')!.speciesName, 'Red Duiker');
      expect(speciesDefaultFor('Southern White Rhinoceros')!.speciesName,
          'White Rhino');
      expect(speciesDefaultFor('Rock Hyrax')!.speciesName,
          'Dassie / Rock Hyrax');
      expect(speciesDefaultFor('Greater Cane Rat')!.speciesName, 'Cane Rat');
      expect(speciesDefaultFor('  impala  ')!.speciesName, 'Impala');
      expect(speciesDefaultFor(''), isNull);
      expect(speciesDefaultFor(null), isNull);
    });

    test('species absent from the table are carried as MISSING placeholders',
        () {
      expect(missingSpeciesNames, isNotEmpty);
      expect(missingSpecies, hasLength(missingSpeciesNames.length));
      for (final species in missingSpecies) {
        expect(species.avgWeightKg, 0.0, reason: species.speciesName);
        expect(species.isCounted, isTrue, reason: species.speciesName);
        expect(species.feedingClass, FeedingClass.unknown);
        expect(species.isMissing, isTrue);
      }
      // A missing species still resolves (so the UI can show "not verified").
      final aardwolf = speciesDefaultFor('Aardwolf');
      expect(aardwolf, isNotNull);
      expect(aardwolf!.isMissing, isTrue);
    });

    test('the table feeds the LSU maths end to end', () {
      final impala = speciesDefaultFor('Impala')!;
      expect(lsuPerAnimal(impala.avgWeightKg), closeTo(0.2066, 0.001));
      expect(
        guPerAnimal(impala.avgWeightKg, impala.grazerPct) +
            buPerAnimal(impala.avgWeightKg, impala.browserPct),
        closeTo(lsuPerAnimal(impala.avgWeightKg), 1e-12),
      );
    });
  });
}
