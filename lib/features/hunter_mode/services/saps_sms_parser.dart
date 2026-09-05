import 'saps_tracker_service.dart';

/// Structured result extracted from a raw SAPS notification SMS.
class SapsSmsParseResult {
  final String referenceNumber;
  final String calibre;
  final String serialNumber;
  final String statusMessage;
  final String applicationType;
  final int? statusStage;
  final String? matchedStatusPattern;

  const SapsSmsParseResult({
    this.referenceNumber = '',
    this.calibre = '',
    this.serialNumber = '',
    this.statusMessage = '',
    this.applicationType = 'Competency Certificate',
    this.statusStage,
    this.matchedStatusPattern,
  });

  bool get hasReference => referenceNumber.trim().isNotEmpty;
  bool get hasFirearmDetails =>
      calibre.trim().isNotEmpty || serialNumber.trim().isNotEmpty;
  bool get hasStatus => statusMessage.trim().isNotEmpty;

  bool get isEmpty => !hasReference && !hasFirearmDetails && !hasStatus;

  /// Whether at least one field was populated by the parser, so callers can
  /// decide whether a "parsed" result is worth pre-filling.
  bool get hasAnyField => hasReference || hasFirearmDetails || hasStatus;
}

/// Pure utility for extracting SAPS application details from the raw
/// notification SMS text the SAPS portal sends to firearm applicants.
///
/// Handles the reference-format and phrase-order variants seen across real
/// SAPS messages:
///   * `SAPS msg: Application Ref. 10470664 for calibre 6MM MUSGRAVE s/n OB14468`
///   * `SAPS: Reference 10470664 Calibre 6MM MUSGRAVE Serial OB14468`
///   * License-collection notices carrying the status text + reference code.
///
/// All matchers are case-insensitive and whitespace-tolerant (multiple
/// spaces / non-breaking spaces normalized to a single ASCII space).
class SapsSmsParser {
  SapsSmsParser._();

