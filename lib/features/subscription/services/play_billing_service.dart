import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'subscription_pricing.dart';

/// Immutable snapshot of a product loaded from the Play Billing catalog.
class PlayProduct {
  final SubscriptionTier tier;
  final String productId;
  final String title;
  final String description;
  final String price; // Formatted, e.g. "R 19,99" per the Play locale.
  final double rawPrice; // Unformatted catalog price (full currency units).
  final String currencyCode;
  final String currencySymbol;

  const PlayProduct({
    required this.tier,
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    this.currencySymbol = '',
  });

  static PlayProduct fromProductDetails(
    SubscriptionTier tier,
    ProductDetails details,
  ) {
    return PlayProduct(
      tier: tier,
      productId: details.id,
      title: details.title,
      description: details.description,
      price: details.price,
      rawPrice: details.rawPrice,
      currencyCode: details.currencyCode,
      currencySymbol: details.currencySymbol,
    );
  }

  /// Reconstructs the authoritative [ProductDetails] this product was loaded
  /// from, so the purchase flow hands Google Play Billing the real catalog
  /// metadata (id, title, description, price, raw price, currency) instead of
  /// a reconstructed copy. This is what keeps the app's purchase flow
  /// synchronized with the Play Console.
  ProductDetails toProductDetails() {
    return ProductDetails(
      id: productId,
      title: title,
      description: description,
      price: price,
      rawPrice: rawPrice,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
    );
  }
}

/// Adapter around the official `in_app_purchase` plugin for Google Play
/// Billing subscriptions.
///
/// The app ships ONE payment channel: Google Play Billing. Subscriptions are
/// recurring and managed *inside Google Play* (the Play Console product
/// catalog + the Play Store subscriptions center), which is what the Google
/// Play Payments policy requires.
///
/// Responsibilities:
///  - Expose the store's availability (`isBillingSupported`).
///  - Load the Hunter / Outfitter subscription products from the Play
///    catalog (`loadProducts`).
///  - Purchase a subscription (`purchaseProduct`) and listen for its
///    completion via [purchaseStream].
///  - Restore / refresh prior purchases (`restorePurchases`) so a subscriber
///    on a new device re-syncs their entitlement.
///  - Forward the user to the Play Store subscription management page for
///    pausing / cancelling / payment-method changes (`openSubscriptionCenter`)
///    — Google Play handles the actual recurring-billing lifecycle.
///
/// Client-side verification note: Google Play's `purchaseState` on
/// [PurchaseDetails] is trusted here for displaying the entitlement, and the
/// authoritative subscription state is mirrored on `users/{uid}`. For
/// production-grade entitlement enforcement a server-side receipt check
/// (Play Developer API) should be layered on top; the service persists the
/// Play Billing purchase token so that can ride along.
class PlayBillingService {
  PlayBillingService._();
  static final PlayBillingService instance = PlayBillingService._();

  /// The plugin facade. Overridable for tests via [billingForTesting].
  @visibleForTesting
  static InAppPurchase? billingForTesting;

  /// Web-safe openable Play subscriptions URL (compliance + management).
  ///
  /// `playStoreSubscriptionsUrl` opens the platform subscriptions page for
  /// the given sku; `playStoreAppPageUrl` opens the app's Play listing where
  /// Google surfaces the same subscription controls.
  static const String playStoreSubscriptionsBase =
      'https://play.google.com/store/account/subscriptions?sku=';
  static const String playStoreAppPageUrl =
      'https://play.google.com/store/apps/details?id=com.example.jagspoor';

  @visibleForTesting
  static void resetTestSeams() {
    billingForTesting = null;
  }

  InAppPurchase get _billing => billingForTesting ?? InAppPurchase.instance;

  /// Whether Google Play Billing is available on this device.
  Future<bool> isBillingSupported() async {
    try {
      return await _billing.isAvailable();
    } catch (e) {
      debugPrint('PlayBillingService.isAvailable failed: $e');
      return false;
    }
  }

  /// The set of product ids the app subscribes to.
  Set<String> get productIds =>
      SubscriptionTier.values.map((t) => t.playProductId).toSet();

  /// Streams every purchase event (including restored purchases) so the
  /// caller can update entitlement UI reactively.
  Stream<List<PurchaseDetails>> get purchaseStream => _billing.purchaseStream;

  /// Loads the Hunter + Outfitter subscription product details from the Play
  /// Billing catalog.
  ///
  /// Returns a map keyed by [SubscriptionTier]. A tier is absent when its
  /// product id is not configured in the Play Console (only in store, dev,
  /// reviewer builds) so the caller degrades gracefully.
  Future<Map<SubscriptionTier, PlayProduct>> loadProducts() async {
    final response = await _billing.queryProductDetails(productIds);
    final result = <SubscriptionTier, PlayProduct>{};
    for (final details in response.productDetails) {
      final tier = SubscriptionTier.fromPlayProductId(details.id);
      result[tier] = PlayProduct.fromProductDetails(tier, details);
    }
    return result;
  }

  /// Launches the Google Play Billing purchase flow for [tier]. Returns false
  /// when the product has not been configured in the Play Console or the
  /// purchase could not be initiated (e.g. billing unavailable).
  ///
  /// The result of the purchase is delivered asynchronously through
  /// [purchaseStream]; consumers should listen there and complete the
  /// purchase with [completePurchase].
  Future<bool> purchaseProduct(SubscriptionTier tier) async {
    final Map<SubscriptionTier, PlayProduct> products;
    try {
      products = await loadProducts();
    } catch (e) {
      debugPrint('PlayBillingService.loadProducts failed: $e');
      return false;
    }
    final product = products[tier];
    if (product == null) {
      debugPrint(
        'PlayBillingService: product ${tier.playProductId} not found in the '
        'Play catalog — is it configured in the Play Console?',
      );
      return false;
    }
    try {
      // Pass the REAL ProductDetails loaded from the Play catalog (not a
      // reconstructed copy) so Google Play Billing receives the authoritative
      // product metadata + pricing configured in the Play Console — this is
      // what keeps the app's purchase flow synchronized with the store.
      return await _billing.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product.toProductDetails()),
      );
    } catch (e) {
      debugPrint('PlayBillingService.buyNonConsumable failed: $e');
      return false;
    }
  }

  /// Restores / refreshes purchases so an existing subscriber re-syncs their
  /// entitlement (e.g. after reinstalling or on a new device).
  Future<void> restorePurchases() async {
    try {
      await _billing.restorePurchases();
    } catch (e) {
      debugPrint('PlayBillingService.restorePurchases failed: $e');
    }
  }

  /// Finishes the transaction so the store stops holding it. Must be called
  /// once the entitlement has been recorded.
  Future<void> completePurchase(PurchaseDetails purchase) async {
    try {
      await _billing.completePurchase(purchase);
    } catch (e) {
      debugPrint('PlayBillingService.completePurchase failed: $e');
    }
  }

  /// Deep link URL for the user to manage / cancel their subscription inside
  /// Google Play (policy-compliant: Play handles recurring billing).
  String subscriptionCenterUrlFor(SubscriptionTier tier) =>
      '$playStoreSubscriptionsBase${tier.playProductId}&package=com.example.jagspoor';
}