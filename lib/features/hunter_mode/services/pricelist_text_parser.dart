import 'dart:convert';

/// A single line item dynamically extracted from a scanned South African
/// hunting price list (image OCR / PDF text / Gemini Vision output).
class PricelistItem {
  /// Original scanned display label, preserved verbatim
  /// (e.g. "Koedoe Bul >50\"", "Dagfooi", "Blesbok Ooi <16\"").
  final String displayLabel;

  /// Canonical English species name (system-standard). Empty for fee items.
  final String speciesName;

  /// System species identifier — the canonical name used by the `animals`
  /// collection / image catalog. Afrikaans names map to this so downstream
  /// package booking + analytics join cleanly. Empty for fee items.
  final String speciesId;

  /// Normalized sex / class bucket: 'Male', 'Female', 'Young Male', or ''.
  final String sex;

  /// Original sex / class token as scanned (e.g. 'Bul', 'Koei', 'Penkop').
  final String sexLabel;

  /// Trophy size range token as scanned (e.g. '>50"', '<20"', '40"–50"').
  /// Empty when the price list does not size-tier the animal.
  final String trophySizeRange;

  /// Base outfitter price in ZAR (before the 7.5% platform commission).
  final double priceZAR;

  /// 'species' for trophy/game line items, 'fee' for daily/slaughter/etc.
  final String itemType;

  /// Fee category for `itemType == 'fee'`: 'daily', 'slaughter', 'guide',
  /// 'gamedrive', 'vehicle', 'accommodation', 'meals', 'transport', or ''.
  final String feeType;

  const PricelistItem({
    required this.displayLabel,
    required this.speciesName,
    required this.speciesId,
    required this.sex,
    required this.sexLabel,
    required this.trophySizeRange,
    required this.priceZAR,
    required this.itemType,
    required this.feeType,
  });

  Map<String, dynamic> toMap() => {
        'displayLabel': displayLabel,
        'name': displayLabel,
        'speciesName': speciesName,
        'speciesId': speciesId,
        'sex': sex,
        'sexLabel': sexLabel,
        'trophySizeRange': trophySizeRange,
        'outfitterBasePrice': priceZAR,
        'itemType': itemType,
        'feeType': feeType,
      };

  @override
  String toString() =>
      'PricelistItem($displayLabel | $speciesName | sex=$sex | '
      'size=$trophySizeRange | R$priceZAR | $itemType/$feeType)';
}

/// Pure-Dart, dependency-free parser that dynamically extracts structured
/// trophy-species + fee line items from the raw text of a South African
/// hunting price list.
///
/// Recognises both English and Afrikaans species names / sex / class / fee
/// terms and maps them to the project's canonical system species IDs while
/// preserving the original scanned display label. Used to normalise both
/// classic OCR output and Gemini Vision JSON output so Afrikaans terms map
/// consistently regardless of the upstream extractor.
class PricelistTextParser {
  PricelistTextParser();

  /// Canonical species mapping. Key = lowercased synonym (English or
  /// Afrikaans, with/without spaces), value = the system-standard species
  /// name (matching the `animals` image catalog keys / doc names).
  static const Map<String, String> speciesAliases = {
    // Afrikaans
    'vlakvark': 'Common Warthog',
    'blesbok': 'Blesbok',
    'springbok': 'Springbok',
    'rooibok': 'Impala',
    'koedoe': 'Greater Kudu',
    'kooedoe': 'Greater Kudu',
    'blouwildebees': 'Blue Wildebeest',
    'swartwildebees': 'Black Wildebeest',
    'gemsbok': 'Gemsbok (Oryx)',
    'eland': 'Eland',
    'bosbok': 'Southern Bushbuck',
    'waterbok': 'Common Waterbuck',
    'rooihartbees': 'Red Hartebeest',
    'rooi hartebees': 'Red Hartebeest',
    'nyala': 'Nyala',
    'sebra': 'Plains Zebra',
    'duiker': 'Common Duiker',
    'steenbok': 'Steenbok',
    'takbok': 'Fallow Deer',
    'wildebees': 'Blue Wildebeest',
    'hartebees': 'Red Hartebeest',
    // English
    'warthog': 'Common Warthog',
    'common warthog': 'Common Warthog',
    'impala': 'Impala',
    'kudu': 'Greater Kudu',
    'greater kudu': 'Greater Kudu',
    'blue wildebeest': 'Blue Wildebeest',
    'black wildebeest': 'Black Wildebeest',
    'gemsbok oryx': 'Gemsbok (Oryx)',
    'oryx': 'Gemsbok (Oryx)',
    'bushbuck': 'Southern Bushbuck',
    'southern bushbuck': 'Southern Bushbuck',
    'waterbuck': 'Common Waterbuck',
    'common waterbuck': 'Common Waterbuck',
    'red hartebeest': 'Red Hartebeest',
    'zebra': 'Plains Zebra',
    'plains zebra': 'Plains Zebra',
    'common duiker': 'Common Duiker',
    'fallow deer': 'Fallow Deer',
    'bushpig': 'Bushpig',
    'giraffe': 'Giraffe',
    'sable': 'Sable Antelope',
    'sable antelope': 'Sable Antelope',
    'roan': 'Roan Antelope',
    'roan antelope': 'Roan Antelope',
    'tsessebe': 'Tsessebe',
    'reedbuck': 'Southern Reedbuck',
    'mountain reedbuck': 'Mountain Reedbuck',
    'klipspringer': 'Klipspringer',
  };

