import '../../../models/animal.dart';

/// SA Game Guide category filter logic.
///
/// The seeder stores the raw CSV `animalType` taxonomy string (e.g.
/// `Mammal (Antelope)`, `Mammal (Dangerous Game)`, `Bird (Gamebird)`) in
/// `animals.category`, while the guide's filter chips are hunting buckets
/// (Big Game / Plains Game / Predator / Bird). The raw taxonomy therefore
/// has to be mapped into a bucket before filtering -- the legacy bug was a
/// switch that only matched the legacy literal codes (`antelope`,
/// `big_game`, ...), so seeded data collapsed every animal into the
/// `Other` bucket and the category filter silently matched nothing.
///
/// Legacy literal codes written by older app versions resolve to the same
/// buckets, so the mapping is backward compatible. Pure static API -- no
/// Flutter imports -- so it is fully unit-testable.
class GameGuideFilter {
  static const String all = 'All';
  static const String bigGame = 'Big Game';
  static const String plainsGame = 'Plains Game';
  static const String predator = 'Predator';
  static const String bird = 'Bird';
  static const String other = 'Other';

  /// The category options offered in the filter sheet, in display order.
  static const List<String> categories = <String>[
    all,
    bigGame,
    plainsGame,
    predator,
    bird,
    other,
  ];

  /// Word-boundary matcher so `Mammal (Pig)` resolves to Plains Game while
  /// an accidental substring of another word cannot match.
  static final RegExp _pigWord = RegExp(r'\bpig\b');

  /// Resolves the raw `animals.category` taxonomy value into one of the
  /// filter buckets in [categories] (excluding [all]).
  static String categoryLabelOf(String? category) {
    final value = category?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return other;

    // Legacy literal codes (older docs + legacy seeds).
    switch (value) {
      case 'big_game':
        return bigGame;
      case 'antelope':
      case 'pig':
        return plainsGame;
      case 'predator':
        return predator;
      case 'bird':
        return bird;
    }

    // Seeded full-taxonomy strings, e.g. 'Mammal (Antelope)'. Dangerous
    // game is checked before predator so 'Mammal (Predator - Dangerous)'
    // (Lion -- a Big Five species) lands in Big Game.
    if (value.contains('dangerous')) return bigGame;
    if (value.contains('predator')) return predator;
    if (value.contains('antelope') ||
        value.contains('equid') ||
        value.contains('giraffid') ||
        _pigWord.hasMatch(value)) {
      return plainsGame;
    }
    if (value.startsWith('bird')) return bird;

    return other;
  }

  /// Whether [animal] belongs to [filter] (the [all] bucket admits every
  /// animal, so selecting 'All' clears the category constraint).
  static bool matchesCategory(Animal animal, String? filter) {
    if (filter == null || filter == all) return true;
    return categoryLabelOf(animal.category) == filter;
  }

  /// Whether [animal] matches the free-text search [query] across its name,
  /// scientific name, Afrikaans name, and search keywords.
  static bool matchesSearch(Animal animal, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (animal.name.toLowerCase().contains(normalized)) return true;
    if (animal.scientificName.toLowerCase().contains(normalized)) {
      return true;
    }
    if (animal.afrikaansName?.toLowerCase().contains(normalized) ?? false) {
      return true;
    }
    return animal.searchKeywords.any(
      (keyword) => keyword.toLowerCase().contains(normalized),
    );
  }
}
