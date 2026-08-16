import 'package:csv/csv.dart';

import '../models/farm_game_price_entry.dart';

/// Result of a CSV price-list import. The parsed [entries] are ready to be
/// persisted via [FarmGamePriceListManager.bulkAddEntries]; [skippedRows]
/// carries the 1-based row numbers (excluding the header) that were rejected
/// so the UI can surface a "rows N, M skipped" warning, and [skipReasons]
/// explains why each was rejected (parallel to [skippedRows]).
class CsvImportResult {
  final List<FarmGamePriceEntry> entries;
  final List<int> skippedRows;
  final List<String> skipReasons;
  final int totalRows;

  const CsvImportResult({
    required this.entries,
    required this.skippedRows,
    required this.skipReasons,
    required this.totalRows,
  });

  int get importedCount => entries.length;
  int get skippedCount => skippedRows.length;
  bool get hasSkips => skippedRows.isNotEmpty;
}

/// Pure, dependency-free CSV parser that maps a price-list spreadsheet to a
/// list of [FarmGamePriceEntry] objects. Firestore is never touched, so the
/// full mapping + validation contract is unit-testable in isolation.
///
/// Column headers are resolved case-insensitively and tolerate common
/// variants (e.g. "Species Name" / "Species" / "Name", "Price (ZAR)" /
/// "Price" / "Price ZAR"). A row is skipped when it is missing a Species
/// Name OR a Price (the two critical fields); Quantity / Gender / Horn-Tusk
/// Length are optional and default sensibly when absent.
class FarmGamePriceCsvImporter {
  FarmGamePriceCsvImporter._();

  /// Header aliases for each field (lowercased, trimmed). The first matching
  /// header in the row wins.
  static const Map<String, List<String>> _speciesAliases = {
    'species': ['species name', 'species', 'name', 'animal', 'animal name'],
  };
  static const Map<String, List<String>> _qtyAliases = {
    'qty': ['quantity', 'qty', 'count', 'amount', 'number'],
  };
  static const Map<String, List<String>> _priceAliases = {
    'price': ['price (zar)', 'price zar', 'price zar', 'pricezar',
      'price', 'price (r)', 'price r', 'price rands', 'rands', 'amount zar'],
  };
  static const Map<String, List<String>> _genderAliases = {
    'gender': ['gender', 'sex'],
  };
  static const Map<String, List<String>> _hornAliases = {
    'horn': ['horn/tusk length', 'horn/tusk', 'horn / tusk length',
      'horn / tusk', 'horn length', 'tusk length', 'horn', 'tusk',
      'trophy length', 'measurement'],
  };
  static const Map<String, List<String>> _unitAliases = {
    'unit': ['horn/tusk unit', 'horn / tusk unit', 'unit', 'measurement unit'],
  };

  /// Parses [csvContent] (a UTF-8 CSV string) into [CsvImportResult] entries
  /// scoped to [farmId] / [outfitterId]. The header row is required; if the
  /// file is empty or unparseable an empty result is returned (no entries,
  /// no skips). [farmId] / [outfitterId] are stamped onto every entry.
  static CsvImportResult parse(String csvContent, {
    required String farmId,
    required String outfitterId,
  }) {
    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(csvContent);
    } catch (_) {
      // Malformed CSV -- treat as empty (no entries, no skips). The caller
      // surfaces a "could not parse" snackbar.
      return const CsvImportResult(
        entries: [],
        skippedRows: [],
        skipReasons: [],
        totalRows: 0,
      );
    }

    if (rows.isEmpty) {
      return const CsvImportResult(
        entries: [],
        skippedRows: [],
        skipReasons: [],
        totalRows: 0,
      );
    }

    // Resolve header indices from the first row. A header is detected when at
    // least one cell matches a known alias; otherwise the first row is treated
    // as data (best-effort positional mapping).
    final header = rows.first
        .map((c) => c.toString().trim().toLowerCase())
        .toList(growable: false);
    final hasHeader = _speciesAliases['species']!.any(header.contains) ||
        _priceAliases['price']!.any(header.contains);

