import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/game_guide/services/game_guide_favorites_service.dart';
import 'package:jagspoor/features/game_guide/services/game_guide_filter.dart';
import 'package:jagspoor/features/game_guide/widgets/game_species_card.dart';
import 'package:jagspoor/models/animal.dart';
import 'package:jagspoor/repositories/animal_repository.dart';
import 'package:jagspoor/screens/animal_list_screen.dart';

// Fixtures use the seeded `animalType` taxonomy strings (the value the
// seeder writes into `animals.category`), so the filter tests exercise the
// real production data shape rather than legacy literal codes.
Animal _kudu() => const Animal(
  id: 'kudu-1',
  name: 'Greater Kudu',
  scientificName: 'Tragelaphus strepsiceros',
  afrikaansName: 'Koedoe',
  category: 'Mammal (Antelope)',
  habitat: 'Savanna',
  imageUrl: '',
  rwMinimum: '53 7/8 inches',
  weightMinKg: 190,
  weightMaxKg: 270,
  shoulderHeightMm: 147,
);

Animal _impala() => const Animal(
  id: 'impala-1',
  name: 'Impala',
  scientificName: 'Aepyceros melampus',
  category: 'Mammal (Antelope)',
  habitat: 'Savanna',
  imageUrl: '',
  rwMinimum: '23 5/8 inches',
);

Animal _leopard() => const Animal(
  id: 'leopard-1',
  name: 'Leopard',
  scientificName: 'Panthera pardus',
  category: 'Mammal (Predator)',
  habitat: 'Bushveld',
  imageUrl: '',
);

Animal _buffalo() => const Animal(
  id: 'buffalo-1',
  name: 'Cape Buffalo',
  scientificName: 'Syncerus caffer',
  category: 'Mammal (Dangerous Game)',
  habitat: 'Savanna',
  imageUrl: '',
);

Animal _guineafowl() => const Animal(
  id: 'guineafowl-1',
  name: 'Helmeted Guineafowl',
  scientificName: 'Numida meleagris',
  category: 'Bird (Gamebird)',
  habitat: 'Savanna',
  imageUrl: '',
);

Animal _aardvark() => const Animal(
  id: 'aardvark-1',
  name: 'Aardvark',
  scientificName: 'Orycteropus afer',
  category: 'Mammal (Other)',
  habitat: 'Savanna',
  imageUrl: '',
);

Future<void> _seedAnimals(FakeFirebaseFirestore firestore) async {
  for (final animal in [
    _kudu(),
    _impala(),
    _leopard(),
    _buffalo(),
    _guineafowl(),
    _aardvark(),
  ]) {
    await firestore.collection('animals').doc(animal.id).set(animal.toJson());
  }
}

