import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jagspoor/features/track/data/spoor_track_attributes.dart';
import 'package:jagspoor/features/track/data/spoor_validation_layer.dart';
import 'package:jagspoor/features/track/data/track_taxonomy.dart';

/// Builds a square image with a dark (track) shape on a light background.
/// [shape] = 'round' (filled disc) or 'elongated' (tall filled rect).
img.Image buildTrackImage(String shape) {
  const size = 200;
  final image = img.Image(width: size, height: size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      image.setPixelRgb(x, y, 210, 195, 160);
    }
  }
  const cx = size ~/ 2;
  const cy = size ~/ 2;
  if (shape == 'round') {
    const r = 40;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dx = x - cx, dy = y - cy;
        if (dx * dx + dy * dy <= r * r) {
          image.setPixelRgb(x, y, 60, 50, 40);
        }
      }
    }
  } else {
    for (int y = cy - 50; y < cy + 50; y++) {
      for (int x = cx - 18; x < cx + 18; x++) {
        image.setPixelRgb(x, y, 60, 50, 40);
      }
    }
  }
  return image;
}

/// A round paw-like track: high circularity, aspect ratio ~1.0.
const roundPaw = SpoorTrackAttributes(
  printLengthMm: 40,
  printWidthMm: 40,
  aspectRatio: 1.0,
  circularity: 0.70,
  toeAlignmentAngle: 0,
  clawDeltaProfile: 0,
  perimeterComplexity: 0.1,
  boundingBoxWidthPx: 40,
  boundingBoxHeightPx: 40,
  contourPerimeterPx: 140,
  contourAreaPx: 1600,
);

/// An elongated hoof-like track: low circularity, aspect ratio >1.4.
const elongatedHoof = SpoorTrackAttributes(
  printLengthMm: 60,
  printWidthMm: 40,
  aspectRatio: 1.45,
  circularity: 0.40,
  toeAlignmentAngle: 20,
  clawDeltaProfile: 0,
  perimeterComplexity: 0.1,
  boundingBoxWidthPx: 20,
  boundingBoxHeightPx: 60,
  contourPerimeterPx: 140,
  contourAreaPx: 1200,
);

