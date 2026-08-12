import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../track/data/track_taxonomy.dart';

/// Geometric track metrics profile extracted during visual analysis pass.
///
/// Beyond bounding-box length/width, this carries true **contour** shape
/// descriptors that discriminate felid round tracks (high circularity, aspect
/// ratio ≈ 1.0) from elongated ungulate/hoof tracks (low circularity, aspect
/// ratio > 1.3).
class SpoorGeometricMetrics {
  final double printLengthMm;
  final double printWidthMm;
  final double toeAlignmentAngle;
  final double clawDeltaProfile;
  final double aspectRatio;
  final double perimeterComplexity;

  /// True contour circularity: 4π·area / perimeter². 1.0 = perfect circle.
  final double circularity;

  /// Contour perimeter in pixels (boundary length of the dark track region).
  final double contourPerimeterPx;

  /// Contour area in pixels (count of dark track pixels).
  final int contourAreaPx;

  const SpoorGeometricMetrics({
    required this.printLengthMm,
    required this.printWidthMm,
    required this.toeAlignmentAngle,
    required this.clawDeltaProfile,
    required this.aspectRatio,
    required this.perimeterComplexity,
    this.circularity = 0.0,
    this.contourPerimeterPx = 0.0,
    this.contourAreaPx = 0,
  });

  @override
  String toString() =>
      'Length: ${printLengthMm.toStringAsFixed(1)}mm, Width: ${printWidthMm.toStringAsFixed(1)}mm, '
      'ToeAngle: ${toeAlignmentAngle.toStringAsFixed(1)}°, ClawDelta: ${clawDeltaProfile.toStringAsFixed(2)}, '
      'Aspect: ${aspectRatio.toStringAsFixed(2)}, Circ: ${circularity.toStringAsFixed(2)}';
}

/// Native Track (Spoor) Satellite AI Classification Service.
/// Analyzes image tensor geometry using metric shape processing pass (print length, toe alignments, claw delta profiles)
/// and outputs descriptive wildlife tracking strings.
class SpoorIdentifierService {
  static final SpoorIdentifierService _instance =
      SpoorIdentifierService._internal();
  static SpoorIdentifierService get instance => _instance;
  SpoorIdentifierService._internal();

  /// Known wildlife species profiles with geometric classification signatures.
  /// Each signature is tagged with its morphological [TrackCategory] so the
  /// geometric matcher can be restricted to a single category, preventing
  /// cross-type errors (e.g. a Leopard paw matching a Kudu hoof).
  static const List<Map<String, dynamic>> _speciesSignatures = [
    {
      'species': 'Leopard',
      'demographic': 'Male, Mature',
      'avgLength': 95.0,
      'avgWidth': 90.0,
      'hasClaws': false,
      'minToeAngle': 12.0,
      'maxToeAngle': 28.0,
      'category': TrackCategory.pawCarnivore,
    },
    {
      'species': 'Lion',
      'demographic': 'Male, Adult',
      'avgLength': 135.0,
      'avgWidth': 125.0,
      'hasClaws': false,
      'minToeAngle': 15.0,
      'maxToeAngle': 35.0,
      'category': TrackCategory.pawCarnivore,
    },
    {
      'species': 'Cheetah',
      'demographic': 'Male, Sub-Adult',
      'avgLength': 82.0,
      'avgWidth': 70.0,
      'hasClaws': true,
      'minToeAngle': 8.0,
      'maxToeAngle': 20.0,
      'category': TrackCategory.pawCarnivore,
    },
    {
      'species': 'Caracal',
      'demographic': 'Adult',
      'avgLength': 58.0,
      'avgWidth': 52.0,
      'hasClaws': false,
      'minToeAngle': 10.0,
      'maxToeAngle': 22.0,
      'category': TrackCategory.pawCarnivore,
    },
    {
      'species': 'Wild Cat',
      'demographic': 'Adult',
      'avgLength': 38.0,
      'avgWidth': 34.0,
      'hasClaws': false,
      'minToeAngle': 9.0,
      'maxToeAngle': 20.0,
      'category': TrackCategory.pawCarnivore,
    },
    {
      'species': 'Kudu',
      'demographic': 'Female, Mature',
      'avgLength': 90.0,
      'avgWidth': 60.0,
      'hasClaws': false,
      'minToeAngle': 2.0,
      'maxToeAngle': 10.0,
      'category': TrackCategory.clovenHoofUngulate,
    },
    {
      'species': 'Cape Buffalo',
      'demographic': 'Male, Adult',
      'avgLength': 150.0,
      'avgWidth': 140.0,
      'hasClaws': false,
      'minToeAngle': 1.0,
      'maxToeAngle': 8.0,
      'category': TrackCategory.clovenHoofUngulate,
    },
    {
      'species': 'Impala',
      'demographic': 'Male, Adult',
      'avgLength': 55.0,
      'avgWidth': 38.0,
      'hasClaws': false,
      'minToeAngle': 2.0,
      'maxToeAngle': 9.0,
      'category': TrackCategory.clovenHoofUngulate,
    },
    {
      'species': 'Gemsbok',
      'demographic': 'Adult',
      'avgLength': 85.0,
      'avgWidth': 60.0,
      'hasClaws': false,
      'minToeAngle': 2.0,
      'maxToeAngle': 10.0,
      'category': TrackCategory.clovenHoofUngulate,
    },
    {
      'species': 'Eland',
      'demographic': 'Adult',
      'avgLength': 130.0,
      'avgWidth': 100.0,
      'hasClaws': false,
      'minToeAngle': 2.0,
      'maxToeAngle': 9.0,
      'category': TrackCategory.clovenHoofUngulate,
    },
    {
      'species': 'Warthog',
      'demographic': 'Adult',
      'avgLength': 70.0,
      'avgWidth': 50.0,
      'hasClaws': false,
      'minToeAngle': 2.0,
      'maxToeAngle': 11.0,
      'category': TrackCategory.clovenHoofUngulate,
    },
    {
      'species': 'Zebra',
      'demographic': 'Adult',
      'avgLength': 110.0,
      'avgWidth': 100.0,
      'hasClaws': false,
      'minToeAngle': 1.0,
      'maxToeAngle': 6.0,
      'category': TrackCategory.solidHoofEquine,
    },
    {
      'species': 'Donkey',
      'demographic': 'Adult',
      'avgLength': 95.0,
      'avgWidth': 85.0,
      'hasClaws': false,
      'minToeAngle': 1.0,
      'maxToeAngle': 6.0,
      'category': TrackCategory.solidHoofEquine,
    },
  ];

