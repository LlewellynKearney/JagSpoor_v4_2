import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/farm_game_price_entry.dart';
import 'package:jagspoor/features/hunter_mode/services/farm_game_price_csv_importer.dart';

void main() {
  const farmId = 'farm-123';
  const outfitterId = 'outfitter-456';

  group('FarmGamePriceCsvImporter.parse — header mapping', () {
    test('maps the canonical column headers', () {
      const csv = 'Species Name,Quantity,Price (ZAR),Gender,Horn/Tusk Length\n'
          'Impala,5,2500,Male,28"+\n'
          'Kudu,2,18500,Female,53"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 2);
      expect(result.skippedCount, 0);
      expect(result.entries[0].speciesName, 'Impala');
      expect(result.entries[0].qty, 5);
      expect(result.entries[0].priceZAR, 2500.0);
      expect(result.entries[0].gender, 'Male');
      expect(result.entries[0].hornTuskLength, '28"+');
      expect(result.entries[1].speciesName, 'Kudu');
      expect(result.entries[1].gender, 'Female');
    });

    test('tolerates header alias variants (Species, Qty, Price, Sex, Horn)', () {
      const csv = 'Species,Qty,Price,Sex,Horn\n'
          'Blesbok,3,1600,Bull,18"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 1);
      expect(result.entries[0].speciesName, 'Blesbok');
      expect(result.entries[0].qty, 3);
      expect(result.entries[0].priceZAR, 1600.0);
      expect(result.entries[0].gender, 'Male');
      expect(result.entries[0].hornTuskLength, '18"');
    });

    test('stamps farmId + outfitterId onto every entry', () {
      const csv = 'Species Name,Quantity,Price (ZAR)\nSpringbok,1,1400\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries.single.farmId, farmId);
      expect(result.entries.single.outfitterId, outfitterId);
    });
  });

  group('FarmGamePriceCsvImporter.parse — gender + horn/tusk unit', () {
    test('normalizes gender aliases (Bull/Ram -> Male, Cow/Ewe -> Female)', () {
      const csv = 'Species Name,Price (ZAR),Gender\n'
          'Impala,2500,Bull\n'
          'Kudu,18500,Cow\n'
          'Springbok,1400,Either\n'
          'Blesbok,1600,\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries[0].gender, 'Male');
      expect(result.entries[1].gender, 'Female');
      expect(result.entries[2].gender, 'Any');
      expect(result.entries[3].gender, 'Any');
    });

    test('reads the Horn/Tusk Unit column and normalizes it', () {
      const csv = 'Species Name,Price (ZAR),Horn/Tusk Length,Horn/Tusk Unit\n'
          'Kudu,18500,53,inches\n'
          'Eland,22000,90,centimeters\n'
          'Impala,2500,28,"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries[0].hornTuskUnit, HornTuskUnit.inches);
      expect(result.entries[1].hornTuskUnit, HornTuskUnit.cm);
      expect(result.entries[2].hornTuskUnit, HornTuskUnit.inches);
    });

    test('defaults hornTuskUnit to inches when the column is absent/blank', () {
      const csv = 'Species Name,Price (ZAR),Horn/Tusk Length\n'
          'Kudu,18500,53\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries.single.hornTuskLength, '53');
      expect(result.entries.single.hornTuskUnit, HornTuskUnit.inches);
    });
  });

  group('FarmGamePriceCsvImporter.parse — price parsing', () {
    test('parses SA-style prices (R prefix, space thousands, comma decimal)', () {
      const csv = 'Species Name,Price (ZAR)\n'
          'Kudu,"R 18 500,00"\n'
          'Impala,R2500.50\n'
          'Springbok,1400\n'
          'Eland,"R 22 000"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries[0].priceZAR, 18500.0);
      expect(result.entries[1].priceZAR, 2500.50);
      expect(result.entries[2].priceZAR, 1400.0);
      expect(result.entries[3].priceZAR, 22000.0);
    });

    test('parses comma-thousands + dot-decimal (quoted: "1,234.56")', () {
      const csv = 'Species Name,Price (ZAR)\nSable,"1,234.56"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries.single.priceZAR, 1234.56);
    });

    test('parses dot-thousands + comma-decimal (quoted: "1.234,56")', () {
      const csv = 'Species Name,Price (ZAR)\nSable,"1.234,56"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries.single.priceZAR, 1234.56);
    });
  });

  group('FarmGamePriceCsvImporter.parse — validation / skips', () {
    test('skips rows missing Species Name and records the row number', () {
      const csv = 'Species Name,Quantity,Price (ZAR)\n'
          'Impala,5,2500\n'
          ',2,1800\n'
          'Kudu,3,18500\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 2);
      expect(result.skippedCount, 1);
      expect(result.skippedRows, [3]); // 1-based, header is row 1
      expect(result.skipReasons, ['Missing Species Name']);
    });

    test('skips rows missing Price and records the row number', () {
      const csv = 'Species Name,Quantity,Price (ZAR)\n'
          'Impala,5,\n'
          'Kudu,3,18500\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 1);
      expect(result.skippedRows, [2]);
      expect(result.skipReasons, ['Missing Price']);
    });

    test('skips rows with an invalid (unparseable) price', () {
      const csv = 'Species Name,Price (ZAR)\n'
          'Impala,abc\n'
          'Kudu,18500\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 1);
      expect(result.skippedRows, [2]);
      expect(result.skipReasons.single, contains('Invalid Price'));
    });

    test('defaults missing Quantity to 0 (does not skip the row)', () {
      const csv = 'Species Name,Quantity,Price (ZAR)\n'
          'Impala,,2500\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 1);
      expect(result.entries.single.qty, 0);
    });

    test('skips fully-blank trailing rows', () {
      const csv = 'Species Name,Price (ZAR)\n'
          'Impala,2500\n'
          ',\n'
          '\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 1);
      expect(result.skippedCount, 0);
      expect(result.totalRows, 1);
    });

    test('reports totalRows as data rows only (excludes header)', () {
      const csv = 'Species Name,Price (ZAR)\n'
          'Impala,2500\n'
          'Kudu,18500\n'
          ',200\n'; // skipped (missing species)
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.totalRows, 3);
      expect(result.importedCount, 2);
      expect(result.skippedCount, 1);
    });
  });

  group('FarmGamePriceCsvImporter.parse — edge cases', () {
    test('returns empty result for an empty file', () {
      final result = FarmGamePriceCsvImporter.parse(
        '',
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries, isEmpty);
      expect(result.skippedRows, isEmpty);
      expect(result.totalRows, 0);
    });

    test('returns empty result for whitespace-only content', () {
      final result = FarmGamePriceCsvImporter.parse(
        '   \n  \n',
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries, isEmpty);
      expect(result.totalRows, 0);
    });

    test('handles quoted fields containing commas', () {
      const csv = 'Species Name,Price (ZAR),Horn/Tusk Length\n'
          '"Greater Kudu",18500,"53 7/8"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 1);
      expect(result.entries.single.speciesName, 'Greater Kudu');
      expect(result.entries.single.priceZAR, 18500.0);
      expect(result.entries.single.hornTuskLength, '53 7/8');
    });

    test('falls back to positional mapping when no header is detected', () {
      // No recognizable header keyword -> treated as data: species, qty, price.
      const csv = 'Impala,5,2500,Male,28"+\n'
          'Kudu,2,18500,Female,53"\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 2);
      expect(result.entries[0].speciesName, 'Impala');
      expect(result.entries[0].qty, 5);
      expect(result.entries[0].priceZAR, 2500.0);
      expect(result.entries[0].gender, 'Male');
      expect(result.entries[1].speciesName, 'Kudu');
    });

    test('does not throw on unterminated-quoted CSV (handles gracefully)', () {
      // An unterminated quoted field is tolerated by the converter (no throw);
      // the importer then validates the resulting row. The species cell is
      // non-empty but the price cell is absent, so the row is skipped -- the
      // contract is "never throw, never crash", which holds.
      const csv = 'Species Name,Price (ZAR)\n"unterminated...\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.entries, isEmpty);
      // The malformed row is skipped (missing price) rather than crashing.
      expect(result.skippedRows, [2]);
    });

    test('handles CRLF line endings', () {
      const csv = 'Species Name,Price (ZAR)\r\nImpala,2500\r\nKudu,18500\r\n';
      final result = FarmGamePriceCsvImporter.parse(
        csv,
        farmId: farmId,
        outfitterId: outfitterId,
      );
      expect(result.importedCount, 2);
      expect(result.entries[0].speciesName, 'Impala');
      expect(result.entries[1].speciesName, 'Kudu');
    });
  });

  group('CsvImportResult', () {
    test('importedCount / skippedCount / hasSkips getters', () {
      const withSkips = CsvImportResult(
        entries: [],
        skippedRows: [2],
        skipReasons: ['Missing Price'],
        totalRows: 1,
      );
      expect(withSkips.importedCount, 0);
      expect(withSkips.skippedCount, 1);
      expect(withSkips.hasSkips, isTrue);

      const noSkips = CsvImportResult(
        entries: [],
        skippedRows: [],
        skipReasons: [],
        totalRows: 0,
      );
      expect(noSkips.hasSkips, isFalse);
    });
  });
}
