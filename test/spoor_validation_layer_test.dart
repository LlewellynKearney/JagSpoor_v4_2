import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:jagspoor/features/track/data/services/spoor_validation_layer.dart';
import 'package:jagspoor/features/track/data/spoor_track_attributes.dart';
import 'package:jagspoor/features/track/data/track_taxonomy.dart';

void main() {
  setUp(() => SpoorValidationLayer.resetTestSeams());
  tearDown(() => SpoorValidationLayer.resetTestSeams());

  group('SpoorTrackAttributes fallback table', () {
    test('covers the classifier species with toe counts + dimension ranges',
        () {
      // Paw/carnivore → 4 toes.
      expect(spoorTrackAttributesFallback['Leopard']!.toeCount, 4);
      expect(spoorTrackAttributesFallback['Lion']!.toeCount, 4);
      expect(spoorTrackAttributesFallback['Cheetah']!.toeCount, 4);
      // Cloven-hoofed → 2 cleaves.
      expect(spoorTrackAttributesFallback['Kudu']!.toeCount, 2);
      expect(spoorTrackAttributesFallback['Impala']!.toeCount, 2);
      expect(spoorTrackAttributesFallback['Gemsbok']!.toeCount, 2);
      // Solid-hoofed → 1 wall.
      expect(spoorTrackAttributesFallback['Zebra']!.toeCount, 1);
      expect(spoorTrackAttributesFallback['Donkey']!.toeCount, 1);
    });

    test('every fallback entry has a positive dimension range', () {
      for (final entry in spoorTrackAttributesFallback.entries) {
        final a = entry.value;
        expect(a.lengthMaxMm, greaterThan(a.lengthMinMm),
            reason: '${entry.key} length range');
        expect(a.widthMaxMm, greaterThan(a.widthMinMm),
            reason: '${entry.key} width range');
        expect(a.toeCount, greaterThan(0), reason: '${entry.key} toes');
      }
    });

    test('fallback category matches the taxonomy map', () {
      for (final entry in spoorTrackAttributesFallback.entries) {
        expect(
          entry.value.category,
          categoryForSpecies(entry.key),
          reason: '${entry.key} category mismatch',
        );
      }
    });
  });

  group('SpoorTrackAttributes.fromMap', () {
    test('hydrates DB fields and prefers them over the fallback', () {
      final attrs = SpoorTrackAttributes.fromMap(
        {
          'toeCount': 4,
          'trackLengthMinMm': 90,
          'trackLengthMaxMm': 110,
          'trackWidthMinMm': 80,
          'trackWidthMaxMm': 95,
        },
        species: 'Leopard',
      );
      expect(attrs.toeCount, 4);
      expect(attrs.lengthMinMm, 90);
      expect(attrs.lengthMaxMm, 110);
      expect(attrs.widthMinMm, 80);
      expect(attrs.widthMaxMm, 95);
    });

    test('tolerates snake_case aliases', () {
      final attrs = SpoorTrackAttributes.fromMap(
        {
          'toe_count': 2,
          'track_length_min_mm': '50',
          'track_length_max_mm': '65',
          'track_width_min_mm': '32',
          'track_width_max_mm': '42',
        },
        species: 'Impala',
      );
      expect(attrs.toeCount, 2);
      expect(attrs.lengthMinMm, 50);
      expect(attrs.lengthMaxMm, 65);
      expect(attrs.widthMinMm, 32);
      expect(attrs.widthMaxMm, 42);
    });

    test('falls back to the built-in table for a partial document', () {
      final attrs = SpoorTrackAttributes.fromMap(
        const {'toeCount': 2},
        species: 'Kudu',
      );
      // Toe count from DB; dimensions from fallback.
      expect(attrs.toeCount, 2);
      expect(attrs.lengthMaxMm, greaterThan(0));
    });

    test('anySpoorFieldPresent detects spoor fields', () {
      expect(
        SpoorTrackAttributes.anySpoorFieldPresent(const {'toeCount': 2}),
        isTrue,
      );
      expect(
        SpoorTrackAttributes.anySpoorFieldPresent(
          const {'track_width_max_mm': 42},
        ),
        isTrue,
      );
      expect(
        SpoorTrackAttributes.anySpoorFieldPresent(const {'name': 'Kudu'}),
        isFalse,
      );
    });
  });

  group('SpoorValidationLayer.estimateToeCount', () {
    test('geometry toe count wins when present', () {
      expect(
        SpoorValidationLayer.estimateToeCount(
          geometryToeCount: 4,
          category: TrackCategory.clovenHoofUngulate,
        ),
        4,
      );
    });

    test('category prior applies when geometry is unknown', () {
      expect(
        SpoorValidationLayer.estimateToeCount(
          geometryToeCount: 0,
          category: TrackCategory.pawCarnivore,
        ),
        4,
      );
      expect(
        SpoorValidationLayer.estimateToeCount(
          geometryToeCount: 0,
          category: TrackCategory.clovenHoofUngulate,
        ),
        2,
      );
      expect(
        SpoorValidationLayer.estimateToeCount(
          geometryToeCount: 0,
          category: TrackCategory.solidHoofEquine,
        ),
        1,
      );
    });

    test('null when both geometry and category are unknown', () {
      expect(
        SpoorValidationLayer.estimateToeCount(
          geometryToeCount: 0,
          category: null,
        ),
        isNull,
      );
    });
  });

  group('SpoorValidationLayer.validateCandidate', () {
    const leopard = SpoorTrackAttributes(
      species: 'Leopard',
      toeCount: 4,
      lengthMinMm: 85,
      lengthMaxMm: 105,
      widthMinMm: 80,
      widthMaxMm: 100,
      category: TrackCategory.pawCarnivore,
    );

    test('passes when toe count + dimensions are compatible', () {
      final m = SpoorValidationLayer.validateCandidate(
        species: 'Leopard',
        attributes: leopard,
        estimatedToeCount: 4,
        printLengthMm: 95,
        printWidthMm: 90,
      );
      expect(m.passed, isTrue);
      expect(m.checked, isTrue);
    });

    test('rejects a toe-count mismatch (the strongest discriminator)', () {
      final m = SpoorValidationLayer.validateCandidate(
        species: 'Leopard',
        attributes: leopard,
        estimatedToeCount: 2,
        printLengthMm: 95,
        printWidthMm: 90,
      );
      expect(m.passed, isFalse);
      expect(m.reason, contains('toe count'));
    });

    test('rejects an out-of-range length', () {
      final m = SpoorValidationLayer.validateCandidate(
        species: 'Leopard',
        attributes: leopard,
        estimatedToeCount: 4,
        printLengthMm: 200,
        printWidthMm: 90,
      );
      expect(m.passed, isFalse);
      expect(m.reason, contains('length'));
    });

    test('rejects an out-of-range width', () {
      final m = SpoorValidationLayer.validateCandidate(
        species: 'Leopard',
        attributes: leopard,
        estimatedToeCount: 4,
        printLengthMm: 95,
        printWidthMm: 180,
      );
      expect(m.passed, isFalse);
      expect(m.reason, contains('width'));
    });

    test('unknown toe count (0) does not reject on toes', () {
      final m = SpoorValidationLayer.validateCandidate(
        species: 'Leopard',
        attributes: leopard,
        estimatedToeCount: 0,
        printLengthMm: 95,
        printWidthMm: 90,
      );
      expect(m.passed, isTrue);
    });
  });

  group('SpoorValidationLayer.validatePredictions (re-ranking)', () {
    test('keeps the raw top when it passes validation', () async {
      final layer = SpoorValidationLayer.instance;
      final outcome = await layer.validatePredictions(
        predictions: const [
          SpoorPrediction(species: 'Leopard', confidence: 0.9),
          SpoorPrediction(species: 'Lion', confidence: 0.1),
        ],
        estimatedToeCount: 4,
        printLengthMm: 95,
        printWidthMm: 90,
      );
      expect(outcome.validatedTopSpecies, 'Leopard');
      expect(outcome.reranked, isFalse);
      expect(outcome.databaseChecked, isTrue);
    });

    test('re-ranks when the raw top fails toe-count validation', () async {
      final layer = SpoorValidationLayer.instance;
      final outcome = await layer.validatePredictions(
        predictions: const [
          // Leopard needs 4 toes but the track has 2 → rejected.
          SpoorPrediction(species: 'Leopard', confidence: 0.9),
          SpoorPrediction(species: 'Kudu', confidence: 0.1),
        ],
        estimatedToeCount: 2,
        printLengthMm: 90,
        printWidthMm: 60,
      );
      expect(outcome.validatedTopSpecies, 'Kudu');
      expect(outcome.reranked, isTrue);
      expect(outcome.note, contains('Leopard'));
    });

    test('database attributes are preferred over the fallback', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('animals').add({
        'name': 'Leopard',
        'toeCount': 4,
        'trackLengthMinMm': 90,
        'trackLengthMaxMm': 110,
      });
      SpoorValidationLayer.firestoreForTesting = fs;

      final layer = SpoorValidationLayer.instance;
      final attrs = await layer.attributesForSpecies('Leopard');
      expect(attrs, isNotNull);
      // DB range wins over the fallback 85–105.
      expect(attrs!.lengthMinMm, 90);
      expect(attrs.lengthMaxMm, 110);
    });

    test('falls back to built-in attributes when Firestore has no record',
        () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('animals').add({'name': 'Kudu'});
      SpoorValidationLayer.firestoreForTesting = fs;

      final layer = SpoorValidationLayer.instance;
      final attrs = await layer.attributesForSpecies('Kudu');
      expect(attrs, isNotNull);
      expect(attrs!.toeCount, 2);
    });

    test('empty predictions produce an empty outcome', () async {
      final layer = SpoorValidationLayer.instance;
      final outcome = await layer.validatePredictions(
        predictions: const [],
        estimatedToeCount: 0,
        printLengthMm: null,
        printWidthMm: null,
      );
      expect(outcome.validatedTopSpecies, '');
      expect(outcome.databaseChecked, isFalse);
    });
  });
}
