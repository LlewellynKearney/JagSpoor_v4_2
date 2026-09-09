import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/animal.dart';

class RolandWardMetrics {
  final String rwMinimum;
  final double? earLength;
  final String? measurementMethod;
  final String? hornDescription;

  const RolandWardMetrics({
    required this.rwMinimum,
    this.earLength,
    this.measurementMethod,
    this.hornDescription,
  });
}

/// Canonical track-morphology attributes for a species, used to expand the
/// Firestore `animals` dataset with spoor-validation fields.
///
/// [toeCount] is the number of toes the track leaves (4 = paw carnivores,
/// 2 = cloven-hoofed ungulates / suids / giraffids, 1 = solid-hoofed
/// equines). [trackLengthMm] / [trackWidthMm] are the typical fore-print
/// dimensions in millimetres (a single histogram value from the local spoor
/// signature table; stored as min == max until a wider field-measured range
/// is validated). All fields are nullable so a species with no recorded
/// track data (birds, reptiles, rodents, ...) simply omits them.
class TrackMorphology {
  final int? toeCount;
  final double? trackLengthMm;
  final double? trackWidthMm;

  const TrackMorphology({
    this.toeCount,
    this.trackLengthMm,
    this.trackWidthMm,
  });
}

/// Canonical track-morphology dataset for the SA game-guide species.
///
/// Keyed by the same lowercased common-name variants used by
/// [_rolandWardMetrics] / [_scientificNames] (space-keyed CSV common name +
/// underscore alias) so a single lookup resolves the spoor fields. The
/// established toe counts follow `lib/features/track/data/track_taxonomy.dart`
/// morphology (paw carnivores = 4, cloven-hoof ungulates = 2, solid-hoof
/// equines = 1); the length/width values are the established histogram
/// values from `spoor_identifier_service.dart` `_speciesSignatures` where
/// present, otherwise placeholders to be validated against field data.
const _trackMorphology = <String, TrackMorphology>{
  // === Paw carnivores (4 toes) — established from spoor signatures ===
  'leopard': TrackMorphology(toeCount: 4, trackLengthMm: 95.0, trackWidthMm: 90.0),
  'leopard (southern african)': TrackMorphology(
    toeCount: 4,
    trackLengthMm: 95.0,
    trackWidthMm: 90.0,
  ),
  'lion': TrackMorphology(
    toeCount: 4,
    trackLengthMm: 135.0,
    trackWidthMm: 125.0,
  ),
  'lion (african)': TrackMorphology(
    toeCount: 4,
    trackLengthMm: 135.0,
    trackWidthMm: 125.0,
  ),
  'cheetah': TrackMorphology(
    toeCount: 4,
    trackLengthMm: 82.0,
    trackWidthMm: 70.0,
  ),
  'caracal': TrackMorphology(
    toeCount: 4,
    trackLengthMm: 58.0,
    trackWidthMm: 52.0,
  ),
  'serval': TrackMorphology(toeCount: 4),
  'african wildcat': TrackMorphology(
    toeCount: 4,
    trackLengthMm: 38.0,
    trackWidthMm: 34.0,
  ),
  'black-footed cat': TrackMorphology(toeCount: 4),
  'spotted hyaena': TrackMorphology(toeCount: 4),
  'brown hyaena': TrackMorphology(toeCount: 4),
  'aardwolf': TrackMorphology(toeCount: 4),
  'black-backed jackal': TrackMorphology(toeCount: 4),
  'side-striped jackal': TrackMorphology(toeCount: 4),
  'cape fox': TrackMorphology(toeCount: 4),
  'bat-eared fox': TrackMorphology(toeCount: 4),
  'african civet': TrackMorphology(toeCount: 4),
  'small-spotted genet': TrackMorphology(toeCount: 4),
  'rusty-spotted genet': TrackMorphology(toeCount: 4),
  'cape genet': TrackMorphology(toeCount: 4),
  'yellow mongoose': TrackMorphology(toeCount: 4),
  'slender mongoose': TrackMorphology(toeCount: 4),
  'banded mongoose': TrackMorphology(toeCount: 4),
  'dwarf mongoose': TrackMorphology(toeCount: 4),
  'water mongoose': TrackMorphology(toeCount: 4),
  'white-tailed mongoose': TrackMorphology(toeCount: 4),
  "selous' mongoose": TrackMorphology(toeCount: 4),
  'suricate (meerkat)': TrackMorphology(toeCount: 4),
  'striped polecat': TrackMorphology(toeCount: 4),
  'african striped weasel': TrackMorphology(toeCount: 4),
  'honey badger': TrackMorphology(toeCount: 4),

  // === Cloven-hoofed ungulates / suids / giraffids (2 toes) ===
  'kudu': TrackMorphology(toeCount: 2, trackLengthMm: 90.0, trackWidthMm: 60.0),
  'greater_kudu': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 90.0,
    trackWidthMm: 60.0,
  ),
  'greater kudu': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 90.0,
    trackWidthMm: 60.0,
  ),
  'kudu (eastern cape)': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 90.0,
    trackWidthMm: 60.0,
  ),
  'kudu (southern greater)': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 90.0,
    trackWidthMm: 60.0,
  ),
  'impala': TrackMorphology(toeCount: 2, trackLengthMm: 55.0, trackWidthMm: 38.0),
  'impala (southern)': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 55.0,
    trackWidthMm: 38.0,
  ),
  'gemsbok (oryx)': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 85.0,
    trackWidthMm: 60.0,
  ),
  'gemsbok': TrackMorphology(toeCount: 2, trackLengthMm: 85.0, trackWidthMm: 60.0),
  'eland': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 130.0,
    trackWidthMm: 100.0,
  ),
  'cape eland': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 130.0,
    trackWidthMm: 100.0,
  ),
  'eland (cape)': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 130.0,
    trackWidthMm: 100.0,
  ),
  'common warthog': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 70.0,
    trackWidthMm: 50.0,
  ),
  'warthog': TrackMorphology(toeCount: 2, trackLengthMm: 70.0, trackWidthMm: 50.0),
  'bushpig': TrackMorphology(toeCount: 2),
  'bush pig': TrackMorphology(toeCount: 2),
  'nyala': TrackMorphology(toeCount: 2),
  'blue wildebeest': TrackMorphology(toeCount: 2),
  'blue_wildebeest': TrackMorphology(toeCount: 2),
  'black wildebeest': TrackMorphology(toeCount: 2),
  'black_wildebeest': TrackMorphology(toeCount: 2),
  'springbok': TrackMorphology(toeCount: 2),
  'springbok (cape)': TrackMorphology(toeCount: 2),
  'springbok (kalahari)': TrackMorphology(toeCount: 2),
  'blesbok': TrackMorphology(toeCount: 2),
  'bontebok': TrackMorphology(toeCount: 2),
  'bontebok (purebred)': TrackMorphology(toeCount: 2),
  'southern bushbuck': TrackMorphology(toeCount: 2),
  'bushbuck (southern african)': TrackMorphology(toeCount: 2),
  'bushbuck (chobe)': TrackMorphology(toeCount: 2),
  'common waterbuck': TrackMorphology(toeCount: 2),
  'waterbuck': TrackMorphology(toeCount: 2),
  'waterbuck (common)': TrackMorphology(toeCount: 2),
  'red hartebeest': TrackMorphology(toeCount: 2),
  'red_hartebeest': TrackMorphology(toeCount: 2),
  'hartebeest (cape/red)': TrackMorphology(toeCount: 2),
  'hartebeest (lichtensteins)': TrackMorphology(toeCount: 2),
  'tsessebe': TrackMorphology(toeCount: 2),
  'sable antelope': TrackMorphology(toeCount: 2),
  'sable': TrackMorphology(toeCount: 2),
  'roan antelope': TrackMorphology(toeCount: 2),
  'common duiker': TrackMorphology(toeCount: 2),
  'blue duiker': TrackMorphology(toeCount: 2),
  'natal red duiker': TrackMorphology(toeCount: 2),
  'red duiker': TrackMorphology(toeCount: 2),
  'steenbok': TrackMorphology(toeCount: 2),
  'cape grysbok': TrackMorphology(toeCount: 2),
  'grysbok (cape)': TrackMorphology(toeCount: 2),
  "sharpe's grysbok": TrackMorphology(toeCount: 2),
  'oribi': TrackMorphology(toeCount: 2),
  'mountain reedbuck': TrackMorphology(toeCount: 2),
  'southern reedbuck': TrackMorphology(toeCount: 2),
  'suni': TrackMorphology(toeCount: 2),
  'suni (moschatus)': TrackMorphology(toeCount: 2),
  "suni (livingstone's)": TrackMorphology(toeCount: 2),
  'klipspringer': TrackMorphology(toeCount: 2),
  'giraffe': TrackMorphology(toeCount: 2),
  'dik-dik (damaraland)': TrackMorphology(toeCount: 2),

  // === Solid-hoofed equines (1 toe) ===
  'plains zebra': TrackMorphology(
    toeCount: 1,
    trackLengthMm: 110.0,
    trackWidthMm: 100.0,
  ),
  'zebra': TrackMorphology(toeCount: 1, trackLengthMm: 110.0, trackWidthMm: 100.0),
  'cape mountain zebra': TrackMorphology(toeCount: 1),
  "hartmann's mountain zebra": TrackMorphology(toeCount: 1),
  'donkey': TrackMorphology(toeCount: 1, trackLengthMm: 95.0, trackWidthMm: 85.0),
  'horse': TrackMorphology(toeCount: 1),

  // === Dangerous game / megafauna (cloven, 2 toes) ===
  'cape buffalo': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 150.0,
    trackWidthMm: 140.0,
  ),
  'cape_buffalo': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 150.0,
    trackWidthMm: 140.0,
  ),
  'buffalo (southern african)': TrackMorphology(
    toeCount: 2,
    trackLengthMm: 150.0,
    trackWidthMm: 140.0,
  ),
  'african elephant': TrackMorphology(toeCount: 4),
  'elephant (african)': TrackMorphology(toeCount: 4),
  'black rhinoceros': TrackMorphology(toeCount: 3),
  'southern white rhinoceros': TrackMorphology(toeCount: 3),
  'hippopotamus': TrackMorphology(toeCount: 4),
};

