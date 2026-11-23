import 'package:cloud_firestore/cloud_firestore.dart';

/// A regulatory / compliance permit attached to a farm.
class FarmPermit {
  FarmPermit({
    required this.id,
    required this.farmId,
    required String permitType,
    required this.permitNumber,
    required this.issuingAuthority,
    required this.province,
    this.issueDate,
    this.expiryDate,
    List<String> speciesCovered = const <String>[],
    List<String> campIds = const <String>[],
    this.fileUrl,
    this.fileName,
    String visibility = visibilityPrivate,
    String? status,
    this.notes = '',
    this.uploadedBy = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : permitType = normalizePermitType(permitType),
        speciesCovered = List<String>.unmodifiable(speciesCovered),
        campIds = List<String>.unmodifiable(campIds),
        visibility = normalizeVisibility(visibility),
        status = _resolveStatus(status, expiryDate),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static const String permitTypeCae = 'CAE';
  static const String permitTypeExemption = 'EXEMPTION';
  static const String permitTypeTops = 'TOPS';
  static const String permitTypeCites = 'CITES';
  static const String permitTypePhLicence = 'PH_LICENCE';
  static const String permitTypeOutfitterReg = 'OUTFITTER_REG';
  static const String permitTypePredatorCaptivity = 'PREDATOR_CAPTIVITY';
  static const String permitTypePredatorFencing = 'PREDATOR_FENCING';
  static const String permitTypeDangerousGameFencing = 'DANGEROUS_GAME_FENCING';
  static const String permitTypeVet = 'VET';
  static const String permitTypeTransport = 'TRANSPORT';
  static const String permitTypeGameMovement = 'GAME_MOVEMENT';
  static const String permitTypeOther = 'OTHER';

  static const List<String> permitTypes = [
    permitTypeCae,
    permitTypeExemption,
    permitTypeTops,
    permitTypeCites,
    permitTypePhLicence,
    permitTypeOutfitterReg,
    permitTypePredatorCaptivity,
    permitTypePredatorFencing,
    permitTypeDangerousGameFencing,
    permitTypeVet,
    permitTypeTransport,
    permitTypeGameMovement,
    permitTypeOther,
  ];

  static const String visibilityHunterVisible = 'hunter_visible';
  static const String visibilityPrivate = 'private';

  static const List<String> visibilities = [
    visibilityHunterVisible,
    visibilityPrivate,
  ];

  static const String permitStatusValid = 'valid';
  static const String permitStatusExpiringSoon = 'expiring_soon';
  static const String permitStatusExpired = 'expired';
  static const String permitStatusNoExpiry = 'no_expiry';

  static const List<String> permitStatuses = [
    permitStatusValid,
    permitStatusExpiringSoon,
    permitStatusExpired,
    permitStatusNoExpiry,
  ];

  /// A permit within this many days of expiry is `expiring_soon`.
  static const int expiringSoonDays = 30;

  final String id;
  final String farmId;
  final String permitType;
  final String permitNumber;
  final String issuingAuthority;
  final String province;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final List<String> speciesCovered;
  final List<String> campIds;
  final String? fileUrl;
  final String? fileName;
  final String visibility;
  final String status;
  final String notes;
  final String uploadedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Normalises the permit type (default `OTHER`).
  static String normalizePermitType(Object? value) {
    final type = (value ?? '').toString().trim().toUpperCase();
    return permitTypes.contains(type) ? type : permitTypeOther;
  }

  /// Normalises visibility (default `private`).
  static String normalizeVisibility(Object? value) {
    final normalised = (value ?? '').toString().trim().toLowerCase();
    return normalised == visibilityHunterVisible
        ? visibilityHunterVisible
        : visibilityPrivate;
  }

  /// Status implied by [expiryDate] when no explicit status is supplied.
  static String deriveStatus(DateTime? expiryDate, {DateTime? now}) {
    if (expiryDate == null) return permitStatusNoExpiry;
    final reference = now ?? DateTime.now();
    final expiryDay =
        DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final today = DateTime(reference.year, reference.month, reference.day);
    if (expiryDay.isBefore(today)) return permitStatusExpired;
    if (expiryDay.difference(today).inDays <= expiringSoonDays) {
      return permitStatusExpiringSoon;
    }
    return permitStatusValid;
  }

  factory FarmPermit.fromMap(Map<String, dynamic> map, {String? id}) {
    return FarmPermit(
      id: id ?? _toStr(map['id']),
      farmId: _toStr(map['farmId']),
      permitType: map['permitType']?.toString() ?? permitTypeOther,
      permitNumber: _toStr(map['permitNumber']),
      issuingAuthority: _toStr(map['issuingAuthority']),
      province: _toStr(map['province']),
      issueDate: _parseDateOrNull(map['issueDate']),
      expiryDate: _parseDateOrNull(map['expiryDate']),
      speciesCovered: _stringList(map['speciesCovered']),
      campIds: _stringList(map['campIds']),
      fileUrl: _optStr(map['fileUrl']),
      fileName: _optStr(map['fileName']),
      visibility: map['visibility']?.toString() ?? visibilityPrivate,
      status: map['status']?.toString(),
      notes: map['notes']?.toString() ?? '',
      uploadedBy: map['uploadedBy']?.toString() ?? '',
      createdAt: _parseDateOrNull(map['createdAt']),
      updatedAt: _parseDateOrNull(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'farmId': farmId,
        'permitType': permitType,
        'permitNumber': permitNumber,
        'issuingAuthority': issuingAuthority,
        'province': province,
        if (issueDate != null) 'issueDate': Timestamp.fromDate(issueDate!),
        if (expiryDate != null) 'expiryDate': Timestamp.fromDate(expiryDate!),
        'speciesCovered': speciesCovered,
        'campIds': campIds,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (fileName != null) 'fileName': fileName,
        'visibility': visibility,
        'status': status,
        'notes': notes,
        'uploadedBy': uploadedBy,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  FarmPermit copyWith({
    String? id,
    String? farmId,
    String? permitType,
    String? permitNumber,
    String? issuingAuthority,
    String? province,
    DateTime? issueDate,
    DateTime? expiryDate,
    List<String>? speciesCovered,
    List<String>? campIds,
    String? fileUrl,
    String? fileName,
    String? visibility,
    String? status,
    String? notes,
    String? uploadedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      FarmPermit(
        id: id ?? this.id,
        farmId: farmId ?? this.farmId,
        permitType: permitType ?? this.permitType,
        permitNumber: permitNumber ?? this.permitNumber,
        issuingAuthority: issuingAuthority ?? this.issuingAuthority,
        province: province ?? this.province,
        issueDate: issueDate ?? this.issueDate,
        expiryDate: expiryDate ?? this.expiryDate,
        speciesCovered: speciesCovered ?? this.speciesCovered,
        campIds: campIds ?? this.campIds,
        fileUrl: fileUrl ?? this.fileUrl,
        fileName: fileName ?? this.fileName,
        visibility: visibility ?? this.visibility,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        uploadedBy: uploadedBy ?? this.uploadedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is FarmPermit &&
      other.id == id &&
      other.farmId == farmId &&
      other.permitType == permitType &&
      other.permitNumber == permitNumber &&
      other.issuingAuthority == issuingAuthority &&
      other.province == province &&
      other.issueDate == issueDate &&
      other.expiryDate == expiryDate &&
      _listEquals(other.speciesCovered, speciesCovered) &&
      _listEquals(other.campIds, campIds) &&
      other.fileUrl == fileUrl &&
      other.fileName == fileName &&
      other.visibility == visibility &&
      other.status == status &&
      other.notes == notes &&
      other.uploadedBy == uploadedBy &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        farmId,
        permitType,
        permitNumber,
        issuingAuthority,
        province,
        issueDate,
        expiryDate,
        Object.hashAll(speciesCovered),
        Object.hashAll(campIds),
        fileUrl,
        fileName,
        visibility,
        status,
        notes,
        uploadedBy,
        createdAt,
        updatedAt,
      ]);
}

String _resolveStatus(String? provided, DateTime? expiryDate) {
  final raw = (provided ?? '').trim().toLowerCase();
  if (FarmPermit.permitStatuses.contains(raw)) return raw;
  return FarmPermit.deriveStatus(expiryDate);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    final result = <String>[];
    for (final item in value) {
      final text = item?.toString().trim() ?? '';
      if (text.isNotEmpty) result.add(text);
    }
    return result;
  }
  return const <String>[];
}

String _toStr(Object? value) => value?.toString() ?? '';

String? _optStr(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _parseDateOrNull(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
  return null;
}
