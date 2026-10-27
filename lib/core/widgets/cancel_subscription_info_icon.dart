import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Which billing relationship the cancel-help copy describes.
enum BillingPlatform { googlePlay, payfast, payfastAlternative }

/// The billing-help mailbox.
///
/// Deliberately the hyphenated domain the operator monitors for subscription
/// questions — NOT the legacy `support@jagspoor.co.za` dispute contact.
const String cancelSupportEmail = 'support@jag-spoor.co.za';

/// The `mailto:` target behind the "Email Support" action.
const String cancelSupportMailto =
    'mailto:$cancelSupportEmail?subject=Cancel%20Subscription%20Help';

/// The cancel instructions for [platform].
///
/// Kept as one switch (rather than strings inlined at each call site) so the
/// copy is unit-testable and English-only localisation has a single seam.
String getCancelInstructions(BillingPlatform platform) {
  switch (platform) {
    case BillingPlatform.googlePlay:
      return 'To cancel your subscription:\n\n'
          '1. Open Google Play Store app\n'
          '2. Tap Payments & subscriptions > Subscriptions\n'
          '3. Select JagSpoor\n'
          '4. Tap Cancel subscription\n\n'
          'Your access stays active until the end of the current period you '
          'already paid for. Cancel at least 24h before renewal to avoid next '
          'charge.\n\n'
          'If you need help, email us at $cancelSupportEmail';
    case BillingPlatform.payfast:
      return 'To cancel your subscription (website billing):\n\n'
          '1. Tap MANAGE SUBSCRIPTION ON PAYFAST\n'
          '2. Log in on PayFast with your JagSpoor email\n'
          '3. Go to My Subscriptions\n'
          '4. Tap Cancel next to your JagSpoor plan\n\n'
          'You will also find a Cancel link in your PayFast email invoices. '
          'Your access stays active until the end of the current period.\n\n'
          'If you need help, email us at $cancelSupportEmail';
    case BillingPlatform.payfastAlternative:
      return 'To cancel your subscription (PayFast via Google Play):\n\n'
          '1. Tap MANAGE SUBSCRIPTION ON PAYFAST\n'
          '2. Log in on PayFast with your JagSpoor email\n'
          '3. Go to My Subscriptions > Cancel\n\n'
          'Your access stays active until the end of the current period. '
          'This was an alternative billing choice through Google Play.\n\n'
          'If you need help, email us at $cancelSupportEmail';
  }
}

/// A small `(i)` action that explains how to cancel, with copy tailored to
/// [platform].
///
/// Only render it for a subscriber that actually has something to cancel — see
/// [resolveFor], which encodes the gating so the three call sites cannot drift.
class CancelSubscriptionInfoIcon extends StatelessWidget {
  const CancelSubscriptionInfoIcon({
    super.key,
    required this.platform,
    this.theme,
    this.iconSize = 20,
  });

  final BillingPlatform platform;

  /// Theme override; defaults to the process-wide [ThemeController.instance].
  final ThemeController? theme;

  final double iconSize;

  /// Resolves which copy to show, or `null` when the icon must NOT be rendered
  /// (no active subscription / live free trial — there is nothing to cancel).
  ///
  /// * WEB build -> PayFast, and only for an active subscriber: a browser has
  ///   no Play subscriptions manager.
  /// * NATIVE PayFast (website or User Choice Billing alternative) -> the
  ///   alternative-billing copy, which points at the PayFast dashboard.
  /// * NATIVE Play-billed -> the Google Play copy.
  static BillingPlatform? resolveFor({
    required bool isWebBilling,
    required bool hasActiveSubscription,
    required bool isPayfastBilled,
    required bool isPayfastAlternative,
    required bool isActivePlaySub,
    bool payfastChosen = false,
  }) {
    final gate = hasActiveSubscription || isPayfastBilled || isActivePlaySub;
    if (!gate) return null;
    if (isWebBilling) return BillingPlatform.payfast;
    if (isPayfastBilled || isPayfastAlternative || payfastChosen) {
      return BillingPlatform.payfastAlternative;
    }
    if (isActivePlaySub) return BillingPlatform.googlePlay;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final color = (theme ?? ThemeController.instance).subtitleColor;
    return IconButton(
      key: ValueKey('cancelInfoIcon_${platform.name}'),
      tooltip: 'How to cancel',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: iconSize + 8,
        minHeight: iconSize + 8,
      ),
      icon: Icon(Icons.info_outline, color: color, size: iconSize),
      onPressed: () =>
          showCancelSubscriptionHelp(context, platform, theme: theme),
    );
  }
}