  /// Parses raw SAPS notification SMS text into structured application fields.
  static SapsSmsParseResult parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const SapsSmsParseResult();
    }

    final normalized = _normalize(raw);

    final reference = _matchReference(normalized);
    final calibre = _matchCalibre(normalized);
    final serial = _matchSerialNumber(normalized);
    final status = _matchStatus(normalized);
    final applicationType = _inferApplicationType(normalized);
    final stageResult = SapsTrackerStatusMapper.stageFor(status);

    return SapsSmsParseResult(
      referenceNumber: reference,
      calibre: calibre,
      serialNumber: serial,
      statusMessage: status,
      applicationType: applicationType,
      statusStage: stageResult.statusStage,
      matchedStatusPattern: stageResult.matchedPattern,
    );
  }

  /// Extracts the application reference code. Accepted shapes:
  ///   * `Application Ref. 10470664`
  ///   * `Ref 10470664` / `Reference 10470664` / `Ref No 10470664`
  ///   * `Application Reference 10470664`
  ///   * `https://.../status-check?...&reference=10470664...`
  ///
  /// A `\b` word boundary after `ref` prevents the bare `ref` pattern from
  /// swallowing the tail of `Reference` (the v4.5 audit bug pattern).
  static String _matchReference(String normalized) {
    const patterns = <String, String>{
      r'application reference\b[.:=]?\s*([A-Z0-9]+\b)': 'application reference',
      r'application ref\b[.:=]?\s*([A-Z0-9]+\b)': 'application ref',
      r'(?<![a-z])reference\b[.:=]?\s*([A-Z0-9]+\b)': 'reference',
      r'(?<![a-z])ref\b(?: no)?[.:=]?\s*([A-Z0-9]+\b)': 'ref',
      r'[?&]reference(?:Number|_no)?=([A-Z0-9]+\b)': 'reference URL param',
    };

    return _firstGroupMatch(normalized, patterns);
  }

  /// Extracts the calibre token immediately following `calibre`/`cal` (with
  /// or without a colon/equals and a space). Captures the whole calibre value
  /// (digits + optional decimal + unit + optional model name, e.g. `6MM
  /// MUSGRAVE`, `308 WIN`, `9MM PARABELLUM`, `.270 WIN`, `6.5 CREEDMOOR`),
  /// stopping at the next word boundary (` s/n `, ` serial `, end-of-line).
  static String _matchCalibre(String normalized) {
    // Calibre value: optional leading dot + digits + optional decimal + unit
    // (mm/cm/in/cal/mag — optional, so `308 WIN` and `6.5 CREEDMOOR` resolve),
    // optionally followed by model-name tokens (e.g. MUSGRAVE, PARABELLUM,
    // WIN, CREEDMOOR). The token loop uses a negative lookahead for the SAPS
    // stop words (`s/n`, `serial`, `for`, ...) so lowercase `s/n` / `serial`
    // introduce a hard stop. The result is uppercased to the canonical SAPS
    // form (`6mm musgrave` -> `6MM MUSGRAVE`).
    final match = RegExp(
      r'(?:^|\s)(?:calibre|caliber|cal)(?:\s*[:\-=])?\s+'
      r'(\.[0-9]+|[0-9]+(?:\.[0-9]+)?(?:\s*(?:mm|cm|in|cal|mag))?'
      r'(?:\s+(?!(?:s/n|serial|snr|for|and|of|status|ref\b|application|'
      r'collected|ready|is|has|been|approved|licence|license)\b)[^\s]+)*)',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim().toUpperCase();
    }

    // Fallback: bare numeric calibre (e.g. `calibre 6MM`, `cal 308`) — with a
    // word boundary so the value cannot swallow the next token.
    final bare = RegExp(
      r'(?:^|\s)(?:calibre|caliber|cal)(?:\s*[:\-=])?\s+'
      r'([0-9]+(?:\.[0-9]+)?\s*(?:mm|cm|in|cal|mag))\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (bare != null && bare.group(1) != null) {
      return bare.group(1)!.trim().toUpperCase();
    }
    return '';
  }

  /// Extracts the firearm serial number following `s/n`, `serial nr`,
  /// or `serial number`. Accepts alphanumeric + `-`/`/`/`(`/`)` runs (real
  /// SAPS serials are dense and can carry embedded hyphens/periods). The value
  /// is uppercased to the canonical SAPS form (`ob14468` -> `OB14468`).
  static String _matchSerialNumber(String normalized) {
    const patterns = <String, String>{
      r's/n\s*[:=\-]?\s*([A-Z0-9][A-Z0-9./\-()]{2,})': 's/n',
      r'serial\s*(?:no\.?|number|nr|#)?\s*[:=\-]?\s*([A-Z0-9][A-Z0-9./\-()]{2,})':
          'serial',
      r'[?&]serial(?:Number|_no)?=([A-Z0-9][A-Z0-9./\-()]{2,})':
          'serial URL param',
    };

    final raw = _firstGroupMatch(normalized, patterns);
    return raw.isEmpty ? '' : raw.toUpperCase();
  }

  /// Detects the status type / stage from common SAPS message phrases.
  static String _matchStatus(String normalized) {
    final lower = normalized.toLowerCase();
    const phrases = <String, String>{
      'application has been approved': 'Application approved – licence printed',
      'approval notice': 'Approval notice – licence printed',
      'ready for collection': 'Ready for collection',
      'collection notice': 'Collection notice – licence ready for collection',
      'licence printed': 'Licence printed – ready for collection',
      'license printed': 'Licence printed – ready for collection',
      'certificate printed': 'Certificate printed – ready for collection',
      'printed': 'Licence printed – ready for collection',
      'forwarded to central firearms registry':
          'Forwarded to Central Firearms Registry',
      'central firearms registry': 'CFR processing',
      'forwarded to provincial': 'Submitted to Provincial Office',
      'provincial office': 'At Provincial Office',
      'provincial firearms': 'At Provincial Office',
      'submitted to provincial': 'Submitted to Provincial Office',
      'received at district': 'Application received at DFO',
      'received at dfo': 'Application received at DFO',
      'district firearms officer': 'Application received at DFO',
      'application received': 'Application received at DFO',
      'application submitted': 'Application submitted',
      'submitted': 'Application submitted',
      'not found': 'Status unavailable – application not found',
      'no record': 'Status unavailable – no record found',
      'declined': 'Application declined',
      'refused': 'Application refused',
    };

    String? best;
    var bestLen = -1;
    for (final entry in phrases.entries) {
      if (lower.contains(entry.key) && entry.key.length > bestLen) {
        best = entry.key;
        bestLen = entry.key.length;
      }
    }

    if (best != null) {
      return phrases[best]!;
    }
    return '';
  }

  /// Infers the application type from the message context. Defaults to
  /// "Competency Certificate" (the generic SAPS application type).
  static String _inferApplicationType(String normalized) {
    final lower = normalized.toLowerCase();
    const types = <String, String>{
      'self-defence':
          'Section 13 – Licence to possess a firearm for self-defence',
      'self defense':
          'Section 13 – Licence to possess a firearm for self-defence',
      'occasional sport': 'Section 15 Occasional Sport',
      'dedicated hunting': 'Section 16 Dedicated Hunting',
      'dedicated sport': 'Section 16 Dedicated Hunting',
      'competency certificate': 'Competency Certificate',
      'competency': 'Competency Certificate',
    };

    for (final entry in types.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }

    return 'Competency Certificate';
  }

  /// Normalizes whitespace: trims and collapses runs of any whitespace
  /// (spaces / tabs / non-breaking spaces / newlines) to a single ASCII space.
  static String _normalize(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Runs ordered regex patterns and returns the first capture-group hit.
  static String _firstGroupMatch(
    String normalized,
    Map<String, String> patterns,
  ) {
    for (final entry in patterns.entries) {
      final match = RegExp(
        entry.key,
        caseSensitive: false,
      ).firstMatch(normalized);
      if (match != null && match.groupCount >= 1 && match.group(1) != null) {
        return match.group(1)!.trim();
      }
    }
    return '';
  }
}

