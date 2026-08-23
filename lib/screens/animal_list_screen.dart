import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/copyright_footer.dart';
import '../features/game_guide/services/game_guide_favorites_service.dart';
import '../features/game_guide/widgets/game_species_card.dart';
import '../features/hunter_mode/widgets/hunter_scaffold.dart';
import '../models/animal.dart';
import '../repositories/animal_repository.dart';
import 'animal_detail_screen.dart';

/// SA Game Guide — polished promotional species browser.
///
/// Clean header typography with quick-access search + filter actions on the
/// right, and a responsive high-density grid of [GameSpeciesCard] rich media
/// cards (full-bleed photo, frosted pills, amber glow borders).
class AnimalListScreen extends StatefulWidget {
  final ThemeController theme;

  /// Test seam: inject a repository backed by a fake Firestore so the grid
  /// can be exercised without a live Firebase app.
  @visibleForTesting
  final AnimalRepository? repository;

  const AnimalListScreen({super.key, required this.theme, this.repository});

  @override
  State<AnimalListScreen> createState() => _AnimalListScreenState();
}

class _AnimalListScreenState extends State<AnimalListScreen> {
  late final AnimalRepository _repository =
      widget.repository ?? AnimalRepository();
  final GameGuideFavoritesService _favorites = GameGuideFavoritesService.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _searchActive = false;
  String _categoryFilter = 'All';

  Set<String> get _favoriteIds => _favorites.favoriteIds;

  static const List<String> _filterOptions = <String>[
    'All',
    'Big Game',
    'Plains Game',
    'Predator',
    'Bird',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    _favorites.addListener(_onFavoritesChanged);
    _favorites.init();
  }

  @override
  void dispose() {
    _favorites.removeListener(_onFavoritesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  bool _matchesSearch(Animal animal, String query) {
    if (query.isEmpty) return true;
    final normalized = query.toLowerCase().trim();

    if (animal.name.toLowerCase().contains(normalized)) return true;
    if (animal.scientificName.toLowerCase().contains(normalized)) return true;
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
        return 'Other';
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

  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchController.clear();
      }
    });
  }

  void _openFilterSheet() {
    final theme = widget.theme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.subtitleColor.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'FILTER BY CATEGORY',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: theme.textColor,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in _filterOptions)
                      ChoiceChip(
                        label: Text(option),
                        selected: _categoryFilter == option,
                        selectedColor: theme.accentColor.withValues(alpha: 0.25),
                        backgroundColor: theme.backgroundColor,
                        side: BorderSide(
                          color:
                              _categoryFilter == option
                                  ? theme.accentColor
                                  : theme.subtitleColor.withValues(alpha: 0.3),
                        ),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              _categoryFilter == option
                                  ? theme.accentColor
                                  : theme.textColor,
                        ),
                        onSelected: (_) {
                          setState(() => _categoryFilter = option);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeController theme) {
    return AppBar(
      title:
          _searchActive
              ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: theme.textColor, fontSize: 16),
                cursorColor: theme.accentColor,
                decoration: InputDecoration(
                  hintText: 'Search species, Afrikaans name…',
                  hintStyle: TextStyle(color: theme.subtitleColor),
                  border: InputBorder.none,
                  isDense: true,
                ),
              )
              : Text(
                'SA Game Guide',
                style: TextStyle(
                  color: HunterUi.titleColor(theme),
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 0.4,
                ),
              ),
      backgroundColor: Colors.transparent,
      iconTheme: IconThemeData(color: HunterUi.titleColor(theme)),
      elevation: 0,
      actions: [
        IconButton(
          key: const ValueKey('gameGuideSearchToggle'),
          tooltip: _searchActive ? 'Close search' : 'Search species',
          icon: Icon(
            _searchActive ? Icons.close_rounded : Icons.search_rounded,
            color:
                _searchActive
                    ? theme.accentColor
                    : HunterUi.titleColor(theme),
          ),
          onPressed: _toggleSearch,
        ),
        IconButton(
          key: const ValueKey('gameGuideFilterButton'),
          tooltip: 'Filter by category',
          icon: Icon(
            Icons.tune_rounded,
            color:
                _categoryFilter != 'All'
                    ? theme.accentColor
                    : HunterUi.titleColor(theme),
          ),
          onPressed: _openFilterSheet,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        final theme = widget.theme;

        return HunterScaffold(
          theme: theme,
          padBodyForAppBar: true,
          appBar: _buildAppBar(theme),
          body: SafeArea(
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
                    child: CircularProgressIndicator(color: theme.accentColor),
                  );
                }

                final animals = snapshot.data ?? [];
                final filtered =
                    animals
                        .where(
                          (animal) => _matchesSearch(animal, _searchQuery),
                        )
                        .where(
                          (animal) =>
                              _categoryFilter == 'All' ||
                              _categoryLabel(animal.category) ==
                                  _categoryFilter,
                        )
                        .toList()
                      ..sort(_favoritesFirst);

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
                        _searchQuery.isNotEmpty
                            ? 'No species match "$_searchQuery".'
                            : 'No species in the "$_categoryFilter" category.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.subtitleColor),
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 280,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                  itemCount: filtered.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      return const Center(child: CopyrightFooter());
                    }
                    final animal = filtered[index];
                    return GameSpeciesCard(
                      theme: theme,
                      animal: animal,
                      assetPath: _getAssetPathForAnimal(animal.name),
                      isFavorite: _favoriteIds.contains(animal.id),
                      onFavoriteToggle: () => _favorites.toggle(animal.id),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => AnimalDetailScreen(
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
        );
      },
    );
  }

  int _favoritesFirst(Animal a, Animal b) {
    final aFav = _favoriteIds.contains(a.id);
    final bFav = _favoriteIds.contains(b.id);
    if (aFav != bFav) return aFav ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}
