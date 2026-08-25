import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/animal.dart';
import '../../shared/widgets/hunter_media_card.dart';

/// Rich media species card for the SA Game Guide.
///
/// The animal's photo is a full-bleed background with a smooth dark gradient
/// overlay for text legibility. A frosted heart action floats in the
/// top-right corner of the image, and the data attributes (category tag,
/// Rowland Ward record minimum, measurement stats) render as translucent
/// amber / dark frosted-glass pills overlaid across the lower section.
///
/// The card is built on the shared [HunterMediaCard] rich-media container --
/// the same design language now used across Hunter Mode's tactical modules.
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
  static const Color amberAccent = kHunterMediaAmber;

  /// Category tag rendered as a taxonomy-style pill, e.g. "Mammal (Antelope)".
  static String taxonomyLabel(String category) {
    final trimmed = category.trim();
    switch (trimmed.toLowerCase()) {
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
        if (trimmed.isEmpty) return 'Mammal';
        // The seeder stores fully-qualified taxonomy strings (e.g.
        // 'Mammal (Antelope)', 'Bird (Gamebird)'). Pass those through
        // unchanged instead of wrapping them in 'Mammal (...)' a second
        // time (the double-wrap display bug).
        if (trimmed.contains('(') || trimmed.contains(' ')) {
          return trimmed;
        }
        final pretty = trimmed
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

    return HunterMediaCard(
      theme: theme,
      image: hasAsset ? AssetImage(assetPath!) : null,
      fallbackIcon: Icons.cruelty_free_rounded,
      title: animal.name,
      subtitle: animal.scientificName.isNotEmpty ? animal.scientificName : null,
      topLeftPill: HunterMediaPill(
        icon: Icons.cruelty_free_rounded,
        label: taxonomyLabel(animal.category),
        amber: true,
      ),
      topRightActions: [
        HunterFrostedCircleButton(
          key: ValueKey('favoriteButton_${animal.id}'),
          icon:
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
          iconColor: isFavorite ? amberAccent : const Color(0xFFF5F1E8),
          onPressed: onFavoriteToggle,
        ),
      ],
      pills: [
        HunterMediaPill(
          icon: Icons.emoji_events_rounded,
          label: rwMinimum != null ? 'RW Min: $rwMinimum' : 'RW Min: N/A',
          amber: true,
        ),
        if (weightRange != null)
          HunterMediaPill(
            icon: Icons.monitor_weight_outlined,
            label: weightRange,
          ),
        if (shoulderHeight != null)
          HunterMediaPill(
            icon: Icons.straighten_rounded,
            label: '${shoulderHeight}mm shoulder',
          ),
      ],
      onTap: onTap,
    );
  }
}
