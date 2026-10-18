import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/web_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/copyright_footer.dart';
import '../../core/widgets/payfast_secure_footer.dart';
import '../../services/entitlement_service.dart';
import '../admin/services/subscription_config_service.dart';
import '../auth/services/user_role_provider.dart';
import '../billing/billing_plans.dart';
import '../billing/billing_service.dart';
import '../billing/payfast_buttons.dart';
import 'services/play_billing_service.dart';
import 'services/play_purchase_recorder.dart';
import 'services/subscription_pricing.dart';
import 'services/subscription_status_service.dart';

/// Subscription checkout screen.
///
/// Shows the user's trial / subscription status, the active tier's price
/// (always resolved dynamically — the live Google Play catalog label when
/// available, else the VAT-inclusive `admin_config/pricing` amount; never a
/// hardcoded literal), a promo-code input that adjusts the displayed checkout
/// total, and a primary action that invokes the native **Google Play Billing**
/// subscription flow.
///
/// Pricing model (Option A): the listed price is the FINAL charge and is
/// **VAT inclusive** (R34.99 hunter / R299.99 outfitter) — 15% SA VAT is
/// absorbed out of it, not added on top.
///
/// Recurring billing is handled entirely by Google Play (Play Console
/// subscription products `jagspoor_hunter_monthly` /
/// `jagspoor_outfitter_monthly`); cancellation and payment management happen
/// inside the Play Store subscriptions center, which is the Play Payments
/// policy-compliant path.
class SubscriptionScreen extends StatefulWidget {
  final ThemeController theme;

  /// The billing tier. When omitted, it is resolved from the cached
  /// [UserRoleProvider] role (outfitter -> outfitter tier, everything else
  /// -> hunter tier).
  final SubscriptionTier? tier;

  const SubscriptionScreen({super.key, required this.theme, this.tier});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final TextEditingController _promoController = TextEditingController();
  PromoCodeAdjustment? _appliedPromo;
  String? _promoError;
  bool _isLaunching = false;
  bool _isOpeningPlayStore = false;
  bool _isRestoring = false;
  bool _billingSupported = true;

  /// True while a Google Play purchase is in the pending (delayed-payment)
  /// state — the subscribe button is disabled and a "payment pending" notice
  /// is shown until the store confirms or cancels (v1.0.12 hotfix).
  bool _paymentPending = false;
  Map<SubscriptionTier, PlayProduct> _products = const {};

  /// True while the Play catalog query is in flight (after billing support is
  /// confirmed). Drives the loading state so the SUBSCRIBE button is never
  /// tapped before the base-plan offer token has been resolved.
  bool _catalogLoading = false;

  /// Admin-controlled fallback price (from `admin_config/pricing`), resolved
  /// when the live Play catalog has not loaded. Null until the async load
  /// completes; the hard-coded last resort applies until then.
  double? _adminFallbackPrice;

  /// The billing cycle the user has selected in the TIER PRICING section
  /// (Monthly by default). Drives the order summary + the highlighted PayFast
  /// plan button.
  BillingCycle _selectedCycle = BillingCycle.monthly;

  /// The reactive subscription stream, cached ONCE for the screen's lifetime.
  ///
  /// Caching is load-bearing: `watchMySubscription()` builds a FRESH Firestore
  /// `.snapshots()` subscription on every call, so re-creating it inside
  /// `build()` (as the screen previously did) tears the subscription down and
  /// re-subscribes on every rebuild. Each rebuild then resets the
  /// `StreamBuilder` to `ConnectionState.waiting` with no data, so an ACTIVE
  /// subscriber briefly renders the empty "NO ACTIVE SUBSCRIPTION" state
  /// (the plan selector) before the next snapshot lands — the reported
  /// "stays on / flashes back to the selector" defect. Holding a single
  /// cached stream keeps the resolved subscription stable across rebuilds.
  /// Mirrors the documented fix for the Custom Package Builder.
  late Stream<UserSubscription> _subscriptionStream;

  /// The last resolved subscription, seeded by a one-shot read in `initState`
  /// and kept current by every stream emission. Used as the `StreamBuilder`
  /// fallback so the FIRST frame after entry already shows the active banner +
  /// plan cards instead of the empty state — no flash of "NO ACTIVE
  /// SUBSCRIPTION" for a subscriber whose `users/{uid}` doc is already active.
  UserSubscription _resolvedSubscription = const UserSubscription();

  SubscriptionTier get _tier =>
      widget.tier ??
      SubscriptionTier.fromAppRole(UserRoleProvider.instance.role);

  /// The Monthly plan for the active tier (client mirror of the server
  /// catalog — `hunter_monthly` / `outfitter_monthly`).
  BillingPlan get _monthlyPlan => BillingPlans.monthlyFor(_tier);

  /// The Yearly plan for the active tier (`hunter_yearly` /
  /// `outfitter_yearly`).
  BillingPlan get _yearlyPlan =>
      BillingPlans.forTier(_tier).firstWhere((p) => p.isYearly);

  /// The plan the user has selected (drives the order summary + checkout).
  BillingPlan get _selectedPlan =>
      _selectedCycle == BillingCycle.yearly ? _yearlyPlan : _monthlyPlan;

