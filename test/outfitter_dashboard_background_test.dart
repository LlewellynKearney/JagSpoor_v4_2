import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/outfitter_mode/outfitter_dashboard.dart';

/// Widget tests for the Outfitter dashboard's bushveld background layering.
///
/// Guards the Stack contract: a full-screen background image (network with a
/// local-asset/color fallback), a dark gradient scrim for readability, and
/// the dashboard content layered on top.
void main() {
  // Pump up to N extra frames and return the last frame window (dp size).
  Future<Widget> buildDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitterDashboard(theme: ThemeController.instance),
      ),
    );
    // One pump so the async role-resolution catch lands the dashboard UI.
    await tester.pump();
    return OutfitterDashboard(theme: ThemeController.instance);
  }

  Stack? findScaffoldBodyStack(WidgetTester tester) {
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    return scaffold.body is Stack ? scaffold.body as Stack : null;
  }

  testWidgets('the body is a Stack with background + scrim + content layered',
      (tester) async {
    await buildDashboard(tester);
    final stack = findScaffoldBodyStack(tester);
    expect(stack, isNotNull,
        reason: 'The dashboard body must be layered via a Stack.');
    expect(stack!.children.length, greaterThanOrEqualTo(3));
  });

  testWidgets('background layer renders an Image (network w/ fallbacks)',
      (tester) async {
    await buildDashboard(tester);
    final stack = findScaffoldBodyStack(tester)!;
    expect(stack.children.first, isA<Image>(),
        reason: 'The first Stack child must be the full-screen background.');
    final image = stack.children.first as Image;
    expect(image.image, isA<NetworkImage>());
    final provider = image.image as NetworkImage;
    expect(provider.url, OutfitterDashboard.kBackgroundImageUrl);
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('scrim layer renders a dark gradient for readability',
      (tester) async {
    await buildDashboard(tester);
    final stack = findScaffoldBodyStack(tester)!;
    final scrims = stack.children.whereType<Container>().where(
      (c) =>
          c.decoration is BoxDecoration &&
          (c.decoration as BoxDecoration).gradient is LinearGradient,
    );
    expect(scrims, isNotEmpty,
        reason: 'A LinearGradient scrim must sit between the background and '
            'the dashboard content.');
    final gradient = (scrims.first.decoration as BoxDecoration).gradient
        as LinearGradient;
    for (final color in gradient.colors) {
      // The scrim must be a pure-black Alpha gradient (no hue), and the
      // non-deprecated Color fields are used here so the test is modern-API
      // clean.
      expect(color.r, 0.0);
      expect(color.g, 0.0);
      expect(color.b, 0.0);
      expect(color.a, greaterThan(0.0));
    }
  });

  testWidgets('dashboard content still renders (status banner + feature cards)',
      (tester) async {
    await buildDashboard(tester);
    expect(find.text('LODGE GATEWAY ONLINE'), findsOneWidget);
    expect(find.text('OUTFITTER OPERATIONS'), findsOneWidget);
    expect(find.text('Trophy Stock Inventory'), findsOneWidget);
  });

  testWidgets('resilient when Firebase auth is unavailable (test env)',
      (tester) async {
    await buildDashboard(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'An unavailable Firebase auth must not hang the dashboard '
            'on the loading spinner.');
    expect(find.text('OUTFITTER OPERATIONS'), findsOneWidget);
  });
}
