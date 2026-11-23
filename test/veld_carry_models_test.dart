import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/models/planted_area.dart';
import 'package:jagspoor/features/veld_carry/models/predator_entry.dart';
import 'package:jagspoor/features/veld_carry/models/stock_entry.dart';

void main() {
  group('Camp', () {
    test('round-trips through toMap/fromMap', () {
      final created = DateTime(2026, 1, 15, 10, 30);
      final updated = DateTime(2026, 2, 1, 8, 0);
      final camp = Camp(
        id: 'camp-1',
        farmId: 'farm-1',
        name: 'Bosveld Camp',
        totalSizeHa: 1200,
        province: 'Limpopo',
        district: 'Waterberg',
        nearestTown: 'Lephalale',
        lat: -23.6667,
        lng: 27.7,
        locationAccuracyM: 12.5,
        locationSource: Camp.locationSourceGps,
        veldType: 'Sweetveld',
        veldCondition: Camp.veldConditionGood,
        deptNormHaPerLsu: 12,
        rainfallMmPerYear: 480,
        notes: 'North camp',
        createdAt: created,
        updatedAt: updated,
      );

      final map = camp.toMap();
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());

      final parsed = Camp.fromMap(map);
      expect(parsed, equals(camp));
      expect(parsed.effectiveHaPerLsu, camp.deptNormHaPerLsu);
      expect(parsed.lat, -23.6667);
      expect(
        parsed.createdAt.millisecondsSinceEpoch,
        created.millisecondsSinceEpoch,
      );
    });

    test('applies safe defaults and never invents coordinates', () {
      final parsed = Camp.fromMap({
        'id': 'camp-2',
        'farmId': 'farm-1',
        'name': 'South Camp',
        'totalSizeHa': 500,
        'province': 'Free State',
        'district': 'Xhariep',
        'veldType': 'Sourveld',
        'deptNormHaPerLsu': 18,
        'veldCondition': 'excellent',
        'locationSource': 'satellite',
        'createdAt': '2026-03-01T00:00:00.000',
        'updatedAt': '2026-03-01T00:00:00.000',
      });

      expect(parsed.veldCondition, Camp.veldConditionGood);
      expect(parsed.locationSource, Camp.locationSourceManual);
      expect(parsed.effectiveHaPerLsu, 18);
      expect(parsed.nearestTown, isNull);
      expect(parsed.lat, isNull);
      expect(parsed.lng, isNull);
    });

    test('copyWith changes one field and equality is value based', () {
      final base = Camp(
        id: 'camp-3',
        farmId: 'farm-1',
        name: 'Camp',
        totalSizeHa: 100,
        province: 'Limpopo',
        district: 'Waterberg',
        veldType: 'Mixed',
        deptNormHaPerLsu: 10,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

      final renamed = base.copyWith(name: 'Renamed Camp');
      expect(renamed.name, 'Renamed Camp');
      expect(renamed.id, base.id);
      expect(renamed == base, isFalse);
      expect(base.copyWith(), equals(base));
    });
  });

  group('StockEntry', () {
    test('round-trips and derives totals for a counted species', () {
      final entry = StockEntry(
        id: 'impala',
        campId: 'camp-1',
        speciesName: 'Impala',
        scientificName: 'Aepyceros melampus',
        feedingClass: StockEntry.feedingClassMixed,
        count: 20,
        avgWeightKg: 45,
        lsuPerAnimal: 0.15,
        guPerAnimal: 0.12,
        buPerAnimal: 0.9,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

      expect(entry.isCounted, isTrue);
      expect(entry.totalLsu, closeTo(3.0, 1e-9));
      expect(entry.totalWeightKg, closeTo(900.0, 1e-9));
      expect(entry.grazerPct + entry.browserPct, closeTo(1.0, 1e-9));

      final parsed = StockEntry.fromMap(entry.toMap());
      expect(parsed, equals(entry));
    });

    test('Baboon (isCounted=false) contributes zero LSU/GU/BU/weight', () {
      final entry = StockEntry.fromMap({
        'id': 'baboon',
        'campId': 'camp-1',
        'speciesName': 'Chacma Baboon',
        'count': 12,
        'avgWeightKg': 25,
        'lsuPerAnimal': 0.15,
        'guPerAnimal': 0.1,
        'buPerAnimal': 1.0,
        'totalWeightKg': 300.0,
        'totalLsu': 1.8,
        'totalGu': 1.2,
        'totalBu': 12.0,
        'isCounted': false,
      });

      expect(entry.isCounted, isFalse);
      expect(entry.totalWeightKg, 0.0);
      expect(entry.totalLsu, 0.0);
      expect(entry.totalGu, 0.0);
      expect(entry.totalBu, 0.0);
    });

    test('non-counted species are detected by name when isCounted is absent',
        () {
      for (final name in [
        'Chacma Baboon',
        'Vervet Monkey',
        'Cape Porcupine',
        'Aardvark',
      ]) {
        expect(StockEntry.isCountedSpecies(name), isFalse, reason: name);
      }
      expect(StockEntry.isCountedSpecies('Impala'), isTrue);
      expect(StockEntry.isCountedSpecies('Greater Kudu'), isTrue);

      final derived = StockEntry.fromMap({
        'campId': 'c1',
        'speciesName': 'Aardvark',
        'count': 3,
        'lsuPerAnimal': 0.5,
      });
      expect(derived.isCounted, isFalse);
      expect(derived.totalLsu, 0.0);
    });

    test('browser feeding class defaults to a browser-heavy split', () {
      final entry = StockEntry(
        id: 'kudu',
        campId: 'camp-1',
        speciesName: 'Greater Kudu',
        feedingClass: StockEntry.feedingClassBrowser,
        count: 10,
        avgWeightKg: 200,
        lsuPerAnimal: 1.0,
      );

      expect(entry.grazerPct, 0.0);
      expect(entry.browserPct, 1.0);
      expect(entry.totalLsu, closeTo(10.0, 1e-9));
    });
  });

  group('PlantedArea', () {
    test('derives lsuPerHa and capacityLsu from area and haPerLsu', () {
      final area = PlantedArea(
        id: 'p1',
        campId: 'c1',
        feedType: PlantedArea.feedTypeLucerneIrrigated,
        areaHa: 100,
        haPerLsu: 2.5,
      );

      expect(area.lsuPerHa, closeTo(0.4, 1e-9));
      expect(area.capacityLsu, closeTo(40.0, 1e-9));
    });

    test('round-trips and normalises feed type and season', () {
      final area = PlantedArea(
        id: 'p2',
        campId: 'c1',
        feedType: 'teff',
        customName: 'Teff paddock',
        areaHa: 50,
        haPerLsu: 4,
        season: 'winter',
        irrigated: true,
        notes: 'Irrigated pivot',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

      expect(area.feedType, PlantedArea.feedTypeTeff);
      expect(area.season, PlantedArea.seasonWinter);

      final parsed = PlantedArea.fromMap(area.toMap());
      expect(parsed, equals(area));
      expect(parsed.capacityLsu, closeTo(12.5, 1e-9));
    });

    test('guards against a non-positive haPerLsu', () {
      final area = PlantedArea(
        id: 'p3',
        campId: 'c1',
        feedType: 'mystery-crop',
        areaHa: 10,
        haPerLsu: 0,
      );

      expect(area.feedType, PlantedArea.feedTypeOtherCustom);
      expect(area.season, PlantedArea.seasonAllYear);
      expect(area.lsuPerHa, 0.0);
      expect(area.capacityLsu, 0.0);
    });
  });

  group('PredatorEntry', () {
    test('derives prey kg/animals per year and never counts LSU', () {
      final predator = PredatorEntry(
        id: 'pr1',
        campId: 'c1',
        predatorName: 'Black-backed Jackal',
        count: 4,
        dailyIntakeKg: 3.5,
      );

      expect(predator.preyKgPerYear, closeTo(5110.0, 1e-9));
      expect(predator.avgPreyWeightKg, 50.0);
      expect(predator.preyAnimalsPerYear, closeTo(102.2, 1e-9));
      expect(predator.totalLsu, 0.0);
      expect(predator.totalGu, 0.0);
      expect(predator.totalBu, 0.0);
    });

    test('round-trips and keeps LSU/GU/BU at zero', () {
      final predator = PredatorEntry(
        id: 'pr2',
        campId: 'c1',
        predatorName: 'Leopard',
        count: 2,
        dailyIntakeKg: 4,
        avgPreyWeightKg: 40,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

      final map = predator.toMap();
      expect(map['totalLsu'], 0.0);
      expect(map['totalGu'], 0.0);
      expect(map['totalBu'], 0.0);

      final parsed = PredatorEntry.fromMap(map);
      expect(parsed, equals(predator));
      expect(parsed.totalLsu, 0.0);
    });
  });

  group('FarmPermit', () {
    test('round-trips including lists, dates and normalised enums', () {
      final permit = FarmPermit(
        id: 'perm-1',
        farmId: 'farm-1',
        permitType: 'cae',
        permitNumber: 'CAE/2026/001',
        issuingAuthority: 'Limpopo Nature Conservation',
        province: 'Limpopo',
        issueDate: DateTime(2026, 1, 5),
        expiryDate: DateTime(2027, 1, 4),
        speciesCovered: const ['Greater Kudu', 'Impala'],
        campIds: const ['camp-1'],
        fileUrl: 'https://example.com/perm.pdf',
        fileName: 'perm.pdf',
        visibility: 'hunter_visible',
        status: FarmPermit.permitStatusValid,
        notes: 'Renew annually',
        uploadedBy: 'uid-1',
        createdAt: DateTime(2026, 1, 5),
        updatedAt: DateTime(2026, 1, 6),
      );

      expect(permit.permitType, FarmPermit.permitTypeCae);
      expect(permit.visibility, FarmPermit.visibilityHunterVisible);

      final parsed = FarmPermit.fromMap(permit.toMap());
      expect(parsed, equals(permit));
      expect(parsed.speciesCovered, ['Greater Kudu', 'Impala']);
      expect(parsed.campIds, ['camp-1']);
    });

    test('derives status from the expiry date when none is supplied', () {
      final now = DateTime(2026, 6, 1);
      expect(
        FarmPermit.deriveStatus(null, now: now),
        FarmPermit.permitStatusNoExpiry,
      );
      expect(
        FarmPermit.deriveStatus(DateTime(2026, 5, 1), now: now),
        FarmPermit.permitStatusExpired,
      );
      expect(
        FarmPermit.deriveStatus(DateTime(2026, 6, 10), now: now),
        FarmPermit.permitStatusExpiringSoon,
      );
      expect(
        FarmPermit.deriveStatus(DateTime(2026, 9, 1), now: now),
        FarmPermit.permitStatusValid,
      );

      final derived = FarmPermit(
        id: 'perm-2',
        farmId: 'farm-1',
        permitType: 'VET',
        permitNumber: 'VET/1',
        issuingAuthority: 'State Vet',
        province: 'Limpopo',
        expiryDate: DateTime(2000, 1, 1),
      );
      expect(derived.status, FarmPermit.permitStatusExpired);
    });

    test('falls back to safe enum defaults and compares lists by value', () {
      final permit = FarmPermit(
        id: 'perm-3',
        farmId: 'farm-1',
        permitType: 'not-a-type',
        permitNumber: 'n',
        issuingAuthority: 'a',
        province: 'p',
        visibility: 'public',
        speciesCovered: const ['Kudu'],
        campIds: const ['c1'],
      );

      expect(permit.permitType, FarmPermit.permitTypeOther);
      expect(permit.visibility, FarmPermit.visibilityPrivate);
      expect(permit.status, FarmPermit.permitStatusNoExpiry);
      expect(permit.copyWith(), equals(permit));

      final other = permit.copyWith(speciesCovered: const ['Impala']);
      expect(other == permit, isFalse);
      expect(other.speciesCovered, ['Impala']);

      expect(() => permit.speciesCovered.add('x'), throwsUnsupportedError);
    });
  });
}
