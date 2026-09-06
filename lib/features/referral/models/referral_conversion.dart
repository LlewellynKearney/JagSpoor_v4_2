import 'package:cloud_firestore/cloud_firestore.dart';

/// The Firestore collection that records every referral that converted.
const String kReferralConversionsCollection = 'referral_conversions';

/// The lifecycle state of a referral conversion.
enum ReferralConversionStatus {
  /// The referred user signed up with the referrer's code but has not yet
  /// completed the qualifying action (e.g. started a paid subscription).
  pending,

  /// The qualifying action completed — the referrer's reward is now due
  /// (subject to the admin reward config + any payout policy).
  rewarded,

  /// The referral was rejected / did not qualify (fraud, self-referral,
  /// refunded subscription, etc.) — no reward is due.
  rejected;

  /// Parses a status string, case-insensitively. Unknown values fall back to
  /// [ReferralConversionStatus.pending].
  static ReferralConversionStatus fromString(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'rewarded':
        return ReferralConversionStatus.rewarded;
      case 'rejected':
        return ReferralConversionStatus.rejected;
      case 'pending':
      default:
        return ReferralConversionStatus.pending;
    }
  }

  String get key => name;
}

/// The app subscription tier of the referred user at conversion time. Mirrors
/// [SubscriptionTier] (`subscription_pricing.dart`) as a standalone enum so
/// the referral module carries no billing dependency.
enum ReferralSubscriptionTier {
  hunter,
  outfitter;

  /// Parses a tier string case-insensitively. Unknown / null values default
  /// to [ReferralSubscriptionTier.hunter] (the cheaper tier — a caller never
  /// over-credits a reward by default).
  static ReferralSubscriptionTier fromString(String? value) =>
      (value ?? '').toLowerCase() == 'outfitter'
          ? ReferralSubscriptionTier.outfitter
          : ReferralSubscriptionTier.hunter;

  String get key => name;
}

/// A single referral conversion record: who referred whom, with which
/// subscription tier, and the current reward status.
///
/// Documents are keyed by their Firestore id (`referral_conversions/{id}`)
/// and carry:
///  - `referrerId`  — the UID of the user whose code was used (the referrer).
///  - `referredUserId` — the UID of the new signup (the referred user).
///  - `referralCode`  — the code that was redeemed (cache so the record is
///    self-contained even if the profile later changes).
///  - `subscriptionTier` — the referred user's tier ('hunter' | 'outfitter')
///    at the moment the conversion qualifies.
///  - `status` — 'pending' → 'rewarded' | 'rejected' (see
///    [ReferralConversionStatus]).
///  - `rewardAmountZAR` — the reward amount recorded for the conversion
///    (0 until the status is finalised; Phase 2 wires the payout + claim
///    flow on top).
class ReferralConversion {
  final String id;
  final String referrerId;
  final String referredUserId;
  final String referralCode;
  final ReferralSubscriptionTier subscriptionTier;
  final ReferralConversionStatus status;
  final double rewardAmountZAR;
  final DateTime? convertedAt;
  final DateTime? statusUpdatedAt;
  final DateTime? createdAt;

  const ReferralConversion({
    required this.id,
    required this.referrerId,
    required this.referredUserId,
    this.referralCode = '',
    this.subscriptionTier = ReferralSubscriptionTier.hunter,
    this.status = ReferralConversionStatus.pending,
    this.rewardAmountZAR = 0.0,
    this.convertedAt,
    this.statusUpdatedAt,
    this.createdAt,
  });

  /// Parses a Firestore document into a [ReferralConversion].
  factory ReferralConversion.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      ReferralConversion.fromMap(doc.data() ?? const <String, dynamic>{},
          id: doc.id);

