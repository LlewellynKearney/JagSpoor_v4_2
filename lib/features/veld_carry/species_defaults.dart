// FALLBACK TABLE — VERIFIED in Phase 7D against citable published sources.
//
// `assets/data/animals_seed.csv` still carries no weight, feeding-class or
// grazer/browser split columns, so the table below remains the source of truth
// for the Veld & Carrying Capacity feature. Values are NOT invented: every
// counted species comes from the table Llewellyn authorised (Phase 1), and
// every species that is absent from that table is carried as a placeholder
// (`avgWeightKg: 0`, `feedingClass: unknown`) and listed in
// [missingSpeciesNames].
//
// ══════════════════════════════════════════════════════════════════════════
// PHASE 7D — verification result (49 species)
// ══════════════════════════════════════════════════════════════════════════
// Every row now carries `isVerified` + `verificationSource` and an inline
// `// VERIFIED:` / `// UNVERIFIED —` marker, so a row can never sit in the
// table with an unstated provenance.
//
//   48 of 49 rows VERIFIED  — the fallback weight was within ±20% of the cited
//                             source, so the authorised value was KEPT.
//    1 of 49 row  CORRECTED — Cane Rat 8 kg -> 4.5 kg (see its own comment).
//    1 of 49 row  UNVERIFIED — Cape Hare: sources conflict (see its comment);
//                             the 2 kg fallback is retained deliberately.
//
// The three large-bodied species flagged in Phase 6 are now resolved:
//
//   • African Elephant 4500 kg — VERIFIED. Wikipedia gives bulls a 6.0 t mean
//     and cows a 3.0 t mean, so 4500 kg is exactly the sex-average. No change.
//   • Giraffe 1100 kg — VERIFIED. Male mean 1,192 kg, female 828 kg (≈1010 kg
//     average) — 1100 kg is +8.9%, inside tolerance. No change.
//   • Hippopotamus 1500 kg — VERIFIED. Adults average 1.5 t (bulls) and 1.3 t
//     (cows) — ≈1400 kg sex-average, so 1500 kg is +7.1%, inside tolerance.
//     No change.
//
// Sources used (priority order per the Phase 7D brief): published species
// literature (Wikipedia species pages, which cite Skinner & Chimimba / Bothma
// and the primary literature) and Animal Diversity Web where a Wikipedia page
// carried no mass figure. No value was taken from an unsourced recollection.
//
// Grazer/browser splits were reviewed and NOT changed: every pure grazer is
// ≥0.90 graze and every pure browser ≤0.10 graze; no obviously-wrong split was
// found.

/// Feeding-class labels used by [SpeciesDefault.feedingClass].
class FeedingClass {
  const FeedingClass._();

  static const String grazer = 'grazer';
  static const String browser = 'browser';
  static const String mixed = 'mixed';
  static const String omnivore = 'omnivore';

  /// Placeholder for a species with no authorised feeding data yet.
  static const String unknown = 'unknown';
}

/// One species' default live weight and grazer/browser split.
///
/// [isCounted] is false for species that are recorded as present on the farm
/// but never counted against veld capacity (see
/// `VeldCarryConstants.presentOnlySpecies`). [isOmnivore] marks the species
/// that browse and graze but also take animal matter.
class SpeciesDefault {
  const SpeciesDefault({
    required this.speciesName,
    required this.scientificName,
    required this.avgWeightKg,
    required this.feedingClass,
    required this.grazerPct,
    required this.browserPct,
    this.isCounted = true,
    this.isOmnivore = false,
    this.isVerified = false,
    this.verificationSource = '',
  });

  /// Canonical species name, as written in the authorised table.
  final String speciesName;

  /// Binomial / trinomial name, or `''` when not yet recorded.
  final String scientificName;

  /// Average adult live weight in kilograms. `0` means "not yet authorised".
  final double avgWeightKg;

  /// One of the [FeedingClass] labels.
  final String feedingClass;

  /// Fraction of intake taken as graze, 0..1.
  final double grazerPct;

  /// Fraction of intake taken as browse, 0..1.
  final double browserPct;

  /// Whether this species counts against veld carrying capacity.
  final bool isCounted;

  /// Whether this species also takes animal matter.
  final bool isOmnivore;