const _rolandWardMetrics = <String, RolandWardMetrics>{
  // Spiral Curve Method (Method 8) — official SA Rowland Ward minimum 53 7/8".
  'kudu': RolandWardMetrics(
    rwMinimum: '53 7/8 inches',
    earLength: 12.0,
    measurementMethod: 'Method 8 - Spiral Curve',
    hornDescription: 'Horn length measured along spiral',
  ),
  'greater_kudu': RolandWardMetrics(
    rwMinimum: '53 7/8 inches',
    earLength: 12.0,
    measurementMethod: 'Method 8 - Spiral Curve',
    hornDescription: 'Horn length measured along spiral',
  ),
  'greater kudu': RolandWardMetrics(
    rwMinimum: '53 7/8 inches',
    earLength: 12.0,
    measurementMethod: 'Method 8 - Spiral Curve',
    hornDescription: 'Horn length measured along spiral',
  ),
  'kudu (eastern cape)': RolandWardMetrics(
    rwMinimum: '53 7/8 inches',
    earLength: 11.0,
    measurementMethod: 'Method 8 - Spiral Curve',
    hornDescription: 'Horn length measured along spiral',
  ),
  'kudu (southern greater)': RolandWardMetrics(
    rwMinimum: '53 7/8 inches',
    earLength: 12.0,
    measurementMethod: 'Method 8 - Spiral Curve',
    hornDescription: 'Horn length measured along spiral',
  ),
  // Cape Eland - Horn Length (Method 8) — official SA minimum 35".
  'cape eland': RolandWardMetrics(
    rwMinimum: '35 inches',
    earLength: 12.0,
    measurementMethod: 'Method 8 - Horn Length',
    hornDescription: 'Horn length measured along curve',
  ),
  'eland': RolandWardMetrics(
    rwMinimum: '35 inches',
    earLength: 12.0,
    measurementMethod: 'Method 8 - Horn Length',
    hornDescription: 'Horn length measured along curve',
  ),
  'eland (cape)': RolandWardMetrics(
    rwMinimum: '35 inches',
    earLength: 12.0,
    measurementMethod: 'Method 8 - Horn Length',
    hornDescription: 'Horn length measured along curve',
  ),
  // Gemsbok - Horn Length (Method 7-a) — official SA minimum 40".
  'gemsbok (oryx)': RolandWardMetrics(
    rwMinimum: '40 inches',
    earLength: 9.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length straight line',
  ),
  'gemsbok': RolandWardMetrics(
    rwMinimum: '40 inches',
    earLength: 9.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length straight line',
  ),
  // Nyala - Spiral Curve (Method 8) — official SA minimum 27".
  'nyala': RolandWardMetrics(
    rwMinimum: '27 inches',
    earLength: 8.5,
    measurementMethod: 'Method 8 - Spiral Curve',
    hornDescription: 'Horn length along spiral',
  ),
  // Blue Wildebeest - Outside Spread (Method 13) — official SA minimum 28 1/2".
  'blue wildebeest': RolandWardMetrics(
    rwMinimum: '28 1/2 inches',
    earLength: 8.0,
    measurementMethod: 'Method 13 - Outside Spread',
    hornDescription: 'Horn spread measured outside',
  ),
  'blue_wildebeest': RolandWardMetrics(
    rwMinimum: '28 1/2 inches',
    earLength: 8.0,
    measurementMethod: 'Method 13 - Outside Spread',
    hornDescription: 'Horn spread measured outside',
  ),
  // Black Wildebeest - Boss Curve (Method 13) — official SA minimum 22 7/8".
  'black wildebeest': RolandWardMetrics(
    rwMinimum: '22 7/8 inches',
    earLength: 6.0,
    measurementMethod: 'Method 13 - Boss Curve',
    hornDescription: 'Boss curve measurement',
  ),
  'black_wildebeest': RolandWardMetrics(
    rwMinimum: '22 7/8 inches',
    earLength: 6.0,
    measurementMethod: 'Method 13 - Boss Curve',
    hornDescription: 'Boss curve measurement',
  ),
  // Impala - Straight Line (Method 7-a) — official SA minimum 23 5/8".
  'impala': RolandWardMetrics(
    rwMinimum: '23 5/8 inches',
    earLength: 6.0,
    measurementMethod: 'Method 7-a - Straight Line',
    hornDescription: 'Horn length straight line',
  ),
  'impala (southern)': RolandWardMetrics(
    rwMinimum: '23 5/8 inches',
    earLength: 6.0,
    measurementMethod: 'Method 7-a - Straight Line',
    hornDescription: 'Horn length straight line',
  ),
  // Blesbok - Ridge Length (Method 7-a) — official SA minimum 16 1/2".
  'blesbok': RolandWardMetrics(
    rwMinimum: '16 1/2 inches',
    earLength: 6.0,
    measurementMethod: 'Method 7-a - Ridge Length',
    hornDescription: 'Horn ridge length',
  ),
  'bontebok': RolandWardMetrics(
    rwMinimum: '14" (35.6 cm)',
    earLength: 6.0,
    measurementMethod: 'Method 7-a - Ridge Length',
    hornDescription: 'Horn ridge length',
  ),
  'bontebok (purebred)': RolandWardMetrics(
    rwMinimum: '14" (35.6 cm)',
    earLength: 6.0,
    measurementMethod: 'Method 7-a - Ridge Length',
    hornDescription: 'Horn ridge length',
  ),
  // Cape Buffalo - official SA minimum 42".
  'cape buffalo': RolandWardMetrics(
    rwMinimum: '42 inches',
    earLength: 9.0,
    measurementMethod: 'Method 22 - Tip-to-tip spread',
    hornDescription: 'Boss width / tip-to-tip spread',
  ),
  'cape_buffalo': RolandWardMetrics(
    rwMinimum: '42 inches',
    earLength: 9.0,
    measurementMethod: 'Method 22 - Tip-to-tip spread',
    hornDescription: 'Boss width / tip-to-tip spread',
  ),
  'buffalo (southern african)': RolandWardMetrics(
    rwMinimum: '42 inches',
    earLength: 9.0,
    measurementMethod: 'Method 22 - Tip-to-tip spread',
    hornDescription: 'Boss width / tip-to-tip spread',
  ),
  // Common Warthog - Upper Tusk Curve (Method 5) — official SA minimum 13".
  'common warthog': RolandWardMetrics(
    rwMinimum: '13 inches',
    earLength: 5.0,
    measurementMethod: 'Method 5 - Upper Tusk Curve',
    hornDescription: 'Upper tusk curve length',
  ),
  'warthog': RolandWardMetrics(
    rwMinimum: '13 inches',
    earLength: 5.0,
    measurementMethod: 'Method 5 - Upper Tusk Curve',
    hornDescription: 'Upper tusk curve length',
  ),
  // Springbok - Curve Length (Method 7-a) — official SA minimum 14".
  'springbok': RolandWardMetrics(
    rwMinimum: '14 inches',
    earLength: 6.0,
    measurementMethod: 'Method 7-a - Curve Length',
    hornDescription: 'Horn curve length',
  ),
  'springbok (cape)': RolandWardMetrics(
    rwMinimum: '14 inches',
    earLength: 6.0,
    measurementMethod: 'Method 7-a - Curve Length',
    hornDescription: 'Horn curve length',
  ),
  'springbok (kalahari)': RolandWardMetrics(
    rwMinimum: '14 inches',
    earLength: 7.0,
    measurementMethod: 'Method 7-a - Curve Length',
    hornDescription: 'Horn curve length',
  ),
  'southern bushbuck': RolandWardMetrics(rwMinimum: '15.0', earLength: 6.0),
  'bushbuck (southern african)': RolandWardMetrics(
    rwMinimum: '15.0',
    earLength: 6.0,
  ),
  'bushbuck (chobe)': RolandWardMetrics(rwMinimum: '14.0', earLength: 9.0),
  'cheetah': RolandWardMetrics(rwMinimum: '12.5', earLength: null),
  'nile crocodile': RolandWardMetrics(rwMinimum: '14 ft', earLength: null),
  'crocodile (nile)': RolandWardMetrics(rwMinimum: '14 ft', earLength: null),
  'dik-dik (damaraland)': RolandWardMetrics(rwMinimum: '2.75', earLength: null),
  'blue duiker': RolandWardMetrics(rwMinimum: '1.75', earLength: null),
  'natal red duiker': RolandWardMetrics(rwMinimum: '2.5', earLength: null),
  'red duiker': RolandWardMetrics(rwMinimum: '2.5', earLength: null),
  'common duiker': RolandWardMetrics(rwMinimum: '4.75', earLength: 4.0),
  'bushpig': RolandWardMetrics(rwMinimum: '5.5', earLength: null),
  'cape grysbok': RolandWardMetrics(rwMinimum: '3.0', earLength: null),
  'grysbok (cape)': RolandWardMetrics(rwMinimum: '3.0', earLength: null),
  "sharpe's grysbok": RolandWardMetrics(rwMinimum: '1.5', earLength: null),
  'grybok (sharp’s)': RolandWardMetrics(rwMinimum: '1.5', earLength: null),
  // Red Hartebeest — official SA minimum 23".
  'red hartebeest': RolandWardMetrics(
    rwMinimum: '23 inches',
    earLength: 8.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length over the curve',
  ),
  'red_hartebeest': RolandWardMetrics(
    rwMinimum: '23 inches',
    earLength: 8.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length over the curve',
  ),
  'hartebeest (cape/red)': RolandWardMetrics(
    rwMinimum: '23 inches',
    earLength: 8.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length over the curve',
  ),
  'hartebeest (lichtensteins)': RolandWardMetrics(
    rwMinimum: '18.5',
    earLength: 9.5,
  ),
  'oribi': RolandWardMetrics(rwMinimum: '5.5', earLength: 3.5),
  'mountain reedbuck': RolandWardMetrics(rwMinimum: '6.25', earLength: 6.0),
  'southern reedbuck': RolandWardMetrics(rwMinimum: '14.0', earLength: 7.0),
  // Common Waterbuck — official SA minimum 28".
  'common waterbuck': RolandWardMetrics(
    rwMinimum: '28 inches',
    earLength: 9.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length straight line',
  ),
  'waterbuck': RolandWardMetrics(
    rwMinimum: '28 inches',
    earLength: 9.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length straight line',
  ),
  'roan antelope': RolandWardMetrics(rwMinimum: '27.0', earLength: 12.0),
  // Sable Antelope — official SA minimum 41 7/8".
  'sable antelope': RolandWardMetrics(
    rwMinimum: '41 7/8 inches',
    earLength: 9.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length over the curve',
  ),
  'sable': RolandWardMetrics(
    rwMinimum: '41 7/8 inches',
    earLength: 9.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length over the curve',
  ),
  'black rhinoceros': RolandWardMetrics(rwMinimum: '24.0', earLength: null),
  'southern white rhinoceros': RolandWardMetrics(
    rwMinimum: '26.0',
    earLength: 10.0,
  ),
  'hippopotamus': RolandWardMetrics(rwMinimum: '29.5', earLength: null),
  'elephant (african)': RolandWardMetrics(rwMinimum: '80 lb', earLength: null),
  'african elephant': RolandWardMetrics(rwMinimum: '80 lb', earLength: null),
  'leopard (southern african)': RolandWardMetrics(
    rwMinimum: '15 pts',
    earLength: null,
  ),
  'lion (african)': RolandWardMetrics(rwMinimum: '23 pts', earLength: null),
  'waterbuck (common)': RolandWardMetrics(
    rwMinimum: '28 inches',
    earLength: 9.0,
    measurementMethod: 'Method 7-a - Horn Length',
    hornDescription: 'Horn length straight line',
  ),
  'tsessebe': RolandWardMetrics(rwMinimum: '15.0', earLength: null),
  'steenbok': RolandWardMetrics(rwMinimum: '4.5', earLength: 4.0),
  'suni': RolandWardMetrics(rwMinimum: '2.5', earLength: null),
  'suni (moschatus)': RolandWardMetrics(rwMinimum: '2.5', earLength: null),
  "suni (livingstone's)": RolandWardMetrics(rwMinimum: '3.0', earLength: 3.0),
  'leopard': RolandWardMetrics(rwMinimum: '15 pts', earLength: null),
  'lion': RolandWardMetrics(rwMinimum: '23 pts', earLength: null),
  'bush pig': RolandWardMetrics(rwMinimum: '5.5', earLength: null),
};

