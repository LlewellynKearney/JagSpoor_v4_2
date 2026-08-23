import '../../screens/animal_list_screen.dart';

/// Convenience re-exports so feature-module consumers need a single import.
export '../../screens/animal_list_screen.dart' show AnimalListScreen;
export 'services/game_guide_favorites_service.dart';
export 'widgets/game_species_card.dart';

/// Canonical SA Game Guide screen under the `features/game_guide` module.
///
/// The polished implementation (rich media [GameSpeciesCard] grid, quick
/// search + filter header actions) lives in
/// `lib/screens/animal_list_screen.dart` as [AnimalListScreen]; this alias
/// keeps the feature-module entry point without duplicating the screen.
class GameGuideScreen extends AnimalListScreen {
  const GameGuideScreen({super.key, required super.theme, super.repository});
}