void main() {
  group('SpoorTrackAttributes', () {
    test('hasUsableContour is true only when a real contour exists', () {
      expect(roundPaw.hasUsableContour, isTrue);
      expect(elongatedHoof.hasUsableContour, isTrue);
      const empty = SpoorTrackAttributes(
        printLengthMm: 0,
        printWidthMm: 0,
        aspectRatio: 1,
        circularity: 0,
        toeAlignmentAngle: 0,
        clawDeltaProfile: 0,
        perimeterComplexity: 0,
        boundingBoxWidthPx: 0,
        boundingBoxHeightPx: 0,
      );
      expect(empty.hasUsableContour, isFalse);
    });

    test('fromImage extracts a usable contour for a round track', () {
      final attrs = SpoorTrackAttributes.fromImage(buildTrackImage('round'));
      expect(attrs.hasUsableContour, isTrue);
      // A filled disc is near-circular.
      expect(attrs.circularity, greaterThan(0.5));
      expect(attrs.aspectRatio, closeTo(1.0, 0.35));
      expect(attrs.boundingBoxWidthPx, greaterThan(0));
      expect(attrs.boundingBoxHeightPx, greaterThan(0));
    });

    test('fromImage elongated track has lower circularity than round', () {
      final round = SpoorTrackAttributes.fromImage(buildTrackImage('round'));
      final elong = SpoorTrackAttributes.fromImage(buildTrackImage('elongated'));
      expect(elong.circularity, lessThan(round.circularity));
      expect(elong.aspectRatio, greaterThan(round.aspectRatio));
    });
  });

  group('SpoorValidationLayer', () {
    test('empty predictions yield a neutral result', () {
      final result = SpoorValidationLayer.classifySpoorTrackValidated(
        rawPredictions: const [],
        attributes: roundPaw,
      );
      expect(result.reRankedPredictions, isEmpty);
      expect(result.wasCorrected, isFalse);
      expect(result.wasReRanked, isFalse);
      expect(result.usedMorphology, isFalse);
      expect(result.note, contains('No AI predictions'));
    });

    test('no usable contour keeps the AI ranking as-is', () {
      const empty = SpoorTrackAttributes(
        printLengthMm: 0,
        printWidthMm: 0,
        aspectRatio: 1,
        circularity: 0,
        toeAlignmentAngle: 0,
        clawDeltaProfile: 0,
        perimeterComplexity: 0,
        boundingBoxWidthPx: 0,
        boundingBoxHeightPx: 0,
      );
      const raw = [
        SpoorPrediction(species: 'Leopard', confidence: 0.8),
        SpoorPrediction(species: 'Kudu', confidence: 0.2),
      ];
      final result = SpoorValidationLayer.classifySpoorTrackValidated(
        rawPredictions: raw,
        attributes: empty,
      );
      expect(result.reRankedPredictions.map((p) => p.species),
          ['Leopard', 'Kudu']);
      expect(result.wasCorrected, isFalse);
      expect(result.wasReRanked, isFalse);
      expect(result.usedMorphology, isFalse);
      expect(result.note, contains('No usable track contour'));
    });

    test('round paw track corrects a raw ungulate top-1 to a carnivore', () {
      // Raw AI ranks the ungulate first, but the measured geometry is a round
      // paw — the validation layer should promote the carnivore.
      const raw = [
        SpoorPrediction(species: 'Kudu', confidence: 0.7),
        SpoorPrediction(species: 'Leopard', confidence: 0.3),
      ];
      final result = SpoorValidationLayer.classifySpoorTrackValidated(
        rawPredictions: raw,
        attributes: roundPaw,
      );
      expect(result.usedMorphology, isTrue);
      expect(result.wasCorrected, isTrue);
      expect(result.topSpecies, 'Leopard');
      expect(result.reRankedPredictions.first.species, 'Leopard');
      expect(result.note, contains('corrected'));
    });

    test('elongated hoof track corrects a raw carnivore top-1 to an ungulate',
        () {
      const raw = [
        SpoorPrediction(species: 'Leopard', confidence: 0.7),
        SpoorPrediction(species: 'Kudu', confidence: 0.3),
      ];
      final result = SpoorValidationLayer.classifySpoorTrackValidated(
        rawPredictions: raw,
        attributes: elongatedHoof,
      );
      expect(result.usedMorphology, isTrue);
      expect(result.wasCorrected, isTrue);
      expect(result.topSpecies, 'Kudu');
      expect(result.note, contains('corrected'));
    });

    test('re-ranking keeps the top-1 but changes the order below it', () {
      // A round-paw geometry scores both carnivores at 1.0 but the ungulate
      // lower, so Wild Cat jumps above Kudu while the top-1 (Leopard) stays.
      const raw = [
        SpoorPrediction(species: 'Leopard', confidence: 0.7),
        SpoorPrediction(species: 'Kudu', confidence: 0.2),
        SpoorPrediction(species: 'Wild Cat', confidence: 0.1),
      ];
      final result = SpoorValidationLayer.classifySpoorTrackValidated(
        rawPredictions: raw,
        attributes: roundPaw,
      );
      expect(result.usedMorphology, isTrue);
      expect(result.wasCorrected, isFalse);
      expect(result.wasReRanked, isTrue);
      expect(result.topSpecies, 'Leopard');
      expect(result.reRankedPredictions.map((p) => p.species),
          ['Leopard', 'Wild Cat', 'Kudu']);
      expect(result.note, contains('re-ranked'));
    });

    test('matching morphology confirms the AI ranking (no change)', () {
      const raw = [
        SpoorPrediction(species: 'Kudu', confidence: 0.8),
        SpoorPrediction(species: 'Impala', confidence: 0.2),
      ];
      final result = SpoorValidationLayer.classifySpoorTrackValidated(
        rawPredictions: raw,
        attributes: elongatedHoof,
      );
      expect(result.usedMorphology, isTrue);
      expect(result.wasCorrected, isFalse);
      expect(result.wasReRanked, isFalse);
      expect(result.topSpecies, 'Kudu');
      expect(result.note, contains('confirmed'));
    });

    test('topConfidence reflects the validated top-1', () {
      const raw = [
        SpoorPrediction(species: 'Kudu', confidence: 0.7),
        SpoorPrediction(species: 'Leopard', confidence: 0.3),
      ];
      final result = SpoorValidationLayer.classifySpoorTrackValidated(
        rawPredictions: raw,
        attributes: roundPaw,
      );
      expect(result.topConfidence, closeTo(0.3, 0.001));
    });

    test('renormalize scales confidences back to a 1.0 sum', () {
      const raw = [
        SpoorPrediction(species: 'Kudu', confidence: 0.7),
        SpoorPrediction(species: 'Leopard', confidence: 0.3),
      ];
      final normalized = SpoorValidationLayer.renormalize(raw);
      final sum =
          normalized.fold<double>(0.0, (a, p) => a + p.confidence);
      expect(sum, closeTo(1.0, 0.001));
      expect(normalized.map((p) => p.species), ['Kudu', 'Leopard']);
    });

    test('renormalize is a no-op for an empty or zero-sum list', () {
      expect(SpoorValidationLayer.renormalize(const []), isEmpty);
      const zeroSum = [SpoorPrediction(species: 'Kudu', confidence: 0)];
      final out = SpoorValidationLayer.renormalize(zeroSum);
      expect(out.length, 1);
      expect(out.first.confidence, 0);
    });
  });
}
