import 'package:cloud_firestore/cloud_firestore.dart';

/// The maximum length of a user-facing referral code.
const int kReferralCodeMaxLength = 12;

/// The alphabet used to generate random, human-friendly referral codes.
///
/// Excludes visually ambiguous characters (`0/O/1/I`) so codes are easy to
/// read back over the phone / in print.
const String kReferralCodeAlphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// The Firestore collection that stores each user's referral profile.
const String kReferralProfilesCollection = 'referral_profiles';

/// A user's referrer profile — the record that links a Firebase Auth UID to
/// its unique, human-readable referral code and (when the user opts in to
/// share their own rewards) their banking payout details.
///
/// The document id is the user's UID (`referral_profiles/{uid}`), which makes
/// lookups O(1) and guarantees one profile per user by construction. The
/// `referralCode` field is globally unique (enforced by the
/// `referral_code_unique` property, see `firestore.rules`) and
/// case-insensitively compared so `JAG-SPOOR-1` and `jag-spoor-1` collide to
/// the same profile.
class ReferralProfile {
  /// The Firebase Auth UID of the profile owner. Also the Firestore document
  /// id of `referral_profiles/{uid}`.
  final String userId;

  /// The user's unique referral/share code (e.g. `JAGSPOOR7Q3X`). Empty when
  /// the profile has not yet been assigned a code.
  final String referralCode;

  /// Whether the user has shared their banking payout details (Phase 2 wires
  /// the payout claim flow). Defaults to false — a user may refer friends to
  /// give THEM the reward without ever providing banking details.
  final bool bankingDetailsProvided;

  /// The account holder name for reward payouts. Empty when not provided.
  final String bankAccountHolder;

  /// The bank name / institution (e.g. "Standard Bank"). Empty when not
  /// provided.
  final String bankName;

  /// The SARB-compliant 12-digit bank account number. Stored as a string so
  /// leading zeros are never lost. Empty when not provided.
  final String bankAccountNumber;

  /// The branch / account type discriminator (`Current` / `Savings` /
  /// `Transmission`). Empty when not provided.
  final String bankAccountType;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ReferralProfile({
    required this.userId,
    this.referralCode = '',
    this.bankingDetailsProvided = false,
    this.bankAccountHolder = '',
    this.bankName = '',
    this.bankAccountNumber = '',
    this.bankAccountType = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Parses a Firestore document into a [ReferralProfile]. All fields are
  /// alias-tolerant and missing-sensitive fields default to safe empty
  /// values so a partial / legacy doc never throws.
  factory ReferralProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      ReferralProfile.fromMap(doc.data() ?? const <String, dynamic>{},
          id: doc.id);

  /// Snapshot-free map parser (unit-testable without a `DocumentSnapshot`).
  factory ReferralProfile.fromMap(
    Map<String, dynamic> data, {
    required String id,
  }) =>
      ReferralProfile(
        userId: ((data['userId'] as String?) ?? id).trim(),
        referralCode:
            ((data['referralCode'] as String?) ??
                    (data['code'] as String?) ??
                    '')
                .trim()
                .toUpperCase(),
        bankingDetailsProvided:
            data['bankingDetailsProvided'] == true ||
                (data['bankingDetails'] as Map?)?.isNotEmpty == true,
        bankAccountHolder:
            ((data['bankAccountHolder'] as String?) ??
                    (data['bankHolder'] as String?) ??
                    '')
                .trim(),
        bankName: ((data['bankName'] as String?) ?? '').trim(),
        bankAccountNumber:
            ((data['bankAccountNumber'] as String?) ??
                    (data['bankAccountNr'] as String?) ??
                    (data['bankAccountNo'] as String?) ??
                    '')
                .trim(),
        bankAccountType:
            ((data['bankAccountType'] as String?) ??
                    (data['accountType'] as String?) ??
                    '')
                .trim(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );

  /// Firestore-serializable map. Nullable DateTime fields are stored as
  /// `Timestamp`s when present; empty banking fields are omitted so the
  /// document stays clean when no banking details have been provided.
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'referralCode': referralCode,
        'bankingDetailsProvided': bankingDetailsProvided,
        if (bankAccountHolder.isNotEmpty) 'bankAccountHolder': bankAccountHolder,
        if (bankName.isNotEmpty) 'bankName': bankName,
        if (bankAccountNumber.isNotEmpty)
          'bankAccountNumber': bankAccountNumber,
        if (bankAccountType.isNotEmpty) 'bankAccountType': bankAccountType,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  ReferralProfile copyWith({
    String? referralCode,
    bool? bankingDetailsProvided,
    String? bankAccountHolder,
    String? bankName,
    String? bankAccountNumber,
    String? bankAccountType,
    DateTime? updatedAt,
  }) =>
      ReferralProfile(
        userId: userId,
        referralCode: referralCode ?? this.referralCode,
        bankingDetailsProvided:
            bankingDetailsProvided ?? this.bankingDetailsProvided,
        bankAccountHolder: bankAccountHolder ?? this.bankAccountHolder,
        bankName: bankName ?? this.bankName,
        bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
        bankAccountType: bankAccountType ?? this.bankAccountType,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// True when the profile carries a usable referral code.
  bool get hasReferralCode => referralCode.isNotEmpty;

  /// True when the user has provided banking details (name + account number).
  bool get hasPayoutDetails =>
      bankingDetailsProvided &&
      bankAccountHolder.isNotEmpty &&
      bankAccountNumber.isNotEmpty;
}