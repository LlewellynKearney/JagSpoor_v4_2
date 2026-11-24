import 'package:cloud_firestore/cloud_firestore.dart';

/// A veld camp on an outfitter farm.
///
/// [lat] / [lng] exist for internal mapping only and must NEVER be shown on a
/// hunter-facing screen.
class Camp {
  Camp({
    required this.id,
    required this.farmId,
    required this.name,
    required this.totalSizeHa,
    required this.province,
    required this.district,
    this.nearestTown,
    this.lat,
    this.lng,
    this.locationAccuracyM,
    this.locationUpdatedAt,
    this.locationSource = locationSourceManual,
    required this.veldType,
    this.veldCondition = veldConditionGood,
    this.deptNormHaPerLsu = 1.0,
    double? effectiveHaPerLsu,
    this.rainfallMmPerYear,
    this.notes,
    List<String>? allowedHunterUids,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : effectiveHaPerLsu = effectiveHaPerLsu ?? deptNormHaPerLsu,
        allowedHunterUids = List<String>.unmodifiable(
            normalizeAllowedHunterUids(allowedHunterUids)),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static const String locationSourceGps = 'gps';
  static const String locationSourceManual = 'manual';

  /// Document field holding the denormalised hunter allow-list.
  ///
  /// Kept in sync by `VeldCarryRepository.syncAllowedHuntersForFarm` and read
  /// by the go-live Firestore rule (`request.auth.uid in
  /// resource.data.allowedHunterUids`). It exists so the rules CAN enforce the
  /// booking relationship — a rule may not read the `bookings` collection.
  static const String allowedHunterUidsField = 'allowedHunterUids';

  /// Normalises an allow-list: trims, drops blanks, de-duplicates, and returns
  /// a stable (first-seen) order.
  ///
  /// Accepts any stored shape so a malformed document can never throw: a
  /// missing / non-list / non-string value resolves to an empty list (which the
  /// rule then treats as "no hunter access"); a lone string is one uid.
  ///
  /// Pure so the union semantics the rule depends on are unit-testable.
  static List<String> normalizeAllowedHunterUids(Object? raw) {
    if (raw == null) return const <String>[];
    final values = raw is Iterable
        ? raw
        : raw is String
            ? <Object?>[raw]
            : const <Object?>[];
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final uid = (value ?? '').toString().trim();
      if (uid.isEmpty) continue;
      if (seen.add(uid)) result.add(uid);
    }
    return result;
  }

  static const String veldConditionGood = 'good';
  static const String veldConditionFair = 'fair';
  static const String veldConditionPoor = 'poor';

  final String id;
  final String farmId;
  final String name;
  final double totalSizeHa;
  final String province;
  final String district;
  final String? nearestTown;

  /// Internal only — never render on a hunter-facing screen.
  final double? lat;

  /// Internal only — never render on a hunter-facing screen.
  final double? lng;

  final double? locationAccuracyM;
  final DateTime? locationUpdatedAt;
  final String locationSource;
  final String veldType;
  final String veldCondition;
  final double deptNormHaPerLsu;
  final double effectiveHaPerLsu;
  final double? rainfallMmPerYear;
  final String? notes;

  /// Hunters allowed veld access by the go-live Firestore rule, denormalised
  /// onto the camp because a rule cannot read the `bookings` collection.
  ///
  /// Empty means "no hunter has confirmed access" — the rule then denies every
  /// non-owner read (fail closed).
  final List<String> allowedHunterUids;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Normalises the location source to `gps` / `manual` (default `manual`).
  static String normalizeLocationSource(Object? value) {
    final source = (value ?? '').toString().trim().toLowerCase();
    return source == locationSourceGps ? locationSourceGps : locationSourceManual;
  }

  /// Normalises the veld condition to `good` / `fair` / `poor` (default `good`).
  static String normalizeVeldCondition(Object? value) {
    final condition = (value ?? '').toString().trim().toLowerCase();
    switch (condition) {
      case veldConditionGood:
      case veldConditionFair:
      case veldConditionPoor:
        return condition;
      default:
        return veldConditionGood;
    }
  }

  factory Camp.fromMap(Map<String, dynamic> map, {String? id}) {
    final deptNorm = _toDouble(map['deptNormHaPerLsu'], 1.0);
    return Camp(
      id: id ?? _toStr(map['id']),
      farmId: _toStr(map['farmId']),
      name: _toStr(map['name']),
      totalSizeHa: _toDouble(map['totalSizeHa']),
      province: _toStr(map['province']),
      district: _toStr(map['district']),
      nearestTown: _optStr(map['nearestTown']),
      lat: _toDoubleOrNull(map['lat']),
      lng: _toDoubleOrNull(map['lng']),
      locationAccuracyM: _toDoubleOrNull(map['locationAccuracyM']),
      locationUpdatedAt: _parseDateOrNull(map['locationUpdatedAt']),
      locationSource: normalizeLocationSource(map['locationSource']),
      veldType: _toStr(map['veldType']),
      veldCondition: normalizeVeldCondition(map['veldCondition']),
      deptNormHaPerLsu: deptNorm,
      effectiveHaPerLsu: _toDoubleOrNull(map['effectiveHaPerLsu']) ?? deptNorm,
      rainfallMmPerYear: _toDoubleOrNull(map['rainfallMmPerYear']),
      notes: _optStr(map['notes']),
      allowedHunterUids:
          normalizeAllowedHunterUids(map[allowedHunterUidsField]),
      createdAt: _parseDateOrNull(map['createdAt']),
      updatedAt: _parseDateOrNull(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'farmId': farmId,
        'name': name,
        'totalSizeHa': totalSizeHa,
        'province': province,
        'district': district,
        if (nearestTown != null) 'nearestTown': nearestTown,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (locationAccuracyM != null) 'locationAccuracyM': locationAccuracyM,
        if (locationUpdatedAt != null)
          'locationUpdatedAt': Timestamp.fromDate(locationUpdatedAt!),
        'locationSource': locationSource,
        'veldType': veldType,
        'veldCondition': veldCondition,
        'deptNormHaPerLsu': deptNormHaPerLsu,
        'effectiveHaPerLsu': effectiveHaPerLsu,
        if (rainfallMmPerYear != null) 'rainfallMmPerYear': rainfallMmPerYear,
        if (notes != null) 'notes': notes,
        // Written only when non-empty so a camp edit (which builds a fresh
        // `Camp` from the form) can never wipe a synced allow-list. The
        // repository writes the list explicitly, including `[]`, when it syncs.
        if (allowedHunterUids.isNotEmpty)
          allowedHunterUidsField: allowedHunterUids,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  Camp copyWith({
    String? id,
    String? farmId,
    String? name,
    double? totalSizeHa,
    String? province,
    String? district,
    String? nearestTown,
    double? lat,
    double? lng,
    double? locationAccuracyM,
    DateTime? locationUpdatedAt,
    String? locationSource,
    String? veldType,
    String? veldCondition,
    double? deptNormHaPerLsu,
    double? effectiveHaPerLsu,
    double? rainfallMmPerYear,
    String? notes,
    List<String>? allowedHunterUids,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Camp(
        id: id ?? this.id,
        farmId: farmId ?? this.farmId,
        name: name ?? this.name,
        totalSizeHa: totalSizeHa ?? this.totalSizeHa,
        province: province ?? this.province,
        district: district ?? this.district,
        nearestTown: nearestTown ?? this.nearestTown,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        locationAccuracyM: locationAccuracyM ?? this.locationAccuracyM,
        locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
        locationSource: locationSource ?? this.locationSource,
        veldType: veldType ?? this.veldType,
        veldCondition: veldCondition ?? this.veldCondition,
        deptNormHaPerLsu: deptNormHaPerLsu ?? this.deptNormHaPerLsu,
        effectiveHaPerLsu: effectiveHaPerLsu ?? this.effectiveHaPerLsu,
        rainfallMmPerYear: rainfallMmPerYear ?? this.rainfallMmPerYear,
        notes: notes ?? this.notes,
        allowedHunterUids: allowedHunterUids ?? this.allowedHunterUids,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Camp &&
      other.id == id &&
      other.farmId == farmId &&
      other.name == name &&
      other.totalSizeHa == totalSizeHa &&
      other.province == province &&
      other.district == district &&
      other.nearestTown == nearestTown &&
      other.lat == lat &&
      other.lng == lng &&
      other.locationAccuracyM == locationAccuracyM &&
      other.locationUpdatedAt == locationUpdatedAt &&
      other.locationSource == locationSource &&
      other.veldType == veldType &&
      other.veldCondition == veldCondition &&
      other.deptNormHaPerLsu == deptNormHaPerLsu &&
      other.effectiveHaPerLsu == effectiveHaPerLsu &&
      other.rainfallMmPerYear == rainfallMmPerYear &&
      other.notes == notes &&
      _sameUids(other.allowedHunterUids, allowedHunterUids) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        farmId,
        name,
        totalSizeHa,
        province,
        district,
        nearestTown,
        lat,
        lng,
        locationAccuracyM,
        locationUpdatedAt,
        locationSource,
        veldType,
        veldCondition,
        deptNormHaPerLsu,
        effectiveHaPerLsu,
        rainfallMmPerYear,
        notes,
        Object.hashAll(allowedHunterUids),
        createdAt,
        updatedAt,
      ]);
}

/// Order-insensitive list equality for the allow-list (the rule treats it as a
/// set).
bool _sameUids(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (final uid in a) {
    if (!b.contains(uid)) return false;
  }
  return true;
}

String _toStr(Object? value) => value?.toString() ?? '';

String? _optStr(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _toDouble(Object? value, [double fallback = 0.0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

double? _toDoubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
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
