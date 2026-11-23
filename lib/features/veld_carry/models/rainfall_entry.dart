import 'package:cloud_firestore/cloud_firestore.dart';

/// One month of recorded rainfall for a camp.
///
/// The document id IS the month key (`2026-11`), so saving the same month twice
/// **overwrites** the existing entry instead of creating a duplicate — the camp
/// can only ever hold one figure per month.
///
/// [month] is always `YYYY-MM`; [isValidMonth] is the single validation rule
/// shared by the model, the repository and the form. Rainfall is a measurement,
/// never a computed capacity figure, so the totals live in
/// `veld_carry_calculator.dart` with the rest of the feature's arithmetic.
class RainfallEntry {
  factory RainfallEntry({
    required String id,
    required String farmId,
    required String campId,
    required String month,
    double rainfallMm = 0.0,
    String? recordedBy,
    DateTime? recordedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final key = month.trim();
    return RainfallEntry._(
      id: id.trim().isEmpty ? key : id.trim(),
      farmId: farmId.trim(),
      campId: campId.trim(),
      month: key,
      rainfallMm: _finiteMm(rainfallMm),
      recordedBy: _optStr(recordedBy),
      recordedAt: recordedAt ?? DateTime.now(),
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  const RainfallEntry._({
    required this.id,
    required this.farmId,
    required this.campId,
    required this.month,
    required this.rainfallMm,
    required this.recordedBy,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// `YYYY-MM`, e.g. `2026-11`.
  static final RegExp monthPattern = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$');

  /// Document id — the month key.
  final String id;
  final String farmId;
  final String campId;

  /// `YYYY-MM`.
  final String month;

  /// Millimetres recorded for [month]; never negative.
  final double rainfallMm;
  final String? recordedBy;
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The calendar year of [month], or null when [month] is malformed.
  int? get year {
    final match = monthPattern.firstMatch(month);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  /// The month number (1–12) of [month], or null when malformed.
  int? get monthNumber {
    final match = monthPattern.firstMatch(month);
    if (match == null) return null;
    return int.tryParse(match.group(2) ?? '');
  }

  /// `2026-11` -> `Nov 2026`, or the raw value when malformed.
  String get monthLabel {
    final year = this.year;
    final monthNumber = this.monthNumber;
    if (year == null || monthNumber == null) return month;
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${names[monthNumber - 1]} $year';
  }

  /// `true` when [value] is a `YYYY-MM` key with a real month (01–12).
  static bool isValidMonth(String? value) =>
      monthPattern.hasMatch((value ?? '').trim());

  /// Normalises [value] to a `YYYY-MM` key, or null when it is not one.
  static String? normalizeMonth(Object? value) {
    final text = (value ?? '').toString().trim();
    return isValidMonth(text) ? text : null;
  }

  /// `2026-11-23` -> `2026-11`.
  static String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  /// The [count] months ending at [now], newest first.
  ///
  /// Used by the rainfall screen's 12-month list and the trailing total.
  static List<String> recentMonths(DateTime now, {int count = 12}) {
    if (count <= 0) return const <String>[];
    final months = <String>[];
    var year = now.year;
    var month = now.month;
    for (var i = 0; i < count; i++) {
      months.add('${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}');
      month -= 1;
      if (month == 0) {
        month = 12;
        year -= 1;
      }
    }
    return months;
  }

  /// The first thing wrong with this entry, or null when it is valid.
  String? get validationError {
    if (farmId.isEmpty) return 'Farm id is required.';
    if (campId.isEmpty) return 'Camp id is required.';
    if (!isValidMonth(month)) {
      return 'Choose a valid month (expected YYYY-MM).';
    }
    if (!rainfallMm.isFinite || rainfallMm < 0) {
      return 'Rainfall must be zero or more millimetres.';
    }
    return null;
  }

  /// `true` when [validationError] is null.
  bool get isValid => validationError == null;

  factory RainfallEntry.fromMap(Map<String, dynamic> map, {String? id}) {
    final month = _toStr(map['month']);
    return RainfallEntry(
      id: id ?? _toStr(map['id']),
      farmId: _toStr(map['farmId']),
      campId: _toStr(map['campId']),
      month: month,
      rainfallMm: _toDouble(map['rainfallMm']),
      recordedBy: _optStr(map['recordedBy']),
      recordedAt: _parseDateOrNull(map['recordedAt']),
      createdAt: _parseDateOrNull(map['createdAt']),
      updatedAt: _parseDateOrNull(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'farmId': farmId,
        'campId': campId,
        'month': month,
        'rainfallMm': rainfallMm,
        if (recordedBy != null) 'recordedBy': recordedBy,
        'recordedAt': Timestamp.fromDate(recordedAt),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  RainfallEntry copyWith({
    String? id,
    String? farmId,
    String? campId,
    String? month,
    double? rainfallMm,
    String? recordedBy,
    DateTime? recordedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      RainfallEntry(
        id: id ?? this.id,
        farmId: farmId ?? this.farmId,
        campId: campId ?? this.campId,
        month: month ?? this.month,
        rainfallMm: rainfallMm ?? this.rainfallMm,
        recordedBy: recordedBy ?? this.recordedBy,
        recordedAt: recordedAt ?? this.recordedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is RainfallEntry &&
      other.id == id &&
      other.farmId == farmId &&
      other.campId == campId &&
      other.month == month &&
      other.rainfallMm == rainfallMm &&
      other.recordedBy == recordedBy &&
      other.recordedAt == recordedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        farmId,
        campId,
        month,
        rainfallMm,
        recordedBy,
        recordedAt,
        createdAt,
        updatedAt,
      ]);

  @override
  String toString() => 'RainfallEntry($month ${rainfallMm}mm)';
}

/// A non-finite figure is stored as 0; a NEGATIVE figure is stored as given so
/// [RainfallEntry.validationError] can reject it instead of silently coercing a
/// typo to zero.
double _finiteMm(double value) => value.isFinite ? value : 0.0;

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
