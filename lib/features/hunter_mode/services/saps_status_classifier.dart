import 'package:flutter/foundation.dart';

/// Stage indices used across the SAPS Tracker (must match the app's
/// 4-stage progress bar + the legacy `convertRawStatusToStage` contract).
const int kSapsStageDfo = 0;
const int kSapsStageProvincial = 1;
const int kSapsStageCfr = 2;
const int kSapsStagePrinted = 3;
const int kSapsStageNotFound = -1;

/// Hardened status classifier for the SAPS Central Firearms Register (CFR)
/// firearm / competency application enquiry.
///
/// The official CFR online enquiry portal (saps.gov.za) returns a free-text
/// status phrase per application. Those phrases vary across DFO / Provincial /
/// CFR / final stages and are frequently re-worded (e.g. "The application was
/// send to the Provincial DFO by the DFO and being processed"). This
/// classifier maps ANY raw phrase to the correct stage with a
/// **longest-match-wins** scan over a stage-priority phrase table, so a
/// short generic keyword can never shadow a more specific phrase (the v4.5
/// "submitted to provincial" bug class).
class SapsStatusClassifier {
  SapsStatusClassifier._();

  /// Canonical display label for each stage.
  static const List<String> stageLabels = [
    'DFO',
    'Provincial',
    'CFR',
    'Printed',
  ];

  /// Normalizes a raw status string for matching: lowercases, collapses every
  /// whitespace run (incl. NBSP / tabs / newlines) to a single space, and
  /// strips surrounding punctuation. Null / blank -> empty string.
  static String normalize(String? raw) {
    if (raw == null) return '';
    return raw
        .trim()
        .replaceAll(RegExp(r'[\s\u00A0]+'), ' ')
        .replaceAll(RegExp(r'^[\s,.;:!?()[\]{}\-`]+'), '')
        .replaceAll(RegExp(r'[\s,.;:!?()[\]{}\-`]+$'), '')
        .toLowerCase();
  }

  /// Stage -> ordered phrase patterns. Longer patterns are matched first
  /// across ALL stages (global longest-match-wins), so "sent to provincial"
  /// beats the generic "sent" and "for consideration by the commissioner"
  /// beats "consideration".
  static const Map<int, List<String>> _stagePatterns = {
    kSapsStageDfo: [
      'application received at dfo',
      'received at dfo',
      'application received',
      'received by the dfo',
      'received at district firearms',
      'district firearms office',
      'captured at the dfo',
      'captured at dfo',
      'application captured',
      'submitted',
      'received',
      'pending review',
      'pending',
    ],
    kSapsStageProvincial: [
      'sent to the provincial dfo',
      'send to the provincial dfo',
      'sent to provincial dfo',
      'forwarded to provincial',
      'submitted to provincial',
      'at provincial office',
      'at the provincial office',
      'provincial dfo',
      'received at provincial',
      'received by provincial',
      'under review at provincial',
      'being processed at provincial',
      'provincial',
      'province',
    ],
    kSapsStageCfr: [
      'for consideration by the commissioner',
      'for consideration by commissioner',
      'final consideration by the cfr',
      'received at the cfr',
      'received at cfr',
      'sent to the cfr',
      'sent to cfr',
      'forwarded to the cfr',
      'forwarded to cfr',
      'at the cfr',
      'at cfr',
      'central firearms registry',
      'received at licensing section',
      'licensing section',
      'consideration by the commissioner',
      'consideration',
      'cfr',
      'registry',
    ],
    kSapsStagePrinted: [
      'licence printed',
      'license printed',
      'ready for collection',
      'ready to be collected',
      'approved and printed',
      'approved',
      'printed',
      'completed',
      'collected',
    ],
    kSapsStageNotFound: [
      'not found in system',
      'not found',
      'no record found',
      'no record',
      'unable to locate',
      'does not exist',
      'invalid reference',
      'invalid application',
      'facility not operational',
      'not operational',
      'error',
    ],
  };

  /// Maps a raw CFR status phrase to a stage index.
  ///
  /// Returns [kSapsStageNotFound] for an explicit not-found / error phrase,
  /// [kSapsStageDfo] (the safe default) for null / blank / unrecognized
  /// input, and the correct stage for every known phrase via the
  /// longest-match-wins scan.
  static int classify(String? rawStatus) {
    final normalized = normalize(rawStatus);
    if (normalized.isEmpty) return kSapsStageDfo;

    int bestStage = kSapsStageDfo;
    int bestLen = -1;
    _stagePatterns.forEach((stage, patterns) {
      for (final pattern in patterns) {
        if (normalized.contains(pattern) && pattern.length > bestLen) {
          bestStage = stage;
          bestLen = pattern.length;
        }
      }
    });

    if (bestLen >= 0) return bestStage;

    debugPrint(
      'SapsStatusClassifier: Unrecognized status "$rawStatus", defaulting to DFO',
    );
    return kSapsStageDfo;
  }

  /// Maps a raw CFR status phrase to a human-friendly display label (used on
  /// the card status badge / detail view).
  static String displayLabel(String? rawStatus) {
    final normalized = normalize(rawStatus);
    if (normalized.isEmpty) return 'Pending Review';
    if (normalized.contains('not found') ||
        normalized.contains('no record') ||
        normalized.contains('invalid') ||
        normalized.contains('error') ||
        normalized.contains('not operational')) {
      return 'Status Unavailable';
    }
    switch (classify(rawStatus)) {
      case kSapsStageDfo:
        return 'Submitted to DFO';
      case kSapsStageProvincial:
        return 'At Provincial Office';
      case kSapsStageCfr:
        return 'At Central Registry';
      case kSapsStagePrinted:
        return 'Ready for Collection';
      default:
        return 'Pending Review';
    }
  }
}
