import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/subscription/paywall_screen.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_purchase_recorder.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

/// Option A VAT compliance: the listed subscription price IS the final
/// VAT-inclusive charge. The Play Console base plan (and `admin_config/pricing`)
/// carry the amount the customer pays — R34.99 hunter / R299.99 outfitter — and
/// the app must display that amount verbatim, never grossed up by 15% (the
/// previous `exVat * 1.15` treatment rendered a R34.99 base plan as R40.24).
///
/// Regression guard for the "paywall still shows R40.24" bug.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PlayBillingService.resetTestSeams();
    PlayPurchaseRecorder.resetTestSeams();
  });

  tearDown(() {
    PlayBillingService.resetTestSeams();
    PlayPurchaseRecorder.resetTestSeams();
    UserRoleProvider.instance.reset();
  });

  PlayProduct productFor(SubscriptionTier tier, double price) => PlayProduct(
        tier: tier,
        productId: tier.playProductId,
        title: tier == SubscriptionTier.outfitter ? 'Outfitter' : 'Hunter',
        description: 'Monthly subscription',
        price: 'R${price.toStringAsFixed(2)}',
        rawPrice: price,
        currencyCode: 'ZAR',
        currencySymbol: 'R',
      );

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

  testWidgets('shows the VAT-inclusive hunter price verbatim (NOT R40.24)',
      (tester) async {
    // The Play Console base plan carries the final VAT-inclusive charge.
    PlayBillingService.productsForTesting = {
      SubscriptionTier.hunter: productFor(SubscriptionTier.hunter, 34.99),
    };
    await tester.pumpWidget(buildPaywall());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The exact Option A listed price — the R40.24 double-VAT bug is gone.
    expect(find.text('R 34.99/month'), findsOneWidget);
    expect(find.text('R40.24/month'), findsNothing);
    // Explanatory subtext states the VAT rate.
    expect(find.text('Incl. 15% VAT'), findsOneWidget);
  });

  testWidgets('shows the VAT-inclusive outfitter price verbatim',
      (tester) async {
    UserRoleProvider.instance.setRole(AppRole.outfitter);
    PlayBillingService.productsForTesting = {
      SubscriptionTier.outfitter:
          productFor(SubscriptionTier.outfitter, 299.99),
    };
    await tester.pumpWidget(buildPaywall());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('R 299.99/month'), findsOneWidget);
    expect(find.text('R344.99/month'), findsNothing);
    expect(find.text('Incl. 15% VAT'), findsOneWidget);
    UserRoleProvider.instance.reset();
  });

  testWidgets('the price label is always present after resolution settles',
      (tester) async {
    await tester.pumpWidget(buildPaywall());
    await tester.pump(const Duration(milliseconds: 50));
    // Whether or not a live catalog is reachable in the test host, the
    // paywall always renders exactly ONE price label (either the Play label
    // or the loading placeholder) — it can never render a hardcoded amount.
    expect(find.byKey(const ValueKey('paywallPriceLabel')), findsOneWidget);
    expect(find.byKey(const ValueKey('paywallVatNote')), findsOneWidget);
  });

  testWidgets('renders the subscribe + website actions', (tester) async {
    await tester.pumpWidget(buildPaywall());
    await tester.pump();
    expect(find.byKey(const ValueKey('paywallPlaySubscribeButton')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('paywallWebsiteButton')), findsOneWidget);
  });

  group('SubscriptionVatPrice', () {
    test('fromInclusive shows the listed price verbatim (no double VAT)', () {
      final p = SubscriptionVatPrice.fromInclusive(34.99);
      expect(p.inclVat, 34.99);
      expect(p.exVat, closeTo(30.4261, 0.001));
      expect(p.vatAmount, closeTo(4.5639, 0.001));
      expect(p.primaryLabel, 'R 34.99/month');
      expect(p.vatNote, 'Incl. 15% VAT');
      // The exact bug: a R34.99 base plan must NOT render as R40.24.
      expect(p.primaryLabel, isNot('R 40.24/month'));
    });

    test('fromInclusive applies to the outfitter amount', () {
      final p = SubscriptionVatPrice.fromInclusive(299.99);
      expect(p.inclVat, 299.99);
      expect(p.exVat, closeTo(260.8608, 0.001));
      expect(p.primaryLabel, 'R 299.99/month');
      expect(p.vatNote, 'Incl. 15% VAT');
    });

    test('fromExVat still grosses a genuinely VAT-exclusive figure up', () {
      final p = SubscriptionVatPrice.fromExVat(30.43);
      expect(p.exVat, 30.43);
      expect(p.inclVat, closeTo(34.9945, 0.001));
      expect(p.primaryLabel, 'R 34.99/month');
    });

    test('non-positive / invalid amounts resolve to zero', () {
      expect(SubscriptionVatPrice.fromInclusive(0).inclVat, 0);
      expect(SubscriptionVatPrice.fromInclusive(-5).inclVat, 0);
      expect(SubscriptionVatPrice.fromInclusive(double.nan).inclVat, 0);
    });

    test('honours the store currency symbol', () {
      final p = SubscriptionVatPrice.fromInclusive(100, currencySymbol: r'$');
      expect(p.primaryLabel, r'$ 100.00/month');
    });
  });
}
