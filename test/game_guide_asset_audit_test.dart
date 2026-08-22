import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the SA Game Guide asset audit: every species
/// registered in `assets/data/animals_seed.csv` (the database that the
/// Firestore `animals` collection is seeded from) must have a decodable
/// local photo at `assets/images/<sanitized name>.jpg`, where sanitization
/// matches the in-app resolver (strips apostrophes and parentheses).
void main() {
  group('game guide asset audit', () {
    String sanitize(String name) =>
        name.replaceAll("'", '').replaceAll('(', '').replaceAll(')', '');

    late final List<String> species;
    late final Directory imagesDir;

    setUpAll(() {
      final csvFile = File('assets/data/animals_seed.csv');
      final rows = const CsvToListConverter(eol: '\n')
          .convert(csvFile.readAsStringSync());
      species = rows
          .skip(1)
          .map((r) => r.first?.toString().trim() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      imagesDir = Directory('assets/images');
    });

    test('species database parses with registered names', () {
      expect(species.length, greaterThan(100),
          reason: 'animals_seed.csv should list the full SA game guide');
    });

    test('every registered species has a local photo asset', () {
      final missing = species
          .where(
            (name) =>
                !File('${imagesDir.path}/${sanitize(name)}.jpg').existsSync(),
          )
          .toList();
      expect(
        missing,
        isEmpty,
        reason: 'missing local photo assets: ${missing.join(', ')}',
      );
    });

    test('all local photo assets are decodable JPEG / PNG payloads', () {
      final bad = imagesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .where((f) {
            final head = f.readAsBytesSync().sublist(0, 8);
            final isJpeg = head.length >= 3 &&
                head[0] == 0xFF &&
                head[1] == 0xD8 &&
                head[2] == 0xFF;
            final isPng = head.length >= 8 &&
                head[0] == 0x89 &&
                head[1] == 0x50 &&
                head[2] == 0x4E &&
                head[3] == 0x47;
            return !(isJpeg || isPng);
          })
          .map((f) => f.path)
          .toList();
      expect(bad, isEmpty,
          reason: 'non-decodable photo assets: ${bad.join(', ')}');
    });

    test('animal_images.json manifest is valid', () {
      final manifest = json.decode(
        File('assets/images/animal_images.json').readAsStringSync(),
      );
      expect(manifest, isA<Map<String, dynamic>>());
      final entries = (manifest as Map<String, dynamic>).entries.toList();
      expect(entries, isNotEmpty);
      for (final e in entries) {
        expect(e.key.trim(), isNotEmpty);
        expect(e.value.toString().startsWith('http'), isTrue,
            reason: 'manifest entries must resolve to a fallback URL');
      }
    });
  });
}
