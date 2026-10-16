import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/entitlement_service.dart';
import '../services/play_billing_service.dart';
import '../services/subscription_pricing.dart';

/// A settings / account tile that renders the Play-policy-compliant
/// subscription management action for the current user.
///
/// **Play compliance (critical):** a Google Play-billed subscriber is routed
/// to Google Play's own subscriptions manager
/// (`play.google.com/store/account/subscriptions`) and is NEVER shown an
/// external website checkout link. Only a PayFast (website) subscriber — the
/// single compliant case — is offered "Manage subscription on website".
///
/// The tile is reactive (it listens to the entitlement stream) and reachable in
/// one tap; cancelling requires no JagSpoor login because Google Play
/// authorises the action with the device's own Google account.
class SubscriptionManagementTile extends StatelessWidget {
  final ThemeController theme;

  /// Overrides the entitlement stream (tests / custom sources). Defaults to
  /// [EntitlementService.watchMyEntitlement].
  final Stream<UserEntitlement>? entitlementStream;

  /// Optional action for a user with NO active subscription (e.g. push the
  /// subscription screen). When null the tile is informational only.
  final VoidCallback? onSubscribe;

  const SubscriptionManagementTile({
    super.key,
    required this.theme,
    this.entitlementStream,
    this.onSubscribe,
  });

  /// The Play subscriptions manager URL for the app's Hunter tier (the entry
  /// point Google exposes for the whole account, so the sku is only a hint).
  static String get playSubscriptionsUrl => PlayBillingService
      .instance
      .subscriptionCenterUrlFor(SubscriptionTier.hunter);

  /// The website billing page (PayFast) — shown ONLY to PayFast subscribers.
  static String get websiteBillingUrl => PlayBillingService.websiteBillingUrl;

  Future<void> _launch(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open the store. Please manage your subscription '
              'from the Google Play Store app.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Unable to open the store: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream =
        entitlementStream ?? EntitlementService.instance.watchMyEntitlement();
    return StreamBuilder<UserEntitlement>(
      stream: stream,
      builder: (context, snapshot) {
        final entitlement = snapshot.data ?? const UserEntitlement();
        final active = entitlement.isPremiumActive(DateTime.now());
        final playBilled = entitlement.isPlayBilled;
        final payfastBilled = entitlement.isPayfastBilled;

        // Play compliance: branch on the billing platform. Anything other than
        // an explicit PayFast subscription is treated as Play (or
        // informational) — never steered to an external checkout.
        if (active && payfastBilled) {
          return _tile(
            key: const ValueKey('settingsManageWebsiteSubscriptionTile'),
            icon: Icons.language_rounded,
            title: 'Manage subscription on website',
            subtitle: 'Billed via the JagSpoor website (PayFast).',
            onTap: () => _launch(context, websiteBillingUrl),
          );
        }
        if (active) {
          return _tile(
            key: const ValueKey('settingsManagePlaySubscriptionTile'),
            icon: Icons.play_circle_outline_rounded,
            title: 'Manage subscription',
            subtitle: playBilled
                ? 'Subscription billed by Google Play'
                : 'Manage your subscription in Google Play.',
            onTap: () => _launch(context, playSubscriptionsUrl),
          );
        }
        return _tile(
          key: const ValueKey('settingsNoSubscriptionTile'),
          icon: Icons.workspace_premium_outlined,
          title: 'Subscription',
          subtitle: 'No active subscription.',
          onTap: onSubscribe,
        );
      },
    );
  }

  Widget _tile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      key: key,
      leading: Icon(icon, color: theme.accentColor),
      title: Text(title, style: TextStyle(color: theme.textColor)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: theme.subtitleColor, fontSize: 12),
      ),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right, color: theme.subtitleColor),
      onTap: onTap,
    );
  }
}
