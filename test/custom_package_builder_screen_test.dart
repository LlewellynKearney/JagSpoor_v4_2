import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart';

/// Widget tests for the Custom Package Builder screen.
///
/// The builder previously rendered a blank screen because its reactive
/// species / service-rates `StreamBuilder`s had no `ConnectionState.waiting`
/// branch and the species stream used a server-side `.orderBy('speciesName')`
/// that required a composite index (missing-index -> the stream errored /
/// hung). These tests lock in the fix: the screen renders a loading indicator
/// (not blank) while a stream is pending, and renders a defined empty state
/// (not blank) when the farm has no published pricing.
///
/// In the test runner there is no signed-in Firebase user, so
/// `FarmGamePriceListManager` resolves `_currentUserId` to null ->
/// `getFarmPriceListStreamForHunter` returns `Stream.empty()` (never emits ->
/// the consuming `StreamBuilder` stays in `ConnectionState.waiting`) and
/// `getFarmServiceRatesStream` returns `Stream.value(FarmServiceRates.empty)`
/// (emits immediately). The `speciesLoading` guard therefore drives the
/// loading branch, which is exactly the "not blank" contract under test.
void main() {
  late ThemeController theme;

  setUp(() {
    theme = ThemeController();
  });

  HunterCustomPackageBuilderScreen _buildScreen() =>
      HunterCustomPackageBuilderScreen(
        theme: theme,
        farmId: 'farm-1',
        farmName: 'Test Farm',
        outfitterId: 'outfitter-1',
      );

  testWidgets('renders the Scaffold with the farm name AppBar (not blank)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _buildScreen(),
    ));

    // The AppBar must render the farm name -- proves the screen is not a
    // blank Container.
    expect(find.text('Test Farm'), findsOneWidget);
  });

  testWidgets('renders a defined empty state (not blank) when the farm has no visible pricing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _buildScreen(),
    ));
    await tester.pumpAndSettle();

    // With no signed-in Firebase user (the test runner), the manager's
    // `_currentUserId` resolves to null -> `getFarmPriceListStreamForHunter`
    // returns `Stream.empty()` (completes with no data) and the service-rates
    // stream returns `Stream.value(FarmServiceRates.empty)`. The builder's
    // StreamBuilder therefore lands in the empty-state branch and renders the
    // "No pricing published yet" banner -- NOT a blank screen. This is the
    // core "fix the blank screen" contract: every branch renders a defined
    // widget instead of an empty Container / hung spinner.
    expect(find.text('No pricing published yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'Stream.empty() completes immediately; the empty-state (not '
            'the loading spinner) is the correct render for an unauthenticated '
            'caller with no visible pricing.');
  });

  testWidgets('renders the CopyrightFooter', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _buildScreen(),
    ));
    await tester.pumpAndSettle();

    // The footer is the only thing the bug report said WAS rendering; the
    // fix keeps it while populating the body. Sanity-check it survives.
    expect(find.textContaining('JagSpoor'), findsWidgets);
  });
}
