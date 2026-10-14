import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/features/subscription/subscription_screen.dart';

/// Google Play Billing Library v5+ REQUIRES the subscription base-plan
/// **offer token**; `launchBillingFlow` rejects a null token with
/// `INVALID_OFFER_TOKEN`. These tests lock the fix end-to-end against a fake
/// [InAppPurchasePlatform]: the catalog query yields REAL
/// [GooglePlayProductDetails] (with a base plan), the service extracts the
/// offer token, and the purchase flow hands Google Play a
/// [GooglePlayPurchaseParam] carrying that token.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Pre-warm the aggregator OUTSIDE any test body: on this host
    // `defaultTargetPlatform` reports Android, which would make
    // `InAppPurchase.instance` register the real Android platform (and fire a
    // pigeon `startConnection` call that has no host implementation). Creating
    // it under a temporary override caches the aggregator WITHOUT registering
    // a platform, so each test can install its own fake via
    // `InAppPurchasePlatform.instance`.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    PlayBillingService.resetTestSeams();
  });

  tearDown(() {
    PlayBillingService.resetTestSeams();
  });

  /// A subscription [GooglePlayProductDetails] backed by a real Play catalog
  /// wrapper with one base plan / offer.
  GooglePlayProductDetails googlePlaySubscription(
    String productId, {
    required String offerToken,
    String basePlanId = 'monthly',
    int priceAmountMicros = 30430000,
    String formattedPrice = 'R30.43',
  }) {
    final wrapper = ProductDetailsWrapper(
      description: 'Monthly subscription',
      name: 'Hunter',
      productId: productId,
      productType: ProductType.subs,
      title: 'Hunter (JagSpoor)',
      subscriptionOfferDetails: <SubscriptionOfferDetailsWrapper>[
        SubscriptionOfferDetailsWrapper(
          basePlanId: basePlanId,
          offerTags: const <String>[],
          offerIdToken: offerToken,
          pricingPhases: <PricingPhaseWrapper>[
            PricingPhaseWrapper(
              billingCycleCount: 0,
              billingPeriod: 'P1M',
              formattedPrice: formattedPrice,
              priceAmountMicros: priceAmountMicros,
              priceCurrencyCode: 'ZAR',
              recurrenceMode: RecurrenceMode.infiniteRecurring,
            ),
          ],
        ),
      ],
    );
    return GooglePlayProductDetails.fromProductDetails(wrapper).first;
  }

  test('loadProducts extracts the offer token + base plan from the Play catalog',
      () async {
    InAppPurchasePlatform.instance = _FakeIapPlatform(
      products: <ProductDetails>[
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: 'tok-hunter-monthly',
        ),
      ],
    );

    final products = await PlayBillingService.instance.loadProducts();
    final hunter = products[SubscriptionTier.hunter]!;
    expect(hunter.offerToken, 'tok-hunter-monthly');
    expect(hunter.basePlanId, 'monthly');
    expect(hunter.isPurchasable, isTrue);
    expect(hunter.rawPrice, closeTo(30.43, 0.001));
  });

  test('collapses monthly + yearly base plans into a single launchable entry',
      () async {
    InAppPurchasePlatform.instance = _FakeIapPlatform(
      products: <ProductDetails>[
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: 'tok-monthly',
          basePlanId: 'monthly',
        ),
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: 'tok-yearly',
          basePlanId: 'yearly',
        ),
      ],
    );

    final products = await PlayBillingService.instance.loadProducts();
    // One entry per tier (the per-base-plan rows are collapsed).
    expect(products, hasLength(1));
    expect(products[SubscriptionTier.hunter]!.offerToken, 'tok-monthly');
  });

  test('a base-plan row without an offer token is upgraded by a later one',
      () async {
    InAppPurchasePlatform.instance = _FakeIapPlatform(
      products: <ProductDetails>[
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: '',
          basePlanId: 'stale',
        ),
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: 'tok-good',
          basePlanId: 'monthly',
        ),
      ],
    );

    final products = await PlayBillingService.instance.loadProducts();
    expect(products[SubscriptionTier.hunter]!.offerToken, 'tok-good');
    expect(products[SubscriptionTier.hunter]!.isPurchasable, isTrue);
  });

  test('purchaseProduct launches a GooglePlayPurchaseParam with the offer token',
      () async {
    final fake = _FakeIapPlatform(
      products: <ProductDetails>[
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: 'tok-hunter-monthly',
        ),
      ],
    );
    InAppPurchasePlatform.instance = fake;

    final launched =
        await PlayBillingService.instance.purchaseProduct(SubscriptionTier.hunter);

    expect(launched, isTrue);
    expect(fake.buys, hasLength(1));
    final param = fake.buys.single;
    expect(param, isA<GooglePlayPurchaseParam>());
    expect((param as GooglePlayPurchaseParam).offerToken, 'tok-hunter-monthly');
    // The REAL catalog object is handed over (so the plugin can resolve the
    // token itself as a fallback).
    expect(param.productDetails, isA<GooglePlayProductDetails>());
  });

  test('buyProduct handles both monthly and yearly products', () async {
    final fake = _FakeIapPlatform(
      products: <ProductDetails>[
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: 'tok-hunter',
          basePlanId: 'monthly',
        ),
        googlePlaySubscription(
          'jagspoor_outfitter_monthly',
          offerToken: 'tok-outfitter',
          basePlanId: 'yearly',
        ),
      ],
    );
    InAppPurchasePlatform.instance = fake;

    final products = await PlayBillingService.instance.loadProducts();
    expect(
      await PlayBillingService.instance
          .buyProduct(products[SubscriptionTier.hunter]!),
      isTrue,
    );
    expect(
      await PlayBillingService.instance
          .buyProduct(products[SubscriptionTier.outfitter]!),
      isTrue,
    );
    expect(
      fake.buys.map((p) => (p as GooglePlayPurchaseParam).offerToken),
      <String>['tok-hunter', 'tok-outfitter'],
    );
  });

  test('a product with no offer token is refused instead of launching',
      () async {
    final fake = _FakeIapPlatform(
      products: <ProductDetails>[
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: '',
        ),
      ],
    );
    InAppPurchasePlatform.instance = fake;

    final launched =
        await PlayBillingService.instance.purchaseProduct(SubscriptionTier.hunter);

    expect(launched, isFalse);
    // The flow never reached the store — no INVALID_OFFER_TOKEN can occur.
    expect(fake.buys, isEmpty);
  });

  test('a PlayProduct fixture reports its offer token / purchasability', () {
    const purchasable = PlayProduct(
      tier: SubscriptionTier.hunter,
      productId: 'jagspoor_hunter_monthly',
      title: 'Hunter',
      description: 'Monthly',
      price: 'R30.43',
      rawPrice: 30.43,
      currencyCode: 'ZAR',
      currencySymbol: 'R',
      offerToken: 'tok',
    );
    expect(purchasable.isPurchasable, isTrue);

    const tokenless = PlayProduct(
      tier: SubscriptionTier.hunter,
      productId: 'jagspoor_hunter_monthly',
      title: 'Hunter',
      description: 'Monthly',
      price: 'R30.43',
      rawPrice: 30.43,
      currencyCode: 'ZAR',
      currencySymbol: 'R',
    );
    expect(tokenless.isPurchasable, isFalse);
  });

  testWidgets(
      'the SUBSCRIBE button is disabled + shows loading until the catalog '
      'resolves', (tester) async {
    // The catalog query never completes, so the screen stays in the loading
    // state and the button must NOT be tappable (it can never launch before
    // the offer token is known).
    InAppPurchasePlatform.instance = _FakeIapPlatform(
      products: const <ProductDetails>[],
      hangCatalog: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: SubscriptionScreen(theme: ThemeController())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('subscribeButton')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();

    expect(find.text('LOADING GOOGLE PLAY…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('subscribeButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'a configured product with an offer token enables the SUBSCRIBE button',
      (tester) async {
    InAppPurchasePlatform.instance = _FakeIapPlatform(
      products: <ProductDetails>[
        googlePlaySubscription(
          'jagspoor_hunter_monthly',
          offerToken: 'tok-hunter',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: SubscriptionScreen(theme: ThemeController())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('subscribeButton')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('subscribeButton')),
    );
    expect(button.onPressed, isNotNull);
  });
}

/// Minimal fake platform that returns a canned catalog + records purchases.
class _FakeIapPlatform extends InAppPurchasePlatform {
  _FakeIapPlatform({required this.products, this.hangCatalog = false});

  final List<ProductDetails> products;
  final bool hangCatalog;
  final List<PurchaseParam> buys = <PurchaseParam>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) {
    if (hangCatalog) return Completer<ProductDetailsResponse>().future;
    final found =
        products.where((p) => identifiers.contains(p.id)).toList(growable: false);
    return Future<ProductDetailsResponse>.value(
      ProductDetailsResponse(
        productDetails: found,
        notFoundIDs:
            identifiers.difference(found.map((p) => p.id).toSet()).toList(),
      ),
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buys.add(purchaseParam);
    return true;
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      const Stream<List<PurchaseDetails>>.empty();

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}
}
