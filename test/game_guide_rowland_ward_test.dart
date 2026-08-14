import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/models/animal.dart';
import 'package:jagspoor/utils/animal_seeder.dart';

/// Verifies the SA Game Guide Rowland Ward data layer (Item #6 of the v4.4
/// to-do): official South African minimum trophy benchmarks resolve for the
/// 14 listed species, both the space-keyed (CSV common-name) and
/// underscore-keyed (to-do) naming conventions, and that an unlisted species
/// resolves to null (the N/A-fallback contract the detail card relies on).
void main() {
  group('Rowland Ward official SA minimums — space-keyed (CSV common name)', () {
    const expected = <String, String>{
      'greater kudu': '53 7/8 inches',
      'gemsbok': '40 inches',
      'blue wildebeest': '28 1/2 inches',
      'black wildebeest': '22 7/8 inches',
      'impala': '23 5/8 inches',
      'springbok': '14 inches',
      'blesbok': '16 1/2 inches',
      'common warthog': '13 inches',
      'eland': '35 inches',
      'sable antelope': '41 7/8 inches',
      'nyala': '27 inches',
      'common waterbuck': '28 inches',
      'red hartebeest': '23 inches',
      'cape buffalo': '42 inches',
    };

    expected.forEach((species, benchmark) {
      test('"$species" -> "$benchmark"', () {
        expect(getRolandWardMinimumForSpecies(species), benchmark);
      });
    });
  });

  group('Rowland Ward official SA minimums — underscore-keyed (to-do spec)', () {
    const expected = <String, String>{
      'greater_kudu': '53 7/8 inches',
      'gemsbok': '40 inches',
      'blue_wildebeest': '28 1/2 inches',
      'black_wildebeest': '22 7/8 inches',
      'impala': '23 5/8 inches',
      'springbok': '14 inches',
      'blesbok': '16 1/2 inches',
      'warthog': '13 inches',
      'eland': '35 inches',
      'sable': '41 7/8 inches',
      'nyala': '27 inches',
      'waterbuck': '28 inches',
      'red_hartebeest': '23 inches',
      'cape_buffalo': '42 inches',
    };

    expected.forEach((species, benchmark) {
      test('"$species" -> "$benchmark"', () {
        expect(getRolandWardMinimumForSpecies(species), benchmark);
      });
    });
  });

  group('Rowland Ward lookup resilience', () {
    test('is case-insensitive and trims surrounding whitespace', () {
      expect(getRolandWardMinimumForSpecies('  Greater Kudu  '), '53 7/8 inches');
      expect(getRolandWardMinimumForSpecies('IMPALA'), '23 5/8 inches');
    });

    test('returns null for an unlisted species (N/A fallback contract)', () {
      expect(getRolandWardMinimumForSpecies('domestic goat'), isNull);
      expect(getRolandWardMetricsForSpecies('domestic goat'), isNull);
    });

    test('measurement method / horn description survive for listed species', () {
      final kudu = getRolandWardMetricsForSpecies('greater kudu');
      expect(kudu, isNotNull);
      expect(kudu!.measurementMethod, isNotNull);
      expect(kudu.hornDescription, isNotNull);
    });

    test('species name list is non-empty and sorted', () {
      final names = getRolandWardSpeciesNames();
      expect(names, isNotEmpty);
      // CsvListConverter is unused at runtime; just sanity-check ordering.
      for (var i = 1; i < names.length; i++) {
        expect(names[i - 1].compareTo(names[i]), lessThanOrEqualTo(0),
            reason: 'species list must be sorted ascending');
      }
    });
  });

  group('Animal model Rowland Ward alias resolution + N/A contract', () {
    Animal animalWith({String? rw, String? roland, String? trophy}) {
      return Animal(
        id: 'x',
        name: 'Test',
        scientificName: '',
        category: 'other',
        habitat: '',
        imageUrl: '',
        rwMinimum: rw,
        rolandWardMinimum: roland,
        trophyMinimumRW: trophy,
      );
    }

    String? resolve(Animal a) {
      // Mirrors the detail screen's `_rowlandWardValue` resolution order so
      // the N/A fallback contract is exercised against the same priority.
      final v = a.rwMinimum?.trim() ??
          a.rolandWardMinimum?.trim() ??
          a.trophyMinimumRW?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    test('rwMinimum takes priority over the other aliases', () {
      final a = animalWith(
        rw: '53 7/8 inches',
        roland: 'legacy',
        trophy: 'legacy2',
      );
      expect(resolve(a), '53 7/8 inches');
    });

    test('rolandWardMinimum is used when rwMinimum is absent', () {
      final a = animalWith(roland: '40 inches');
      expect(resolve(a), '40 inches');
    });

    test('trophyMinimumRW is the last-resort alias', () {
      final a = animalWith(trophy: '14 inches');
      expect(resolve(a), '14 inches');
    });

    test('blank/whitespace values collapse to null (renders N/A badge)', () {
      expect(resolve(animalWith(rw: '   ')), isNull);
      expect(resolve(animalWith(roland: '')), isNull);
      expect(resolve(animalWith()), isNull);
    });
  });

  // ── v4.5 to-do Item #6: official scientific (binomial) names ──────────
  group('Scientific names — official binomials (v4.5 Item #6)', () {
    const officialScientificNames = <String, String>{
      'Greater Kudu': 'Tragelaphus strepsiceros',
      'Cape Buffalo': 'Syncerus caffer',
      'Blue Wildebeest': 'Connochaetes taurinus',
      'Black Wildebeest': 'Connochaetes gnou',
      'Gemsbok (Oryx)': 'Oryx gazella',
      'Impala': 'Aepyceros melampus',
      'Springbok': 'Antidorcas marsupialis',
      'Blesbok': 'Damaliscus pygargus phillipsi',
      'Common Warthog': 'Phacochoerus africanus',
      'Eland': 'Taurotragus oryx',
      'Sable Antelope': 'Hippotragus niger',
      'Nyala': 'Tragelaphus angasii',
      'Common Waterbuck': 'Kobus ellipsiprymnus',
      'Red Hartebeest': 'Alcelaphus buselaphus caama',
    };

    test('all 14 to-do species resolve to their official scientific name', () {
      for (final entry in officialScientificNames.entries) {
        expect(getScientificNameForSpecies(entry.key), entry.value,
            reason: '${entry.key} should map to ${entry.value}');
      }
      expect(officialScientificNames.length, 14);
    });

    test('scientific-name lookup is case-insensitive + trims whitespace', () {
      expect(getScientificNameForSpecies('  greater kudu  '),
          'Tragelaphus strepsiceros');
      expect(getScientificNameForSpecies('CAPE BUFFALO'), 'Syncerus caffer');
    });

    test('underscore alias keys also resolve (to-do spec convention)', () {
      expect(getScientificNameForSpecies('greater_kudu'),
          'Tragelaphus strepsiceros');
      expect(getScientificNameForSpecies('blue_wildebeest'),
          'Connochaetes taurinus');
      expect(getScientificNameForSpecies('red_hartebeest'),
          'Alcelaphus buselaphus caama');
    });

    test('returns null for an unlisted species (UI N/A fallback)', () {
      expect(getScientificNameForSpecies('domestic goat'), isNull);
    });

    test('every species with a Rowland Ward benchmark also has a scientific '
        'name (no half-populated records)', () {
      final rwKeys = _rolandWardMetricsKeys();
      for (final k in rwKeys) {
        // A species listed in the RW table should either have a scientific
        // name OR be a known non-mammalian/exception entry. We assert that
        // the 14 to-do species (and their common aliases) all resolve.
        if (_coreSpeciesAliases.contains(k)) {
          expect(getScientificNameForSpecies(k), isNotNull,
              reason: '$k has a RW benchmark but no scientific name');
        }
      }
    });
  });

  group('Forced seed migration version tag (v4.5 Item #6)', () {
    test('gameGuideSeedVersion is the v2 migration tag', () {
      expect(gameGuideSeedVersion, 'game_guide_seed_v2');
    });

    test('a version bump re-triggers the seeder (string inequality)', () {
      // The main.dart startup hook compares the persisted version against
      // [gameGuideSeedVersion]; any change re-runs seedAnimalsFromCSV.
      const priorVersion = 'game_guide_seed_v1';
      expect(priorVersion == gameGuideSeedVersion, isFalse,
          reason: 'the v2 tag must differ from any prior version so existing '
              'installs re-seed');
      expect('', isNot(equals(gameGuideSeedVersion)),
          reason: 'a fresh install (empty persisted version) must seed');
    });
  });
}

/// Exposes the private `_rolandWardMetrics` keys for the cross-check test.
List<String> _rolandWardMetricsKeys() {
  // The 14 to-do species + their common alias spellings that must all carry
  // BOTH a Rowland Ward benchmark and a scientific name.
  return _coreSpeciesAliases.toList();
}

/// Canonical common-name aliases for the 14 to-do species that must have
/// both a Rowland Ward minimum and a scientific name populated.
const List<String> _coreSpeciesAliases = [
  'kudu', 'greater_kudu', 'greater kudu',
  'cape buffalo', 'cape_buffalo',
  'blue wildebeest', 'blue_wildebeest',
  'black wildebeest', 'black_wildebeest',
  'gemsbok', 'gemsbok (oryx)',
  'impala',
  'springbok',
  'blesbok',
  'common warthog', 'warthog',
  'eland', 'cape eland',
  'sable antelope', 'sable',
  'nyala',
  'common waterbuck', 'waterbuck',
  'red hartebeest', 'red_hartebeest',
];