/// Official scientific (binomial / trinomial) names for the South African
/// game-guide species. Keyed by the same lowercased common-name variants
/// used by [_rolandWardMetrics] (space-keyed CSV common name + underscore
/// alias) so a single lookup resolves both the trophy benchmark and the
/// scientific name. Per v4.5 to-do Item #6.
const _scientificNames = <String, String>{
  // Greater Kudu
  'kudu': 'Tragelaphus strepsiceros',
  'greater_kudu': 'Tragelaphus strepsiceros',
  'greater kudu': 'Tragelaphus strepsiceros',
  'kudu (eastern cape)': 'Tragelaphus strepsiceros',
  'kudu (southern greater)': 'Tragelaphus strepsiceros',
  // Cape Buffalo
  'cape buffalo': 'Syncerus caffer',
  'cape_buffalo': 'Syncerus caffer',
  'buffalo (southern african)': 'Syncerus caffer',
  // Blue Wildebeest
  'blue wildebeest': 'Connochaetes taurinus',
  'blue_wildebeest': 'Connochaetes taurinus',
  // Black Wildebeest
  'black wildebeest': 'Connochaetes gnou',
  'black_wildebeest': 'Connochaetes gnou',
  // Gemsbok (Oryx)
  'gemsbok (oryx)': 'Oryx gazella',
  'gemsbok': 'Oryx gazella',
  // Impala
  'impala': 'Aepyceros melampus',
  'impala (southern)': 'Aepyceros melampus',
  // Springbok
  'springbok': 'Antidorcas marsupialis',
  'springbok (cape)': 'Antidorcas marsupialis',
  'springbok (kalahari)': 'Antidorcas marsupialis',
  // Blesbok
  'blesbok': 'Damaliscus pygargus phillipsi',
  'bontebok': 'Damaliscus pygargus pygargus',
  'bontebok (purebred)': 'Damaliscus pygargus pygargus',
  // Common Warthog
  'common warthog': 'Phacochoerus africanus',
  'warthog': 'Phacochoerus africanus',
  // Eland
  'eland': 'Taurotragus oryx',
  'cape eland': 'Taurotragus oryx',
  'eland (cape)': 'Taurotragus oryx',
  // Sable Antelope
  'sable antelope': 'Hippotragus niger',
  'sable': 'Hippotragus niger',
  // Nyala
  'nyala': 'Tragelaphus angasii',
  // Waterbuck
  'common waterbuck': 'Kobus ellipsiprymnus',
  'waterbuck': 'Kobus ellipsiprymnus',
  'waterbuck (common)': 'Kobus ellipsiprymnus',
  // Red Hartebeest
  'red hartebeest': 'Alcelaphus buselaphus caama',
  'red_hartebeest': 'Alcelaphus buselaphus caama',
  'hartebeest (cape/red)': 'Alcelaphus buselaphus caama',
  // Additional species recorded in the Rowland Ward table
  'southern bushbuck': 'Tragelaphus sylvaticus',
  'bushbuck (southern african)': 'Tragelaphus sylvaticus',
  'bushbuck (chobe)': 'Tragelaphus ornatus',
  'roan antelope': 'Hippotragus equinus',
  'tsessebe': 'Damaliscus lunatus',
  'common duiker': 'Sylvicapra grimmia',
  'red duiker': 'Cephalophus natalensis',
  'natal red duiker': 'Cephalophus natalensis',
  'blue duiker': 'Philantomba monticola',
  'mountain reedbuck': 'Redunca fulvorufula',
  'southern reedbuck': 'Redunca arundinum',
  'steenbok': 'Raphicerus campestris',
  'oribi': 'Ourebia ourebi',
  'cape grysbok': 'Raphicerus melanotis',
  'grysbok (cape)': 'Raphicerus melanotis',
  "sharpe's grysbok": 'Raphicerus sharpei',
  'bushpig': 'Potamochoerus larvatus',
  'bush pig': 'Potamochoerus larvatus',
  'cheetah': 'Acinonyx jubatus',
  'leopard': 'Panthera pardus',
  'leopard (southern african)': 'Panthera pardus',
  'lion': 'Panthera leo',
  'lion (african)': 'Panthera leo',
  'african elephant': 'Loxodonta africana',
  'elephant (african)': 'Loxodonta africana',
  'black rhinoceros': 'Diceros bicornis',
  'southern white rhinoceros': 'Ceratotherium simum simum',
  'hippopotamus': 'Hippopotamus amphibius',
  'nile crocodile': 'Crocodylus niloticus',
  'crocodile (nile)': 'Crocodylus niloticus',
  'dik-dik (damaraland)': 'Madoqua kirkii',
  'suni': 'Neotragus moschatus',
  'suni (moschatus)': 'Neotragus moschatus',
  "suni (livingstone's)": 'Neotragus livingstonianus',
  'klipspringer': 'Oreotragus oreotragus',
  'hartebeest (lichtensteins)': 'Alcelaphus lichtensteinii',
};

