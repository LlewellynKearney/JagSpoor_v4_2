import 'package:cloud_firestore/cloud_firestore.dart';

/// A predator recorded against a camp.
///
/// Predators never contribute LSU / GU / BU to the veld calculation, so
/// [totalLsu] / [totalGu] / [totalBu] are always `0.0`. Their prey impact is
/// reported through [preyKgPerYear] and [preyAnimalsPerYear].
class PredatorEntry {
  PredatorEntry({
    required this.id,
    required this.campId,
    required this.predatorName,
    int count = 0,
    this.dailyIntakeKg = 0.0,
    this.avgPreyWeightKg = defaultAvgPreyWeightKg,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : count = _safeCount(count),
        preyKgPerYear = _safeCount(count) * dailyIntakeKg * daysPerYear,
        preyAnimalsPerYear = avgPreyWeightKg > 0
            ? (_safeCount(count) * dailyIntakeKg * daysPerYear) /
                avgPreyWeightKg
            : 0.0,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static const double defaultAvgPreyWeightKg = 50.0;
  static const double daysPerYear = 365.0;

  final String id;
  final String campId;
  final String predatorName;
  final int count;
  final double dailyIntakeKg;
  final double preyKgPerYear;
  final double preyAnimalsPerYear;
  final double avgPreyWeightKg;

  /// Always `0.0` — predators are not counted against veld capacity.
  final double totalLsu = 0.0;

  /// Always `0.0` — predators are not counted against veld capacity.
  final double totalGu = 0.0;

  /// Always `0.0` — predators are not counted against veld capacity.
  final double totalBu = 0.0;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory PredatorEntry.fromMap(Map<String, dynamic> map, {String? id}) {
    return PredatorEntry(
      id: id ?? _toStr(map['id']),
      campId: _toStr(map['campId']),
      predatorName: _toStr(map['predatorName']),
      count: _toInt(map['count']),
      dailyIntakeKg: _toDouble(map['dailyIntakeKg']),
      avgPreyWeightKg: _toDoubleOrNull(map['avgPreyWeightKg']) ??
          defaultAvgPreyWeightKg,
      createdAt: _parseDateOrNull(map['createdAt']),
      updatedAt: _parseDateOrNull(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'campId': campId,
        'predatorName': predatorName,
        'count': count,
        'dailyIntakeKg': dailyIntakeKg,
        'preyKgPerYear': preyKgPerYear,
        'preyAnimalsPerYear': preyAnimalsPerYear,
        'avgPreyWeightKg': avgPreyWeightKg,
        'totalLsu': totalLsu,
        'totalGu': totalGu,
        'totalBu': totalBu,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  PredatorEntry copyWith({
    String? id,
    String? campId,
    String? predatorName,
    int? count,
    double? dailyIntakeKg,
    double? avgPreyWeightKg,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PredatorEntry(
        id: id ?? this.id,
        campId: campId ?? this.campId,
        predatorName: predatorName ?? this.predatorName,
        count: count ?? this.count,
        dailyIntakeKg: dailyIntakeKg ?? this.dailyIntakeKg,
        avgPreyWeightKg: avgPreyWeightKg ?? this.avgPreyWeightKg,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is PredatorEntry &&
      other.id == id &&
      other.campId == campId &&
      other.predatorName == predatorName &&
      other.count == count &&
      other.dailyIntakeKg == dailyIntakeKg &&
      other.preyKgPerYear == preyKgPerYear &&
      other.preyAnimalsPerYear == preyAnimalsPerYear &&
      other.avgPreyWeightKg == avgPreyWeightKg &&
      other.totalLsu == totalLsu &&
      other.totalGu == totalGu &&
      other.totalBu == totalBu &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        campId,
        predatorName,
        count,
        dailyIntakeKg,
        preyKgPerYear,
        preyAnimalsPerYear,
        avgPreyWeightKg,
        totalLsu,
        totalGu,
        totalBu,
        createdAt,
        updatedAt,
      ]);
}

int _safeCount(int value) => value < 0 ? 0 : value;

String _toStr(Object? value) => value?.toString() ?? '';

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
