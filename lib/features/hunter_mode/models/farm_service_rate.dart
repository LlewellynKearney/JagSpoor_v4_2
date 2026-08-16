import 'package:cloud_firestore/cloud_firestore.dart';

/// A single itemized service-rate line for a farm (e.g. Bakkie / Hunting
/// Vehicle Fees, Slaughtering Fees, Coldroom Fees, Hunter Daily Fees, etc.).
///
/// Each rate carries the per-category *unit semantics* ([unitLabel], e.g.
/// "Per vehicle per day") and the *quantity noun* ([quantityNoun], e.g.
/// "vehicles") so the form UI + PDF export can label the quantity + rate
/// columns exactly per the configured service type, instead of a generic
/// "Quantity × Rate" row.
class FarmServiceRate {
  /// The [FarmServiceCategory.key] this rate belongs to.
  final String key;

  /// The human-readable label (mirrors [FarmServiceCategory.label]).
  final String label;

  /// The rate-unit description shown in the UI + PDF
  /// (e.g. "Per vehicle per day", "Per day", "Per night", "Per animal").
  final String unitLabel;

  /// The noun describing what the [quantity] counts
  /// (e.g. "vehicles", "animals", "hunters", "nights", "persons").
  final String quantityNoun;

  /// Quantity / multiplier for the rate (e.g. 2 vehicles, 3 nights).
  final int quantity;

  /// Price per unit in ZAR.
  final double pricePerUnit;

  const FarmServiceRate({
    required this.key,
    required this.label,
    required this.quantity,
    required this.pricePerUnit,
    this.unitLabel = '',
    this.quantityNoun = '',
  });

  double get total => quantity * pricePerUnit;

