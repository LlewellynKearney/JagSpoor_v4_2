// Morphological track taxonomy for the Spoor Identifier.
//
// Tracks fall into three broad morphological categories that are visually
// distinct. Pre-filtering classification candidates by the user-selected
// category prevents cross-type confusion (e.g. a feline paw ever being
// classified as a cloven-hoofed ungulate such as Kudu).

/// The three coarse track morphologies the hunter can pre-select.
enum TrackCategory {
  /// Paw prints with toe pads + (sometimes) claw marks — felids & canids.
  pawCarnivore,

  /// Cloven (two-toed) hoof prints — antelope, bovids, suids.
  clovenHoofUngulate,

  /// Solid single-hoof prints — equines.
  solidHoofEquine,
}

/// A single ranked classification candidate.
class SpoorPrediction {
  final String species;
  final double confidence;

  const SpoorPrediction({required this.species, required this.confidence});

  double get confidencePercent => confidence * 100;

  @override
  String toString() => '$species ${(confidencePercent).toStringAsFixed(1)}%';
}

/// Canonical species → morphological category mapping.
///
/// Any label emitted by the classifier that is not listed here is treated as
/// `clovenHoofUngulate` by default (the most common track type in the region).
const Map<String, TrackCategory> speciesCategoryMap = {
  // Paw / carnivores (4 toes)
  'Leopard': TrackCategory.pawCarnivore,
  'Lion': TrackCategory.pawCarnivore,
  'Cheetah': TrackCategory.pawCarnivore,
  'Caracal': TrackCategory.pawCarnivore,
  'Wild Cat': TrackCategory.pawCarnivore,
  'Wildcat': TrackCategory.pawCarnivore,
  'Hyena': TrackCategory.pawCarnivore,
  'Spotted Hyaena': TrackCategory.pawCarnivore,
  'Brown Hyaena': TrackCategory.pawCarnivore,
  'Jackal': TrackCategory.pawCarnivore,
  'Black-backed Jackal': TrackCategory.pawCarnivore,
  'Side-striped Jackal': TrackCategory.pawCarnivore,
  'Serval': TrackCategory.pawCarnivore,
  'African Wildcat': TrackCategory.pawCarnivore,
  'Black-footed Cat': TrackCategory.pawCarnivore,
  'Aardwolf': TrackCategory.pawCarnivore,
  'Cape Fox': TrackCategory.pawCarnivore,
  'Bat-eared Fox': TrackCategory.pawCarnivore,
  'African Civet': TrackCategory.pawCarnivore,
  'Small-spotted Genet': TrackCategory.pawCarnivore,
  'Rusty-spotted Genet': TrackCategory.pawCarnivore,
  'Cape Genet': TrackCategory.pawCarnivore,
  'Yellow Mongoose': TrackCategory.pawCarnivore,
  'Slender Mongoose': TrackCategory.pawCarnivore,
  'Banded Mongoose': TrackCategory.pawCarnivore,
  'Dwarf Mongoose': TrackCategory.pawCarnivore,
  'Water Mongoose': TrackCategory.pawCarnivore,
  'White-tailed Mongoose': TrackCategory.pawCarnivore,
  "Selous' Mongoose": TrackCategory.pawCarnivore,
  'Suricate': TrackCategory.pawCarnivore,
  'Striped Polecat': TrackCategory.pawCarnivore,
  'African Striped Weasel': TrackCategory.pawCarnivore,
  'Honey Badger': TrackCategory.pawCarnivore,
  'African Elephant': TrackCategory.pawCarnivore,
  'Hippopotamus': TrackCategory.pawCarnivore,

  // Cloven-hoofed / ungulates (2 toes)
  'Kudu': TrackCategory.clovenHoofUngulate,
  'Greater Kudu': TrackCategory.clovenHoofUngulate,
  'Impala': TrackCategory.clovenHoofUngulate,
  'Gemsbok': TrackCategory.clovenHoofUngulate,
  'Eland': TrackCategory.clovenHoofUngulate,
  'Cape Eland': TrackCategory.clovenHoofUngulate,
  'Warthog': TrackCategory.clovenHoofUngulate,
  'Common Warthog': TrackCategory.clovenHoofUngulate,
  'Bushpig': TrackCategory.clovenHoofUngulate,
  'Nyala': TrackCategory.clovenHoofUngulate,
  'Springbok': TrackCategory.clovenHoofUngulate,
  'Blesbok': TrackCategory.clovenHoofUngulate,
  'Bontebok': TrackCategory.clovenHoofUngulate,
  'Hartebeest': TrackCategory.clovenHoofUngulate,
  'Red Hartebeest': TrackCategory.clovenHoofUngulate,
  'Blue Wildebeest': TrackCategory.clovenHoofUngulate,
  'Black Wildebeest': TrackCategory.clovenHoofUngulate,
  'Wildebeest': TrackCategory.clovenHoofUngulate,
  'Roan Antelope': TrackCategory.clovenHoofUngulate,
  'Sable Antelope': TrackCategory.clovenHoofUngulate,
  'Bushbuck': TrackCategory.clovenHoofUngulate,
  'Southern Bushbuck': TrackCategory.clovenHoofUngulate,
  'Duiker': TrackCategory.clovenHoofUngulate,
  'Common Duiker': TrackCategory.clovenHoofUngulate,
  'Blue Duiker': TrackCategory.clovenHoofUngulate,
  'Natal Red Duiker': TrackCategory.clovenHoofUngulate,
  'Steenbok': TrackCategory.clovenHoofUngulate,
  'Cape Grysbok': TrackCategory.clovenHoofUngulate,
  "Sharpe's Grysbok": TrackCategory.clovenHoofUngulate,
  'Oribi': TrackCategory.clovenHoofUngulate,
  'Mountain Reedbuck': TrackCategory.clovenHoofUngulate,
  'Southern Reedbuck': TrackCategory.clovenHoofUngulate,
  'Suni': TrackCategory.clovenHoofUngulate,
  'Tsessebe': TrackCategory.clovenHoofUngulate,
  'Common Waterbuck': TrackCategory.clovenHoofUngulate,
  'Giraffe': TrackCategory.clovenHoofUngulate,
  'Dik-dik': TrackCategory.clovenHoofUngulate,
  'Klipspringer': TrackCategory.clovenHoofUngulate,
  'Cape Buffalo': TrackCategory.clovenHoofUngulate,
  'Buffalo': TrackCategory.clovenHoofUngulate,
  'Black Rhinoceros': TrackCategory.clovenHoofUngulate,
  'Southern White Rhinoceros': TrackCategory.clovenHoofUngulate,

  // Solid hoof / equines (1 toe)
  'Zebra': TrackCategory.solidHoofEquine,
  'Plains Zebra': TrackCategory.solidHoofEquine,
  'Cape Mountain Zebra': TrackCategory.solidHoofEquine,
  "Hartmann's Mountain Zebra": TrackCategory.solidHoofEquine,
  'Donkey': TrackCategory.solidHoofEquine,
  'Horse': TrackCategory.solidHoofEquine,
};