/// Resolves the official scientific (binomial) name for a South African
/// game species by its common name (case-insensitive, trimmed). Returns
/// null when the species has no recorded scientific name.
String? getScientificNameForSpecies(String speciesName) {
  final normalizedName = speciesName.trim().toLowerCase();
  return _scientificNames[normalizedName];
}

/// The current game-guide seed version. Bumping this forces every existing
/// app install to re-seed the full `animals` dataset at startup (the
/// `main.dart` startup seeder compares this against the persisted
/// `game_guide_seed_version` SharedPreferences key). Per v4.5 to-do Item #6
/// — earlier installs carried null / empty / em-dash Rowland Ward values and
/// blank scientific names; a version bump re-runs the seeder so the
/// `merge: true` write overwrites those stale fields with the full benchmark
/// data (official RW minimum + measurement method + horn description +
/// scientific name).
///
/// v3 (spoor morphology): adds the canonical track-morphology fields
/// (`toeCount`, `trackLengthMinMm`, `trackLengthMaxMm`, `trackWidthMinMm`,
/// `trackWidthMaxMm`) to every `animals` doc from the `_trackMorphology`
/// dataset, so the Spoor Validation database can expand systematically.
const String gameGuideSeedVersion = 'game_guide_seed_v4';

String? getRolandWardMinimumForSpecies(String speciesName) {
  final normalizedName = speciesName.trim().toLowerCase();
  return _rolandWardMetrics[normalizedName]?.rwMinimum;
}

