import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';

/// One recorded change to a camp's stock ledger.
///
/// The camp's [StockEntry] rows are a *snapshot*; a [StockMovement] is the
/// audit trail that explains how that snapshot got there. The two are always
/// written together — the repository applies [campDeltas] to the affected
/// stock rows and writes this record in the SAME transaction, so history and
/// stock can never drift apart.
///
/// ## Signed count
///
/// [count] is **signed**: positive means animals came in, negative means they
/// went out. The sign is not free-form — it is dictated by [movementType]
/// (see [isSignValid]) so a caller can never record `hunted +3`:
///
/// | movementType       | sign     | camps touched            |
/// |--------------------|----------|--------------------------|
/// | `added`            | positive | [campId] only            |
/// | `moved_in`         | positive | [fromCampId] and [toCampId] |
/// | `moved_out`        | negative | [fromCampId] and [toCampId] |
/// | `hunted`           | negative | [campId] only            |
/// | `died`             | negative | [campId] only            |
/// | `sold`             | negative | [campId] only            |
/// | `count_adjustment` | either   | [campId] only            |
///
/// A movement may never take a camp's count below zero. That is enforced by
/// [applyDeltaToStockEntry] (pure) and re-checked inside the repository
/// transaction; the count is never silently clamped to zero.
class StockMovement {
  factory StockMovement({
    required String id,
    required String farmId,
    required String campId,
    String speciesId = '',
    String speciesName = '',
    String movementType = typeAdded,
    int count = 0,
    String? fromCampId,
    String? toCampId,
    String? reason,
    String? recordedBy,
    DateTime? recordedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final type = normalizeMovementType(movementType);
    return StockMovement._(
      id: id.trim(),
      farmId: farmId.trim(),
      campId: campId.trim(),
      speciesId: speciesId.trim(),
      speciesName: speciesName.trim(),
      movementType: type.isEmpty ? movementType.trim().toLowerCase() : type,
      count: count,
      fromCampId: _optStr(fromCampId),
      toCampId: _optStr(toCampId),
      reason: _optStr(reason),
      recordedBy: _optStr(recordedBy),
      recordedAt: recordedAt ?? DateTime.now(),
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  const StockMovement._({
    required this.id,
    required this.farmId,
    required this.campId,
    required this.speciesId,
    required this.speciesName,
    required this.movementType,
    required this.count,
    required this.fromCampId,
    required this.toCampId,
    required this.reason,
    required this.recordedBy,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  static const String typeAdded = 'added';
  static const String typeMovedIn = 'moved_in';
  static const String typeMovedOut = 'moved_out';
  static const String typeHunted = 'hunted';
  static const String typeDied = 'died';
  static const String typeSold = 'sold';
  static const String typeCountAdjustment = 'count_adjustment';

  /// Every accepted movement type, in display order.
  static const List<String> movementTypes = [
    typeAdded,
    typeMovedIn,
    typeMovedOut,
    typeHunted,
    typeDied,
    typeSold,
    typeCountAdjustment,
  ];

  /// Movement types that ADD animals to a camp.
  static const List<String> incomingTypes = [typeAdded, typeMovedIn];

  /// Movement types that REMOVE animals from a camp.
  static const List<String> outgoingTypes = [
    typeMovedOut,
    typeHunted,
    typeDied,
    typeSold,
  ];

  /// Movement types where a human-entered cause is required.
  static const List<String> reasonRequiredTypes = [typeHunted, typeDied];

  final String id;
  final String farmId;

  /// The camp this record is filed under — the destination for `moved_in`,
  /// the source for `moved_out`, and the only camp for every other type.
  final String campId;

  /// Stable stock-ledger document id (`greater_kudu`), so the movement updates
  /// the same row the stock form writes.
  final String speciesId;
  final String speciesName;
  final String movementType;

  /// Signed count — positive in, negative out.
  final int count;

  /// Source camp of a move (`moved_in` / `moved_out` only).
  final String? fromCampId;

  /// Destination camp of a move (`moved_in` / `moved_out` only).
  final String? toCampId;

  /// Free-text cause / notes. Required for [reasonRequiredTypes].
  final String? reason;
  final String? recordedBy;
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Magnitude of the movement, always positive.
  int get magnitude => count.abs();

  /// `true` when this record moves animals between two camps.
  bool get isMove => isMoveType(movementType);

  /// Camps whose ledger this record describes — both camps for a move, one
  /// otherwise. Used to file the per-camp history copy.
  List<String> get historyCampIds {
    final ids = <String>{};
    if (campId.isNotEmpty) ids.add(campId);
    if (isMove) {
      final from = fromCampId;
      final to = toCampId;
      if (from != null && from.isNotEmpty) ids.add(from);
      if (to != null && to.isNotEmpty) ids.add(to);
    }
    return ids.toList(growable: false);
  }

  /// `+3` / `-2`, the form the history list renders.
  String get signedCountLabel => count > 0 ? '+$count' : '$count';

  /// Normalises a movement type, tolerating the common aliases. Returns an
  /// empty string for an unknown value so [validationError] can report it.
  static String normalizeMovementType(Object? value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) return '';
    if (movementTypes.contains(raw)) return raw;
    switch (raw) {
      case 'move_in':
      case 'movein':
      case 'in':
        return typeMovedIn;
      case 'move_out':
      case 'moveout':
      case 'out':
        return typeMovedOut;
      case 'hunt':
      case 'hunted_out':
        return typeHunted;
      case 'death':
      case 'dead':
        return typeDied;
      case 'sale':
        return typeSold;
      case 'adjustment':
      case 'countadjustment':
      case 'count-adjustment':
        return typeCountAdjustment;
      case 'add':
      case 'introduced':
        return typeAdded;
      default:
        return '';
    }
  }

  /// Human label for a movement type badge.
  static String movementTypeLabel(String movementType) {
    switch (normalizeMovementType(movementType)) {
      case typeAdded:
        return 'Added';
      case typeMovedIn:
        return 'Moved in';
      case typeMovedOut:
        return 'Moved out';
      case typeHunted:
        return 'Hunted';
      case typeDied:
        return 'Died';
      case typeSold:
        return 'Sold';
      case typeCountAdjustment:
        return 'Count adjustment';
      default:
        return 'Unknown';
    }
  }

  /// `true` for `moved_in` / `moved_out`.
  static bool isMoveType(String movementType) {
    final type = normalizeMovementType(movementType);
    return type == typeMovedIn || type == typeMovedOut;
  }

  /// `true` when the type requires a positive count.
  static bool requiresPositiveCount(String movementType) =>
      incomingTypes.contains(normalizeMovementType(movementType));

  /// `true` when the type requires a negative count.
  static bool requiresNegativeCount(String movementType) =>
      outgoingTypes.contains(normalizeMovementType(movementType));

  /// `true` when the type accepts either sign (but never zero).
  static bool allowsAnySign(String movementType) =>
      normalizeMovementType(movementType) == typeCountAdjustment;

  /// `true` when the type requires a cause / notes entry.
  static bool requiresReason(String movementType) =>
      reasonRequiredTypes.contains(normalizeMovementType(movementType));

  /// The sign contract: `added` / `moved_in` must be positive, `moved_out` /
  /// `hunted` / `died` / `sold` must be negative, `count_adjustment` may be
  /// either but never zero.
  static bool isSignValid(String movementType, int count) {
    final type = normalizeMovementType(movementType);
    if (count == 0) return false;
    if (requiresPositiveCount(type)) return count > 0;
    if (requiresNegativeCount(type)) return count < 0;
    if (type == typeCountAdjustment) return true;
    return false;
  }

  /// The net change each affected camp's ledger receives.
  ///
  /// Pure so the "a move touches two camps, a hunt touches one" contract is
  /// unit-testable without Firestore. An invalid movement (unknown type,
  /// zero count, missing move camp) yields an empty map — [validationError]
  /// is the guard that must be checked first.
  static Map<String, int> campDeltas(StockMovement movement) {
    final type = normalizeMovementType(movement.movementType);
    if (!isSignValid(type, movement.count)) return const <String, int>{};
    switch (type) {
      case typeAdded:
      case typeCountAdjustment:
        return movement.campId.isEmpty
            ? const <String, int>{}
            : {movement.campId: movement.count};
      case typeMovedIn:
      case typeMovedOut:
        final from = (movement.fromCampId ?? '').trim();
        final to = (movement.toCampId ?? '').trim();
        if (from.isEmpty || to.isEmpty || from == to) {
          return const <String, int>{};
        }
        final magnitude = movement.magnitude;
        return {from: -magnitude, to: magnitude};
      case typeHunted:
      case typeDied:
      case typeSold:
        return movement.campId.isEmpty
            ? const <String, int>{}
            : {movement.campId: -movement.magnitude};
      default:
        return const <String, int>{};
    }
  }

  /// The first thing wrong with this record, or null when it is valid.
  ///
  /// Pure and exhaustively unit-tested so the UI and the repository share one
  /// validation rule.
  String? get validationError {
    final type = normalizeMovementType(movementType);
    if (type.isEmpty) {
      return 'Choose a movement type.';
    }
    if (farmId.isEmpty) return 'Farm id is required.';
    if (campId.isEmpty) return 'Camp id is required.';
    if (speciesName.isEmpty && speciesId.isEmpty) {
      return 'Choose a species.';
    }
    if (count == 0) return 'Enter a count greater than zero.';
    if (requiresPositiveCount(type) && count < 0) {
      return '${movementTypeLabel(type)} needs a positive count.';
    }
    if (requiresNegativeCount(type) && count > 0) {
      return '${movementTypeLabel(type)} needs a negative count.';
    }
    if (!isSignValid(type, count)) {
      return 'The count does not match the movement type.';
    }
    if (isMoveType(type)) {
      final from = (fromCampId ?? '').trim();
      final to = (toCampId ?? '').trim();
      if (from.isEmpty) return 'Choose the camp the animals came from.';
      if (to.isEmpty) return 'Choose the camp the animals went to.';
      if (from == to) return 'The source and destination camps must differ.';
    }
    if (requiresReason(type) && (reason ?? '').trim().isEmpty) {
      return '${movementTypeLabel(type)} needs a cause / notes entry.';
    }
    return null;
  }

  /// `true` when [validationError] is null.
  bool get isValid => validationError == null;

  /// Applies [delta] to [entry], recomputing the derived totals.
  ///
  /// Throws [StockBelowZeroException] instead of clamping when the result
  /// would be negative — a silent clamp would hide a data-integrity problem.
  static StockEntry applyDeltaToStockEntry(
    StockEntry entry,
    int delta, {
    DateTime? now,
  }) {
    final newCount = entry.count + delta;
    if (newCount < 0) {
      throw StockBelowZeroException(
        campId: entry.campId,
        speciesName: entry.speciesName,
        currentCount: entry.count,
        requested: delta,
      );
    }
    return StockEntry(
      id: entry.id,
      campId: entry.campId,
      speciesName: entry.speciesName,
      scientificName: entry.scientificName,
      feedingClass: entry.feedingClass,
      count: newCount,
      avgWeightKg: entry.avgWeightKg,
      grazerPct: entry.grazerPct,
      browserPct: entry.browserPct,
      isOmnivore: entry.isOmnivore,
      isCounted: entry.isCounted,
      lsuPerAnimal: entry.lsuPerAnimal,
      guPerAnimal: entry.guPerAnimal,
      buPerAnimal: entry.buPerAnimal,
      createdAt: entry.createdAt,
      updatedAt: now ?? DateTime.now(),
    );
  }

  factory StockMovement.fromMap(Map<String, dynamic> map, {String? id}) {
    return StockMovement(
      id: id ?? _toStr(map['id']),
      farmId: _toStr(map['farmId']),
      campId: _toStr(map['campId']),
      speciesId: _toStr(map['speciesId']),
      speciesName: _toStr(map['speciesName']),
      movementType: _toStr(map['movementType']),
      count: _toInt(map['count']),
      fromCampId: _optStr(map['fromCampId']),
      toCampId: _optStr(map['toCampId']),
      reason: _optStr(map['reason']),
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
        'speciesId': speciesId,
        'speciesName': speciesName,
        'movementType': movementType,
        'count': count,
        if (fromCampId != null) 'fromCampId': fromCampId,
        if (toCampId != null) 'toCampId': toCampId,
        if (reason != null) 'reason': reason,
        if (recordedBy != null) 'recordedBy': recordedBy,
        'recordedAt': Timestamp.fromDate(recordedAt),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  StockMovement copyWith({
    String? id,
    String? farmId,
    String? campId,
    String? speciesId,
    String? speciesName,
    String? movementType,
    int? count,
    String? fromCampId,
    String? toCampId,
    String? reason,
    String? recordedBy,
    DateTime? recordedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      StockMovement(
        id: id ?? this.id,
        farmId: farmId ?? this.farmId,
        campId: campId ?? this.campId,
        speciesId: speciesId ?? this.speciesId,
        speciesName: speciesName ?? this.speciesName,
        movementType: movementType ?? this.movementType,
        count: count ?? this.count,
        fromCampId: fromCampId ?? this.fromCampId,
        toCampId: toCampId ?? this.toCampId,
        reason: reason ?? this.reason,
        recordedBy: recordedBy ?? this.recordedBy,
        recordedAt: recordedAt ?? this.recordedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is StockMovement &&
      other.id == id &&
      other.farmId == farmId &&
      other.campId == campId &&
      other.speciesId == speciesId &&
      other.speciesName == speciesName &&
      other.movementType == movementType &&
      other.count == count &&
      other.fromCampId == fromCampId &&
      other.toCampId == toCampId &&
      other.reason == reason &&
      other.recordedBy == recordedBy &&
      other.recordedAt == recordedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        farmId,
        campId,
        speciesId,
        speciesName,
        movementType,
        count,
        fromCampId,
        toCampId,
        reason,
        recordedBy,
        recordedAt,
        createdAt,
        updatedAt,
      ]);

  @override
  String toString() => 'StockMovement($movementType $signedCountLabel '
      '$speciesName in $campId)';
}

/// Thrown when a movement would push a camp's count below zero.
///
/// Deliberately an exception rather than a clamp: a negative count means the
/// ledger and the movement history disagree, and the operator must see it.
class StockBelowZeroException implements Exception {
  const StockBelowZeroException({
    required this.campId,
    required this.speciesName,
    required this.currentCount,
    required this.requested,
  });

  final String campId;
  final String speciesName;
  final int currentCount;
  final int requested;

  @override
  String toString() => 'StockBelowZeroException: $speciesName in camp '
      '$campId has $currentCount and the movement would apply $requested, '
      'which would leave ${currentCount + requested}.';
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
