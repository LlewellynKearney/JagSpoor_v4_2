import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/copyright_footer.dart';
import '../auth/services/user_role_provider.dart';
import 'services/play_billing_service.dart';
import 'services/subscription_pricing.dart';
import 'services/subscription_status_service.dart';

/// Subscription checkout screen.
///
/// Shows the user's trial / subscription status, the two tier prices
/// (Hunter R19.99/month vs Outfitter R199.99/month), a promo-code input that
/// adjusts the displayed checkout total, and a primary action that invokes
/// the native **Google Play Billing** subscription flow.
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
  bool _billingSupported = true;
  Map<SubscriptionTier, PlayProduct> _products = const {};

  SubscriptionTier get _tier =>
      widget.tier ??
      SubscriptionTier.fromAppRole(UserRoleProvider.instance.role);

  double get _baseAmount =>
      _tier == SubscriptionTier.outfitter ? 199.99 : 19.99;
  double get _checkoutAmount =>
      _appliedPromo == null ? _baseAmount : _appliedPromo!.apply(_baseAmount);

  @override
  void initState() {
    super.initState();
    _initBilling();
    _listenForPurchases();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  /// Resolves billing availability + the Play catalog so the UI can show the
  /// real Play Console price and surface a graceful "billing unavailable"
  /// state.
  Future<void> _initBilling() async {
    final supported = await PlayBillingService.instance.isBillingSupported();
    Map<SubscriptionTier, PlayProduct> products = const {};
    if (supported) {
      try {
        products = await PlayBillingService.instance.loadProducts();
      } catch (e) {
        debugPrint('SubscriptionScreen: loadProducts failed: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _billingSupported = supported;
      _products = products;
    });
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

  /// Launches the native Google Play Billing subscription flow for the
  /// current tier.
  ///
  /// The purchase result arrives asynchronously through
  /// [PlayBillingService.purchaseStream]; the screen listens there and
  /// records the entitlement (see [_listenForPurchases]).
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
    setState(() => _isLaunching = true);
    try {
      final launched = await PlayBillingService.instance.purchaseProduct(_tier);
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

  /// Listens to the Play Billing purchase stream and mirrors completed
  /// purchases onto `users/{uid}` so the UI + role gating update.
  ///
  /// Subscriptions are non-consumable; once a [PurchaseStatus.purchased] /
  /// [PurchaseStatus.restored] event arrives the entitlement is recorded and
  /// the transaction is finished.
  void _listenForPurchases() {
    PlayBillingService.instance.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          final tier = SubscriptionTier.fromPlayProductId(purchase.productID);
          try {
            await SubscriptionStatusService.instance.recordPlayPurchase(
              tier: tier,
              purchaseToken:
                  purchase.verificationData.serverVerificationData,
            );
          } catch (e) {
            debugPrint('recordPlayPurchase failed (non-fatal): $e');
          }
          await PlayBillingService.instance.completePurchase(purchase);
          if (!mounted) continue;
          final messenger = ScaffoldMessenger.maybeOf(context);
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
        } else if (purchase.status == PurchaseStatus.error) {
          debugPrint('Play purchase error: ${purchase.error}');
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
          stream: SubscriptionStatusService.instance.watchMySubscription(),
          builder: (context, snapshot) {
            final subscription = snapshot.data ?? const UserSubscription();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _buildStatusBanner(theme, subscription),
                const SizedBox(height: 20),
                _buildTierCards(theme),
                const SizedBox(height: 20),
                _buildPromoSection(theme),
                const SizedBox(height: 20),
                _buildTotalCard(theme),
                const SizedBox(height: 24),
                _buildSubscribeButton(theme, subscription),
                const CopyrightFooter(),
              ],
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

  /// Renders ONLY the active mode's tier card — Hunter Mode shows the Hunter
  /// tier, Outfitter Mode shows the Outfitter tier; the other tier card is
  /// hidden completely.
  Widget _buildTierCards(ThemeController theme) {
    final isOutfitter = _tier == SubscriptionTier.outfitter;
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
        _tierCard(
          theme,
          tier: _tier,
          title: isOutfitter ? 'Outfitter' : 'Hunter',
          amount: _baseAmount,
          playPrice: _products[_tier]?.price,
          perks: isOutfitter ? _outfitterPerks : _hunterPerks,
        ),
      ],
    );
  }

  Widget _tierCard(
    ThemeController theme, {
    required SubscriptionTier tier,
    required String title,
    required double amount,
    required List<String> perks,
    String? playPrice,
  }) {
    final isCurrent = tier == _tier;
    return Container(
      key: ValueKey('tierCard_${tier.key}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? theme.accentColor : theme.subtitleColor.withValues(alpha: 0.25),
          width: isCurrent ? 2 : 1,
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
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.accentColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'YOUR TIER',
                    style: TextStyle(
                      color: Colors.white,
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
            playPrice ?? 'R ${amount.toStringAsFixed(2)} / month',
            style: TextStyle(
              color: theme.accentColor,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
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
                  Icon(Icons.check_circle_rounded, color: theme.accentColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(perk, style: TextStyle(color: theme.textColor, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
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
    final discounted = _appliedPromo != null && _checkoutAmount < _baseAmount;
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
            'Then monthly (${_tier.key})',
            'R ${_baseAmount.toStringAsFixed(2)}',
            strikethrough: discounted,
          ),
          if (discounted) ...[
            const SizedBox(height: 8),
            _totalRow(
              theme,
              'Promo-adjusted monthly',
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
    // Active subscription / live free trial: the primary checkout button is
    // replaced by the manage-in-Google-Play action, since recurring billing
    // is owned by Google Play.
    if (sub.hasSubscription) {
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
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('subscribeButton'),
        onPressed: _isLaunching ? null : _subscribe,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          disabledBackgroundColor: theme.subtitleColor.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: _isLaunching
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.play_circle_fill_rounded),
        label: Text(
          _isLaunching ? 'CONTACTING GOOGLE PLAY…' : 'SUBSCRIBE VIA GOOGLE PLAY',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
