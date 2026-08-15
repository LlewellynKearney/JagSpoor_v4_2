import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'caliber_normalizer.dart';

/// A single factory ammunition profile parsed from the bundled
/// `assets/data/ammunition_database.csv` asset catalog.
class FactoryAmmoProfile {
  final String brand;
  final String caliber;
  final int grain;
  final String description;
  final double? bc;
  final double? muzzleVelocityFps;

  const FactoryAmmoProfile({
    required this.brand,
    required this.caliber,
    required this.grain,
    required this.description,
    this.bc,
    this.muzzleVelocityFps,
  });

  /// Composite display label used by the cascading-ammunition form
  /// (brand / grain / description selectors).
  String get displayLabel {
    final parts = <String>[brand];
    if (grain > 0) parts.add('$grain gr');
    if (description.isNotEmpty) parts.add(description);
    return parts.join(' · ');
  }

  @override
  String toString() => displayLabel;
}

/// Offline-first repository for factory ammunition profiles.
///
/// Reads the bundled CSV asset catalog (`assets/data/ammunition_database.csv`)
/// directly via `rootBundle` so the ammunition selector is populated the moment
/// a caliber is selected — independent of the Firestore `factory_ammunition`
/// seed (which requires a network round-trip + a successful one-time seed +
/// the deployed Firestore rules). This resolves the "No factory ammunition
/// profiles found" empty state for every caliber present in the asset
/// database, even on a fresh install with no network.
///
/// The CSV is parsed once and cached for the process lifetime; subsequent
/// lookups are synchronous + O(n) over the ~300-row catalog.
class FactoryAmmunitionRepository {
  FactoryAmmunitionRepository._();
  static final FactoryAmmunitionRepository instance =
      FactoryAmmunitionRepository._();

  static const String assetPath = 'assets/data/ammunition_database.csv';

  List<FactoryAmmoProfile>? _cache;

  /// Loads (and caches) the full catalog from the bundled asset. Safe to call
  /// repeatedly — only the first call reads + parses the asset.
  Future<List<FactoryAmmoProfile>> loadAll() async {
    if (_cache != null) return _cache!;
    final csvString = await rootBundle.loadString(assetPath);
    _cache = parseCsv(csvString);
    return _cache!;
  }

  /// Returns the cached catalog if already loaded, otherwise `null`. Useful
  /// for synchronous UI paths that have previously awaited [loadAll].
  List<FactoryAmmoProfile>? get cached => _cache;

  /// Returns all factory profiles matching [caliber]. Matching uses
  /// [CaliberNormalizer.getVariants] (so "9mm Par"/"9mm"/"9mm Luger" all map
  /// to the same rows) plus a tolerant contains-check that catches variants
  /// the curated normalizer does not enumerate. Empty/blank caliber -> `[]`.
  Future<List<FactoryAmmoProfile>> getProfilesForCaliber(
    String? caliber,
  ) async {
    if (caliber == null || caliber.trim().isEmpty) return const [];
    final all = await loadAll();
    return _filterByCaliber(all, caliber);
  }

  /// Synchronous caliber filter over an already-loaded catalog. Exposed for
  /// unit testing the matching logic without going through `rootBundle`.
  List<FactoryAmmoProfile> _filterByCaliber(
    List<FactoryAmmoProfile> profiles,
    String caliber,
  ) {
    if (caliber.trim().isEmpty) return const [];
    final canon = _canonicalize(caliber);
    final variants = <String>{};
    for (final v in CaliberNormalizer.getVariants(canon)) {
      variants.add(v);
      variants.add(_normalize(v));
    }
    variants.add(_normalize(canon));

    final matches = <FactoryAmmoProfile>[];
    for (final p in profiles) {
      if (matchesCaliber(caliber, p.caliber, variants)) {
        matches.add(p);
      }
    }
    // De-duplicate by (brand, caliber, grain, description) — the catalog
    // occasionally carries duplicate rows under variant caliber spellings.
    final seen = <String>{};
    return matches.where((p) {
      final key =
          '${p.brand}|${p.caliber}|${p.grain}|${p.description}'.toLowerCase();
      return seen.add(key);
    }).toList();
  }

