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
    'trophy_room': 'lib/features/hunter_mode/trophy_room_screen.dart',
    'trophy_detail': 'lib/features/hunter_mode/trophy_detail_screen.dart',
    'firearm_safe': 'lib/features/hunter_mode/firearm_safe_screen.dart',
    'firearm_detail': 'lib/features/hunter_mode/firearm_detail_screen.dart',
    'add_firearm_manual':
        'lib/features/hunter_mode/add_firearm_manual_form.dart',
    'add_trophy': 'lib/features/hunter_mode/add_trophy_screen.dart',
    'edit_trophy': 'lib/features/hunter_mode/edit_trophy_screen.dart',
    'firearm_maintenance':
        'lib/features/hunter_mode/firearm_maintenance_screen.dart',
    'spoor_identifier':
        'lib/features/hunter_mode/spoor_identifier_screen.dart',
    'firearm_renewal':
        'lib/features/hunter_mode/screens/firearm_renewal_screen.dart',
    'custom_handloads':
        'lib/features/hunter_mode/screens/custom_handloads_form_screen.dart',
    'venison_permit_form':
        'lib/features/hunter_mode/screens/venison_permit_form_screen.dart',
    'trophy_browser':
        'lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart',
    'saps_tracker':
        'lib/features/hunter_mode/presentation/saps_tracker_screen.dart',
    'meat_processing':
        'lib/features/hunter_mode/screens/meat_processing_screen.dart',
    'meat_processing_history':
        'lib/features/hunter_mode/screens/meat_processing_order_history_screen.dart',
    'carcass_matrix':
        'lib/features/hunter_mode/screens/carcass_matrix_screen.dart',
    'mesh_radar': 'lib/features/hunter_mode/screens/mesh_radar_screen.dart',
    'weather': 'lib/features/hunter_mode/weather/weather_tracker_screen.dart',
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

    test('HunterUi light-mode palette uses rich warm cards + espresso text',
        () {
      final src =
          readSource('lib/features/hunter_mode/widgets/hunter_scaffold.dart');
      expect(src.contains('class HunterUi'), isTrue);
      expect(
        src.contains('Color(0xFFEFE7DC)'),
        isTrue,
        reason: 'The light card surface must be the toned-down warm EFE7DC.',
      );
      expect(
        src.contains('Color(0xFF2C221E)'),
        isTrue,
        reason: 'The espresso title text must be 0xFF2C221E.',
      );
      expect(
        src.contains('Color(0xFF4A3B32)'),
        isTrue,
        reason:
            'The warm-brown secondary text must be 0xFF4A3B32.',
      );
    });

    test('the scrim is mode-aware (light cream veil in Day, dense black in '
        'Night)', () {
      final src =
          readSource('lib/features/hunter_mode/widgets/hunter_scaffold.dart');
      // Light-mode warm cream veil colours.
      expect(src.contains('Color(0xE6F7F1E6)'), isTrue,
          reason: 'Light-mode scrim must be a warm cream veil.');
      expect(src.contains('Color(0xF2EFE5D4)'), isTrue,
          reason: 'Light-mode bottom scrim must be a warm cream.');
      // Dark-mode dense black gradient colours.
      expect(src.contains('Color(0xA6000000)'), isTrue,
          reason: 'Dark-mode scrim must be a dense black gradient.');
      expect(
        src.contains('scrim({bool isDarkMode = true})'),
        isTrue,
        reason: 'The scrim must accept a mode flag.',
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
      final stackFinder = find.byType(Stack);
      expect(stackFinder, findsWidgets);
      final stacks = tester.widgetList<Stack>(stackFinder);
      final stack = stacks.firstWhere(
        (s) => s.children.length >= 3 && s.children.first is Image,
      );
      expect(stack.children.first, isA<Image>(),
          reason: 'The first Stack child must be the background photo.');
      final image = stack.children.first as Image;
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url,
          HunterAcaciaBackground.kBackgroundImageUrl);
      expect(find.text('CONTENT'), findsOneWidget);
    });

    testWidgets('the scrim adapts: warm cream veil in Day, dense black in '
        'Night', (tester) async {
      Container scrimOf(bool isDarkMode) {
        return HunterAcaciaBackground.scrim(isDarkMode: isDarkMode)
            as Container;
      }

      final lightScrim = scrimOf(false);
      final lightGradient =
          (lightScrim.decoration as BoxDecoration).gradient as LinearGradient;
      expect(lightGradient.colors.first, const Color(0xE6F7F1E6));
      expect(lightGradient.colors.last, const Color(0xF2EFE5D4));

      final darkScrim = scrimOf(true);
      final darkGradient =
          (darkScrim.decoration as BoxDecoration).gradient as LinearGradient;
      expect(darkGradient.colors.first, const Color(0xA6000000));
      expect(darkGradient.colors.last, const Color(0xBF000000));
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
