import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/services/payfast_checkout.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_config.dart';
import 'package:jagspoor/features/hunter_mode/services/pricelist_text_parser.dart';

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

  group('FarmPayFastProfile', () {
    test('empty profile is not configured', () {
      expect(FarmPayFastProfile.empty.isConfigured, isFalse);
    });

    test('isConfigured requires non-empty merchant id + key', () {
      expect(
          const FarmPayFastProfile(
                  merchantId: '10000100', merchantKey: 'key')
              .isConfigured,
          isTrue);
      expect(
          const FarmPayFastProfile(merchantId: '', merchantKey: 'key')
              .isConfigured,
          isFalse);
      expect(
          const FarmPayFastProfile(merchantId: '10000100', merchantKey: '')
              .isConfigured,
          isFalse);
    });

    test('toMap omits empty passphrase', () {
      final map = const FarmPayFastProfile(
              merchantId: 'id', merchantKey: 'key')
          .toMap();
      expect(map.containsKey('passphrase'), isFalse);
      expect(map['useLive'], isFalse);
    });

    test('toMap includes passphrase when set', () {
      final map = const FarmPayFastProfile(
              merchantId: 'id', merchantKey: 'key', passphrase: 'secret')
          .toMap();
      expect(map['passphrase'], 'secret');
    });

    test('fromMap round-trips all fields', () {
      const original = FarmPayFastProfile(
          merchantId: 'id', merchantKey: 'key', passphrase: 'p', useLive: true);
      final restored = FarmPayFastProfile.fromMap(original.toMap());
      expect(restored.merchantId, 'id');
      expect(restored.merchantKey, 'key');
      expect(restored.passphrase, 'p');
      expect(restored.useLive, isTrue);
    });

    test('fromMap(null) returns empty profile', () {
      expect(FarmPayFastProfile.fromMap(null).isConfigured, isFalse);
    });
  });

  group('PayfastCheckout.resolveEndpoint', () {
    test('uses platform default sandbox when no profile', () {
      final ep = PayfastCheckout.resolveEndpoint(null);
      expect(ep.isLive, isFalse);
      expect(ep.merchantId, '10000100');
    });

    test('uses farm profile when configured (sandbox)', () {
      final ep = PayfastCheckout.resolveEndpoint(const FarmPayFastProfile(
          merchantId: 'FARM_MID', merchantKey: 'FARM_KEY'));
      expect(ep.merchantId, 'FARM_MID');
      expect(ep.merchantKey, 'FARM_KEY');
      expect(ep.isLive, isFalse);
    });

    test('uses live host when farm profile useLive', () {
      final ep = PayfastCheckout.resolveEndpoint(const FarmPayFastProfile(
          merchantId: 'FARM_MID', merchantKey: 'FARM_KEY', useLive: true));
      expect(ep.isLive, isTrue);
    });

    test('falls back to default when farm profile not configured', () {
      final ep = PayfastCheckout.resolveEndpoint(FarmPayFastProfile.empty);
      expect(ep.merchantId, '10000100');
    });
  });

  group('PayfastCheckout.buildReturnUrl', () {
    test('encodes booking id + success flag', () {
      final url = PayfastCheckout.buildReturnUrl('booking-123');
      expect(url, startsWith('jagspoor://payment-return?'));
      expect(url, contains('booking_id=booking-123'));
      expect(url, contains('status=success'));
    });

    test('percent-encodes special characters', () {
      final url = PayfastCheckout.buildReturnUrl('a b/c&d');
      expect(url, contains('a%20b%2Fc%26d'));
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
          'hunterDisplayPriceZAR': 19887.5,
          'quantityLimit': 3,
        },
        {
          'itemType': 'fee',
          'feeType': 'daily',
          'displayLabel': 'Dagfooi',
          'outfitterBasePrice': 1500,
          'hunterDisplayPriceZAR': 1612.5,
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
      expect(kudu.hunterPriceZAR, 19887.5);
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
      expect(catalog.animals.first.hunterPriceZAR, closeTo(2150, 0.01));
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

  group('PricelistTextParser quantityLimit extraction', () {
    final parser = PricelistTextParser();

    test('parses "max N" notation', () {
      final items = parser.parse('Kudu Bul R18500 max 3');
      expect(items, isNotEmpty);
      expect(items.first.speciesName, 'Greater Kudu');
      expect(items.first.quantityLimit, 3);
    });

    test('parses "(N avail)" notation', () {
      final items = parser.parse('Impala Ram R2500 (2 avail)');
      expect(items, isNotEmpty);
      expect(items.first.quantityLimit, 2);
    });

    test('parses "xN" notation', () {
      final items = parser.parse('Springbok R1500 x4');
      expect(items, isNotEmpty);
      expect(items.first.quantityLimit, 4);
    });

    test('parses "N available" notation', () {
      final items = parser.parse('Blesbok R2000 5 available');
      expect(items, isNotEmpty);
      expect(items.first.quantityLimit, 5);
    });

    test('returns null when no limit stated', () {
      final items = parser.parse('Warthog R1200');
      expect(items, isNotEmpty);
      expect(items.first.quantityLimit, isNull);
    });

    test('does not strip the x in 6.5x55 caliber-like tokens', () {
      // No species here -> no item; but the key assertion is that the parser
      // does not crash and produces no spurious quantityLimit.
      final items = parser.parse('6.5x55 R100');
      // No species token -> empty (no false item).
      expect(items, isEmpty);
    });

    test('qty token is removed from the species label', () {
      final items = parser.parse('Koedoe Koei R9000 max 2');
      expect(items, isNotEmpty);
      // The display label preserves the original line, but the species
      // resolution used the qty-stripped remainder.
      expect(items.first.speciesName, 'Greater Kudu');
      expect(items.first.sex, 'Female');
      expect(items.first.quantityLimit, 2);
    });
  });

  group('GeminiResultNormalizer quantityLimit', () {
    test('carries quantityLimit from structured JSON', () {
      final items = GeminiResultNormalizer.normalize([
        {
          'type': 'species',
          'species': 'Kudu',
          'sex': 'Bul',
          'priceZAR': 18500,
          'quantityLimit': 3,
        },
      ]);
      expect(items, hasLength(1));
      expect(items.first.quantityLimit, 3);
    });

    test('accepts quantityAvailable alias', () {
      final items = GeminiResultNormalizer.normalize([
        {
          'type': 'species',
          'species': 'Impala',
          'priceZAR': 2500,
          'quantityAvailable': 5,
        },
      ]);
      expect(items.first.quantityLimit, 5);
    });

    test('null / zero / negative quantityLimit collapses to null', () {
      final items = GeminiResultNormalizer.normalize([
        {'type': 'species', 'species': 'A', 'priceZAR': 100, 'quantityLimit': 0},
        {'type': 'species', 'species': 'B', 'priceZAR': 100, 'quantityLimit': -1},
        {'type': 'species', 'species': 'C', 'priceZAR': 100, 'quantityLimit': null},
      ]);
      expect(items[0].quantityLimit, isNull);
      expect(items[1].quantityLimit, isNull);
      expect(items[2].quantityLimit, isNull);
    });
  });
}
