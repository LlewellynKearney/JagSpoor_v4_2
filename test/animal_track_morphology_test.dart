import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/track/data/track_taxonomy.dart';
import 'package:jagspoor/models/animal.dart';
import 'package:jagspoor/utils/animal_seeder.dart';

/// Verifies the spoor-morphology expansion of the SA Game Guide dataset:
/// the five new `Animal` track fields (`toeCount`, `trackLengthMinMm`,
/// `trackLengthMaxMm`, `trackWidthMinMm`, `trackWidthMaxMm`) round-trip
/// through the model serialization, the seeder's `_trackMorphology` dataset
/// resolves the canonical toe counts + dimensions, the seed version was
/// bumped so existing installs re-seed, and the spoor taxonomy category map
/// covers every canonical species with a matching toe count.
void main() {
  group('Animal model — track morphology serialization', () {
    Animal animalWith({
      int? toeCount,
      double? trackLengthMinMm,
      double? trackLengthMaxMm,
      double? trackWidthMinMm,
      double? trackWidthMaxMm,
    }) {
      return Animal(
        id: 'test',
        name: 'Test',
        scientificName: '',
        category: 'other',
        habitat: '',
        imageUrl: '',
        toeCount: toeCount,
        trackLengthMinMm: trackLengthMinMm,
        trackLengthMaxMm: trackLengthMaxMm,
        trackWidthMinMm: trackWidthMinMm,
        trackWidthMaxMm: trackWidthMaxMm,
      );
    }

    test('toJson writes all five fields when set', () {
      final json = animalWith(
        toeCount: 2,
        trackLengthMinMm: 55.0,
        trackLengthMaxMm: 55.0,
        trackWidthMinMm: 38.0,
        trackWidthMaxMm: 38.0,
      ).toJson();
      expect(json['toeCount'], 2);
      expect(json['trackLengthMinMm'], 55.0);
      expect(json['trackLengthMaxMm'], 55.0);
      expect(json['trackWidthMinMm'], 38.0);
      expect(json['trackWidthMaxMm'], 38.0);
    });

    test('toJson omits the fields when null (species without track data)', () {
      final json = animalWith().toJson();
      expect(json.containsKey('toeCount'), isFalse);
      expect(json.containsKey('trackLengthMinMm'), isFalse);
      expect(json.containsKey('trackLengthMaxMm'), isFalse);
      expect(json.containsKey('trackWidthMinMm'), isFalse);
      expect(json.containsKey('trackWidthMaxMm'), isFalse);
    });

    test('fromJson round-trips all five fields', () {
      final json = {
        'id': 'kudu',
        'name': 'Greater Kudu',
        'commonName': 'Greater Kudu',
        'scientificName': 'Tragelaphus strepsiceros',
        'category': 'Mammal (Antelope)',
        'habitat': 'South Africa',
        'imageUrl': '',
        'toeCount': 2,
        'trackLengthMinMm': 90.0,
        'trackLengthMaxMm': 90.0,
        'trackWidthMinMm': 60.0,
        'trackWidthMaxMm': 60.0,
      };
      final animal = Animal.fromJson(json);
      expect(animal.toeCount, 2);
      expect(animal.trackLengthMinMm, 90.0);
      expect(animal.trackLengthMaxMm, 90.0);
      expect(animal.trackWidthMinMm, 60.0);
      expect(animal.trackWidthMaxMm, 60.0);
    });

    test('fromJson tolerates numeric-string values for the track fields', () {
      final animal = Animal.fromJson({
        'id': 'x',
        'name': 'X',
        'category': 'other',
        'habitat': '',
        'imageUrl': '',
        'toeCount': '2',
        'trackLengthMinMm': '90.5',
        'trackWidthMaxMm': '60.25',
      });
      expect(animal.toeCount, 2);
      expect(animal.trackLengthMinMm, 90.5);
      expect(animal.trackWidthMaxMm, 60.25);
    });

    test('fromJson leaves the fields null when absent', () {
      final animal = Animal.fromJson({
        'id': 'x',
        'name': 'X',
        'category': 'other',
        'habitat': '',
        'imageUrl': '',
      });
      expect(animal.toeCount, isNull);
      expect(animal.trackLengthMinMm, isNull);
      expect(animal.trackLengthMaxMm, isNull);
      expect(animal.trackWidthMinMm, isNull);
      expect(animal.trackWidthMaxMm, isNull);
    });
  });

  group('Seeder — canonical track-morphology dataset', () {
    test('paw carnivores resolve to 4 toes with established dimensions', () {
      final leopard = getTrackMorphologyForSpecies('leopard');
      expect(leopard, isNotNull);
      expect(leopard!.toeCount, 4);
      expect(leopard.trackLengthMm, 95.0);
      expect(leopard.trackWidthMm, 90.0);

      final lion = getTrackMorphologyForSpecies('lion');
      expect(lion, isNotNull);
      expect(lion!.toeCount, 4);
      expect(lion.trackLengthMm, 135.0);
      expect(lion.trackWidthMm, 125.0);

      final cheetah = getTrackMorphologyForSpecies('cheetah');
      expect(cheetah, isNotNull);
      expect(cheetah!.toeCount, 4);
      expect(cheetah.trackLengthMm, 82.0);
      expect(cheetah.trackWidthMm, 70.0);
    });

    test('cloven-hoofed ungulates resolve to 2 toes', () {
      for (final species in [
        'kudu',
        'impala',
        'gemsbok',
        'eland',
        'nyala',
        'springbok',
        'blesbok',
        'blue wildebeest',
        'black wildebeest',
        'common waterbuck',
        'red hartebeest',
        'sable antelope',
        'roan antelope',
        'common duiker',
        'steenbok',
        'oribi',
        'giraffe',
        'cape buffalo',
      ]) {
        final m = getTrackMorphologyForSpecies(species);
        expect(m, isNotNull, reason: '$species should have track morphology');
        expect(m!.toeCount, 2, reason: '$species should be cloven-hoofed');
      }
    });

    test('solid-hoofed equines resolve to 1 toe', () {
      for (final species in ['plains zebra', 'zebra', 'donkey', 'horse']) {
        final m = getTrackMorphologyForSpecies(species);
        expect(m, isNotNull, reason: '$species should have track morphology');
        expect(m!.toeCount, 1, reason: '$species should be solid-hoofed');
      }
    });

    test('dangerous game / megafauna resolve to their canonical toe counts', () {
      expect(getToeCountForSpecies('african elephant'), 4);
      expect(getToeCountForSpecies('black rhinoceros'), 3);
      expect(getToeCountForSpecies('southern white rhinoceros'), 3);
      expect(getToeCountForSpecies('hippopotamus'), 4);
      expect(getToeCountForSpecies('cape buffalo'), 2);
    });

    test('species without track data resolve to null', () {
      // Birds / reptiles / rodents are not track-relevant in the spoor
      // classifier, so the seeder omits all five fields for them.
      expect(getTrackMorphologyForSpecies('domestic goat'), isNull);
      expect(getToeCountForSpecies('domestic goat'), isNull);
      expect(getTrackMorphologyForSpecies('nile crocodile'), isNull);
    });

    test('lookup is case-insensitive and trims whitespace', () {
      final m = getTrackMorphologyForSpecies('  Greater Kudu  ');
      expect(m, isNotNull);
      expect(m!.toeCount, 2);
      expect(getToeCountForSpecies('IMPALA'), 2);
    });

    test('underscore alias keys also resolve (to-do spec convention)', () {
      expect(getToeCountForSpecies('greater_kudu'), 2);
      expect(getToeCountForSpecies('blue_wildebeest'), 2);
      expect(getToeCountForSpecies('black_wildebeest'), 2);
      expect(getToeCountForSpecies('red_hartebeest'), 2);
      expect(getToeCountForSpecies('cape_buffalo'), 2);
    });
  });

  group('Track taxonomy — speciesCategoryMap coverage', () {
    test('every canonical seeder species maps to a category', () {
      // The seeder's canonical species (by CSV common name) must all be
      // resolvable through the spoor taxonomy so the classifier and the
      // Firestore dataset never disagree.
      for (final species in [
        'Leopard',
        'Lion',
        'Cheetah',
        'Caracal',
        'Serval',
        'Kudu',
        'Impala',
        'Gemsbok',
        'Eland',
        'Warthog',
        'Bushpig',
        'Nyala',
        'Springbok',
        'Blesbok',
        'Bontebok',
        'Hartebeest',
        'Blue Wildebeest',
        'Black Wildebeest',
        'Roan Antelope',
        'Sable Antelope',
        'Bushbuck',
        'Duiker',
        'Steenbok',
        'Oribi',
        'Reedbuck',
        'Suni',
        'Tsessebe',
        'Waterbuck',
        'Giraffe',
        'Dik-dik',
        'Cape Buffalo',
        'Zebra',
        'Donkey',
        'Horse',
      ]) {
        expect(categoryForSpecies(species), isNotNull,
            reason: '$species should resolve to a category');
      }
    });

    test('toeCountForCategory matches the seeder toe counts', () {
      expect(toeCountForCategory(TrackCategory.pawCarnivore), 4);
      expect(toeCountForCategory(TrackCategory.clovenHoofUngulate), 2);
      expect(toeCountForCategory(TrackCategory.solidHoofEquine), 1);
    });

    test('categoryForSpecies toe count agrees with the seeder dataset', () {
      // A species' seeder toe count must equal the toe count of the
      // category the spoor classifier assigns it to.
      final checks = <String, int>{
        'Leopard': 4,
        'Lion': 4,
        'Cheetah': 4,
        'Kudu': 2,
        'Impala': 2,
        'Gemsbok': 2,
        'Eland': 2,
        'Cape Buffalo': 2,
        'Zebra': 1,
        'Donkey': 1,
        'Horse': 1,
      };
      checks.forEach((species, expectedToes) {
        final category = categoryForSpecies(species);
        expect(toeCountForCategory(category), expectedToes,
            reason: '$species category toe count must match the seeder');
      });
    });

    test('unknown species still defaults to cloven-hoofed ungulate', () {
      expect(categoryForSpecies('Mystery Animal'),
          TrackCategory.clovenHoofUngulate);
    });
  });

  group('Seed version — spoor morphology migration', () {
    test('gameGuideSeedVersion is the v3 migration tag', () {
      expect(gameGuideSeedVersion, 'game_guide_seed_v3');
    });
  });
}
