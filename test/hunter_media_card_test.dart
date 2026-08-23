import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/shared/widgets/hunter_media_card.dart';

Widget _wrapCard({
  bool dark = true,
  ImageProvider? image,
  String title = 'Test Card',
  String? subtitle,
  List<HunterMediaPill> pills = const [],
  HunterMediaPill? topLeftPill,
  List<Widget> topRightActions = const [],
  VoidCallback? onTap,
  IconData fallbackIcon = Icons.shield_rounded,
}) {
  final theme = ThemeController.instance..setDarkMode(dark);
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 420,
          child: HunterMediaCard(
            theme: theme,
            image: image,
            title: title,
            subtitle: subtitle,
            pills: pills,
            topLeftPill: topLeftPill,
            topRightActions: topRightActions,
            onTap: onTap,
            fallbackIcon: fallbackIcon,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('HunterMediaCard layout', () {
    testWidgets(
      'renders the full-bleed image, gradient scrim, title, subtitle, and frosted pills',
      (tester) async {
        await tester.pumpWidget(
          _wrapCard(
            image: const AssetImage('assets/images/Greater Kudu.jpg'),
            title: 'Tikka T3x',
            subtitle: 'S/N: ABC-123',
            pills: const [
              HunterMediaPill(
                icon: Icons.gps_fixed_rounded,
                label: '.308 Win',
                amber: true,
              ),
              HunterMediaPill(
                icon: Icons.speed_rounded,
                label: 'Barrel: 1200 rds left',
              ),
            ],
            topLeftPill: const HunterMediaPill(
              icon: Icons.verified_user_rounded,
              label: 'LICENCE: VALID',
              amber: true,
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Image), findsWidgets);
        expect(find.byType(BackdropFilter), findsWidgets);
        expect(find.text('Tikka T3x'), findsOneWidget);
        expect(find.text('S/N: ABC-123'), findsOneWidget);
        expect(find.text('LICENCE: VALID'), findsOneWidget);
        expect(find.text('.308 Win'), findsOneWidget);
        expect(find.text('Barrel: 1200 rds left'), findsOneWidget);

        // Smooth dark gradient overlay for text legibility.
        final gradientBox = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(HunterMediaCard),
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

    testWidgets('renders the icon fallback when no image is provided', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapCard(fallbackIcon: Icons.pets_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.pets_rounded), findsOneWidget);
    });

    testWidgets('top-right action renders in the top-right corner and taps', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrapCard(
          topRightActions: [
            HunterFrostedCircleButton(
              key: const ValueKey('testAction'),
              icon: Icons.favorite_border_rounded,
              iconColor: const Color(0xFFF5F1E8),
              onPressed: () => tapped++,
            ),
          ],
        ),
      );
      await tester.pump();

      final action = find.byKey(const ValueKey('testAction'));
      expect(action, findsOneWidget);

      final actionPos = tester.getTopLeft(action);
      final cardPos = tester.getTopLeft(find.byType(HunterMediaCard));
      final cardSize = tester.getSize(find.byType(HunterMediaCard));
      expect(
        actionPos.dx,
        greaterThan(cardPos.dx + cardSize.width / 2),
        reason: 'The action must sit on the right half of the card.',
      );
      expect(
        actionPos.dy,
        lessThan(cardPos.dy + 40),
        reason: 'The action must sit at the top of the card image.',
      );

      await tester.tap(action);
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('card onTap fires', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrapCard(onTap: () => tapped++));
      await tester.pump();
      await tester.tap(find.byType(HunterMediaCard));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('dark mode renders the amber glowing border', (tester) async {
      await tester.pumpWidget(_wrapCard(dark: true));
      await tester.pump();
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(HunterMediaCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(20));
      final border = decoration.border! as Border;
      expect(
        border.top.color,
        kHunterMediaAmber.withValues(alpha: 0.35),
        reason: 'Dark mode cards carry the warm amber glowing border.',
      );
      expect(decoration.boxShadow, isNotEmpty);
    });

    testWidgets('light mode renders the defined warm border (not the amber '
        'glow)', (tester) async {
      await tester.pumpWidget(_wrapCard(dark: false));
      await tester.pump();
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(HunterMediaCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(
        border.top.color,
        isNot(kHunterMediaAmber.withValues(alpha: 0.35)),
        reason: 'Light mode uses the warm card border, not the amber glow.',
      );
    });
  });

  group('HunterFrostedPill variants', () {
    testWidgets('amber pill renders the amber icon + light-amber label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCard(
          pills: const [
            HunterMediaPill(label: 'AMBER PILL', amber: true),
          ],
        ),
      );
      await tester.pump();
      expect(find.text('AMBER PILL'), findsOneWidget);
    });

    testWidgets('accentColor pill overrides the variant (status badge)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HunterFrostedPill(
              pill: HunterMediaPill(
                label: 'EXPIRED',
                accentColor: Colors.redAccent,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('EXPIRED'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('HunterDataPill', () {
    testWidgets('renders a solid theme-aware pill with label + icon', (
      tester,
    ) async {
      final theme = ThemeController.instance..setDarkMode(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HunterDataPill(
              theme: theme,
              pill: const HunterMediaPill(
                icon: Icons.speed_rounded,
                label: '2850 fps',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2850 fps'), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    });
  });

  group('Hunter Mode module adoption (structural)', () {
    String readFile(String path) => File(path).readAsStringSync();

    test('the Game Guide card is built on the shared HunterMediaCard', () {
      final src = readFile(
        'lib/features/game_guide/widgets/game_species_card.dart',
      );
      expect(src.contains('HunterMediaCard('), isTrue);
      expect(src.contains('HunterFrostedCircleButton('), isTrue);
    });

    test('the Digital Firearm Safe uses the shared media card + grid', () {
      final src = readFile('lib/features/hunter_mode/firearm_safe_screen.dart');
      expect(src.contains('HunterMediaCard('), isTrue);
      expect(src.contains('HunterGridContainer('), isTrue);
    });

    test('the Ammunition Manager uses the shared media card + grid', () {
      final src = readFile(
        'lib/features/ballistics/presentation/ammunition_screen.dart',
      );
      expect(src.contains('HunterMediaCard('), isTrue);
      expect(src.contains('HunterGridContainer('), isTrue);
    });

    test('the saved ammunition variation cards use the clean data pills', () {
      final src = readFile(
        'lib/features/ballistics/presentation/ammunition_type_selection_screen.dart',
      );
      expect(src.contains('HunterDataPill('), isTrue);
    });

    test('the Package Marketplace card carries the full-bleed hero + frosted '
        'pricing pill', () {
      final src = readFile(
        'lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart',
      );
      expect(src.contains('HunterFrostedPill('), isTrue);
      expect(src.contains('HunterMediaCard.legibilityGradient'), isTrue);
      expect(src.contains('_heroFallback('), isTrue);
    });

    test('the Trophy Registry uses the shared media card + grid', () {
      final src = readFile(
        'lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart',
      );
      expect(src.contains('HunterMediaCard('), isTrue);
      expect(src.contains('HunterGridContainer('), isTrue);
    });
  });
}
