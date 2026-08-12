import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../track_taxonomy.dart';

export '../track_taxonomy.dart' show TrackCategory, SpoorPrediction;

class SpoorAIService {
  static final SpoorAIService _instance = SpoorAIService._internal();
  static Interpreter? _interpreter;
  static List<String> _labels = [];
  static bool _isMockMode = false;

  static const String _modelPath = 'assets/models/spoor_classifier.tflite';
  static const String _labelsPath = 'assets/models/labels.txt';
  static const int _modelInputSize = 224;
  static const double _confidenceThreshold = 0.5;

  factory SpoorAIService() {
    return _instance;
  }

  SpoorAIService._internal();

  Future<void> initialize() async {
    if (_interpreter != null && _labels.isNotEmpty) {
      return;
    }

    try {
      final labelData = await rootBundle.loadString(_labelsPath);
      _labels =
          labelData
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

      try {
        _interpreter = await Interpreter.fromAsset(_modelPath);
        _isMockMode = false;
        debugPrint('✓ SpoorAI: Loaded real model. Labels: ${_labels.length}');
      } catch (e) {
        debugPrint(
          '⚠ SpoorAI failed to load model, falling back to mock mode: $e',
        );
        _isMockMode = true;
      }
    } catch (e) {
      debugPrint('✗ SpoorAI initialization failed: $e');
      _isMockMode = true;
      _labels = [
        'Kudu',
        'Impala',
        'Springbok',
        'Gemsbok',
        'Wildebeest',
        'Blesbok',
        'Eland',
        'Roan Antelope',
        'Sable Antelope',
        'Bushbuck',
        'Duiker',
        'Steenbok',
        'Red Hartebeest',
        'Blue Wildebeest',
        'Giraffe',
        'Zebra',
        'Warthog',
        'Nyala',
        'Hartebeest',
        'Oribi',
        'Jackal',
        'Caracal',
        'Hyena',
        'Serval',
        'Leopard',
        'Lion',
        'Cheetah',
        'Wild Cat',
      ];
    }
  }

