import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';

void main() {
  group('AppScreenHelpScripts repository', () {
    test('all registered keys resolve to a script', () {
      for (final key in AppScreenHelpScripts.allKeys) {
        final script = AppScreenHelpScripts.scripts[key];
        expect(script, isNotNull, reason: 'Missing script for $key');
        expect(script!.title.trim(), isNotEmpty);
        expect(script.description.trim(), isNotEmpty);
      }
    });

    test('all twelve core portal screens have help scripts', () {
      const required = <String>[
        // Hunter portal.
        'hunter_marketplace',
        'hunter_custom_package_builder',
        'hunter_trophy_registry',
        'hunter_firearm_safe',
        'hunter_ballistics_calculator',
        'hunter_spoor_identification',
        // Outfitter portal.
        'outfitter_dashboard',
        'outfitter_farm_control_panel',
        'outfitter_package_manager',
        'outfitter_trophy_stock',
        'outfitter_price_lists',
        'outfitter_venison_permits',
      ];
      for (final key in required) {
        final script = AppScreenHelpScripts.scripts[key];
        expect(script, isNotNull, reason: 'Missing script for $key');
        expect(script!.concepts, isNotEmpty,
            reason: '$key must carry key concepts');
      }
    });

    test('forKey falls back to a generic script for unknown keys', () {
      final script = AppScreenHelpScripts.forKey('does_not_exist');
      expect(script.title, 'About This Screen');
      expect(script.description, isNotEmpty);
    });

    test('forKey returns the exact script for a known key', () {
      expect(
        AppScreenHelpScripts.forKey(AppScreenHelpScripts.hunterMarketplace)
            .title,
        'Package Marketplace',
      );
    });
  });

  group('AppInfoModal theme adaptation', () {
    test('surface/accent/text palette resolves per brightness', () {
      expect(AppInfoModal.surfaceColor(Brightness.light),
          AppInfoModal.lightSurface);
      expect(AppInfoModal.surfaceColor(Brightness.dark),
          AppInfoModal.darkSurface);
      expect(AppInfoModal.titleColor(Brightness.light),
          AppInfoModal.lightTitle);
      expect(AppInfoModal.titleColor(Brightness.dark), AppInfoModal.darkTitle);
      expect(AppInfoModal.bodyColor(Brightness.light), AppInfoModal.lightBody);
      expect(AppInfoModal.bodyColor(Brightness.dark), AppInfoModal.darkBody);
    });

    testWidgets('renders the warm cream surface in light mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: AppInfoModal(
              screenKey: AppScreenHelpScripts.hunterMarketplace,
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppInfoModal),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppInfoModal.lightSurface);
      expect(find.text('PACKAGE MARKETPLACE'), findsOneWidget);
      expect(find.text('KEY CONCEPTS'), findsOneWidget);
      expect(find.text('GOT IT'), findsOneWidget);
    });

    testWidgets('renders the dark card surface in dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: AppInfoModal(
              screenKey: AppScreenHelpScripts.outfitterDashboard,
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppInfoModal),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppInfoModal.darkSurface);
      expect(find.text('OUTFITTER DASHBOARD'), findsOneWidget);
    });
  });

  group('AppInfoIconButton integration', () {
    testWidgets('tapping the icon opens the modal with the screen script',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                AppInfoIconButton(
                  screenKey: AppScreenHelpScripts.outfitterTrophyStock,
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.byType(AppInfoModal), findsNothing);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.byType(AppInfoModal), findsOneWidget);
      expect(find.text('TROPHY STOCK MANAGEMENT'), findsOneWidget);
      expect(find.textContaining('sellable trophy inventory'),
          findsOneWidget);
      expect(find.text('KEY CONCEPTS'), findsOneWidget);

      // Dismissal via the GOT IT action (scroll it into view first — the
      // modal content is scrollable and the button may be below the fold).
      await tester.ensureVisible(find.text('GOT IT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GOT IT'));
      await tester.pumpAndSettle();
      expect(find.byType(AppInfoModal), findsNothing);
    });

    testWidgets('modal adapts when opened under the dark theme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                AppInfoIconButton(
                  screenKey: AppScreenHelpScripts.hunterBallisticsCalculator,
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('BALLISTICS CALCULATOR'), findsOneWidget);
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppInfoModal),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppInfoModal.darkSurface);
    });
  });

  group('per-screen info icon wiring (structural contract)', () {
    String readSource(String relPath) => File(relPath).readAsStringSync();

    const hunterScreens = <String, String>{
      'lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart':
          'hunterMarketplace',
      'lib/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart':
          'hunterCustomPackageBuilder',
      'lib/features/hunter_mode/screens/hunter_trophy_browser_screen.dart':
          'hunterTrophyRegistry',
      'lib/features/hunter_mode/firearm_safe_screen.dart': 'hunterFirearmSafe',
      'lib/features/ballistics/presentation/ballistic_calc_screen.dart':
          'hunterBallisticsCalculator',
      'lib/features/hunter_mode/spoor_identifier_screen.dart':
          'hunterSpoorIdentification',
    };

    const outfitterScreens = <String, String>{
      'lib/features/outfitter_mode/outfitter_dashboard.dart':
          'outfitterDashboard',
      'lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart':
          'outfitterFarmControlPanel',
      'lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart':
          'outfitterPackageManager',
      'lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart':
          'outfitterTrophyStock',
      'lib/features/hunter_mode/screens/outfitter_price_list_screen.dart':
          'outfitterPriceLists',
      'lib/features/hunter_mode/screens/venison_permit_list_screen.dart':
          'outfitterVenisonPermits',
    };

    test('every hunter screen wires an AppInfoIconButton with its key', () {
      hunterScreens.forEach((path, key) {
        final src = readSource(path);
        expect(src.contains('app_info_modal.dart'), isTrue,
            reason: '$path must import the universal info modal');
        expect(src.contains('AppInfoIconButton('), isTrue,
            reason: '$path must render the info action button');
        expect(src.contains('AppScreenHelpScripts.$key'), isTrue,
            reason: '$path must pass its exact screen key');
      });
    });

    test('every outfitter screen wires an info chip invoking the modal', () {
      outfitterScreens.forEach((path, key) {
        final src = readSource(path);
        expect(src.contains('app_info_modal.dart'), isTrue,
            reason: '$path must import the universal info modal');
        expect(src.contains('showAppInfoModal('), isTrue,
            reason: '$path must invoke the universal info modal');
        expect(src.contains('AppScreenHelpScripts.$key'), isTrue,
            reason: '$path must pass its exact screen key');
      });
    });

    test('the shared venison permit screen is mode-aware', () {
      final src = readSource(
        'lib/features/hunter_mode/screens/venison_permit_list_screen.dart',
      );
      expect(src.contains('AppScreenHelpScripts.hunterVenisonPermits'), isTrue,
          reason: 'Hunter mode must use the hunter permit script');
      expect(src.contains('AppScreenHelpScripts.outfitterVenisonPermits'),
          isTrue,
          reason: 'Outfitter mode must use the outfitter permit script');
    });
  });
}