/// Parses a Rowland Ward minimum trophy benchmark into a numeric value in
/// inches. Handles mixed fractions ('22 7/8 inches' -> 22.875), bare
/// fractions ('7/8' -> 0.875), plain decimals ('35 inches' -> 35.0), and
/// compact whole numbers. The legacy screen-level parser stripped
/// non-numeric characters, so '22 7/8 inches' collapsed to 2278 (and
/// '30.00' vs 2278 read as below-minimum) — this fraction-aware parser is
/// the fix that makes the Field Estimate Verification comparison correct
/// (estimate >= minimum qualifies).
double? parseRolandWardMinimumValue(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final input = value.trim();

  // Pull the integer part when a mixed-fraction string is present
  // ('22 7/8 inches'), so the fraction below adds to it rather than the
  // fraction replacing it.
  final fractionMatch = RegExp(r'(\d+)?\s*(\d+)\s*/\s*(\d+)').firstMatch(input);
  if (fractionMatch != null) {
    final numeratorWhole = fractionMatch.group(1);
    final numerator = double.tryParse(fractionMatch.group(2)!);
    final denominator = double.tryParse(fractionMatch.group(3)!);
    if (numerator != null && denominator != null && denominator > 0) {
      final whole =
          (numeratorWhole != null ? double.tryParse(numeratorWhole) : 0) ?? 0.0;
      return whole + (numerator / denominator);
    }
  }

  // Otherwise take the first plain decimal number in the string.
  final decimalMatch = RegExp(r'\d+(?:\.\d+)?').firstMatch(input);
  if (decimalMatch != null) {
    return double.tryParse(decimalMatch.group(0)!);
  }

  return null;
}

