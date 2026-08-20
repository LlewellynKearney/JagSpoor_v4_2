import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/photo_unavailable_placeholder.dart';
import '../../../utils/image_helper.dart';

/// Horizontal scrollable photo gallery for hunter-facing detail surfaces.
///
/// Renders every photo URL the document carries (resolvable via
/// `resolveGalleryUrls`) as a horizontally scrollable strip with a
/// "N photos" position chip; each image goes through the resilient
/// [AdaptiveImage] pipeline (local-first, network fallback, clean
/// placeholder) and opens a full-screen viewer on tap.
///
/// Returns an empty [SizedBox] when the document has no photos at all so
/// cards/sheets can embed it unconditionally.
class PhotoGalleryStrip extends StatelessWidget {
  /// Photo URLs to render (already resolved + de-duplicated).
  final List<String> urls;
  final ThemeController theme;

  /// Thumbnail height (width is derived at 1.45x height).
  final double height;

  const PhotoGalleryStrip({
    super.key,
    required this.urls,
    required this.theme,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    final width = height * 1.45;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final url = urls[index];
              return GestureDetector(
                onTap: () => _openFullScreen(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AdaptiveImage(
                    imagePath: url,
                    fit: BoxFit.cover,
                    width: width,
                    height: height,
                    errorWidget: PhotoUnavailablePlaceholder(
                      icon: Icons.photo_outlined,
                      label: 'Photo ${index + 1}',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (urls.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_rounded,
                  size: 12,
                  color: theme.accentColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${urls.length} photos -- swipe to browse',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _openFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenPhoto(url: url, theme: theme),
      ),
    );
  }
}

/// Full-screen immersive photo viewer (tap to dismiss).
class _FullScreenPhoto extends StatelessWidget {
  final String url;
  final ThemeController theme;

  const _FullScreenPhoto({required this.url, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: AdaptiveImage(
              imagePath: url,
              fit: BoxFit.contain,
              errorWidget: const PhotoUnavailablePlaceholder(
                icon: Icons.photo_outlined,
                label: 'Photo unavailable',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