  /// Sex / class token → normalized bucket. The original token is preserved
  /// on the item as `sexLabel`.
  static const Map<String, String> sexAliases = {
    // Afrikaans
    'bul': 'Male',
    'ram': 'Male',
    'ooi': 'Female',
    'koei': 'Female',
    'jongbul': 'Young Male',
    'penkop': 'Young Male',
    'knypkop': 'Young Male',
    // English
    'bull': 'Male',
    'male': 'Male',
    'trophy': 'Male',
    'female': 'Female',
    'ewe': 'Female',
    'cow': 'Female',
    'young male': 'Young Male',
    'young bull': 'Young Male',
    'juvenile': 'Young Male',
    'yearling': 'Young Male',
  };

  /// Fee token → fee category. Keys are lowercased label fragments.
  static const Map<String, String> feeAliases = {
    'dagfooi': 'daily',
    'daily rate': 'daily',
    'daily fee': 'daily',
    'per day': 'daily',
    'dag tarief': 'daily',
    'slagfooi': 'slaughter',
    'slaughter fee': 'slaughter',
    'slaughtering': 'slaughter',
    'slag': 'slaughter',
    'gidskoste': 'guide',
    'guide fee': 'guide',
    'gids': 'guide',
    'ph fee': 'guide',
    'professional hunter': 'guide',
    'wildrit': 'gamedrive',
    'game drive': 'gamedrive',
    'bakkiefooi': 'vehicle',
    'vehicle fee': 'vehicle',
    'bakkie': 'vehicle',
    'transport': 'transport',
    'airport transfer': 'transport',
    'akkommodasie': 'accommodation',
    'accommodation': 'accommodation',
    'per night': 'accommodation',
    'meals': 'meals',
    'kos': 'meals',
    'catering': 'meals',
  };

  /// Parse a block of raw price-list text (one line per entry, or any text
  /// containing price lines) into structured [PricelistItem]s. Lines without
  /// a parseable ZAR price are skipped. Order is preserved; duplicate
  /// (speciesId + sex + sizeRange) entries are de-duplicated (first wins).
  List<PricelistItem> parse(String rawText) {
    final items = <PricelistItem>[];
    final seen = <String>{};
    for (final rawLine in rawText.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final item = _parseLine(line);
      if (item == null) continue;
      final key =
          '${item.itemType}|${item.speciesId}|${item.feeType}|${item.sex}|${item.trophySizeRange}';
      if (!seen.add(key)) continue;
      items.add(item);
    }
    return items;
  }

  /// Parse a single line into a [PricelistItem], or `null` if it has no
  /// price or no recognisable species/fee token.
  PricelistItem? _parseLine(String line) {
    // Extract trophy size range FIRST so size tokens (e.g. the "50" in
    // >50") are not mistaken for a price.
    final sizeResult = _popSizeRange(line);
    final working = sizeResult.remaining.trim();

    final priceResult = _extractPrice(working);
    if (priceResult == null) return null;
    final priceZAR = priceResult.value;
    final remainder = priceResult.strippedLine.trim();

    final species = _resolveSpecies(remainder);
    final sex = species == null ? null : _resolveSex(remainder);

    if (species != null) {
      final label = _cleanLabel(line);
      return PricelistItem(
        displayLabel: label,
        speciesName: species,
        speciesId: species,
        sex: sex?.bucket ?? '',
        sexLabel: sex?.original ?? '',
        trophySizeRange: sizeResult.range,
        priceZAR: priceZAR,
        itemType: 'species',
        feeType: '',
      );
    }

    final fee = _resolveFee(remainder);
    if (fee != null) {
      final label = _cleanLabel(line);
      return PricelistItem(
        displayLabel: label,
        speciesName: '',
        speciesId: '',
        sex: '',
        sexLabel: '',
        trophySizeRange: '',
        priceZAR: priceZAR,
        itemType: 'fee',
        feeType: fee,
      );
    }
    return null;
  }

