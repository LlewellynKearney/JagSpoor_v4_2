import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Helper widget that automatically detects whether an image path is
/// a local file path or a remote URL and renders it appropriately.
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
    // Empty/blank path → neutral placeholder (no scary "File not found" text).
    if (imagePath.trim().isEmpty) {
      return errorWidget ?? placeholder ?? _buildNeutralPlaceholder();
    }

    // Check if the path is a local file path
    if (_isLocalPath(imagePath)) {
      final file = File(imagePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) {
            return errorWidget ??
                placeholder ??
                _buildNeutralPlaceholder();
          },
        );
      } else {
        // Local file no longer present (e.g. app reinstalled / new device).
        // Fall back to a neutral placeholder rather than "File not found".
        return errorWidget ?? placeholder ?? _buildNeutralPlaceholder();
      }
    }

    // Otherwise, treat as a remote URL
    return CachedNetworkImage(
      imageUrl: imagePath,
      fit: fit,
      width: width,
      height: height,
      placeholder:
          placeholder != null
              ? (context, url) => placeholder!
              : (context, url) => _buildPlaceholder(),
      errorWidget: (context, url, error) {
        return errorWidget ??
            placeholder ??
            _buildNeutralPlaceholder();
      },
    );
  }

  bool _isLocalPath(String path) {
    // Check for common local file path patterns
    return path.startsWith('/') ||
        path.startsWith('file://') ||
        path.contains(':\\') || // Windows path
        path.startsWith('./') ||
        RegExp(r'^[a-zA-Z]:\\').hasMatch(path);
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.withValues(alpha: 0.1),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  /// Neutral placeholder shown when no usable image is available (missing
  /// local file, blank path, or remote error). Intentionally does NOT print
  /// alarming "File not found" text so callers can layer their own branded
  /// placeholder via [errorWidget]/[placeholder] when desired.
  Widget _buildNeutralPlaceholder() {
    return Container(
      color: Colors.grey.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 48,
          color: Colors.grey.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
