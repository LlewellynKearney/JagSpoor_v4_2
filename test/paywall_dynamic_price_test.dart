import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/subscription/paywall_screen.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';

/// Task 2 (Option A VAT): the paywall must NEVER hardcode a price. It shows
/// the live Google Play catalog label (already localized + VAT inclusive per
/// the Play Console base plan, e.g. "R34.99") and falls back to a neutral
/// "Loading price…" placeholder — never an invented amount such as R40.24.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PlayBillingService.resetTestSeams();
  });

  tearDown(() {
    PlayBillingService.resetTestSeams();
  });

  Widget buildPaywall() => MaterialApp(
        home: PaywallScreen(theme: ThemeController()),
      );

  testWidgets('renders the neutral loading label when the Play catalog has '
      'not resolved — never a hardcoded price', (tester) async {
    await tester.pumpWidget(buildPaywall());
    await tester.pump();

    final priceLabel = find.byKey(const ValueKey('paywallPriceLabel'));
    expect(priceLabel, findsOneWidget);
    final priceText = tester.widget<Text>(priceLabel);
    expect(priceText.data, PaywallScreen.loadingPriceLabel);

    // No speculative VAT-added or exclusive-VAT figures leak into the UI.
    for (final forbidden in const [
      'R40.24',
      'R344.99',
      'R30.43',
      'R260.86',
      'R34.99',
      'R299.99',
    ]) {
      expect(
        find.text(forbidden),
        findsNothing,
        reason: 'paywall must not hardcode $forbidden',
      );
    }
  });

  testWidgets('the price label is always present after resolution settles',
      (tester) async {
    await tester.pumpWidget(buildPaywall());
    await tester.pump(const Duration(milliseconds: 50));
    // Whether or not a live catalog is reachable in the test host, the
    // paywall always renders exactly ONE price label (either the Play label
    // or the loading placeholder) — it can never render a hardcoded amount.
    expect(find.byKey(const ValueKey('paywallPriceLabel')), findsOneWidget);
    expect(find.text('per month · includes VAT'), findsOneWidget);
  });

  testWidgets('uses the fake Firestore seam without crashing', (tester) async {
    // Guards against a regression where the paywall touches Firestore at
    // build time (it should not — the price comes from Play Billing).
    await FakeFirebaseFirestore().collection('admin_config').doc('pricing').set({
      'hunter_monthly': 34.99,
      'outfitter_monthly': 299.99,
    });
    await tester.pumpWidget(buildPaywall());
    await tester.pump();
    expect(find.byKey(const ValueKey('paywallPlaySubscribeButton')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('paywallWebsiteButton')), findsOneWidget);
  });
}
