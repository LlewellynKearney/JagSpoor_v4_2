import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/layout/web_layout.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/hunter_dashboard.dart';
import 'package:jagspoor/features/hunter_mode/widgets/dashboard_feature_folder.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';

/// Responsive **web** layout contract.
///
/// The desktop browser previously rendered the mobile layout stretched
/// edge-to-edge. These tests lock in the desktop treatment:
///  * a `> 800px` breakpoint,
///  * a centred max-width (1280) content container,
///  * 2-column module grids,
///  * a web-only background contrast veil,
///  * a 64px header on web / 56px on native.
///
/// The 800x600 default widget-test surface stays on the MOBILE presentation
/// (strict `>` breakpoint), so the existing mobile layout is unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mockConnectivity(WidgetTester tester) {
    const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async {
        if (call.method == 'check') return <String>['wifi'];
        return null;
      },
    );
  }

  group('WebLayout breakpoint + constants', () {
    test('breakpoint is 800 and content width is 1280', () {
      expect(WebLayout.desktopBreakpoint, 800);
      expect(WebLayout.maxContentWidth, 1280);
      expect(WebLayout.webHeaderHeight, 64);
    });

    test('isDesktopWidth is strictly greater than the breakpoint', () {
      expect(WebLayout.isDesktopWidth(320), isFalse);
      expect(WebLayout.isDesktopWidth(799), isFalse);
      // The default 800x600 widget-test surface must stay mobile.
      expect(WebLayout.isDesktopWidth(800), isFalse);
      expect(WebLayout.isDesktopWidth(801), isTrue);
      expect(WebLayout.isDesktopWidth(1440), isTrue);
    });

    test('native platforms keep the 56px toolbar height', () {
      // Tests run on the host VM (not web), so the native height applies.
      expect(WebLayout.headerHeight(), kToolbarHeight);
    });
  });

  group('dashboard responsive body', () {
    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      mockConnectivity(tester);
      await tester.pumpWidget(
        MaterialApp(home: HunterDashboard(theme: ThemeController.instance)),
      );
      await tester.pump();
    }

    testWidgets('mobile width: no centred max-width container is applied',
        (tester) async {
      await pumpAt(tester, 420);
      // The constrained desktop wrapper is absent on a phone-width viewport.
      final constrained = find.ancestor(
        of: find.text('TACTICAL MODULES'),
        matching: find.byType(ConstrainedBox),
      );
      final has1280 = tester
          .widgetList<ConstrainedBox>(constrained)
          .any((b) => b.constraints.maxWidth == WebLayout.maxContentWidth);
      expect(has1280, isFalse,
          reason: 'A phone-width layout must not be capped at 1280.');
    });

    testWidgets('desktop width: body is centred and capped at 1280',
        (tester) async {
      await pumpAt(tester, 1600);
      final constrained = find.ancestor(
        of: find.text('TACTICAL MODULES'),
        matching: find.byType(ConstrainedBox),
      );
      final has1280 = tester
          .widgetList<ConstrainedBox>(constrained)
          .any((b) => b.constraints.maxWidth == WebLayout.maxContentWidth);
      expect(has1280, isTrue,
          reason: 'Desktop content must be wrapped in a 1280 max-width box.');
      // And it is centred (a Center ancestor of the same content).
      expect(
        find.ancestor(
          of: find.text('TACTICAL MODULES'),
          matching: find.byType(Center),
        ),
        findsWidgets,
      );
    });

    testWidgets('desktop width: TACTICAL MODULES folders render 2 per row',
        (tester) async {
      await pumpAt(tester, 1600);
      // Three folders -> first row has two side-by-side folders.
      final folders = find.byType(DashboardFeatureFolder);
      expect(folders, findsNWidgets(3));
      final first = tester.getRect(folders.at(0));
      final second = tester.getRect(folders.at(1));
      final third = tester.getRect(folders.at(2));
      // Row 1: first + second share a top and sit side by side.
      expect((first.top - second.top).abs() < 1.0, isTrue,
          reason: 'The first two folders must share a grid row.');
      expect(first.right <= second.left + 1.0, isTrue,
          reason: 'The first two folders must be side by side, not stacked.');
      // Row 2: the third folder starts below the first row.
      expect(third.top > first.bottom - 1.0, isTrue,
          reason: 'The third folder must wrap to a second row.');
    });

    testWidgets('mobile width: folders stack in a single column',
        (tester) async {
      await pumpAt(tester, 420);
      final folders = find.byType(DashboardFeatureFolder);
      final first = tester.getRect(folders.at(0));
      final second = tester.getRect(folders.at(1));
      expect(second.top >= first.bottom - 1.0, isTrue,
          reason: 'On mobile the folders stack vertically.');
    });

    testWidgets('desktop width: MORE MODULES renders 2 per row', (tester) async {
      await pumpAt(tester, 1600);
      // Scroll the MORE MODULES section into view.
      for (var i = 0; i < 40; i++) {
        if (find.text('Digital Trophy Room').evaluate().isNotEmpty) break;
        await tester.drag(
            find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 40));
      }
      final trophy = find.text('Digital Trophy Room');
      final gameGuide = find.text('SA Game Guide');
      expect(trophy, findsOneWidget);
      expect(gameGuide, findsOneWidget);
      final a = tester.getRect(trophy);
      final b = tester.getRect(gameGuide);
      // The first two non-grouped features share a row (top aligned).
      expect((a.top - b.top).abs() < 1.0, isTrue,
          reason: 'The first two MORE MODULES cards must share a grid row.');
      expect(a.left < b.left, isTrue,
          reason: 'They must be side by side, left to right.');
    });
  });

  group('web background contrast veil', () {
    testWidgets('desktop: a 65% black veil sits over the photo',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

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

      final stacks = tester.widgetList<Stack>(find.byType(Stack));
      final stack = stacks.firstWhere(
        (s) => s.children.length >= 3 && s.children.first is Image,
      );
      // photo + contrast veil + scrim + content (>= 4 children on desktop).
      expect(stack.children.length, greaterThanOrEqualTo(4),
          reason: 'Desktop must add the contrast veil layer.');
      final veil = stack.children[1] as Container;
      final color = veil.color!;
      expect(color.a, closeTo(0.65, 0.01),
          reason: 'The web contrast veil must be 65% black.');
      expect(color.r, 0);
      expect(color.g, 0);
      expect(color.b, 0);
    });

    testWidgets('mobile: no contrast veil is added (3-layer stack)',
        (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

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

      final stacks = tester.widgetList<Stack>(find.byType(Stack));
      final stack = stacks.firstWhere(
        (s) => s.children.length >= 3 && s.children.first is Image,
      );
      // photo + scrim + content only.
      expect(stack.children.length, 3,
          reason: 'Mobile keeps the original 3-layer stack.');
    });
  });

  group('source contracts', () {
    test('the dashboard uses the shared WebLayout breakpoint + max width', () {
      final src = File('lib/features/hunter_mode/hunter_dashboard.dart')
          .readAsStringSync();
      expect(src.contains('WebLayout.isDesktopWidth'), isTrue);
      expect(src.contains('WebLayout.maxContentWidth'), isTrue);
      expect(src.contains('WebLayout.headerHeight'), isTrue);
      // 2-column grid helper present.
      expect(src.contains('_twoColumnGrid'), isTrue);
    });

    test('the header height is platform-aware (64 web / 56 native)', () {
      final src = File(
        'lib/features/shared/widgets/jagspoor_dashboard_header.dart',
      ).readAsStringSync();
      expect(src.contains('WebLayout.headerHeight()'), isTrue,
          reason: 'The header must derive its height from WebLayout.');
    });

    test('the scaffold adds the web-only contrast veil', () {
      final src =
          File('lib/features/hunter_mode/widgets/hunter_scaffold.dart')
              .readAsStringSync();
      expect(src.contains('webContrastOverlay'), isTrue);
      expect(src.contains('WebLayout.isDesktopLayout'), isTrue);
    });

    test('web/index.html declares a viewport and keeps flutter_bootstrap',
        () {
      final html = File('web/index.html').readAsStringSync();
      expect(html.contains('name="viewport"'), isTrue,
          reason: 'The web build must declare a viewport meta tag.');
      expect(html.contains('flutter_bootstrap.js'), isTrue,
          reason: 'The Flutter bootstrap must be preserved.');
      expect(
        html.contains('Ultimate South African Hunting Companion'),
        isFalse,
        reason: 'The marketing landing page must never be the entry point.',
      );
    });
  });
}
