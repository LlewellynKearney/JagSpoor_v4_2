import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed store for the hunter's favorited SA Game Guide
/// species. Process-wide singleton so the guide grid and the species cards
/// always read the same favorite set; every mutation notifies listeners so
/// the UI re-renders instantly.
class GameGuideFavoritesService extends ChangeNotifier {
  GameGuideFavoritesService._();

  static final GameGuideFavoritesService instance =
      GameGuideFavoritesService._();

  static const String prefsKey = 'game_guide_favorite_species';

  final Set<String> _favoriteIds = <String>{};
  bool _loaded = false;

  /// The current favorite species ids (unmodifiable view).
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  bool isFavorite(String speciesId) => _favoriteIds.contains(speciesId);

  /// Load the persisted favorites once. Safe to call repeatedly.
  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _favoriteIds
        ..clear()
        ..addAll(prefs.getStringList(prefsKey) ?? const <String>[]);
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  /// Toggle [speciesId] and persist the new set.
  Future<void> toggle(String speciesId) async {
    if (_favoriteIds.contains(speciesId)) {
      _favoriteIds.remove(speciesId);
    } else {
      _favoriteIds.add(speciesId);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, _favoriteIds.toList());
    } catch (_) {}
  }

  /// Sort helper: favorites first, then alphabetical by species name.
  static int favoritesFirstComparator<T>(
    T a,
    T b,
    String Function(T) idOf,
    String Function(T) nameOf,
    Set<String> favoriteIds,
  ) {
    final aFav = favoriteIds.contains(idOf(a));
    final bFav = favoriteIds.contains(idOf(b));
    if (aFav != bFav) return aFav ? -1 : 1;
    return nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase());
  }

  /// Test seam: clears the in-memory set + loaded flag.
  @visibleForTesting
  void resetForTesting() {
    _favoriteIds.clear();
    _loaded = false;
  }
}