  /// The recurring monthly amount for the current tier, **including VAT**.
  ///
  /// Precedence: the LIVE Google Play Billing catalog price (`rawPrice` from
  /// [PlayBillingService.loadProducts], the authoritative charge — under
  /// Option A the base plan already carries the final VAT-inclusive amount) →
  /// the admin-controlled `admin_config/pricing` amount (also a VAT-inclusive
  /// end-user amount) → the hard-coded last resort. This keeps the checkout
  /// summary, promo calculations, and the tier-card copy consistent with the
  /// Play Console catalog while the Admin Portal remains the control plane
  /// when the catalog is unavailable.
  double get _baseAmount =>
      _playInclVat ??
      _adminFallbackPrice ??
      (_tier == SubscriptionTier.outfitter
          ? outfitterMonthlyPriceZAR
          : hunterMonthlyPriceZAR);

  /// The live Play catalog amount — under Option A this IS the VAT-inclusive
  /// amount the customer is charged (the base plan carries the final listed
  /// price), or null when no Play product has loaded. It is never grossed up;
  /// the previous `exVat * 1.15` treatment is what produced R40.24 for a
  /// R34.99 base plan.
  double? get _playInclVat {
    final product = _products[_tier];
    if (product == null) return null;
    return SubscriptionVatPrice.fromInclusive(
      product.rawPrice,
      currencySymbol: product.currencySymbol,
    ).inclVat;
  }

  /// The live Play catalog amount resolved to its VAT breakdown, or null when
  /// no product has loaded (the control-plane amount is then shown instead).
  SubscriptionVatPrice? get _playVatPrice {
    final product = _products[_tier];
    if (product == null) return null;
    return SubscriptionVatPrice.fromInclusive(
      product.rawPrice,
      currencySymbol: product.currencySymbol,
    );
  }

  /// Whether the live Play catalog price diverges from the admin-configured
  /// price — the Admin Portal WARNING basis, surfaced here so a subscriber sees
  /// the same mismatch the operator does. Under Option A both figures are the
  /// final VAT-inclusive charge, so they are compared directly via the shared
  /// [PlayPriceReconciliation].
  bool get _hasPriceDivergence {
    final product = _products[_tier];
    final admin = _adminFallbackPrice;
    if (product == null || admin == null || admin <= 0) return false;
    return !PlayPriceReconciliation.compare(
      playExVat: product.rawPrice,
      adminInclVat: admin,
      currencySymbol: product.currencySymbol,
    ).matches;
  }

  /// The Monthly plan amount, VAT inclusive.
  ///
  /// Prefers the live Play catalog / admin control-plane amount ([_baseAmount])
  /// so the operator stays the control plane when the catalog is unavailable.
  double get _monthlyAmount => _baseAmount;

  /// The Yearly plan amount, VAT inclusive.
  ///
  /// Taken from the client plan catalog (the mirror of the server
  /// `PAYFAST_PLAN_CATALOG`): R349.99 (hunter) / R2999.99 (outfitter). The
  /// server is the authority for the actual charge; this is only the display
  /// figure.
  double get _yearlyAmount => _yearlyPlan.amountZar;

  /// The amount for the currently selected billing cycle (VAT inclusive).
  double get _selectedBaseAmount =>
      _selectedCycle == BillingCycle.yearly ? _yearlyAmount : _monthlyAmount;

  double get _checkoutAmount => _appliedPromo == null
      ? _selectedBaseAmount
      : _appliedPromo!.apply(_selectedBaseAmount);

  /// Selects a billing cycle and re-renders the tier cards + order summary.
  void _selectCycle(BillingCycle cycle) {
    if (_selectedCycle == cycle) return;
    setState(() => _selectedCycle = cycle);
  }

