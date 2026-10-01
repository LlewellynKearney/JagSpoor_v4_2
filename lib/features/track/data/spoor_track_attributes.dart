import 'track_taxonomy.dart';

/// Morphological spoor attributes for a species, used by the structured
/// validation layer to cross-check raw camera classifications.
///
/// The attributes are the discriminators a tracker uses on the ground:
/// * [toeCount] — the canonical number of toes/cleaves (4 for a felid paw,
///   including the four main toes; 2 for a cloven-hoofed ungulate; 1 for a
///   solid-hoofed equine).
/// * [lengthMinMm] / [lengthMaxMm] — expected print-length range.
/// * [widthMinMm] / [widthMaxMm] — expected print-width range.
///
/// Attributes may be hydrated from a Firestore `animals` document (so admins
/// can refine them without a code change) or from the built-in fallback
/// table when the database has no record / is unreachable.
class SpoorTrackAttributes {
  final String species;
  final int toeCount;
  final double lengthMinMm;
  final double lengthMaxMm;
  final double widthMinMm;
  final double widthMaxMm;
  final TrackCategory category;

  const SpoorTrackAttributes({
    required this.species,
    required this.toeCount,
    required this.lengthMinMm,
    required this.lengthMaxMm,
    required this.widthMinMm,
    required this.widthMaxMm,
    this.category = TrackCategory.clovenHoofUngulate,
  });

  /// Hydrates attributes from a Firestore `animals` document map.
  ///
  /// Numeric strings are tolerated; a missing/invalid field falls back to
  /// [fallback] (typically the built-in table) so a partial document never
  /// yields a null/empty attribute set.
  factory SpoorTrackAttributes.fromMap(
    Map<String, dynamic> data, {
    required String species,
    SpoorTrackAttributes? fallback,
  }) {
    final fb = fallback ?? spoorTrackAttributesFallback[species];
    final toe = _intOrNull(
      data['toeCount'] ??
          data['toe_count'] ??
          data['hoofCount'] ??
          data['pawToes'],
    );
    final lenMin = _doubleOrNull(
      data['trackLengthMinMm'] ??
          data['track_length_min_mm'] ??
          data['printLengthMinMm'],
    );
    final lenMax = _doubleOrNull(
      data['trackLengthMaxMm'] ??
          data['track_length_max_mm'] ??
          data['printLengthMaxMm'],
    );
    final widMin = _doubleOrNull(
      data['trackWidthMinMm'] ??
          data['track_width_min_mm'] ??
          data['printWidthMinMm'],
    );
    final widMax = _doubleOrNull(
      data['trackWidthMaxMm'] ??
          data['track_width_max_mm'] ??
          data['printWidthMaxMm'],
    );

    final resolvedToe = toe ?? ((fb != null) ? fb.toeCount : 0);
    final resolvedLenMin = lenMin ?? ((fb != null) ? fb.lengthMinMm : 0);
    final resolvedLenMax =
        lenMax ?? ((fb != null) ? fb.lengthMaxMm : resolvedLenMin);
    final resolvedWidMin = widMin ?? ((fb != null) ? fb.widthMinMm : 0);
    final resolvedWidMax =
        widMax ?? ((fb != null) ? fb.widthMaxMm : resolvedWidMin);
    final resolvedCategory =
        (fb != null) ? fb.category : categoryForSpecies(species);

    return SpoorTrackAttributes(
      species: species,
      toeCount: resolvedToe,
      lengthMinMm: resolvedLenMin,
      lengthMaxMm: resolvedLenMax,
      widthMinMm: resolvedWidMin,
      widthMaxMm: resolvedWidMax,
      category: resolvedCategory,
    );
  }