  /// Caliber match predicate shared with the ammunition selector UI. Returns
  /// true when [weaponCaliber] and [dbCaliber] refer to the same cartridge.
  /// [variants] is an optional pre-computed normalized-variant set (from
  /// [CaliberNormalizer]); when omitted it is derived from [weaponCaliber].
  ///
  /// Matching priority:
  /// 1. Exact normalized equality.
  /// 2. Curated-variant set membership (handles .308 Win ↔ 308 Cal / 7.62 NATO,
  ///    9mm ↔ 9mm Luger, .30-06 Sprg ↔ 30-06 Springfield, etc.).
  /// 3. Boundary-aware contains — the needle must appear in the haystack at a
  ///    digit boundary so `9mm` matches `9mm Luger` but NOT `7.62x39mm` (the
  ///    `9mm` in `39mm` is preceded by a digit and is rejected).
  static bool matchesCaliber(
    String? weaponCaliber,
    String? dbCaliber, [
    Set<String>? variants,
  ]) {
    if (weaponCaliber == null || dbCaliber == null) return false;
    if (weaponCaliber.trim().isEmpty || dbCaliber.trim().isEmpty) return false;

    // Canonicalize synonyms (9mm Par -> 9mm Luger, 7.62 Soviet -> 7.62x39mm)
    // before normalizing so the curated-variant branches resolve.
    final canonWeapon = _canonicalize(weaponCaliber);
    final wClean = _normalize(canonWeapon);
    final dClean = _normalize(dbCaliber);
    if (wClean.isEmpty || dClean.isEmpty) return false;

    // 243 / 6mm cross-mapping (mirrors the UI's historical special case).
    if ((wClean == '243' || wClean == '6mm') &&
        (dClean.contains('243') || dClean.contains('6mm'))) {
      // Guard against `6mm` matching `762x39mm`-style substrings: only accept
      // when the match sits at a digit boundary.
      if (_boundaryContains(dClean, '243') ||
          _boundaryContains(dClean, '6mm') ||
          _boundaryContains('243', dClean) ||
          _boundaryContains('6mm', dClean)) {
        return true;
      }
    }

    // Exact normalized equality.
    if (wClean == dClean) return true;

    // Curated-variant set membership. When the caller did not pre-compute a
    // variant set, derive one from the (canonicalized) weapon caliber so the
    // matcher is self-contained (handles .308 Win ↔ 308 Cal / 7.62 NATO, 9mm ↔
    // 9mm Luger, .30-06 Sprg ↔ 30-06 Springfield, etc.).
    final vset = variants ?? _variantSet(canonWeapon);
    if (vset.isNotEmpty) {
      if (vset.contains(dbCaliber) || vset.contains(dClean)) return true;
    }

    // Boundary-aware bidirectional contains (strict — rejects digit-adjacent
    // substrings like `9mm` inside `39mm`).
    return _boundaryContains(wClean, dClean) ||
        _boundaryContains(dClean, wClean);
  }

