import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/shared/widgets/hunter_media_card.dart';
import 'package:jagspoor/features/shared/widgets/jagspoor_dashboard_header.dart';

/// Widget tests for the shared frosted dashboard header used by every
/// JagSpoor portal (Hunter Mode + Outfitter Mode).
///
/// Verifies the two-line brand layout (bold 'JAGSPOOR' wordmark + the amber
/// mode sub-badge with the glowing sync-status dot), the frosted dark
/// backdrop, the compact frosted action chips, and — critically — that the
/// header renders cleanly across narrow-to-wide device widths (320px up to
/// 768px) without any text overflow or RenderFlex warnings, for BOTH the
/// Hunter Mode and Outfitter Mode configurations.
void main() {
  Widget buildHeader({
    String modeBadgeText = 'OUTFITTER MODE',
    bool syncActive = true,
    List<Widget> actionButtons = const [],
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        appBar: JagSpoorDashboardHeader(
          modeBadgeText: modeBadgeText,
          syncActive: syncActive,
          actionButtons: actionButtons,
        ),
        body: const SizedBox.expand(),
      ),
    );
  }

  List<Widget> sampleActions({VoidCallback? onTap}) => [
        HunterFrostedCircleButton(
          icon: Icons.info_outline_rounded,
          iconColor: kHunterMediaAmber,
          tooltip: 'Screen info',
          onPressed: onTap ?? () {},
        ),
        const SizedBox(width: 8),
        HunterFrostedCircleButton(
          icon: Icons.settings_rounded,
          iconColor: kHunterMediaAmber,
          tooltip: 'Settings',
          onPressed: () {},
        ),
        const SizedBox(width: 8),
        HunterFrostedCircleButton(
          icon: Icons.lock_reset_rounded,
          iconColor: kHunterMediaAmber,
          tooltip: 'Sign out',
          onPressed: () {},
        ),
      ];

  group('title layout', () {
    testWidgets('renders the JAGSPOOR wordmark + the injected mode badge',
        (tester) async {
      await tester.pumpWidget(buildHeader(actionButtons: sampleActions()));
      expect(find.text('JAGSPOOR'), findsOneWidget);
      expect(find.text('OUTFITTER MODE'), findsOneWidget);
    });

    testWidgets('the wordmark is bold header caps wrapped in a scale-down '
        'FittedBox (no truncation possible)', (tester) async {
      await tester.pumpWidget(buildHeader(actionButtons: sampleActions()));
      final title = tester.widget<Text>(find.text('JAGSPOOR'));
      expect(title.style?.fontWeight, FontWeight.w800);
      expect(title.style?.color, Colors.white);
      expect(title.style?.letterSpacing, greaterThan(1.0));
      expect(title.maxLines, 1);
      // The FittedBox ancestor guarantees the wordmark scales down instead of
      // clipping when the title width shrinks.
      final fitted = find.ancestor(
        of: find.text('JAGSPOOR'),
        matching: find.byType(FittedBox),
      );
      expect(fitted, findsOneWidget);
      final box = tester.widget<FittedBox>(fitted);
      expect(box.fit, BoxFit.scaleDown);
    });

    testWidgets('the mode badge label is fully caller-injected',
        (tester) async {
      await tester.pumpWidget(
        buildHeader(modeBadgeText: 'FARM MANAGER MODE', actionButtons: sampleActions()),
      );
      expect(find.text('FARM MANAGER MODE'), findsOneWidget);
      expect(find.text('OUTFITTER MODE'), findsNothing);
    });
  });

  group('sync status dot', () {
    testWidgets('glows warm amber when sync is active', (tester) async {
      await tester.pumpWidget(
        buildHeader(syncActive: true, actionButtons: sampleActions()),
      );
      final header = tester.widget<JagSpoorDashboardHeader>(
          find.byType(JagSpoorDashboardHeader));
      expect(header.syncDotColor, kHunterMediaAmber);
    });

    testWidgets('mutes to grey when sync is offline', (tester) async {
      await tester.pumpWidget(
        buildHeader(syncActive: false, actionButtons: sampleActions()),
      );
      final header = tester.widget<JagSpoorDashboardHeader>(
          find.byType(JagSpoorDashboardHeader));
      expect(header.syncDotColor, isNot(kHunterMediaAmber));
    });
  });

  group('frosted backdrop', () {
    testWidgets('applies the #1E1E1E frosted backdrop + ambient blur',
        (tester) async {
      await tester.pumpWidget(buildHeader(actionButtons: sampleActions()));
      expect(find.byType(BackdropFilter), findsWidgets);
      final headerFinder = find.byType(JagSpoorDashboardHeader);
      final container = tester.widgetList<Container>(
        find.descendant(of: headerFinder, matching: find.byType(Container)),
      );
      final backdrop = container.where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.color == JagSpoorDashboardHeader.backdropColor;
      });
      expect(backdrop, isNotEmpty,
          reason: 'The header must float on the frosted #1E1E1E backdrop.');
      final decoration = backdrop.first.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull,
          reason: 'The warm bottom hairline divider must be present.');
      expect(decoration.boxShadow, isNotEmpty,
          reason: 'A subtle ambient shadow must lift the header.');
    });

    testWidgets('renders identically in dark mode', (tester) async {
      await tester.pumpWidget(buildHeader(
        actionButtons: sampleActions(),
        brightness: Brightness.dark,
      ));
      expect(find.text('JAGSPOOR'), findsOneWidget);
      expect(find.text('OUTFITTER MODE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('compact action group', () {
    testWidgets('renders the frosted circular chips and they receive taps',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(buildHeader(
        actionButtons: sampleActions(onTap: () => tapped++),
      ));
      expect(find.byType(HunterFrostedCircleButton), findsNWidgets(3));
      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      expect(tapped, 1);
    });

    testWidgets('preferredSize matches the standard toolbar height',
        (tester) async {
      const header = JagSpoorDashboardHeader(modeBadgeText: 'OUTFITTER MODE');
      expect(header.preferredSize.height, kToolbarHeight);
    });
  });

  group('multi-width overflow safety', () {
    // 320px is the narrowest modern Android baseline; 360/375/390/414 are the
    // common phone widths the task calls out; 768 covers small tablets.
    for (final width in [320.0, 360.0, 375.0, 390.0, 414.0, 768.0]) {
      testWidgets('renders cleanly at ${width.toInt()}px logical width '
          '(no overflow)', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildHeader(actionButtons: sampleActions()));
        await tester.pump();

        expect(find.text('JAGSPOOR'), findsOneWidget);
        expect(find.text('OUTFITTER MODE'), findsOneWidget);
        // A RenderFlex overflow / text clip surfaces as a framework exception
        // during layout; none may be present.
        expect(tester.takeException(), isNull,
            reason: 'The header must not overflow at ${width.toInt()}px.');
      });
    }

    testWidgets('the longest badge label also fits the narrowest width',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildHeader(
          modeBadgeText: 'FARM MANAGER MODE',
          actionButtons: sampleActions(),
        ),
      );
      await tester.pump();

      expect(find.text('FARM MANAGER MODE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Hunter Mode configuration', () {
    testWidgets('renders the HUNTER MODE badge with the same layout',
        (tester) async {
      await tester.pumpWidget(
        buildHeader(modeBadgeText: 'HUNTER MODE', actionButtons: sampleActions()),
      );
      expect(find.text('JAGSPOOR'), findsOneWidget);
      expect(find.text('HUNTER MODE'), findsOneWidget);
      expect(find.text('OUTFITTER MODE'), findsNothing);
    });

    // Parallel multi-width sweep for the Hunter configuration.
    for (final width in [320.0, 360.0, 375.0, 390.0, 414.0, 768.0]) {
      testWidgets('Hunter header renders cleanly at ${width.toInt()}px '
          '(no overflow)', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          buildHeader(
            modeBadgeText: 'HUNTER MODE',
            actionButtons: sampleActions(),
          ),
        );
        await tester.pump();

        expect(find.text('JAGSPOOR'), findsOneWidget);
        expect(find.text('HUNTER MODE'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason:
                'The Hunter header must not overflow at ${width.toInt()}px.');
      });
    }
  });
}
