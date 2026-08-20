/// Data model for the legal South African Venison / Game Transport & Hunt Permit.
///
/// Mirrors the official SA statutory template: a hunter authorizes the
/// transport of harvested species (venison/game) from a registered farm, with
/// dual signatures from both the Hunter and the Authorized Person (Outfitter /
/// farm representative) and a full audit trail.
///
/// Persisted to the `venison_permits` Firestore collection. Captured signature
/// PNGs live in Firebase Storage under `permit_signatures/{permitId}/`.
class VenisonTransportPermit {
  final String? id;
  final String permitNumber;

  // ── Issuing parties ──
  final String outfitterId;
  final String? hunterId;

  /// Hunter-user alias stamped alongside [hunterId] so permits written by any
  /// app version (which historically stamped only `userId` on some paths, or
  /// omitted `hunterId` entirely for permits issued without a booking) are
  /// still readable by the designated hunter.
  final String? userId;
  final String? bookingId;

  // ── Hunter block ──
  final String hunterName;
  final String hunterIdNumber;
  final String hunterCell;
  final String hunterAddress;

  // ── Authorized Person / Farm block ──
  final String authorizedPersonName;
  final String farmName;
  final String farmAddress;
  final String farmCell;

  // ── Hunt window ──
  final DateTime? huntStartDate;
  final DateTime? huntEndDate;

  // ── Species hunted and transported ──
  /// List of `{species, quantity, sex?}` entries declared on the permit.
  final List<Map<String, dynamic>> speciesHuntedAndTransported;

  // ── Signatures & audit ──
  final String? hunterSignatureUrl;
  final String? outfitterSignatureUrl;
  final DateTime? hunterSignedDate;
  final DateTime? outfitterSignedDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String status;

  VenisonTransportPermit({
    this.id,
    required this.permitNumber,
    required this.outfitterId,
    this.hunterId,
    this.userId,
    this.bookingId,
    required this.hunterName,
    required this.hunterIdNumber,
    required this.hunterCell,
    required this.hunterAddress,
    required this.authorizedPersonName,
    required this.farmName,
    required this.farmAddress,
    required this.farmCell,
    this.huntStartDate,
    this.huntEndDate,
    required this.speciesHuntedAndTransported,
    this.hunterSignatureUrl,
    this.outfitterSignatureUrl,
    this.hunterSignedDate,
    this.outfitterSignedDate,
    this.createdAt,
    this.updatedAt,
    this.status = 'Issued',
  });

  factory VenisonTransportPermit.fromMap(Map<String, dynamic> map) {
    DateTime? toDate(dynamic v) {
      if (v == null) return null;
      try {
        return v is DateTime ? v : v.toDate();
      } catch (_) {
        return null;
      }
    }

    return VenisonTransportPermit(
      id: map['id'] as String?,
      permitNumber: map['permitNumber'] as String? ?? '',
      outfitterId: map['outfitterId'] as String? ?? '',
      // Alias tolerance: legacy docs may carry only `userId` (or `hunterId`)
      // for the designated hunter. Treat either spelling as the same party so
      // a permit never silently goes unread by the hunter on a key mismatch.
      hunterId: map['hunterId'] as String? ?? map['userId'] as String?,
      userId: map['userId'] as String? ?? map['hunterId'] as String?,
      bookingId: map['bookingId'] as String?,
      hunterName: map['hunterName'] as String? ?? '',
      hunterIdNumber: map['hunterIdNumber'] as String? ?? '',
      hunterCell: map['hunterCell'] as String? ?? '',
      hunterAddress: map['hunterAddress'] as String? ?? '',
      authorizedPersonName: map['authorizedPersonName'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      farmAddress: map['farmAddress'] as String? ?? '',
      farmCell: map['farmCell'] as String? ?? '',
      huntStartDate: toDate(map['huntStartDate']),
      huntEndDate: toDate(map['huntEndDate']),
      speciesHuntedAndTransported:
          (map['speciesHuntedAndTransported'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
      hunterSignatureUrl: map['hunterSignatureUrl'] as String?,
      outfitterSignatureUrl: map['outfitterSignatureUrl'] as String?,
      hunterSignedDate: toDate(map['hunterSignedDate']),
      outfitterSignedDate: toDate(map['outfitterSignedDate']),
      createdAt: toDate(map['createdAt']),
      updatedAt: toDate(map['updatedAt']),
      status: map['status'] as String? ?? 'Issued',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'permitNumber': permitNumber,
      'outfitterId': outfitterId,
      // Dual-stamp BOTH aliases so hunter-side list queries (and the Firestore
      // rules read allowance) match whether they filter on `hunterId` or
      // `userId`.
      if (hunterId != null) 'hunterId': hunterId,
      if (userId != null) 'userId': userId,
      if (bookingId != null) 'bookingId': bookingId,
      'hunterName': hunterName,
      'hunterIdNumber': hunterIdNumber,
      'hunterCell': hunterCell,
      'hunterAddress': hunterAddress,
      'authorizedPersonName': authorizedPersonName,
      'farmName': farmName,
      'farmAddress': farmAddress,
      'farmCell': farmCell,
      if (huntStartDate != null) 'huntStartDate': huntStartDate,
      if (huntEndDate != null) 'huntEndDate': huntEndDate,
      'speciesHuntedAndTransported': speciesHuntedAndTransported,
      if (hunterSignatureUrl != null) 'hunterSignatureUrl': hunterSignatureUrl,
      if (outfitterSignatureUrl != null)
        'outfitterSignatureUrl': outfitterSignatureUrl,
      if (hunterSignedDate != null) 'hunterSignedDate': hunterSignedDate,
      if (outfitterSignedDate != null)
        'outfitterSignedDate': outfitterSignedDate,
      'status': status,
    };
  }

  /// The designated hunter's uid regardless of which alias was stamped on the
  /// document (`hunterId` preferred, `userId` fallback).
  String? get effectiveHunterId => hunterId ?? userId;

  /// True when both parties have signed the permit.
  bool get isFullySigned =>
      (hunterSignatureUrl?.isNotEmpty ?? false) &&
      (outfitterSignatureUrl?.isNotEmpty ?? false);

  /// Comma-separated summary of species for list cards.
  String get speciesSummary {
    if (speciesHuntedAndTransported.isEmpty) return 'No species declared';
    return speciesHuntedAndTransported.map((s) {
      final name = s['species'] ?? 'Unknown';
      final qty = (s['quantity'] as num?)?.toInt() ?? 1;
      final sex = s['sex'];
      return sex != null && sex.toString().isNotEmpty
          ? '$name (${qty}x $sex)'
          : '$name (${qty}x)';
    }).join(', ');
  }
}