  @override
  void initState() {
    super.initState();
    // Cache the subscription stream ONCE. Re-creating it in `build()` would
    // re-subscribe on every rebuild and flicker the screen back to the empty
    // selector state for an active subscriber (see the field doc).
    _subscriptionStream =
        SubscriptionStatusService.instance.watchMySubscription();
    _seedSubscription();
    _initBilling();
    // The Play purchase stream + recorder are Android/iOS only — the web build
    // charges through PayFast (whose ITN webhook writes the entitlement).
    if (!_isWebBilling) {
      _listenForPurchases();
      // Persist any purchase (new or restored) onto users/{uid} + `purchases`.
      PlayPurchaseRecorder.instance.startListening();
    }
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  /// One-shot read of the subscription state so the first frame renders the
  /// active banner + plan cards immediately.
  ///
  /// The reactive stream delivers its first Firestore snapshot asynchronously,
  /// so without this seed an active subscriber would see the empty
  /// "NO ACTIVE SUBSCRIPTION" state for a frame. Best-effort: a read failure
  /// (offline / no session) leaves the empty default in place and the stream
  /// still delivers the real value a moment later.
  Future<void> _seedSubscription() async {
    try {
      final sub = await SubscriptionStatusService.instance.getMySubscription();
      if (!mounted) return;
      setState(() => _resolvedSubscription = sub);
    } catch (e) {
      debugPrint('SubscriptionScreen: subscription seed failed: $e');
    }
  }

  /// Resolves billing availability + the Play catalog so the UI can show the
  /// real Play Console price and surface a graceful "billing unavailable"
  /// state.
  Future<void> _initBilling() async {
    // On the WEB build billing runs through PayFast, so the Google Play
    // catalog query is skipped entirely (the plugin has no web implementation
    // and the browser has no Play products). Only the admin control-plane
    // price is resolved, for display consistency.
    if (_isWebBilling) {
      double? adminFallback;
      try {
        adminFallback = await SubscriptionConfigService.instance
            .getFallbackPrice(_tier.key);
      } catch (e) {
        debugPrint('SubscriptionScreen: admin pricing load failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _billingSupported = true;
        _catalogLoading = false;
        _adminFallbackPrice = adminFallback;
      });
      return;
    }
    // Only touch the Play Billing plugin when the host actually supports it.
    // On a non-store host (emulator, test host) `isAvailable` is false — or
    // the plugin call never returns — so the catalog is left unresolved and
    // the SUBSCRIBE affordance stays in its normal state (the price falls back
    // to the admin control plane). The loading state is engaged ONLY once
    // billing support has been confirmed, so the UI never hangs on a query
    // that cannot complete.
    bool supported;
    try {
      supported = await PlayBillingService.instance.isBillingSupported();
    } catch (e) {
      debugPrint('SubscriptionScreen: billing availability check failed: $e');
      supported = false;
    }
    Map<SubscriptionTier, PlayProduct> products = const {};
    if (supported) {
      if (mounted) setState(() => _catalogLoading = true);
      try {
        products = await PlayBillingService.instance.loadProducts();
      } catch (e) {
        debugPrint('SubscriptionScreen: loadProducts failed: $e');
      }
    }
    // Resolve the admin-controlled fallback price (`admin_config/pricing`).
    // Best-effort — an unreadable doc leaves the hard-coded last resort in
    // place. `_baseAmount` still prefers the live Play catalog price.
    double? adminFallback;
    try {
      adminFallback = await SubscriptionConfigService.instance
          .getFallbackPrice(_tier.key);
    } catch (e) {
      debugPrint('SubscriptionScreen: admin pricing load failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _billingSupported = supported;
      _products = products;
      _catalogLoading = false;
      _adminFallbackPrice = adminFallback;
    });
  }

  /// The Play catalog entry for the active tier, or null when it has not
  /// loaded / is not configured in the Play Console.
  PlayProduct? get _activeProduct => _products[_tier];

  /// Whether the SUBSCRIBE button is enabled.
  ///
  /// Held disabled while the Play catalog is loading, and — once loaded —
  /// until the active product carries the base-plan **offer token** Google
  /// Play Billing v5+ requires (without it `launchBillingFlow` fails with
  /// `INVALID_OFFER_TOKEN`, so the button must not launch). When NO catalog
  /// entry resolved at all (a non-store host, or a product not yet configured
  /// in the Play Console) the affordance stays tappable so [_subscribe] can
  /// explain the reason instead of leaving a dead button.
  bool get _subscribeEnabled {
    if (_catalogLoading) return false;
    final product = _activeProduct;
    if (product == null) return true;
    return product.isPurchasable;
  }

  String? get _userId {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  void _applyPromo() {
    final raw = _promoController.text;
    if (raw.trim().isEmpty) {
      setState(() {
        _appliedPromo = null;
        _promoError = null;
      });
      return;
    }
    final adjustment = PromoCodeEngine.validate(raw);
    setState(() {
      _appliedPromo = adjustment;
      _promoError = adjustment == null ? 'Invalid promo code' : null;
    });
  }

  /// Whether this build charges through PayFast (web) rather than the native
  /// Google Play Billing flow.
  ///
  /// True when the platform is the web build ([BillingService.usesPayFast],
  /// which is `kIsWeb`) OR when the subscription on file was itself billed
  /// through PayFast (`sub.isPayfastBilled`). Either way the Play catalog /
  /// purchase stream / restore affordances are meaningless and the PayFast
  /// checkout (or the PayFast management link) is the correct path.
  bool _isWebBillingFor(UserSubscription sub) =>
      BillingService.instance.usesPayFast || sub.isPayfastBilled;

  /// Platform-only check (no subscription context) — used in `initState`
  /// before the subscription doc has resolved.
  bool get _isWebBilling => BillingService.instance.usesPayFast;

  /// Launches the platform-appropriate subscription checkout.
  ///
  /// * **Web** -> the PayFast hosted checkout. The signed form is built by the
  ///   `createPayFastPayment` Cloud Function (the merchant key never reaches
  ///   the browser) and posted in the current tab; the `payfastNotify` ITN
  ///   webhook then writes the authoritative entitlement.
  /// * **Android / iOS** -> the native Google Play Billing flow (Play policy
  ///   requires Play Billing for in-app digital goods).
  Future<void> _subscribe() async {
    if (_isLaunching) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uid = _userId;
    if (uid == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Please sign in to subscribe.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_isWebBilling) {
      await _subscribeViaPayFast(messenger);
      return;
    }
    if (!_billingSupported) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Google Play Billing is unavailable on this device. Please try again later.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    // The base-plan offer token must be resolved before launching. It is
    // missing when the product has no ACTIVE base plan in the Play Console —
    // surface that (instead of the opaque INVALID_OFFER_TOKEN platform error).
    final product = _activeProduct;
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
    setState(() => _isLaunching = true);
    try {
      // Prefer the already-loaded product (its offer token was resolved at
      // catalog load); fall back to the by-tier lookup when it is absent.
      final launched = product != null
          ? await PlayBillingService.instance.buyProduct(product)
          : await PlayBillingService.instance.purchaseProduct(_tier);
      if (!mounted) return;
      if (!launched) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to start the Google Play purchase — the subscription '
              'product may not be configured yet. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      // When launched, the Play billing sheet is presented; the purchase
      // stream will deliver the outcome.
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Subscription purchase failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  /// Web checkout: request the server-signed PayFast form and post it.
  ///
  /// The entitlement is written by the `payfastNotify` ITN webhook (server
  /// side) — the client only starts the checkout. The signed form carries the
  /// public `merchant_id` + the MD5 signature; the merchant KEY and passphrase
  /// stay in Secret Manager.
  Future<void> _subscribeViaPayFast(ScaffoldMessengerState? messenger) async {
    setState(() => _isLaunching = true);
    try {
      // The plan matches the billing cycle selected in TIER PRICING
      // (hunter_monthly / hunter_yearly / outfitter_monthly /
      // outfitter_yearly) — the server resolves the authoritative amount.
      final plan = _selectedPlan;
      final result = await BillingService.instance.pay(
        role: _tier.key,
        plan: plan,
      );
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  /// Listens to the Play Billing purchase stream.
  ///
  /// **v1.0.12 hotfix — acknowledge first.** For a completed purchase the
  /// transaction is acknowledged (`completePurchase`) IMMEDIATELY, before the
  /// server verification round-trip, so it can never be left unacknowledged
  /// (which is what makes Google auto-refund after 3 days). Only after the
  /// acknowledgement is the purchase recorded + verified server-side.
  ///
  /// The entitlement itself is written by the `validateGooglePlayPurchase`
  /// Cloud Function — the app no longer mirrors it onto `users/{uid}` (those
  /// fields are frozen in `firestore.rules`). `pending` purchases (delayed
  /// payment) show a pending notice; `error` / `canceled` clear it.
  void _listenForPurchases() {
    PlayBillingService.instance.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          final tier = SubscriptionTier.fromPlayProductId(purchase.productID);
          final token = purchase.verificationData.serverVerificationData;
          // 1) Acknowledge IMMEDIATELY — never leave a transaction open.
          await PlayBillingService.instance.completePurchase(purchase);
          // 2) Durable, owner-scoped transaction record.
          await PlayPurchaseRecorder.instance.recordPurchase(
            productId: purchase.productID,
            purchaseToken: token,
          );
          // 3) Server-side verification (writes the authoritative entitlement).
          try {
            final result = await EntitlementService.instance
                .verifyGooglePlayPurchase(
              purchaseToken: token,
              productId: tier.playProductId,
            );
            if (!mounted) continue;
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (result.success) {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    'Subscription active — ${tier == SubscriptionTier.outfitter ? 'Outfitter' : 'Hunter'} '
                    'tier unlocked via Google Play.',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 5),
                ),
              );
            } else {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    'Purchase received, but server verification is pending. '
                    'Please try again shortly.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } catch (e) {
            debugPrint('EntitlementService.verifyGooglePlayPurchase failed: $e');
            if (mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Purchase received — verification pending. Pull to refresh '
                    'in a moment.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } else if (purchase.status == PurchaseStatus.pending) {
          // Delayed-payment: the store confirms/cancels later. Show a pending
          // notice and disable the subscribe button meanwhile.
          if (mounted) setState(() => _paymentPending = true);
        } else if (purchase.status == PurchaseStatus.error) {
          // `itemAlreadyOwned` is NOT a failure — the user already holds the
          // subscription. `PlayPurchaseRecorder` (listening on the same
          // stream) restores the existing purchase and grants the entitlement,
          // so this branch only clears the pending state and reports the
          // recovery instead of a purchase error.
          if (PlayBillingErrors.isItemAlreadyOwned(purchase.error)) {
            debugPrint(
              'Play purchase: subscription already owned — restoring '
              '(${purchase.productID}).',
            );
            if (mounted) setState(() => _paymentPending = false);
          } else {
            debugPrint('Play purchase error: ${purchase.error}');
            if (mounted) setState(() => _paymentPending = false);
          }
        } else if (purchase.status == PurchaseStatus.canceled) {
          if (mounted) setState(() => _paymentPending = false);
        }
      }
    });
  }

  /// Opens the Google Play Store subscriptions center so the user can manage
  /// / pause / cancel their recurring billing (the policy-compliant path for
  /// Play-billed subscriptions).
  Future<void> _openPlaySubscriptionCenter() async {
    if (_isOpeningPlayStore) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isOpeningPlayStore = true);
    final url = PlayBillingService.instance.subscriptionCenterUrlFor(_tier);
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open Google Play. You can manage your subscription '
              'from the Play Store app.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Unable to open Google Play: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningPlayStore = false);
    }
  }

