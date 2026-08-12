import 'dart:typed_data';

/// Adjustable thresholds for the HSV red/hemoglobin blood detection mask.
///
/// Blood (oxyhemoglobin) reads as a saturated red in HSV space: hue close to 0°
/// (which wraps around 360°), high saturation, and moderate-to-high value.
class BloodDetectionThresholds {
  /// Half-width of the red hue window around 0°/180°. A value of 15 means
  /// hues in [0,15] ∪ [165,180] are considered red.
  final double redHueTolerance;

  /// Minimum saturation (0..1) for a pixel to count as blood.
  final double minSaturation;

  /// Minimum value/brightness (0..1) for a pixel to count as blood.
  final double minValue;

  /// Downsample grid resolution (cells per axis). Higher = finer mask, more CPU.
  final int gridSize;

  const BloodDetectionThresholds({
    this.redHueTolerance = 15.0,
    this.minSaturation = 0.45,
    this.minValue = 0.20,
    this.gridSize = 64,
  });

  BloodDetectionThresholds copyWith({
    double? redHueTolerance,
    double? minSaturation,
    double? minValue,
    int? gridSize,
  }) {
    return BloodDetectionThresholds(
      redHueTolerance: redHueTolerance ?? this.redHueTolerance,
      minSaturation: minSaturation ?? this.minSaturation,
      minValue: minValue ?? this.minValue,
      gridSize: gridSize ?? this.gridSize,
    );
  }
}

/// Result of a single blood-detection pass over one camera frame.
class BloodDetectionResult {
  /// Grid mask: `mask[y][x]` is true where blood-colored pixels dominate that cell.
  final List<List<bool>> mask;

  /// Number of positive cells.
  final int detectionCount;

  /// Fraction of the grid flagged as blood (0..1).
  final double detectionRatio;

  /// Grid resolution per axis.
  final int gridSize;

  const BloodDetectionResult({
    required this.mask,
    required this.detectionCount,
    required this.detectionRatio,
    required this.gridSize,
  });

  bool get hasDetection => detectionCount > 0;
}

/// Per-pixel HSV red/hemoglobin mask engine. Operates on raw RGB(A) byte
/// buffers so it is fully unit-testable without a live camera.
///
/// The camera screen feeds YUV420 frames converted to a flat RGBA byte list;
/// any RGB source works (file, synthetic, stream).
class BloodDetectionEngine {
  BloodDetectionThresholds thresholds;

  BloodDetectionEngine({this.thresholds = const BloodDetectionThresholds()});

  /// Detect blood-colored pixels in an [rgba] buffer of [width]×[height] and
  /// return a downsampled boolean grid plus summary statistics.
  ///
  /// [rgba] is a flat list of bytes in R,G,B,(A) order. Channels-per-pixel is
  /// inferred from [bytesPerPixel] (3 = RGB, 4 = RGBA).
  BloodDetectionResult detect({
    required Uint8List rgba,
    required int width,
    required int height,
    int bytesPerPixel = 4,
  }) {
    final grid = thresholds.gridSize;
    final mask = List<List<bool>>.generate(
        grid, (_) => List<bool>.filled(grid, false));

    if (width <= 0 || height <= 0 || rgba.length < bytesPerPixel) {
      return BloodDetectionResult(
          mask: mask, detectionCount: 0, detectionRatio: 0, gridSize: grid);
    }

    final cellW = width / grid;
    final cellH = height / grid;
    final tol = thresholds.redHueTolerance.clamp(0.0, 90.0);
    final satMin = thresholds.minSaturation.clamp(0.0, 1.0);
    final valMin = thresholds.minValue.clamp(0.0, 1.0);

    int count = 0;

    for (int gy = 0; gy < grid; gy++) {
      for (int gx = 0; gx < grid; gx++) {
        final x0 = (gx * cellW).floor();
        final y0 = (gy * cellH).floor();
        final x1 = ((gx + 1) * cellW).floor().clamp(0, width);
        final y1 = ((gy + 1) * cellH).floor().clamp(0, height);

        int sampleCount = 0;
        int redHits = 0;

        // Sample up to a few pixels per cell for performance.
        for (int sy = y0; sy < y1; sy += 2) {
          for (int sx = x0; sx < x1; sx += 2) {
            final idx = (sy * width + sx) * bytesPerPixel;
            if (idx + 2 >= rgba.length) continue;
            final r = rgba[idx];
            final g = rgba[idx + 1];
            final b = rgba[idx + 2];
            sampleCount++;

            final hsv = _rgbToHsv(r, g, b);
            final hue = hsv[0]; // 0..360
            final sat = hsv[1]; // 0..1
            final val = hsv[2]; // 0..1

            final isRed = hue <= tol || hue >= (360.0 - tol);
            if (isRed && sat >= satMin && val >= valMin) {
              redHits++;
            }
          }
        }

        // Cell is flagged if a majority of its samples are blood-colored.
        final flagged = sampleCount > 0 && (redHits / sampleCount) >= 0.5;
        mask[gy][gx] = flagged;
        if (flagged) count++;
      }
    }

    final ratio = (grid * grid) > 0 ? count / (grid * grid) : 0.0;
    return BloodDetectionResult(
      mask: mask,
      detectionCount: count,
      detectionRatio: ratio,
      gridSize: grid,
    );
  }

