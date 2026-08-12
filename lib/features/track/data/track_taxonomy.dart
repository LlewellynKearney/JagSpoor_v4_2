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
  // Paw / carnivores
  'Leopard': TrackCategory.pawCarnivore,
  'Lion': TrackCategory.pawCarnivore,
  'Cheetah': TrackCategory.pawCarnivore,
  'Caracal': TrackCategory.pawCarnivore,
  'Wild Cat': TrackCategory.pawCarnivore,
  'Hyena': TrackCategory.pawCarnivore,
  'Jackal': TrackCategory.pawCarnivore,
  'Serval': TrackCategory.pawCarnivore,
  'Wildcat': TrackCategory.pawCarnivore,

  // Cloven-hoofed / ungulates
  'Kudu': TrackCategory.clovenHoofUngulate,
  'Impala': TrackCategory.clovenHoofUngulate,
  'Gemsbok': TrackCategory.clovenHoofUngulate,
  'Eland': TrackCategory.clovenHoofUngulate,
  'Warthog': TrackCategory.clovenHoofUngulate,
  'Nyala': TrackCategory.clovenHoofUngulate,
  'Springbok': TrackCategory.clovenHoofUngulate,
  'Blesbok': TrackCategory.clovenHoofUngulate,
  'Hartebeest': TrackCategory.clovenHoofUngulate,
  'Red Hartebeest': TrackCategory.clovenHoofUngulate,
  'Blue Wildebeest': TrackCategory.clovenHoofUngulate,
  'Wildebeest': TrackCategory.clovenHoofUngulate,
  'Roan Antelope': TrackCategory.clovenHoofUngulate,
  'Sable Antelope': TrackCategory.clovenHoofUngulate,
  'Bushbuck': TrackCategory.clovenHoofUngulate,
  'Duiker': TrackCategory.clovenHoofUngulate,
  'Steenbok': TrackCategory.clovenHoofUngulate,
  'Oribi': TrackCategory.clovenHoofUngulate,
  'Giraffe': TrackCategory.clovenHoofUngulate,
  'Cape Buffalo': TrackCategory.clovenHoofUngulate,
  'Buffalo': TrackCategory.clovenHoofUngulate,

  // Solid hoof / equines
  'Zebra': TrackCategory.solidHoofEquine,
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
