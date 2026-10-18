import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/web_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../services/entitlement_service.dart';
import '../admin/services/subscription_config_service.dart';
import '../auth/services/user_role_provider.dart';
import '../billing/billing_plans.dart';
import '../billing/billing_service.dart';
import 'services/play_billing_service.dart';
import 'services/play_purchase_recorder.dart';
import 'services/subscription_pricing.dart';

/// Paywall shown when a user's free trial has expired and they are not a
/// premium subscriber.
///
/// **Play compliance (critical):** the management affordance is branched on
/// the subscription's billing platform ([UserEntitlement.billingPlatform]):
///   * Google Play-billed users get a "Manage subscription" action that opens
///     Google Play's own subscriptions manager
///     (https://play.google.com/store/account/subscriptions) — NEVER a link
///     that steers to an external website checkout.
///   * PayFast (website) subscribers may be shown "Manage subscription on
///     website" — that is the only case where an external billing link is
///     policy-compliant.
///   * Everyone else (no active subscription) is shown the native Google Play
///     subscribe call-to-action.
class PaywallScreen extends StatefulWidget {
  final ThemeController theme;

  const PaywallScreen({super.key, required this.theme});

  /// The billing page hosted on the website (PayFast). Shown ONLY to
  /// PayFast-billed subscribers — never to a Play-billed user (Play policy).
  static const String websiteBillingUrl =
      'https://jagspoor.co.za/account/billing';

  /// Google Play's own subscriptions manager — the policy-compliant
  /// management surface for a Play-billed subscription. No login is required
  /// beyond the device's signed-in Google account, and it is reachable in one
  /// tap from this screen.
  static const String playSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions?package=za.co.jagspoor.app&sku=jagspoor_hunter_monthly';

  /// The literal fragment that must never appear for a Play-billed user.
  static const String websiteManageLabel = 'on website';

  /// Test seam: pre-seeds the entitlement the paywall branches on, so the
  /// Play-vs-PayFast management affordance can be asserted without a live
  /// Firebase read.
  @visibleForTesting
  static UserEntitlement? entitlementForTesting;

  /// Shown while the live Google Play catalog price has not resolved yet.
  static const String loadingPriceLabel = 'Loading price…';

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  /// Live Play catalog price — under Option A this is the FINAL VAT-inclusive
  /// charge the customer pays (the Play Console base plan carries the listed
  /// amount and 15% VAT is absorbed out of it). Derived from
  /// [PlayProduct.rawPrice] (see `SubscriptionVatPrice.fromInclusive`). Null
  /// until the catalog resolves.
  SubscriptionVatPrice? _price;

  /// The resolved Play catalog for the app's tiers. Held so the purchase flow
  /// can launch with the base-plan offer token resolved at catalog load.
  Map<SubscriptionTier, PlayProduct> _products = const {};

  /// True while the Play catalog query is in flight (after billing support is
  /// confirmed) — gates the SUBSCRIBE button so it can never launch before the
  /// base-plan offer token is known.
  bool _catalogLoading = false;

  /// v1.0.12 hotfix: the paywall is a first-class purchase surface. It listens
  /// to the Play purchase stream so a purchase made here is acknowledged
  /// immediately (the previous version had no listener at all, so a purchase
  /// started from the paywall was never acknowledged and Google auto-refunded
  /// it after 3 days).
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  /// True while a Google Play purchase is in the pending (delayed-payment)
  /// state — the user is shown a "payment pending" notice until the store
  /// confirms or cancels.
  bool _paymentPending = false;

  /// Google Play's view of the subscription, resolved from the `purchases`
  /// collection (the durable record of what the store actually charged for).
  ///
  /// The paywall treats `purchases` as a source of truth in ADDITION to the
  /// server-written `users/{uid}.subscriptionStatus` mirror, so a subscriber
  /// whose entitlement was never mirrored is never asked to pay twice.

  /// Whether Google Play already holds an active subscription for this
  /// account. Drives the "you are already subscribed" state, which replaces
  /// the purchase call-to-action so the user is not charged again while the
  /// server mirror catches up.
  bool _alreadySubscribed = false;

  /// True while the `purchases` collection check is in flight.
  bool _checkingPurchaseState = false;

  /// The current entitlement (server-authoritative), used to branch the
  /// management affordance on the billing platform (Play vs PayFast). Null
  /// until the one-shot read resolves.
  UserEntitlement? _entitlement;