  /// Longest-match species resolver (case-insensitive). Returns the canonical
  /// system species name, or `null` when no species synonym is present.
  String? _resolveSpecies(String text) {
    final lower = text.toLowerCase();
    String? best;
    int bestLen = 0;
    for (final entry in speciesAliases.entries) {
      final key = entry.key;
      if (_containsWord(lower, key) && key.length > bestLen) {
        best = entry.value;
        bestLen = key.length;
      }
    }
    return best;
  }

  _SexMatch? _resolveSex(String text) {
    final lower = text.toLowerCase();
    String? best;
    int bestLen = 0;
    for (final entry in sexAliases.entries) {
      final key = entry.key;
      if (_containsWord(lower, key) && key.length > bestLen) {
        best = entry.key;
        bestLen = key.length;
      }
    }
    if (best == null) return null;
    return _SexMatch(original: best, bucket: sexAliases[best]!);
  }

  String? _resolveFee(String text) {
    final lower = text.toLowerCase();
    String? best;
    int bestLen = 0;
    for (final entry in feeAliases.entries) {
      final key = entry.key;
      if (lower.contains(key) && key.length > bestLen) {
        best = entry.value;
        bestLen = key.length;
      }
    }
    return best;
  }

  /// Word-boundary contains check so "ram" does not match inside "framing".
  bool _containsWord(String haystack, String needle) {
    if (needle.contains(' ')) return haystack.contains(needle);
    final pattern = RegExp(r'(^|[^a-z])' + RegExp.escape(needle) + r'([^a-z]|$)');
    return pattern.hasMatch(haystack);
  }

  static final RegExp _sizeRangePattern = RegExp(
    r'((?:>|<|≥|≤|over|under|up to)\s?\d{1,3}["”′]' // >50", <20", ≥40"
    r'|\d{1,3}["”′]\s?[-–]\s?\d{1,3}["”′]' // 40"–50"
    r'|\d{1,3}["”′]\+)', // 50"+
    caseSensitive: false,
  );

  /// Pops a trophy size range token out of the line, returning the matched
  /// range and the line with that token removed.
  _SizeResult _popSizeRange(String line) {
    final m = _sizeRangePattern.firstMatch(line);
    if (m == null) return _SizeResult(range: '', remaining: line);
    final range = m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    final remaining = line.replaceRange(m.start, m.end, '');
    return _SizeResult(range: range, remaining: remaining);
  }

  /// Extracts the rightmost ZAR amount from a line. Handles South African
  /// formatting: "R 12 500", "R12,500", "R 12 500,00", "12500", "12 500,00",
  /// "R1.234,56", "ZAR 1,234.50". The matched amount is removed from the
  /// returned [strippedLine] so the remainder carries only the description.
  _PriceResult? _extractPrice(String line) {
    final matches = RegExp(
      r'(?:R|ZAR)\s?(\d[\d\s.,]*\d|\d)|\b(\d[\d\s.,]*\d)\b',
      caseSensitive: false,
    ).allMatches(line);
    String? raw;
    int start = 0, end = 0;
    for (final m in matches) {
      final currencyMatch = m.group(1);
      final bareMatch = m.group(2);
      final candidate = currencyMatch ?? bareMatch;
      if (candidate == null) continue;
      final digits = candidate.replaceAll(RegExp(r'[\s.,]'), '');
      // Bare 1-2 digit runs without a currency prefix are not prices.
      if (currencyMatch == null && digits.length < 3) continue;
      raw = candidate;
      start = m.start;
      end = m.end;
    }
    if (raw == null) return null;
    final value = parsePrice(raw);
    if (value == null || value <= 0) return null;
    final strippedLine = line.replaceRange(start, end, '').trim();
    return _PriceResult(value: value, strippedLine: strippedLine);
  }

