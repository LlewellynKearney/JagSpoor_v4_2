import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:jagspoor/features/hunter_mode/models/package_pricing.dart';

/// A single itemized service-rate line for a farm (e.g. Bakkie / Hunting
/// Vehicle Fees, Slaughtering Fees, Coldroom Fees, Hunter Daily Fees, etc.).
///
/// Mirrors [ItemizedLineItem] but is persisted independently under the farm's
/// service-rate configuration (see [FarmServiceRates]) so an outfitter can
/// configure farm-level pricing for the 7 standard service categories without
/// coupling them to a published package.
class FarmServiceRate {
  /// The [ItemizedBreakdownCategory.key] this rate belongs to.
  final String key;

  /// The human-readable label (mirrors [ItemizedBreakdownCategory.label]).
  final String label;

  /// Quantity / multiplier for the rate (e.g. 2 bakkies, 3 nights).
  final int quantity;

  /// Price per unit in ZAR.
  final double pricePerUnit;

  const FarmServiceRate({
    required this.key,
    required this.label,
    required this.quantity,
    required this.pricePerUnit,
  });

  double get total => quantity * pricePerUnit;

  /// True when this rate has a meaningful quantity + price (used to decide
  /// whether to render it in the PDF / list).
  bool get isConfigured => quantity > 0 && pricePerUnit > 0;

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'quantity': quantity,
        'pricePerUnit': pricePerUnit,
        'total': total,
      };

  factory FarmServiceRate.fromMap(Map<String, dynamic> map) {
    return FarmServiceRate(
      key: map['key'] as String? ?? '',
      label: map['label'] as String? ?? '',
      quantity: _asInt(map['quantity']),
      pricePerUnit: _asDouble(map['pricePerUnit']),
    );
  }

  FarmServiceRate copyWith({
    String? label,
    int? quantity,
    double? pricePerUnit,
  }) =>
      FarmServiceRate(
        key: key,
        label: label ?? this.label,
        quantity: quantity ?? this.quantity,
        pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      );

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }
}

/// The full set of itemized service rates for a single farm, keyed by
/// [ItemizedBreakdownCategory.key]. Persisted as one document in the
/// `farm_service_rates` Firestore collection (id == `farmId`) so the whole
/// configuration reads/writes atomically and streams as a single snapshot.
class FarmServiceRates {
  final String farmId;
  final String outfitterId;
  final Map<String, FarmServiceRate> rates;

  final DateTime? updatedAt;

  const FarmServiceRates({
    required this.farmId,
    required this.outfitterId,
    required this.rates,
    this.updatedAt,
  });

  /// Empty/default rates for a farm (no rates configured yet). All 7 standard
  /// categories are present with quantity 0 / price 0 so the UI can render the
  /// full list immediately.
  factory FarmServiceRates.empty(String farmId, String outfitterId) {
    final rates = <String, FarmServiceRate>{};
    for (final cat in ItemizedBreakdownCategory.all) {
      rates[cat.key] = FarmServiceRate(
        key: cat.key,
        label: cat.label,
        quantity: 0,
        pricePerUnit: 0,
      );
    }
    return FarmServiceRates(
      farmId: farmId,
      outfitterId: outfitterId,
      rates: rates,
    );
  }

  /// Convenience lookup; falls back to an unconfigured rate for the key so the
  /// UI never null-derefs on a missing category.
  FarmServiceRate rate(String key) =>
      rates[key] ??
      FarmServiceRate(
        key: key,
        label: ItemizedBreakdownCategory.all
            .firstWhere(
              (c) => c.key == key,
              orElse: () => ItemizedBreakdownCategory(key, key),
            )
            .label,
        quantity: 0,
        pricePerUnit: 0,
      );

  /// The configured (qty>0 + price>0) rates, in the standard category order.
  List<FarmServiceRate> get configuredRates {
    final result = <FarmServiceRate>[];
    for (final cat in ItemizedBreakdownCategory.all) {
      final r = rates[cat.key];
      if (r != null && r.isConfigured) result.add(r);
    }
    return result;
  }

  /// Sum of all configured rate totals.
  double get grandTotal =>
      configuredRates.fold(0.0, (acc, r) => acc + r.total);

  /// Snapshot-free map parser (unit-testable without a [DocumentSnapshot]).
  factory FarmServiceRates.fromMap(
    Map<String, dynamic> map, {
    required String farmId,
  }) {
    final rawRates = map['rates'];
    final rates = <String, FarmServiceRate>{};
    // Seed the 7 standard categories so the UI always renders the full list.
    for (final cat in ItemizedBreakdownCategory.all) {
      rates[cat.key] = FarmServiceRate(
        key: cat.key,
        label: cat.label,
        quantity: 0,
        pricePerUnit: 0,
      );
    }
    if (rawRates is Map) {
      rawRates.forEach((k, v) {
        if (v is Map) {
          final r = FarmServiceRate.fromMap(
            Map<String, dynamic>.from(v),
          );
          rates[r.key.isNotEmpty ? r.key : k.toString()] = r;
        }
      });
    }
    return FarmServiceRates(
      farmId: farmId,
      outfitterId: (map['outfitterId'] as String?) ?? '',
      rates: rates,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory FarmServiceRates.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return FarmServiceRates.fromMap(data, farmId: doc.id);
  }

  Map<String, dynamic> toMap() => {
        'farmId': farmId,
        'outfitterId': outfitterId,
        'rates': {
          for (final r in rates.values) r.key: r.toMap(),
        },
        if (updatedAt != null)
          'updatedAt': Timestamp.fromDate(updatedAt!),
      };
}
