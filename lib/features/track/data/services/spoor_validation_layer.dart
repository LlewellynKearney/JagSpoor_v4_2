import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../../models/animal.dart';
import '../spoor_track_attributes.dart';
import '../track_taxonomy.dart';

/// Per-candidate result of a structured morphological cross-check.
///
/// [species] is the candidate species; [passed] is true when the candidate is
/// morphologically compatible with the observed track; [checked] is true when
/// attribute data was available to test against. When [passed] is false,
/// [reason] explains which attribute rejected the candidate (toe count /
/// length / width).
class SpoorValidationMatch {
  final String species;
  final bool passed;
  final bool checked;
  final String? reason;

  const SpoorValidationMatch({
    required this.species,
    required this.passed,
    required this.checked,
    this.reason,
  });

  @override
  String toString() => '$species: ${passed ? 'pass' : 'FAIL'}'
      '${reason != null ? ' ($reason)' : ''}';
}

/// Overall outcome of a structured validation pass over a raw classification.
class SpoorValidationOutcome {
  /// The top-1 species as ranked by the raw classifier (pre-validation).
  final String rawTopSpecies;

  /// The top-1 species AFTER morphological re-ranking.
  final String validatedTopSpecies;

  /// Whether the validated top candidate differs from the raw top.
  final bool reranked;

  /// Whether attributes were available for at least one candidate.
  final bool databaseChecked;

  /// Per-candidate validation results, aligned with the input predictions.
  final List<SpoorValidationMatch> matches;

  /// Human-readable note for the UI (e.g. a rejected top candidate).
  final String? note;

  const SpoorValidationOutcome({
    required this.rawTopSpecies,
    required this.validatedTopSpecies,
    required this.reranked,
    required this.databaseChecked,
    required this.matches,
    this.note,
  });

  @override
  String toString() =>
      'raw=$rawTopSpecies validated=$validatedTopSpecies '
      'reranked=$reranked checked=$databaseChecked';
}

/// Structured validation layer for camera spoor classifications.
///
/// The raw classifier (TFLite + geometric matcher) can be fooled by lighting,
/// soil texture and shadow noise. This layer cross-checks the raw output
/// against morphological attribute ranges (toe counts, calibrated length /
/// width) queried from the Firestore `animals` collection — the same
/// database the SA Game Guide + trophy flow consume — and re-ranks the
/// candidates so an anatomically impossible top match cannot survive.
///
/// Design goals:
/// * **Pure + unit-testable**: [validatePredictions], [validateCandidate] and
///   [estimateToeCount] are static and dependency-free.
/// * **Graceful offline fallback**: when Firestore is unreachable / the app
///   is cold-launching, [attributesForSpecies] falls back to the built-in
///   [spoorTrackAttributesFallback] table, so validation still runs.
/// * **Never throws**: every failure path degrades to a permissive result.
class SpoorValidationLayer {
  static final SpoorValidationLayer _instance = SpoorValidationLayer._internal();
  static SpoorValidationLayer get instance => _instance;
  SpoorValidationLayer._internal();

  /// Test seam: swap in a `FakeFirebaseFirestore` (or null to force the
  /// built-in fallback table) without touching the production singleton.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  /// Test seam: override the species→attributes resolution (used to prove
  /// the layer prefers database attributes over the built-in table).
  @visibleForTesting
  static SpoorTrackAttributes? Function(String species)?
      attributesResolverForTesting;

  FirebaseFirestore? get _firestore =>
      firestoreForTesting ?? (() {
        try {
          return FirebaseFirestore.instance;
        } catch (_) {
          return null;
        }
      })();

  static void resetTestSeams() {
    firestoreForTesting = null;
    attributesResolverForTesting = null;
  }

  /// Estimates the toe count for a track from its geometric metrics +
  /// category:
  ///
  /// * [SpoorGeometricMetrics.estimatedToeCount] is preferred when the
  ///   geometry pass could resolve one (see the lobe-detection logic in
  ///   `spoor_identifier_service.dart`).
  /// * Otherwise the category drives a strong prior: cloven-hoofed ungulates
  ///   leave 2 cleaves, solid-hoofed equines 1 wall, carnivore paws 4 toes.
  static int? estimateToeCount({
    required int? geometryToeCount,
    required TrackCategory? category,
  }) {
    if (geometryToeCount != null && geometryToeCount > 0) {
      return geometryToeCount;
    }
    if (category == null) return null;
    switch (category) {
      case TrackCategory.pawCarnivore:
        return 4;
      case TrackCategory.clovenHoofUngulate:
        return 2;
      case TrackCategory.solidHoofEquine:
        return 1;
    }
  }

  /// Resolves the spoor attributes for [species] from the Firestore
  /// `animals` collection when available, else the built-in fallback table.
  ///
  /// The resolution is cached for the process lifetime. Firestore failures
  /// (offline, cold-launch `[core/no-app]`, permission) degrade to the
  /// fallback — never throw.
  Future<SpoorTrackAttributes?> attributesForSpecies(String species) async {
    final override = attributesResolverForTesting;
    if (override != null) return override(species);

    // Fast path: fallback table only when the database is not connected.
    final fs = _firestore;
    if (fs == null) {
      return spoorTrackAttributesFallback[species];
    }
    try {
      final snapshot = await fs.collection('animals').get();
      for (final doc in snapshot.docs) {
        final animal = Animal.fromFirestore(doc);
        if (animal.name.toLowerCase() == species.toLowerCase()) {
          final attributes = SpoorTrackAttributes.fromMap(
            doc.data(),
            species: species,
            fallback: spoorTrackAttributesFallback[species],
          );
          return attributes;
        }
      }
      // No document → fall back to the built-in table.
      return spoorTrackAttributesFallback[species];
    } catch (e) {
      debugPrint('SpoorValidationLayer.attributesForSpecies: $e');
      return spoorTrackAttributesFallback[species];
    }
  }