  /// Snapshot-free map parser (unit-testable without a `DocumentSnapshot`).
  /// Tolerates the `referredBy` legacy alias for `referrerId` and the
  /// `referredUid` alias for `referredUserId`.
  factory ReferralConversion.fromMap(
    Map<String, dynamic> data, {
    required String id,
  }) =>
      ReferralConversion(
        id: id,
        referrerId:
            ((data['referrerId'] as String?) ??
                    (data['referredBy'] as String?) ??
                    '')
                .trim(),
        referredUserId:
            ((data['referredUserId'] as String?) ??
                    (data['referredUid'] as String?) ??
                    (data['referredUser'] as String?) ??
                    '')
                .trim(),
        referralCode:
            ((data['referralCode'] as String?) ??
                    (data['code'] as String?) ??
                    '')
                .trim()
                .toUpperCase(),
        subscriptionTier: ReferralSubscriptionTier.fromString(
            data['subscriptionTier'] ?? data['tier']),
        status: ReferralConversionStatus.fromString(data['status']),
        rewardAmountZAR: _asDouble(
            data['rewardAmountZAR'] ?? data['rewardAmount'] ?? 0),
        convertedAt: (data['convertedAt'] as Timestamp?)?.toDate(),
        statusUpdatedAt: (data['statusUpdatedAt'] as Timestamp?)?.toDate(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );

  /// Firestore-serializable map. `convertedAt` is a server timestamp
  /// placeholder when the conversion is first written; [rewardAmountZAR] is
  /// omitted until the reward is finalised so a pending record carries no
  /// stale amount.
  Map<String, dynamic> toMap() => {
        'referrerId': referrerId,
        'referredUserId': referredUserId,
        'referralCode': referralCode,
        'subscriptionTier': subscriptionTier.key,
        'status': status.key,
        if (rewardAmountZAR > 0) 'rewardAmountZAR': rewardAmountZAR,
        if (convertedAt != null)
          'convertedAt': Timestamp.fromDate(convertedAt!),
        if (statusUpdatedAt != null)
          'statusUpdatedAt': Timestamp.fromDate(statusUpdatedAt!),
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      };

  ReferralConversion copyWith({
    ReferralConversionStatus? status,
    double? rewardAmountZAR,
    DateTime? statusUpdatedAt,
  }) =>
      ReferralConversion(
        id: id,
        referrerId: referrerId,
        referredUserId: referredUserId,
        referralCode: referralCode,
        subscriptionTier: subscriptionTier,
        status: status ?? this.status,
        rewardAmountZAR: rewardAmountZAR ?? this.rewardAmountZAR,
        convertedAt: convertedAt,
        statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
        createdAt: createdAt,
      );

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// Pure referral-state constants: the initial documented reward amounts.
///
/// These mirror the ADMIN-CONFIGURED defaults in `functions/src/referral.ts`
/// (`DEFAULT_HUNTER_REWARD_ZAR` / `DEFAULT_OUTFITTER_REWARD_ZAR`) and the
/// `admin_config/referral_rewards` document (the dynamic source of truth).
/// The client constants exist so the shared [referralRewardLabel] /
/// [referralRewardForTier] helpers have a fallback when the admin config has
/// not loaded (offline / first launch).
class ReferralRewards {
  ReferralRewards._();

  /// Document id of the admin reward-config doc inside `admin_config`.
  static const String adminConfigDocId = 'referral_rewards';

  /// Default hunter-tier referral reward (ZAR) — one month's hunter
  /// subscription value.
  static const double defaultHunterRewardZAR = 19.99;

  /// Default outfitter-tier referral reward (ZAR) — one month's outfitter
  /// subscription value.
  static const double defaultOutfitterRewardZAR = 199.99;

  /// The reward amount the referred new subscriber's tier pays out. Used by
  /// the UI copy + the fallback path when the dynamic admin config is
  /// unreachable. The TypeScript backend applies the SAME tier-to-amount
  /// mapping when it finalises a conversion.
  static double amountFor(ReferralSubscriptionTier tier) =>
      tier == ReferralSubscriptionTier.outfitter
          ? defaultOutfitterRewardZAR
          : defaultHunterRewardZAR;

  /// A human-readable reward label, e.g. `R 199.99`.
  static String labelFor(ReferralSubscriptionTier tier) {
    final amount = amountFor(tier);
    final whole = amount.round();
    final text = (amount - whole).abs() < 0.005
        ? '$whole'
        : amount.toStringAsFixed(2);
    return 'R $text';
  }
}