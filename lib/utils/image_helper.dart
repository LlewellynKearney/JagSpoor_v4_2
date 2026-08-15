import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/photo_unavailable_placeholder.dart';

/// Helper widget that automatically detects whether an image path is
/// a local file path or a remote URL and renders it appropriately, with a
/// resilient fallback pipeline:
///
///   1. **Local file** — if the path looks local (`file://`, a filesystem
///      path, or a Windows drive path) AND `File(localPath).existsSync()`
///      is true, render via `Image.file`. Decode failures (corrupt file,
///      permission error) are logged and fall through to step 2.
///   2. **Network image** — for a remote URL (`http`/`https`) OR a local
///      path whose file no longer exists, render via `CachedNetworkImage`.
///      Network failures (HTTP 403 Forbidden, 404 Not Found, storage access
///      errors) are logged with the exact exception and fall through to
///      step 3.
///   3. **Placeholder** — when every source has failed, render the
///      [PhotoUnavailablePlaceholder] (or the caller-supplied [errorWidget]
///      if one was provided).
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
      return errorWidget ?? _buildNeutralPlaceholder();
    }

    // Stage 1: local file.
    if (_isLocalPath(path)) {
      final localPath = _stripFileScheme(path);
      final file = File(localPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) {
            // The file existed on disk but failed to DECODE (corrupt bytes,
            // a permission error, or an unsupported format). Log the exact
            // failure and fall back to the network stage — the same path may
            // also resolve as a remote URL (e.g. a cached storage URL whose
            // local copy was truncated).
            debugPrint('AdaptiveImage: local file decode failed for '
                '"$localPath" — $error\n$stackTrace');
            return _buildNetworkImage(path);
          },
        );
      }
      // Local file no longer present (app reinstalled / new device / scoped
      // storage migration). Log and fall through to the network stage.
      debugPrint('AdaptiveImage: local file does not exist at "$localPath" — '
          'falling back to network load.');
    }

    // Stage 2 + 3: network image (with logged error -> placeholder).
    return _buildNetworkImage(path);
  }

  /// Stage 2 + 3: load the path as a network image. For a genuine remote
  /// URL this resolves the bytes via `CachedNetworkImage`; for a stale local
  /// path (not a valid URL) the network load fails, is logged, and the
  /// placeholder is rendered.
  Widget _buildNetworkImage(String path) {
    // A path that is neither a remote URL nor a previously-local file is
    // unlikely to resolve as a network resource — log it explicitly so the
    // fallback is traceable rather than a silent CachedNetworkImage 404.
    if (!_looksLikeRemoteUrl(path)) {
      debugPrint('AdaptiveImage: path "$path" is not a remote URL and no '
          'local file exists — network fallback will likely fail.');
    }
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
        return errorWidget ?? _buildNeutralPlaceholder();
      },
    );
  }

  /// A path is treated as local if it begins with a filesystem indicator:
  /// `file://`, a POSIX absolute path (`/`), a Windows drive path
  /// (`C:\`), or a relative path (`./`). `content://` Android media URIs are
  /// intentionally NOT treated as local filesystem paths (Flutter `File()`
  /// cannot read them directly) — they fall through to the network stage,
  /// which degrades gracefully to the placeholder if unresolvable.
  bool _isLocalPath(String path) {
    return path.startsWith('/') ||
        path.startsWith('file://') ||
        path.startsWith('./') ||
        RegExp(r'^[a-zA-Z]:\\').hasMatch(path);
  }

  /// Strip a leading `file://` scheme so `File()` can read the path.
  String _stripFileScheme(String path) {
    if (path.startsWith('file://')) {
      return path.substring('file://'.length);
    }
    return path;
  }

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

  /// Final fallback when all image sources have failed. Defaults to the
  /// reusable [PhotoUnavailablePlaceholder] (neutral broken-image state with
  /// no sensitive path/HTTP detail surfaced to the user).
  Widget _buildNeutralPlaceholder() {
    return PhotoUnavailablePlaceholder();
  }
}

