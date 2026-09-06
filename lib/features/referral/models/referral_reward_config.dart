import 'referral_conversion.dart';

/// The Firestore collection that stores admin-only platform configuration.
///
/// The referral reward amounts live at `admin_config/referral_rewards`
/// (see [ReferralRewards.adminConfigDocId]).
const String kAdminConfigCollection = 'admin_config';

/// Admin-configured referral reward amounts (ZAR), stored on
/// `admin_config/referral_rewards`.
///
/// The amounts are DYNAMIC — an admin can adjust the hunter vs. outfitter
/// reward at any time and every consumer (the referral UI copy, the reward
/// calculation, the payout flow) reads the live document rather than a
/// hardcoded constant. When the document is absent (first launch / offline)
/// consumers fall back to [ReferralRewards.defaultHunterRewardZAR] /
/// [ReferralRewards.defaultOutfitterRewardZAR].
class ReferralRewardConfig {
  final double hunterRewardZAR;
  final double outfitterRewardZAR;

  const ReferralRewardConfig({
    this.hunterRewardZAR = ReferralRewards.defaultHunterRewardZAR,
    this.outfitterRewardZAR = ReferralRewards.defaultOutfitterRewardZAR,
  });

  /// Hydrates from a Firestore map. Numeric strings are tolerated; missing /
  /// invalid values fall back to the documented defaults; negative amounts
  /// are clamped to zero so a misconfiguration can never produce a negative
  /// reward.
  static ReferralRewardConfig fromMap(Map<String, dynamic>? data) {
    if (data == null) return const ReferralRewardConfig();
    return ReferralRewardConfig(
      hunterRewardZAR: _clamped(data['hunterRewardZAR'] ??
            data['hunterAmountZAR'] ??
            data['hunter'] ??
            ReferralRewards.defaultHunterRewardZAR),
      outfitterRewardZAR: _clamped(data['outfitterRewardZAR'] ??
            data['outfitterAmountZAR'] ??
            data['outfitter'] ??
            ReferralRewards.defaultOutfitterRewardZAR),
    );
  }

  Map<String, dynamic> toMap() => {
        'hunterRewardZAR': hunterRewardZAR,
        'outfitterRewardZAR': outfitterRewardZAR,
      };

  /// The reward amount for a given subscription tier.
  double amountFor(ReferralSubscriptionTier tier) =>
      tier == ReferralSubscriptionTier.outfitter
          ? outfitterRewardZAR
          : hunterRewardZAR;

  static double _clamped(dynamic v) {
    final parsed = v is num
        ? v.toDouble()
        : double.tryParse(v?.toString() ?? '') ?? 0.0;
    return parsed < 0 ? 0.0 : parsed;
  }
}