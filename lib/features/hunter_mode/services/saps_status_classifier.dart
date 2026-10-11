import 'package:flutter/foundation.dart';

/// Stage indices used across the SAPS Tracker (must match the app's
/// 4-stage progress bar + the legacy `convertRawStatusToStage` contract).
const int kSapsStageDfo = 0;
const int kSapsStageProvincial = 1;
const int kSapsStageCfr = 2;
const int kSapsStagePrinted = 3;
const int kSapsStageNotFound = -1;

/// Sentinel stage used when the portal refuses the enquiry because a firearm
/// application needs BOTH a serial number AND a reference number (a
/// competency-only application needs the reference alone). Distinct from
/// [kSapsStageNotFound] so the caller can surface an actionable "enter both"
/// message instead of "status unavailable".
const int kSapsStageNeedSerialAndRef = -2;

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
      'in preparation for consideration',
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
      // The portal appends this note to an IN PREPARATION FOR CONSIDERATION
      // result; treat it as the CFR stage (not DFO) so it does not downgrade
      // a live CFR status.
      'no status available contact the dfo',
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
    // Treated as a validation prompt, not a status. The longest-match-wins
    // scan classifies the "Please supply a Serial Number AND Reference Number"
    // banner here so the caller can prompt for both fields. Nothing in the
    // results-table status vocabulary contains these phrases, so there is no
    // shadowing risk.
    kSapsStageNeedSerialAndRef: [
      'please supply a serial number and reference number',
      'please supply a serial',
      'supply a serial number and reference number',
      'serial number and reference number',
      'need_serial_and_ref',
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

  /// Whether a raw CFR status phrase represents an APPROVED / finalised
  /// application — the trigger for the "Add to Digital Firearm Safe" flow.
  ///
  /// True when the phrase classifies to the final stage ([kSapsStagePrinted],
  /// i.e. printed / ready for collection / approved / collected) OR contains
  /// an explicit approval keyword ("approved", "card printed", "finalised" /
  /// "finalized", "ready for collection"). Deliberately narrow so an
  /// in-progress CFR phrase ("For consideration by the Commissioner") never
  /// reads as approved.
  static bool isApproved(String? rawStatus) {
    if (classify(rawStatus) == kSapsStagePrinted) return true;
    final normalized = normalize(rawStatus);
    if (normalized.isEmpty) return false;
    return normalized.contains('approved') ||
        normalized.contains('card printed') ||
        normalized.contains('finalised') ||
        normalized.contains('finalized');
  }

  /// The next anticipated stage label in the SAPS licensing workflow for a
  /// given [stage]: DFO -> Provincial -> CFR -> Printed / Ready for
  /// Collection -> Licence Collected (for the terminal stages). Used to
  /// render the card's `Next:` indicator from a classified en-memory stage
  /// rather than re-parsing the raw phrase.
  static String nextStepForStage(int stage) {
    switch (stage) {
      case kSapsStageDfo:
        return 'Provincial';
      case kSapsStageProvincial:
        return 'CFR';
      case kSapsStageCfr:
        return 'Central Firearms Register (CFR) Processing';
      case kSapsStagePrinted:
        return 'Licence Collected';
      default:
        // NOT_FOUND / NEED_SERIAL / unknown -> no forward step.
        return 'Status Unavailable';
    }
  }

  /// Normalizes a firearm serial number to its canonical form: trimmed and
  /// upper-cased, with interior whitespace removed. This prevents the
  /// hand-entry typo class seen live (`F0004574` instead of `F004574`) from
  /// being stored / compared verbatim -- leading zeros are NOT invented or
  /// stripped (the serial is opaque), only case / whitespace are normalised.
  static String normalizeSerial(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'\s+'), '').trim().toUpperCase();
  }

  /// Maps a raw CFR status phrase to a human-friendly display label (used on
  /// the card status badge / detail view).
  static String displayLabel(String? rawStatus) {
    final normalized = normalize(rawStatus);
    if (normalized.isEmpty) return 'Pending Review';
    if (classify(rawStatus) == kSapsStageNeedSerialAndRef) {
      return 'Enter both Serial + Reference for firearm apps (Ref only for competency)';
    }
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