    final Map<String, int> idx = {};
    int dataStart = 0;
    if (hasHeader) {
      idx['species'] = _resolveIndex(header, _speciesAliases['species']!);
      idx['qty'] = _resolveIndex(header, _qtyAliases['qty']!);
      idx['price'] = _resolveIndex(header, _priceAliases['price']!);
      idx['gender'] = _resolveIndex(header, _genderAliases['gender']!);
      idx['horn'] = _resolveIndex(header, _hornAliases['horn']!);
      idx['unit'] = _resolveIndex(header, _unitAliases['unit']!);
      dataStart = 1;
    } else {
      // Positional fallback: species, qty, price, gender, horn, unit.
      idx['species'] = 0;
      idx['qty'] = 1;
      idx['price'] = 2;
      idx['gender'] = 3;
      idx['horn'] = 4;
      idx['unit'] = 5;
      dataStart = 0;
    }

    final entries = <FarmGamePriceEntry>[];
    final skippedRows = <int>[];
    final skipReasons = <String>[];
    int totalDataRows = 0;

    for (var i = dataStart; i < rows.length; i++) {
      final row = rows[i];
      // Skip fully-blank rows (trailing newlines / empty lines).
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) {
        continue;
      }
      totalDataRows++;
      final rowNumber = i + 1; // 1-based, matches spreadsheet intuition.

      final species = _cell(row, idx['species']!);
      final priceRaw = _cell(row, idx['price']!);

      if (species.trim().isEmpty) {
        skippedRows.add(rowNumber);
        skipReasons.add('Missing Species Name');
        continue;
      }
      if (priceRaw.trim().isEmpty) {
        skippedRows.add(rowNumber);
        skipReasons.add('Missing Price');
        continue;
      }
      final price = _parsePrice(priceRaw);
      if (price == null) {
        skippedRows.add(rowNumber);
        skipReasons.add('Invalid Price "$priceRaw"');
        continue;
      }

      final qty = _parseQty(_cell(row, idx['qty']!));
      final gender = _normalizeGenderCsv(_cell(row, idx['gender']!));
      final hornTuskLength = _cell(row, idx['horn']!).trim();
      final hornTuskUnit =
          HornTuskUnit.normalize(_cell(row, idx['unit']!).trim());

      entries.add(FarmGamePriceEntry(
        id: '', // manager assigns the real id on persist.
        farmId: farmId,
        outfitterId: outfitterId,
        speciesName: species.trim(),
        qty: qty,
        priceZAR: price,
        gender: gender,
        hornTuskLength: hornTuskLength,
        hornTuskUnit: hornTuskUnit,
      ));
    }

    return CsvImportResult(
      entries: entries,
      skippedRows: skippedRows,
      skipReasons: skipReasons,
      totalRows: totalDataRows,
    );
  }

  static int _resolveIndex(List<String> header, List<String> aliases) {
    for (final alias in aliases) {
      final i = header.indexOf(alias);
      if (i != -1) return i;
    }
    return -1;
  }

  static String _cell(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].toString();
  }

  /// Parses a ZAR price string, tolerating 'R', 'ZAR', thousands spaces, and
  /// both comma / dot decimal separators. Returns null if unparseable.
  static double? _parsePrice(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Strip currency prefixes / suffixes and whitespace (incl. NBSP).
    s = s.replaceAll(RegExp(r'[RrZAzA\s\u00A0]'), '');
    if (s.isEmpty) return null;
    // South African convention: space thousands, comma OR dot decimal. If both
    // separators present, the rightmost is the decimal.
    if (s.contains(',') && s.contains('.')) {
      final lastComma = s.lastIndexOf(',');
      final lastDot = s.lastIndexOf('.');
      if (lastComma > lastDot) {
        // comma decimal -> drop dots (thousands), replace comma with dot.
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // dot decimal -> drop commas (thousands).
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      // Only commas: if exactly 2 trailing digits -> decimal, else thousands.
      final parts = s.split(',');
      if (parts.length == 2 && parts[1].length == 2) {
        s = s.replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    }
    return double.tryParse(s);
  }

  /// Parses a quantity string to a non-negative int. Empty / unparseable -> 0.
  static int _parseQty(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }

  /// Reuses the model's gender normalization but coerces an empty / unknown
  /// CSV gender to 'Any' (the entry default) rather than titling it.
  static String _normalizeGenderCsv(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return FarmGamePriceValidator.defaultGender;
    switch (s.toLowerCase()) {
      case 'male':
      case 'm':
      case 'bull':
      case 'ram':
        return 'Male';
      case 'female':
      case 'f':
      case 'cow':
      case 'ewe':
      case 'hen':
        return 'Female';
      case 'any':
      case 'both':
      case 'either':
      case 'all':
        return 'Any';
      default:
        return s[0].toUpperCase() + s.substring(1);
    }
  }
}