  /// True when this rate has a meaningful, non-zero quantity AND price (used
  /// to decide whether to render it in the PDF / list). A blank, zero, or
  /// null quantity/price (resolved to 0 on parse) is strictly NOT configured
  /// and is omitted from the exported PDF price list.
  bool get isConfigured => quantity > 0 && pricePerUnit > 0;

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'unitLabel': unitLabel,
        'quantityNoun': quantityNoun,
        'quantity': quantity,
        'pricePerUnit': pricePerUnit,
        'total': total,
      };

  factory FarmServiceRate.fromMap(Map<String, dynamic> map) {
    final key = map['key'] as String? ?? '';
    final cat = FarmServiceCategory.findByKey(key);
    return FarmServiceRate(
      key: key,
      label: (map['label'] as String?)?.isNotEmpty == true
          ? map['label'] as String
          : cat.label,
      unitLabel: (map['unitLabel'] as String?)?.isNotEmpty == true
          ? map['unitLabel'] as String
          : cat.unitLabel,
      quantityNoun: (map['quantityNoun'] as String?)?.isNotEmpty == true
          ? map['quantityNoun'] as String
          : cat.quantityNoun,
      quantity: _asInt(map['quantity']),
      pricePerUnit: _asDouble(map['pricePerUnit']),
    );
  }

  FarmServiceRate copyWith({
    String? key,
    String? label,
    String? unitLabel,
    String? quantityNoun,
    int? quantity,
    double? pricePerUnit,
  }) =>
      FarmServiceRate(
        key: key ?? this.key,
        label: label ?? this.label,
        unitLabel: unitLabel ?? this.unitLabel,
        quantityNoun: quantityNoun ?? this.quantityNoun,
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

/// A farm-level itemized service category with explicit per-category unit
/// semantics.
///
/// Each category declares:
/// - [key]: the stable storage key.
/// - [label]: the human-readable service name (UI + PDF).
/// - [unitLabel]: the rate-unit description (e.g. "Per vehicle per day",
///   "Per day", "Per night", "Per animal") -- rendered as the Rate column
///   qualifier in the form + PDF.
/// - [quantityNoun]: the noun describing what the quantity counts (e.g.
///   "vehicles", "animals", "hunters", "nights", "persons") -- rendered as
///   the Quantity field label in the form.
///
/// The 9 categories implement the exact specified breakdown:
/// 1. Bakkie / Hunting Vehicle Fees -- qty = vehicles, rate = per vehicle per day.
/// 2. Slaughtering Fees (Big Animals) -- qty = animals, rate = per animal.
/// 3. Slaughtering Fees (Small Animals) -- qty = animals, rate = per animal.
/// 4. Coldroom / Cold Storage Fees -- qty = animals, rate = per day.
/// 5. Hunter Daily Fees -- qty = hunters, rate = per day.
/// 6. Non-Hunter Observer Daily Fees -- qty = non-hunters/observers, per day.
/// 7. Overnight Accommodation (Hunter) -- qty = nights, rate = per night.
/// 8. Overnight Accommodation (Non-Hunter) -- qty = nights, rate = per night.
/// 9. Catering Services -- qty = persons, rate = per day.
class FarmServiceCategory {
  final String key;
  final String label;
  final String unitLabel;
  final String quantityNoun;

  const FarmServiceCategory({
    required this.key,
    required this.label,
    required this.unitLabel,
    required this.quantityNoun,
  });

  /// The 9 standard farm service categories in display order.
  static const List<FarmServiceCategory> all = [
    FarmServiceCategory(
      key: 'bakkie_vehicle',
      label: 'Bakkie / Hunting Vehicle Fees',
      unitLabel: 'Per vehicle per day',
      quantityNoun: 'vehicles',
    ),
    FarmServiceCategory(
      key: 'slaughtering_big',
      label: 'Slaughtering Fees (Big Animals)',
      unitLabel: 'Per animal',
      quantityNoun: 'animals',
    ),
    FarmServiceCategory(
      key: 'slaughtering_small',
      label: 'Slaughtering Fees (Small Animals)',
      unitLabel: 'Per animal',
      quantityNoun: 'animals',
    ),
    FarmServiceCategory(
      key: 'coldroom',
      label: 'Coldroom / Cold Storage Fees',
      unitLabel: 'Per day',
      quantityNoun: 'animals',
    ),
    FarmServiceCategory(
      key: 'hunter_daily',
      label: 'Hunter Daily Fees',
      unitLabel: 'Per day',
      quantityNoun: 'hunters',
    ),
    FarmServiceCategory(
      key: 'non_hunter_observer_daily',
      label: 'Non-Hunter Observer Daily Fees',
      unitLabel: 'Per day',
      quantityNoun: 'observers',
    ),
    FarmServiceCategory(
      key: 'overnight_accommodation_hunter',
      label: 'Overnight Accommodation (Hunter)',
      unitLabel: 'Per night',
      quantityNoun: 'nights',
    ),
    FarmServiceCategory(
      key: 'overnight_accommodation_non_hunter',
      label: 'Overnight Accommodation (Non-Hunter)',
      unitLabel: 'Per night',
      quantityNoun: 'nights',
    ),
    FarmServiceCategory(
      key: 'catering',
      label: 'Catering Services',
      unitLabel: 'Per day',
      quantityNoun: 'persons',
    ),
  ];

  /// Resolves a category by key; falls back to a synthetic category echoing
  /// the key so the UI never null-derefs on an unknown/legacy key.
  static FarmServiceCategory findByKey(String key) {
    for (final cat in all) {
      if (cat.key == key) return cat;
    }
    return FarmServiceCategory(
      key: key,
      label: key,
      unitLabel: '',
      quantityNoun: '',
    );
  }

  /// Maps a legacy pre-refactor storage key to its current equivalent so an
  /// existing farm's stored configuration migrates cleanly:
  /// - `slaughtering` -> `slaughtering_big` (default the single legacy
  ///   slaughtering rate to Big Animals).
  /// - `overnight_accommodation` -> `overnight_accommodation_hunter`
  ///   (default the single legacy accommodation rate to Hunter).
  /// Any other key (incl. the new 9) is returned unchanged.
  static String migrateLegacyKey(String key) {
    switch (key) {
      case 'slaughtering':
        return 'slaughtering_big';
      case 'overnight_accommodation':
        return 'overnight_accommodation_hunter';
      default:
        return key;
    }
  }
}

/// The full set of itemized service rates for a single farm, keyed by
/// [FarmServiceCategory.key]. Persisted as one document in the
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

  /// Empty/default rates for a farm (no rates configured yet). All 9 standard
  /// categories are present with quantity 0 / price 0 so the UI can render the
  /// full list immediately.
  factory FarmServiceRates.empty(String farmId, String outfitterId) {
    final rates = <String, FarmServiceRate>{};
    for (final cat in FarmServiceCategory.all) {
      rates[cat.key] = FarmServiceRate(
        key: cat.key,
        label: cat.label,
        unitLabel: cat.unitLabel,
        quantityNoun: cat.quantityNoun,
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
  FarmServiceRate rate(String key) {
    final migrated = FarmServiceCategory.migrateLegacyKey(key);
    return rates[migrated] ??
        rates[key] ??
        FarmServiceRate(
          key: key,
          label: FarmServiceCategory.findByKey(key).label,
          unitLabel: FarmServiceCategory.findByKey(key).unitLabel,
          quantityNoun: FarmServiceCategory.findByKey(key).quantityNoun,
          quantity: 0,
          pricePerUnit: 0,
        );
  }

  /// The configured (qty>0 + price>0) rates, in the standard category order.
  /// Used by the PDF exporter so any zero/blank/null service is strictly
  /// omitted from the generated price list table.
  List<FarmServiceRate> get configuredRates {
    final result = <FarmServiceRate>[];
    for (final cat in FarmServiceCategory.all) {
      final r = rates[cat.key];
      if (r != null && r.isConfigured) result.add(r);
    }
    // Include any configured rate whose key is not in the standard 9 (e.g. a
    // custom/legacy key) so it is not silently dropped from the export.
    for (final r in rates.values) {
      if (r.isConfigured &&
          !FarmServiceCategory.all.any((c) => c.key == r.key)) {
        result.add(r);
      }
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
    // Seed the 9 standard categories so the UI always renders the full list.
    for (final cat in FarmServiceCategory.all) {
      rates[cat.key] = FarmServiceRate(
        key: cat.key,
        label: cat.label,
        unitLabel: cat.unitLabel,
        quantityNoun: cat.quantityNoun,
        quantity: 0,
        pricePerUnit: 0,
      );
    }
    if (rawRates is Map) {
      rawRates.forEach((k, v) {
        if (v is Map) {
          final parsed = FarmServiceRate.fromMap(
            Map<String, dynamic>.from(v),
          );
          // Migrate legacy keys (slaughtering -> slaughtering_big,
          // overnight_accommodation -> overnight_accommodation_hunter) so an
          // existing farm's stored configuration maps onto the new 9-category
          // structure without losing the configured rate.
          final rawKey = parsed.key.isNotEmpty ? parsed.key : k.toString();
          final resolvedKey = FarmServiceCategory.migrateLegacyKey(rawKey);
          // Re-stamp the resolved key + category label/unit semantics so the
          // in-memory model always reflects the current structure.
          final cat = FarmServiceCategory.findByKey(resolvedKey);
          rates[resolvedKey] = parsed.copyWith(
            key: resolvedKey,
            label: cat.label,
            unitLabel: cat.unitLabel,
            quantityNoun: cat.quantityNoun,
          );
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
