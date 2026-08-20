import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/hunter_dashboard.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';

/// Hunter-scaffold rollout contract: the shared Solitary Acacia background
/// stack and the high-contrast `HunterActionChip` widgets must be applied
/// consistently across every hunter-side screen so the entire portal carries
/// the same immersive acacia aesthetic (and no screen regresses back to a
/// plain themed background).
///
/// Mirroring `outfitter_scaffold_rollout_test`: the Firestore emulator
/// cannot run in this sandbox, so the structural portion asserts the rollout
/// contract by reading the screen sources directly; the widget portion
/// renders the real `HunterScaffold` + `HunterDashboard` to validate the
/// layered Stack contract at runtime.
void main() {
  const hunterScreens = {
    'dashboard': 'lib/features/hunter_mode/hunter_dashboard.dart',
    'marketplace':
        'lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart',
    'venison_permits':
        'lib/features/hunter_mode/screens/hunter_venison_permit_log_screen.dart',
    'profile': 'lib/features/hunter_mode/hunter_profile_screen.dart',
    'custom_builder':
        'lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart',
    'farm_selection':
        'lib/features/hunter_mode/screens/custom_package_farm_selection_screen.dart',
  };

  String readSource(String relPath) => File(relPath).readAsStringSync();

  group('shared Solitary Acacia background', () {
    test('the shared background helper exposes the photo + asset fallback + '
        'scrim', () {
      final src =
          readSource('lib/features/hunter_mode/widgets/hunter_scaffold.dart');
      expect(src.contains('class HunterAcaciaBackground'), isTrue);
      expect(src.contains('kBackgroundImageUrl'), isTrue);
      expect(src.contains('kBackgroundFallbackAsset'), isTrue);
      expect(
        src.contains(
            'https://images.unsplash.com/photo-1523805009345-7448845a9094'),
        isTrue,
        reason: 'The Solitary Acacia URL must be the primary background.',
      );
      expect(src.contains('Greater Kudu.jpg'), isTrue,
          reason: 'The local Greater Kudu.jpg must be the offline fallback.');
      expect(src.contains('LinearGradient'), isTrue,
          reason: 'The scrim must be an adaptive dark gradient.');
    });

    test('HunterScaffold wires extendBodyBehindAppBar + the background stack',
        () {
      final src =
          readSource('lib/features/hunter_mode/widgets/hunter_scaffold.dart');
      expect(src.contains('class HunterScaffold'), isTrue);
      expect(src.contains('extendBodyBehindAppBar'), isTrue);
      expect(src.contains('HunterAcaciaBackground.stack'), isTrue);
    });

    for (final entry in hunterScreens.entries) {
      test('${entry.key} renders the shared HunterScaffold background', () {
        final src = readSource(entry.value);
        expect(
          src.contains('HunterScaffold') ||
              src.contains('HunterAcaciaBackground'),
          isTrue,
          reason: '${entry.key} must render the shared HunterScaffold so the '
              'portal carries the immersive acacia aesthetic.',
        );
        expect(
          src.contains('backgroundColor: Colors.transparent') ||
              src.contains('extendBodyBehindAppBar'),
          isTrue,
          reason: '${entry.key} must full-bleed the background under a '
              'transparent AppBar (extendBodyBehindAppBar).',
        );
      });
    }

    test('HunterUi light-mode palette uses cream cards + espresso text', () {
      final src =
          readSource('lib/features/hunter_mode/widgets/hunter_scaffold.dart');
      expect(src.contains('class HunterUi'), isTrue);
      expect(
        src.contains('Color(0xF5FCF9F5)'),
        isTrue,
        reason: 'The cream card surface must be FCF9F5 at 96% opacity.',
      );
      expect(
        src.contains('Color(0xFF2C221E)'),
        isTrue,
        reason: 'The espresso text must be 0xFF2C221E for titles/descriptions.',
      );
    });
  });

  group('top-right action icon contrast chips', () {
    test('the HunterActionChip widget renders a high-contrast dark chip', () {
      final src =
          readSource('lib/features/hunter_mode/widgets/hunter_scaffold.dart');
      expect(src.contains('class HunterActionChip'), isTrue);
      expect(src.contains('BoxShape.circle'), isTrue);
      expect(src.contains('Colors.black.withAlpha'), isTrue,
          reason:
              'The chip background must be a translucent dark circle so icons '
              'stay readable on the bright region of the acacia photo.');
    });

    test('the hunter dashboard uses chips for the theme toggle + profile icons',
        () {
      final src = readSource(hunterScreens['dashboard']!);
      // The raw accent-only IconButtons for theme toggle/profile must be gone.
      expect(
        src.contains('icon: Icon(Icons.settings_rounded, color: theme.accentColor)'),
        isFalse,
        reason: 'The low-contrast raw settings IconButton must be replaced '
            'by the chip.',
      );
      expect(
        src.split('HunterActionChip(').length - 1,
        greaterThanOrEqualTo(2),
        reason: 'Theme toggle + profile settings must each be a chip.',
      );
    });
  });

  group('widget rendering', () {
    testWidgets('HunterScaffold layers background + scrim + content in a Stack',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HunterScaffold(
            theme: ThemeController.instance,
            appBar: AppBar(title: const Text('Test')),
            body: const Text('CONTENT'),
          ),
        ),
      );
      await tester.pump();
      final scaffold =
          tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.body, isA<Stack>());
      final stack = scaffold.body! as Stack;
      expect(stack.children.length, greaterThanOrEqualTo(3));
      expect(stack.children.first, isA<Image>(),
          reason: 'The first Stack child must be the background photo.');
      final image = stack.children.first as Image;
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url,
          HunterAcaciaBackground.kBackgroundImageUrl);
      expect(find.text('CONTENT'), findsOneWidget);
    });

    testWidgets('HunterActionChip renders as a dark circular chip',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HunterActionChip(
              icon: Icons.settings_rounded,
              onPressed: () {},
            ),
          ),
        ),
      );
      final containers = find.byType(Container);
      expect(containers, findsWidgets);
      final widgets = tester.widgetList<Container>(containers);
      final chips = widgets.where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(chips, isNotEmpty,
          reason: 'The chip must render as a circle-decorated container.');
    });

    testWidgets('the Hunter dashboard renders the stacked acacia background '
        'resilient to missing Firebase auth', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HunterDashboard(theme: ThemeController.instance),
        ),
      );
      await tester.pump();
      expect(find.text('Jagspoor: Hunter Mode'), findsOneWidget);
      expect(find.text('TACTICAL MODULES'), findsOneWidget);
      expect(find.text('SYSTEM ACTIVE'), findsOneWidget);
    });
  });
}