/// Resolves the morphological category for a species label.
TrackCategory categoryForSpecies(String species) {
  final key = species.trim();
  // Exact match first, then case-insensitive.
  if (speciesCategoryMap.containsKey(key)) return speciesCategoryMap[key]!;
  final lower = key.toLowerCase();
  for (final entry in speciesCategoryMap.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return TrackCategory.clovenHoofUngulate;
}

/// Canonical number of toes a track in the given category leaves.
///
/// Paw carnivores (felids, canids, hyaenids, viverrids, herpestids,
/// mustelids) leave 4 toes; cloven-hoofed ungulates / suids / giraffids
/// leave 2; solid-hoofed equines leave 1. This is the single source of
/// truth the seeder's `_trackMorphology` dataset mirrors, so the Firestore
/// `animals.toeCount` field and the spoor classifier always agree.
int toeCountForCategory(TrackCategory c) {
  switch (c) {
    case TrackCategory.pawCarnivore:
      return 4;
    case TrackCategory.clovenHoofUngulate:
      return 2;
    case TrackCategory.solidHoofEquine:
      return 1;
  }
}

/// Human-readable label for a category, shown in the selector UI.
String categoryLabel(TrackCategory c) {
  switch (c) {
    case TrackCategory.pawCarnivore:
      return 'Paw / Carnivore';
    case TrackCategory.clovenHoofUngulate:
      return 'Cloven-Hoofed / Ungulate';
    case TrackCategory.solidHoofEquine:
      return 'Solid Hoof / Equine';
  }
}

/// Short descriptor shown beneath the selector.
String categoryHint(TrackCategory c) {
  switch (c) {
    case TrackCategory.pawCarnivore:
      return 'Leopard, Lion, Cheetah, Caracal, Wild Cat';
    case TrackCategory.clovenHoofUngulate:
      return 'Kudu, Impala, Gemsbok, Eland, Warthog';
    case TrackCategory.solidHoofEquine:
      return 'Zebra, Donkey';
  }
}

/// Anatomical verification prompts the hunter can confirm against the track,
/// per morphological category. These help a user sanity-check a top match
/// rather than trusting a single absolute result.
List<String> verificationPrompts(TrackCategory c) {
  switch (c) {
    case TrackCategory.pawCarnivore:
      return [
        'Claw marks visible ahead of toe pads? (Cheetah yes; felids usually retracted)',
        'Toe pad count = 4 with a distinct three-lobed heel pad?',
        'Track length/width ratio near 1:1 (round) for felids, longer for canids?',
      ];
    case TrackCategory.clovenHoofUngulate:
      return [
        'Two distinct cleaves (toes) — no outer toes touching ground?',
        'Dew claws absent on level ground? (present = heavy/fast animal or mud)',
        'Track longer than wide (cleaves point forward, not round)?',
      ];
    case TrackCategory.solidHoofEquine:
      return [
        'Single solid hoof (one rounded wall, no cleft)?',
        'Hoof roughly round and wider than a cloven antelope track?',
        'Frog (V-shaped centre) visible in the sole impression?',
      ];
  }
}
