import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'subscription_pricing.dart';

/// Pure detection helpers for the Google Play Billing error surface.
///
/// `itemAlreadyOwned` is NOT a failure — it is the store telling us the user
/// already holds this subscription (e.g. re-subscribing on a device where the
/// entitlement was never linked, or a replay after a reinstall). The correct
/// response is to restore the existing purchase, NOT to report a purchase
/// error. These helpers keep that classification in ONE place so the recorder
/// and the subscription screen agree.
class PlayBillingErrors {
  PlayBillingErrors._();

  /// The `IAPError.code` the Android plugin attaches to a failed purchase
  /// (`in_app_purchase_android` `kPurchaseErrorCode`).
  static const String purchaseErrorCode = 'purchase_error';

  /// Whether [error] represents `BillingResponse.itemAlreadyOwned`.
  ///
  /// The Android plugin does not expose the `BillingResponse` enum on the
  /// [IAPError]; it stringifies the response code into `message` (e.g.
  /// `"BillingResponse.itemAlreadyOwned"`) and puts the raw billing debug
  /// message in `details`. Both are scanned (case-insensitively) so the
  /// detection is robust to either spelling.
  static bool isItemAlreadyOwned(IAPError? error) =>
      isItemAlreadyOwnedMessage(error?.message) ||
      isItemAlreadyOwnedMessage('${error?.details}');

  /// Whether a raw string mentions `itemAlreadyOwned` (case-insensitive).
  static bool isItemAlreadyOwnedMessage(String? message) {
    if (message == null || message.isEmpty) return false;
    final normalized = message.toLowerCase();
    return normalized.contains('itemalreadyowned') ||
        normalized.contains('item_already_owned') ||
        normalized.contains('item already owned') ||
        // Some plugin builds surface the numeric response code (7) instead of
        // the enum name; only treat a bare 7 as owned when it is the whole
        // message (never a substring of another code like 17/70).
        normalized.trim() == '7';
  }
}

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

  /// Test seam: replaces [queryPastPurchases] so the `itemAlreadyOwned`
  /// recovery path can be exercised without the Android billing plugin.
  @visibleForTesting
  static Future<List<PurchaseDetails>> Function()? pastPurchasesForTesting;

  /// Test seam: replaces the plugin's `restorePurchases` call.
  @visibleForTesting
  static Future<void> Function()? restoreForTesting;

  /// Test seam: replaces the plugin's `completePurchase` call.
  @visibleForTesting
  static Future<void> Function(PurchaseDetails purchase)?
      completePurchaseForTesting;

  /// Records each [restorePurchases] invocation (tests assert the restore was
  /// requested when the store reported `itemAlreadyOwned`).
  @visibleForTesting
  static int restoreCallsForTesting = 0;

  /// Records each [completePurchase] invocation (tests assert the existing
  /// purchase was acknowledged).
  @visibleForTesting
  static final List<PurchaseDetails> completedPurchasesForTesting = [];

  /// Web-safe openable Play subscriptions URL (compliance + management).
  ///
  /// `playStoreSubscriptionsUrl` opens the platform subscriptions page for
  /// the given sku; `playStoreAppPageUrl` opens the app's Play listing where
  /// Google surfaces the same subscription controls.
  static const String playStoreSubscriptionsBase =
      'https://play.google.com/store/account/subscriptions?sku=';
  static const String playStoreAppPageUrl =
      'https://play.google.com/store/apps/details?id=za.co.jagspoor.app';

  /// The website billing page (PayFast). Shown ONLY to PayFast-billed
  /// subscribers — a Google Play-billed user is ALWAYS routed to Google Play's
  /// own subscriptions manager (Play policy), never to this URL.
  static const String websiteBillingUrl =
      'https://jagspoor.co.za/account/billing';

  @visibleForTesting
  static void resetTestSeams() {
    billingForTesting = null;
    productsForTesting = null;
    pastPurchasesForTesting = null;
    restoreForTesting = null;
    completePurchaseForTesting = null;
    restoreCallsForTesting = 0;
    completedPurchasesForTesting.clear();
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
    restoreCallsForTesting++;
    final override = restoreForTesting;
    if (override != null) {
      try {
        await override();
      } catch (e) {
        debugPrint('PlayBillingService.restorePurchases (test) failed: $e');
      }
      return;
    }
    try {
      await _billing.restorePurchases();
    } catch (e) {
      debugPrint('PlayBillingService.restorePurchases failed: $e');
    }
  }

  /// Queries Google Play for the user's EXISTING (non-consumed) purchases.
  ///
  /// This is the authoritative lookup for the `itemAlreadyOwned` recovery
  /// path: when the store reports the subscription is already owned, the app
  /// must find that live purchase and acknowledge it rather than reporting a
  /// purchase error. Returns an empty list (never throws) when billing is
  /// unavailable, the platform is not Android, or the query fails — so callers
  /// can treat "no result" as "nothing to restore".
  ///
  /// `restorePurchases()` alone is not enough here: it replays purchases onto
  /// [purchaseStream], but a caller that needs the purchase object
  /// SYNCHRONOUSLY (to call `completePurchase`) must query for it.
  Future<List<PurchaseDetails>> queryPastPurchases() async {
    final override = pastPurchasesForTesting;
    if (override != null) {
      try {
        return await override();
      } catch (e) {
        debugPrint('PlayBillingService.queryPastPurchases (test) failed: $e');
        return const <PurchaseDetails>[];
      }
    }
    try {
      // `queryPastPurchases` lives on the Android platform ADDITION, not on the
      // core `InAppPurchase` facade. `getPlatformAddition` casts the active
      // addition to the Android type — on a non-Android platform (or with no
      // plugin registered) it throws, which the catch below turns into an
      // empty result.
      final addition = _billing.getPlatformAddition<
          InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      return response.pastPurchases;
    } catch (e) {
      debugPrint('PlayBillingService.queryPastPurchases unavailable: $e');
      return const <PurchaseDetails>[];
    }
  }

  /// Finds the live purchase for [productId] among the store's existing
  /// purchases. Prefers a purchased / restored entry (an acknowledged, still
  /// valid subscription) and falls back to the first match for the product.
  Future<PurchaseDetails?> findExistingPurchase(String productId) async {
    final past = await queryPastPurchases();
    PurchaseDetails? fallback;
    for (final purchase in past) {
      if (purchase.productID != productId) continue;
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        return purchase;
      }
      fallback ??= purchase;
    }
    return fallback;
  }

  /// Finishes the transaction so the store stops holding it. Must be called
  /// once the entitlement has been recorded.
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completedPurchasesForTesting.add(purchase);
    final override = completePurchaseForTesting;
    if (override != null) {
      try {
        await override(purchase);
      } catch (e) {
        debugPrint('PlayBillingService.completePurchase (test) failed: $e');
      }
      return;
    }
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