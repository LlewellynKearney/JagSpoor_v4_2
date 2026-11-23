// FALLBACK — verify — weights/splits authorised by Llewellyn, to be verified
// against official SA tables in Phase 3.
//
// `assets/data/animals_seed.csv` carries no weight, feeding-class or
// grazer/browser split columns, so the table below is the interim source of
// truth for the Veld & Carrying Capacity feature. Values are NOT invented:
// every counted species comes from the table Llewellyn authorised, and every
// species that is absent from that table is carried as a placeholder
// (`avgWeightKg: 0`, `feedingClass: unknown`) and listed in
// [missingSpeciesNames] so it can be filled in during Phase 3.

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
  SpeciesDefault(
    speciesName: "Impala",
    scientificName: "Aepyceros melampus",
    avgWeightKg: 55,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.60,
    browserPct: 0.40,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Greater Kudu",
    scientificName: "Tragelaphus strepsiceros",
    avgWeightKg: 250,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Lesser Kudu",
    scientificName: "Tragelaphus imberbis",
    avgWeightKg: 100,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Nyala",
    scientificName: "Tragelaphus angasii",
    avgWeightKg: 110,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Bushbuck",
    scientificName: "Tragelaphus scriptus",
    avgWeightKg: 45,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Eland",
    scientificName: "Taurotragus oryx",
    avgWeightKg: 600,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.40,
    browserPct: 0.60,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Sable Antelope",
    scientificName: "Hippotragus niger",
    avgWeightKg: 235,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Roan Antelope",
    scientificName: "Hippotragus equinus",
    avgWeightKg: 270,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Gemsbok",
    scientificName: "Oryx gazella",
    avgWeightKg: 210,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.85,
    browserPct: 0.15,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Blue Wildebeest",
    scientificName: "Connochaetes taurinus",
    avgWeightKg: 230,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Black Wildebeest",
    scientificName: "Connochaetes gnou",
    avgWeightKg: 150,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Red Hartebeest",
    scientificName: "Alcelaphus buselaphus",
    avgWeightKg: 150,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Tsessebe",
    scientificName: "Damaliscus lunatus",
    avgWeightKg: 140,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Blesbok",
    scientificName: "Damaliscus pygargus phillipsi",
    avgWeightKg: 70,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Bontebok",
    scientificName: "Damaliscus pygargus pygargus",
    avgWeightKg: 70,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Springbok",
    scientificName: "Antidorcas marsupialis",
    avgWeightKg: 40,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.70,
    browserPct: 0.30,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Waterbuck",
    scientificName: "Kobus ellipsiprymnus",
    avgWeightKg: 220,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Reedbuck (Common)",
    scientificName: "Redunca arundinum",
    avgWeightKg: 55,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Mountain Reedbuck",
    scientificName: "Redunca fulvorufula",
    avgWeightKg: 30,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Grey Rhebok",
    scientificName: "Pelea capreolus",
    avgWeightKg: 20,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.60,
    browserPct: 0.40,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Steenbok",
    scientificName: "Raphicerus campestris",
    avgWeightKg: 12,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Common Duiker",
    scientificName: "Sylvicapra grimmia",
    avgWeightKg: 20,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Blue Duiker",
    scientificName: "Philantomba monticola",
    avgWeightKg: 5,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Red Duiker",
    scientificName: "Cephalophus natalensis",
    avgWeightKg: 14,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Klipspringer",
    scientificName: "Oreotragus oreotragus",
    avgWeightKg: 13,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Cape Grysbok",
    scientificName: "Raphicerus melanotis",
    avgWeightKg: 10,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Sharpe's Grysbok",
    scientificName: "Raphicerus sharpei",
    avgWeightKg: 10,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.30,
    browserPct: 0.70,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Oribi",
    scientificName: "Ourebia ourebi",
    avgWeightKg: 15,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Suni",
    scientificName: "Neotragus moschatus",
    avgWeightKg: 6,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.10,
    browserPct: 0.90,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Giraffe",
    scientificName: "Giraffa camelopardalis",
    avgWeightKg: 1100,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Plains Zebra",
    scientificName: "Equus quagga",
    avgWeightKg: 300,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Mountain Zebra",
    scientificName: "Equus zebra",
    avgWeightKg: 280,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Grevy's Zebra",
    scientificName: "Equus grevyi",
    avgWeightKg: 350,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Warthog",
    scientificName: "Phacochoerus africanus",
    avgWeightKg: 90,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.70,
    browserPct: 0.30,
    isCounted: true,
    isOmnivore: true,
  ),
  SpeciesDefault(
    speciesName: "Bushpig",
    scientificName: "Potamochoerus larvatus",
    avgWeightKg: 80,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.50,
    browserPct: 0.50,
    isCounted: true,
    isOmnivore: true,
  ),
  SpeciesDefault(
    speciesName: "Cape Buffalo",
    scientificName: "Syncerus caffer",
    avgWeightKg: 650,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "African Elephant",
    scientificName: "Loxodonta africana",
    avgWeightKg: 4500,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.40,
    browserPct: 0.60,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "White Rhino",
    scientificName: "Ceratotherium simum",
    avgWeightKg: 2000,
    feedingClass: FeedingClass.grazer,
    grazerPct: 1.00,
    browserPct: 0.00,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Black Rhino",
    scientificName: "Diceros bicornis",
    avgWeightKg: 1200,
    feedingClass: FeedingClass.browser,
    grazerPct: 0.05,
    browserPct: 0.95,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Hippopotamus",
    scientificName: "Hippopotamus amphibius",
    avgWeightKg: 1500,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.95,
    browserPct: 0.05,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Chacma Baboon",
    scientificName: "Papio ursinus",
    avgWeightKg: 25,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.50,
    browserPct: 0.50,
    isCounted: false,
    isOmnivore: true,
  ),
  SpeciesDefault(
    speciesName: "Vervet Monkey",
    scientificName: "Chlorocebus pygerythrus",
    avgWeightKg: 5,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.40,
    browserPct: 0.60,
    isCounted: false,
    isOmnivore: true,
  ),
  SpeciesDefault(
    speciesName: "Cape Porcupine",
    scientificName: "Hystrix africaeaustralis",
    avgWeightKg: 20,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.60,
    browserPct: 0.40,
    isCounted: false,
    isOmnivore: true,
  ),
  SpeciesDefault(
    speciesName: "Aardvark",
    scientificName: "Orycteropus afer",
    avgWeightKg: 60,
    feedingClass: FeedingClass.omnivore,
    grazerPct: 0.00,
    browserPct: 0.00,
    isCounted: false,
    isOmnivore: true,
  ),
  SpeciesDefault(
    speciesName: "Scrub Hare",
    scientificName: "Lepus saxatilis",
    avgWeightKg: 3,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Cape Hare",
    scientificName: "Lepus capensis",
    avgWeightKg: 2,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Springhare",
    scientificName: "Pedetes capensis",
    avgWeightKg: 3,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Dassie / Rock Hyrax",
    scientificName: "Procavia capensis",
    avgWeightKg: 4,
    feedingClass: FeedingClass.mixed,
    grazerPct: 0.50,
    browserPct: 0.50,
    isCounted: true,
    isOmnivore: false,
  ),
  SpeciesDefault(
    speciesName: "Cane Rat",
    scientificName: "Thryonomys swinderianus",
    avgWeightKg: 8,
    feedingClass: FeedingClass.grazer,
    grazerPct: 0.90,
    browserPct: 0.10,
    isCounted: true,
    isOmnivore: false,
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
