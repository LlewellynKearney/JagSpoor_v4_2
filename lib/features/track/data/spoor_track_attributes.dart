import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Physical track attributes derived from the captured frame's bounding box.
///
/// These describe the dark-pixel contour (the track print) in both pixel and
/// millimetre terms, and are the morphological inputs the
/// [SpoorValidationLayer] uses to sanity-check / re-rank the raw AI output.
class SpoorTrackAttributes {
  /// Track print length in millimetres (calibrated when a scale reference is
  /// supplied, otherwise estimated via a focal-scaling constant).
  final double printLengthMm;

  /// Track print width in millimetres.
  final double printWidthMm;

  /// Length / width ratio — >1.3 suggests an elongated hoof, ~1.0 a round paw.
  final double aspectRatio;

  /// Contour circularity 4π·A/P² — 1.0 is a perfect circle.
  final double circularity;

  /// Toe-alignment angle derived from the bounding box diagonal.
  final double toeAlignmentAngle;

  /// Red/blue colour-delta profile of the track pixels.
  final double clawDeltaProfile;

  /// Perimeter complexity of the bounding box.
  final double perimeterComplexity;

  /// Raw bounding-box width in pixels.
  final double boundingBoxWidthPx;

  /// Raw bounding-box height in pixels.
  final double boundingBoxHeightPx;

  /// Contour perimeter in pixels.
  final double contourPerimeterPx;

  /// Contour area in pixels.
  final int contourAreaPx;

  const SpoorTrackAttributes({
    required this.printLengthMm,
    required this.printWidthMm,
    required this.aspectRatio,
    required this.circularity,
    required this.toeAlignmentAngle,
    required this.clawDeltaProfile,
    required this.perimeterComplexity,
    required this.boundingBoxWidthPx,
    required this.boundingBoxHeightPx,
    this.contourPerimeterPx = 0.0,
    this.contourAreaPx = 0,
  });

  /// True when a usable track contour could be extracted (a non-zero bounding
  /// box with a positive area). Validation is neutral when this is false.
  bool get hasUsableContour =>
      boundingBoxWidthPx > 0 && boundingBoxHeightPx > 0 && contourAreaPx > 0;

  /// Extracts track attributes from a decoded image by analysing the dark
  /// (track) pixel contour and, when [scaleReferenceMm] is supplied,
  /// calibrating the pixel dimensions to true millimetres.
  ///
  /// Dark pixels (luminance below 140) form the track region. Its bounding
  /// box yields the print length/width; the contour perimeter + area yield
  /// circularity — round felid paws score near 1.0 while elongated ungulate
  /// hooves score well below.
  static SpoorTrackAttributes fromImage(
    img.Image image, {
    double? scaleReferenceMm,
  }) {
    final imgWidth = image.width;
    final imgHeight = image.height;

    const sampleStep = 4;
    final grid = <List<bool>>[];
    int totalR = 0, totalB = 0;
    int pixelCount = 0;
    int minX = imgWidth, maxX = 0, minY = imgHeight, maxY = 0;

    for (int y = 0; y < imgHeight; y += sampleStep) {
      final row = <bool>[];
      for (int x = 0; x < imgWidth; x += sampleStep) {
        final pixel = image.getPixelSafe(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        final isDark = luminance < 140;
        row.add(isDark);
        if (isDark) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          totalR += r;
          totalB += b;
          pixelCount++;
        }
      }
      grid.add(row);
    }

    final boundingBoxWidthPx =
        (maxX > minX ? (maxX - minX) : 50).toDouble();
    final boundingBoxHeightPx =
        (maxY > minY ? (maxY - minY) : 60).toDouble();

    // Pixels-per-mm calibration. With a scale reference the user places the
    // reference object (coin/casing) so it spans the full image width.
    final double pxPerMm;
    if (scaleReferenceMm != null && scaleReferenceMm > 0) {
      pxPerMm = imgWidth / scaleReferenceMm;
    } else {
      pxPerMm = 1.0 / 0.475; // legacy focal-scaling constant (~0.45-0.50).
    }

    final printWidthMm = (boundingBoxWidthPx / pxPerMm).clamp(20.0, 300.0);
    final printLengthMm = (boundingBoxHeightPx / pxPerMm).clamp(20.0, 300.0);

    final toeAlignmentAngle =
        (math.atan2(boundingBoxHeightPx, boundingBoxWidthPx) * 180.0 /
                math.pi) %
            45.0;

    final clawDeltaProfile = ((totalR - totalB).abs() /
            (pixelCount > 0 ? pixelCount : 1))
        .clamp(0.0, 15.0);

    // --- True contour geometry: perimeter (boundary length) + area (fill) ---
    int area = 0;
    int perimeter = 0;
    final gridW = grid.isNotEmpty ? grid.first.length : 0;
    final gridH = grid.length;
    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        if (!grid[gy][gx]) continue;
        area++;
        final left = gx == 0 ? false : grid[gy][gx - 1];
        final right = gx == gridW - 1 ? false : grid[gy][gx + 1];
        final up = gy == 0 ? false : grid[gy - 1][gx];
        final down = gy == gridH - 1 ? false : grid[gy + 1][gx];
        if (!left || !right || !up || !down) {
          perimeter++;
        }
      }
    }

    final contourPerimeterPx = perimeter * sampleStep.toDouble();
    final contourAreaPx = area * (sampleStep * sampleStep);

    double circularity = 0.0;
    if (contourPerimeterPx > 0 && contourAreaPx > 0) {
      circularity = (4.0 *
              math.pi *
              contourAreaPx.toDouble() /
              (contourPerimeterPx * contourPerimeterPx))
          .clamp(0.0, 1.0);
    }

    final aspectRatio =
        printLengthMm / (printWidthMm > 0 ? printWidthMm : 1.0);
    final perimeterComplexity =
        ((boundingBoxWidthPx + boundingBoxHeightPx) * 2.0) /
        (boundingBoxWidthPx * boundingBoxHeightPx + 1.0);

    return SpoorTrackAttributes(
      printLengthMm: printLengthMm,
      printWidthMm: printWidthMm,
      aspectRatio: aspectRatio,
      circularity: circularity,
      toeAlignmentAngle: toeAlignmentAngle,
      clawDeltaProfile: clawDeltaProfile,
      perimeterComplexity: perimeterComplexity,
      boundingBoxWidthPx: boundingBoxWidthPx,
      boundingBoxHeightPx: boundingBoxHeightPx,
      contourPerimeterPx: contourPerimeterPx,
      contourAreaPx: contourAreaPx,
    );
  }

  /// Convenience async factory that reads + decodes an [XFile] then delegates
  /// to [fromImage]. Returns an empty (non-usable) attribute set when the
  /// image cannot be decoded, so validation degrades gracefully.
  static Future<SpoorTrackAttributes> fromXFile(
    XFile file, {
    double? scaleReferenceMm,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const SpoorTrackAttributes(
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
      }
      return fromImage(decoded, scaleReferenceMm: scaleReferenceMm);
    } catch (_) {
      return const SpoorTrackAttributes(
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
    }
  }
}