List<String> getRolandWardSpeciesNames() {
  final speciesNames = _rolandWardMetrics.keys.toList();
  speciesNames.sort();
  return speciesNames;
}

RolandWardMetrics? getRolandWardMetricsForSpecies(String speciesName) {
  final normalizedName = speciesName.trim().toLowerCase();
  return _rolandWardMetrics[normalizedName];
}

double? getEarLengthForSpecies(String speciesName) {
  final normalizedName = speciesName.trim().toLowerCase();
  return _rolandWardMetrics[normalizedName]?.earLength;
}

/// Resolves the canonical track-morphology attributes (toe count + typical
/// track length/width in mm) for a South African game species by its common
/// name (case-insensitive, trimmed). Returns null when the species has no
/// recorded track data (birds, reptiles, rodents, ...).
TrackMorphology? getTrackMorphologyForSpecies(String speciesName) {
  final normalizedName = speciesName.trim().toLowerCase();
  return _trackMorphology[normalizedName];
}

/// Resolves the number of toes a species' track leaves (4 = paw carnivores,
/// 2 = cloven-hoofed ungulates / suids / giraffids, 1 = solid-hoofed
/// equines). Returns null for species with no recorded track data.
int? getToeCountForSpecies(String speciesName) {
  return getTrackMorphologyForSpecies(speciesName)?.toeCount;
}

