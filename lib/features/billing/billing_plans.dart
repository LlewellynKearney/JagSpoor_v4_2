import '../subscription/services/subscription_pricing.dart';

/// Billing cycle for a subscription plan.
enum BillingCycle {
  monthly,
  yearly;

  static BillingCycle fromString(String? value) =>
      (value ?? '').trim().toLowerCase() == 'yearly'
          ? BillingCycle.yearly
          : BillingCycle.monthly;

  String get key => name;

  /// Human label used on the plan cards ("Monthly" / "Yearly").
  String get label => this == BillingCycle.yearly ? 'Yearly' : 'Monthly';
}

/// A purchasable subscription plan for the CURRENT role.
///
/// Plans are the client-side mirror of the server catalog
/// (`functions/src/payfast/plans.ts`). The client sends only the [planId] to
/// `createPayFastPayment` — the server resolves the authoritative amount from
/// its own catalog, so a tampered client price can never be charged.
class BillingPlan {
  /// Stable server plan id, e.g. `hunter_monthly`.
  final String planId;

  /// The tier this plan bills.
  final SubscriptionTier tier;

  /// Monthly or yearly.
  final BillingCycle cycle;

  /// The ZAR amount shown to the customer (VAT inclusive).
  final double amountZar;

  /// Item name shown on the PayFast checkout / native store.
  final String itemName;

  const BillingPlan({
    required this.planId,
    required this.tier,
    required this.cycle,
    required this.amountZar,
    required this.itemName,
  });

  /// Whether this is an annual plan.
  bool get isYearly => cycle == BillingCycle.yearly;

  /// A short price label, e.g. `R 34.99/month` or `R 349.99/year`.
  String get priceLabel =>
      'R ${amountZar.toStringAsFixed(2)}/${isYearly ? 'year' : 'month'}';

  /// The monthly-equivalent amount for a yearly plan (used for the
  /// "save X%" hint); equals [amountZar] for a monthly plan.
  double get monthlyEquivalent => isYearly ? amountZar / 12.0 : amountZar;

  /// A savings percentage versus the monthly plan, or null when not yearly or
  /// no monthly baseline is known.
  int? savingsPercent(double? monthlyAmount) {
    if (!isYearly || monthlyAmount == null || monthlyAmount <= 0) return null;
    final fullYear = monthlyAmount * 12.0;
    if (fullYear <= 0 || amountZar >= fullYear) return null;
    return (((fullYear - amountZar) / fullYear) * 100).round();
  }
}

/// The canonical plan catalog — the client mirror of
/// `functions/src/payfast/plans.ts` (PAYFAST_PLAN_CATALOG). Kept in sync so
/// the web UI can render prices without a round-trip; the server remains the
/// authority for the actual charge.
class BillingPlans {
  BillingPlans._();

  /// The two plans offered for a tier: monthly + yearly.
  static List<BillingPlan> forTier(SubscriptionTier tier) => [
        BillingPlan(
          planId: '${tier.key}_monthly',
          tier: tier,
          cycle: BillingCycle.monthly,
          amountZar: tier == SubscriptionTier.outfitter ? 299.99 : 34.99,
          itemName:
              'JagSpoor ${_roleLabel(tier)} — Monthly',
        ),
        BillingPlan(
          planId: '${tier.key}_yearly',
          tier: tier,
          cycle: BillingCycle.yearly,
          amountZar: tier == SubscriptionTier.outfitter ? 2999.99 : 349.99,
          itemName: 'JagSpoor ${_roleLabel(tier)} — Yearly',
        ),
      ];

  /// The monthly plan for a tier.
  static BillingPlan monthlyFor(SubscriptionTier tier) =>
      forTier(tier).firstWhere((p) => p.cycle == BillingCycle.monthly);

  /// Resolves a plan id back to its plan, or null when unknown.
  static BillingPlan? byId(String? planId) {
    if (planId == null || planId.isEmpty) return null;
    for (final tier in SubscriptionTier.values) {
      for (final plan in forTier(tier)) {
        if (plan.planId == planId) return plan;
      }
    }
    return null;
  }

  static String _roleLabel(SubscriptionTier tier) =>
      tier == SubscriptionTier.outfitter ? 'Outfitter' : 'Hunter';
}