/// Immutable status-stage mapping result used by [SapsSmsParser] and
/// [SapsTrackerService] so both share the same stage vocabulary.
class SapsTrackerStatusMapper {
  SapsTrackerStatusMapper._();

  /// Maps a raw status phrase to a stage index (0-3 or -1). Returns a result
  /// with `statusStage == null` when no stage pattern matches.
  static SapsTrackerStatusMapperResult stageFor(String rawStatus) {
    if (rawStatus.trim().isEmpty) {
      return const SapsTrackerStatusMapperResult();
    }
    final current = SapsTrackerService.convertRawStatusToStage(rawStatus);
    if (current == 0 && !_looksSubmitted(rawStatus)) {
      return const SapsTrackerStatusMapperResult();
    }
    return SapsTrackerStatusMapperResult(
      statusStage: current,
      matchedPattern: _matchedPatternForStage(current),
    );
  }

  static bool _looksSubmitted(String rawStatus) {
    final lower = rawStatus.toLowerCase();
    return lower.contains('submitted') ||
        lower.contains('received') ||
        lower.contains('dfo') ||
        lower.contains('district');
  }

  static String? _matchedPatternForStage(int? stage) {
    switch (stage) {
      case 0:
        return 'Submitted / DFO';
      case 1:
        return 'Provincial Office';
      case 2:
        return 'Central Firearms Registry';
      case 3:
        return 'Printed / Ready for Collection';
      case -1:
        return 'Status unavailable';
      default:
        return null;
    }
  }
}

/// Result of the status-stage mapping performed by [SapsTrackerStatusMapper].
class SapsTrackerStatusMapperResult {
  final int? statusStage;
  final String? matchedPattern;

  const SapsTrackerStatusMapperResult({
    this.statusStage,
    this.matchedPattern,
  });
}
