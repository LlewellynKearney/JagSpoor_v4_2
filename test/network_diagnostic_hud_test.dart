import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/hunter_mode/widgets/network_diagnostic_hud.dart';

/// Cloud Sync Telemetry banner (NetworkDiagnosticHud) contrast contract.
///
/// The "CLOUD SYNC TELEMETRY ONLINE" status banner must never blend into the
/// Solitary Acacia background photo/scrim. Asserts the mode-aware palette:
/// Light Mode -> warm cream/off-white card surface + defined deep-green
/// border + deep espresso title + solid dark-green SYNCED pill (white text).
/// Dark Mode -> solid very-dark olive surface + bright-green border +
/// bright-light-green title + bright-green SYNCED pill (near-black text).
///
/// The widget is pumped with `Theme.of(context).brightness` resolution, so
/// wrapping it in `MaterialApp(theme: ThemeData.light()/dark())` exercises
/// the real mode-aware branch it selects on device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Offline the banner's `checkConnectivity()` future so no unhandled
  /// async plugin error leaks into the widget-test zone.
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

  /// The closest ancestor Container of [child] whose decoration carries the
  /// expected surface [Color]; null when none matches.
  Container? ancestorContainerWithColor(
    WidgetTester tester,
    Finder child,
    Color expectedColor,
  ) {
    final ancestors = tester.widgetList<Container>(
      find.ancestor(of: child, matching: find.byType(Container)),
    );
    for (final container in ancestors) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration && decoration.color == expectedColor) {
        return container;
      }
    }
    return null;
  }

  group('online banner (CLOUD SYNC TELEMETRY ONLINE)', () {
    testWidgets(
      'Light Mode: warm cream card + deep green border + espresso title + '
      'solid dark-green SYNCED pill',
      (tester) async {
        mockConnectivity(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: const Scaffold(body: NetworkDiagnosticHud()),
          ),
        );
        await tester.pump();

        expect(
          find.text('CLOUD SYNC TELEMETRY ONLINE'),
          findsOneWidget,
        );

        // Deep espresso title text (HunterUi.lightTitle = 0xFF2C221E).
        final title = tester.widget<Text>(
          find.text('CLOUD SYNC TELEMETRY ONLINE'),
        );
        expect(title.style!.color, HunterUi.lightTitle);

        // Solid warm cream wrapper (HunterUi.lightCard = 0xFFEFE7DC) with a
        // defined deep-green border.
        final banner = ancestorContainerWithColor(
          tester,
          find.text('CLOUD SYNC TELEMETRY ONLINE'),
          HunterUi.lightCard,
        );
        expect(banner, isNotNull,
            reason: 'Banner wrapper must be a solid cream surface.');
        final decoration = banner!.decoration as BoxDecoration;
        expect(decoration.border, isA<Border>());
        expect((decoration.border! as Border).top.color,
            const Color(0xFF4F6E33));

        // SYNCED pill: solid dark-green surface + white text + white icon.
        final pillText = tester.widget<Text>(find.text('SYNCED'));
        expect(pillText.style!.color, Colors.white);
        final pill = ancestorContainerWithColor(
          tester,
          find.text('SYNCED'),
          const Color(0xFF2E4A1C),
        );
        expect(pill, isNotNull,
            reason: 'SYNCED pill must be a solid dark-green surface.');

        // Satellite icon dark green in light mode.
        final icon = tester.widget<Icon>(find.byIcon(Icons.satellite_alt));
        expect(icon.color, const Color(0xFF2E4A1C));
      },
    );

    testWidgets(
      'Dark Mode: solid very-dark olive surface + bright-green border + '
      'bright title + bright-green SYNCED pill with dark text',
      (tester) async {
        mockConnectivity(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(body: NetworkDiagnosticHud()),
          ),
        );
        await tester.pump();

        expect(
          find.text('CLOUD SYNC TELEMETRY ONLINE'),
          findsOneWidget,
        );

        // Bright light-green title for sharp contrast on the dark surface.
        final title = tester.widget<Text>(
          find.text('CLOUD SYNC TELEMETRY ONLINE'),
        );
        expect(title.style!.color, const Color(0xFFCDEBA8));

        // Solid very-dark olive wrapper + bright-green defined border.
        final banner = ancestorContainerWithColor(
          tester,
          find.text('CLOUD SYNC TELEMETRY ONLINE'),
          const Color(0xFF1E3011),
        );
        expect(banner, isNotNull,
            reason: 'Banner wrapper must be a solid very-dark olive surface.');
        final decoration = banner!.decoration as BoxDecoration;
        expect((decoration.border! as Border).top.color,
            const Color(0xFF7CB342));

        // SYNCED pill: bright-green surface + near-black text.
        final pillText = tester.widget<Text>(find.text('SYNCED'));
        expect(pillText.style!.color, const Color(0xFF18250A));
        final pill = ancestorContainerWithColor(
          tester,
          find.text('SYNCED'),
          const Color(0xFF7CB342),
        );
        expect(pill, isNotNull,
            reason: 'SYNCED pill must be a solid bright-green surface.');

        // Satellite icon bright green in dark mode.
        final icon = tester.widget<Icon>(find.byIcon(Icons.satellite_alt));
        expect(icon.color, const Color(0xFF7CB342));
      },
    );

    test('the banner resolves mode from the ambient theme brightness', () {
      final src = File(
        'lib/features/hunter_mode/widgets/network_diagnostic_hud.dart',
      ).readAsStringSync();
      expect(src.contains('Theme.of(context).brightness'), isTrue,
          reason: 'The banner must derive Day/Night from the ambient theme.');
      expect(src.contains('HunterUi.lightCard'), isTrue,
          reason: 'Light mode must use the warm cream card surface.');
      expect(src.contains('HunterUi.lightTitle'), isTrue,
          reason: 'Light mode must use the deep espresso title color.');
    });
  });

  group('AI Game Movement Activity Forecaster banner', () {
    testWidgets(
      'Light Mode: solid cream wrapper + deep-green border + espresso title',
      (tester) async {
        mockConnectivity(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: const Scaffold(body: NetworkDiagnosticHud()),
          ),
        );
        await tester.pump();

        final titleFinder =
            find.textContaining('AI GAME MOVEMENT ACTIVITY FORECASTER');
        expect(titleFinder, findsOneWidget);

        // Deep espresso title text (HunterUi.lightTitle = 0xFF2C221E).
        final title = tester.widget<Text>(titleFinder);
        expect(title.style!.color, HunterUi.lightTitle);

        // Solid warm cream wrapper (HunterUi.lightCard = 0xFFEFE7DC) with a
        // defined deep-green border — the forecaster must sit on a solid
        // surface, never on a translucent photo-blend gradient.
        final banner = ancestorContainerWithColor(
          tester,
          titleFinder,
          HunterUi.lightCard,
        );
        expect(banner, isNotNull,
            reason: 'The forecaster banner must be a solid cream surface.');
        final decoration = banner!.decoration as BoxDecoration;
        expect(decoration.border, isA<Border>());
        expect((decoration.border! as Border).top.color,
            const Color(0xFF4F6E33));
      },
    );

    testWidgets(
      'Dark Mode: solid very-dark olive wrapper + bright-green border + '
      'bright title',
      (tester) async {
        mockConnectivity(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(body: NetworkDiagnosticHud()),
          ),
        );
        await tester.pump();

        final titleFinder =
            find.textContaining('AI GAME MOVEMENT ACTIVITY FORECASTER');
        expect(titleFinder, findsOneWidget);

        // Bright light-green title for sharp contrast on the dark surface.
        final title = tester.widget<Text>(titleFinder);
        expect(title.style!.color, const Color(0xFFCDEBA8));

        // Solid very-dark olive wrapper + bright-green defined border.
        final banner = ancestorContainerWithColor(
          tester,
          titleFinder,
          const Color(0xFF1E3011),
        );
        expect(banner, isNotNull,
            reason:
                'The forecaster banner must be a solid very-dark olive surface.');
        final decoration = banner!.decoration as BoxDecoration;
        expect((decoration.border! as Border).top.color,
            const Color(0xFF7CB342));
      },
    );

    testWidgets('the forecaster wrapper uses a solid color (no translucent '
        'photo-blend gradient)', (tester) async {
      mockConnectivity(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(body: NetworkDiagnosticHud()),
        ),
      );
      await tester.pump();

      final titleFinder =
          find.textContaining('AI GAME MOVEMENT ACTIVITY FORECASTER');
      // The forecaster wrapper is the ancestor Container whose decoration
      // carries the solid cream surface color.
      final wrapper = ancestorContainerWithColor(
        tester,
        titleFinder,
        HunterUi.lightCard,
      );
      expect(wrapper, isNotNull);
      final decoration = wrapper!.decoration as BoxDecoration;
      expect(decoration.gradient, isNull,
          reason: 'A translucent gradient washes out over the background '
              'photo; the banner must use a solid surface color.');
      expect(decoration.color, isNotNull);
      expect(decoration.color!.a, greaterThan(0.9),
          reason: 'The banner surface must be (near-)opaque.');
    });
  });
}
