import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Pure, dependency-light composer for the Digital Trophy Room native share
/// message.
///
/// [buildTrophyShareMessage] is a pure function over a `Map<String, dynamic>`
/// trophy document — fully unit-testable with no Flutter / platform plugins.
/// [shareTrophy] is the thin platform wrapper that hands the composed message
/// (and, when available, the actual trophy photo file) to `share_plus` to
/// activate the native mobile platform share sheet (WhatsApp, Telegram,
/// Email, SMS, etc.).
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

  /// Extracts the first usable photo path/URL from a trophy document's
  /// `photos` list. Returns `null` when there are no photos. Pure / unit
  /// testable.
  static String? firstPhotoPath(Map<String, dynamic> trophy) {
    final photos = trophy['photos'];
    if (photos is! List || photos.isEmpty) return null;
    for (final entry in photos) {
      final s = entry?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  /// Whether [path] refers to a local file (vs. a remote URL). Pure / unit
  /// testable. Mirrors the detection logic in `AdaptiveImage`.
  static bool isLocalFilePath(String path) {
    return path.startsWith('/') ||
        path.startsWith('file://') ||
        path.contains(':\\') ||
        path.startsWith('./') ||
        RegExp(r'^[a-zA-Z]:\\').hasMatch(path);
  }

  /// Resolves a trophy photo reference to a local [File] suitable for
  /// `Share.shareXFiles`. Local file paths are returned directly (when the
  /// file still exists); remote URLs are downloaded to a temp file. Returns
  /// `null` when the photo cannot be resolved (missing local file, download
  /// failure, or no path). Best-effort: errors are swallowed and reported as
  /// `null` so the caller falls back to a text-only share.
  static Future<File?> resolveShareFile(String? photoPath) async {
    if (photoPath == null || photoPath.trim().isEmpty) return null;
    final trimmed = photoPath.trim();

    if (isLocalFilePath(trimmed)) {
      final file = File(trimmed);
      if (file.existsSync()) return file;
      return null;
    }

    // Remote URL — download to a temp file so share_plus can attach it.
    try {
      final uri = Uri.parse(trimmed);
      if (!uri.hasScheme) return null;
      final response = await http.get(uri);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      final tmpDir = await getTemporaryDirectory();
      final ext = _extFor(uri.path);
      final file = File(p.join(
          tmpDir.path,
          'jagspoor_trophy_${DateTime.now().millisecondsSinceEpoch}$ext'));
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Composes the message and triggers the native platform share sheet.
  ///
  /// When the trophy has a photo, the actual image file is shared alongside
  /// the formatted text caption via `Share.shareXFiles` (so WhatsApp /
  /// Telegram / Email attach the image). When there is no photo (or the
  /// photo cannot be resolved to a local file), falls back to a text-only
  /// `Share.share`.
  ///
  /// Returns whether the share invocation completed without throwing (the
  /// platform sheet itself is asynchronous UI; a return of `true` means the
  /// sheet was presented). Best-effort: a platform error is swallowed and
  /// reported as `false` so the caller can surface a fallback snackbar.
  static Future<bool> shareTrophy(
    Map<String, dynamic> trophy, {
    String? subject,
  }) async {
    try {
      final message = buildTrophyShareMessage(trophy);
      final photoPath = firstPhotoPath(trophy);
      final shareSubject = subject ?? defaultSubject;
      if (photoPath != null) {
        final file = await resolveShareFile(photoPath);
        if (file != null) {
          await Share.shareXFiles(
            [XFile(file.path)],
            subject: shareSubject,
            text: message,
          );
          return true;
        }
      }
      // No usable photo — text-only share.
      await Share.share(message, subject: shareSubject);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Picks a file extension (with dot) for a downloaded image based on the
  /// URL path; defaults to `.jpg` for unknown / non-image extensions.
  static String _extFor(String urlPath) {
    final ext = p.extension(urlPath).toLowerCase();
    const known = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'};
    return known.contains(ext) ? ext : '.jpg';
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