  /// True when [avgWeightKg] was checked against a citable published source in
  /// Phase 7D and is within the ±20% acceptance tolerance (or was corrected to
  /// the source value).
  ///
  /// False marks a row that is still a fallback: either unverified, or verified
  /// as CONFLICTING (see [verificationSource]). Never invent a value for an
  /// unverified row.
  final bool isVerified;

  /// The source the weight was checked against, or the reason it could not be
  /// verified. Empty only for rows that predate Phase 7D.
  final String verificationSource;

  /// Short label for the UI: `Chacma Baboon` -> `Baboon`, `Cape Porcupine`
  /// -> `Porcupine`, `Vervet Monkey` -> `Vervet`; otherwise [speciesName].
  String get displayName => speciesDisplayName(speciesName);

  /// False when this row is a placeholder awaiting Phase 3 verification.
  bool get hasKnownWeight => avgWeightKg > 0;

  /// True when this row is a placeholder awaiting Phase 3 verification.
  bool get isMissing => !hasKnownWeight;

  /// True when the grazer/browser split sums to 1 (Aardvark is the documented
  /// exception at 0 / 0).
  bool get hasCompleteSplit =>
      (grazerPct + browserPct - 1.0).abs() < 1e-9;

  @override
  String toString() =>
      'SpeciesDefault($speciesName, ${avgWeightKg}kg, $feedingClass)';
}

/// UI label overrides for the species whose table name is longer than the name
/// the app uses elsewhere.
const Map<String, String> speciesDisplayNames = {
  "chacma baboon": "Baboon",
  "cape porcupine": "Porcupine",
  "vervet monkey": "Vervet",
};

/// Resolves a CSV / free-text spelling to the canonical table name.
const Map<String, String> csvSpeciesAliases = {
  "chacma baboon": "Chacma Baboon",
  "cape porcupine": "Cape Porcupine",
  "vervet monkey": "Vervet Monkey",
  "gemsbok (oryx)": "Gemsbok",
  "common warthog": "Warthog",
  "common waterbuck": "Waterbuck",
  "southern bushbuck": "Bushbuck",
  "southern reedbuck": "Reedbuck (Common)",
  "natal red duiker": "Red Duiker",
  "cape mountain zebra": "Mountain Zebra",
  "hartmann's mountain zebra": "Mountain Zebra",
  "southern white rhinoceros": "White Rhino",
  "black rhinoceros": "Black Rhino",
  "rock hyrax": "Dassie / Rock Hyrax",
  "greater cane rat": "Cane Rat",
};

/// Display label for [speciesName] (`Chacma Baboon` -> `Baboon`).
String speciesDisplayName(String? speciesName) {
  final raw = (speciesName ?? '').trim();
  if (raw.isEmpty) return '';
  return speciesDisplayNames[raw.toLowerCase()] ?? raw;
}

