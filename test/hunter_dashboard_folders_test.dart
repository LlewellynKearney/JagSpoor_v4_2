import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/hunter_dashboard.dart';
import 'package:jagspoor/features/hunter_mode/firearm_safe_screen.dart';
import 'package:jagspoor/features/hunter_mode/widgets/dashboard_feature_folder.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/ballistics/presentation/ammunition_screen.dart';
import 'package:jagspoor/features/ballistics/presentation/ballistic_calc_screen.dart';
import 'package:jagspoor/features/game_guide/presentation/field_estimate_screen.dart';
import 'package:jagspoor/features/track/presentation/spoor_detection_hud_screen.dart';
import 'package:jagspoor/features/hunter_mode/screens/shot_group_analyzer_screen.dart';
import 'package:jagspoor/features/hunter_mode/screens/hunter_package_marketplace_screen.dart';
import 'package:jagspoor/features/hunter_mode/screens/hunter_trophy_browser_screen.dart';
import 'package:jagspoor/features/hunter_mode/screens/custom_package_farm_selection_screen.dart';

/// Records every pushed route so navigation routing can be asserted without
/// pumping (and building) the destination screen (which would hit Firebase).
class _PushObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DashboardFeatureFolder widget', () {
    Widget buildFolder({
      required ThemeController theme,
      bool initiallyExpanded = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardFeatureFolder(
            theme: theme,
            icon: Icons.gps_fixed_rounded,
            title: 'All things guns',
            subtitle: 'Firearm safe & ammunition management',
            initiallyExpanded: initiallyExpanded,
            children: const [
              Text('Nested Feature A'),
              Text('Nested Feature B'),
            ],
          ),
        ),
      );
    }

    testWidgets('renders the header, subtitle and count badge while collapsed',
        (tester) async {
      await tester.pumpWidget(buildFolder(theme: ThemeController()));
      expect(find.text('All things guns'), findsOneWidget);
      expect(find.text('Firearm safe & ammunition management'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.gps_fixed_rounded), findsOneWidget);
    });

    testWidgets('collapsed by default: nested children are not in the tree',
        (tester) async {
      await tester.pumpWidget(buildFolder(theme: ThemeController()));
      expect(find.text('Nested Feature A'), findsNothing);
      expect(find.text('Nested Feature B'), findsNothing);
    });

    testWidgets('tapping the header expands with an AnimatedSize animation '
        'and tapping again collapses', (tester) async {
      await tester.pumpWidget(buildFolder(theme: ThemeController()));
      expect(find.byType(AnimatedSize), findsOneWidget);

      await tester.tap(find.text('All things guns'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Nested Feature A'), findsOneWidget);
      expect(find.text('Nested Feature B'), findsOneWidget);

      await tester.tap(find.text('All things guns'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Nested Feature A'), findsNothing);
      expect(find.text('Nested Feature B'), findsNothing);
    });

    testWidgets('initiallyExpanded renders the nested children immediately',
        (tester) async {
      await tester
          .pumpWidget(buildFolder(theme: ThemeController(), initiallyExpanded: true));
      expect(find.text('Nested Feature A'), findsOneWidget);
      expect(find.text('Nested Feature B'), findsOneWidget);
    });

    testWidgets('light mode uses the warm cream surface + espresso title',
        (tester) async {
      final theme = ThemeController()..setDarkMode(false);
      await tester.pumpWidget(buildFolder(theme: theme));

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DashboardFeatureFolder),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, HunterUi.lightCard);
      expect((decoration.border! as Border).top.color, HunterUi.lightCardBorder);

      final title = tester.widget<Text>(find.text('All things guns'));
      expect(title.style!.color, HunterUi.lightTitle);
    });

    testWidgets('dark mode uses gold accents on the folder icon',
        (tester) async {
      final theme = ThemeController()..setDarkMode(true);
      await tester.pumpWidget(buildFolder(theme: theme));

      final icon = tester.widget<Icon>(find.byIcon(Icons.gps_fixed_rounded));
      expect(icon.color, HunterAcaciaBackground.kOverlayGold);
    });

    test('accentColor resolves gold in dark mode and theme accent in light',
        () {
      final dark = ThemeController()..setDarkMode(true);
      final light = ThemeController()..setDarkMode(false);
      expect(DashboardFeatureFolder.accentColor(dark),
          HunterAcaciaBackground.kOverlayGold);
      expect(DashboardFeatureFolder.accentColor(light), light.accentColor);
    });
  });

  group('HunterDashboard folder organization', () {
    testWidgets('renders the three categorized folder headers', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HunterDashboard(theme: ThemeController.instance)),
      );
      await tester.pump();

      expect(find.text('All things guns'), findsOneWidget);
      expect(find.text('Market place'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
      expect(find.byType(DashboardFeatureFolder), findsNWidgets(3));
    });

    /// Expands a folder and lets the AnimatedSize animation complete. Uses
    /// fixed-duration pumps (not pumpAndSettle) because the dashboard's
    /// NetworkDiagnosticHud runs a periodic Timer that never settles.
    Future<void> expandFolder(WidgetTester tester, String title) async {
      await tester.ensureVisible(find.text(title));
      await tester.tap(find.text(title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('grouped features are hidden until their folder is expanded',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HunterDashboard(theme: ThemeController.instance)),
      );
      await tester.pump();

      // Collapsed: grouped feature cards are not in the tree.
      expect(find.text('🔒 Digital Firearm Safe'), findsNothing);
      expect(find.text('Ammunition Manager'), findsNothing);
      expect(find.text('🎯 Package Marketplace'), findsNothing);
      expect(find.text('Ballistic Calculator'), findsNothing);

      await expandFolder(tester, 'All things guns');
      expect(find.text('🔒 Digital Firearm Safe'), findsOneWidget);
      expect(find.text('Ammunition Manager'), findsOneWidget);

      await expandFolder(tester, 'Market place');
      expect(find.text('🎯 Package Marketplace'), findsOneWidget);
      expect(find.text('🦌 Custom Package Builder'), findsOneWidget);
      expect(find.text('🦌 Trophy Registry & Booking'), findsOneWidget);

      await expandFolder(tester, 'Tools');
      expect(find.text('Ballistic Calculator'), findsOneWidget);
      expect(find.text('Field Estimate Verification'), findsOneWidget);
      expect(find.text('Track (Spoor) Identifier'), findsOneWidget);
      expect(find.text('🎯 Scope Settings & Tools'), findsOneWidget);
      expect(find.text('🎯 Shot Group Target Analyzer'), findsOneWidget);
    });

    /// Drags the dashboard's single Scrollable downward until [title]
    /// materializes (ListView lazily builds children).
    Future<void> dragUntilFound(WidgetTester tester, String title) async {
      for (var i = 0; i < 60; i++) {
        if (find.text(title).evaluate().isNotEmpty) return;
        await tester.drag(
            find.byType(Scrollable).first, const Offset(0, -250));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(title), findsOneWidget,
          reason: '"$title" should materialize after scrolling.');
    }

    testWidgets('non-grouped features still render flat below the folders',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HunterDashboard(theme: ThemeController.instance)),
      );
      await tester.pump();

      await dragUntilFound(tester, 'MORE MODULES');
      await dragUntilFound(tester, 'Digital Trophy Room');
      await dragUntilFound(tester, 'SA Game Guide');
      await dragUntilFound(tester, 'Weather & Wind Tracker');
      expect(find.text('MORE MODULES'), findsOneWidget);
      expect(find.text('Digital Trophy Room'), findsOneWidget);
      expect(find.text('SA Game Guide'), findsOneWidget);
      expect(find.text('Weather & Wind Tracker'), findsOneWidget);
    });

    /// Renders the dashboard with a push-recording observer, expands
    /// [folderTitle], taps the nested [featureTitle] card, and asserts it
    /// pushed a [MaterialPageRoute] whose builder produces a screen of type
    /// [T]. The pushed route is deliberately never pumped, so the destination
    /// screen (which touches Firebase in initState) never builds.
    Future<void> assertFeatureRoutesTo<T>(
      WidgetTester tester, {
      required String folderTitle,
      required String featureTitle,
    }) async {
      final observer = _PushObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: HunterDashboard(theme: ThemeController.instance),
        ),
      );
      await tester.pump();
      await expandFolder(tester, folderTitle);

      final context = tester.element(find.byType(HunterDashboard));
      final before = observer.pushed.length;
      await tester.ensureVisible(find.text(featureTitle));
      await tester.tap(find.text(featureTitle));
      expect(observer.pushed.length, before + 1,
          reason: 'Tapping "$featureTitle" must push a route.');
      final route = observer.pushed.last;
      expect(route, isA<MaterialPageRoute>());
      expect((route as MaterialPageRoute).builder(context), isA<T>());
    }

    testWidgets('All things guns > Digital Firearm Safe routes to the '
        'FirearmSafeScreen', (tester) async {
      await assertFeatureRoutesTo<FirearmSafeScreen>(tester,
          folderTitle: 'All things guns',
          featureTitle: '🔒 Digital Firearm Safe');
    });

    testWidgets('All things guns > Ammunition Manager routes to the '
        'AmmunitionScreen', (tester) async {
      await assertFeatureRoutesTo<AmmunitionScreen>(tester,
          folderTitle: 'All things guns', featureTitle: 'Ammunition Manager');
    });

    testWidgets('Market place > Package Marketplace routes to the '
        'HunterPackageMarketplaceScreen', (tester) async {
      await assertFeatureRoutesTo<HunterPackageMarketplaceScreen>(tester,
          folderTitle: 'Market place', featureTitle: '🎯 Package Marketplace');
    });

    testWidgets('Market place > Custom Package Builder routes to the '
        'CustomPackageFarmSelectionScreen', (tester) async {
      await assertFeatureRoutesTo<CustomPackageFarmSelectionScreen>(tester,
          folderTitle: 'Market place',
          featureTitle: '🦌 Custom Package Builder');
    });

    testWidgets('Market place > Trophy Registry & Booking routes to the '
        'HunterTrophyBrowserScreen', (tester) async {
      await assertFeatureRoutesTo<HunterTrophyBrowserScreen>(tester,
          folderTitle: 'Market place',
          featureTitle: '🦌 Trophy Registry & Booking');
    });

    testWidgets('Tools > Ballistic Calculator routes to the '
        'BallisticCalcScreen', (tester) async {
      await assertFeatureRoutesTo<BallisticCalcScreen>(tester,
          folderTitle: 'Tools', featureTitle: 'Ballistic Calculator');
    });

    testWidgets('Tools > Field Estimate Verification routes to the '
        'FieldEstimateScreen', (tester) async {
      await assertFeatureRoutesTo<FieldEstimateScreen>(tester,
          folderTitle: 'Tools',
          featureTitle: 'Field Estimate Verification');
    });

    testWidgets('Tools > Track (Spoor) Identifier routes to the '
        'SpoorDetectionHudScreen', (tester) async {
      await assertFeatureRoutesTo<SpoorDetectionHudScreen>(tester,
          folderTitle: 'Tools', featureTitle: 'Track (Spoor) Identifier');
    });

    testWidgets('Tools > Shot Group Target Analyzer routes to the '
        'ShotGroupAnalyzerScreen', (tester) async {
      await assertFeatureRoutesTo<ShotGroupAnalyzerScreen>(tester,
          folderTitle: 'Tools',
          featureTitle: '🎯 Shot Group Target Analyzer');
    });

    testWidgets('Tools > Scope Settings & Tools opens a modal bottom sheet',
        (tester) async {
      final observer = _PushObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: HunterDashboard(theme: ThemeController.instance),
        ),
      );
      await tester.pump();
      await expandFolder(tester, 'Tools');

      final before = observer.pushed.length;
      await tester.ensureVisible(find.text('🎯 Scope Settings & Tools'));
      await tester.tap(find.text('🎯 Scope Settings & Tools'));
      expect(observer.pushed.length, before + 1);
      expect(observer.pushed.last, isNot(isA<MaterialPageRoute>()));
    });
  });

  group('Dashboard folder wiring contract (structural)', () {
    final source =
        File('lib/features/hunter_mode/hunter_dashboard.dart').readAsStringSync();

    test('the dashboard declares the three categorized folders', () {
      expect(source.contains("title: 'All things guns'"), isTrue);
      expect(source.contains("title: 'Market place'"), isTrue);
      expect(source.contains("title: 'Tools'"), isTrue);
    });

    test('the dashboard renders the folders via DashboardFeatureFolder', () {
      expect(source.contains('dashboard_feature_folder.dart'), isTrue);
      expect(source.contains('DashboardFeatureFolder('), isTrue);
    });

    test('All things guns groups the firearm safe and ammunition manager', () {
      expect(
        source.contains("ids: const ['firearm_safe', 'ammunition']"),
        isTrue,
      );
    });

    test('Market place groups marketplace, custom builder and trophy browser',
        () {
      expect(source.contains("'marketplace',"), isTrue);
      expect(source.contains("'custom_package_builder',"), isTrue);
      expect(source.contains("'trophy_browser',"), isTrue);
    });

    test('Tools groups ballistics, field estimate, spoor, scope settings '
        'and shot group analyzer', () {
      expect(source.contains("'ballistic_calculator',"), isTrue);
      expect(source.contains("'field_estimate',"), isTrue);
      expect(source.contains("'spoor_tracker',"), isTrue);
      expect(source.contains("'scope_settings',"), isTrue);
      expect(source.contains("'shot_group_analyzer',"), isTrue);
    });
  });
}
