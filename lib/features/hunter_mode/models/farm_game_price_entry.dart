import 'package:cloud_firestore/cloud_firestore.dart';

/// A single game-species price-list entry for a farm.
///
/// Each entry maps one game species to its offered quantity (`qty`) and unit
/// price (ZAR), plus an optional [gender] classification ('Male' / 'Female' /
/// 'Any') and an optional [hornTuskLength] trophy descriptor (e.g. '28"+',
/// 'Trophy', 'Cull'). Records are persisted in the `farm_pricelists`
/// Firestore collection linked directly to the owning [farmId] (and stamped
/// with the outfitter's [outfitterId] for ownership scoping).
///
/// Field aliases are tolerated on read ([speciesName]/[name], [qty]/[quantity],
/// [price]/[priceZAR]/[priceRands], [gender]/[sex], [hornTuskLength]/[horn]/
/// [tusk]) so legacy / hand-written docs hydrate cleanly.
class FarmGamePriceEntry {
  final String id;
  final String farmId;
  final String outfitterId;
  final String speciesName;
  final int qty;
  final double priceZAR;

  /// 'Male' / 'Female' / 'Any' (defaults to 'Any' when unset).
  final String gender;

  /// Optional trophy descriptor, e.g. '28"+', 'Trophy', 'Cull'. May be empty.
  final String hornTuskLength;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FarmGamePriceEntry({
    required this.id,
    required this.farmId,
    required this.outfitterId,
    required this.speciesName,
    required this.qty,
    required this.priceZAR,
    this.gender = 'Any',
    this.hornTuskLength = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Parses a Firestore document into a [FarmGamePriceEntry]. Field aliases
  /// are tolerated; missing numeric fields default to 0 so a partial doc never
  /// throws.
  factory FarmGamePriceEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return FarmGamePriceEntry(
      id: doc.id,
      farmId: (data['farmId'] as String?) ?? '',
      outfitterId: (data['outfitterId'] as String?) ?? '',
      speciesName: ((data['speciesName'] as String?) ?? (data['name'] as String?) ?? '').trim(),
      qty: _parseInt(data['qty'] ?? data['quantity']),
      priceZAR: _parseDouble(data['price'] ?? data['priceZAR'] ?? data['priceRands']),
      gender: _normalizeGender(data['gender'] ?? data['sex']),
      hornTuskLength:
          ((data['hornTuskLength'] as String?) ?? (data['horn'] as String?) ?? (data['tusk'] as String?) ?? '').trim(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Snapshot-free map parser (unit-testable without a [DocumentSnapshot]).
  factory FarmGamePriceEntry.fromMap(
    Map<String, dynamic> data, {
    required String id,
  }) {
    return FarmGamePriceEntry(
      id: id,
      farmId: (data['farmId'] as String?) ?? '',
      outfitterId: (data['outfitterId'] as String?) ?? '',
      speciesName: ((data['speciesName'] as String?) ?? (data['name'] as String?) ?? '').trim(),
      qty: _parseInt(data['qty'] ?? data['quantity']),
      priceZAR: _parseDouble(data['price'] ?? data['priceZAR'] ?? data['priceRands']),
      gender: _normalizeGender(data['gender'] ?? data['sex']),
      hornTuskLength:
          ((data['hornTuskLength'] as String?) ?? (data['horn'] as String?) ?? (data['tusk'] as String?) ?? '').trim(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'farmId': farmId,
        'outfitterId': outfitterId,
        'speciesName': speciesName,
        'qty': qty,
        'price': priceZAR,
        'gender': gender,
        if (hornTuskLength.isNotEmpty) 'hornTuskLength': hornTuskLength,
        if (createdAt != null)
          'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null)
          'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  FarmGamePriceEntry copyWith({
    String? speciesName,
    int? qty,
    double? priceZAR,
    String? gender,
    String? hornTuskLength,
    DateTime? updatedAt,
  }) =>
      FarmGamePriceEntry(
        id: id,
        farmId: farmId,
        outfitterId: outfitterId,
        speciesName: speciesName ?? this.speciesName,
        qty: qty ?? this.qty,
        priceZAR: priceZAR ?? this.priceZAR,
        gender: gender ?? this.gender,
        hornTuskLength: hornTuskLength ?? this.hornTuskLength,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
    return 0;
  }

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0.0;
    }
    return 0.0;
  }

  /// Normalises a raw gender value to one of 'Male' / 'Female' / 'Any'.
  /// Accepts case-insensitive input + the common 'M'/'F'/'Any'/'Both' aliases.
  static String _normalizeGender(dynamic v) {
    if (v == null) return 'Any';
    final s = v.toString().trim().toLowerCase();
    switch (s) {
      case 'male':
      case 'm':
      case 'bull':
      case 'ram':
        return 'Male';
      case 'female':
      case 'f':
      case 'cow':
      case 'ewe':
      case 'hen':
        return 'Female';
      case 'any':
      case 'both':
      case 'either':
      case 'all':
      case '':
        return 'Any';
      default:
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  @override
  String toString() =>
      'FarmGamePriceEntry(id: $id, farmId: $farmId, species: $speciesName, '
      'qty: $qty, priceZAR: $priceZAR, gender: $gender, '
      'hornTuskLength: $hornTuskLength)';
}

/// Pure validation helpers for the price-list add/edit form. Unit-testable
/// without Firestore.
class FarmGamePriceValidator {
  static const int minQty = 0;
  static const double minPrice = 0.0;

  /// The set of selectable gender values for the entry gender control.
  static const List<String> genderOptions = ['Male', 'Female', 'Any'];

  /// Default gender when none is specified.
  static const String defaultGender = 'Any';

  /// Returns an error message if [species] is invalid (empty), else null.
  static String? validateSpecies(String? species) {
    if (species == null || species.trim().isEmpty) {
      return 'Species name is required.';
    }
    if (species.trim().length > 80) {
      return 'Species name is too long (max 80 characters).';
    }
    return null;
  }

  /// Returns an error message if [qtyText] is not a valid non-negative integer,
  /// else null. An empty input is rejected (the field is required).
  static String? validateQty(String? qtyText) {
    if (qtyText == null || qtyText.trim().isEmpty) {
      return 'Quantity is required.';
    }
    final qty = int.tryParse(qtyText.trim());
    if (qty == null) {
      return 'Quantity must be a valid whole number.';
    }
    if (qty < minQty) {
      return 'Quantity cannot be negative.';
    }
    return null;
  }

  /// Returns an error message if [priceText] is not a valid non-negative
  /// number, else null. An empty input is rejected (the field is required).
  static String? validatePrice(String? priceText) {
    if (priceText == null || priceText.trim().isEmpty) {
      return 'Price is required.';
    }
    final price = double.tryParse(priceText.trim().replaceAll(RegExp(r'[Rr ]'), ''));
    if (price == null) {
      return 'Price must be a valid number.';
    }
    if (price < minPrice) {
      return 'Price cannot be negative.';
    }
    return null;
  }

  /// Returns an error message if [hornTuskLength] exceeds the max length,
  /// else null. The field is optional, so an empty value is accepted.
  static String? validateHornTuskLength(String? value) {
    if (value == null) return null;
    if (value.trim().length > 40) {
      return 'Horn / Tusk length must be at most 40 characters.';
    }
    return null;
  }
}
