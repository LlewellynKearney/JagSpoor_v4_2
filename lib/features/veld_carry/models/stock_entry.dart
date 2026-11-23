import 'package:cloud_firestore/cloud_firestore.dart';

/// One species row inside a camp's stock ledger.
///
/// Grazer/browser split only applies to counted species. [isCounted] is
/// `false` for Baboon / Vervet / Porcupine / Aardvark: those are recorded for
/// information but never contribute LSU / GU / BU to the veld calculation.
class StockEntry {
  factory StockEntry({
    required String id,
    required String campId,
    required String speciesName,
    String? scientificName,
    String feedingClass = feedingClassMixed,
    int count = 0,
    double avgWeightKg = 0.0,
    double? grazerPct,
    double? browserPct,
    bool? isOmnivore,
    bool? isCounted,
    double lsuPerAnimal = 0.0,
    double guPerAnimal = 0.0,
    double buPerAnimal = 0.0,
    double? totalWeightKg,
    double? totalLsu,
    double? totalGu,
    double? totalBu,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final normalisedClass = normalizeFeedingClass(feedingClass);
    final omnivore = isOmnivore ?? normalisedClass == feedingClassOmnivore;
    final counted = isCounted ?? isCountedSpecies(speciesName);
    final safeCount = _safeCount(count);
    final grazer = _clamp01(
      grazerPct ?? _defaultGrazerPct(normalisedClass, omnivore),
    );
    final browser = _clamp01(browserPct ?? (omnivore ? 0.0 : 1.0 - grazer));

    return StockEntry._(
      id: id,
      campId: campId,
      speciesName: speciesName,
      scientificName: _optStr(scientificName),
      feedingClass: normalisedClass,
      count: safeCount,
      avgWeightKg: avgWeightKg,
      grazerPct: grazer,
      browserPct: browser,
      isOmnivore: omnivore,
      isCounted: counted,
      lsuPerAnimal: lsuPerAnimal,
      guPerAnimal: guPerAnimal,
      buPerAnimal: buPerAnimal,
      totalWeightKg: counted ? (totalWeightKg ?? safeCount * avgWeightKg) : 0.0,
      totalLsu: counted ? (totalLsu ?? safeCount * lsuPerAnimal) : 0.0,
      totalGu: counted ? (totalGu ?? safeCount * guPerAnimal) : 0.0,
      totalBu: counted ? (totalBu ?? safeCount * buPerAnimal) : 0.0,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  const StockEntry._({
    required this.id,
    required this.campId,
    required this.speciesName,
    required this.scientificName,
    required this.feedingClass,
    required this.count,
    required this.avgWeightKg,
    required this.grazerPct,
    required this.browserPct,
    required this.isOmnivore,
    required this.isCounted,
    required this.lsuPerAnimal,
    required this.guPerAnimal,
    required this.buPerAnimal,
    required this.totalWeightKg,
    required this.totalLsu,
    required this.totalGu,
    required this.totalBu,
    required this.createdAt,
    required this.updatedAt,
  });

  static const String feedingClassGrazer = 'grazer';
  static const String feedingClassBrowser = 'browser';
  static const String feedingClassMixed = 'mixed';
  static const String feedingClassOmnivore = 'omnivore';

  static const List<String> feedingClasses = [
    feedingClassGrazer,
    feedingClassBrowser,
    feedingClassMixed,
    feedingClassOmnivore,
  ];

  /// Species that are never counted against veld capacity.
  static const List<String> nonCountedSpeciesKeywords = [
    'baboon',
    'vervet',
    'porcupine',
    'aardvark',
  ];

  /// Document id — the species id.
  final String id;
  final String campId;
  final String speciesName;
  final String? scientificName;
  final String feedingClass;
  final int count;
  final double avgWeightKg;
  final double grazerPct;
  final double browserPct;
  final bool isOmnivore;
  final bool isCounted;
  final double lsuPerAnimal;
  final double guPerAnimal;
  final double buPerAnimal;
  final double totalWeightKg;
  final double totalLsu;
  final double totalGu;
  final double totalBu;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Normalises the feeding class (default `mixed`).
  static String normalizeFeedingClass(Object? value) {
    final feeding = (value ?? '').toString().trim().toLowerCase();
    switch (feeding) {
      case feedingClassGrazer:
      case feedingClassBrowser:
      case feedingClassMixed:
      case feedingClassOmnivore:
        return feeding;
      default:
        return feedingClassMixed;
    }
  }

  /// `false` for Baboon / Vervet / Porcupine / Aardvark, `true` otherwise.
  static bool isCountedSpecies(String? speciesName) {
    final name = (speciesName ?? '').trim().toLowerCase();
    if (name.isEmpty) return true;
    for (final keyword in nonCountedSpeciesKeywords) {
      if (name.contains(keyword)) return false;
    }
    return true;
  }

  factory StockEntry.fromMap(Map<String, dynamic> map, {String? id}) {
    final rawOmnivore = map['isOmnivore'];
    final rawCounted = map['isCounted'];
    return StockEntry(
      id: id ?? _toStr(map['id']),
      campId: _toStr(map['campId']),
      speciesName: _toStr(map['speciesName']),
      scientificName: _optStr(map['scientificName']),
      feedingClass: map['feedingClass']?.toString() ?? feedingClassMixed,
      count: _toInt(map['count']),
      avgWeightKg: _toDouble(map['avgWeightKg']),
      grazerPct: _toDoubleOrNull(map['grazerPct']),
      browserPct: _toDoubleOrNull(map['browserPct']),
      isOmnivore: rawOmnivore is bool ? rawOmnivore : null,
      isCounted: rawCounted is bool ? rawCounted : null,
      lsuPerAnimal: _toDouble(map['lsuPerAnimal']),
      guPerAnimal: _toDouble(map['guPerAnimal']),
      buPerAnimal: _toDouble(map['buPerAnimal']),
      totalWeightKg: _toDoubleOrNull(map['totalWeightKg']),
      totalLsu: _toDoubleOrNull(map['totalLsu']),
      totalGu: _toDoubleOrNull(map['totalGu']),
      totalBu: _toDoubleOrNull(map['totalBu']),
      createdAt: _parseDateOrNull(map['createdAt']),
      updatedAt: _parseDateOrNull(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'campId': campId,
        'speciesName': speciesName,
        if (scientificName != null) 'scientificName': scientificName,
        'feedingClass': feedingClass,
        'count': count,
        'avgWeightKg': avgWeightKg,
        'grazerPct': grazerPct,
        'browserPct': browserPct,
        'isOmnivore': isOmnivore,
        'isCounted': isCounted,
        'lsuPerAnimal': lsuPerAnimal,
        'guPerAnimal': guPerAnimal,
        'buPerAnimal': buPerAnimal,
        'totalWeightKg': totalWeightKg,
        'totalLsu': totalLsu,
        'totalGu': totalGu,
        'totalBu': totalBu,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  StockEntry copyWith({
    String? id,
    String? campId,
    String? speciesName,
    String? scientificName,
    String? feedingClass,
    int? count,
    double? avgWeightKg,
    double? grazerPct,
    double? browserPct,
    bool? isOmnivore,
    bool? isCounted,
    double? lsuPerAnimal,
    double? guPerAnimal,
    double? buPerAnimal,
    double? totalWeightKg,
    double? totalLsu,
    double? totalGu,
    double? totalBu,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      StockEntry(
        id: id ?? this.id,
        campId: campId ?? this.campId,
        speciesName: speciesName ?? this.speciesName,
        scientificName: scientificName ?? this.scientificName,
        feedingClass: feedingClass ?? this.feedingClass,
        count: count ?? this.count,
        avgWeightKg: avgWeightKg ?? this.avgWeightKg,
        grazerPct: grazerPct ?? this.grazerPct,
        browserPct: browserPct ?? this.browserPct,
        isOmnivore: isOmnivore ?? this.isOmnivore,
        isCounted: isCounted ?? this.isCounted,
        lsuPerAnimal: lsuPerAnimal ?? this.lsuPerAnimal,
        guPerAnimal: guPerAnimal ?? this.guPerAnimal,
        buPerAnimal: buPerAnimal ?? this.buPerAnimal,
        totalWeightKg: totalWeightKg ?? this.totalWeightKg,
        totalLsu: totalLsu ?? this.totalLsu,
        totalGu: totalGu ?? this.totalGu,
        totalBu: totalBu ?? this.totalBu,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is StockEntry &&
      other.id == id &&
      other.campId == campId &&
      other.speciesName == speciesName &&
      other.scientificName == scientificName &&
      other.feedingClass == feedingClass &&
      other.count == count &&
      other.avgWeightKg == avgWeightKg &&
      other.grazerPct == grazerPct &&
      other.browserPct == browserPct &&
      other.isOmnivore == isOmnivore &&
      other.isCounted == isCounted &&
      other.lsuPerAnimal == lsuPerAnimal &&
      other.guPerAnimal == guPerAnimal &&
      other.buPerAnimal == buPerAnimal &&
      other.totalWeightKg == totalWeightKg &&
      other.totalLsu == totalLsu &&
      other.totalGu == totalGu &&
      other.totalBu == totalBu &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        campId,
        speciesName,
        scientificName,
        feedingClass,
        count,
        avgWeightKg,
        grazerPct,
        browserPct,
        isOmnivore,
        isCounted,
        lsuPerAnimal,
        guPerAnimal,
        buPerAnimal,
        totalWeightKg,
        totalLsu,
        totalGu,
        totalBu,
        createdAt,
        updatedAt,
      ]);
}

int _safeCount(int value) => value < 0 ? 0 : value;

double _clamp01(double value) {
  if (value.isNaN || value.isInfinite) return 0.0;
  if (value < 0.0) return 0.0;
  if (value > 1.0) return 1.0;
  return value;
}

double _defaultGrazerPct(String feedingClass, bool isOmnivore) {
  if (isOmnivore) return 0.0;
  switch (feedingClass) {
    case StockEntry.feedingClassGrazer:
      return 1.0;
    case StockEntry.feedingClassBrowser:
      return 0.0;
    default:
      return 0.5;
  }
}

String _toStr(Object? value) => value?.toString() ?? '';

String? _optStr(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _toInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
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