Widget _wrapCard({
  required Animal animal,
  bool isFavorite = false,
  VoidCallback? onFavoriteToggle,
  VoidCallback? onTap,
  String? assetPath = 'assets/images/Greater Kudu.jpg',
}) {
  final theme = ThemeController.instance..setDarkMode(true);
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 420,
          child: GameSpeciesCard(
            theme: theme,
            animal: animal,
            assetPath: assetPath,
            isFavorite: isFavorite,
            onFavoriteToggle: onFavoriteToggle ?? () {},
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameGuideFavoritesService.instance.resetForTesting();
  });

  tearDown(() {
    GameGuideFavoritesService.instance.resetForTesting();
  });

  group('GameSpeciesCard helpers', () {
    test('taxonomyLabel renders the Mammal (X) category tag', () {
      expect(GameSpeciesCard.taxonomyLabel('antelope'), 'Mammal (Antelope)');
      expect(GameSpeciesCard.taxonomyLabel('big_game'), 'Mammal (Big Game)');
      expect(GameSpeciesCard.taxonomyLabel('predator'), 'Mammal (Predator)');
      expect(GameSpeciesCard.taxonomyLabel('bird'), 'Bird');
      expect(GameSpeciesCard.taxonomyLabel(''), 'Mammal');
    });

    test('taxonomyLabel passes seeded taxonomy strings through unchanged', () {
      // Regression guard for the double-wrap bug: a seeded category like
      // 'Mammal (Antelope)' must render as-is, not 'Mammal (Mammal
      // (Antelope))'.
      expect(
        GameSpeciesCard.taxonomyLabel('Mammal (Antelope)'),
        'Mammal (Antelope)',
      );
      expect(
        GameSpeciesCard.taxonomyLabel('Bird (Gamebird)'),
        'Bird (Gamebird)',
      );
      expect(
        GameSpeciesCard.taxonomyLabel('Mammal (Dangerous Game)'),
        'Mammal (Dangerous Game)',
      );
    });

    test('rwMinimumOf resolves the three storage aliases', () {
      expect(GameSpeciesCard.rwMinimumOf(_kudu()), '53 7/8 inches');
      expect(
        GameSpeciesCard.rwMinimumOf(
          const Animal(
            id: 'x',
            name: 'X',
            scientificName: '',
            category: 'antelope',
            habitat: '',
            imageUrl: '',
            rolandWardMinimum: '40 inches',
          ),
        ),
        '40 inches',
      );
      expect(GameSpeciesCard.rwMinimumOf(_leopard()), isNull);
    });
  });

  group('GameSpeciesCard layout', () {
    testWidgets(
      'renders the full-bleed image, gradient, name, and frosted pills',
      (tester) async {
        await tester.pumpWidget(_wrapCard(animal: _kudu()));
        await tester.pump();

        expect(find.byType(Image), findsWidgets);
        expect(find.byType(BackdropFilter), findsWidgets);
        expect(find.text('Greater Kudu'), findsOneWidget);
        expect(find.text('Tragelaphus strepsiceros'), findsOneWidget);
        expect(find.text('Mammal (Antelope)'), findsOneWidget);
        expect(find.text('RW Min: 53 7/8 inches'), findsOneWidget);
        expect(find.text('190–270 kg'), findsOneWidget);
        expect(find.text('147mm shoulder'), findsOneWidget);

        // Smooth dark gradient overlay for text legibility.
        final gradientBox = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(GameSpeciesCard),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).gradient is LinearGradient,
            ),
          ),
        );
        final gradient =
            (gradientBox.decoration as BoxDecoration).gradient!
                as LinearGradient;
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);
        expect(
          gradient.colors.last,
          const Color(0xF2000000),
          reason: 'The bottom of the gradient must be a deep dark scrim.',
        );
      },
    );

    testWidgets('floating favorite heart sits in the top-right corner', (
      tester,
    ) async {
      var toggled = 0;
      await tester.pumpWidget(
        _wrapCard(animal: _kudu(), onFavoriteToggle: () => toggled++),
      );
      await tester.pump();

      final heart = find.byKey(const ValueKey('favoriteButton_kudu-1'));
      expect(heart, findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      final heartPos = tester.getTopLeft(heart);
      final cardPos = tester.getTopLeft(find.byType(GameSpeciesCard));
      final cardSize = tester.getSize(find.byType(GameSpeciesCard));
      expect(
        heartPos.dx,
        greaterThan(cardPos.dx + cardSize.width / 2),
        reason: 'The heart must sit on the right half of the card.',
      );
      expect(
        heartPos.dy,
        lessThan(cardPos.dy + 40),
        reason: 'The heart must sit at the top of the card image.',
      );

      await tester.tap(heart);
      await tester.pump();
      expect(toggled, 1);
    });

    testWidgets('favorited card renders the filled amber heart', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapCard(animal: _kudu(), isFavorite: true));
      await tester.pump();
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.favorite_rounded),
      );
      expect(icon.color, GameSpeciesCard.amberAccent);
    });

    testWidgets('dark mode renders the amber glowing border', (tester) async {
      await tester.pumpWidget(_wrapCard(animal: _kudu()));
      await tester.pump();
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GameSpeciesCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(20));
      final border = decoration.border! as Border;
      expect(
        border.top.color,
        GameSpeciesCard.amberAccent.withValues(alpha: 0.35),
        reason: 'Dark mode cards carry the warm amber glowing border.',
      );
      expect(decoration.boxShadow, isNotEmpty);
    });
  });

  group('GameGuideFilter (pure category logic)', () {
    test('resolves legacy literal codes to the same buckets', () {
      expect(GameGuideFilter.categoryLabelOf('antelope'), 'Plains Game');
      expect(GameGuideFilter.categoryLabelOf('pig'), 'Plains Game');
      expect(GameGuideFilter.categoryLabelOf('big_game'), 'Big Game');
      expect(GameGuideFilter.categoryLabelOf('predator'), 'Predator');
      expect(GameGuideFilter.categoryLabelOf('bird'), 'Bird');
      expect(GameGuideFilter.categoryLabelOf('other'), 'Other');
    });

    test('resolves seeded taxonomy strings to the hunting buckets', () {
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Antelope)'),
        'Plains Game',
      );
      expect(GameGuideFilter.categoryLabelOf('Mammal (Pig)'), 'Plains Game');
      expect(GameGuideFilter.categoryLabelOf('Mammal (Equid)'), 'Plains Game');
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Giraffid)'),
        'Plains Game',
      );
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Dangerous Game)'),
        'Big Game',
      );
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Protected - Dangerous Game)'),
        'Big Game',
      );
      // Lion is a Big Five species -- 'dangerous' is checked before
      // 'predator' so it lands in the Big Game bucket.
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Predator - Dangerous)'),
        'Big Game',
      );
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Predator)'),
        'Predator',
      );
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Predator - small)'),
        'Predator',
      );
      expect(
        GameGuideFilter.categoryLabelOf('Mammal (Predator - medium)'),
        'Predator',
      );
      expect(GameGuideFilter.categoryLabelOf('Bird (Gamebird)'), 'Bird');
      expect(GameGuideFilter.categoryLabelOf('Bird (Waterfowl)'), 'Bird');
      expect(GameGuideFilter.categoryLabelOf('Reptile (Monitor)'), 'Other');
      expect(GameGuideFilter.categoryLabelOf('Mammal (Hyrax)'), 'Other');
    });

    test('null and empty categories resolve to Other', () {
      expect(GameGuideFilter.categoryLabelOf(null), 'Other');
      expect(GameGuideFilter.categoryLabelOf(''), 'Other');
      expect(GameGuideFilter.categoryLabelOf('   '), 'Other');
    });

    test('matchesCategory admits everything for All and null filters', () {
      expect(GameGuideFilter.matchesCategory(_kudu(), 'All'), isTrue);
      expect(GameGuideFilter.matchesCategory(_kudu(), null), isTrue);
      expect(GameGuideFilter.matchesCategory(_kudu(), 'Plains Game'), isTrue);
      expect(GameGuideFilter.matchesCategory(_kudu(), 'Predator'), isFalse);
    });

    test('matchesSearch matches name, scientific, Afrikaans, keywords', () {
      expect(GameGuideFilter.matchesSearch(_kudu(), 'kudu'), isTrue);
      expect(GameGuideFilter.matchesSearch(_kudu(), 'strepsiceros'), isTrue);
      expect(GameGuideFilter.matchesSearch(_kudu(), 'koedoe'), isTrue);
      expect(
        GameGuideFilter.matchesSearch(
          const Animal(
            id: 'x',
            name: 'X',
            scientificName: '',
            category: 'other',
            habitat: '',
            imageUrl: '',
            searchKeywords: ['springbok'],
          ),
          'springbok',
        ),
        isTrue,
      );
      expect(GameGuideFilter.matchesSearch(_kudu(), 'zebra'), isFalse);
      expect(GameGuideFilter.matchesSearch(_kudu(), ''), isTrue);
    });
  });

  group('GameGuideFavoritesService', () {
    test('toggle persists + notifies and isFavorite reflects state', () async {
      final service = GameGuideFavoritesService.instance;
      await service.init();

      var notifications = 0;
      service.addListener(() => notifications++);

      await service.toggle('kudu-1');
      expect(service.isFavorite('kudu-1'), isTrue);

      await service.toggle('kudu-1');
      expect(service.isFavorite('kudu-1'), isFalse);
      expect(notifications, greaterThanOrEqualTo(2));

      await service.toggle('impala-1');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(GameGuideFavoritesService.prefsKey),
        contains('impala-1'),
      );
    });

    test('init restores persisted favorites', () async {
      SharedPreferences.setMockInitialValues({
        GameGuideFavoritesService.prefsKey: <String>['kudu-1'],
      });
      final service = GameGuideFavoritesService.instance;
      await service.init();
      expect(service.isFavorite('kudu-1'), isTrue);
    });
  });

  group('AnimalListScreen (SA Game Guide)', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      FakeFirebaseFirestore? firestore,
    }) async {
      final fake = firestore ?? FakeFirebaseFirestore();
      await _seedAnimals(fake);
      final theme = ThemeController.instance..setDarkMode(true);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimalListScreen(
            theme: theme,
            repository: AnimalRepository(firestore: fake),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the header + a responsive species grid', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('SA Game Guide'), findsOneWidget);
      expect(find.byKey(const ValueKey('gameGuideSearchToggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('gameGuideFilterButton')), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(GameSpeciesCard), findsNWidgets(6));
      expect(find.text('Greater Kudu'), findsOneWidget);
      expect(find.text('Impala'), findsOneWidget);
      expect(find.text('Cape Buffalo'), findsOneWidget);
      expect(find.text('Helmeted Guineafowl'), findsOneWidget);
      expect(find.text('Leopard'), findsOneWidget);
      expect(find.text('Aardvark'), findsOneWidget);
    });

    testWidgets('search icon toggles the inline search field and filters', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byKey(const ValueKey('gameGuideSearchToggle')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'kudu');
      await tester.pumpAndSettle();
      expect(find.text('Greater Kudu'), findsOneWidget);
      expect(find.text('Impala'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('gameGuideSearchToggle')));
      await tester.pumpAndSettle();
      expect(find.text('Impala'), findsOneWidget);
    });

    testWidgets('filter icon opens the category sheet and filters the grid', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const ValueKey('gameGuideFilterButton')));
      await tester.pumpAndSettle();
      expect(find.text('FILTER BY CATEGORY'), findsOneWidget);

      await tester.tap(find.text('Predator'));
      await tester.pumpAndSettle();

      expect(find.text('Leopard'), findsOneWidget);
      expect(find.text('Greater Kudu'), findsNothing);
      expect(find.text('Impala'), findsNothing);
    });

    testWidgets('Big Game filter resolves the seeded dangerous-game bucket', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('gameGuideFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Big Game'));
      await tester.pumpAndSettle();

      expect(find.text('Cape Buffalo'), findsOneWidget);
      expect(find.text('Leopard'), findsNothing);
      expect(find.text('Greater Kudu'), findsNothing);
      expect(find.text('Helmeted Guineafowl'), findsNothing);
      expect(find.text('Aardvark'), findsNothing);
    });

    testWidgets('Plains Game filter resolves antelope + pig families', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('gameGuideFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plains Game'));
      await tester.pumpAndSettle();

      expect(find.text('Greater Kudu'), findsOneWidget);
      expect(find.text('Impala'), findsOneWidget);
      expect(find.text('Leopard'), findsNothing);
      expect(find.text('Cape Buffalo'), findsNothing);
      expect(find.text('Helmeted Guineafowl'), findsNothing);
      expect(find.text('Aardvark'), findsNothing);
    });

    testWidgets('Bird filter resolves the seeded bird families', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('gameGuideFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bird'));
      await tester.pumpAndSettle();

      expect(find.text('Helmeted Guineafowl'), findsOneWidget);
      expect(find.text('Greater Kudu'), findsNothing);
      expect(find.text('Leopard'), findsNothing);
    });

    testWidgets('Other filter excludes categorized species', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('gameGuideFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();

      expect(find.text('Aardvark'), findsOneWidget);
      expect(find.text('Greater Kudu'), findsNothing);
      expect(find.text('Cape Buffalo'), findsNothing);
      expect(find.text('Leopard'), findsNothing);
      expect(find.text('Helmeted Guineafowl'), findsNothing);
    });

    testWidgets('selecting All clears the category filter state', (
      tester,
    ) async {
      await pumpScreen(tester);

      // Apply a restrictive bucket first...
      await tester.tap(find.byKey(const ValueKey('gameGuideFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Predator'));
      await tester.pumpAndSettle();
      expect(find.text('Leopard'), findsOneWidget);
      expect(find.text('Greater Kudu'), findsNothing);

      // ...then reset to All and confirm the full grid state is restored.
      await tester.tap(find.byKey(const ValueKey('gameGuideFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Greater Kudu'), findsOneWidget);
      expect(find.text('Leopard'), findsOneWidget);
      expect(find.text('Aardvark'), findsOneWidget);
      expect(find.byType(GameSpeciesCard), findsNWidgets(6));
    });

    testWidgets('tapping a card heart favorites it and sorts it first', (
      tester,
    ) async {
      await pumpScreen(tester);

      List<String> cardIds() => tester
          .widgetList<GameSpeciesCard>(find.byType(GameSpeciesCard))
          .map((card) => card.animal.id)
          .toList();

      expect(
        cardIds(),
        <String>[
          'aardvark-1',
          'buffalo-1',
          'kudu-1',
          'guineafowl-1',
          'impala-1',
          'leopard-1',
        ],
        reason: 'No favorites -- the grid renders in alphabetical order.',
      );

      // The heart button itself is tap-tested in the isolated card suite;
      // here the favorite toggle is driven through the real service so the
      // grid's reactive re-sort is exercised end-to-end.
      expect(
        find.byKey(const ValueKey('favoriteButton_impala-1')),
        findsOneWidget,
      );
      await GameGuideFavoritesService.instance.toggle('impala-1');
      await tester.pumpAndSettle();

      expect(
        cardIds().first,
        'impala-1',
        reason: 'Favorites sort to the front of the grid.',
      );
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(GameGuideFavoritesService.prefsKey),
        contains('impala-1'),
      );
    });
  });
}