  /// Whether the geometry is compatible with these attributes.
  ///
  /// A candidate passes when BOTH the estimated toe count matches (when the
  /// count could be estimated) AND the calibrated print length/width fall
  /// within the species' expected ranges (tolerating a small overlap slack).
  bool matches({
    required int? estimatedToeCount,
    required double? printLengthMm,
    required double? printWidthMm,
    double slackMm = 8.0,
    bool requireToeCount = true,
  }) {
    if (requireToeCount &&
        estimatedToeCount != null &&
        estimatedToeCount > 0 &&
        toeCount > 0 &&
        estimatedToeCount != toeCount) {
      return false;
    }
    if (printLengthMm != null && lengthMaxMm > 0) {
      final lenMargin = (lengthMaxMm - lengthMinMm).abs() + slackMm;
      if (printLengthMm < lengthMinMm - slackMm ||
          printLengthMm > lengthMaxMm + slackMm) {
        // Allow a generous catch-all for unidentified/median species when the
        // DB range is very tight and the observation is close.
        if (lenMargin > 0 &&
            (printLengthMm - lengthMinMm).abs() > lenMargin * 1.5) {
          return false;
        }
      }
    }
    if (printWidthMm != null && widthMaxMm > 0) {
      final widMargin = (widthMaxMm - widthMinMm).abs() + slackMm;
      if (printWidthMm < widthMinMm - slackMm ||
          printWidthMm > widthMaxMm + slackMm) {
        if (widMargin > 0 &&
            (printWidthMm - widthMinMm).abs() > widMargin * 1.5) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  String toString() =>
      '$species (toes: $toeCount, L: ${lengthMinMm.toStringAsFixed(0)}–${lengthMaxMm.toStringAsFixed(0)} mm, '
      'W: ${widthMinMm.toStringAsFixed(0)}–${widthMaxMm.toStringAsFixed(0)} mm)';

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _doubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Whether the DB hydration actually supplied any spoor field.
  static bool anySpoorFieldPresent(Map<String, dynamic> data) {
    return data.containsKey('toeCount') ||
        data.containsKey('toe_count') ||
        data.containsKey('hoofCount') ||
        data.containsKey('trackLengthMinMm') ||
        data.containsKey('track_length_min_mm') ||
        data.containsKey('trackWidthMaxMm') ||
        data.containsKey('track_width_max_mm');
  }
}

/// Built-in fallback spoor attributes keyed by canonical species name.
///
/// This doubles as the offline baseline when the Firestore `animals`
/// collection is unreachable or a species has no stored record. Dimensions
/// are mature-field averages; ranges widen with the observed variance.
const Map<String, SpoorTrackAttributes> spoorTrackAttributesFallback = {
  // Felid / carnivore paws — 4 toes + a three-lobed heel pad.
  'Leopard': SpoorTrackAttributes(
    species: 'Leopard',
    toeCount: 4,
    lengthMinMm: 85,
    lengthMaxMm: 105,
    widthMinMm: 80,
    widthMaxMm: 100,
    category: TrackCategory.pawCarnivore,
  ),
  'Lion': SpoorTrackAttributes(
    species: 'Lion',
    toeCount: 4,
    lengthMinMm: 120,
    lengthMaxMm: 150,
    widthMinMm: 110,
    widthMaxMm: 140,
    category: TrackCategory.pawCarnivore,
  ),
  'Cheetah': SpoorTrackAttributes(
    species: 'Cheetah',
    toeCount: 4,
    lengthMinMm: 72,
    lengthMaxMm: 92,
    widthMinMm: 60,
    widthMaxMm: 80,
    category: TrackCategory.pawCarnivore,
  ),
  'Caracal': SpoorTrackAttributes(
    species: 'Caracal',
    toeCount: 4,
    lengthMinMm: 48,
    lengthMaxMm: 68,
    widthMinMm: 42,
    widthMaxMm: 62,
    category: TrackCategory.pawCarnivore,
  ),
  'Wild Cat': SpoorTrackAttributes(
    species: 'Wild Cat',
    toeCount: 4,
    lengthMinMm: 30,
    lengthMaxMm: 46,
    widthMinMm: 26,
    widthMaxMm: 42,
    category: TrackCategory.pawCarnivore,
  ),
  'Wildcat': SpoorTrackAttributes(
    species: 'Wildcat',
    toeCount: 4,
    lengthMinMm: 30,
    lengthMaxMm: 46,
    widthMinMm: 26,
    widthMaxMm: 42,
    category: TrackCategory.pawCarnivore,
  ),
  'Hyena': SpoorTrackAttributes(
    species: 'Hyena',
    toeCount: 4,
    lengthMinMm: 95,
    lengthMaxMm: 125,
    widthMinMm: 80,
    widthMaxMm: 105,
    category: TrackCategory.pawCarnivore,
  ),
  'Jackal': SpoorTrackAttributes(
    species: 'Jackal',
    toeCount: 4,
    lengthMinMm: 55,
    lengthMaxMm: 70,
    widthMinMm: 40,
    widthMaxMm: 52,
    category: TrackCategory.pawCarnivore,
  ),
  'Serval': SpoorTrackAttributes(
    species: 'Serval',
    toeCount: 4,
    lengthMinMm: 45,
    lengthMaxMm: 60,
    widthMinMm: 38,
    widthMaxMm: 50,
    category: TrackCategory.pawCarnivore,
  ),

  // Cloven-hoofed ungulates — 2 cleaves.
  'Kudu': SpoorTrackAttributes(
    species: 'Kudu',
    toeCount: 2,
    lengthMinMm: 75,
    lengthMaxMm: 105,
    widthMinMm: 50,
    widthMaxMm: 70,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Cape Buffalo': SpoorTrackAttributes(
    species: 'Cape Buffalo',
    toeCount: 2,
    lengthMinMm: 130,
    lengthMaxMm: 170,
    widthMinMm: 120,
    widthMaxMm: 160,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Buffalo': SpoorTrackAttributes(
    species: 'Buffalo',
    toeCount: 2,
    lengthMinMm: 130,
    lengthMaxMm: 170,
    widthMinMm: 120,
    widthMaxMm: 160,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Impala': SpoorTrackAttributes(
    species: 'Impala',
    toeCount: 2,
    lengthMinMm: 45,
    lengthMaxMm: 62,
    widthMinMm: 30,
    widthMaxMm: 42,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Gemsbok': SpoorTrackAttributes(
    species: 'Gemsbok',
    toeCount: 2,
    lengthMinMm: 72,
    lengthMaxMm: 95,
    widthMinMm: 48,
    widthMaxMm: 68,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Eland': SpoorTrackAttributes(
    species: 'Eland',
    toeCount: 2,
    lengthMinMm: 115,
    lengthMaxMm: 145,
    widthMinMm: 88,
    widthMaxMm: 112,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Warthog': SpoorTrackAttributes(
    species: 'Warthog',
    toeCount: 2,
    lengthMinMm: 58,
    lengthMaxMm: 80,
    widthMinMm: 40,
    widthMaxMm: 58,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Nyala': SpoorTrackAttributes(
    species: 'Nyala',
    toeCount: 2,
    lengthMinMm: 70,
    lengthMaxMm: 88,
    widthMinMm: 45,
    widthMaxMm: 60,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Springbok': SpoorTrackAttributes(
    species: 'Springbok',
    toeCount: 2,
    lengthMinMm: 40,
    lengthMaxMm: 55,
    widthMinMm: 26,
    widthMaxMm: 36,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Blesbok': SpoorTrackAttributes(
    species: 'Blesbok',
    toeCount: 2,
    lengthMinMm: 50,
    lengthMaxMm: 62,
    widthMinMm: 32,
    widthMaxMm: 42,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Hartebeest': SpoorTrackAttributes(
    species: 'Hartebeest',
    toeCount: 2,
    lengthMinMm: 78,
    lengthMaxMm: 90,
    widthMinMm: 48,
    widthMaxMm: 58,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Red Hartebeest': SpoorTrackAttributes(
    species: 'Red Hartebeest',
    toeCount: 2,
    lengthMinMm: 78,
    lengthMaxMm: 90,
    widthMinMm: 48,
    widthMaxMm: 58,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Wildebeest': SpoorTrackAttributes(
    species: 'Wildebeest',
    toeCount: 2,
    lengthMinMm: 85,
    lengthMaxMm: 105,
    widthMinMm: 60,
    widthMaxMm: 80,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Blue Wildebeest': SpoorTrackAttributes(
    species: 'Blue Wildebeest',
    toeCount: 2,
    lengthMinMm: 85,
    lengthMaxMm: 105,
    widthMinMm: 60,
    widthMaxMm: 80,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Roan Antelope': SpoorTrackAttributes(
    species: 'Roan Antelope',
    toeCount: 2,
    lengthMinMm: 95,
    lengthMaxMm: 115,
    widthMinMm: 65,
    widthMaxMm: 80,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Sable Antelope': SpoorTrackAttributes(
    species: 'Sable Antelope',
    toeCount: 2,
    lengthMinMm: 88,
    lengthMaxMm: 108,
    widthMinMm: 55,
    widthMaxMm: 70,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Bushbuck': SpoorTrackAttributes(
    species: 'Bushbuck',
    toeCount: 2,
    lengthMinMm: 55,
    lengthMaxMm: 68,
    widthMinMm: 36,
    widthMaxMm: 46,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Duiker': SpoorTrackAttributes(
    species: 'Duiker',
    toeCount: 2,
    lengthMinMm: 30,
    lengthMaxMm: 42,
    widthMinMm: 18,
    widthMaxMm: 28,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Steenbok': SpoorTrackAttributes(
    species: 'Steenbok',
    toeCount: 2,
    lengthMinMm: 28,
    lengthMaxMm: 38,
    widthMinMm: 16,
    widthMaxMm: 24,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Oribi': SpoorTrackAttributes(
    species: 'Oribi',
    toeCount: 2,
    lengthMinMm: 30,
    lengthMaxMm: 40,
    widthMinMm: 18,
    widthMaxMm: 26,
    category: TrackCategory.clovenHoofUngulate,
  ),
  'Giraffe': SpoorTrackAttributes(
    species: 'Giraffe',
    toeCount: 2,
    lengthMinMm: 160,
    lengthMaxMm: 220,
    widthMinMm: 120,
    widthMaxMm: 170,
    category: TrackCategory.clovenHoofUngulate,
  ),

  // Solid-hoofed equines — 1 hoof wall.
  'Zebra': SpoorTrackAttributes(
    species: 'Zebra',
    toeCount: 1,
    lengthMinMm: 95,
    lengthMaxMm: 125,
    widthMinMm: 85,
    widthMaxMm: 115,
    category: TrackCategory.solidHoofEquine,
  ),
  'Donkey': SpoorTrackAttributes(
    species: 'Donkey',
    toeCount: 1,
    lengthMinMm: 80,
    lengthMaxMm: 105,
    widthMinMm: 70,
    widthMaxMm: 95,
    category: TrackCategory.solidHoofEquine,
  ),
  'Horse': SpoorTrackAttributes(
    species: 'Horse',
    toeCount: 1,
    lengthMinMm: 105,
    lengthMaxMm: 135,
    widthMinMm: 90,
    widthMaxMm: 115,
    category: TrackCategory.solidHoofEquine,
  ),
};