  /// Opens the website billing page. Shown ONLY to PayFast (website)
  /// subscribers — never to a Play-billed user (Play policy).
  Future<void> _openWebsiteBilling() async {
    if (_isOpeningPlayStore) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isOpeningPlayStore = true);
    try {
      final opened = await launchUrl(
        Uri.parse(PlayBillingService.websiteBillingUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Unable to open the website. Please visit '
              '${PlayBillingService.websiteBillingUrl} in your browser.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Unable to open the website: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningPlayStore = false);
    }
  }

  /// Opens the PayFast site so a web subscriber can manage their recurring
  /// billing. Shown ONLY on the web build (and only to a subscriber) — never
  /// to a Play-billed user (Play policy).
  Future<void> _openPayfastDashboard() async {
    if (_isOpeningPlayStore) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isOpeningPlayStore = true);
    try {
      final opened = await launchUrl(
        Uri.parse(BillingService.payfastDashboardUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
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
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Unable to open PayFast: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningPlayStore = false);
    }
  }

  /// Shows a confirmation dialog explaining that cancellation is handled in
  /// Google Play. Returns `true` when the user chooses to open the Play
  /// subscription center.
  Future<bool> _confirmOpenPlaySubscriptions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Manage Subscription'),
        content: const Text(
          'Your subscription is billed and managed by Google Play. To pause '
          'or cancel it, you will be taken to your Google Play subscriptions '
          'page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('KEEP SUBSCRIPTION'),
          ),
          FilledButton(
            key: const ValueKey('confirmCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('OPEN GOOGLE PLAY'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// The "cancel" action for Play-billed subscriptions: routes the user to
  /// Google Play's subscription management page (Play owns the recurring-
  /// billing lifecycle).
  Future<void> _cancelSubscription() async {
    if (_isOpeningPlayStore) return;
    final confirmed = await _confirmOpenPlaySubscriptions();
    if (!mounted || !confirmed) return;
    await _openPlaySubscriptionCenter();
  }

  /// Restores prior Google Play purchases (required for Play policy). Queries
  /// the store for existing subscriptions; any restored purchase arrives on
  /// [PlayBillingService.purchaseStream], which the screen already mirrors to
  /// the server-authoritative entitlement via [EntitlementService].
  Future<void> _restorePurchases() async {
    if (_isRestoring) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isRestoring = true);
    try {
      await PlayBillingService.instance.restorePurchases();
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Checking Google Play for prior purchases — any restored '
            'subscription will be applied shortly.',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Unable to restore purchases: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        title: const Text(
          'Subscription',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<UserSubscription>(
          // The cached stream — NEVER re-created here (see [_subscriptionStream]).
          stream: _subscriptionStream,
          builder: (context, snapshot) {
            // Fall back to the last resolved subscription (seeded by the
            // one-shot read) rather than the empty default, so a rebuild — or
            // the first frame before the stream's initial snapshot — never
            // flickers an active subscriber back to the empty selector state.
            final subscription = snapshot.data ?? _resolvedSubscription;
            // Keep the seed current with every emission so a later rebuild
            // (before the stream re-emits) uses the freshest value.
            _resolvedSubscription = subscription;
            // Responsive container: on a wide browser window the checkout is
            // centred at 800px (narrower than the 1280px dashboards) so the
            // tier cards / promo field / price breakdown stay a comfortable
            // reading width instead of stretching edge-to-edge. On a
            // mobile-width viewport the child is returned unchanged.
            return LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop =
                    WebLayout.isDesktopWidth(constraints.maxWidth);
                return WebLayout.responsive(
                  context: context,
                  maxWidth: 800,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 24 : 20,
                      12,
                      isDesktop ? 24 : 20,
                      24,
                    ),
                    children: [
                      _buildStatusBanner(theme, subscription),
                      if (_paymentPending) ...[
                        const SizedBox(height: 12),
                        _buildPendingBanner(theme),
                      ],
                      const SizedBox(height: 20),
                      _buildTierCards(theme, subscription),
                      const SizedBox(height: 20),
                      _buildPromoSection(theme),
                      const SizedBox(height: 20),
                      _buildTotalCard(theme),
                      const SizedBox(height: 24),
                      _buildSubscribeButton(theme, subscription),
                      // Web (PayFast) checkout: the two explicit plan buttons
                      // for the active role (Monthly + Yearly). Shown whenever
                      // the user is NOT already an active subscriber — a live
                      // free trial still sees them so it can convert to paid;
                      // an active subscriber sees the PayFast manage action
                      // instead (the Play manager affordance is never rendered
                      // in a browser).
                      if (_isWebBillingFor(subscription) &&
                          !subscription.isActive) ...[
                        const SizedBox(height: 20),
                        PayFastHunterOutfitterButtons(
                          theme: theme,
                          tier: _tier,
                          selectedCycle: _selectedCycle,
                          onPlanSelected: (plan) =>
                              _selectCycle(plan.cycle),
                        ),
                      ],
                      // The Play "Restore Purchases" affordance is a Google
                      // Play Billing requirement — it has no meaning on the
                      // web build (the PayFast entitlement is server-written
                      // by the ITN webhook), so it is hidden there.
                      if (!_isWebBillingFor(subscription)) ...[
                        const SizedBox(height: 12),
                        _buildRestoreButton(theme),
                      ],
                      if (_hasPriceDivergence) ...[
                        const SizedBox(height: 16),
                        _buildDivergenceNotice(theme),
                      ],
                      // PayFast trust footer — shown wherever PayFast is the
                      // payment path for this view: ALWAYS on the web build
                      // (the browser charges through PayFast) and on a native
                      // build for a PayFast (website) subscription. It is
                      // deliberately NOT rendered on a native Google Play
                      // checkout — advertising a third-party payment provider
                      // on a Play-billed screen would steer Play users
                      // off-store, which the Play compliance contract forbids.
                      // Sits below the plan cards, so it is visible on the
                      // Hunter AND Outfitter, Monthly AND Yearly views.
                      if (_isWebBillingFor(subscription))
                        const PayFastSecureFooter(),
                      const CopyrightFooter(),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusBanner(ThemeController theme, UserSubscription sub) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String detail;
    if (sub.isActive) {
      bg = Colors.green.shade700;
      fg = Colors.white;
      icon = Icons.verified_rounded;
      title = 'SUBSCRIPTION ACTIVE';
      detail = sub.renewalDate == null
          ? 'Your ${sub.tier?.key ?? ''} subscription is active.'
          : 'Your ${sub.tier?.key ?? ''} subscription renews on ${_fmtDate(sub.renewalDate!)}.';
    } else if (sub.isInTrial) {
      bg = theme.accentColor;
      fg = Colors.white;
      icon = Icons.hourglass_top_rounded;
      final remaining = sub.trialDaysRemaining(DateTime.now());
      title = 'FREE TRIAL ACTIVE';
      detail = remaining > 0
          ? '$remaining day${remaining == 1 ? '' : 's'} left of your 30-day free trial.'
          : 'Your 30-day free trial ends today.';
    } else if (sub.status == SubscriptionStatus.cancelled) {
      bg = Colors.red.shade700;
      fg = Colors.white;
      icon = Icons.cancel_outlined;
      title = 'SUBSCRIPTION CANCELLED';
      detail = 'Re-subscribe below to restore full access.';
    } else {
      bg = theme.cardColor;
      fg = theme.textColor;
      icon = Icons.workspace_premium_rounded;
      title = 'NO ACTIVE SUBSCRIPTION';
      detail = 'Start your 30-day free trial — no charge until day 31.';
    }
    return Container(
      key: const ValueKey('subscriptionStatusBanner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(detail, style: TextStyle(color: fg, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hunter-tier feature checklist (comprehensive).
  static const List<String> _hunterPerks = [
    'Full Hunter Toolkit & Ballistics Calculator',
    'Weather, Wind & Solunar Tracker',
    'SA Game Guide & Field Estimates',
    'Digital Firearm Safe & Ammunition Manager',
    'Package Marketplace & Custom Package Builder',
    'Digital Trophy Room & Sighting Logger',
    'Off-Grid Topographic Maps & Spoor Identifier',
    'SAPS License Application Tracker',
  ];

  /// Outfitter-tier feature checklist (comprehensive — outfitter / farm
  /// manager business & lodge management features only).
  static const List<String> _outfitterPerks = [
    'Farm Control Panel & Manager Assignments',
    'Custom Farm Species Price List Management',
    'Hunting Package Publishing & Booking Request Management',
    'Slaughterhouse & Carcass Weight Matrix',
    'Off-Grid Mesh Sync & Team Radar',
    'Business Intelligence & Revenue Analytics',
  ];

  /// "Payment pending" notice shown while a delayed-payment Play purchase is
  /// awaiting confirmation (v1.0.12 hotfix). The subscribe button is disabled
  /// meanwhile so the user cannot start a duplicate purchase.
  Widget _buildPendingBanner(ThemeController theme) {
    return Container(
      key: const ValueKey('subscriptionPendingBanner'),
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
              'Payment pending — your subscription will activate once Google '
              'Play confirms the payment.',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the active mode's tier pricing as TWO stacked plan cards —
  /// **Monthly** and **Yearly** — so both prices are always visible
  /// (R34.99/month AND R349.99/year for hunters; R299.99/month AND
  /// R2999.99/year for outfitters). Tapping a card selects that billing cycle
  /// (it drives the order summary + the highlighted PayFast button). Only the
  /// active tier (Hunter or Outfitter) is shown — the other tier is hidden.
  ///
  /// When [sub] is an ACTIVE subscription, the card matching the subscriber's
  /// plan is badged **YOUR TIER** (resolved from the server-owned plan id) —
  /// the layout the brief specifies: the active banner stays at the top and
  /// BOTH plan cards remain visible below it, with the current plan marked.
  Widget _buildTierCards(ThemeController theme, UserSubscription sub) {
    final isOutfitter = _tier == SubscriptionTier.outfitter;
    final roleLabel = isOutfitter ? 'Outfitter' : 'Hunter';
    final perks = isOutfitter ? _outfitterPerks : _hunterPerks;
    final monthly = _monthlyPlan;
    final yearly = _yearlyPlan;
    final savings = yearly.savingsPercent(_monthlyAmount);
    final fullYear = _monthlyAmount * 12;
    // Only badge a card as the subscriber's plan when there IS an active
    // subscription — a trialing / cancelled / free user sees the plain
    // selector with no "YOUR TIER" claim.
    final active = sub.isActive;
    final monthlyCard = _planCard(
      theme,
      plan: monthly,
      title: '$roleLabel Monthly',
      priceLabel: _monthlyPriceLabel(monthly),
      caption: 'Billed every month · incl. VAT',
      key: ValueKey('tierCard_${_tier.key}_monthly'),
      keyBase: 'tierCard_${_tier.key}_monthly',
      perks: perks,
      isActivePlan: active && sub.isActiveCycle('monthly'),
    );
    final yearlyCard = _planCard(
      theme,
      plan: yearly,
      title: '$roleLabel Yearly',
      priceLabel: 'R ${yearly.amountZar.toStringAsFixed(2)}/year',
      caption: 'Billed once a year · incl. VAT',
      savingsLabel: savings == null
          ? null
          : 'SAVE ~$savings% '
              '(R${yearly.amountZar.toStringAsFixed(2)} vs '
              'R${fullYear.toStringAsFixed(2)})',
      key: ValueKey('tierCard_${_tier.key}_yearly'),
      keyBase: 'tierCard_${_tier.key}_yearly',
      perks: perks,
      isActivePlan: active && sub.isActiveCycle('yearly'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TIER PRICING',
          style: TextStyle(
            color: theme.subtitleColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        // On a desktop browser the two plans sit side-by-side so both prices
        // are visible at a glance; on mobile web (and every native platform /
        // the VM test host) they stay stacked, unchanged.
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide =
                kIsWeb && !WebLayout.isMobileWebWidth(constraints.maxWidth);
            if (!sideBySide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  monthlyCard,
                  const SizedBox(height: 12),
                  yearlyCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: monthlyCard),
                const SizedBox(width: 16),
                Expanded(child: yearlyCard),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The Monthly plan's displayed price label. Prefers the live Play catalog
  /// label when available, else the control-plane amount.
  String _monthlyPriceLabel(BillingPlan monthly) =>
      _playVatPrice?.primaryLabel ?? 'R ${_monthlyAmount.toStringAsFixed(2)}/month';

  /// A single selectable plan card (Monthly or Yearly) for the active tier.
  ///
  /// [isActivePlan] marks the card the current ACTIVE subscription bills on
  /// with a green **YOUR TIER** badge (and a green border) so an existing
  /// subscriber can see at a glance which plan they hold while both plan cards
  /// remain visible.
  Widget _planCard(
    ThemeController theme, {
    required BillingPlan plan,
    required String title,
    required String priceLabel,
    required String caption,
    required List<String> perks,
    required Key key,
    required String keyBase,
    String? savingsLabel,
    bool isActivePlan = false,
  }) {
    final isSelected = plan.cycle == _selectedCycle;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: () => _selectCycle(plan.cycle),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActivePlan
                  ? Colors.green
                  : (isSelected
                      ? theme.accentColor
                      : theme.subtitleColor.withValues(alpha: 0.25)),
              width: (isActivePlan || isSelected) ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (isActivePlan) ...[
                    Container(
                      key: ValueKey('${keyBase}_yourTier'),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green),
                      ),
                      child: const Text(
                        'YOUR TIER',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (savingsLabel != null && !isSelected) ...[
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Text(
                        'SAVE ~${plan.savingsPercent(_monthlyAmount)}%',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.accentColor
                          : theme.subtitleColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isSelected ? 'SELECTED' : 'SELECT',
                      style: TextStyle(
                        color: isSelected ? Colors.white : theme.subtitleColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                priceLabel,
                key: ValueKey('${keyBase}_price'),
                style: TextStyle(
                  color: theme.accentColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                key: ValueKey('${keyBase}_caption'),
                style: TextStyle(color: theme.subtitleColor, fontSize: 12),
              ),
              if (savingsLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  savingsLabel,
                  key: ValueKey('${keyBase}_savings'),
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'After a ${SubscriptionTrial.trialDays}-day free trial',
                style: TextStyle(color: theme.subtitleColor, fontSize: 12),
              ),
              const SizedBox(height: 10),
              for (final perk in perks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: theme.accentColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(perk,
                            style: TextStyle(
                                color: theme.textColor, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPromoSection(ThemeController theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROMO CODE',
          style: TextStyle(
            color: theme.subtitleColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('promoCodeField'),
                controller: _promoController,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: theme.textColor),
                decoration: InputDecoration(
                  hintText: 'Enter promo code (optional)',
                  hintStyle: TextStyle(color: theme.subtitleColor),
                  filled: true,
                  fillColor: theme.cardColor,
                  errorText: _promoError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.subtitleColor.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.accentColor, width: 2),
                  ),
                ),
                onSubmitted: (_) => _applyPromo(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              key: const ValueKey('applyPromoButton'),
              onPressed: _applyPromo,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              ),
              child: const Text('APPLY'),
            ),
          ],
        ),
        if (_appliedPromo != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.local_offer_rounded, color: Colors.green, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Promo ${_appliedPromo!.code} applied — '
                    '${_appliedPromo!.percentOff > 0 ? '${_appliedPromo!.percentOff.toStringAsFixed(0)}% off' : 'R ${_appliedPromo!.amountOffZAR.toStringAsFixed(2)} off'}',
                    key: const ValueKey('promoAppliedLabel'),
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTotalCard(ThemeController theme) {
    final discounted =
        _appliedPromo != null && _checkoutAmount < _selectedBaseAmount;
    final isYearly = _selectedCycle == BillingCycle.yearly;
    final cycleLabel = isYearly ? 'yearly' : 'monthly';
    return Container(
      key: const ValueKey('checkoutTotalCard'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          _totalRow(
            theme,
            'Free trial (first ${SubscriptionTrial.trialDays} days)',
            'R 0.00',
          ),
          const SizedBox(height: 8),
          _totalRow(
            theme,
            'Then $cycleLabel (${_tier.key}) · incl. VAT',
            'R ${_selectedBaseAmount.toStringAsFixed(2)}',
            strikethrough: discounted,
          ),
          if (discounted) ...[
            const SizedBox(height: 8),
            _totalRow(
              theme,
              'Promo-adjusted $cycleLabel · incl. VAT',
              'R ${_checkoutAmount.toStringAsFixed(2)}',
              highlight: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _totalRow(
    ThemeController theme,
    String label,
    String value, {
    bool strikethrough = false,
    bool highlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlight ? Colors.green : theme.textColor,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            decoration: strikethrough ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSubscribeButton(ThemeController theme, UserSubscription sub) {
    // ---------------------------------------------------------------------
    // WEB BUILD (`kIsWeb`) — HARD RULE: the "MANAGE IN GOOGLE PLAY" affordance
    // is NEVER rendered in a browser, under ANY circumstance. There is no
    // Google Play Billing in a browser: no Play catalog, no Play purchase
    // stream and no Play subscriptions manager. This is a PLATFORM check only
    // — it is deliberately NOT conditioned on the subscription being active,
    // on the recorded `subscriptionPlatform`, or on the trial state. If the
    // build is the web build, the Play manager branch below is unreachable.
    //
    // What the web shows instead:
    //   * an ACTIVE subscriber -> "MANAGE SUBSCRIPTION ON PAYFAST"
    //     (a browser cannot open the Play subscriptions centre for a web
    //     purchase);
    //   * otherwise (no subscription / live free trial) -> the green
    //     "SUBSCRIBE VIA PAYFAST" checkout CTA, plus the Monthly + Yearly
    //     plan buttons and the PayFast trust footer rendered by the caller.
    // ---------------------------------------------------------------------
    if (_isWebBilling) {
      if (sub.isActive) {
        return _buildManageOnPayFastButton(theme);
      }
      return _buildCheckoutButton(theme);
    }

    // ---------------------------------------------------------------------
    // NATIVE (Android / iOS) — Google Play owns the recurring billing.
    //   * a PayFast (website) subscriber -> the website manage link (the only
    //     case where an external link is Play-policy-compliant);
    //   * otherwise a subscriber (Play-billed / unknown platform) -> the Play
    //     subscriptions manager;
    //   * no subscription -> the native Play subscribe CTA.
    // ---------------------------------------------------------------------
    if (sub.hasSubscription) {
      if (sub.isPayfastBilled) {
        return _buildManageOnWebsiteButton(theme);
      }
      return _buildManageInGooglePlayButton(theme);
    }
    return _buildCheckoutButton(theme);
  }

  /// NATIVE-ONLY: the Google Play subscriptions manager action.
  ///
  /// Guarded a second time on `!_isWebBilling` (defense in depth) so even a
  /// future refactor of [_buildSubscribeButton] can never surface this in a
  /// browser. A `kIsWeb` build must never show this button.
  Widget _buildManageInGooglePlayButton(ThemeController theme) {
    if (_isWebBilling) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('cancelSubscriptionButton'),
        onPressed: _isOpeningPlayStore ? null : _cancelSubscription,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          side: BorderSide(color: Colors.red.shade700, width: 1.6),
          disabledForegroundColor: theme.subtitleColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: _isOpeningPlayStore
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.red.shade700,
                ),
              )
            : Icon(Icons.settings_rounded, color: Colors.red.shade700),
        label: Text(
          _isOpeningPlayStore ? 'OPENING…' : 'MANAGE IN GOOGLE PLAY',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  /// WEB-ONLY: the PayFast (website) subscriptions manager action, shown to an
  /// ACTIVE subscriber on the web build.
  Widget _buildManageOnPayFastButton(ThemeController theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('managePayfastSubscriptionButton'),
        onPressed: _isOpeningPlayStore ? null : _openPayfastDashboard,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.accentColor,
          side: BorderSide(color: theme.accentColor, width: 1.6),
          disabledForegroundColor: theme.subtitleColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.language_rounded),
        label: Text(
          _isOpeningPlayStore
              ? 'OPENING…'
              : 'MANAGE SUBSCRIPTION ON PAYFAST',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  /// NATIVE-ONLY: the website (PayFast) manage link for a PayFast-billed
  /// subscriber — the single case where an external link is compliant.
  Widget _buildManageOnWebsiteButton(ThemeController theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('manageWebsiteSubscriptionButton'),
        onPressed: _isOpeningPlayStore ? null : _openWebsiteBilling,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.accentColor,
          side: BorderSide(color: theme.accentColor, width: 1.6),
          disabledForegroundColor: theme.subtitleColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.language_rounded),
        label: const Text(
          'MANAGE SUBSCRIPTION ON WEBSITE',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  /// The green checkout CTA. The label/icon/route branch on the platform:
  /// PayFast on the web, Google Play Billing on native.
  ///
  /// On the WEB build the button is enabled as soon as it is not launching
  /// (there is no Play catalog in a browser). On NATIVE it additionally waits
  /// for the Play catalog to resolve AND for the base-plan offer token Google
  /// Play Billing v5+ requires (tapping before that point produced the
  /// INVALID_OFFER_TOKEN failure).
  Widget _buildCheckoutButton(ThemeController theme) {
    final busy = _isLaunching || (!_isWebBilling && _catalogLoading);
    final String label;
    if (_paymentPending) {
      label = 'PAYMENT PENDING…';
    } else if (_isLaunching) {
      label = _isWebBilling
          ? 'OPENING PAYFAST…'
          : 'CONTACTING GOOGLE PLAY…';
    } else if (!_isWebBilling && _catalogLoading) {
      label = 'LOADING GOOGLE PLAY…';
    } else if (_isWebBilling) {
      label = 'SUBSCRIBE VIA PAYFAST';
    } else {
      label = 'SUBSCRIBE VIA GOOGLE PLAY';
    }
    final canSubscribe =
        _isWebBilling ? !_isLaunching : (!_isLaunching && _subscribeEnabled);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('subscribeButton'),
        onPressed: (_isLaunching || _paymentPending || !canSubscribe)
            ? null
            : _subscribe,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          disabledBackgroundColor: theme.subtitleColor.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: busy
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
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  /// Play-policy "Restore Purchases" action. Always available so a subscriber
  /// on a new device / after a reinstall can re-sync their entitlement.
  Widget _buildRestoreButton(ThemeController theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('restorePurchasesButton'),
        onPressed: _isRestoring ? null : _restorePurchases,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.accentColor,
          side: BorderSide(color: theme.accentColor, width: 1.4),
          disabledForegroundColor: theme.subtitleColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: _isRestoring
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.accentColor,
                ),
              )
            : const Icon(Icons.restore_rounded, size: 18),
        label: Text(
          _isRestoring ? 'RESTORING…' : 'RESTORE PURCHASES',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// Warns the subscriber that the live Play catalog price differs from the
  /// Admin-Portal-configured price. Under Option A both are the final
  /// VAT-inclusive charge. The store is the charge truth; the operator must
  /// align the Play base plan.
  Widget _buildDivergenceNotice(ThemeController theme) {
    final product = _products[_tier];
    final admin = _adminFallbackPrice ?? 0;
    final message = product == null
        ? 'Play Console price unavailable != Admin pricing '
            'R ${admin.toStringAsFixed(2)} — update the Play Console base plan '
            'to match.'
        : PlayPriceReconciliation.compare(
            playExVat: product.rawPrice,
            adminInclVat: admin,
            currencySymbol: product.currencySymbol,
          ).mismatchMessage;
    return Container(
      key: const ValueKey('priceDivergenceNotice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'WARNING: $message',
              style: TextStyle(color: theme.textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