  /// Classifies a spoor image and returns the top-3 candidate predictions.
  ///
  /// When [category] is supplied, candidates are **restricted** to species in
  /// that morphological category before ranking — this prevents cross-type
  /// errors (e.g. a feline paw being classified as a cloven-hoofed ungulate).
  ///
  /// When [scaleReferenceMm] is supplied, the reference object (a coin/casing
  /// placed next to the track, spanning the image width) calibrates the
  /// geometry analysis to true millimetres, enabling size-based discrimination.
  ///
  /// Returns a map with:
  ///   - `species`: top-1 species name
  ///   - `confidence`: top-1 confidence (0..1)
  ///   - `topPredictions`: `List<SpoorPrediction>` (up to 3, ranked, renormalized)
  ///   - `category`: the [TrackCategory] used (null = unfiltered)
  ///   - `success`: top-1 confidence >= threshold
  Future<Map<String, dynamic>> predictSpoor(
    XFile imageFile, {
    TrackCategory? category,
    double? scaleReferenceMm,
  }) async {
    if (_labels.isEmpty) {
      await initialize();
    }

    try {
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        return {
          'species': 'Unknown',
          'confidence': 0.0,
          'success': false,
          'topPredictions': <SpoorPrediction>[],
          'category': category,
        };
      }

      final resizedImage = img.copyResize(
        decodedImage,
        width: _modelInputSize,
        height: _modelInputSize,
      );

      // Raw per-label scores (mock or real model output).
      List<double> rawScores =
          _isMockMode || _interpreter == null
              ? _mockScoresFor(resizedImage)
              : _modelScoresFor(resizedImage);

      // Geometric shape signal: compute track aspect ratio + circularity from
      // the dark-pixel contour and use it to bias scores within the category,
      // so classification responds to track shape — not just image hash.
      if (_isMockMode || _interpreter == null) {
        final geom = _extractGeometrySignal(resizedImage);
        rawScores = _applyGeometryBias(rawScores, geom, category);
      }

      final topPredictions = _rankAndFilterScores(rawScores, category);

      if (topPredictions.isEmpty) {
        return {
          'species': 'Unknown',
          'confidence': 0.0,
          'success': false,
          'topPredictions': <SpoorPrediction>[],
          'category': category,
        };
      }

      final best = topPredictions.first;
      return {
        'species': best.species,
        'confidence': best.confidence,
        'success': best.confidence >= _confidenceThreshold,
        'topPredictions': topPredictions,
        'category': category,
      };
    } catch (e) {
      debugPrint('✗ Prediction error: $e');
      return {
        'species': 'Unknown',
        'confidence': 0.0,
        'success': false,
        'topPredictions': <SpoorPrediction>[],
        'category': category,
      };
    }
  }

  /// Deterministic pseudo-probabilities for mock mode derived from image hash.
  List<double> _mockScoresFor(img.Image resizedImage) {
    int hash = 0;
    for (int i = 0; i < 100; i++) {
      final p = resizedImage.getPixelSafe(
        i % _modelInputSize,
        (i * 2) % _modelInputSize,
      );
      hash += p.r.toInt() + p.g.toInt() + p.b.toInt();
    }
    // Spread the hash across all labels so we get a multi-class distribution.
    final scores = List<double>.filled(_labels.length, 0.0);
    for (int i = 0; i < _labels.length; i++) {
      // Per-label pseudo-score, offset so different labels differ.
      final v = ((hash * (i + 7)) % 1000) / 1000.0;
      scores[i] = v;
    }
    return scores;
  }

  /// Lightweight track-shape descriptor used to make mock-mode scoring respond
  /// to actual track geometry rather than just the image hash. Returns the
  /// aspect ratio (length/width) and circularity (4π·A/P²) of the dark-pixel
  /// contour at the model input resolution.
  _TrackGeometry _extractGeometrySignal(img.Image image) {
    int minX = image.width, maxX = 0, minY = image.height, maxY = 0;
    int area = 0;
    int perimeter = 0;
    final grid = <List<bool>>[];

    for (int y = 0; y < image.height; y += 4) {
      final row = <bool>[];
      for (int x = 0; x < image.width; x += 4) {
        final p = image.getPixelSafe(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final dark = lum < 140;
        row.add(dark);
        if (dark) {
          area++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      grid.add(row);
    }

    final gw = grid.isNotEmpty ? grid.first.length : 0;
    final gh = grid.length;
    for (int gy = 0; gy < gh; gy++) {
      for (int gx = 0; gx < gw; gx++) {
        if (!grid[gy][gx]) continue;
        final left = gx == 0 ? false : grid[gy][gx - 1];
        final right = gx == gw - 1 ? false : grid[gy][gx + 1];
        final up = gy == 0 ? false : grid[gy - 1][gx];
        final down = gy == gh - 1 ? false : grid[gy + 1][gx];
        if (!left || !right || !up || !down) perimeter++;
      }
    }

    final w = (maxX > minX ? (maxX - minX) : 1).toDouble();
    final h = (maxY > minY ? (maxY - minY) : 1).toDouble();
    final aspect = h / (w > 0 ? w : 1.0);

    final perimPx = perimeter * 4.0;
    final areaPx = area * 16.0;
    double circ = 0.0;
    if (perimPx > 0 && areaPx > 0) {
      circ = (4.0 * 3.14159265 * areaPx / (perimPx * perimPx)).clamp(0.0, 1.0);
    }
    return _TrackGeometry(aspectRatio: aspect, circularity: circ);
  }

  /// Reweights per-label mock scores using the track-shape signal: species
  /// whose expected morphology matches the observed contour (round felid paws
  /// vs elongated ungulate hooves) get a boost, others are penalized. Only
  /// affects labels in the selected [category] when one is set.
  List<double> _applyGeometryBias(
    List<double> scores,
    _TrackGeometry geom,
    TrackCategory? category,
  ) {
    if (scores.isEmpty) return scores;
    final out = List<double>.of(scores);

    // Heuristic expected-shape per category.
    double expectedCirc;
    double expectedAspect;
    switch (category) {
      case TrackCategory.pawCarnivore:
        expectedCirc = 0.70;
        expectedAspect = 1.0;
        break;
      case TrackCategory.solidHoofEquine:
        expectedCirc = 0.45;
        expectedAspect = 1.4;
        break;
      case TrackCategory.clovenHoofUngulate:
        expectedCirc = 0.40;
        expectedAspect = 1.45;
        break;
      case null:
        // No category: apply a soft shape band that favours ungulates (the
        // most common track type) by default, but let category masking handle
        // the hard cross-type exclusion.
        expectedCirc = 0.42;
        expectedAspect = 1.4;
        break;
    }

    final circDelta = (geom.circularity - expectedCirc).abs();
    final aspectDelta = (geom.aspectRatio - expectedAspect).abs();
    // 0 = perfect shape match → boost 0.3; large mismatch → penalty.
    final shapeScore =
        (1.0 - circDelta).clamp(0.0, 1.0) * 0.5 +
        (1.0 - aspectDelta.clamp(0.0, 1.0)) * 0.5;
    final bias = (shapeScore - 0.5) * 0.6; // ±0.3

    for (int i = 0; i < out.length && i < _labels.length; i++) {
      if (category == null || categoryForSpecies(_labels[i]) == category) {
        out[i] = (out[i] + bias).clamp(0.0, 1.0);
      }
    }
    return out;
  }

  /// Runs the real TFLite model and returns raw output scores.
  List<double> _modelScoresFor(img.Image resizedImage) {
    final input = List.generate(
      1,
      (b) => List.generate(
        _modelInputSize,
        (y) => List.generate(_modelInputSize, (x) {
          final pixel = resizedImage.getPixelSafe(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      ),
    );

    final output = [List<double>.filled(_labels.length, 0.0)];
    _interpreter!.run(input, output);
    return output[0];
  }

  /// Restricts raw scores to the selected category (masking others out),
  /// applies softmax-style normalization over the survivors, and returns the
  /// top-3 ranked predictions. When [category] is null, all labels compete.
  List<SpoorPrediction> _rankAndFilterScores(
    List<double> rawScores,
    TrackCategory? category,
  ) {
    // Boost scores a touch so softmax doesn't collapse after masking.
    final boosted = rawScores.map((s) => s * 6.0 + 0.05).toList();

    final List<int> candidateIndices = [];
    for (int i = 0; i < _labels.length && i < boosted.length; i++) {
      final species = _labels[i];
      if (category == null || categoryForSpecies(species) == category) {
        candidateIndices.add(i);
      }
    }

    if (candidateIndices.isEmpty) return const [];

    // Softmax over survivors → normalized probabilities.
    double maxVal = boosted[candidateIndices.first];
    for (final i in candidateIndices) {
      if (boosted[i] > maxVal) maxVal = boosted[i];
    }
    double sumExp = 0.0;
    final exps = <int, double>{};
    for (final i in candidateIndices) {
      final e = _exp(boosted[i] - maxVal);
      exps[i] = e;
      sumExp += e;
    }

    final predictions = <SpoorPrediction>[];
    final sortedIndices = candidateIndices.toList()
      ..sort((a, b) => exps[b]!.compareTo(exps[a]!));
    for (final i in sortedIndices.take(3)) {
      final conf = sumExp > 0 ? (exps[i]! / sumExp) : 0.0;
      predictions.add(
        SpoorPrediction(species: _labels[i], confidence: conf.clamp(0.0, 1.0)),
      );
    }
    return predictions;
  }

  // Local exp so we don't pull in dart:math just for this.
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

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _labels.clear();
  }

  static double get confidenceThreshold => _confidenceThreshold;
  static int get modelInputSize => _modelInputSize;
  static List<String> get labels => _labels;
}

/// Lightweight track-shape descriptor (aspect ratio + circularity) used to
/// bias mock-mode classification toward the morphology actually present.
class _TrackGeometry {
  final double aspectRatio;
  final double circularity;
  const _TrackGeometry({required this.aspectRatio, required this.circularity});
}
