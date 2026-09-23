import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/subscription/paywall_screen.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_purchase_recorder.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

/// v9.2 VAT compliance: Google Play quotes the catalog amount EXCLUDING VAT in
/// South Africa, so the paywall must show the VAT-inclusive amount the customer
/// is actually charged (`exVat * 1.15`) as the primary price, with the ex-VAT
/// figure as the explanatory subtext. Applies to both `jagspoor_hunter_monthly`
/// and `jagspoor_outfitter_monthly`.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PlayBillingService.resetTestSeams();
    PlayPurchaseRecorder.resetTestSeams();
  });

  tearDown(() {
    PlayBillingService.resetTestSeams();
    PlayPurchaseRecorder.resetTestSeams();
  });

  PlayProduct productFor(SubscriptionTier tier, double exVat) => PlayProduct(
        tier: tier,
        productId: tier.playProductId,
        title: tier == SubscriptionTier.outfitter ? 'Outfitter' : 'Hunter',
        description: 'Monthly subscription',
        price: 'R${exVat.toStringAsFixed(2)}',
        rawPrice: exVat,
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

  testWidgets('shows the VAT-inclusive hunter price with the ex-VAT subtext',
      (tester) async {
    // The catalog amount is quoted excluding VAT (e.g. R199.00 ex VAT).
    PlayBillingService.productsForTesting = {
      SubscriptionTier.hunter: productFor(SubscriptionTier.hunter, 199.00),
    };
    await tester.pumpWidget(buildPaywall());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Primary price = exVat * 1.15 = R228.85.
    expect(find.text('R228.85/month'), findsOneWidget);
    // Explanatory subtext carries both the VAT rate and the ex-VAT amount.
    expect(
      find.text('Incl. 15% VAT (R199.00 excl. VAT)'),
      findsOneWidget,
    );
  });

  testWidgets('shows the VAT-inclusive outfitter price', (tester) async {
    UserRoleProvider.instance.setRole(AppRole.outfitter);
    PlayBillingService.productsForTesting = {
      SubscriptionTier.outfitter:
          productFor(SubscriptionTier.outfitter, 299.99),
    };
    await tester.pumpWidget(buildPaywall());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 299.99 * 1.15 = 344.9885 -> R344.99.
    expect(find.text('R344.99/month'), findsOneWidget);
    expect(find.text('Incl. 15% VAT (R299.99 excl. VAT)'), findsOneWidget);
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
    test('derives the inclusive amount + VAT note from an ex-VAT amount', () {
      final p = SubscriptionVatPrice.fromExVat(199.00);
      expect(p.exVat, 199.00);
      expect(p.inclVat, closeTo(228.85, 0.001));
      expect(p.vatAmount, closeTo(29.85, 0.001));
      expect(p.primaryLabel, 'R228.85/month');
      expect(p.vatNote, 'Incl. 15% VAT (R199.00 excl. VAT)');
    });

    test('applies the SA 15% rate to the outfitter amount', () {
      final p = SubscriptionVatPrice.fromExVat(299.99);
      expect(p.inclVat, closeTo(344.9885, 0.0001));
      expect(p.primaryLabel, 'R344.99/month');
      expect(p.vatNote, 'Incl. 15% VAT (R299.99 excl. VAT)');
    });

    test('non-positive / invalid amounts resolve to zero', () {
      expect(SubscriptionVatPrice.fromExVat(0).inclVat, 0);
      expect(SubscriptionVatPrice.fromExVat(-5).inclVat, 0);
      expect(SubscriptionVatPrice.fromExVat(double.nan).inclVat, 0);
    });

    test('honours the store currency symbol', () {
      final p = SubscriptionVatPrice.fromExVat(100, currencySymbol: r'$');
      expect(p.primaryLabel, r'$115.00/month');
    });
  });
}
