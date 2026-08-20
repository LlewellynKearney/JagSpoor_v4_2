import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Shared immersive bushveld background used across the entire outfitter
/// portal (dashboard, farm management, trophy stock, package publishing /
/// management, price lists, booking requests, permit log).
///
/// Renders the full-screen bushveld photo with a two-step fallback chain
/// (bundled bushveld asset when offline/off-grid, then the theme background
/// color), overlaid by a dark gradient scrim so every outfitter screen's
/// text and cards stay high-contrast and readable in both Day and Night
/// modes.
class OutfitterBushveldBackground {
  OutfitterBushveldBackground._();

  /// Bushveld landscape shown full-screen behind the outfitter UI.
  static const String kBackgroundImageUrl =
      'https://images.unsplash.com/photo-1516426122078-c23e76319801?auto=format&fit=crop&w=1600&q=80';

  /// Local asset fallback when the network image is unavailable (offline /
  /// off-grid). Bundled via `assets/images/` in pubspec.yaml.
  static const String kBackgroundFallbackAsset =
      'assets/images/Greater Kudu.jpg';

  /// Warm gold used for overlay subtitles/labels rendered directly on the
  /// scrim (the light-mode accent brown would wash out on the dark scrim).
  static const Color kOverlayGold = Color(0xFFD4AF37);

  /// Full-screen bushveld photo; falls back to the bundled bushveld asset
  /// (offline) and finally to [fallbackColor] (usually the theme background).
  static Widget backgroundImage({Color? fallbackColor}) {
    return Image.network(
      kBackgroundImageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        kBackgroundFallbackAsset,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Container(color: fallbackColor ?? const Color(0xFF121212)),
      ),
    );
  }

  /// Semi-transparent dark gradient scrim (strongest at the top / AppBar and
  /// at the bottom text run) so overlay text + cards stay readable over any
  /// photo exposure.
  static Widget scrim() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x99000000), // ~60% black (strongest at the top / AppBar)
            Color(0x66000000), // ~40% black (mid frame)
            Color(0xB3000000), // ~70% black (darkest at the bottom text run)
          ],
        ),
      ),
    );
  }

  /// The responsive background stack: photo + scrim + content, layered.
  ///
  /// Use inside a Scaffold body to make a non-Scaffold screen (or a body that
  /// already manages its own Scaffold/AppBar) immersive.
  static Widget stack({
    required Widget child,
    Color? fallbackColor,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        backgroundImage(fallbackColor: fallbackColor),
        scrim(),
        child,
      ],
    );
  }
}

/// A Scaffold pre-configured with the immersive bushveld background:
/// the photo + scrim are layered behind [body], the (transparent) AppBar is
/// full-bleed, and the body's scroll content clears the AppBar via the top
/// inset.
///
/// All outfitter-side screens share this so the whole portal carries the
/// bushveld aesthetic consistently.
class OutfitterScaffold extends StatelessWidget {
  final ThemeController? theme;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final Color? backgroundColor;

  const OutfitterScaffold({
    super.key,
    this.theme,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ??
        theme?.backgroundColor ??
        Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      extendBodyBehindAppBar: appBar != null,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: OutfitterBushveldBackground.stack(
        fallbackColor: bg,
        child: body,
      ),
    );
  }
}

/// High-contrast circular chip that keeps an AppBar action icon readable
/// against the bright sunrise portion of the bushveld background in both
/// light and dark modes. Wraps the icon in a subtle dark circle so the glyph
/// (settings, history, logout, mode switcher, etc.) never disappears into a
/// light region of the photo.
class OutfitterActionChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? iconColor;

  const OutfitterActionChip({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.iconColor,
  });

  /// Shared chip decoration — a translucent black circle with a faint white
  /// rim, readable on ANY background exposure.
  static BoxDecoration decoration() {
    return BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.black.withAlpha(115), // ~45% black
      border: Border.all(color: Colors.white.withAlpha(46), width: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? Colors.white;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(8),
            decoration: decoration(),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}
