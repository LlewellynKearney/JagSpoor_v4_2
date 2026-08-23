import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../hunter_mode/widgets/hunter_scaffold.dart' show HunterUi;

/// Brushed-gold accent shared by every Hunter Mode rich-media surface. Dark
/// mode cards glow with this amber; the frosted pills use it for their
/// highlighted variant.
const Color kHunterMediaAmber = Color(0xFFD4AF37);

/// Data spec for a [HunterFrostedPill] / [HunterDataPill].
///
/// [amber] selects the warm amber highlighted variant; otherwise the neutral
/// (dark frosted / subtle solid) variant is used. [accentColor] overrides
/// both variants with an explicit accent (e.g. a red "expired" status pill).
class HunterMediaPill {
  final IconData? icon;
  final String label;
  final bool amber;
  final Color? accentColor;

  const HunterMediaPill({
    this.icon,
    required this.label,
    this.amber = false,
    this.accentColor,
  });
}

/// Reusable rich-media card container extracted from the SA Game Guide's
/// [GameSpeciesCard] design language:
///
/// * full-bleed background [image] (any [ImageProvider]) with a graceful
///   icon fallback when no image is available or the image fails to load;
/// * a smooth 4-stop dark gradient overlay for text legibility;
/// * an optional amber tag pill floating in the top-left corner;
/// * optional interactive action elements floating in the top-right corner
///   (e.g. favorite hearts, quick toggles -- see [HunterFrostedCircleButton]);
/// * the title, an optional italic subtitle, and translucent frosted-glass
///   telemetry/data pills overlaid across the lower section;
/// * a 20px rounded card carrying the warm amber glowing border in dark mode
///   and the defined warm border in light mode.
class HunterMediaCard extends StatelessWidget {
  final ThemeController theme;

  /// Full-bleed background image. When null (or when it fails to decode), the
  /// [fallbackIcon] placeholder is rendered instead.
  final ImageProvider? image;

  /// Icon rendered in the center of the placeholder surface when there is no
  /// usable image.
  final IconData fallbackIcon;

  /// Primary title rendered at the lower-left of the card.
  final String title;

  /// Optional italic secondary line rendered directly under the title.
  final String? subtitle;

  /// Frosted telemetry/data pills overlaid across the lower section.
  final List<HunterMediaPill> pills;

  /// Optional amber tag pill floating in the top-left corner.
  final HunterMediaPill? topLeftPill;

  /// Optional interactive action elements floating in the top-right corner.
  final List<Widget> topRightActions;

  /// Tap handler for the whole card surface.
  final VoidCallback? onTap;

  /// Corner radius of the card (20px by default, matching the Game Guide).
  final double borderRadius;

  const HunterMediaCard({
    super.key,
    required this.theme,
    required this.title,
    this.image,
    this.fallbackIcon = Icons.image_outlined,
    this.subtitle,
    this.pills = const [],
    this.topLeftPill,
    this.topRightActions = const [],
    this.onTap,
    this.borderRadius = 20,
  });

  /// The smooth dark multi-stop gradient overlay used for text legibility
  /// over the full-bleed imagery (33% black top -> transparent mid -> 55% ->
  /// 95% black bottom).
  static const LinearGradient legibilityGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x33000000),
      Color(0x00000000),
      Color(0x8C000000),
      Color(0xF2000000),
    ],
    stops: [0.0, 0.35, 0.68, 1.0],
  );

  Widget _buildImageLayer() {
    final provider = image;
    if (provider == null) return _buildFallback();
    return Image(
      image: provider,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return ColoredBox(
      color: const Color(0xFF2A241F),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: 56,
          color: theme.accentColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = theme.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark
              ? kHunterMediaAmber.withValues(alpha: 0.35)
              : HunterUi.cardBorderColor(theme),
          width: isDark ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? kHunterMediaAmber.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: isDark ? 14 : 8,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Full-bleed background imagery.
                _buildImageLayer(),
                // Smooth dark gradient overlay for text legibility.
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: legibilityGradient),
                ),
                // Amber tag pill, top-left of the image.
                if (topLeftPill != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: HunterFrostedPill(pill: topLeftPill!),
                  ),
                // Interactive action elements, top-right of the image.
                if (topRightActions.isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: topRightActions,
                    ),
                  ),
                // Title + subtitle + telemetry pills across the lower section.
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF7F3EA),
                          letterSpacing: 0.2,
                          shadows: [
                            Shadow(
                              color: Color(0xAA000000),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: Color(0xE6EFE7DC),
                          ),
                        ),
                      ],
                      if (pills.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: pills
                              .map((pill) => HunterFrostedPill(pill: pill))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Translucent frosted-glass pill used for the overlaid data attributes on
/// rich-media cards. The [HunterMediaPill.amber] variant is the warm amber
/// highlighted style; otherwise a dark frosted style is used. An explicit
/// [HunterMediaPill.accentColor] overrides both variants (e.g. a red
/// "expired" status pill).
class HunterFrostedPill extends StatelessWidget {
  final HunterMediaPill pill;

  const HunterFrostedPill({super.key, required this.pill});

  @override
  Widget build(BuildContext context) {
    final accent = pill.accentColor;
    final isAmber = pill.amber || accent != null;
    final effectiveAccent = accent ?? kHunterMediaAmber;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: isAmber
                ? effectiveAccent.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isAmber
                  ? effectiveAccent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pill.icon != null) ...[
                Icon(
                  pill.icon,
                  size: 12,
                  color: isAmber ? effectiveAccent : const Color(0xFFF0EAE0),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  pill.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: accent ??
                        (isAmber
                            ? const Color(0xFFF1D894)
                            : const Color(0xFFF0EAE0)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Solid (non-frosted) theme-aware data pill for use inside regular card
/// bodies -- the clean companion of [HunterFrostedPill] for surfaces that are
/// not overlaid on imagery (caliber / bullet-weight / velocity stats, meta
/// chips, etc.).
class HunterDataPill extends StatelessWidget {
  final ThemeController theme;
  final HunterMediaPill pill;

  const HunterDataPill({super.key, required this.theme, required this.pill});

  @override
  Widget build(BuildContext context) {
    final accent = pill.accentColor ?? theme.accentColor;
    final isAmber = pill.amber || pill.accentColor != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isAmber
            ? accent.withValues(alpha: 0.14)
            : theme.backgroundColor.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAmber
              ? accent.withValues(alpha: 0.45)
              : HunterUi.cardBorderColor(theme),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pill.icon != null) ...[
            Icon(
              pill.icon,
              size: 12,
              color: isAmber ? accent : theme.subtitleColor,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              pill.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: isAmber ? accent : theme.subtitleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small frosted circular icon button floating over a rich-media card image
/// (favorite hearts, quick toggles, and other top-right actions).
class HunterFrostedCircleButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onPressed;
  final String? tooltip;

  const HunterFrostedCircleButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.35),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          ),
          child: IconButton(
            icon: Icon(icon, size: 18, color: iconColor),
            onPressed: onPressed,
            tooltip: tooltip,
            padding: const EdgeInsets.all(7),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}
