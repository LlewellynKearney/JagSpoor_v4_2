import 'dart:math' as math;

import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_constants.dart';

/// Pure carrying-capacity arithmetic for the Veld & Carrying Capacity feature.
///
/// Every formula lives here: UI widgets and repositories must call these
/// helpers instead of re-deriving the maths. No Firestore, no Flutter, no
/// state.
///
/// The unit coefficients (`lsuPerAnimal` and the GU/BU split) and the stocking
/// bands are provisional working values — Phase 1 replaces them with the
/// official SA tables. The signatures below are final.

/// Reference live weight of one Large Stock Unit, in kilograms.
const double lsuReferenceWeightKg = 450.0;

/// Days in a year used for predator prey-impact maths.
const double daysPerYear = 365.0;

/// A permit within this many days of expiry counts as `expiring_soon`.
const int permitExpiringSoonDays = 30;

/// LSU equivalent of an animal weighing [weightKg].
///
/// Scales metabolically against a 450 kg reference steer:
/// `(weightKg / 450) ^ 0.75`. Non-positive or non-finite weights return 0.
double lsuPerAnimal(double weightKg) {
  if (!weightKg.isFinite || weightKg <= 0) return 0.0;
  return math.pow(weightKg / lsuReferenceWeightKg, 0.75).toDouble();
}

/// Grazer units for an animal weighing [weightKg] with a grazer fraction of
/// [grazerPct] (clamped to 0..1).
double guPerAnimal(double weightKg, double grazerPct) =>
    lsuPerAnimal(weightKg) * _clampFraction(grazerPct);

/// Browser units for an animal weighing [weightKg] with a browser fraction of
/// [browserPct] (clamped to 0..1).
double buPerAnimal(double weightKg, double browserPct) =>
    lsuPerAnimal(weightKg) * _clampFraction(browserPct);

/// Total live weight of [count] animals at [avgWeightKg] each.
double totalWeightKg(int count, double avgWeightKg) {
  if (count <= 0 || !avgWeightKg.isFinite || avgWeightKg <= 0) return 0.0;
  return count * avgWeightKg;
}

/// Total LSU of [count] animals at [lsuPerAnimal] each.
double totalLsu(int count, double lsuPerAnimal) => _total(count, lsuPerAnimal);

/// Total GU of [count] animals at [guPerAnimal] each.
double totalGu(int count, double guPerAnimal) => _total(count, guPerAnimal);

/// Total BU of [count] animals at [buPerAnimal] each.
double totalBu(int count, double buPerAnimal) => _total(count, buPerAnimal);

/// Departmental ha/LSU norm adjusted for veld condition
/// (`good` 1.0 / `fair` 1.25 / `poor` 1.60).
double effectiveHaPerLsu(double deptNormHaPerLsu, String veldCondition) {
  if (!deptNormHaPerLsu.isFinite || deptNormHaPerLsu <= 0) return 0.0;
  return deptNormHaPerLsu *
      VeldCarryConstants.veldConditionMultiplier(veldCondition);
}

/// Carrying capacity of [veldHa] hectares at [effectiveHaPerLsu].
double veldCapacityLsu(double veldHa, double effectiveHaPerLsu) {
  if (!veldHa.isFinite || veldHa <= 0) return 0.0;
  if (!effectiveHaPerLsu.isFinite || effectiveHaPerLsu <= 0) return 0.0;
  return veldHa / effectiveHaPerLsu;
}

/// Carrying capacity of a planted area of [areaHa] at [haPerLsu].
double plantedCapacityLsu(double areaHa, double haPerLsu) {
  if (!areaHa.isFinite || areaHa <= 0) return 0.0;
  if (!haPerLsu.isFinite || haPerLsu <= 0) return 0.0;
  return areaHa / haPerLsu;
}