  /// The billing platform that granted the current subscription — `'google_play'`
  /// / `'payfast'` / `null`. Resolved from the entitlement, with the `purchases`
  /// collection as a secondary Play signal (a durable Play transaction can only
  /// have come from Google Play).
  String? get _billingPlatform {
    final platform = _entitlement?.billingPlatform;
    if (platform != null) return platform;
    // A Play purchase row owned by the caller is definitive proof of a Play
    // billing relationship, even before the users/{uid} mirror resolves.
    if (_alreadySubscribed) return SubscriptionSource.googlePlay;
    return null;
  }

  /// Whether the active subscription is billed by Google Play. Play policy:
  /// route to Google Play's subscriptions manager, never to the website.
  bool get _isPlayBilled => _billingPlatform == SubscriptionSource.googlePlay;

  /// Whether the active subscription is billed via the PayFast website
  /// checkout (the only case where a website management link is compliant).
  bool get _isPayfastBilled =>
      _billingPlatform == SubscriptionSource.payfast;

  /// Whether an active paid subscription exists (either source) — gates the
  /// "manage" affordance vs the subscribe call-to-action.
  bool get _hasActiveSubscription =>
      _alreadySubscribed ||
      _isPlayBilled ||
      _isPayfastBilled ||
      (_entitlement?.isPremiumActive(DateTime.now()) ?? false);

  ThemeController get theme => widget.theme;

  /// Whether the current build charges through PayFast (web) instead of the
  /// native Google Play Billing flow. On the web there is no Play catalog, no
  /// Play purchase stream and no Play subscriptions manager — the PayFast
  /// hosted checkout is the purchase path.
  bool get _isWebBilling => BillingService.instance.usesPayFast;

  /// The PayFast plan id for the active tier (used by the web checkout).
  String get _payFastPlanId => BillingPlans.monthlyFor(_tier).planId;

  SubscriptionTier get _tier =>
      SubscriptionTier.fromAppRole(UserRoleProvider.instance.role);

  @override
  void initState() {
    super.initState();
    // The Play purchase stream + recorder are Android/iOS only. On the web
    // build the PayFast ITN webhook writes the entitlement, so there is no
    // Play stream to listen to.
    if (!_isWebBilling) {
      // Record any Google Play purchase (new or restored) onto `purchases`.
      // Idempotent, so it is safe to start from every subscription surface.
      PlayPurchaseRecorder.instance.startListening();
      _listenForPurchases();
      _checkPurchasesCollection();
      _loadPlayPrice();
    } else {
      _loadAdminPrice();
    }
    _loadEntitlement();
  }