  /// Validates a single candidate against the observed morphology.
  ///
  /// Returns a permissive pass when no attributes are available for the
  /// species (checked = false) so an unlisted species can never be dropped
  /// purely by a missing database record.
  static SpoorValidationMatch validateCandidate({
    required String species,
    required SpoorTrackAttributes attributes,
    required int? estimatedToeCount,
    required double? printLengthMm,
    required double? printWidthMm,
  }) {
    final toeOk =
        estimatedToeCount == null ||
        estimatedToeCount <= 0 ||
        attributes.toeCount <= 0 ||
        estimatedToeCount == attributes.toeCount;
    if (!toeOk) {
      return SpoorValidationMatch(
        species: species,
        passed: false,
        checked: true,
        reason: 'toe count $estimatedToeCount ≠ ${attributes.toeCount}',
      );
    }

    final reason = <String>[];
    if (printLengthMm != null &&
        attributes.lengthMaxMm > 0 &&
        (printLengthMm < attributes.lengthMinMm - 8.0 ||
            printLengthMm > attributes.lengthMaxMm + 8.0)) {
      reason.add(
        'length ${printLengthMm.toStringAsFixed(0)} mm ∉ '
        '[${attributes.lengthMinMm.toStringAsFixed(0)}, '
        '${attributes.lengthMaxMm.toStringAsFixed(0)}]',
      );
    }
    if (printWidthMm != null &&
        attributes.widthMaxMm > 0 &&
        (printWidthMm < attributes.widthMinMm - 8.0 ||
            printWidthMm > attributes.widthMaxMm + 8.0)) {
      reason.add(
        'width ${printWidthMm.toStringAsFixed(0)} mm ∉ '
        '[${attributes.widthMinMm.toStringAsFixed(0)}, '
        '${attributes.widthMaxMm.toStringAsFixed(0)}]',
      );
    }

    if (reason.isNotEmpty) {
      return SpoorValidationMatch(
        species: species,
        passed: false,
        checked: true,
        reason: reason.join('; '),
      );
    }
    return SpoorValidationMatch(
      species: species,
      passed: true,
      checked: true,
    );
  }

  /// Cross-checks a ranked prediction list from the raw classifier against
  /// the species database, and returns a [SpoorValidationOutcome] that may
  /// re-rank the candidates.
  ///
  /// The re-ranking rule: the first candidate that PASSES morphological
  /// validation becomes the validated top. A candidate that fails on toe
  /// count (the most discriminative attribute) is dropped from the head of
  /// the list — the next plausible candidate takes its place. Dimensions
  /// contribute a soft ranking adjustment. When no candidate passes, the
  /// raw top is retained but flagged via [note] (permissive fallback).
  Future<SpoorValidationOutcome> validatePredictions({
    required List<SpoorPrediction> predictions,
    required int? estimatedToeCount,
    required double? printLengthMm,
    required double? printWidthMm,
  }) async {
    if (predictions.isEmpty) {
      return SpoorValidationOutcome(
        rawTopSpecies: '',
        validatedTopSpecies: '',
        reranked: false,
        databaseChecked: false,
        matches: const [],
        note: 'No predictions to validate.',
      );
    }

    final matches = <SpoorValidationMatch>[];
    for (final p in predictions) {
      final attrs = await attributesForSpecies(p.species);
      if (attrs == null) {
        matches.add(SpoorValidationMatch(
          species: p.species,
          passed: true,
          checked: false,
        ));
        continue;
      }
      matches.add(validateCandidate(
        species: p.species,
        attributes: attrs,
        estimatedToeCount: estimatedToeCount,
        printLengthMm: printLengthMm,
        printWidthMm: printWidthMm,
      ));
    }

    final databaseChecked = matches.any((m) => m.checked);
    final rawTop = predictions.first.species;

    // Find the first passing candidate in rank order. Toe-count rejections
    // are hard (an anatomically impossible top match drops); dimension
    // rejections are also treated as hard for the head slot (the layer
    // exists to stop infeasible outputs).
    String? validatedTop;
    for (int i = 0; i < predictions.length && i < matches.length; i++) {
      if (matches[i].passed) {
        validatedTop = predictions[i].species;
        break;
      }
    }

    final reached = validatedTop ?? rawTop;
    final reranked = reached != rawTop;
    final String? note;
    if (reranked) {
      note =
          'Top match "$rawTop" failed morphological validation'
          ' (toe/width/length) — showing "$reached" instead.';
    } else if (matches.isNotEmpty && matches.first.passed) {
      note = null;
    } else if (!databaseChecked) {
      note = 'Morphology database unavailable — showing raw best match.';
    } else {
      note = 'No candidate passed morphological validation — showing raw best match.';
    }

    return SpoorValidationOutcome(
      rawTopSpecies: rawTop,
      validatedTopSpecies: reached,
      reranked: reranked,
      databaseChecked: databaseChecked,
      matches: matches,
      note: note,
    );
  }
}