  /// Converts 8-bit RGB to HSV. Returns [hue(0..360), sat(0..1), val(0..1)].
  static List<double> _rgbToHsv(int r, int g, int b) {
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;

    final max = _max3(rf, gf, bf);
    final min = _min3(rf, gf, bf);
    final delta = max - min;

    final v = max;
    final s = max == 0 ? 0.0 : delta / max;

    double h;
    if (delta == 0) {
      h = 0;
    } else if (max == rf) {
      h = 60.0 * (((gf - bf) / delta) % 6);
    } else if (max == gf) {
      h = 60.0 * (((bf - rf) / delta) + 2);
    } else {
      h = 60.0 * (((rf - gf) / delta) + 4);
    }
    if (h < 0) h += 360.0;

    return [h, s, v];
  }

  static double _max3(double a, double b, double c) =>
      a >= b ? (a >= c ? a : c) : (b >= c ? b : c);
  static double _min3(double a, double b, double c) =>
      a <= b ? (a <= c ? a : c) : (b <= c ? b : c);

  /// Converts a YUV420 camera frame (Y, U, V planes) into a flat RGBA byte
  /// list at [targetGridSize]×[targetGridSize] resolution for detection.
  /// This keeps per-frame CPU cost bounded regardless of camera resolution.
  static Uint8List yuv420ToRgbaGrid({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int width,
    required int height,
    required int uvRowStride,
    required int uvPixelStride,
    int targetGridSize = 64,
  }) {
    final grid = targetGridSize;
    final out = Uint8List(grid * grid * 4);
    final cellW = width / grid;
    final cellH = height / grid;

    for (int gy = 0; gy < grid; gy++) {
      for (int gx = 0; gx < grid; gx++) {
        final x = (gx * cellW).floor().clamp(0, width - 1);
        final y = (gy * cellH).floor().clamp(0, height - 1);

        final yIdx = y * width + x;
        if (yIdx >= yPlane.length) continue;
        final yVal = yPlane[yIdx].toDouble();

        final uvX = (x ~/ 2).clamp(0, (width ~/ 2) - 1);
        final uvY = (y ~/ 2).clamp(0, (height ~/ 2) - 1);
        final uIdx = uvY * uvRowStride + uvX * uvPixelStride;
        final vIdx = uvY * uvRowStride + uvX * uvPixelStride;

        if (uIdx >= uPlane.length || vIdx >= vPlane.length) continue;
        final uVal = uPlane[uIdx].toDouble() - 128.0;
        final vVal = vPlane[vIdx].toDouble() - 128.0;

        // BT.601 YUV → RGB
        var r = yVal + 1.402 * vVal;
        var g = yVal - 0.344 * uVal - 0.714 * vVal;
        var b = yVal + 1.772 * uVal;

        final outIdx = (gy * grid + gx) * 4;
        out[outIdx] = r.clamp(0, 255).round();
        out[outIdx + 1] = g.clamp(0, 255).round();
        out[outIdx + 2] = b.clamp(0, 255).round();
        out[outIdx + 3] = 255;
      }
    }
    return out;
  }
}
