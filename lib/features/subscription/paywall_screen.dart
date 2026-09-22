import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../auth/services/user_role_provider.dart';
import 'services/play_billing_service.dart';
import 'services/subscription_pricing.dart';

/// Paywall shown when a user's free trial has expired and they are not a
/// premium subscriber. Two actions:
///   1. Subscribe via Google Play (native in_app_purchase).
///   2. Manage subscription on the JagSpoor website
///      (https://jagspoor.co.za/pricing — PayFast lives on the website,
///      deliberately NOT embedded in the app).
class PaywallScreen extends StatefulWidget {
  final ThemeController theme;

  const PaywallScreen({super.key, required this.theme});

  /// The pricing page hosted on the website (PayFast checkout).
  static const String websitePricingUrl = 'https://jagspoor.co.za/pricing';

  /// Shown while the live Google Play catalog price has not resolved yet.
  static const String loadingPriceLabel = 'Loading price…';

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  /// Live Play catalog price label (e.g. "R34.99") — already formatted by
  /// Google Play, so it reflects whatever base-plan amount (VAT inclusive)
  /// the Play Console configured. Null until the catalog resolves.
  String? _playPrice;

  ThemeController get theme => widget.theme;

  SubscriptionTier get _tier =>
      SubscriptionTier.fromAppRole(UserRoleProvider.instance.role);

  @override
  void initState() {
    super.initState();
    _loadPlayPrice();
  }

  /// Loads the live Google Play Billing catalog price for the active tier.
  ///
  /// The price is NEVER hardcoded here: Google Play returns the localized,
  /// VAT-inclusive base-plan amount (`ProductDetails.price`, e.g. "R34.99"),
  /// so the paywall always shows exactly what the store will charge. Until
  /// the catalog resolves — or when billing is unavailable — the paywall
  /// falls back to [PaywallScreen.loadingPriceLabel] rather than inventing a
  /// number.
  Future<void> _loadPlayPrice() async {
    try {
      final products = await PlayBillingService.instance.loadProducts();
      final product = products[_tier];
      if (!mounted || product == null) return;
      setState(() => _playPrice = product.price);
    } catch (e) {
      debugPrint('PaywallScreen.loadPlayPrice failed: $e');
    }
  }

  Future<void> _launchWebsite(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final launched = await launchUrl(
        Uri.parse(PaywallScreen.websitePricingUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Unable to open the website. Please visit '
              '${PaywallScreen.websitePricingUrl} in your browser.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('PaywallScreen.launchWebsite failed: $e');
    }
  }

  Future<void> _subscribeViaGooglePlay(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final launched = await PlayBillingService.instance.purchaseProduct(_tier);
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

  @override
  Widget build(BuildContext context) {
    final theme = this.theme;
    final priceLabel = _playPrice ?? PaywallScreen.loadingPriceLabel;
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
                      'Your free trial has ended',
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Subscribe to continue using the full hunting '
                      'toolkit, package marketplace, ballistics calculator '
                      'and all premium features.',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    // Live Google Play price — already localized + VAT
                    // inclusive, so it always matches what the store charges
                    // (e.g. "R34.99"). Never a hardcoded amount.
                    Text(
                      priceLabel,
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
                      'per month · includes VAT',
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
              FilledButton.icon(
                key: const ValueKey('paywallPlaySubscribeButton'),
                onPressed: () => _subscribeViaGooglePlay(context),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.play_circle_fill_rounded),
                label: const Text(
                  'SUBSCRIBE VIA GOOGLE PLAY',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('paywallWebsiteButton'),
                onPressed: () => _launchWebsite(context),
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
                  'MANAGE SUBSCRIPTION ON WEBSITE',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
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