import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/animal.dart';
import '../repositories/animal_repository.dart';
import 'animal_detail_screen.dart';

class AnimalListScreen extends StatefulWidget {
  final ThemeController theme;

  const AnimalListScreen({super.key, required this.theme});

  @override
  State<AnimalListScreen> createState() => _AnimalListScreenState();
}

class _AnimalListScreenState extends State<AnimalListScreen> {
  final AnimalRepository _repository = AnimalRepository();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Animal animal, String query) {
    if (query.isEmpty) return true;
    final normalized = query.toLowerCase().trim();

    if (animal.name.toLowerCase().contains(normalized)) return true;
    if (animal.afrikaansName?.toLowerCase().contains(normalized) ?? false) {
      return true;
    }
    return animal.searchKeywords.any(
      (keyword) => keyword.toLowerCase().contains(normalized),
    );
  }

  String _categoryLabel(String category) {
    switch (category.toLowerCase()) {
      case 'big_game':
        return 'Big Game';
      case 'antelope':
        return 'Plains Game';
      case 'predator':
        return 'Predator';
      case 'pig':
        return 'Plains Game';
      case 'bird':
        return 'Bird';
      default:
        if (category.isEmpty) return 'Other';
        return category
            .split('_')
            .map(
              (part) => part.isEmpty
                  ? part
                  : '${part[0].toUpperCase()}${part.substring(1)}',
            )
            .join(' ');
    }
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'big_game':
        return Icons.terrain_rounded;
      case 'antelope':
        return Icons.brightness_low_rounded;
      case 'predator':
        return Icons.pets_rounded;
      case 'pig':
        return Icons.brightness_low_rounded;
      case 'bird':
        return Icons.flight_rounded;
      default:
        return Icons.cruelty_free_rounded;
    }
  }

  String? _getAssetPathForAnimal(String animalName) {
    final sanitized = animalName
        .replaceAll("'", '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    final assetPath = 'assets/images/$sanitized.jpg';
    return assetPath;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        final theme = widget.theme;

        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'SA Game Guide',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: theme.backgroundColor,
            iconTheme: IconThemeData(color: theme.accentColor),
            elevation: 0,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: theme.textColor),
                    decoration: InputDecoration(
                      hintText: 'Search species, Afrikaans name…',
                      hintStyle: TextStyle(color: theme.subtitleColor),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: theme.accentColor,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: theme.subtitleColor,
                              ),
                              onPressed: _searchController.clear,
                            )
                          : null,
                      filled: true,
                      fillColor: theme.cardColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.accentColor.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.accentColor.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.accentColor),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Animal>>(
                    stream: _repository.watchAnimals(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Unable to load species guide.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.subtitleColor),
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: theme.accentColor,
                          ),
                        );
                      }

                      final animals = snapshot.data ?? [];
                      final filtered = animals
                          .where(
                            (animal) => _matchesSearch(animal, _searchQuery),
                          )
                          .toList();

                      if (animals.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No species in the guide yet.\nConnect online once to sync the catalogue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.subtitleColor),
                            ),
                          ),
                        );
                      }

                      if (filtered.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No species match "$_searchQuery".',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.subtitleColor),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16 + MediaQuery.of(context).padding.bottom,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final animal = filtered[index];
                          return _AnimalListCard(
                            theme: theme,
                            animal: animal,
                            categoryLabel: _categoryLabel(animal.category),
                            categoryIcon: _categoryIcon(animal.category),
                            assetPath: _getAssetPathForAnimal(animal.name),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AnimalDetailScreen(
                                    theme: theme,
                                    animal: animal,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AnimalListCard extends StatelessWidget {
  final ThemeController theme;
  final Animal animal;
  final String categoryLabel;
  final IconData categoryIcon;
  final String? assetPath;
  final VoidCallback onTap;

  const _AnimalListCard({
    required this.theme,
    required this.animal,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.assetPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rwLabel = animal.rwMinimum?.trim() ??
        animal.rolandWardMinimum?.trim() ??
        animal.trophyMinimumRW?.trim();
    final hasAsset = assetPath != null && assetPath!.isNotEmpty;

    return Card(
      color: theme.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: hasAsset
                      ? Image.asset(
                          assetPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              ColoredBox(
                                color: theme.backgroundColor,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: theme.subtitleColor,
                                ),
                              ),
                        )
                      : ColoredBox(
                          color: theme.backgroundColor,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: theme.subtitleColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animal.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R.W. Min: ${rwLabel == null || rwLabel.isEmpty ? '—' : rwLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.subtitleColor,
                      ),
                    ),
                    if (animal.afrikaansName != null &&
                        animal.afrikaansName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        animal.afrikaansName!,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.subtitleColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _InfoChip(
                          theme: theme,
                          icon: categoryIcon,
                          label: categoryLabel,
                        ),
                        _InfoChip(
                          theme: theme,
                          icon: Icons.emoji_events_rounded,
                          label: rwLabel != null && rwLabel.isNotEmpty
                              ? 'RW Min: $rwLabel'
                              : 'RW Min: —',
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
    );
  }
}

class _InfoChip extends StatelessWidget {
  final ThemeController theme;
  final IconData? icon;
  final String label;

  const _InfoChip({required this.theme, this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: theme.accentColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.textColor,
            ),
          ),
        ],
      ),
    );
  }
}
