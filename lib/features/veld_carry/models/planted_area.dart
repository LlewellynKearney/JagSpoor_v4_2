import 'package:cloud_firestore/cloud_firestore.dart';

/// A planted (cultivated) area that contributes feed to a camp.
///
/// [lsuPerHa] and [capacityLsu] are derived from [haPerLsu] and [areaHa] and
/// are recomputed on every construction so the invariant cannot drift.
class PlantedArea {
  PlantedArea({
    required this.id,
    required this.campId,
    String feedType = feedTypeOtherCustom,
    this.customName,
    required this.areaHa,
    required this.haPerLsu,
    String season = seasonAllYear,
    this.irrigated = false,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : feedType = normalizeFeedType(feedType),
        season = normalizeSeason(season),
        lsuPerHa = haPerLsu > 0 ? 1.0 / haPerLsu : 0.0,
        capacityLsu = haPerLsu > 0 ? areaHa / haPerLsu : 0.0,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static const String feedTypeLucerneIrrigated = 'LUCERNE_IRRIGATED';
  static const String feedTypeLucerneDryland = 'LUCERNE_DRYLAND';
  static const String feedTypeTeff = 'TEFF';
  static const String feedTypeOats = 'OATS';
  static const String feedTypeOatsVetch = 'OATS_VETCH';
  static const String feedTypeRyegrassPerennial = 'RYEGRASS_PERENNIAL';
  static const String feedTypeRyegrassAnnual = 'RYEGRASS_ANNUAL';
  static const String feedTypeKikuyuIrrigated = 'KIKUYU_IRRIGATED';
  static const String feedTypeKikuyuDryland = 'KIKUYU_DRYLAND';
  static const String feedTypeEragrostis = 'ERAGROSTIS';
  static const String feedTypeSmutsFinger = 'SMUTS_FINGER';
  static const String feedTypeMaizeStover = 'MAIZE_STOVER';
  static const String feedTypeSorghum = 'SORGHUM';
  static const String feedTypeOtherCustom = 'OTHER_CUSTOM';

  static const List<String> feedTypes = [
    feedTypeLucerneIrrigated,
    feedTypeLucerneDryland,
    feedTypeTeff,
    feedTypeOats,
    feedTypeOatsVetch,
    feedTypeRyegrassPerennial,
    feedTypeRyegrassAnnual,
    feedTypeKikuyuIrrigated,
    feedTypeKikuyuDryland,
    feedTypeEragrostis,
    feedTypeSmutsFinger,
    feedTypeMaizeStover,
    feedTypeSorghum,
    feedTypeOtherCustom,
  ];

  static const String seasonAllYear = 'ALL_YEAR';
  static const String seasonSummer = 'SUMMER';
  static const String seasonWinter = 'WINTER';

  static const List<String> seasons = [
    seasonAllYear,
    seasonSummer,
    seasonWinter,
  ];

  final String id;
  final String campId;
  final String feedType;
  final String? customName;
  final double areaHa;
  final double haPerLsu;
  final double lsuPerHa;
  final String season;
  final bool irrigated;
  final double capacityLsu;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Normalises the feed type (default `OTHER_CUSTOM`).
  static String normalizeFeedType(Object? value) {
    final type = (value ?? '').toString().trim().toUpperCase();
    return feedTypes.contains(type) ? type : feedTypeOtherCustom;
  }

  /// Normalises the season (default `ALL_YEAR`).
  static String normalizeSeason(Object? value) {
    final normalised = (value ?? '').toString().trim().toUpperCase();
    switch (normalised) {
      case seasonAllYear:
      case seasonSummer:
      case seasonWinter:
        return normalised;
      default:
        return seasonAllYear;
    }
  }

  factory PlantedArea.fromMap(Map<String, dynamic> map, {String? id}) {
    final rawIrrigated = map['irrigated'];
    return PlantedArea(
      id: id ?? _toStr(map['id']),
      campId: _toStr(map['campId']),
      feedType: map['feedType']?.toString() ?? feedTypeOtherCustom,
      customName: _optStr(map['customName']),
      areaHa: _toDouble(map['areaHa']),
      haPerLsu: _toDouble(map['haPerLsu']),
      season: map['season']?.toString() ?? seasonAllYear,
      irrigated: rawIrrigated is bool ? rawIrrigated : false,
      notes: map['notes']?.toString() ?? '',
      createdAt: _parseDateOrNull(map['createdAt']),
      updatedAt: _parseDateOrNull(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'campId': campId,
        'feedType': feedType,
        if (customName != null) 'customName': customName,
        'areaHa': areaHa,
        'haPerLsu': haPerLsu,
        'lsuPerHa': lsuPerHa,
        'season': season,
        'irrigated': irrigated,
        'capacityLsu': capacityLsu,
        'notes': notes,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  PlantedArea copyWith({
    String? id,
    String? campId,
    String? feedType,
    String? customName,
    double? areaHa,
    double? haPerLsu,
    String? season,
    bool? irrigated,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PlantedArea(
        id: id ?? this.id,
        campId: campId ?? this.campId,
        feedType: feedType ?? this.feedType,
        customName: customName ?? this.customName,
        areaHa: areaHa ?? this.areaHa,
        haPerLsu: haPerLsu ?? this.haPerLsu,
        season: season ?? this.season,
        irrigated: irrigated ?? this.irrigated,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is PlantedArea &&
      other.id == id &&
      other.campId == campId &&
      other.feedType == feedType &&
      other.customName == customName &&
      other.areaHa == areaHa &&
      other.haPerLsu == haPerLsu &&
      other.lsuPerHa == lsuPerHa &&
      other.season == season &&
      other.irrigated == irrigated &&
      other.capacityLsu == capacityLsu &&
      other.notes == notes &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        campId,
        feedType,
        customName,
        areaHa,
        haPerLsu,
        lsuPerHa,
        season,
        irrigated,
        capacityLsu,
        notes,
        createdAt,
        updatedAt,
      ]);
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