/// Opens the cancel-help dialog for [platform].
Future<void> showCancelSubscriptionHelp(
  BuildContext context,
  BillingPlatform platform, {
  ThemeController? theme,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        CancelSubscriptionHelpDialog(platform: platform, theme: theme),
  );
}

/// The "How to cancel your subscription" dialog.
///
/// Web-responsive: capped at 480px on the web build and 400px on mobile, and
/// centred by `Dialog` itself. Scrollable so it never overflows a short
/// viewport.
class CancelSubscriptionHelpDialog extends StatelessWidget {
  const CancelSubscriptionHelpDialog({
    super.key,
    required this.platform,
    this.theme,
  });

  final BillingPlatform platform;
  final ThemeController? theme;

  Future<void> _emailSupport(BuildContext context) async {
    // Capture the messenger before the async gap: the dialog may be dismissed
    // while the mail client is being handed off.
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final opened = await launchUrl(
        Uri.parse(cancelSupportMailto),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open your mail app. Email us at $cancelSupportEmail.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not open your mail app: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = theme ?? ThemeController.instance;
    final maxWidth = kIsWeb ? 480.0 : 400.0;
    return Dialog(
      key: const ValueKey('cancelSubscriptionHelpDialog'),
      backgroundColor: t.cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    color: t.accentColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'How to cancel your subscription',
                      style: TextStyle(
                        color: t.textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InstructionBody(
                text: getCancelInstructions(platform),
                theme: t,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('cancelInfoCloseButton'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(
                        'CLOSE',
                        style: TextStyle(
                          color: t.subtitleColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('cancelInfoEmailButton'),
                      onPressed: () => _emailSupport(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: t.accentColor,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.mail_outline_rounded, size: 18),
                      label: const Text(
                        'EMAIL SUPPORT',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the instructions with the support address as an inline tappable
/// `mailto:` link.
///
/// Stateful so the [TapGestureRecognizer] is created once and disposed with the
/// widget — building a recognizer inside `build` would leak it on every frame.
class _InstructionBody extends StatefulWidget {
  const _InstructionBody({required this.text, required this.theme});

  final String text;
  final ThemeController theme;

  @override
  State<_InstructionBody> createState() => _InstructionBodyState();
}

class _InstructionBodyState extends State<_InstructionBody> {
  late final TapGestureRecognizer _emailTap;

  @override
  void initState() {
    super.initState();
    _emailTap = TapGestureRecognizer()..onTap = _email;
  }

  @override
  void dispose() {
    _emailTap.dispose();
    super.dispose();
  }

  Future<void> _email() async {
    try {
      await launchUrl(
        Uri.parse(cancelSupportMailto),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Best-effort: the dialog also carries an explicit Email Support button,
      // which surfaces a message when no mail client is available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: widget.theme.subtitleColor,
      fontSize: 13.5,
      height: 1.45,
    );
    final index = widget.text.indexOf(cancelSupportEmail);
    if (index < 0) {
      return SelectableText(widget.text, style: base);
    }
    return SelectableText.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: widget.text.substring(0, index)),
          TextSpan(
            text: cancelSupportEmail,
            style: TextStyle(
              color: widget.theme.accentColor,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
            recognizer: _emailTap,
          ),
          TextSpan(text: widget.text.substring(index + cancelSupportEmail.length)),
        ],
      ),
    );
  }
}