  /// Web price: the admin control-plane amount (`admin_config/pricing`), since
  /// no Play catalog exists in the browser. Never hardcoded — until the doc
  /// resolves the paywall shows the neutral loading label.
  Future<void> _loadAdminPrice() async {
    try {
      final amount = await SubscriptionConfigService.instance
          .getFallbackPrice(_tier.key);
      if (!mounted) return;
      setState(() {
        _catalogLoading = false;
        _price = SubscriptionVatPrice.fromInclusive(amount);
      });
    } catch (e) {
      debugPrint('PaywallScreen.loadAdminPrice failed: $e');
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  /// One-shot read of the server-authoritative entitlement so the management
  /// affordance can branch on the billing platform (Play vs PayFast).
  ///
  /// Best-effort: a read failure (offline / no session) leaves the platform
  /// unknown, in which case the paywall shows the neutral subscribe
  /// call-to-action — never an external checkout link.
  Future<void> _loadEntitlement() async {
    final override = PaywallScreen.entitlementForTesting;
    if (override != null) {
      if (mounted) setState(() => _entitlement = override);
      return;
    }
    try {
      final entitlement = await EntitlementService.instance.getMyEntitlement();
      if (!mounted) return;
      setState(() => _entitlement = entitlement);
    } catch (e) {
      debugPrint('PaywallScreen.loadEntitlement failed: $e');
    }
  }

  /// Reads the `purchases` collection as the paywall's second source of truth.
  ///
  /// A purchase row owned by the caller with `status == 'active'` means Google
  /// Play has already charged for a subscription — so the paywall must show
  /// the "already subscribed" state and must NOT invite a second purchase,
  /// even when `users/{uid}.subscriptionStatus` has not been mirrored yet.
  /// Best-effort: a read failure (offline / rules / no session) leaves the
  /// normal purchase call-to-action in place.
  Future<void> _checkPurchasesCollection() async {
    if (mounted) setState(() => _checkingPurchaseState = true);
    try {
      final result = await PlayPurchaseRecorder.instance
          .reconcileEntitlementFromPurchases();
      if (!mounted) return;
      setState(() {
        _checkingPurchaseState = false;
        _alreadySubscribed = result.hasActivePurchase;
      });
    } catch (e) {
      debugPrint('PaywallScreen.checkPurchasesCollection failed: $e');
      if (mounted) setState(() => _checkingPurchaseState = false);
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  /// Acknowledges completed purchases IMMEDIATELY and drives server
  /// verification.
  ///
  /// Order matters: `completePurchase` (Google Play's acknowledge) is called
  /// FIRST, before the server round-trip, so the transaction is always
  /// acknowledged even if verification is slow, fails, or the app is killed.
  /// A verification failure is then surfaced for a retry rather than leaving
  /// the purchase unacknowledged (which is what triggers Google's 3-day
  /// auto-refund).
  void _listenForPurchases() {
    _purchaseSub = PlayBillingService.instance.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          final status = purchase.status;
          if (status == PurchaseStatus.purchased ||
              status == PurchaseStatus.restored) {
            // 1) Acknowledge immediately — never leave a transaction open.
            await PlayBillingService.instance.completePurchase(purchase);
            // 2) Durable, owner-scoped transaction record.
            await PlayPurchaseRecorder.instance.recordPurchase(
              productId: purchase.productID,
              purchaseToken:
                  purchase.verificationData.serverVerificationData,
            );
            // 3) Server-side verification (writes the authoritative
            //    entitlement). Best-effort; a failure is surfaced for retry.
            await _verifyPurchase(purchase);
          } else if (status == PurchaseStatus.pending) {
            if (mounted) setState(() => _paymentPending = true);
          } else if (status == PurchaseStatus.error) {
            if (mounted) {
              setState(() => _paymentPending = false);
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(
                    'Google Play purchase failed: '
                    '${purchase.error?.message ?? 'unknown error'}.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } else if (status == PurchaseStatus.canceled) {
            if (mounted) setState(() => _paymentPending = false);
          }
        }
      },
      onError: (Object e) =>
          debugPrint('PaywallScreen purchase stream error: $e'),
    );
  }

  /// Calls the `validateGooglePlayPurchase` Cloud Function and surfaces the
  /// outcome. Never throws.
  Future<void> _verifyPurchase(PurchaseDetails purchase) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final tier = SubscriptionTier.fromPlayProductId(purchase.productID);
    try {
      final result = await EntitlementService.instance
          .verifyGooglePlayPurchase(
        purchaseToken: purchase.verificationData.serverVerificationData,
        productId: tier.playProductId,
      );
      if (!mounted) return;
      setState(() => _paymentPending = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Subscription active — access unlocked.'
                : 'Purchase received, but verification is pending. '
                    'Please try again shortly.',
          ),
          backgroundColor: result.success ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('PaywallScreen.verifyPurchase failed: $e');
      if (!mounted) return;
      setState(() => _paymentPending = false);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Purchase received — verification pending. Pull to refresh in a '
            'moment.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Loads the live Google Play Billing catalog price for the active tier.
  ///
  /// Under Option A the Play Console base plan is configured with the FINAL
  /// VAT-inclusive charge (R34.99 / R299.99), so the catalog amount is shown
  /// verbatim as the primary price with the `Incl. 15% VAT` caption beneath it
  /// — it is NEVER grossed up (the previous `exVat * 1.15` treatment is what
  /// produced the incorrect R40.24 display). The amount is NEVER hardcoded:
  /// until the catalog resolves the paywall shows
  /// [PaywallScreen.loadingPriceLabel] rather than inventing a number.
  Future<void> _loadPlayPrice() async {
    // Query the Play catalog directly (no separate availability probe — the
    // catalog query is itself the availability check, and a host that cannot
    // reach the store simply leaves the price on the neutral loading label).
    // The loading state is engaged while the query is in flight so the
    // SUBSCRIBE button can never launch before the base-plan offer token is
    // known.
    if (mounted) setState(() => _catalogLoading = true);
    try {
      final products = await PlayBillingService.instance.loadProducts();
      if (!mounted) return;
      final product = products[_tier];
      setState(() {
        _products = products;
        _catalogLoading = false;
        if (product != null) {
          _price = SubscriptionVatPrice.fromInclusive(
            product.rawPrice,
            currencySymbol: product.currencySymbol,
          );
        }
      });
    } catch (e) {
      debugPrint('PaywallScreen.loadPlayPrice failed: $e');
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  /// The Play catalog entry for the active tier, or null when it has not
  /// loaded / is not configured in the Play Console.
  PlayProduct? get _activeProduct => _products[_tier];

  /// Whether the SUBSCRIBE button is enabled: held disabled while the catalog
  /// is loading, and — once loaded — until the active product carries the
  /// base-plan offer token Google Play Billing v5+ requires. When no catalog
  /// entry resolved (non-store host / product not configured) the button stays
  /// tappable so [_subscribeViaGooglePlay] can explain the reason.
  ///
  /// It is also held disabled while the `purchases` collection check is in
  /// flight, so the user can never be charged again in the window before the
  /// paywall knows Google Play already holds an active subscription.
  bool get _subscribeEnabled {
    if (_catalogLoading || _checkingPurchaseState) return false;
    final product = _activeProduct;
    if (product == null) return true;
    return product.isPurchasable;
  }

  /// Launches [url] in the platform's external app (browser / Play Store).
  /// Returns whether the launch succeeded; never throws.
  Future<bool> _launchExternal(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('PaywallScreen.launchExternal failed for $url: $e');
      return false;
    }
  }

  /// Opens Google Play's subscriptions manager — the policy-compliant
  /// management surface for a Play-billed subscription. One tap from this
  /// screen; the device's own Google account authorises it (no JagSpoor login
  /// step).
  Future<void> _openPlaySubscriptions(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final launched = await _launchExternal(PaywallScreen.playSubscriptionsUrl);
    if (!launched) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open Google Play. You can manage your subscription '
            'from the Play Store app under "Subscriptions".',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Opens the website billing page. Shown ONLY to PayFast-billed
  /// subscribers — never to a Play-billed user (Play policy).
  Future<void> _openWebsiteBilling(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final launched = await _launchExternal(PaywallScreen.websiteBillingUrl);
    if (!launched) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open the website. Please visit '
            '${PaywallScreen.websiteBillingUrl} in your browser.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Opens the PayFast site for a web subscriber to manage their recurring
  /// billing. Only reachable on the web build.
  Future<void> _openPayfastDashboard(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final launched =
        await _launchExternal(BillingService.payfastDashboardUrl);
    if (!launched) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open PayFast. Please visit '
            '${BillingService.payfastDashboardUrl} in your browser.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _subscribeViaGooglePlay(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final product = _activeProduct;
    if (_catalogLoading) return; // catalog still loading — button is disabled
    if (product != null && !product.isPurchasable) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'This subscription is not available yet — the Play Console base '
            'plan is not active. Please try again later or contact support.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      final launched = product != null
          ? await PlayBillingService.instance.buyProduct(product)
          : await PlayBillingService.instance.purchaseProduct(_tier);
      if (!launched && messenger != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to start the Google Play purchase — please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      // On success the Play purchase stream flows to the app's purchase
      // listener, which calls the server-side validateGooglePlayPurchase.
    } catch (e) {
      debugPrint('PaywallScreen.subscribe failed: $e');
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Subscription purchase failed. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Web checkout: request the server-signed PayFast form and post it to the
  /// hosted checkout. The merchant key never reaches the browser — the
  /// `createPayFastPayment` Cloud Function signs the payload server-side and
  /// the `payfastNotify` ITN webhook writes the authoritative entitlement.
  Future<void> _subscribeViaPayFast(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _paymentPending = false;
      _catalogLoading = true;
    });
    try {
      final result = await BillingService.instance.payWithPlanId(
        role: _tier.key,
        planId: _payFastPlanId,
      );
      if (!mounted) return;
      setState(() => _catalogLoading = false);
      if (!result.launched) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              result.message ??
                  'Unable to start the PayFast checkout. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Opening the secure PayFast checkout — complete the payment to '
            'activate your subscription.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('PaywallScreen.subscribeViaPayFast failed: $e');
      if (mounted) setState(() => _catalogLoading = false);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Subscription purchase failed. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = this.theme;
    final price = _price;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        title: const Text(
          'Premium Access Required',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: WebLayout.responsive(
          context: context,
          maxWidth: 800,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.accentColor, width: 1.4),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 64,
                      color: theme.accentColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _hasActiveSubscription
                          ? 'Your subscription is active'
                          : 'Your free trial has ended',
                      key: const ValueKey('paywallHeadline'),
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hasActiveSubscription
                          ? 'Manage your billing below. Your subscription is '
                              'handled by the store that billed it.'
                          : 'Subscribe to continue using the full hunting '
                              'toolkit, package marketplace, ballistics '
                              'calculator and all premium features.',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    // The VAT-inclusive price the customer is charged. Under
                    // Option A the Play Console base plan already carries the
                    // final listed amount, so it is shown verbatim (never
                    // grossed up) with the `Incl. 15% VAT` caption beneath it.
                    // Never a hardcoded amount: until the catalog resolves the
                    // neutral loading label is shown instead.
                    Text(
                      price?.primaryLabel ?? PaywallScreen.loadingPriceLabel,
                      key: const ValueKey('paywallPriceLabel'),
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price?.vatNote ?? 'per month · includes VAT',
                      key: const ValueKey('paywallVatNote'),
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (_alreadySubscribed) ...[
                // `purchases` says Google Play already holds an active
                // subscription for this account — never invite a second
                // purchase while the server mirror catches up.
                Container(
                  key: const ValueKey('paywallAlreadySubscribedBanner'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded,
                          color: Colors.green, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You already have an active Google Play '
                          'subscription — restoring your access now. No need '
                          'to subscribe again; manage it below.',
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_paymentPending) ...[
                Container(
                  key: const ValueKey('paywallPendingBanner'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Payment pending — your subscription will activate '
                          'once Google Play confirms the payment.',
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_isWebBilling && _hasActiveSubscription) ...[
                // WEB (PayFast) subscriber with an active subscription — the
                // single case where an external billing link is compliant.
                // (A PayFast-billed subscriber on any platform is also routed
                // here; a Play-billed subscriber is never steered off-store.)
                OutlinedButton.icon(
                  key: const ValueKey('paywallManageWebsiteButton'),
                  onPressed: () => _openPayfastDashboard(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.accentColor,
                    side: BorderSide(color: theme.accentColor, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.language_rounded),
                  label: const Text(
                    'Manage subscription on PayFast',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ] else if (!_isWebBilling &&
                  (_isPlayBilled ||
                      _alreadySubscribed ||
                      // An active subscriber whose platform is unknown (no
                      // mirror yet) is routed to the Play manager — never the
                      // website link. This is the compliance-safe default: a
                      // Play user is never steered off-store.
                      (!_isPayfastBilled && _hasActiveSubscription))) ...[
                // COMPLIANT for Google Play. A Play-billed subscriber is
                // routed to Google Play's own subscriptions manager — there is
                // deliberately NO external/website checkout affordance here
                // (Play policy forbids steering Play users off-store).
                OutlinedButton.icon(
                  key: const ValueKey('paywallManagePlayButton'),
                  onPressed: () => _openPlaySubscriptions(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.accentColor,
                    side: BorderSide(color: theme.accentColor, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: const Text(
                    'Manage subscription',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Subscription billed by Google Play',
                  key: const ValueKey('paywallPlayBillingNote'),
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else if (_isPayfastBilled) ...[
                // OK for web (PayFast) subscribers only — the single case
                // where an external billing link is policy-compliant.
                OutlinedButton.icon(
                  key: const ValueKey('paywallManageWebsiteButton'),
                  onPressed: () => _openWebsiteBilling(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.accentColor,
                    side: BorderSide(color: theme.accentColor, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.language_rounded),
                  label: const Text(
                    'Manage subscription on website',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ] else
                // No active subscription — the platform-appropriate subscribe
                // call-to-action: PayFast hosted checkout on the web, Google
                // Play Billing on Android/iOS.
                FilledButton.icon(
                  key: const ValueKey('paywallPlaySubscribeButton'),
                  onPressed: (_paymentPending || !_subscribeEnabled)
                      ? null
                      : () => _isWebBilling
                          ? _subscribeViaPayFast(context)
                          : _subscribeViaGooglePlay(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        theme.subtitleColor.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _catalogLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isWebBilling
                              ? Icons.lock_outline_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                  label: Text(
                    _catalogLoading
                        ? (_isWebBilling
                            ? 'OPENING PAYFAST…'
                            : 'LOADING GOOGLE PLAY…')
                        : (_isWebBilling
                            ? 'SUBSCRIBE VIA PAYFAST'
                            : 'SUBSCRIBE VIA GOOGLE PLAY'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// A lightweight trial banner widget. Set to `SizedBox.shrink` when there is
/// no active trial.
class TrialBanner extends StatelessWidget {
  final ThemeController theme;
  final int daysRemaining;
  final DateTime? trialEnd;

  const TrialBanner({
    super.key,
    required this.theme,
    required this.daysRemaining,
    this.trialEnd,
  });

  bool get _hasActiveTrial => daysRemaining > 0;

  @override
  Widget build(BuildContext context) {
    if (!_hasActiveTrial) return const SizedBox.shrink();
    final days = daysRemaining;
    return Container(
      key: const ValueKey('trialBanner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accentColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              days == 1
                  ? 'Trial ends tomorrow.'
                  : 'Trial: $days days left',
              key: const ValueKey('trialBannerText'),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}