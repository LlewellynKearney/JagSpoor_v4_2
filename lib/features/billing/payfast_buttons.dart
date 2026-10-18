import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../subscription/services/subscription_pricing.dart';
import 'billing_plans.dart';
import 'billing_service.dart';

/// The PayFast subscription buttons for the active role (web only).
///
/// The web build cannot use Google Play Billing, so a browser charges
/// subscriptions through PayFast. This widget renders the TWO plans for the
/// given [tier] —
///  * Hunter:    `HUNTER MONTHLY` R34.99 and `HUNTER YEARLY` R349.99, or
///  * Outfitter: `OUTFITTER MONTHLY` R299.99 and `OUTFITTER YEARLY` R2999.99.
///
/// Each button asks the `createPayFastPayment` callable for the signed form
/// and launches the hosted checkout ([BillingService.payWithPlanId]). The
/// button matching [selectedCycle] is highlighted as the selected plan; when
/// the user taps a button it both launches that plan AND reports the choice
/// via [onPlanSelected] so the parent's order summary stays in sync.
///
/// The merchant key never reaches the browser: the Cloud Function signs the
/// payload server-side and the `payfastNotify` ITN webhook writes the
/// authoritative entitlement.
///
/// Off the web (Android / iOS) the widget renders nothing, because Play
/// policy requires in-app digital goods to be sold through Google Play
/// Billing. Pass `forceShow` in tests to render it on the VM.
class PayFastHunterOutfitterButtons extends StatefulWidget {
  const PayFastHunterOutfitterButtons({
    super.key,
    required this.theme,
    required this.tier,
    this.selectedCycle,
    this.forceShow = false,
    this.onPlanSelected,
    this.onLaunched,
    this.onError,
  });

  /// The app theme controller (drives the button palette).
  final ThemeController theme;

  /// The role whose plans are offered. Only this tier's Monthly + Yearly
  /// buttons render (never the other role's).
  final SubscriptionTier tier;

  /// The currently-selected billing cycle (highlights that button). When null
  /// the Monthly button is treated as selected.
  final BillingCycle? selectedCycle;

  /// Render even off the web (widget tests on the VM). Production leaves this
  /// false so the buttons only ever appear in a browser.
  final bool forceShow;

  /// Called when the user taps a plan button, before the checkout launches, so
  /// the parent can update its selected-plan state.
  final void Function(BillingPlan plan)? onPlanSelected;

  /// Called after a checkout is launched successfully.
  final void Function(BillingPlan plan)? onLaunched;

  /// Called with a user-facing message when a checkout could not start.
  final void Function(String message)? onError;

  /// Whether the platform is the web build (or the widget was forced on).
  bool get _isWeb => forceShow || kIsWeb;

  @override
  State<PayFastHunterOutfitterButtons> createState() =>
      _PayFastHunterOutfitterButtonsState();
}

class _PayFastHunterOutfitterButtonsState
    extends State<PayFastHunterOutfitterButtons> {
  /// The plan id currently launching a checkout (drives its spinner), or null.
  String? _launchingPlanId;

  Future<void> _launch(BillingPlan plan) async {
    if (_launchingPlanId != null) return;
    // Report the choice first so the parent's selected-plan state (order
    // summary) reflects the tapped button even if the checkout then fails.
    widget.onPlanSelected?.call(plan);
    setState(() => _launchingPlanId = plan.planId);
    try {
      final result = await BillingService.instance.payWithPlanId(
        role: plan.tier.key,
        planId: plan.planId,
      );
      if (!mounted) return;
      if (result.launched) {
        widget.onLaunched?.call(plan);
      } else {
        widget.onError?.call(
          result.message ?? 'Unable to start the PayFast checkout.',
        );
      }
    } catch (e) {
      if (mounted) {
        widget.onError?.call('Unable to start the PayFast checkout.');
      }
      debugPrint('PayFastHunterOutfitterButtons launch error: $e');
    } finally {
      if (mounted) setState(() => _launchingPlanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget._isWeb) return const SizedBox.shrink();
    final theme = widget.theme;
    final selected = widget.selectedCycle ?? BillingCycle.monthly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PAY WITH PAYFAST',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        for (final plan in BillingPlans.forTier(widget.tier))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlanButton(
              plan: plan,
              theme: theme,
              selected: plan.cycle == selected,
              busy: _launchingPlanId == plan.planId,
              disabled: _launchingPlanId != null,
              onPressed: () => _launch(plan),
            ),
          ),
      ],
    );
  }
}

/// A single PayFast plan button — "HUNTER MONTHLY R34.99" style label.
class _PlanButton extends StatelessWidget {
  const _PlanButton({
    required this.plan,
    required this.theme,
    required this.selected,
    required this.busy,
    required this.disabled,
    required this.onPressed,
  });

  final BillingPlan plan;
  final ThemeController theme;
  final bool selected;
  final bool busy;
  final bool disabled;
  final VoidCallback onPressed;

  /// The role + cycle label, e.g. `HUNTER MONTHLY`.
  String get _label =>
      '${plan.tier == SubscriptionTier.outfitter ? 'OUTFITTER' : 'HUNTER'} '
      '${plan.cycle.label.toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    // The selected plan is filled with the accent; the other is outlined so
    // the current choice is unmistakable while both remain tappable.
    return selected
        ? FilledButton.icon(
            key: ValueKey('payfastPlanButton_${plan.planId}'),
            onPressed: disabled ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: theme.accentColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  theme.subtitleColor.withValues(alpha: 0.3),
              padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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
                : const Icon(Icons.lock_outline_rounded),
            label: _labelRow(),
          )
        : OutlinedButton.icon(
            key: ValueKey('payfastPlanButton_${plan.planId}'),
            onPressed: disabled ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.accentColor,
              side: BorderSide(color: theme.accentColor, width: 1.6),
              disabledForegroundColor: theme.subtitleColor,
              padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.accentColor,
                    ),
                  )
                : const Icon(Icons.lock_outline_rounded),
            label: _labelRow(),
          );
  }

  Widget _labelRow() => Row(
        children: [
          Expanded(
            child: Text(
              _label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Text(
            'R ${plan.amountZar.toStringAsFixed(2)}'
            '${plan.isYearly ? '/year' : '/month'}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      );
}