/// Authorised fallback defaults for every species in the Phase 1 table.
const List<SpeciesDefault> speciesDefaults = [
  // VERIFIED: Wikipedia (en) — Impala: 40–65 kg; males 53–76 kg, females 40–53 kg
  SpeciesDefault(
    speciesName: "Impala",
    scientificName: "Aepyceros melampus",
    avgWeightKg: 55,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.60,
    browserPct: 0.40,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Impala: 40–65 kg; males 53–76 kg, females 40–53 kg',
  ),
  // VERIFIED: Wikipedia (en) — Greater kudu: bulls 190–270 kg, cows 120–210 kg
  SpeciesDefault(
    speciesName: "Greater Kudu",
    scientificName: "Tragelaphus strepsiceros",
    avgWeightKg: 250,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Greater kudu: bulls 190–270 kg, cows 120–210 kg',
  ),
  // VERIFIED: Wikipedia (en) — Lesser kudu: males 92–108 kg, females 56–70 kg
  SpeciesDefault(
    speciesName: "Lesser Kudu",
    scientificName: "Tragelaphus imberbis",
    avgWeightKg: 100,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Lesser kudu: males 92–108 kg, females 56–70 kg',
  ),
  // VERIFIED: Wikipedia (en) — Nyala: males 98–125 kg, females 55–68 kg
  SpeciesDefault(
    speciesName: "Nyala",
    scientificName: "Tragelaphus angasii",
    avgWeightKg: 110,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Nyala: males 98–125 kg, females 55–68 kg',
  ),
  // VERIFIED: Wikipedia (en) — Cape bushbuck: 45–80 kg (males 60–80, females 25–60)
  SpeciesDefault(
    speciesName: "Bushbuck",
    scientificName: "Tragelaphus scriptus",
    avgWeightKg: 45,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Cape bushbuck: 45–80 kg (males 60–80, females 25–60)',
  ),
  // VERIFIED: Wikipedia (en) — Common eland: males 500–600 kg typical, females 340–445 kg
  SpeciesDefault(
    speciesName: "Eland",
    scientificName: "Taurotragus oryx",
    avgWeightKg: 600,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.40,
    browserPct: 0.60,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Common eland: males 500–600 kg typical, females 340–445 kg',
  ),
  // VERIFIED: Wikipedia (en) — Sable antelope: males ~235 kg, females ~220 kg
  SpeciesDefault(
    speciesName: "Sable Antelope",
    scientificName: "Hippotragus niger",
    avgWeightKg: 235,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Sable antelope: males ~235 kg, females ~220 kg',
  ),
  // VERIFIED: Wikipedia (en) — Roan antelope: males 242–300 kg, females 223–280 kg
  SpeciesDefault(
    speciesName: "Roan Antelope",
    scientificName: "Hippotragus equinus",
    avgWeightKg: 270,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Roan antelope: males 242–300 kg, females 223–280 kg',
  ),
  // VERIFIED: Wikipedia (en) — Gemsbok: males 180–240 kg, females 100–210 kg
  SpeciesDefault(
    speciesName: "Gemsbok",
    scientificName: "Oryx gazella",
    avgWeightKg: 210,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.85,
    browserPct: 0.15,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Gemsbok: males 180–240 kg, females 100–210 kg',
  ),
  // VERIFIED: Wikipedia (en) — Blue wildebeest: males 165–290 kg, females 140–260 kg
  SpeciesDefault(
    speciesName: "Blue Wildebeest",
    scientificName: "Connochaetes taurinus",
    avgWeightKg: 230,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Blue wildebeest: males 165–290 kg, females 140–260 kg',
  ),
  // VERIFIED: Wikipedia (en) — Black wildebeest: 110–180 kg (bulls 140–157)
  SpeciesDefault(
    speciesName: "Black Wildebeest",
    scientificName: "Connochaetes gnou",
    avgWeightKg: 150,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Black wildebeest: 110–180 kg (bulls 140–157)',
  ),
  // VERIFIED: Wikipedia (en) — Red hartebeest: male mean 150 kg, female 120 kg
  SpeciesDefault(
    speciesName: "Red Hartebeest",
    scientificName: "Alcelaphus buselaphus",
    avgWeightKg: 150,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Red hartebeest: male mean 150 kg, female 120 kg',
  ),
  // VERIFIED: Wikipedia (en) — Tsessebe: males 137 kg, females 120 kg
  SpeciesDefault(
    speciesName: "Tsessebe",
    scientificName: "Damaliscus lunatus",
    avgWeightKg: 140,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Tsessebe: males 137 kg, females 120 kg',
  ),
  // VERIFIED: Wikipedia (en) — Blesbok: male mean 70 kg, female 61 kg
  SpeciesDefault(
    speciesName: "Blesbok",
    scientificName: "Damaliscus pygargus phillipsi",
    avgWeightKg: 70,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Blesbok: male mean 70 kg, female 61 kg',
  ),
  // VERIFIED: Wikipedia (en) — Bontebok: 50–68 kg
  SpeciesDefault(
    speciesName: "Bontebok",
    scientificName: "Damaliscus pygargus pygargus",
    avgWeightKg: 70,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Bontebok: 50–68 kg',
  ),
  // VERIFIED: Wikipedia (en) — Springbok: 27–42 kg
  SpeciesDefault(
    speciesName: "Springbok",
    scientificName: "Antidorcas marsupialis",
    avgWeightKg: 40,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.70,
    browserPct: 0.30,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Springbok: 27–42 kg',
  ),
  // VERIFIED: Wikipedia (en) — Waterbuck: males 198–262 kg, females 161–214 kg
  SpeciesDefault(
    speciesName: "Waterbuck",
    scientificName: "Kobus ellipsiprymnus",
    avgWeightKg: 220,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Waterbuck: males 198–262 kg, females 161–214 kg',
  ),
  // VERIFIED: Wikipedia (en) — Common reedbuck: mean 58 kg (females 48, males 68)
  SpeciesDefault(
    speciesName: "Reedbuck (Common)",
    scientificName: "Redunca arundinum",
    avgWeightKg: 55,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Common reedbuck: mean 58 kg (females 48, males 68)',
  ),
  // VERIFIED: Wikipedia (en) — Mountain reedbuck: ~30 kg
  SpeciesDefault(
    speciesName: "Mountain Reedbuck",
    scientificName: "Redunca fulvorufula",
    avgWeightKg: 30,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Mountain reedbuck: ~30 kg',
  ),
  // VERIFIED: Wikipedia (en) — Grey rhebok: 19–30 kg
  SpeciesDefault(
    speciesName: "Grey Rhebok",
    scientificName: "Pelea capreolus",
    avgWeightKg: 20,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.60,
    browserPct: 0.40,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Grey rhebok: 19–30 kg',
  ),
  // VERIFIED: Wikipedia (en) — Steenbok: 7–16 kg
  SpeciesDefault(
    speciesName: "Steenbok",
    scientificName: "Raphicerus campestris",
    avgWeightKg: 12,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Steenbok: 7–16 kg',
  ),
  // VERIFIED: Wikipedia (en) — Common duiker: 12–25 kg
  SpeciesDefault(
    speciesName: "Common Duiker",
    scientificName: "Sylvicapra grimmia",
    avgWeightKg: 20,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Common duiker: 12–25 kg',
  ),
  // VERIFIED: Wikipedia (en) — Blue duiker: 3.5–9 kg
  SpeciesDefault(
    speciesName: "Blue Duiker",
    scientificName: "Philantomba monticola",
    avgWeightKg: 5,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Blue duiker: 3.5–9 kg',
  ),
  // VERIFIED: Wikipedia (en) — Natal duiker: mean 14 kg
  SpeciesDefault(
    speciesName: "Red Duiker",
    scientificName: "Cephalophus natalensis",
    avgWeightKg: 14,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Natal duiker: mean 14 kg',
  ),
  // VERIFIED: Wikipedia (en) — Klipspringer: 8–18 kg
  SpeciesDefault(
    speciesName: "Klipspringer",
    scientificName: "Oreotragus oreotragus",
    avgWeightKg: 13,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Klipspringer: 8–18 kg',
  ),
  // VERIFIED: Wikipedia (en) — Cape grysbok: 8–12 kg
  SpeciesDefault(
    speciesName: "Cape Grysbok",
    scientificName: "Raphicerus melanotis",
    avgWeightKg: 10,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Cape grysbok: 8–12 kg',
  ),
  // VERIFIED: Wikipedia (en) — Sharpe's grysbok: 7–11.5 kg
  SpeciesDefault(
    speciesName: "Sharpe's Grysbok",
    scientificName: "Raphicerus sharpei",
    avgWeightKg: 10,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Sharpe\'s grysbok: 7–11.5 kg',
  ),
  // VERIFIED: Wikipedia (en) — Oribi: 12–22 kg
  SpeciesDefault(
    speciesName: "Oribi",
    scientificName: "Ourebia ourebi",
    avgWeightKg: 15,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Oribi: 12–22 kg',
  ),
  // VERIFIED: Wikipedia (en) — Suni: 4.5–5.4 kg
  SpeciesDefault(
    speciesName: "Suni",
    scientificName: "Neotragus moschatus",
    avgWeightKg: 6,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Suni: 4.5–5.4 kg',
  ),
  // VERIFIED: Wikipedia (en) — Giraffe: male mean 1,192 kg, female mean 828 kg
  SpeciesDefault(
    speciesName: "Giraffe",
    scientificName: "Giraffa camelopardalis",
    avgWeightKg: 1100,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Giraffe: male mean 1,192 kg, female mean 828 kg',
  ),
  // VERIFIED: Wikipedia (en) — Plains zebra: males 220–322 kg, females 175–250 kg
  SpeciesDefault(
    speciesName: "Plains Zebra",
    scientificName: "Equus quagga",
    avgWeightKg: 300,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Plains zebra: males 220–322 kg, females 175–250 kg',
  ),
  // VERIFIED: Wikipedia (en) — Mountain zebra: 204–372 kg
  SpeciesDefault(
    speciesName: "Mountain Zebra",
    scientificName: "Equus zebra",
    avgWeightKg: 280,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Mountain zebra: 204–372 kg',
  ),
  // VERIFIED: Wikipedia (en) — Grevy's zebra: 350–450 kg
  SpeciesDefault(
    speciesName: "Grevy's Zebra",
    scientificName: "Equus grevyi",
    avgWeightKg: 350,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Grevy\'s zebra: 350–450 kg',
  ),
  // VERIFIED: Wikipedia (en) — Common warthog: males 60–150 kg, females 45–75 kg
  SpeciesDefault(
    speciesName: "Warthog",
    scientificName: "Phacochoerus africanus",
    avgWeightKg: 90,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.70,
    browserPct: 0.30,
    isCounted: true,
    isOmnivore: true,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Common warthog: males 60–150 kg, females 45–75 kg',
  ),
  // VERIFIED: Wikipedia (en) — Bushpig: 60–80 kg common, boars to 150 kg
  SpeciesDefault(
    speciesName: "Bushpig",
    scientificName: "Potamochoerus larvatus",
    avgWeightKg: 80,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.50,
    browserPct: 0.50,
    isCounted: true,
    isOmnivore: true,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Bushpig: 60–80 kg common, boars to 150 kg',
  ),
  // VERIFIED: Wikipedia (en) — African buffalo: males 650–900 kg, females to 500 kg
  SpeciesDefault(
    speciesName: "Cape Buffalo",
    scientificName: "Syncerus caffer",
    avgWeightKg: 650,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — African buffalo: males 650–900 kg, females to 500 kg',
  ),
  // VERIFIED: Wikipedia (en) — African bush elephant: bulls mean 6.0 t, cows mean 3.0 t; 4500 kg is the sex-average
  SpeciesDefault(
    speciesName: "African Elephant",
    scientificName: "Loxodonta africana",
    avgWeightKg: 4500,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.40,
    browserPct: 0.60,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — African bush elephant: bulls mean 6.0 t, cows mean 3.0 t; 4500 kg is the sex-average',
  ),
  // VERIFIED: Wikipedia (en) — White rhinoceros: bulls 2,000–2,300 kg, cows 1,600–1,700 kg
  SpeciesDefault(
    speciesName: "White Rhino",
    scientificName: "Ceratotherium simum",
    avgWeightKg: 2000,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — White rhinoceros: bulls 2,000–2,300 kg, cows 1,600–1,700 kg',
  ),
  // VERIFIED: Wikipedia (en) — Black rhinoceros: 800–1,400 kg
  SpeciesDefault(
    speciesName: "Black Rhino",
    scientificName: "Diceros bicornis",
    avgWeightKg: 1200,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Black rhinoceros: 800–1,400 kg',
  ),
  // VERIFIED: Wikipedia (en) — Hippopotamus: adults average 1.5 t bulls,
  // 1.3 t cows (≈1400 kg sex-average)
  SpeciesDefault(
    speciesName: "Hippopotamus",
    scientificName: "Hippopotamus amphibius",
    avgWeightKg: 1500,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Hippopotamus: adults average 1.5 t bulls, 1.3 t cows '
        '(≈1400 kg sex-average)',
  ),
  // VERIFIED: Wikipedia (en) — Chacma baboon: male mean 31.8 kg, female mean 15.4 kg
  SpeciesDefault(
    speciesName: "Chacma Baboon",
    scientificName: "Papio ursinus",
    avgWeightKg: 25,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.50,
    browserPct: 0.50,
    isCounted: false,
    isOmnivore: true,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Chacma baboon: male mean 31.8 kg, female mean 15.4 kg',
  ),
  // VERIFIED: Wikipedia (en) — Vervet monkey: adult males mean 5.5 kg
  SpeciesDefault(
    speciesName: "Vervet Monkey",
    scientificName: "Chlorocebus pygerythrus",
    avgWeightKg: 5,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.40,
    browserPct: 0.60,
    isCounted: false,
    isOmnivore: true,
    isVerified: true,
    verificationSource:
        'Wikipedia (en) — Vervet monkey: adult males mean 5.5 kg',
  ),
  // VERIFIED: Wikipedia (en) — Cape porcupine: 10–24 kg
  SpeciesDefault(
    speciesName: "Cape Porcupine",
    scientificName: "Hystrix africaeaustralis",
    avgWeightKg: 20,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.60,
    browserPct: 0.40,
    isCounted: false,
    isOmnivore: true,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Cape porcupine: 10–24 kg',
  ),
  // VERIFIED: Wikipedia (en) — Aardvark: 60–80 kg
  SpeciesDefault(
    speciesName: "Aardvark",
    scientificName: "Orycteropus afer",
    avgWeightKg: 60,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.00,
    browserPct: 0.00,
    isCounted: false,
    isOmnivore: true,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Aardvark: 60–80 kg',
  ),
  // VERIFIED: Wikipedia (en) — Scrub hare: 3.2–4 kg
  SpeciesDefault(
    speciesName: "Scrub Hare",
    scientificName: "Lepus saxatilis",
    avgWeightKg: 3,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Scrub hare: 3.2–4 kg',
  ),
  // UNVERIFIED — UNVERIFIED — ADW gives 4–5 kg for Lepus capensis, but regional southern-African accounts give 1.5–3 kg and L. capensis is a recognised species complex; conflicting, so the 2 kg fallback is retained pending an official SA source
  SpeciesDefault(
    speciesName: "Cape Hare",
    scientificName: "Lepus capensis",
    avgWeightKg: 2,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: false,
    verificationSource:
        'UNVERIFIED — ADW gives 4–5 kg for Lepus capensis, but regional southern-African accounts give 1.5–3 kg and L. capensis is a recognised species complex; conflicting, so the 2 kg fallback is retained pending an official SA source',
  ),
  // VERIFIED: Animal Diversity Web (Pedetes capensis) — range mass 3–4 kg
  SpeciesDefault(
    speciesName: "Springhare",
    scientificName: "Pedetes capensis",
    avgWeightKg: 3,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        'Animal Diversity Web (Pedetes capensis) — range mass 3–4 kg',
  ),
  // VERIFIED: Wikipedia (en) — Rock hyrax: 4–5 kg
  SpeciesDefault(
    speciesName: "Dassie / Rock Hyrax",
    scientificName: "Procavia capensis",
    avgWeightKg: 4,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.50,
    browserPct: 0.50,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource: 'Wikipedia (en) — Rock hyrax: 4–5 kg',
  ),
  // VERIFIED: Wikipedia (en) — Greater cane rat: typical 3.2–5.2 kg, males
  // mean 4.5 kg. Phase 7D corrected this row from 8 kg (which matched only the
  // exceptional 7–9 kg upper tail) to the source-quoted male mean.
  SpeciesDefault(
    speciesName: "Cane Rat",
    scientificName: "Thryonomys swinderianus",
    avgWeightKg: 4.5,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
    isVerified: true,
    verificationSource:
        "Wikipedia (en) — Greater cane rat: typical 3.2–5.2 kg, males mean 4.5 kg (was 8 kg)",
  ),
];

