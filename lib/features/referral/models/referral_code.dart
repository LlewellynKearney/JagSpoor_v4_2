import 'package:cloud_firestore/cloud_firestore.dart';

/// The Firestore collection that maps a human-readable referral CODE to its
/// owner.
///
/// The document id IS the (upper-cased) referral code, so a code → owner
/// lookup is an O(1) direct read rather than a query — which is what the
/// post-Dynamic-Links App Links flow needs: an incoming
/// `https://jagspoor.co.za/r/<CODE>` link resolves its owner without a
/// composite index or a collection scan.
///
/// The parallel `referral_profiles/{uid}` collection remains the per-user
/// record (uid → code + banking details); this collection is the reverse
/// index (code → uid). Both are written together when a profile is created.
const String kReferralCodesCollection = 'referralCodes';

/// A referral code → owner index entry: `referralCodes/{code}`.
class ReferralCode {
  /// The upper-cased referral code. Also the Firestore document id.
  final String code;

  /// The Firebase Auth UID of the code's owner (the referrer).
  final String ownerUid;

  /// How many times the code has been redeemed (best-effort counter).
  final int uses;

  /// Whether the code can still be redeemed. An owner (or an admin) can
  /// deactivate a code without deleting it (preserving the audit trail).
  final bool active;

  final DateTime? createdAt;

  /// The last time the code was redeemed (nullable — may be absent on a
  /// never-used code).
  final DateTime? lastUsedAt;

  const ReferralCode({
    required this.code,
    required this.ownerUid,
    this.uses = 0,
    this.active = true,
    this.createdAt,
    this.lastUsedAt,
  });

  /// Snapshot-free map parser (unit-testable without a `DocumentSnapshot`).
  factory ReferralCode.fromMap(
    Map<String, dynamic> data, {
    required String id,
  }) =>
      ReferralCode(
        code: _cleanCode((data['code'] as String?) ?? id),
        ownerUid: ((data['ownerUid'] as String?) ??
                (data['userId'] as String?) ??
                (data['ownerId'] as String?) ??
                '')
            .trim(),
        uses: _asInt(data['uses']),
        active: data['active'] != false,
        createdAt: _asDate(data['createdAt']),
        lastUsedAt: _asDate(data['lastUsedAt']),
      );

  factory ReferralCode.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      ReferralCode.fromMap(doc.data() ?? const <String, dynamic>{}, id: doc.id);

  /// Firestore-serializable map. The document id carries the code, so it is
  /// also stamped as a field for convenience / admin queries.
  Map<String, dynamic> toMap() => {
        'code': code,
        'ownerUid': ownerUid,
        'uses': uses,
        'active': active,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (lastUsedAt != null) 'lastUsedAt': Timestamp.fromDate(lastUsedAt!),
      };

  ReferralCode copyWith({
    int? uses,
    bool? active,
    DateTime? lastUsedAt,
  }) =>
      ReferralCode(
        code: code,
        ownerUid: ownerUid,
        uses: uses ?? this.uses,
        active: active ?? this.active,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  /// True when the code can currently be redeemed by a new signup.
  bool get isRedeemable => active && ownerUid.isNotEmpty && code.isNotEmpty;

  static String _cleanCode(String? code) =>
      (code ?? '').trim().toUpperCase();

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }
}
