import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/ballistics/data/factory_ammunition_repository.dart';

/// A representative slice of the bundled `ammunition_database.csv` shape used
/// to exercise the pure parser + matcher without going through `rootBundle`.
const _sampleCsv = '''Brand,Caliber,Grain,Description,BC
Barnes,.308 Win,168,TSX BT,
Federal,.308 Win,168,Premium Gold Medal Sierra MatchKing,
Frontier,9mm,124,RN CMJ,0.140
Frontier,9mm,147,RN CMJ,0.210
Frontier,9mm Luger,124,RN CMJ,0.140
Barnes,.30-06 Sprg,180,Harvest,
Federal,7.62x39mm,123,Power Shok,
Barnes,.223 Rem,55,TSX BT,
''';

void main() {
  group('FactoryAmmunitionRepository.parseCsv', () {
    test('parses header + data rows into profiles', () {
      final profiles = FactoryAmmunitionRepository.parseCsv(_sampleCsv);
      expect(profiles.length, 8);
      expect(profiles.first.brand, 'Barnes');
      expect(profiles.first.caliber, '.308 Win');
      expect(profiles.first.grain, 168);
      expect(profiles.first.description, 'TSX BT');
      expect(profiles.first.bc, isNull);
    });

    test('parses BC when present', () {
      final profiles = FactoryAmmunitionRepository.parseCsv(_sampleCsv);
      final frontier9 = profiles.firstWhere(
        (p) => p.brand == 'Frontier' && p.caliber == '9mm' && p.grain == 147,
      );
      expect(frontier9.bc, 0.210);
    });

    test('strips "gr" suffix from grain values', () {
      const csv = 'Brand,Caliber,Grain,Description,BC\n'
          'Acme,9mm,124gr,CMJ,';
      final profiles = FactoryAmmunitionRepository.parseCsv(csv);
      expect(profiles.single.grain, 124);
    });

    test('empty/blank content returns an empty list', () {
      expect(FactoryAmmunitionRepository.parseCsv(''), isEmpty);
      expect(FactoryAmmunitionRepository.parseCsv('   '), isEmpty);
    });

    test('skips rows with an empty brand or caliber', () {
      const csv = 'Brand,Caliber,Grain,Description,BC\n'
          ',9mm,124,CMJ,\n'
          'Acme,,124,CMJ,\n'
          'Acme,9mm,124,CMJ,';
      final profiles = FactoryAmmunitionRepository.parseCsv(csv);
      expect(profiles.length, 1);
      expect(profiles.single.brand, 'Acme');
    });

    test('grain falls back to 0 for non-numeric values', () {
      const csv = 'Brand,Caliber,Grain,Description,BC\n'
          'Acme,9mm,N/A,CMJ,';
      final profiles = FactoryAmmunitionRepository.parseCsv(csv);
      expect(profiles.single.grain, 0);
    });

    test('displayLabel joins brand / grain / description', () {
      final profiles = FactoryAmmunitionRepository.parseCsv(_sampleCsv);
      final p = profiles.firstWhere(
        (p) => p.brand == 'Federal' && p.caliber == '.308 Win',
      );
      expect(p.displayLabel, 'Federal · 168 gr · Premium Gold Medal Sierra MatchKing');
    });
  });

  group('FactoryAmmunitionRepository.matchesCaliber', () {
    test('exact match', () {
      expect(FactoryAmmunitionRepository.matchesCaliber('.308 Win', '.308 Win'),
          isTrue);
    });

    test('9mm matches 9mm Luger (bidirectional contains)', () {
      expect(FactoryAmmunitionRepository.matchesCaliber('9mm', '9mm Luger'),
          isTrue);
      expect(FactoryAmmunitionRepository.matchesCaliber('9mm Luger', '9mm'),
          isTrue);
    });

    test('9mm Parabellum matches 9mm Luger (curated variant)', () {
      // "9mm Par" cleans to "9mmpar" which the CaliberNormalizer maps to the
      // 9mm Luger variant set.
      expect(
          FactoryAmmunitionRepository.matchesCaliber('9mm Par', '9mm Luger'),
          isTrue);
    });

    test('.308 Win matches 308 Cal / 7.62 NATO (curated variants)', () {
      expect(
          FactoryAmmunitionRepository.matchesCaliber('.308 Win', '308 Cal'),
          isTrue);
      expect(
          FactoryAmmunitionRepository.matchesCaliber('.308 Win', '7.62mm NATO'),
          isTrue);
    });

    test('.30-06 Sprg matches 30-06 Springfield', () {
      expect(FactoryAmmunitionRepository.matchesCaliber('.30-06 Sprg',
          '30-06 Springfield'), isTrue);
    });

    test('243 cross-matches 6mm', () {
      expect(FactoryAmmunitionRepository.matchesCaliber('.243 Win', '6mm'),
          isTrue);
    });

    test('unrelated calibers do not match', () {
      expect(FactoryAmmunitionRepository.matchesCaliber('.308 Win', '9mm'),
          isFalse);
      expect(FactoryAmmunitionRepository.matchesCaliber('.223 Rem', '.308 Win'),
          isFalse);
    });

    test('null or blank returns false', () {
      expect(FactoryAmmunitionRepository.matchesCaliber(null, '9mm'), isFalse);
      expect(FactoryAmmunitionRepository.matchesCaliber('9mm', null), isFalse);
      expect(FactoryAmmunitionRepository.matchesCaliber('', '9mm'), isFalse);
      expect(FactoryAmmunitionRepository.matchesCaliber('9mm', '  '), isFalse);
    });
  });

  group('FactoryAmmunitionRepository.getProfilesForCaliber (filtered)', () {
    final profiles = FactoryAmmunitionRepository.parseCsv(_sampleCsv);

    /// Exercises the same filtering path the instance uses, without needing
    /// `rootBundle`. We mirror the private filter via the public matcher so
    /// the de-dup + variant logic is covered.
    List<FactoryAmmoProfile> filterFor(String caliber) {
      if (caliber.trim().isEmpty) return const [];
      final matches = profiles
          .where((p) =>
              FactoryAmmunitionRepository.matchesCaliber(caliber, p.caliber))
          .toList();
      final seen = <String>{};
      return matches.where((p) {
        final key =
            '${p.brand}|${p.caliber}|${p.grain}|${p.description}'.toLowerCase();
        return seen.add(key);
      }).toList();
    }

    test('9mm matches both 9mm and 9mm Luger rows', () {
      final matches = filterFor('9mm');
      // 4 rows in the sample: Frontier 9mm 124, Frontier 9mm 147,
      // Frontier 9mm Luger 124.
      expect(matches.length, 3);
      expect(matches.every((p) =>
          p.caliber == '9mm' || p.caliber == '9mm Luger'), isTrue);
    });

    test('.308 Win matches .308 Win rows', () {
      final matches = filterFor('.308 Win');
      expect(matches.length, 2);
      expect(matches.every((p) => p.caliber == '.308 Win'), isTrue);
    });

    test('blank caliber returns an empty list', () {
      expect(filterFor(''), isEmpty);
    });

    test('unrelated caliber returns an empty list', () {
      expect(filterFor('.470 Nitro Express'), isEmpty);
    });

    test('de-duplicates identical brand/caliber/grain/description rows', () {
      const dup = 'Brand,Caliber,Grain,Description,BC\n'
          'Acme,9mm,124,CMJ,\n'
          'Acme,9mm,124,CMJ,\n';
      final dupProfiles = FactoryAmmunitionRepository.parseCsv(dup);
      final matches = dupProfiles
          .where((p) =>
              FactoryAmmunitionRepository.matchesCaliber('9mm', p.caliber))
          .toList();
      final seen = <String>{};
      final deduped = matches.where((p) {
        final key =
            '${p.brand}|${p.caliber}|${p.grain}|${p.description}'.toLowerCase();
        return seen.add(key);
      }).toList();
      expect(deduped.length, 1);
    });
  });

  group('FactoryAmmunitionRepository live asset integration', () {
    // Tests that load the real bundled asset require a TestWidgetsFlutterBinding
    // so `rootBundle` can resolve asset bindings declared in pubspec.
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('loads the bundled catalog and finds 9mm profiles', () async {
      final repo = FactoryAmmunitionRepository.instance..resetCache();
      final profiles = await repo.getProfilesForCaliber('9mm');
      expect(profiles, isNotEmpty,
          reason: '9mm must resolve profiles from the bundled asset catalog');
      expect(profiles.every((p) =>
          p.caliber.toLowerCase().contains('9mm')), isTrue);
    });

    test('resolves .308 Win profiles (curated-variant caliber)', () async {
      final repo = FactoryAmmunitionRepository.instance..resetCache();
      final profiles = await repo.getProfilesForCaliber('.308 Win');
      expect(profiles, isNotEmpty,
          reason: '.308 Win must resolve profiles from the bundled asset');
      expect(profiles.any((p) => p.brand == 'Barnes'), isTrue);
    });

    test('resolves 9mm Par (Parabellum) to 9mm Luger profiles', () async {
      final repo = FactoryAmmunitionRepository.instance..resetCache();
      final profiles = await repo.getProfilesForCaliber('9mm Par');
      expect(profiles, isNotEmpty,
          reason: '"9mm Par" must resolve to 9mm Luger profiles via the '
              'curated variant set, resolving the empty state');
    });

    test('blank caliber returns an empty list (no empty-state crash)', () async {
      final repo = FactoryAmmunitionRepository.instance..resetCache();
      expect(await repo.getProfilesForCaliber(''), isEmpty);
      expect(await repo.getProfilesForCaliber(null), isEmpty);
    });

    test('a caliber absent from the catalog returns an empty list', () async {
      final repo = FactoryAmmunitionRepository.instance..resetCache();
      expect(await repo.getProfilesForCaliber('.700 Nitro Express'), isEmpty);
    });

    test('catalog cache is reused across lookups', () async {
      final repo = FactoryAmmunitionRepository.instance..resetCache();
      await repo.getProfilesForCaliber('9mm');
      final cached = repo.cached;
      expect(cached, isNotNull);
      expect(cached!.length, greaterThan(100),
          reason: 'bundled catalog should carry 100+ profiles');
      // A second lookup must NOT re-read the asset (same cached instance).
      await repo.getProfilesForCaliber('.308 Win');
      expect(identical(repo.cached, cached), isTrue);
    });
  });
}