  String _cleanLabel(String line) =>
      line.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Parses a raw ZAR price token (handling South African thousand/decimal
/// separators) into a [double]. Returns `null` when the token is not a
/// number. Used by both the text parser and the Gemini JSON normalizer.
double? parsePrice(String raw) {
  // Strip currency markers (R / ZAR) and surrounding whitespace.
  var s = raw.replaceAll(RegExp(r'[\s\u00A0]'), '');
  s = s.replaceAll(RegExp(r'^(?:R|ZAR)', caseSensitive: false), '');
  final hasDot = s.contains('.');
  final hasComma = s.contains(',');
  if (hasDot && hasComma) {
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastDot > lastComma) {
      // dot = decimal, comma = thousands
      s = s.replaceAll(',', '');
    } else {
      // comma = decimal, dot = thousands
      s = s.replaceAll('.', '').replaceAll(',', '.');
    }
  } else if (hasComma) {
    final parts = s.split(',');
    if (parts.length == 2 && parts[1].length == 2) {
      // comma decimal (e.g. 12500,00)
      s = s.replaceAll(',', '.');
    } else {
      // comma thousands (e.g. 12,500)
      s = s.replaceAll(',', '');
    }
  }
  return double.tryParse(s);
}

class _PriceResult {
  final double value;
  final String strippedLine;
  _PriceResult({required this.value, required this.strippedLine});
}

class _SizeResult {
  final String range;
  final String remaining;
  _SizeResult({required this.range, required this.remaining});
}

class _SexMatch {
  final String original;
  final String bucket;
  _SexMatch({required this.original, required this.bucket});
}

/// Normalises a Gemini Vision structured-JSON response (a list of raw
/// entries with species/sex/sizeRange/priceZAR/type fields) into
/// [PricelistItem]s by routing every field through the same Afrikaans-aware
/// resolver used for raw OCR text, so Afrikaans labels map consistently.
class GeminiResultNormalizer {
  static List<PricelistItem> normalize(List<dynamic> entries) {
    final parser = PricelistTextParser();
    final items = <PricelistItem>[];
    for (final raw in entries) {
      if (raw is! Map) continue;
      final type = (raw['type'] ?? raw['itemType'] ?? '').toString().toLowerCase();
      final rawSpecies = (raw['species'] ?? raw['name'] ?? '').toString();
      final rawSex = (raw['sex'] ?? raw['class'] ?? '').toString();
      final sizeRange =
          _normalizeSizeRange((raw['sizeRange'] ?? raw['trophySizeRange'] ?? '').toString());
      final priceZAR = _toPrice(raw['priceZAR'] ?? raw['price'] ?? raw['outfitterBasePrice']);
      if (priceZAR <= 0) continue;
      final displayLabel = (raw['displayLabel'] ?? raw['label'] ?? rawSpecies).toString();

      if (type == 'fee' || rawSpecies.isEmpty) {
        final fee = parser._resolveFee('$rawSpecies $displayLabel') ??
            (type == 'fee' ? (raw['feeType'] ?? '').toString() : '');
        if (fee.isEmpty) continue;
        items.add(PricelistItem(
          displayLabel: displayLabel.isEmpty ? rawSpecies : displayLabel,
          speciesName: '',
          speciesId: '',
          sex: '',
          sexLabel: '',
          trophySizeRange: '',
          priceZAR: priceZAR,
          itemType: 'fee',
          feeType: fee,
        ));
        continue;
      }

      final species = parser._resolveSpecies(rawSpecies) ??
          parser._resolveSpecies(displayLabel) ??
          rawSpecies;
      final sex = parser._resolveSex(rawSex);
      items.add(PricelistItem(
        displayLabel: displayLabel,
        speciesName: species,
        speciesId: species,
        sex: sex?.bucket ?? '',
        sexLabel: sex?.original ?? rawSex,
        trophySizeRange: sizeRange,
        priceZAR: priceZAR,
        itemType: 'species',
        feeType: '',
      ));
    }
    return items;
  }

  static String _normalizeSizeRange(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    if (t.contains('"') || t.contains('”') || t.contains('+') ||
        RegExp(r'^[<>≥≤]').hasMatch(t) || RegExp(r'\d+\s?[-–]\s?\d+').hasMatch(t)) {
      return t;
    }
    return '$t"';
  }

  static double _toPrice(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final m = RegExp(r'[\d\s.,]+').firstMatch(v);
      if (m == null) return 0;
      return parsePrice(m.group(0)!) ?? 0;
    }
    return 0;
  }
}

/// Convenience: parse a raw JSON string (Gemini text output) into normalized
/// [PricelistItem]s. Falls back to plain-text parsing when the response is
/// not a JSON array.
List<PricelistItem> parseGeminiTextResponse(String response) {
  final trimmed = response.trim();
  // Try to locate a JSON array in the response.
  final start = trimmed.indexOf('[');
  final end = trimmed.lastIndexOf(']');
  if (start != -1 && end != -1 && end > start) {
    final slice = trimmed.substring(start, end + 1);
    try {
      final decoded = jsonDecode(slice);
      if (decoded is List) {
        return GeminiResultNormalizer.normalize(decoded);
      }
    } catch (_) {
      // fall through to text parsing
    }
  }
  return PricelistTextParser().parse(response);
}