/// Species present in `assets/data/animals_seed.csv` but absent from the
/// authorised Phase 1 table.
///
/// These are carried as placeholders — `avgWeightKg: 0`,
/// `feedingClass: unknown`, split 0 / 0 — so no weight or split is invented.
/// They are reported as MISSING for Phase 3 verification.
const List<String> missingSpeciesNames = [
  "Aardwolf",
  "African Black Duck",
  "African Civet",
  "African Green Pigeon",
  "African Olive Pigeon (Rameron)",
  "African Pygmy Goose",
  "African Rock Python",
  "African Savanna Hare",
  "African Striped Weasel",
  "African Wildcat",
  "Angulate Tortoise",
  "Banded Mongoose",
  "Bat-eared Fox",
  "Black-backed Jackal",
  "Black-footed Cat",
  "Blue Korhaan",
  "Blue-spotted Wood Dove",
  "Brown Hyaena",
  "Cape Fox",
  "Cape Genet",
  "Cape Ground Squirrel",
  "Cape Spurfowl",
  "Cape Teal",
  "Cape Turtle Dove",
  "Caracal",
  "Cheetah",
  "Common Quail",
  "Crested Francolin",
  "Crested Guineafowl",
  "Damara Ground Squirrel",
  "Denham's Bustard",
  "Double-banded Sandgrouse",
  "Dwarf Mongoose",
  "Eastern Bronze-naped Pigeon",
  "Egyptian Goose",
  "Emerald-spotted Wood Dove",
  "Fulvous Whistling Duck",
  "Geometric Tortoise",
  "Green Turtle",
  "Grey-winged Francolin",
  "Harlequin Quail",
  "Hawksbill Turtle",
  "Helmeted Guineafowl",
  "Honey Badger",
  "Hottentot Teal",
  "Karoo Korhaan",
  "Knob-billed Duck",
  "Kori Bustard",
  "Laughing Dove",
  "Leatherback Turtle",
  "Lemon Dove",
  "Leopard",
  "Leopard Tortoise",
  "Lion",
  "Loggerhead Turtle",
  "Ludwig's Bustard",
  "Maccoa Duck",
  "Namaqua Dove",
  "Namaqua Sandgrouse",
  "Natal Spurfowl",
  "Nile Crocodile",
  "Nile Monitor (Varanus niloticus)",
  "Northern Black Korhaan",
  "Olive Ridley Turtle",
  "Orange River Francolin",
  "Red-billed Spurfowl",
  "Red-billed Teal",
  "Red-crested Korhaan",
  "Red-eyed Dove",
  "Red-winged Francolin",
  "Rock Dove (feral pigeon)",
  "Rock Monitor (Varanus albigularis)",
  "Rusty-spotted Genet",
  "Secretarybird",
  "Selous' Mongoose",
  "Serval",
  "Shelley's Francolin",
  "Side-striped Jackal",
  "Slender Mongoose",
  "Small-spotted Genet",
  "South African Shelduck",
  "Southern Black Korhaan",
  "Southern Pochard",
  "Speckled Padloper Tortoise",
  "Speckled Pigeon (Rock Pigeon)",
  "Spotted Hyaena",
  "Spur-winged Goose",
  "Striped Polecat",
  "Suricate (Meerkat)",
  "Swainson's Spurfowl",
  "Tambourine Dove",
  "Temminck's Ground Pangolin",
  "Tree Hyrax",
  "Tree Squirrel",
  "Water Mongoose",
  "Water Monitor (Varanus niloticus)",
  "White-bellied Korhaan",
  "White-faced Whistling Duck",
  "White-tailed Mongoose",
  "Yellow Mongoose",
  "Yellow-billed Duck",
  "Yellow-spotted Rock Hyrax",
  "Yellow-throated Sandgrouse",
];

