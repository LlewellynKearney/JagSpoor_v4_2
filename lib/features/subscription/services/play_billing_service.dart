import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

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

  /// The Google Play **base plan / offer token** required to launch a
  /// subscription purchase (Billing Library v5+).
  ///
  /// Extracted from the product's `subscriptionOfferDetails` (the first
  /// base plan's `offerToken`). It is `null` for a one-time product — and also
  /// `null` when a subscription product has no ACTIVE base plan in the Play
  /// Console, which is exactly the condition Google Play reports as
  /// `INVALID_OFFER_TOKEN`. The purchase flow must never launch without it.
  final String? offerToken;

  /// The Play base plan id backing [offerToken] (e.g. `monthly` / `yearly`),
  /// when the catalog exposes one. Diagnostic only.
  final String? basePlanId;

  /// The authoritative Play catalog object this snapshot was built from, kept
  /// so the purchase flow can hand Google Play the REAL
  /// [GooglePlayProductDetails] (which carries the offer token + base plan).
  final ProductDetails? _details;

  const PlayProduct({
    required this.tier,
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    this.currencySymbol = '',
    this.offerToken,
    this.basePlanId,
    ProductDetails? details,
  }) : _details = details;

  /// Builds a snapshot from a [ProductDetails] returned by
  /// `queryProductDetails`.
  ///
  /// On Android the plugin returns a [GooglePlayProductDetails] per base plan,
  /// so the `offerToken` is read from the Google Play specific type. When the
  /// plugin hands back the platform-agnostic [ProductDetails] (iOS / tests /
  /// non-subscription products) `offerToken` stays `null` and the purchase
  /// flow falls back to the plain [PurchaseParam] path.
  static PlayProduct fromProductDetails(
    SubscriptionTier tier,
    ProductDetails details,
  ) {
    final googlePlay =
        details is GooglePlayProductDetails ? details : null;
    return PlayProduct(
      tier: tier,
      productId: details.id,
      title: details.title,
      description: details.description,
      price: details.price,
      rawPrice: details.rawPrice,
      currencyCode: details.currencyCode,
      currencySymbol: details.currencySymbol,
      offerToken: googlePlay?.offerToken,
      basePlanId: googlePlay?.productDetails
          .subscriptionOfferDetails?[googlePlay.subscriptionIndex ?? 0]
          .basePlanId,
      details: details,
    );
  }

  /// Whether this product can be purchased as a Google Play subscription —
  /// i.e. a base plan offer token was resolved from the catalog.
  bool get isPurchasable => offerToken != null && offerToken!.isNotEmpty;

  /// The authoritative catalog object to hand the purchase flow.
  ///
  /// Prefers the ORIGINAL [ProductDetails] the snapshot was built from, so the
  /// purchase flow passes the REAL [GooglePlayProductDetails] (which carries
  /// the offer token) to the plugin rather than a reconstructed copy. Only
  /// falls back to a reconstructed copy for a product built without a
  /// backing catalog object (e.g. a test fixture) — and that copy is NEVER a
  /// [GooglePlayProductDetails], so it can only ever be used for the
  /// one-time / non-subscription path.
  ProductDetails toProductDetails() {
    final original = _details;
    if (original != null) return original;
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

  /// Test seam: a canned Play catalog so the price rendering (including the
  /// ex-VAT -> VAT-inclusive conversion) can be asserted without the
  /// `in_app_purchase` platform plugin.
  @visibleForTesting
  static Map<SubscriptionTier, PlayProduct>? productsForTesting;

  /// Web-safe openable Play subscriptions URL (compliance + management).
  ///
  /// `playStoreSubscriptionsUrl` opens the platform subscriptions page for
  /// the given sku; `playStoreAppPageUrl` opens the app's Play listing where
  /// Google surfaces the same subscription controls.
  static const String playStoreSubscriptionsBase =
      'https://play.google.com/store/account/subscriptions?sku=';
  static const String playStoreAppPageUrl =
      'https://play.google.com/store/apps/details?id=za.co.jagspoor.app';

  @visibleForTesting
  static void resetTestSeams() {
    billingForTesting = null;
    productsForTesting = null;
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
  /// Billing catalog via [queryProductDetails].
  ///
  /// Returns a map keyed by [SubscriptionTier]. A tier is absent when its
  /// product id is not configured in the Play Console (only in store, dev,
  /// reviewer builds) so the caller degrades gracefully.
  ///
  /// **Google Play returns ONE [GooglePlayProductDetails] per base plan / offer
  /// per subscription product** (e.g. a `monthly` and a `yearly` base plan both
  /// surface under `jagspoor_hunter_monthly`). This collapses them to a single
  /// entry per tier, preferring the FIRST catalog entry that carries a usable
  /// offer token — the one the purchase flow can actually launch.
  Future<Map<SubscriptionTier, PlayProduct>> loadProducts() async {
    final canned = productsForTesting;
    if (canned != null) return canned;
    final response = await _billing.queryProductDetails(productIds);
    final result = <SubscriptionTier, PlayProduct>{};
    for (final details in response.productDetails) {
      final tier = SubscriptionTier.fromPlayProductId(details.id);
      final candidate = PlayProduct.fromProductDetails(tier, details);
      final existing = result[tier];
      // First entry wins, EXCEPT an entry without an offer token is upgraded
      // by a later entry that has one (the duplicate base-plan rows the plugin
      // emits must not shadow a launchable offer).
      if (existing == null ||
          (!existing.isPurchasable && candidate.isPurchasable)) {
        result[tier] = candidate;
      }
    }
    if (result.isEmpty && response.notFoundIDs.isNotEmpty) {
      debugPrint(
        'PlayBillingService: no products resolved — the Play Console products '
        'may not be active/published yet (queried: ${response.notFoundIDs}).',
      );
    }
    return result;
  }

  /// Launches the Google Play Billing purchase flow for [tier]. Returns false
  /// when the product has not been configured in the Play Console, has no
  /// ACTIVE base plan (no offer token), or the purchase could not be initiated
  /// (e.g. billing unavailable).
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
    return buyProduct(product);
  }

  /// Launches the purchase flow for an already-loaded [product].
  ///
  /// Google Play Billing Library v5+ REQUIRES the base-plan **offer token**
  /// for a subscription (`launchBillingFlow` rejects a null token with
  /// `INVALID_OFFER_TOKEN`). The token is resolved from the catalog in
  /// [loadProducts] (via [GooglePlayProductDetails.offerToken]) and passed to
  /// the plugin on a [GooglePlayPurchaseParam]. A product with no active base
  /// plan is refused here (with an actionable log) instead of surfacing the
  /// opaque platform exception.
  Future<bool> buyProduct(PlayProduct product) async {
    if (product.offerToken == null || product.offerToken!.isEmpty) {
      debugPrint(
        'PlayBillingService: no offer token for ${product.productId} — the '
        'base plan is not active/published in the Play Console. Activate the '
        'base plan (and any free-trial offer) and re-check the catalog.',
      );
      return false;
    }
    try {
      // Pass the REAL ProductDetails loaded from the Play catalog (not a
      // reconstructed copy) wrapped in a GooglePlayPurchaseParam carrying the
      // base-plan offer token, so Google Play Billing receives the
      // authoritative product metadata + the offer it must charge for.
      return await _billing.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: product.toProductDetails(),
          offerToken: product.offerToken,
        ),
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
      '$playStoreSubscriptionsBase${tier.playProductId}&package=za.co.jagspoor.app';
}