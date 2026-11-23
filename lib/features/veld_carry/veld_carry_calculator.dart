import 'dart:math' as math;

import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/rainfall_entry.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_constants.dart';

/// Pure carrying-capacity arithmetic for the Veld & Carrying Capacity feature.
///
/// Every formula lives here: UI widgets and repositories must call these
/// helpers instead of re-deriving the maths. No Firestore, no Flutter, no
/// state.
///
/// Phase 1: the LSU coefficient, the GU/BU split, the veld-condition
/// adjustment and the stocking bands are the real formulas. The 18 public
/// signatures are final and unchanged from Phase 0.

/// Reference live weight of one Large Stock Unit, in kilograms.
const double lsuReferenceWeightKg = 450.0;

/// Days in a year used for predator prey-impact maths.
const double daysPerYear = 365.0;

/// A permit within this many days of expiry counts as `expiring_soon`.
const int permitExpiringSoonDays = 30;

/// Upper bound applied to [usagePct] so a pathological input cannot render an
/// absurd percentage.
const double usagePctCeiling = 999.0;

/// Stocking-band edges, in percent of carrying capacity.
const double stockingUnderstockedMaxPct = 70.0;
const double stockingOptimalMaxPct = 100.0;
const double stockingOverstockedMaxPct = 120.0;

/// Stocking bands returned by [stockingStatus].
const String stockingUnderstocked = 'understocked';
const String stockingOptimal = 'optimal';
const String stockingOverstocked = 'overstocked';
const String stockingSeverelyOverstocked = 'severely_overstocked';

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
  if (count < 0 || !avgWeightKg.isFinite || avgWeightKg <= 0) return 0.0;
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
///
/// An unknown or blank condition is treated as `fair` (1.25) — the
/// conservative middle band — so an unset condition never flatters the
/// carrying capacity.
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

/// Additional LSU supplied in [season] by planted areas planted for exactly
/// that season.
///
/// `ALL_YEAR` areas are excluded — they already sit in
/// [yearRoundCapacityLsu]. Asking for `ALL_YEAR` therefore returns 0.
double seasonalBoostLsu(List<PlantedArea> plantedAreas, String season) {
  final wanted = season.trim().toUpperCase();
  if (wanted.isEmpty || wanted == PlantedArea.seasonAllYear) return 0.0;
  var total = 0.0;
  for (final area in plantedAreas) {
    if (area.season == wanted) {
      total += plantedCapacityLsu(area.areaHa, area.haPerLsu);
    }
  }
  return total;
}

/// Stocking pressure as a percentage of capacity (`50 of 200 => 25.0`).
///
/// A non-positive capacity yields 0 rather than infinity. The result is
/// clamped to 0..[usagePctCeiling].
double usagePct(double totalLsu, double totalCapacity) {
  if (!totalCapacity.isFinite || totalCapacity <= 0) return 0.0;
  if (!totalLsu.isFinite) return 0.0;
  final pct = (totalLsu / totalCapacity) * 100.0;
  if (!pct.isFinite || pct <= 0) return 0.0;
  return pct > usagePctCeiling ? usagePctCeiling : pct;
}

/// Remaining LSU headroom. Negative means the camp is overstocked.
double headroomLsu(double totalCapacity, double totalLsu) {
  final capacity = totalCapacity.isFinite ? totalCapacity : 0.0;
  final used = totalLsu.isFinite ? totalLsu : 0.0;
  return capacity - used;
}

/// Stocking band for a [usagePct]:
/// `understocked` (< 70), `optimal` (70..100), `overstocked` (100..120),
/// `severely_overstocked` (> 120).
String stockingStatus(double usagePct) {
  if (!usagePct.isFinite) return stockingUnderstocked;
  if (usagePct < stockingUnderstockedMaxPct) return stockingUnderstocked;
  if (usagePct <= stockingOptimalMaxPct) return stockingOptimal;
  if (usagePct <= stockingOverstockedMaxPct) return stockingOverstocked;
  return stockingSeverelyOverstocked;
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

// ── Rainfall log ──────────────────────────────────────────────────────
//
// Rainfall is a measurement, so its aggregation lives here with the rest of
// the feature's arithmetic. The condition hint is a SUGGESTION only — it never
// writes a camp's `veldCondition`, the outfitter decides.

/// Fraction of a camp's own expected annual rainfall at or above which the
/// trailing 12-month total reads as `good`.
const double rainfallGoodFraction = 0.9;

/// Fraction at or above which the trailing total reads as `fair` (below it,
/// `poor`).
const double rainfallFairFraction = 0.6;

/// Total millimetres across [entries]. Negative / non-finite figures are
/// ignored rather than subtracted.
double rainfallTotalMm(Iterable<RainfallEntry> entries) {
  var total = 0.0;
  for (final entry in entries) {
    if (!entry.rainfallMm.isFinite || entry.rainfallMm <= 0) continue;
    total += entry.rainfallMm;
  }
  return total;
}

/// Total millimetres recorded for [year] (a calendar year, `2026`).
double rainfallTotalForYear(Iterable<RainfallEntry> entries, int year) {
  return rainfallTotalMm(
    entries.where((entry) => entry.year == year),
  );
}

/// Total millimetres across the month keys in [months] (`2026-11`).
double rainfallTotalForMonths(
  Iterable<RainfallEntry> entries,
  Set<String> months,
) {
  if (months.isEmpty) return 0.0;
  return rainfallTotalMm(entries.where((entry) => months.contains(entry.month)));
}

/// Total millimetres for the trailing 12 months ending at [now] (the current
/// month plus the eleven before it).
double rainfallTotalLastTwelveMonths(
  Iterable<RainfallEntry> entries, {
  DateTime? now,
}) {
  final months =
      RainfallEntry.recentMonths(now ?? DateTime.now(), count: 12).toSet();
  return rainfallTotalForMonths(entries, months);
}

/// The veld-condition hint implied by a trailing rainfall total, as one of
/// `Camp.veldConditionGood` / `Fair` / `Poor`.
///
/// Compares the last 12 months against the camp's OWN recorded annual rainfall
/// ([expectedAnnualMm]) — no absolute millimetre bands are invented, because a
/// "good" total in the Karoo would be a drought in KwaZulu-Natal. Returns null
/// when the camp has no expected annual figure to compare against, so the UI
/// shows no hint rather than a guess.
String? rainfallConditionSuggestion({
  required double last12MonthsMm,
  double? expectedAnnualMm,
}) {
  if (!last12MonthsMm.isFinite || last12MonthsMm < 0) return null;
  if (expectedAnnualMm == null ||
      !expectedAnnualMm.isFinite ||
      expectedAnnualMm <= 0) {
    return null;
  }
  final fraction = last12MonthsMm / expectedAnnualMm;
  if (fraction >= rainfallGoodFraction) return 'good';
  if (fraction >= rainfallFairFraction) return 'fair';
  return 'poor';
}

double _total(int count, double perAnimal) {
  if (count < 0 || !perAnimal.isFinite || perAnimal <= 0) return 0.0;
  return count * perAnimal;
}

double _clampFraction(double value) {
  if (!value.isFinite || value <= 0) return 0.0;
  if (value >= 1) return 1.0;
  return value;
}
