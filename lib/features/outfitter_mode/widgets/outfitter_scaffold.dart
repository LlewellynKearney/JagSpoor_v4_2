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

  /// Adaptive gradient scrim layered over the photo so overlay text + cards
  /// stay readable over any exposure.
  ///
  /// * **Dark mode** ([isDarkMode] = true): a dense black gradient (strongest
  ///   at the top / AppBar and at the bottom text run) so bright white / gold
  ///   text pops.
  /// * **Light mode** ([isDarkMode] = false): a soft warm cream veil that
  ///   tones down the photo's bright sunrise exposure (softer, less blinding)
  ///   while giving the deep-espresso light-mode typography a light surface
  ///   to stand out sharply against.
  static Widget scrim({bool isDarkMode = true}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDarkMode
              ? const [
                  Color(0xA6000000), // ~65% black (top / AppBar)
                  Color(0x73000000), // ~45% black (mid frame)
                  Color(0xBF000000), // ~75% black (bottom text run)
                ]
              : const [
                  Color(0xE6F7F1E6), // ~90% warm cream (top / AppBar)
                  Color(0xCCF3EDE0), // ~80% warm cream (mid frame)
                  Color(0xF2EFE5D4), // ~95% warm cream (bottom text run)
                ],
        ),
      ),
    );
  }

  /// The responsive background stack: photo + scrim + content, layered.
  ///
  /// Use inside a Scaffold body to make a non-Scaffold screen (or a body that
  /// already manages its own Scaffold/AppBar) immersive.
  ///
  /// [isDarkMode] selects the scrim palette; when null it is derived from the
  /// ambient [Theme] brightness so existing call sites become mode-aware with
  /// no changes.
  static Widget stack({
    required Widget child,
    Color? fallbackColor,
    bool? isDarkMode,
  }) {
    return Builder(
      builder: (context) {
        final dark = isDarkMode ??
            Theme.of(context).brightness == Brightness.dark;
        return Stack(
          fit: StackFit.expand,
          children: [
            backgroundImage(fallbackColor: fallbackColor),
            scrim(isDarkMode: dark),
            child,
          ],
        );
      },
    );
  }
}

/// Light-mode contrast helpers shared by every outfitter screen.
///
/// The bushveld background photo has a bright sunrise exposure in its upper
/// portion, so the default Day-theme text / card colors (dark-charcoal text on
/// translucent white) wash out. These helpers resolve a richer, high-contrast
/// outfitter surface palette in light mode while delegating to the standard
/// [ThemeController] palette in dark mode (where the scrim keeps the standard
/// colors readable).
class OutfitterUi {
  OutfitterUi._();

  /// High-contrast dark espresso for screen titles / primary header text in
  /// light mode. Dark mode keeps white.
  static const Color lightTitle = Color(0xFF2C221E);

  /// Rich warm-tinted card surface for light mode (opaque EFE7DC) — tones
  /// down the overly bright near-white fills so the interface feels softer
  /// and less blinding against the photographic background.
  static const Color lightCard = Color(0xFFEFE7DC);

  /// Defined warm card/input border for light mode (deep enough to read
  /// against the richer [lightCard] tint).
  static const Color lightCardBorder = Color(0xFFC4B29E);

  /// High-contrast warm brown for subtitles / descriptions / hint text in
  /// light mode.
  static const Color lightBody = Color(0xFF4A3B32);

  /// Screen title / primary header color: dark espresso in light mode, white
  /// (readable on the dark scrim) in dark mode.
  static Color titleColor(ThemeController theme) =>
      theme.isDarkMode ? Colors.white : lightTitle;

  /// Card surface color: rich cream in light mode, theme card in dark mode.
  static Color cardColor(ThemeController theme) =>
      theme.isDarkMode ? theme.cardColor : lightCard;

  /// Card border color: defined warm border in light mode, faint white rim
  /// in dark mode.
  static Color cardBorderColor(ThemeController theme) =>
      theme.isDarkMode ? Colors.white.withAlpha(20) : lightCardBorder;

  /// Subtitle / description / placeholder color: high-contrast warm brown in
  /// light mode, theme subtitle in dark mode.
  static Color subtitleColor(ThemeController theme) =>
      theme.isDarkMode ? theme.subtitleColor : lightBody;

  /// Standard outfitter card decoration: solid cream surface + defined border
  /// in light mode; theme card surface + faint rim in dark mode.
  static BoxDecoration cardDecoration(
    ThemeController theme, {
    double radius = 12,
  }) {
    return BoxDecoration(
      color: cardColor(theme),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: cardBorderColor(theme)),
    );
  }

  /// Standard outfitter form-field decoration: filled cream surface, defined
  /// border, and dark high-contrast label/hint/typed text in light mode.
  static InputDecoration inputDecoration(
    ThemeController theme, {
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? suffixText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cardBorderColor(theme)),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      suffixText: suffixText,
      filled: true,
      fillColor: cardColor(theme),
      labelStyle: TextStyle(color: subtitleColor(theme)),
      hintStyle: TextStyle(color: subtitleColor(theme)),
      suffixStyle: TextStyle(color: subtitleColor(theme)),
      enabledBorder: border,
      border: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: theme.accentColor, width: 1.6),
      ),
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
    final dark =
        theme?.isDarkMode ?? Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: bg,
      extendBodyBehindAppBar: appBar != null,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: OutfitterBushveldBackground.stack(
        fallbackColor: bg,
        isDarkMode: dark,
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
