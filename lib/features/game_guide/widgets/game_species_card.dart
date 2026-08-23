import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/animal.dart';
import '../../hunter_mode/widgets/hunter_scaffold.dart' show HunterUi;

/// Rich media species card for the SA Game Guide.
///
/// The animal's photo is a full-bleed background with a smooth dark gradient
/// overlay for text legibility. A frosted heart action floats in the
/// top-right corner of the image, and the data attributes (category tag,
/// Rowland Ward record minimum, measurement stats) render as translucent
/// amber / dark frosted-glass pills overlaid across the lower section.
class GameSpeciesCard extends StatelessWidget {
  final ThemeController theme;
  final Animal animal;
  final String? assetPath;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;

  const GameSpeciesCard({
    super.key,
    required this.theme,
    required this.animal,
    required this.assetPath,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  /// Brushed-gold accent used for the amber glow border + frosted pills.
  static const Color amberAccent = Color(0xFFD4AF37);

  /// Category tag rendered as a taxonomy-style pill, e.g. "Mammal (Antelope)".
  static String taxonomyLabel(String category) {
    switch (category.toLowerCase()) {
      case 'antelope':
        return 'Mammal (Antelope)';
      case 'big_game':
        return 'Mammal (Big Game)';
      case 'predator':
        return 'Mammal (Predator)';
      case 'pig':
        return 'Mammal (Pig)';
      case 'bird':
        return 'Bird';
      default:
        if (category.isEmpty) return 'Mammal';
        final pretty = category
            .split('_')
            .map(
              (part) =>
                  part.isEmpty
                      ? part
                      : '${part[0].toUpperCase()}${part.substring(1)}',
            )
            .join(' ');
        return 'Mammal ($pretty)';
    }
  }

  /// The resolved Rowland Ward record minimum (the three storage aliases),
  /// or null when the species has no recorded benchmark.
  static String? rwMinimumOf(Animal animal) {
    final value =
        animal.rwMinimum?.trim() ??
        animal.rolandWardMinimum?.trim() ??
        animal.trophyMinimumRW?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final rwMinimum = rwMinimumOf(animal);
    final weightRange = animal.displayWeightRange;
    final shoulderHeight = animal.shoulderHeightMm;
    final hasAsset = assetPath != null && assetPath!.isNotEmpty;
    final isDark = theme.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isDark
                  ? amberAccent.withValues(alpha: 0.35)
                  : HunterUi.cardBorderColor(theme),
          width: isDark ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color:
                isDark
                    ? amberAccent.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.08),
            blurRadius: isDark ? 14 : 8,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Full-bleed species photo.
                hasAsset
                    ? Image.asset(
                      assetPath!,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              _ImageFallback(theme: theme),
                    )
                    : _ImageFallback(theme: theme),
                // Smooth dark gradient overlay for text legibility.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x33000000),
                        Color(0x00000000),
                        Color(0x8C000000),
                        Color(0xF2000000),
                      ],
                      stops: [0.0, 0.35, 0.68, 1.0],
                    ),
                  ),
                ),
                // Floating favorite action, top-right of the image.
                Positioned(
                  top: 8,
                  right: 8,
                  child: _FrostedCircleButton(
                    key: ValueKey('favoriteButton_${animal.id}'),
                    icon:
                        isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                    iconColor:
                        isFavorite ? amberAccent : const Color(0xFFF5F1E8),
                    onPressed: onFavoriteToggle,
                  ),
                ),
                // Category tag pill, top-left of the image.
                Positioned(
                  top: 10,
                  left: 10,
                  child: _FrostedPill(
                    icon: Icons.cruelty_free_rounded,
                    label: taxonomyLabel(animal.category),
                    amber: true,
                  ),
                ),
                // Name + measurement pills across the lower section.
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        animal.name,
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
                      if (animal.scientificName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          animal.scientificName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: Color(0xE6EFE7DC),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _FrostedPill(
                            icon: Icons.emoji_events_rounded,
                            label:
                                rwMinimum != null
                                    ? 'RW Min: $rwMinimum'
                                    : 'RW Min: N/A',
                            amber: true,
                          ),
                          if (weightRange != null)
                            _FrostedPill(
                              icon: Icons.monitor_weight_outlined,
                              label: weightRange,
                            ),
                          if (shoulderHeight != null)
                            _FrostedPill(
                              icon: Icons.straighten_rounded,
                              label: '${shoulderHeight}mm shoulder',
                            ),
                        ],
                      ),
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

class _ImageFallback extends StatelessWidget {
  final ThemeController theme;

  const _ImageFallback({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF2A241F),
      child: Center(
        child: Icon(
          Icons.cruelty_free_rounded,
          size: 56,
          color: theme.accentColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Translucent frosted-glass pill used for the overlaid data attributes.
/// [amber] selects the warm amber frosted variant; otherwise a dark frosted
/// variant is used.
class _FrostedPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool amber;

  const _FrostedPill({this.icon, required this.label, this.amber = false});

  @override
  Widget build(BuildContext context) {
    const amberColor = GameSpeciesCard.amberAccent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color:
                amber
                    ? amberColor.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  amber
                      ? amberColor.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 12,
                  color: amber ? amberColor : const Color(0xFFF0EAE0),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color:
                        amber ? const Color(0xFFF1D894) : const Color(0xFFF0EAE0),
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

/// Small frosted circular icon button floating over the card image.
class _FrostedCircleButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onPressed;

  const _FrostedCircleButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
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
            padding: const EdgeInsets.all(7),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}