/// Seeds the Firestore 'animals' collection from the CSV file at assets/data/animals_seed.csv
Future<void> seedAnimalsFromCSV() async {
  final firestore = FirebaseFirestore.instance;

  // Load the CSV file from assets
  final csvData = await rootBundle.loadString('assets/data/animals_seed.csv');

  // Parse the CSV data
  final rows = const CsvToListConverter().convert(csvData);

  // Load the image URLs manifest from assets
  Map<String, dynamic> imageManifest = {};
  try {
    final manifestData = await rootBundle.loadString(
      'assets/images/animal_images.json',
    );
    imageManifest = json.decode(manifestData) as Map<String, dynamic>;
    debugPrint('Loaded ${imageManifest.length} image URLs from manifest');
  } catch (e) {
    debugPrint('Warning: Could not load assets/images/animal_images.json: $e');
  }

  // Skip header row (first row)
  final dataRows = rows.skip(1).toList();

  debugPrint('Found ${dataRows.length} animals to seed');

  // Create a batch for Firestore operations
  final batch = firestore.batch();
  int count = 0;

  // Process each row
  for (var i = 0; i < dataRows.length; i++) {
    final row = dataRows[i];

    // Extract values from CSV row
    final commonName = row[0]?.toString() ?? '';
    final recommendedCaliber = row[1]?.toString() ?? '';
    final animalType = row[3]?.toString() ?? '';
    final provinceOfOrigin = row[4]?.toString() ?? '';
    final huntingSeason = row[5]?.toString() ?? '';

    // Skip empty rows
    if (commonName.isEmpty) {
      debugPrint('Skipping empty row ${i + 1}');
      continue;
    }

    // Generate a document ID from the common name (lowercase, spaces replaced with dashes)
    final docId = commonName
        .toLowerCase()
        .replaceAll(' ', '-')
        .replaceAll("'", '');

    // Parse provinces (split by hyphen)
    final regions =
        provinceOfOrigin.isNotEmpty
            ? provinceOfOrigin.split('-').map((p) => p.trim()).toList()
            : <String>[];

    // Build hunting notes from caliber and season
    final huntingNotes = <String>[];
    if (recommendedCaliber.isNotEmpty && recommendedCaliber != 'N/A') {
      huntingNotes.add('Recommended caliber: $recommendedCaliber');
    }
    if (huntingSeason.isNotEmpty && huntingSeason != 'N/A') {
      huntingNotes.add('Season: $huntingSeason');
    }

    // Lookup image URL from manifest
    var imageUrl = imageManifest[commonName]?.toString() ?? '';

    // Explicit overwrite for Nyala to ensure correct male photo
    if (commonName == 'Nyala') {
      imageUrl =
          'https://upload.wikimedia.org/wikipedia/commons/6/6f/Nyala_%28Tragelaphus_angasii%29_male.jpg';
    }

    // Resolve the full Rowland Ward benchmark (official minimum + measurement
    // method + horn description + ear length) and the official scientific
    // name for this species. The seeder writes ALL of these onto the `animals`
    // doc with `merge: true`, so a re-seed (forced by bumping
    // [gameGuideSeedVersion]) overwrites stale null / empty / em-dash
    // Rowland Ward values and blank scientific names on existing installs.
    final rwMetrics = getRolandWardMetricsForSpecies(commonName);
    final rwMinimum = rwMetrics?.rwMinimum ?? getRolandWardMinimumForSpecies(commonName);
    final scientificName = getScientificNameForSpecies(commonName) ?? '';

    // Resolve the canonical track-morphology attributes (toe count + typical
    // track length/width in mm) for this species. A single histogram value
    // from the spoor signature table is stored as min == max until a wider
    // field-measured range is validated; species without track data (birds,
    // reptiles, rodents, ...) simply omit all five fields.
    final trackMorphology = getTrackMorphologyForSpecies(commonName);

    // Create Animal object
    final animal = Animal(
      id: docId,
      name: commonName,
      scientificName: scientificName,
      category: animalType,
      regions: regions,
      habitat: 'South Africa', // Default habitat
      huntingNotes: huntingNotes.isNotEmpty ? huntingNotes.join('\n') : null,
      recommendedCaliber:
          recommendedCaliber.isNotEmpty && recommendedCaliber != 'N/A'
              ? recommendedCaliber
              : null,
      trophyMinimumRW: rwMinimum,
      rolandWardMinimum: rwMinimum,
      rwMinimum: rwMinimum,
      earLength: rwMetrics?.earLength ?? getEarLengthForSpecies(commonName),
      rwMeasurementMethod: rwMetrics?.measurementMethod,
      rwHornDescription: rwMetrics?.hornDescription,
      toeCount: trackMorphology?.toeCount,
      trackLengthMinMm: trackMorphology?.trackLengthMm,
      trackLengthMaxMm: trackMorphology?.trackLengthMm,
      trackWidthMinMm: trackMorphology?.trackWidthMm,
      trackWidthMaxMm: trackMorphology?.trackWidthMm,
      imageUrl: imageUrl,
      searchKeywords: [
        commonName.toLowerCase(),
        animalType.toLowerCase(),
        ...regions.map((r) => r.toLowerCase()),
        if (scientificName.isNotEmpty) scientificName.toLowerCase(),
      ],
      sortOrder: i,
      updatedAt: DateTime.now(),
    );

    // Add to batch using set with merge: true to avoid wiping other fields if already populated
    final docRef = firestore.collection('animals').doc(docId);
    batch.set(docRef, animal.toJson(), SetOptions(merge: true));
    count++;

    debugPrint('✓ Prepared: $commonName ($count/${dataRows.length})');
  }

  // Commit the batch
  debugPrint('\nCommitting batch to Firestore...');
  await batch.commit();

  debugPrint('\nSeeding complete!');
  debugPrint('Total animals seeded: $count');
}
