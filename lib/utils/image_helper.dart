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
                _buildErrorWidget('Local file error: ${error.toString()}');
          },
        );
      } else {
        return errorWidget ?? _buildErrorWidget('File not found');
      }
    }

    // Otherwise, treat as a remote URL
    return CachedNetworkImage(
      imageUrl: imagePath,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder != null
          ? (context, url) => placeholder!
          : (context, url) => _buildPlaceholder(),
      errorWidget: (context, url, error) {
        return errorWidget ?? _buildErrorWidget('Photo unavailable');
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
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Container(
      color: Colors.grey.withValues(alpha: 0.1),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
