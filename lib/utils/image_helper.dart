import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../widgets/photo_unavailable_placeholder.dart';

/// Helper widget that automatically detects whether an image path is
/// a local file path or a remote URL and renders it appropriately, with a
/// strict, resilient fallback pipeline:
///
///   1. **Local file** — if the path is a local file path (starts with
///      `/data/`, `/storage/`, `file://`, or `Path.isAbsolute(path)`),
///      the `file://` scheme is stripped via `Uri.parse(path).toFilePath()`
///      and `File(normalizedPath).existsSync()` is verified BEFORE rendering
///      `Image.file`. A decode failure is logged and falls through to the
///      placeholder (step 3) — it is NOT retried as a network URL.
///   2. **Network image** — ONLY when the string explicitly starts with
///      `http://` or `https://`, render via `CachedNetworkImage`. Network
///      failures (HTTP 403 Forbidden, 404 Not Found, socket/SSL/storage
///      errors) are logged with the exact exception and fall through to
///      step 3.
///   3. **Placeholder** — when the string is neither a valid local file
///      (exists on disk) NOR an `http(s)` URL, render the reusable
///      [PhotoUnavailablePlaceholder] (or the caller-supplied [errorWidget]).
///      A non-existent local path is NEVER passed to `CachedNetworkImage`
///      (that was the previous bug — a local-looking path was treated as a
///      URL, hanging/throwing inside the network loader).
///
/// Exact failure diagnostics (exception type + message, HTTP status where
/// available, the offending path) are emitted via `debugPrint` so failures
/// are clearly visible in dev logs instead of failing silently. The
/// user-facing placeholder copy stays generic ("Photo unavailable") — no
/// raw path or HTTP status is surfaced to end users.
class AdaptiveImage extends StatelessWidget {
  final String imagePath;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;

  const AdaptiveImage({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();

    // Empty/blank path -> no source to try; go straight to the placeholder.
    if (path.isEmpty) {
      debugPrint('AdaptiveImage: empty image path — rendering placeholder.');
      return _buildFallback();
    }

    // Stage 1: local file.
    if (_isLocalPath(path)) {
      final normalizedPath = _normalizeLocalPath(path);
      final file = File(normalizedPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) {
            // The file existed on disk but failed to DECODE (corrupt bytes,
            // a permission error, or an unsupported format). Log the exact
            // failure. The path is NOT an http(s) URL, so per the contract
            // it must NOT be retried via CachedNetworkImage — fall straight
            // to the placeholder.
            debugPrint('AdaptiveImage: local file decode failed for '
                '"$normalizedPath" — $error\n$stackTrace');
            return _buildFallback();
          },
        );
      }
      // Local-looking path whose file does not exist (app reinstalled / new
      // device / scoped-storage migration / stale cache). This is NOT an
      // http(s) URL, so it must NOT be passed to CachedNetworkImage — fall
      // straight to the placeholder.
      debugPrint('AdaptiveImage: local file does not exist at '
          '"$normalizedPath" — rendering placeholder (not an http(s) URL, '
          'so not retried via network).');
      return _buildFallback();
    }

    // Stage 2: network image — ONLY for explicit http(s) URLs.
    if (_looksLikeRemoteUrl(path)) {
      return _buildNetworkImage(path);
    }

    // Stage 3: neither an existing local file NOR an http(s) URL.
    // Do NOT pass to CachedNetworkImage; fall straight to the placeholder.
    debugPrint('AdaptiveImage: path "$path" is neither an existing local '
        'file nor an http(s) URL — rendering placeholder.');
    return _buildFallback();
  }

  /// Stage 2: load an http(s) URL via `CachedNetworkImage`. Network failures
  /// are logged with the exact exception and fall back to the placeholder.
  Widget _buildNetworkImage(String path) {
    return CachedNetworkImage(
      imageUrl: path,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder != null
          ? (context, url) => placeholder!
          : (context, url) => _buildLoadingPlaceholder(),
      errorWidget: (context, url, error) {
        // Log the exact network failure (HTTP 403 Forbidden, 404 Not Found,
        // socket/SSL/storage error) so it is visible in dev logs. The user
        // never sees this text — the placeholder copy is generic.
        debugPrint('AdaptiveImage: network image load failed for "$url" — '
            '$error');
        return _buildFallback();
      },
    );
  }

  /// A path is treated as local if it begins with `/data/`, `/storage/`,
  /// the `file://` scheme, OR satisfies `Path.isAbsolute(path)` (which
  /// covers POSIX absolute paths like `/…` and Windows drive paths like
  /// `C:\…`). `content://` Android media URIs and `http(s)` URLs are
  /// intentionally NOT local (Flutter `File()` cannot read them directly)
  /// and fall through to the network/placeholder stages.
  bool _isLocalPath(String path) => isLocalImagePath(path);

  /// Normalize a local path before `File(...).existsSync()`:
  /// if the path carries a `file://` scheme, strip it via
  /// `Uri.parse(path).toFilePath()` so `File` can read it natively. A plain
  /// filesystem path is returned unchanged.
  String _normalizeLocalPath(String path) => normalizeLocalImagePath(path);

  bool _looksLikeRemoteUrl(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      color: Colors.grey.withValues(alpha: 0.1),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  /// Final fallback when the path is neither an existing local file NOR an
  /// http(s) URL (or when a source failed). Uses the caller-supplied
  /// [errorWidget] if provided, otherwise the reusable
  /// [PhotoUnavailablePlaceholder] (neutral broken-image state with no
  /// sensitive path/HTTP detail surfaced to the user).
  Widget _buildFallback() {
    return errorWidget ?? PhotoUnavailablePlaceholder();
  }
}

/// A path is treated as a local file path if it begins with `/data/`,
/// `/storage/`, the `file://` scheme, OR satisfies `Path.isAbsolute(path)`
/// (which covers POSIX absolute paths like `/…` and Windows drive paths like
/// `C:\…`).
///
/// `content://` Android media URIs and `http(s)` URLs are intentionally NOT
/// treated as local: Flutter's `File()` cannot read a `content://` URI
/// directly, and an `http(s)` URL is a remote resource. They fall through to
/// the network/placeholder stages.
///
/// Extracted as a top-level pure function so the URI-path-handling logic is
/// unit-testable without mounting an `Image` widget (image decode is flaky in
/// a headless test sandbox).
bool isLocalImagePath(String path) {
  return path.startsWith('/data/') ||
      path.startsWith('/storage/') ||
      path.startsWith('file://') ||
      p.isAbsolute(path);
}

/// Normalize a local image path before `File(...).existsSync()`:
///
/// If the path carries a `file://` scheme, strip it via
/// `Uri.parse(path).toFilePath()` so `File` can read it natively. A plain
/// filesystem path is returned unchanged. If `Uri.parse` fails, fall back to
/// a raw `file://` substring strip so a malformed file-URI never crashes the
/// pipeline.
///
/// Extracted as a top-level pure function so the URI-normalization logic is
/// unit-testable without mounting an `Image` widget.
String normalizeLocalImagePath(String path) {
  if (!path.startsWith('file://')) {
    return path;
  }
  try {
    return Uri.parse(path).toFilePath();
  } catch (e) {
    debugPrint('AdaptiveImage: failed to parse file:// URI "$path" — $e; '
        'falling back to raw string after scheme strip.');
    return path.substring('file://'.length);
  }
}


