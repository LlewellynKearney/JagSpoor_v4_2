import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';

/// Static reference tables for the Veld & Carrying Capacity feature.
///
/// Pure data only: no feature flag (see `veld_carry_feature_flag.dart`), no
/// models and no arithmetic (see `veld_carry_calculator.dart`).
class VeldCarryConstants {
  const VeldCarryConstants._();

  /// The nine South African provinces, canonical spelling.
  static const List<String> provinces = [
    'Gauteng',
    'Limpopo',
    'Mpumalanga',
    'North West',
    'Free State',
    'KwaZulu-Natal',
    'Eastern Cape',
    'Western Cape',
    'Northern Cape',
  ];

  /// Suggested hectares-per-LSU norm per province. A starting point only —
  /// the outfitter's own camp norm always wins.
  static const Map<String, double> provinceSuggestedHaPerLsu = {
    'Gauteng': 6.0,
    'Limpopo': 10.0,
    'Mpumalanga': 5.0,
    'North West': 12.0,
    'Free State': 7.5,
    'KwaZulu-Natal': 6.4,
    'Eastern Cape': 10.8,
    'Western Cape': 12.0,
    'Northern Cape': 33.3,
  };

  /// Veld type options.
  static const List<String> veldTypes = [
    'Sweetveld',
    'Sourveld',
    'Mixed Veld',
    'Bushveld / Savanna',
    'Grassland / Highveld',
    'Karoo / Nama-Karoo',
    'Kalahari / Thornveld',
    'Fynbos / Renosterveld',
    'Thicket / Valley Bushveld',
  ];

  /// Condition multipliers applied to the hectares-per-LSU norm.
  static const Map<String, double> veldConditionMultipliers = {
    'good': 1.0,
    'fair': 1.25,
    'poor': 1.60,
  };

  /// Hectares per LSU for each planted feed type.
  ///
  /// Keys match `PlantedArea.feedTypes` (`OTHER_CUSTOM` intentionally has no
  /// norm because it is outfitter-defined).
  static const Map<String, double> plantedFeedHaPerLsu = {
    'LUCERNE_IRRIGATED': 1.0,
    'LUCERNE_DRYLAND': 1.5,
    'TEFF': 1.5,
    'OATS': 1.2,
    'OATS_VETCH': 1.1,
    'RYEGRASS_PERENNIAL': 0.8,
    'RYEGRASS_ANNUAL': 1.0,
    'KIKUYU_IRRIGATED': 0.20,
    'KIKUYU_DRYLAND': 0.50,
    'ERAGROSTIS': 2.0,
    'SMUTS_FINGER': 2.5,
    'MAIZE_STOVER': 3.0,
    'SORGHUM': 1.8,
  };

  /// Average daily intake (kg of prey) per predator species.
  static const Map<String, double> predatorDailyIntakeKg = {
    'Lion': 7.0,
    'Leopard': 4.0,
    'Cheetah': 3.5,
    'African Wild Dog': 3.0,
    'Spotted Hyena': 4.0,
    'Brown Hyena': 2.5,
    'Caracal': 1.5,
    'Serval': 1.0,
    'Black-backed Jackal': 1.0,
    'Side-striped Jackal': 1.0,
    'African Wild Cat': 0.5,
    'Honey Badger': 1.0,
  };

  /// Permit types — single source of truth is [FarmPermit.permitTypes].
  static const List<String> permitTypes = FarmPermit.permitTypes;

  /// Species recorded as present but never counted against veld capacity.
  static const List<String> presentOnlySpecies = [
    'Baboon',
    'Vervet Monkey',
    'Porcupine',
    'Aardvark',
  ];

  /// Multiplier for [condition] (`good` / `fair` / `poor`); defaults to
  /// `good` for unknown or blank input.
  static double veldConditionMultiplier(String? condition) {
    final key = (condition ?? '').trim().toLowerCase();
    return veldConditionMultipliers[key] ?? 1.0;
  }

  /// Suggested ha/LSU for [province] (case-insensitive), or `null` when the
  /// province is unknown.
  static double? suggestedHaPerLsuForProvince(String? province) {
    final key = (province ?? '').trim();
    if (key.isEmpty) return null;
    final direct = provinceSuggestedHaPerLsu[key];
    if (direct != null) return direct;
    final lower = key.toLowerCase();
    for (final entry in provinceSuggestedHaPerLsu.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// Ha/LSU norm for a planted [feedType] (case-insensitive), or `null` when
  /// the feed type has no published norm.
  static double? plantedHaPerLsuFor(String? feedType) {
    final key = (feedType ?? '').trim().toUpperCase();
    if (key.isEmpty) return null;
    return plantedFeedHaPerLsu[key];
  }

  /// Daily intake (kg) for [predatorName] (case-insensitive), or `null` when
  /// the species is not in the table.
  static double? predatorDailyIntakeFor(String? predatorName) {
    final key = (predatorName ?? '').trim();
    if (key.isEmpty) return null;
    final direct = predatorDailyIntakeKg[key];
    if (direct != null) return direct;
    final lower = key.toLowerCase();
    for (final entry in predatorDailyIntakeKg.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }
}
