import 'package:flutter/material.dart';

/// Reusable fallback widget rendered when every image source in the
/// `AdaptiveImage` resilient pipeline has failed (the local file is missing
/// AND the network load failed, or the path was empty/invalid).
///
/// Shows a neutral "Photo unavailable" state with a broken-image icon. The
/// icon + label colours are sourced from the ambient theme so the placeholder
/// adapts to Day/Night mode. No raw error detail (HTTP status, storage path)
/// is surfaced to the end user — exact failure diagnostics are logged via
/// `debugPrint` inside `AdaptiveImage`'s error handlers, keeping user-facing
/// copy free of sensitive/internal path information.
class PhotoUnavailablePlaceholder extends StatelessWidget {
  /// Optional override for the icon (defaults to a broken-image glyph).
  final IconData icon;

  /// Optional override for the caption (defaults to "Photo unavailable").
  final String label;

  /// Optional background colour override (defaults to the theme card colour).
  final Color? backgroundColor;

  const PhotoUnavailablePlaceholder({
    super.key,
    this.icon = Icons.image_not_supported_outlined,
    this.label = 'Photo unavailable',
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = backgroundColor ?? theme.cardColor;
    final subtitle = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7) ??
        const Color(0xFFB0B0B0);
    return Container(
      color: cardColor,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: subtitle),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: subtitle, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
