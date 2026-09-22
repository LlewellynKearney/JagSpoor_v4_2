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

  /// The reward mechanism (`extension_days` today). Reserved for future
  /// mechanisms (e.g. a cash payout); the Cloud Function grants the reward as
  /// an entitlement extension when this is `extension_days`.
  final String rewardType;

  /// Days the referrer's entitlement is extended per granted hunter referral.
  final int hunterDays;

  /// Days the referrer's entitlement is extended per granted outfitter
  /// referral.
  final int outfitterDays;

  const ReferralRewardConfig({
    this.hunterRewardZAR = ReferralRewards.defaultHunterRewardZAR,
    this.outfitterRewardZAR = ReferralRewards.defaultOutfitterRewardZAR,
    this.rewardType = ReferralRewards.defaultRewardType,
    this.hunterDays = ReferralRewards.defaultHunterDays,
    this.outfitterDays = ReferralRewards.defaultOutfitterDays,
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
      rewardType: (data['rewardType'] ?? ReferralRewards.defaultRewardType)
          .toString(),
      hunterDays: _clampedInt(
          data['hunter_days'] ?? data['hunterDays'],
          ReferralRewards.defaultHunterDays),
      outfitterDays: _clampedInt(
          data['outfitter_days'] ?? data['outfitterDays'],
          ReferralRewards.defaultOutfitterDays),
    );
  }

  /// The admin-config payload. Writes BOTH the canonical snake_case keys the
  /// control plane / Cloud Function read and the legacy camelCase aliases.
  Map<String, dynamic> toMap() => {
        'hunter': hunterRewardZAR,
        'outfitter': outfitterRewardZAR,
        'hunterRewardZAR': hunterRewardZAR,
        'outfitterRewardZAR': outfitterRewardZAR,
        'rewardType': rewardType,
        'hunter_days': hunterDays,
        'outfitter_days': outfitterDays,
      };

  /// The reward amount for a given subscription tier.
  double amountFor(ReferralSubscriptionTier tier) =>
      tier == ReferralSubscriptionTier.outfitter
          ? outfitterRewardZAR
          : hunterRewardZAR;

  /// The entitlement-extension length (days) for a given subscription tier.
  int daysFor(ReferralSubscriptionTier tier) =>
      tier == ReferralSubscriptionTier.outfitter ? outfitterDays : hunterDays;

  static double _clamped(dynamic v) {
    final parsed = v is num
        ? v.toDouble()
        : double.tryParse(v?.toString() ?? '') ?? 0.0;
    return parsed < 0 ? 0.0 : parsed;
  }

  /// Clamps a day count to >= 0; tolerates numeric strings; a missing /
  /// unparseable value falls back to [fallback].
  static int _clampedInt(dynamic v, int fallback) {
    if (v == null) return fallback;
    final parsed =
        v is num ? v.toInt() : int.tryParse(v.toString().trim());
    if (parsed == null) return fallback;
    return parsed < 0 ? 0 : parsed;
  }
}

/// Pure validation for the admin reward-amount inputs.
///
/// Mirrors [FarmGamePriceValidator] / the subscription-config clamping
/// contract: blank input is rejected, a non-numeric value is rejected, and a
/// negative amount is rejected — the Admin Portal can never persist an
/// invalid (negative or unparseable) ZAR reward.
class ReferralRewardValidator {
  ReferralRewardValidator._();

  /// Strips an optional `R` / `r` currency prefix + internal spaces from raw
  /// input (the dashboard field is prefixed with `R `).
  static String _sanitize(String? text) {
    if (text == null) return '';
    return text.trim().replaceAll(RegExp(r'[Rr]'), '').trim();
  }

  /// Parses a ZAR amount: null/blank -> null; otherwise the sanitized value's
  /// `double.tryParse` result (null when unparseable).
  static double? tryParseZar(String? text) {
    final cleaned = _sanitize(text);
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Returns an error message for an invalid reward amount, else null.
  /// Negative amounts are always rejected; zero is permitted (an admin can
  /// intentionally set a R0.00 reward, e.g. while pausing the programme).
  static String? validateZar(String? text) {
    if (text == null || text.trim().isEmpty) {
      return 'Reward amount is required.';
    }
    final parsed = double.tryParse(_sanitize(text));
    if (parsed == null) {
      return 'Enter a valid ZAR amount, e.g. 19.99.';
    }
    if (parsed < 0) {
      return 'Reward amount cannot be negative.';
    }
    return null;
  }
}