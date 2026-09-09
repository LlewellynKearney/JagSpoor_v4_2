import 'track_taxonomy.dart';
import 'spoor_track_attributes.dart';

/// Result of running the morphological validation layer over a raw AI
/// prediction set.
///
/// The validation layer does not invent new species — it *re-ranks* the
/// candidates the AI already returned, using the measured track geometry
/// (aspect ratio + contour circularity) to promote the candidate whose
/// expected morphology best matches the observed track, and demote the rest.
class SpoorValidationResult {
  /// The re-ranked candidate list (same species as the raw input, new order).
  final List<SpoorPrediction> reRankedPredictions;

  /// True when the top-1 species changed after validation (a correction).
  final bool wasCorrected;

  /// True when the relative order of the top-3 changed (a re-ranking).
  final bool wasReRanked;

  /// True when the validation layer had enough morphology to act.
  final bool usedMorphology;

  /// Human-readable note explaining what the validation layer did.
  final String note;

  const SpoorValidationResult({
    required this.reRankedPredictions,
    required this.wasCorrected,
    required this.wasReRanked,
    required this.usedMorphology,
    required this.note,
  });

  /// The validated top-1 species (falls back to the raw top-1 when the
  /// re-ranked list is empty).
  String get topSpecies =>
      reRankedPredictions.isNotEmpty ? reRankedPredictions.first.species : '';

  /// The validated top-1 confidence.
  double get topConfidence =>
      reRankedPredictions.isNotEmpty ? reRankedPredictions.first.confidence : 0.0;
}

/// Expected morphological profile of a species, derived from the same
/// geometric taxonomy the [SpoorIdentifierService] uses.
class _SpeciesMorphology {
  final double expectedCircularity;
  final double expectedAspectRatio;

  const _SpeciesMorphology({
    required this.expectedCircularity,
    required this.expectedAspectRatio,
  });
}

/// Morphological validation layer for the spoor classification pipeline.
///
/// Takes the raw top-3 AI predictions and the measured
/// [SpoorTrackAttributes] (computed from the captured frame's dark-pixel
/// contour) and re-ranks the candidates so the species whose expected track
/// morphology best matches the observed geometry rises to the top. This is a
/// *validation* pass — it corrects the AI's ranking when the measured track
/// shape contradicts the raw model output, and it is neutral (no-op) when no
/// usable contour could be extracted.
class SpoorValidationLayer {
  SpoorValidationLayer._();

  /// Expected morphology per morphological [TrackCategory]. Mirrors the
  /// expected-shape heuristics used by the AI service + identifier service so
  /// the validation layer agrees with the rest of the pipeline.
  static const Map<TrackCategory, _SpeciesMorphology> _categoryMorphology = {
    TrackCategory.pawCarnivore: _SpeciesMorphology(
      expectedCircularity: 0.70,
      expectedAspectRatio: 1.0,
    ),
    TrackCategory.solidHoofEquine: _SpeciesMorphology(
      expectedCircularity: 0.45,
      expectedAspectRatio: 1.4,
    ),
    TrackCategory.clovenHoofUngulate: _SpeciesMorphology(
      expectedCircularity: 0.40,
      expectedAspectRatio: 1.45,
    ),
  };

  /// Resolves the expected morphology for a species label via its
  /// morphological category.
  static _SpeciesMorphology _morphologyForSpecies(String species) {
    return _categoryMorphology[categoryForSpecies(species)] ??
        _categoryMorphology[TrackCategory.clovenHoofUngulate]!;
  }

  /// How closely the measured track geometry matches a species' expected
  /// morphology. Returns a score in [0, 1] where 1.0 is a perfect match.
  /// When no usable contour exists (or circularity is 0), returns 0.5
  /// (neutral — no opinion).
  static double _morphologyMatchScore(
    SpoorTrackAttributes attributes,
    String species,
  ) {
    if (!attributes.hasUsableContour || attributes.circularity <= 0) {
      return 0.5;
    }
    final expected = _morphologyForSpecies(species);
    final circDelta =
        (attributes.circularity - expected.expectedCircularity).abs();
    final aspectDelta =
        (attributes.aspectRatio - expected.expectedAspectRatio).abs();
    return (1.0 - circDelta).clamp(0.0, 1.0) * 0.5 +
        (1.0 - aspectDelta.clamp(0.0, 1.0)) * 0.5;
  }

