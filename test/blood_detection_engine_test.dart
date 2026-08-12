import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/blood_detection_engine.dart';

void main() {
  group('BloodDetectionEngine', () {
    test('detects saturated red pixels as blood', () {
      // 8×8 image, all pure red (255,0,0).
      final rgba = Uint8List.fromList([
        for (int i = 0; i < 64; i++) ...[255, 0, 0, 255],
      ]);
      final engine = BloodDetectionEngine(
        thresholds: const BloodDetectionThresholds(gridSize: 4),
      );
      final result = engine.detect(
        rgba: rgba,
        width: 8,
        height: 8,
        bytesPerPixel: 4,
      );
      expect(result.hasDetection, isTrue);
      expect(result.detectionCount, 16); // all 4×4 cells flagged
      expect(result.detectionRatio, closeTo(1.0, 0.01));
    });

    test('does not flag green/brown background (foliage) as blood', () {
      // 8×8 image, all green (0,180,0) — saturated but not red.
      final rgba = Uint8List.fromList([
        for (int i = 0; i < 64; i++) ...[0, 180, 0, 255],
      ]);
      final engine = BloodDetectionEngine(
        thresholds: const BloodDetectionThresholds(gridSize: 4),
      );
      final result = engine.detect(
        rgba: rgba,
        width: 8,
        height: 8,
        bytesPerPixel: 4,
      );
      expect(result.detectionCount, 0);
      expect(result.hasDetection, isFalse);
    });

    test('flags only the red region in a mixed image', () {
      // 8×8: left half red, right half green.
      final rgba = Uint8List(8 * 8 * 4);
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          final idx = (y * 8 + x) * 4;
          if (x < 4) {
            rgba[idx] = 200;
            rgba[idx + 1] = 20;
            rgba[idx + 2] = 20;
          } else {
            rgba[idx] = 20;
            rgba[idx + 1] = 180;
            rgba[idx + 2] = 20;
          }
          rgba[idx + 3] = 255;
        }
      }
      final engine = BloodDetectionEngine(
        thresholds: const BloodDetectionThresholds(gridSize: 4),
      );
      final result = engine.detect(
        rgba: rgba,
        width: 8,
        height: 8,
        bytesPerPixel: 4,
      );
      // Left two columns of the 4×4 grid should be flagged.
      int leftHits = 0;
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 2; x++) {
          if (result.mask[y][x]) leftHits++;
        }
      }
      expect(leftHits, 8); // 2 columns × 4 rows
      // Right columns must not be flagged.
      for (int y = 0; y < 4; y++) {
        expect(result.mask[y][3], isFalse);
      }
    });

    test('increasing saturation threshold suppresses detection', () {
      // Dim/desaturated red: (140, 60, 60) — low saturation.
      final rgba = Uint8List.fromList([
        for (int i = 0; i < 64; i++) ...[140, 60, 60, 255],
      ]);
      final engine = BloodDetectionEngine(
        thresholds: const BloodDetectionThresholds(
          gridSize: 4,
          minSaturation: 0.85, // demanding
        ),
      );
      final result = engine.detect(
        rgba: rgba,
        width: 8,
        height: 8,
        bytesPerPixel: 4,
      );
      expect(result.detectionCount, 0);
    });

    test('handles empty / degenerate buffers safely', () {
      final engine = BloodDetectionEngine();
      final result = engine.detect(
        rgba: Uint8List(0),
        width: 0,
        height: 0,
      );
      expect(result.detectionCount, 0);
      expect(result.detectionRatio, 0);
    });

    test('yuv420ToRgbaGrid converts a uniform YUV frame correctly', () {
      // Uniform mid-grey Y=128, U=V=128 (neutral). Expect R≈G≈B≈128.
      const w = 8, h = 8;
      final y = Uint8List.fromList([for (int i = 0; i < w * h; i++) 128]);
      final uv = Uint8List.fromList([for (int i = 0; i < (w * h) ~/ 4; i++) 128]);
      final rgba = BloodDetectionEngine.yuv420ToRgbaGrid(
        yPlane: y,
        uPlane: uv,
        vPlane: uv,
        width: w,
        height: h,
        uvRowStride: w ~/ 2,
        uvPixelStride: 1,
        targetGridSize: 4,
      );
      // Sample one pixel: channels should all be ~128 (±2).
      expect(rgba[0], closeTo(128, 3));
      expect(rgba[1], closeTo(128, 3));
      expect(rgba[2], closeTo(128, 3));
      expect(rgba[3], 255);
    });
  });
}