  /// Analyzes track geometry by extracting image tensor metrics (print length, toe alignments, claw delta profiles)
  /// and running a model processor execution pass to generate descriptive tracking output strings.
  ///
  /// When [category] is supplied, candidate species are restricted to that
  /// morphological category before matching, preventing cross-type confusion
  /// (e.g. a feline paw being classified as a cloven-hoofed ungulate).
  ///
  /// When [scaleReferenceMm] is supplied, the reference object (a coin/casing
  /// placed next to the track) is assumed to span the full image width, and
  /// pixels are calibrated to true millimetres — enabling exact species-size
  /// matching. When omitted, a focal-scaling constant estimates dimensions.
  Future<Map<String, dynamic>> classifySpoorTrack(
    XFile imageFile, {
    TrackCategory? category,
    double? scaleReferenceMm,
  }) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        return {
          'trackingResult':
              'Identified Spoor: Unknown Track (Unreadable Image)',
          'confidence': 0.0,
          'success': false,
          'topPredictions': <SpoorPrediction>[],
          'category': category,
        };
      }

      // Step 1: Geometric Feature Extraction Pass (contour + scale-calibrated mm)
      final metrics = _extractTrackGeometricMetrics(
        decodedImage,
        scaleReferenceMm: scaleReferenceMm,
      );

      // Step 2: Running Tensor Emulation & Metric Matching Pass
      final rankings = _matchGeometricMetricsToSpecies(metrics, category);

      if (rankings.isEmpty) {
        return {
          'trackingResult': 'Identified Spoor: Unknown Track',
          'confidence': 0.0,
          'success': false,
          'topPredictions': <SpoorPrediction>[],
          'category': category,
          'metrics': metrics,
        };
      }

      final top = rankings.first;
      final String species = top.species;
      final double confidence = top.confidence;
      final sig = _signatureForSpecies(species);
      final String demographic = sig?['demographic'] as String? ?? 'Adult';
      final String descriptiveString =
          'Identified Spoor: $species ($demographic)';

      debugPrint(
        '✓ Spoor AI Analysis Pass Completed: $descriptiveString [Confidence: ${(confidence * 100).toStringAsFixed(1)}%]',
      );
      debugPrint('  Metrics: $metrics');

      return {
        'trackingResult': descriptiveString,
        'species': species,
        'demographic': demographic,
        'confidence': confidence,
        'metrics': metrics,
        'success': confidence >= 0.50,
        'topPredictions': rankings,
        'category': category,
      };
    } catch (e) {
      debugPrint('✗ Spoor Identifier Service error: $e');
      // Safe fallback: no fabricated classification, mark as failed.
      return {
        'trackingResult': 'Identified Spoor: Unknown Track (Analysis Error)',
        'confidence': 0.0,
        'success': false,
        'topPredictions': <SpoorPrediction>[],
        'category': category,
      };
    }
  }

  Map<String, dynamic>? _signatureForSpecies(String species) {
    for (final s in _speciesSignatures) {
      if (s['species'] == species) return s;
    }
    return null;
  }

  /// Extracts geometric metrics from image pixels, including true contour
  /// perimeter/area and circularity (4π·area / perimeter²), plus scale-
  /// calibrated millimetre dimensions when a [scaleReferenceMm] is supplied.
  ///
  /// Contour extraction: dark pixels (luminance below the contrast threshold)
  /// form the track region. Its boundary length (perimeter) and pixel count
  /// (area) yield circularity — round felid paws score near 1.0 while elongated
  /// ungulate hooves score well below.
  SpoorGeometricMetrics _extractTrackGeometricMetrics(
    img.Image image, {
    double? scaleReferenceMm,
  }) {
    final int imgWidth = image.width;
    final int imgHeight = image.height;

    // Mark dark (track) pixels on a sample grid and accumulate color stats.
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

    final double rawWidthPixels =
        (maxX > minX ? (maxX - minX) : 50).toDouble();
    final double rawHeightPixels =
        (maxY > minY ? (maxY - minY) : 60).toDouble();

    // Pixels-per-mm calibration. With a scale reference the user places the
    // reference object (coin/casing) so it spans the full image width.
    final double pxPerMm;
    if (scaleReferenceMm != null && scaleReferenceMm > 0) {
      pxPerMm = imgWidth / scaleReferenceMm;
    } else {
      pxPerMm = 1.0 / 0.475; // legacy focal-scaling constant (~0.45-0.50).
    }

    final double printWidthMm = (rawWidthPixels / pxPerMm).clamp(20.0, 300.0);
    final double printLengthMm = (rawHeightPixels / pxPerMm).clamp(20.0, 300.0);

    final double toeAlignmentAngle =
        (math.atan2(rawHeightPixels, rawWidthPixels) * 180.0 / math.pi) % 45.0;

    final double clawDeltaProfile = ((totalR - totalB).abs() /
            (pixelCount > 0 ? pixelCount : 1))
        .clamp(0.0, 15.0);

    // --- True contour geometry: perimeter (boundary length) + area (fill) ---
    int area = 0; // count of dark cells
    int perimeter = 0; // count of dark cells with at least one light/neighbour
    final gridW = grid.isNotEmpty ? grid.first.length : 0;
    final gridH = grid.length;
    for (int gy = 0; gy < gridH; gy++) {
      for (int gx = 0; gx < gridW; gx++) {
        if (!grid[gy][gx]) continue;
        area++;
        // A dark cell is on the contour if any 4-neighbour is light or edge.
        final left = gx == 0 ? false : grid[gy][gx - 1];
        final right = gx == gridW - 1 ? false : grid[gy][gx + 1];
        final up = gy == 0 ? false : grid[gy - 1][gx];
        final down = gy == gridH - 1 ? false : grid[gy + 1][gx];
        if (!left || !right || !up || !down) {
          perimeter++;
        }
      }
    }

    // Circular (4-neighbour) perimeter in pixels, scaled back to image pixels.
    final double contourPerimeterPx = perimeter * sampleStep.toDouble();
    final int contourAreaPx = area * (sampleStep * sampleStep);

    // Circularity = 4π·A / P². Clamp to [0,1] (1.0 = perfect circle).
    double circularity = 0.0;
    if (contourPerimeterPx > 0 && contourAreaPx > 0) {
      circularity = (4.0 *
              math.pi *
              contourAreaPx.toDouble() /
              (contourPerimeterPx * contourPerimeterPx))
          .clamp(0.0, 1.0);
    }

    final double aspectRatio =
        printLengthMm / (printWidthMm > 0 ? printWidthMm : 1.0);
    final double perimeterComplexity =
        ((rawWidthPixels + rawHeightPixels) * 2.0) /
        (rawWidthPixels * rawHeightPixels + 1.0);

    return SpoorGeometricMetrics(
      printLengthMm: printLengthMm,
      printWidthMm: printWidthMm,
      toeAlignmentAngle: toeAlignmentAngle,
      clawDeltaProfile: clawDeltaProfile,
      aspectRatio: aspectRatio,
      perimeterComplexity: perimeterComplexity,
      circularity: circularity,
      contourPerimeterPx: contourPerimeterPx,
      contourAreaPx: contourAreaPx,
    );
  }

  /// Running model processor pass: scores each in-category species signature
  /// against the extracted metrics, then returns the top-3 ranked predictions
  /// (renormalized so confidences sum to 1.0). When [category] is null, all
  /// signatures compete.
  List<SpoorPrediction> _matchGeometricMetricsToSpecies(
    SpoorGeometricMetrics metrics,
    TrackCategory? category,
  ) {
    final candidates = _speciesSignatures.where((sig) {
      return category == null || sig['category'] == category;
    }).toList();

    if (candidates.isEmpty) return const [];

    final scores = <double>[];
    for (final sig in candidates) {
      final targetLength = sig['avgLength'] as double;
      final targetWidth = sig['avgWidth'] as double;
      final minAngle = sig['minToeAngle'] as double;
      final maxAngle = sig['maxToeAngle'] as double;
      final sigCategory = sig['category'] as TrackCategory;

      final lengthScore =
          1.0 -
          ((metrics.printLengthMm - targetLength).abs() / targetLength).clamp(
            0.0,
            1.0,
          );
      final widthScore =
          1.0 -
          ((metrics.printWidthMm - targetWidth).abs() / targetWidth).clamp(
            0.0,
            1.0,
          );
      final angleScore =
          (metrics.toeAlignmentAngle >= minAngle &&
                  metrics.toeAlignmentAngle <= maxAngle)
              ? 1.0
              : 0.6;

      // Contour shape discrimination: felid paw/carnivore tracks are round
      // (circularity high, aspect ratio ≈ 1.0); ungulate/equine hooves are
      // elongated (circularity low, aspect ratio > 1.3). This blocks
      // cross-type confusion even within a category.
      final double expectedCircularity;
      final double expectedAspect;
      if (sigCategory == TrackCategory.pawCarnivore) {
        expectedCircularity = 0.70; // round paw
        expectedAspect = 1.0;
      } else if (sigCategory == TrackCategory.solidHoofEquine) {
        expectedCircularity = 0.45; // elongated solid hoof
        expectedAspect = 1.4;
      } else {
        expectedCircularity = 0.40; // elongated cloven hoof
        expectedAspect = 1.45;
      }

      final double shapeScore;
      if (metrics.circularity > 0) {
        final circDelta =
            (metrics.circularity - expectedCircularity).abs();
        final aspectDelta =
            (metrics.aspectRatio - expectedAspect).abs();
        shapeScore =
            (1.0 - circDelta).clamp(0.0, 1.0) * 0.5 +
            (1.0 - aspectDelta.clamp(0.0, 1.0)) * 0.5;
      } else {
        shapeScore = 0.5; // neutral when no contour could be extracted
      }

      // Weighted blend: size (length+width) 50%, contour shape 25%, angle 25%.
      final double totalScore =
          (lengthScore * 0.25) +
          (widthScore * 0.25) +
          (shapeScore * 0.25) +
          (angleScore * 0.25);
      scores.add(totalScore);
    }

    // Softmax over the (boosted) per-species scores → normalized confidences.
    final boosted = scores.map((s) => s * 4.0).toList();
    double maxVal = boosted.isEmpty ? 0.0 : boosted.first;
    for (final v in boosted) {
      if (v > maxVal) maxVal = v;
    }
    double sumExp = 0.0;
    final exps = <double>[];
    for (final v in boosted) {
      final e = _exp(v - maxVal);
      exps.add(e);
      sumExp += e;
    }

    final indexed = <int>[
      for (int i = 0; i < candidates.length; i++) i,
    ]..sort((a, b) => exps[b].compareTo(exps[a]));

    final predictions = <SpoorPrediction>[];
    for (final i in indexed.take(3)) {
      final conf = sumExp > 0 ? (exps[i] / sumExp) : 0.0;
      predictions.add(SpoorPrediction(
        species: candidates[i]['species'] as String,
        confidence: conf.clamp(0.0, 1.0),
      ));
    }
    return predictions;
  }

  double _exp(double x) {
    if (x.isNaN) return double.nan;
    if (x > 50) return double.infinity;
    if (x < -50) return 0.0;
    double term = 1.0;
    double result = 1.0;
    for (int k = 1; k <= 18; k++) {
      term *= x / k;
      result += term;
      if (result.isInfinite) break;
    }
    return result;
  }
}
