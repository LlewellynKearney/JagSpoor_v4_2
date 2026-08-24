import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/copyright_footer.dart';
import '../auth/services/user_role_provider.dart';
import 'services/payfast_service.dart';
import 'services/subscription_status_service.dart';

/// Subscription checkout screen.
///
/// Shows the user's trial / subscription status, the two tier prices
/// (Hunter R19.99/month vs Outfitter R199.99/month), a promo-code input that
/// adjusts the checkout total before the payment payload is generated, and a
/// secure "Subscribe via PayFast" action button that launches the signed
/// PayFast subscription checkout in the external browser.
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

  SubscriptionTier get _tier =>
      widget.tier ??
      SubscriptionTier.fromAppRole(UserRoleProvider.instance.role);

  double get _baseAmount => PayFastService.baseAmountFor(_tier);
  double get _checkoutAmount =>
      PayFastService.resolveAmount(_tier, _appliedPromo);

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  String? get _userEmail {
    try {
      return FirebaseAuth.instance.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  String? get _userName {
    try {
      return FirebaseAuth.instance.currentUser?.displayName;
    } catch (_) {
      return null;
    }
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

  Future<void> _subscribe() async {
    if (_isLaunching) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uid = _userId;
    final email = _userEmail;
    if (uid == null || email == null || email.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Please sign in with a valid email to subscribe.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isLaunching = true);
    try {
      final payload = PayFastService.buildCheckoutPayload(
        tier: _tier,
        userId: uid,
        emailAddress: email,
        userName: _userName,
        promo: _appliedPromo,
      );
      final launched = await PayFastService.instance.launchCheckout(payload);
      if (!mounted) return;
      if (launched) {
        // Record the trial window so the UI reflects the pending
        // subscription immediately; the ITN webhook flips the status to
        // `active` once PayFast confirms the subscription.
        try {
          await SubscriptionStatusService.instance.markTrialStarted(
            tier: _tier,
            promoCode: _appliedPromo?.code ?? '',
          );
        } catch (e) {
          debugPrint('markTrialStarted failed (non-fatal): $e');
        }
        if (!mounted) return;
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'PayFast checkout opened — complete the subscription in your browser. Your 30-day free trial has started.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open PayFast checkout — no browser app available. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Subscription checkout failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLaunching = false);
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

  /// Outfitter-tier feature checklist (comprehensive — business & lodge
  /// management on top of the full Hunter toolkit).
  static const List<String> _outfitterPerks = [
    'Everything in Hunter Tier included',
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
          amount: PayFastService.baseAmountFor(_tier),
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
            'R ${amount.toStringAsFixed(2)} / month',
            style: TextStyle(
              color: theme.accentColor,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'After a 30-day free trial',
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
          _totalRow(theme, 'Free trial (first ${PayFastService.trialDays} days)', 'R 0.00'),
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
    final alreadyActive = sub.isActive;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('subscribeButton'),
        onPressed: alreadyActive || _isLaunching ? null : _subscribe,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          disabledBackgroundColor: theme.subtitleColor.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: _isLaunching
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(alreadyActive ? Icons.verified_rounded : Icons.lock_rounded),
        label: Text(
          alreadyActive
              ? 'SUBSCRIPTION ACTIVE'
              : _isLaunching
                  ? 'OPENING PAYFAST…'
                  : 'SUBSCRIBE VIA PAYFAST',
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
