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
  /// Returns a map with:
  ///   - `species`: top-1 species name
  ///   - `confidence`: top-1 confidence (0..1)
  ///   - `topPredictions`: `List<SpoorPrediction>` (up to 3, ranked, renormalized)
  ///   - `category`: the [TrackCategory] used (null = unfiltered)
  ///   - `success`: top-1 confidence >= threshold
  Future<Map<String, dynamic>> predictSpoor(
    XFile imageFile, {
    TrackCategory? category,
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
      final List<double> rawScores =
          _isMockMode || _interpreter == null
              ? _mockScoresFor(resizedImage)
              : _modelScoresFor(resizedImage);

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
