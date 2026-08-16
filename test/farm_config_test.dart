import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_config.dart';

void main() {
  group('FarmCostConfig', () {
    test('empty config is empty', () {
      expect(FarmCostConfig.empty.isEmpty, isTrue);
    });

    test('toMap omits null fields', () {
      final map = const FarmCostConfig(dailyRateHunter: 1500).toMap();
      expect(map, {'dailyRateHunter': 1500});
    });

    test('toMap includes extraOptions when present', () {
      final map = const FarmCostConfig(extraOptions: [
        FarmExtraOption(name: 'Game drive', priceZAR: 350),
      ]).toMap();
      expect(map['extraOptions'], [
        {'name': 'Game drive', 'priceZAR': 350}
      ]);
    });

    test('fromMap round-trips all fields', () {
      const original = FarmCostConfig(
        dailyRateHunter: 1500,
        dailyRateObserver: 750,
        accommodationPerNight: 600,
        cateringPerDay: 400,
        vehicleFee: 500,
        guideFee: 1000,
        extraOptions: [FarmExtraOption(name: 'Transfer', priceZAR: 600)],
      );
      final restored = FarmCostConfig.fromMap(original.toMap());
      expect(restored.dailyRateHunter, 1500);
      expect(restored.dailyRateObserver, 750);
      expect(restored.accommodationPerNight, 600);
      expect(restored.cateringPerDay, 400);
      expect(restored.vehicleFee, 500);
      expect(restored.guideFee, 1000);
      expect(restored.extraOptions.length, 1);
      expect(restored.extraOptions.first.name, 'Transfer');
      expect(restored.extraOptions.first.priceZAR, 600);
    });

    test('fromMap(null) returns empty config', () {
      expect(FarmCostConfig.fromMap(null).isEmpty, isTrue);
    });

    test('copyWith updates only the specified field', () {
      const base = FarmCostConfig(dailyRateHunter: 1500, guideFee: 1000);
      final updated = base.copyWith(guideFee: 1200);
      expect(updated.dailyRateHunter, 1500);
      expect(updated.guideFee, 1200);
    });
  });

  group('FarmHuntingCatalog.fromPricelist', () {
    Map<String, dynamic> pricelist(List<Map<String, dynamic>> items) => {
          'id': 'pl1',
          'farmId': 'farm1',
          'farmName': 'Test Farm',
          'outfitterId': 'out1',
          'items': items,
        };

    test('splits items into animals and fees', () {
      final catalog = FarmHuntingCatalog.fromPricelist(pricelist([
        {
          'itemType': 'species',
          'speciesId': 'Greater Kudu',
          'displayLabel': 'Koedoe Bul >50"',
          'sex': 'Male',
          'sexLabel': 'Bul',
          'trophySizeRange': '>50"',
          'outfitterBasePrice': 18500,
          'hunterDisplayPriceZAR': 18500,
          'quantityLimit': 3,
        },
        {
          'itemType': 'fee',
          'feeType': 'daily',
          'displayLabel': 'Dagfooi',
          'outfitterBasePrice': 1500,
          'hunterDisplayPriceZAR': 1500,
        },
      ]));
      expect(catalog.farmId, 'farm1');
      expect(catalog.farmName, 'Test Farm');
      expect(catalog.outfitterId, 'out1');
      expect(catalog.pricelistId, 'pl1');
      expect(catalog.animals.length, 1);
      expect(catalog.fees.length, 1);
      final kudu = catalog.animals.first;
      expect(kudu.speciesId, 'Greater Kudu');
      expect(kudu.displayLabel, 'Koedoe Bul >50"');
      expect(kudu.sex, 'Male');
      expect(kudu.basePriceZAR, 18500);
      expect(kudu.hunterPriceZAR, 18500);
      expect(kudu.quantityLimit, 3);
      final daily = catalog.fees.first;
      expect(daily.feeType, 'daily');
      expect(daily.basePriceZAR, 1500);
      expect(daily.quantityLimit, isNull);
    });

    test('derives hunterPriceZAR from base when missing', () {
      final catalog = FarmHuntingCatalog.fromPricelist(pricelist([
        {
          'itemType': 'species',
          'speciesId': 'Impala',
          'displayLabel': 'Rooibok',
          'outfitterBasePrice': 2000,
        },
      ]));
      // hunterPriceZAR equals the base price (no platform commission).
      expect(catalog.animals.first.hunterPriceZAR, closeTo(2000, 0.01));
    });

    test('null / non-positive quantityLimit collapses to null', () {
      final catalog = FarmHuntingCatalog.fromPricelist(pricelist([
        {
          'itemType': 'species',
          'speciesId': 'A',
          'displayLabel': 'A',
          'outfitterBasePrice': 100,
          'quantityLimit': 0,
        },
        {
          'itemType': 'species',
          'speciesId': 'B',
          'displayLabel': 'B',
          'outfitterBasePrice': 100,
          'quantityLimit': -2,
        },
        {
          'itemType': 'species',
          'speciesId': 'C',
          'displayLabel': 'C',
          'outfitterBasePrice': 100,
        },
      ]));
      expect(catalog.animals[0].quantityLimit, isNull);
      expect(catalog.animals[1].quantityLimit, isNull);
      expect(catalog.animals[2].quantityLimit, isNull);
    });

    test('accepts quantityLimit as numeric string', () {
      final catalog = FarmHuntingCatalog.fromPricelist(pricelist([
        {
          'itemType': 'species',
          'speciesId': 'A',
          'displayLabel': 'A',
          'outfitterBasePrice': 100,
          'quantityLimit': '5',
        },
      ]));
      expect(catalog.animals.first.quantityLimit, 5);
    });

    test('empty items -> empty catalog', () {
      final catalog = FarmHuntingCatalog.fromPricelist(pricelist([]));
      expect(catalog.animals, isEmpty);
      expect(catalog.fees, isEmpty);
    });
  });
}