  /// Returns true if [needle] appears in [haystack] at a digit boundary: the
  /// character immediately before [needle] (if any) is NOT a digit, and the
  /// character immediately after [needle] (if any) is NOT a digit. This lets
  /// `9mm` match `9mmluger` (boundary after = `l`) but reject `39mm` (boundary
  /// before = `3`). Both arguments are assumed pre-normalized (lower-cased,
  /// no spaces/dots/hyphens).
  static bool _boundaryContains(String haystack, String needle) {
    if (needle.isEmpty) return false;
    if (haystack == needle) return true;
    if (haystack.length < needle.length) return false;
    int start = 0;
    while (true) {
      final idx = haystack.indexOf(needle, start);
      if (idx == -1) return false;
      final beforeOk = idx == 0 || !_isDigit(haystack.codeUnitAt(idx - 1));
      final afterIdx = idx + needle.length;
      final afterOk = afterIdx >= haystack.length ||
          !_isDigit(haystack.codeUnitAt(afterIdx));
      if (beforeOk && afterOk) return true;
      start = idx + 1;
    }
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  /// Strips spaces, hyphens, dots, and lower-cases — the canonical form used
  /// for matching. Pure / unit-testable.
  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'[\s\-\.]'), '').toLowerCase();

  /// Canonicalizes common cartridge synonyms so variant lookups resolve
  /// regional/commercial spellings the curated [CaliberNormalizer] does not
  /// enumerate. Applied to the weapon caliber before variant generation so
  /// "9mm Par" / "9mm Parabellum" route through the 9mm branch, and "7.62
  /// Soviet" routes through the 7.62x39 branch.
  static String _canonicalize(String caliber) {
    final lower = caliber.trim().toLowerCase();
    // 9mm Parabellum synonyms -> 9mm Luger (the CSV's canonical 9mm spelling).
    if (RegExp(r'^9\s*mm\s*par(abellum)?\b').hasMatch(lower) ||
        lower == '9x19mm parabellum' ||
        lower == '9x19 parabellum') {
      return '9mm Luger';
    }
    // 7.62 Soviet -> 7.62x39mm.
    if (lower.contains('7.62 soviet') || lower.contains('762 soviet')) {
      return '7.62x39mm';
    }
    return caliber;
  }

  /// Builds the curated + normalized variant set for [caliber] (raw + cleaned
  /// forms of each [CaliberNormalizer] variant). Used by [matchesCaliber] when
  /// the caller does not supply a pre-computed set.
  static Set<String> _variantSet(String caliber) {
    final set = <String>{};
    for (final v in CaliberNormalizer.getVariants(caliber)) {
      set.add(v);
      set.add(_normalize(v));
    }
    set.add(_normalize(caliber));
    return set;
  }

  /// Parses a raw CSV string (with a `Brand,Caliber,Grain,Description,BC`
  /// header) into [FactoryAmmoProfile]s. Pure / unit-testable — exposed for
  /// tests so the parsing contract can be verified without `rootBundle`.
  @visibleForTesting
  static List<FactoryAmmoProfile> parseCsv(String csvContent) {
    if (csvContent.trim().isEmpty) return const [];
    final rows = const CsvToListConverter(eol: '\n').convert(csvContent);
    if (rows.isEmpty) return const [];

    final header = rows.first;
    int brandIdx = _headerIndex(header, ['brand']);
    int caliberIdx = _headerIndex(header, ['caliber', 'calibergauge']);
    int grainIdx = _headerIndex(header, ['grain', 'bulletgrain', 'weight']);
    int descIdx = _headerIndex(header, ['description', 'desc']);
    int bcIdx = _headerIndex(header, ['bc']);

    if (brandIdx == -1) brandIdx = 0;
    if (caliberIdx == -1) caliberIdx = 1;
    if (grainIdx == -1) grainIdx = 2;
    if (descIdx == -1) descIdx = 3;

    final profiles = <FactoryAmmoProfile>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final brand = _cell(row, brandIdx).trim();
      final caliber = _cell(row, caliberIdx).trim();
      if (brand.isEmpty || caliber.isEmpty) continue;
      final grainStr = _cell(row, grainIdx)
          .toLowerCase()
          .replaceAll('gr', '')
          .trim();
      final grain = int.tryParse(grainStr) ?? 0;
      final desc = _cell(row, descIdx).trim();
      final bcStr = bcIdx != -1 ? _cell(row, bcIdx).trim() : '';
      final bc = double.tryParse(bcStr);
      profiles.add(FactoryAmmoProfile(
        brand: brand,
        caliber: caliber,
        grain: grain,
        description: desc,
        bc: bc,
      ));
    }
    return profiles;
  }

  static int _headerIndex(List<dynamic> header, List<String> names) {
    for (var i = 0; i < header.length; i++) {
      final h = header[i]
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      for (final n in names) {
        if (h == n.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')) {
          return i;
        }
      }
    }
    return -1;
  }

  static String _cell(List<dynamic> row, int idx) {
    if (idx < 0 || idx >= row.length) return '';
    final v = row[idx];
    return v == null ? '' : v.toString();
  }

  /// Resets the in-memory cache. Test-only — the catalog is static so there
  /// is no production reason to invalidate it.
  @visibleForTesting
  void resetCache() => _cache = null;
}
