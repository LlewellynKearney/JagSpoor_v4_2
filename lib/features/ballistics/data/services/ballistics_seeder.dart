import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class BallisticsSeeder {
  final FirebaseFirestore _firestore;

  BallisticsSeeder({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  int _findHeaderIndex(List<dynamic> headerRow, List<String> possibleNames) {
    for (int i = 0; i < headerRow.length; i++) {
      final sanitizedHeader = headerRow[i]
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      for (final name in possibleNames) {
        final sanitizedName = name.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        if (sanitizedHeader == sanitizedName) return i;
      }
    }
    return -1;
  }

  int _parseGrain(dynamic val) {
    if (val == null) return 0;
    final str = val.toString().toLowerCase().replaceAll('gr', '').trim();
    return int.tryParse(str) ?? 0;
  }

  double? _parseDouble(dynamic val) {
    if (val == null) return null;
    final str = val.toString().trim();
    if (str.isEmpty) return null;
    return double.tryParse(str);
  }

  int _parseWeightGrams(dynamic val) {
    if (val == null) return 0;
    String str = val.toString().toLowerCase();
    str = str.replaceAll('g', '').replaceAll('(1lb)', '').trim();
    if (str.contains('kg')) {
      final kg = double.tryParse(str.replaceAll('kg', '').trim()) ?? 0;
      return (kg * 1000).toInt();
    }
    return int.tryParse(str) ?? 0;
  }

  Future<void> seedAll() async {
    debugPrint("Starting JagSpoor Ballistics seed...");
    await seedAmmunition('assets/data/ammunition_database.csv');
    await seedBullets('assets/data/bullet_database.csv');
    await seedPropellants('assets/data/propellant_database.csv');
    debugPrint("✓ JagSpoor seed complete");
  }

  Future<void> seedAmmunition(String assetPath) async {
    try {
      final csvString = await rootBundle.loadString(assetPath);
      final fields = const CsvToListConverter(eol: '\n').convert(csvString);
      if (fields.isEmpty) return;

      final headers = fields.first;
      final brandIdx = _findHeaderIndex(headers, ['brand']);
      final caliberIdx = _findHeaderIndex(headers, ['caliber', 'calibergauge']);
      final grainIdx = _findHeaderIndex(headers, [
        'grain',
        'bulletgrain',
        'weight',
      ]);
      final descIdx = _findHeaderIndex(headers, ['description', 'desc']);
      final bcIdx = _findHeaderIndex(headers, ['bc']);

      final batch = _firestore.batch();
      int ops = 0;

      for (int i = 1; i < fields.length; i++) {
        final row = fields[i];
        if (row.isEmpty) continue;
        final brand = row[brandIdx].toString().trim();
        final caliber = row[caliberIdx].toString().trim();
        final grain = _parseGrain(row[grainIdx]);
        final desc = row[descIdx].toString().trim();
        final bc = bcIdx != -1 ? _parseDouble(row[bcIdx]) : null;
        if (brand.isEmpty || caliber.isEmpty) continue;

        final docId = '${brand}_${caliber}_$grain'.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        batch.set(
          _firestore.collection('factory_ammunition').doc(docId),
          {
            'brand': brand,
            'caliber': caliber,
            'bulletgrain': grain,
            'description': desc,
            'bc': bc,
            'muzzlevelocityfps': null,
            'type': 'factory',
            'createdat': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (++ops >= 499) {
          await batch.commit();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      debugPrint('✓ factory_ammunition seeded');
    } catch (e) {
      debugPrint('✗ Error: $e');
    }
  }

  Future<void> seedBullets(String assetPath) async {
    try {
      final csvString = await rootBundle.loadString(assetPath);
      final fields = const CsvToListConverter(eol: '\n').convert(csvString);
      if (fields.isEmpty) return;

      final batch = _firestore.batch();
      int ops = 0;

      for (int i = 1; i < fields.length; i++) {
        final row = fields[i];
        if (row.length < 3 || row[0].toString().isEmpty) continue;
        final brand = row[0].toString().trim();
        final caliber = row[1].toString().trim();
        final weight = int.tryParse(row[2].toString().trim()) ?? 0;
        final desc = row.length > 3 ? row[3].toString().trim() : '';
        final bc = row.length > 4 ? _parseDouble(row[4]) : 0.0;
        if (brand.isEmpty || caliber.isEmpty) continue;

        final docId = '${brand}_${caliber}_$weight'.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        batch.set(_firestore.collection('bullets').doc(docId), {
          'brand': brand,
          'caliber': caliber,
          'weightgr': weight,
          'description': desc,
          'bc': bc,
          'createdat': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (++ops >= 499) {
          await batch.commit();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      debugPrint('✓ bullets seeded');
    } catch (e) {
      debugPrint('✗ Error: $e');
    }
  }

  Future<void> seedPropellants(String assetPath) async {
    try {
      final csvString = await rootBundle.loadString(assetPath);
      final fields = const CsvToListConverter(eol: '\n').convert(csvString);
      if (fields.isEmpty) return;

      final headers = fields.first;
      final brandIdx = _findHeaderIndex(headers, ['brand']);
      final typeIdx = _findHeaderIndex(headers, ['typename', 'type', 'name']);
      final weightIdx = _findHeaderIndex(headers, ['weightgrams', 'weight']);
      final notesIdx = _findHeaderIndex(headers, ['notes', 'application']);
      final burnIdx = _findHeaderIndex(headers, ['burnrateindex', 'burnrate']);

      final batch = _firestore.batch();
      int ops = 0;

      for (int i = 1; i < fields.length; i++) {
        final row = fields[i];
        if (row.isEmpty) continue;
        final brand = row[brandIdx].toString().trim();
        final type = row[typeIdx].toString().trim();
        final weight = weightIdx != -1 ? _parseWeightGrams(row[weightIdx]) : 0;
        final notes = notesIdx != -1 ? row[notesIdx].toString().trim() : '';
        final burn = burnIdx != -1 ? _parseDouble(row[burnIdx]) : 0.0;
        if (brand.isEmpty || type.isEmpty) continue;

        final docId = '${brand}_$type'.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        batch.set(_firestore.collection('propellants').doc(docId), {
          'brand': brand,
          'typename': type,
          'weightgrams': weight,
          'notes': notes,
          'burnrateindex': burn,
          'createdat': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (++ops >= 499) {
          await batch.commit();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      debugPrint('✓ propellants seeded');
    } catch (e) {
      debugPrint('✗ Error: $e');
    }
  }
}