  /// Validates + re-ranks the raw AI prediction set against the measured
  /// track attributes.
  ///
  /// [rawPredictions] is the top-3 (or fewer) ranked list from the AI service.
  /// [attributes] is the measured track geometry from the captured frame.
  ///
  /// The returned [SpoorValidationResult] carries the re-ranked list, the
  /// correction/re-ranking flags, and a human-readable note. When the
  /// prediction list is empty or no usable contour could be extracted, the
  /// result is neutral (predictions unchanged, `wasReRanked`/`wasCorrected`
  /// false).
  static SpoorValidationResult classifySpoorTrackValidated({
    required List<SpoorPrediction> rawPredictions,
    required SpoorTrackAttributes attributes,
  }) {
    if (rawPredictions.isEmpty) {
      return const SpoorValidationResult(
        reRankedPredictions: [],
        wasCorrected: false,
        wasReRanked: false,
        usedMorphology: false,
        note: 'No AI predictions to validate.',
      );
    }

    if (!attributes.hasUsableContour || attributes.circularity <= 0) {
      return SpoorValidationResult(
        reRankedPredictions: List.of(rawPredictions),
        wasCorrected: false,
        wasReRanked: false,
        usedMorphology: false,
        note:
            'No usable track contour extracted — AI ranking kept as-is. '
            'Add a scale reference or re-capture for morphology validation.',
      );
    }

    // Score every candidate by morphology match, then re-rank descending.
    final scored = rawPredictions
        .map(
          (p) => (
            prediction: p,
            score: _morphologyMatchScore(attributes, p.species),
          ),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final reRanked = scored.map((s) => s.prediction).toList();

    final wasReRanked = _orderChanged(rawPredictions, reRanked);
    final wasCorrected = rawPredictions.isNotEmpty &&
        reRanked.isNotEmpty &&
        rawPredictions.first.species != reRanked.first.species;

    final String note;
    if (wasCorrected) {
      note =
          'Morphology check corrected the top match: '
          '${rawPredictions.first.species} → ${reRanked.first.species} '
          '(measured aspect ${attributes.aspectRatio.toStringAsFixed(2)}, '
          'circularity ${attributes.circularity.toStringAsFixed(2)}).';
    } else if (wasReRanked) {
      note =
          'Morphology check re-ranked the candidates '
          '(measured aspect ${attributes.aspectRatio.toStringAsFixed(2)}, '
          'circularity ${attributes.circularity.toStringAsFixed(2)}).';
    } else {
      note =
          'Morphology check confirmed the AI ranking '
          '(measured aspect ${attributes.aspectRatio.toStringAsFixed(2)}, '
          'circularity ${attributes.circularity.toStringAsFixed(2)}).';
    }

    return SpoorValidationResult(
      reRankedPredictions: reRanked,
      wasCorrected: wasCorrected,
      wasReRanked: wasReRanked,
      usedMorphology: true,
      note: note,
    );
  }

  /// True when the species order (ignoring confidence ties) differs between
  /// the raw and re-ranked lists.
  static bool _orderChanged(
    List<SpoorPrediction> raw,
    List<SpoorPrediction> reRanked,
  ) {
    if (raw.length != reRanked.length) return true;
    for (int i = 0; i < raw.length; i++) {
      if (raw[i].species != reRanked[i].species) return true;
    }
    return false;
  }

  /// Convenience: re-normalizes the re-ranked predictions so their
  /// confidences sum to 1.0 (softmax over the re-ranked set). Used when the
  /// caller wants the displayed percentages to stay coherent after a
  /// re-ranking.
  static List<SpoorPrediction> renormalize(List<SpoorPrediction> predictions) {
    if (predictions.isEmpty) return const [];
    final sum = predictions.fold<double>(0.0, (a, p) => a + p.confidence);
    if (sum <= 0) return List.of(predictions);
    return predictions
        .map(
          (p) => SpoorPrediction(
            species: p.species,
            confidence: (p.confidence / sum).clamp(0.0, 1.0),
          ),
        )
        .toList();
  }
}
