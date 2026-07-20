import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/animal.dart';

class RolandWardMetrics {
  final String rwMinimum;
  final double? earLength;

  const RolandWardMetrics({required this.rwMinimum, this.earLength});
}

const _rolandWardMetrics = <String, RolandWardMetrics>{
  'greater kudu': RolandWardMetrics(rwMinimum: '53.875', earLength: 12.0),
  'kudu (eastern cape)': RolandWardMetrics(rwMinimum: '53.0', earLength: 11.0),
  'kudu (southern greater)': RolandWardMetrics(rwMinimum: '53.875', earLength: 12.0),
  'cape eland': RolandWardMetrics(rwMinimum: '35.0', earLength: 12.0),
  'eland': RolandWardMetrics(rwMinimum: '35.0', earLength: 12.0),
  'eland (cape)': RolandWardMetrics(rwMinimum: '35.0', earLength: 12.0),
  'gemsbok (oryx)': RolandWardMetrics(rwMinimum: '40.0', earLength: 9.0),
  'gemsbok': RolandWardMetrics(rwMinimum: '40.0', earLength: 9.0),
  'nyala': RolandWardMetrics(rwMinimum: '26.0', earLength: 8.5),
  'blue wildebeest': RolandWardMetrics(rwMinimum: '28.5', earLength: 8.0),
  'black wildebeest': RolandWardMetrics(rwMinimum: '22.875', earLength: 6.0),
  'impala': RolandWardMetrics(rwMinimum: '23.5', earLength: 6.0),
  'impala (southern)': RolandWardMetrics(rwMinimum: '23.5', earLength: 6.0),
  'blesbok': RolandWardMetrics(rwMinimum: '16.5', earLength: 6.0),
  'bontebok': RolandWardMetrics(rwMinimum: '14.0', earLength: 6.0),
  'bontebok (purebred)': RolandWardMetrics(rwMinimum: '14.0', earLength: 6.0),
  'cape buffalo': RolandWardMetrics(rwMinimum: '42.0', earLength: 9.0),
  'buffalo (southern african)': RolandWardMetrics(rwMinimum: '42.0', earLength: 9.0),
  'southern bushbuck': RolandWardMetrics(rwMinimum: '15.0', earLength: 6.0),
  'bushbuck (southern african)': RolandWardMetrics(rwMinimum: '15.0', earLength: 6.0),
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
  'common warthog': RolandWardMetrics(rwMinimum: '13.0', earLength: 5.0),
  'springbok': RolandWardMetrics(rwMinimum: '13.0', earLength: 6.0),
  'springbok (cape)': RolandWardMetrics(rwMinimum: '13.0', earLength: 6.0),
  'springbok (kalahari)': RolandWardMetrics(rwMinimum: '13.5', earLength: 7.0),
  'cape grysbok': RolandWardMetrics(rwMinimum: '3.0', earLength: null),
  'grysbok (cape)': RolandWardMetrics(rwMinimum: '3.0', earLength: null),
  "sharpe's grysbok": RolandWardMetrics(rwMinimum: '1.5', earLength: null),
  'grybok (sharp’s)': RolandWardMetrics(rwMinimum: '1.5', earLength: null),
  'red hartebeest': RolandWardMetrics(rwMinimum: '23.0', earLength: 8.0),
  'hartebeest (cape/red)': RolandWardMetrics(rwMinimum: '23.0', earLength: 8.0),
  'hartebeest (lichtensteins)': RolandWardMetrics(rwMinimum: '18.5', earLength: 9.5),
  'oribi': RolandWardMetrics(rwMinimum: '5.5', earLength: 3.5),
  'mountain reedbuck': RolandWardMetrics(rwMinimum: '6.25', earLength: 6.0),
  'southern reedbuck': RolandWardMetrics(rwMinimum: '14.0', earLength: 7.0),
  'common waterbuck': RolandWardMetrics(rwMinimum: '28.0', earLength: 9.0),
  'roan antelope': RolandWardMetrics(rwMinimum: '27.0', earLength: 12.0),
  'sable antelope': RolandWardMetrics(rwMinimum: '40.0', earLength: 9.0),
  'black rhinoceros': RolandWardMetrics(rwMinimum: '24.0', earLength: null),
  'southern white rhinoceros': RolandWardMetrics(rwMinimum: '26.0', earLength: 10.0),
  'hippopotamus': RolandWardMetrics(rwMinimum: '29.5', earLength: null),
  'elephant (african)': RolandWardMetrics(rwMinimum: '80 lb', earLength: null),
  'african elephant': RolandWardMetrics(rwMinimum: '80 lb', earLength: null),
  'leopard (southern african)': RolandWardMetrics(rwMinimum: '15 pts', earLength: null),
  'lion (african)': RolandWardMetrics(rwMinimum: '23 pts', earLength: null),
  'waterbuck (common)': RolandWardMetrics(rwMinimum: '28.0', earLength: 9.0),
  'tsessebe': RolandWardMetrics(rwMinimum: '15.0', earLength: null),
  'steenbok': RolandWardMetrics(rwMinimum: '4.5', earLength: 4.0),
  'suni': RolandWardMetrics(rwMinimum: '2.5', earLength: null),
  'suni (moschatus)': RolandWardMetrics(rwMinimum: '2.5', earLength: null),
  "suni (livingstone's)": RolandWardMetrics(rwMinimum: '3.0', earLength: 3.0),
  'leopard': RolandWardMetrics(rwMinimum: '15 pts', earLength: null),
  'lion': RolandWardMetrics(rwMinimum: '23 pts', earLength: null),
  'bush pig': RolandWardMetrics(rwMinimum: '5.5', earLength: null),
};

String? getRolandWardMinimumForSpecies(String speciesName) {
  final normalizedName = speciesName.trim().toLowerCase();
  return _rolandWardMetrics[normalizedName]?.rwMinimum;
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
    final regions = provinceOfOrigin.isNotEmpty
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

    // Create Animal object
    final animal = Animal(
      id: docId,
      name: commonName,
      scientificName: '', // Not provided in CSV
      category: animalType,
      regions: regions,
      habitat: 'South Africa', // Default habitat
      huntingNotes: huntingNotes.isNotEmpty ? huntingNotes.join('\n') : null,
      recommendedCaliber:
          recommendedCaliber.isNotEmpty && recommendedCaliber != 'N/A'
          ? recommendedCaliber
          : null,
      trophyMinimumRW: getRolandWardMinimumForSpecies(commonName),
      rolandWardMinimum: getRolandWardMinimumForSpecies(commonName),
      rwMinimum: getRolandWardMinimumForSpecies(commonName),
      earLength: getEarLengthForSpecies(commonName),
      imageUrl: imageUrl,
      searchKeywords: [
        commonName.toLowerCase(),
        animalType.toLowerCase(),
        ...regions.map((r) => r.toLowerCase()),
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
