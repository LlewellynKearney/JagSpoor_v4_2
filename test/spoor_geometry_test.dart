import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:jagspoor/features/hunter_mode/services/spoor_identifier_service.dart';
import 'package:jagspoor/features/track/data/track_taxonomy.dart';

void main() {
  group('SpoorIdentifierService geometry', () {
    late Directory tmpDir;

    setUp(() => tmpDir = Directory.systemTemp.createTempSync('spoor_test_'));
    tearDown(() => tmpDir.delete(recursive: true));

    /// Builds a square image with a dark (track) shape on a light background.
    /// [shape] = 'round' (filled disc) or 'elongated' (tall filled rect).
    img.Image buildTrackImage(String shape) {
      const size = 200;
      final image = img.Image(width: size, height: size);
      // Light sandy background (luminance well above 140 → not "track").
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          image.setPixelRgb(x, y, 210, 195, 160);
        }
      }
      // Dark track pixels (luminance < 140).
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
        // Elongated vertical rectangle (hoof-like).
        for (int y = cy - 50; y < cy + 50; y++) {
          for (int x = cx - 18; x < cx + 18; x++) {
            image.setPixelRgb(x, y, 60, 50, 40);
          }
        }
      }
      return image;
    }

    Future<XFile> writePng(img.Image image, String name) async {
      final path = '${tmpDir.path}/$name.png';
      final bytes = img.encodePng(image);
      await File(path).writeAsBytes(bytes);
      return XFile(path);
    }

    test('returns top-3 predictions for a round track', () async {
      final service = SpoorIdentifierService.instance;
      final xfile = await writePng(buildTrackImage('round'), 'round');
      final result = await service.classifySpoorTrack(
        xfile,
        category: TrackCategory.pawCarnivore,
      );
      expect(result['success'], isNotNull);
      final top = result['topPredictions'] as List;
      expect(top.length, lessThanOrEqualTo(3));
      expect(top.length, greaterThan(0));
      final metrics = result['metrics'] as SpoorGeometricMetrics;
      // Round disc → aspect ratio near 1.0.
      expect(metrics.aspectRatio, closeTo(1.0, 0.35));
      // A filled disc has a well-defined, positive circularity.
      expect(metrics.circularity, greaterThan(0));
    });

    test('elongated track has lower circularity than round track', () async {
      final service = SpoorIdentifierService.instance;
      final roundFile = await writePng(buildTrackImage('round'), 'round2');
      final elongFile = await writePng(buildTrackImage('elongated'), 'elong');

      final roundRes =
          await service.classifySpoorTrack(roundFile, category: null);
      final elongRes =
          await service.classifySpoorTrack(elongFile, category: null);

      final roundM = roundRes['metrics'] as SpoorGeometricMetrics;
      final elongM = elongRes['metrics'] as SpoorGeometricMetrics;

      // Elongated hoof: aspect ratio clearly > round's.
      expect(elongM.aspectRatio, greaterThan(roundM.aspectRatio + 0.4));
      // Circular (round) track should be more circular than the elongated one.
      expect(roundM.circularity, greaterThan(elongM.circularity));
    });

    test('scaleReferenceMm produces plausible mm dimensions', () async {
      final service = SpoorIdentifierService.instance;
      // Round disc ~80px diameter in a 200px image. With a 26mm reference
      // spanning the full width → ~0.13mm/px → disc ≈ 80*0.13 ≈ 10.4mm.
      final xfile = await writePng(buildTrackImage('round'), 'scaled');
      final result = await service.classifySpoorTrack(
        xfile,
        scaleReferenceMm: 26.0,
      );
      final metrics = result['metrics'] as SpoorGeometricMetrics;
      // Both dimensions should be positive and below the full-image width
      // (26mm reference), i.e. a sub-frame disc must be < 26mm.
      expect(metrics.printLengthMm, greaterThan(0));
      expect(metrics.printWidthMm, greaterThan(0));
      expect(metrics.printLengthMm, lessThan(26.0));
    });

    test('category restriction prevents cross-type ranking', () async {
      final service = SpoorIdentifierService.instance;
      final xfile = await writePng(buildTrackImage('round'), 'cat');
      // Restrict to solid-hoof equines: candidates must all be equine.
      final result = await service.classifySpoorTrack(
        xfile,
        category: TrackCategory.solidHoofEquine,
      );
      final top = result['topPredictions'] as List<SpoorPrediction>;
      for (final p in top) {
        expect(categoryForSpecies(p.species), TrackCategory.solidHoofEquine);
      }
    });
  });
}