/// Veld capacity plus the year-round (`ALL_YEAR`) planted areas.
///
/// Season-specific plantings are excluded here; they are reported by
/// [seasonalBoostLsu].
double yearRoundCapacityLsu(
  double veldCapacity,
  List<PlantedArea> plantedAreas,
) {
  var total = veldCapacity.isFinite && veldCapacity > 0 ? veldCapacity : 0.0;
  for (final area in plantedAreas) {
    if (area.season == PlantedArea.seasonAllYear) {
      total += plantedCapacityLsu(area.areaHa, area.haPerLsu);
    }
  }
  return total;
}

/// Additional LSU supplied in [season] by planted areas that are either
/// season-specific for that season or year-round (`ALL_YEAR`).
double seasonalBoostLsu(List<PlantedArea> plantedAreas, String season) {
  var total = 0.0;
  for (final area in plantedAreas) {
    if (area.season == PlantedArea.seasonAllYear || area.season == season) {
      total += plantedCapacityLsu(area.areaHa, area.haPerLsu);
    }
  }
  return total;
}

/// Stocking pressure as a percentage of capacity (`50 of 200 => 25.0`).
///
/// A non-positive capacity yields 0 rather than infinity.
double usagePct(double totalLsu, double totalCapacity) {
  if (!totalCapacity.isFinite || totalCapacity <= 0) return 0.0;
  if (!totalLsu.isFinite || totalLsu <= 0) return 0.0;
  return (totalLsu / totalCapacity) * 100.0;
}

/// Remaining LSU headroom. Negative means the camp is overstocked.
double headroomLsu(double totalCapacity, double totalLsu) {
  final capacity = totalCapacity.isFinite ? totalCapacity : 0.0;
  final used = totalLsu.isFinite ? totalLsu : 0.0;
  return capacity - used;
}

/// Provisional stocking band for a [usagePct]:
/// `empty` (<= 0), `within_capacity` (<= 85), `near_capacity` (<= 100),
/// `overstocked` (> 100).
String stockingStatus(double usagePct) {
  if (!usagePct.isFinite || usagePct <= 0) return 'empty';
  if (usagePct <= 85) return 'within_capacity';
  if (usagePct <= 100) return 'near_capacity';
  return 'overstocked';
}

/// Prey consumed per year by [count] predators eating [dailyIntakeKg] a day.
double preyKgPerYear(int count, double dailyIntakeKg) {
  if (count <= 0 || !dailyIntakeKg.isFinite || dailyIntakeKg <= 0) return 0.0;
  return count * dailyIntakeKg * daysPerYear;
}

/// Number of prey animals of [avgPreyWeightKg] needed to supply
/// [preyKgPerYear].
double preyAnimalsPerYear(double preyKgPerYear, double avgPreyWeightKg) {
  if (!preyKgPerYear.isFinite || preyKgPerYear <= 0) return 0.0;
  if (!avgPreyWeightKg.isFinite || avgPreyWeightKg <= 0) return 0.0;
  return preyKgPerYear / avgPreyWeightKg;
}

/// Permit status implied by [expiryDate]:
/// `no_expiry` when null, `expired` when past, `expiring_soon` within
/// [permitExpiringSoonDays] days, otherwise `valid`.
///
/// Mirrors `FarmPermit.deriveStatus` so the model and calculator cannot
/// disagree.
String permitStatus(DateTime? expiryDate) {
  if (expiryDate == null) return 'no_expiry';
  final now = DateTime.now();
  final expiryDay =
      DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
  final today = DateTime(now.year, now.month, now.day);
  if (expiryDay.isBefore(today)) return 'expired';
  if (expiryDay.difference(today).inDays <= permitExpiringSoonDays) {
    return 'expiring_soon';
  }
  return 'valid';
}

double _total(int count, double perAnimal) {
  if (count <= 0 || !perAnimal.isFinite || perAnimal <= 0) return 0.0;
  return count * perAnimal;
}

double _clampFraction(double value) {
  if (!value.isFinite || value <= 0) return 0.0;
  if (value >= 1) return 1.0;
  return value;
}
