import 'package:share_plus/share_plus.dart';

/// Pure, dependency-light composer for the Digital Trophy Room native share
/// message.
///
/// [buildTrophyShareMessage] is a pure function over a `Map<String, dynamic>`
/// trophy document — fully unit-testable with no Flutter / platform plugins.
/// [shareTrophy] is the thin platform wrapper that hands the composed message
/// to `Share.share` to activate the native mobile platform share sheet
/// (WhatsApp, Telegram, Email, SMS, etc.).
class TrophyShareComposer {
  TrophyShareComposer._();

  /// Builds the engaging harvest dispatch message for a trophy entry.
  ///
  /// Trophy documents carry the harvest measurements (`antlerSpread`,
  /// `antlerLength`, `antlerCircumference` in cm, `weight` in kg) but no
  /// stored Rowland Ward / SCI score, so the "Score / Details" line is
  /// assembled from whichever horn / antler measurements are present (the
  /// spec's "or horn measurements" alternative). Fields missing from legacy
  /// / partial entries collapse to an `N/A` placeholder so the message is
  /// always complete and shareable.
  ///
  /// `harvestDate` is stored as an ISO `YYYY-MM-DD` string; a malformed or
  /// missing date falls back to `N/A`.
  static String buildTrophyShareMessage(Map<String, dynamic> trophy) {
    final species = _asString(trophy['species']) ?? 'Unknown Trophy';
    final date = _formatDate(_asString(trophy['harvestDate']));
    final scoreDetails = _buildScoreDetails(trophy);

    return '''🦌 Check out my latest harvest on JagSpoor!
Species: $species
Score / Details: $scoreDetails
Date: $date
Shared via JagSpoor App''';
  }

  /// Default share subject for the platform share sheet.
  static const String defaultSubject = 'My JagSpoor Trophy!';

  /// Composes the message and triggers the native platform share sheet via
  /// `Share.share`. Returns whether the share invocation completed without
  /// throwing (the platform sheet itself is asynchronous UI; a return of
  /// `true` means the sheet was presented). Best-effort: a platform error
  /// is swallowed and reported as `false` so the caller can surface a
  /// fallback snackbar.
  static Future<bool> shareTrophy(
    Map<String, dynamic> trophy, {
    String? subject,
  }) async {
    try {
      final message = buildTrophyShareMessage(trophy);
      await Share.share(message, subject: subject ?? defaultSubject);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Assembles the "Score / Details" line from the trophy's recorded horn /
  /// antler measurements (and weight when present). Returns `N/A` when no
  /// measurement is recorded so the line is never blank.
  static String _buildScoreDetails(Map<String, dynamic> trophy) {
    final parts = <String>[];

    final spread = _asNum(trophy['antlerSpread']);
    final length = _asNum(trophy['antlerLength']);
    final circumference = _asNum(trophy['antlerCircumference']);
    final weight = _asNum(trophy['weight']);

    if (spread != null) parts.add('Spread ${_fmt(spread)} cm');
    if (length != null) parts.add('Length ${_fmt(length)} cm');
    if (circumference != null) {
      parts.add('Circumference ${_fmt(circumference)} cm');
    }
    if (weight != null) parts.add('Weight ${_fmt(weight)} kg');

    if (parts.isEmpty) return 'N/A';
    return parts.join(' • ');
  }

  static String? _asString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static String _fmt(double v) {
    if (v == v.truncate()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  static String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'N/A';
    // Already stored as YYYY-MM-DD; validate the shape.
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso; // best-effort: show raw value
    return '${parsed.year.toString().padLeft(4, '0')}'
        '-${parsed.month.toString().padLeft(2, '0')}'
        '-${parsed.day.toString().padLeft(2, '0')}';
  }
}