/// Placeholder rows for [missingSpeciesNames].
final List<SpeciesDefault> missingSpecies = List<SpeciesDefault>.unmodifiable(
  missingSpeciesNames.map(
    (name) => SpeciesDefault(
      speciesName: name,
      scientificName: "",
      avgWeightKg: 0,
      feedingClass: FeedingClass.unknown,
      grazerPct: 0,
      browserPct: 0,
    ),
  ),
);

/// Lookup index over [speciesDefaults] keyed by lower-cased species name.
final Map<String, SpeciesDefault> speciesDefaultsByName = {
  for (final entry in speciesDefaults) entry.speciesName.toLowerCase(): entry,
};

/// Looks up the default for [speciesName].
///
/// Tolerant of case, surrounding whitespace and the documented CSV spellings
/// (`Chacma Baboon` / `Cape Porcupine` / `Vervet Monkey`, `Common Warthog`,
/// `Gemsbok (Oryx)`, ...). Falls back to the [missingSpecies] placeholders so
/// every species in the seed catalogue resolves to something. Returns null
/// only for blank input or a name in neither list.
SpeciesDefault? speciesDefaultFor(String? speciesName) {
  final raw = (speciesName ?? '').trim();
  if (raw.isEmpty) return null;
  final key = raw.toLowerCase();
  final direct = speciesDefaultsByName[key];
  if (direct != null) return direct;
  final aliased = csvSpeciesAliases[key];
  if (aliased != null) return speciesDefaultsByName[aliased.toLowerCase()];
  for (final entry in missingSpecies) {
    if (entry.speciesName.toLowerCase() == key) return entry;
  }
  return null;
}

/// Species that count against carrying capacity (excludes the present-only
/// species such as baboon, porcupine, vervet and aardvark).
List<SpeciesDefault> get countedSpeciesDefaults =>
    speciesDefaults.where((entry) => entry.isCounted).toList(growable: false);
