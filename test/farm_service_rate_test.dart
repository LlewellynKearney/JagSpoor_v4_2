import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/farm_service_rate.dart';

void main() {
  const farmId = 'farm-123';
  const outfitterId = 'outfitter-456';

  group('FarmServiceRate', () {
    test('total = quantity × pricePerUnit', () {
      const rate = FarmServiceRate(
        key: 'bakkie_vehicle',
        label: 'Bakkie / Hunting Vehicle Fees',
        quantity: 2,
        pricePerUnit: 500.0,
      );
      expect(rate.total, 1000.0);
    });

    test('isConfigured is true only when qty>0 AND price>0', () {
      expect(
        const FarmServiceRate(
                key: 'k', label: 'l', quantity: 2, pricePerUnit: 500)
            .isConfigured,
        isTrue,
      );
      expect(
        const FarmServiceRate(key: 'k', label: 'l', quantity: 0, pricePerUnit: 500)
            .isConfigured,
        isFalse,
      );
      expect(
        const FarmServiceRate(key: 'k', label: 'l', quantity: 2, pricePerUnit: 0)
            .isConfigured,
        isFalse,
      );
      expect(
        const FarmServiceRate(key: 'k', label: 'l', quantity: 0, pricePerUnit: 0)
            .isConfigured,
        isFalse,
      );
    });

    test('toMap / fromMap round-trip preserves every field', () {
      const rate = FarmServiceRate(
        key: 'catering',
        label: 'Catering Services',
        unitLabel: 'Per day',
        quantityNoun: 'persons',
        quantity: 3,
        pricePerUnit: 250.75,
      );
      final restored = FarmServiceRate.fromMap(rate.toMap());
      expect(restored.key, rate.key);
      expect(restored.label, rate.label);
      expect(restored.unitLabel, rate.unitLabel);
      expect(restored.quantityNoun, rate.quantityNoun);
      expect(restored.quantity, rate.quantity);
      expect(restored.pricePerUnit, rate.pricePerUnit);
      expect(restored.total, rate.total);
    });

    test('fromMap backfills label/unitLabel/quantityNoun from the category '
        'when omitted (legacy doc)', () {
      final rate = FarmServiceRate.fromMap(const {
        'key': 'bakkie_vehicle',
        'quantity': 2,
        'pricePerUnit': 500,
      });
      expect(rate.label, 'Bakkie / Hunting Vehicle Fees');
      expect(rate.unitLabel, 'Per vehicle per day');
      expect(rate.quantityNoun, 'vehicles');
      expect(rate.quantity, 2);
      expect(rate.pricePerUnit, 500.0);
    });

    test('fromMap tolerates missing fields (defaults)', () {
      final rate = FarmServiceRate.fromMap(const {});
      expect(rate.key, '');
      expect(rate.label, '');
      expect(rate.quantity, 0);
      expect(rate.pricePerUnit, 0.0);
    });

    test('fromMap tolerates numeric-as-string storage', () {
      final rate = FarmServiceRate.fromMap(const {
        'key': 'k',
        'label': 'l',
        'quantity': '5',
        'pricePerUnit': '120.50',
      });
      expect(rate.quantity, 5);
      expect(rate.pricePerUnit, 120.50);
    });

    test('copyWith updates only the supplied fields', () {
      const rate = FarmServiceRate(
        key: 'k',
        label: 'l',
        unitLabel: 'Per day',
        quantityNoun: 'persons',
        quantity: 2,
        pricePerUnit: 500,
      );
      final updated = rate.copyWith(quantity: 4, unitLabel: 'Per night');
      expect(updated.quantity, 4);
      expect(updated.unitLabel, 'Per night');
      expect(updated.pricePerUnit, 500); // unchanged
      expect(updated.quantityNoun, 'persons'); // unchanged
      expect(updated.key, 'k');
    });

    test('copyWith can update the key (legacy-key migration support)', () {
      const rate = FarmServiceRate(
        key: 'slaughtering',
        label: 'Slaughtering Fees',
        quantity: 2,
        pricePerUnit: 600,
      );
      final migrated = rate.copyWith(
        key: 'slaughtering_big',
        label: 'Slaughtering Fees (Big Animals)',
      );
      expect(migrated.key, 'slaughtering_big');
      expect(migrated.label, 'Slaughtering Fees (Big Animals)');
      expect(migrated.quantity, 2);
    });
  });

  group('FarmServiceCategory', () {
    test('all returns the 9 standard categories in display order', () {
      expect(FarmServiceCategory.all.length, 9);
      expect(FarmServiceCategory.all.map((c) => c.key).toList(), [
        'bakkie_vehicle',
        'slaughtering_big',
        'slaughtering_small',
        'coldroom',
        'hunter_daily',
        'non_hunter_observer_daily',
        'overnight_accommodation_hunter',
        'overnight_accommodation_non_hunter',
        'catering',
      ]);
    });

    test('each category carries its specified unit semantics', () {
      final byKey = {
        for (final c in FarmServiceCategory.all) c.key: c,
      };
      // Bakkie: qty = vehicles, rate = per vehicle per day.
      expect(byKey['bakkie_vehicle']!.unitLabel, 'Per vehicle per day');
      expect(byKey['bakkie_vehicle']!.quantityNoun, 'vehicles');
      // Slaughtering big/small: qty = animals, rate = per animal.
      expect(byKey['slaughtering_big']!.unitLabel, 'Per animal');
      expect(byKey['slaughtering_big']!.quantityNoun, 'animals');
      expect(byKey['slaughtering_small']!.unitLabel, 'Per animal');
      expect(byKey['slaughtering_small']!.quantityNoun, 'animals');
      expect(byKey['slaughtering_big']!.label, contains('Big Animals'));
      expect(byKey['slaughtering_small']!.label, contains('Small Animals'));
      // Coldroom: qty = animals, rate = per day.
      expect(byKey['coldroom']!.unitLabel, 'Per day');
      expect(byKey['coldroom']!.quantityNoun, 'animals');
      // Hunter daily: qty = hunters, rate = per day.
      expect(byKey['hunter_daily']!.unitLabel, 'Per day');
      expect(byKey['hunter_daily']!.quantityNoun, 'hunters');
      // Non-hunter observer daily: qty = observers, rate = per day.
      expect(byKey['non_hunter_observer_daily']!.unitLabel, 'Per day');
      expect(byKey['non_hunter_observer_daily']!.quantityNoun, 'observers');
      // Overnight accommodation (hunter/non-hunter): qty = nights, per night.
      expect(byKey['overnight_accommodation_hunter']!.unitLabel, 'Per night');
      expect(byKey['overnight_accommodation_hunter']!.quantityNoun, 'nights');
      expect(byKey['overnight_accommodation_hunter']!.label, contains('Hunter'));
      expect(byKey['overnight_accommodation_non_hunter']!.unitLabel, 'Per night');
      expect(
          byKey['overnight_accommodation_non_hunter']!.quantityNoun, 'nights');
      expect(byKey['overnight_accommodation_non_hunter']!.label,
          contains('Non-Hunter'));
      // Catering: qty = persons, rate = per day.
      expect(byKey['catering']!.unitLabel, 'Per day');
      expect(byKey['catering']!.quantityNoun, 'persons');
    });

    test('findByKey resolves a known key', () {
      final cat = FarmServiceCategory.findByKey('catering');
      expect(cat.label, 'Catering Services');
      expect(cat.unitLabel, 'Per day');
    });

    test('findByKey falls back to a synthetic category for an unknown key',
        () {
      final cat = FarmServiceCategory.findByKey('custom_key');
      expect(cat.key, 'custom_key');
      expect(cat.label, 'custom_key');
      expect(cat.unitLabel, '');
    });

    test('migrateLegacyKey maps the legacy slaughtering + accommodation keys',
        () {
      expect(FarmServiceCategory.migrateLegacyKey('slaughtering'),
          'slaughtering_big');
      expect(FarmServiceCategory.migrateLegacyKey('overnight_accommodation'),
          'overnight_accommodation_hunter');
      // New keys pass through unchanged.
      expect(FarmServiceCategory.migrateLegacyKey('catering'), 'catering');
      expect(FarmServiceCategory.migrateLegacyKey('slaughtering_small'),
          'slaughtering_small');
    });
  });

  group('FarmServiceRates', () {
    test('empty() seeds all 9 standard categories at zero', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      expect(rates.rates.length, FarmServiceCategory.all.length);
      for (final cat in FarmServiceCategory.all) {
        expect(rates.rates[cat.key], isNotNull);
        expect(rates.rates[cat.key]!.label, cat.label);
        expect(rates.rates[cat.key]!.unitLabel, cat.unitLabel);
        expect(rates.rates[cat.key]!.quantityNoun, cat.quantityNoun);
        expect(rates.rates[cat.key]!.quantity, 0);
        expect(rates.rates[cat.key]!.pricePerUnit, 0);
      }
      expect(rates.farmId, farmId);
      expect(rates.outfitterId, outfitterId);
    });

    test('rate() falls back to a zeroed rate for an unknown key (no null)', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      final r = rates.rate('nonexistent_key');
      expect(r.key, 'nonexistent_key');
      expect(r.quantity, 0);
      expect(r.pricePerUnit, 0);
    });

    test('rate() resolves a legacy key to its migrated category', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      // Legacy 'slaughtering' should resolve onto the 'slaughtering_big'
      // category (the migrated storage key), returning that category's label +
      // unit semantics.
      final r = rates.rate('slaughtering');
      expect(r.key, 'slaughtering_big');
      expect(r.label, 'Slaughtering Fees (Big Animals)');
      expect(r.unitLabel, 'Per animal');
      expect(r.quantityNoun, 'animals');
    });

    test('configuredRates returns only qty>0+price>0, in category order', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      rates.rates['catering'] = const FarmServiceRate(
        key: 'catering',
        label: 'Catering Services',
        unitLabel: 'Per day',
        quantityNoun: 'persons',
        quantity: 3,
        pricePerUnit: 250,
      );
      rates.rates['bakkie_vehicle'] = const FarmServiceRate(
        key: 'bakkie_vehicle',
        label: 'Bakkie / Hunting Vehicle Fees',
        unitLabel: 'Per vehicle per day',
        quantityNoun: 'vehicles',
        quantity: 1,
        pricePerUnit: 500,
      );
      // coldroom left at zero -> excluded.
      final configured = rates.configuredRates;
      expect(configured.length, 2);
      // Category order: bakkie_vehicle before catering.
      expect(configured[0].key, 'bakkie_vehicle');
      expect(configured[1].key, 'catering');
    });

    test('grandTotal sums all configured rate totals', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      rates.rates['bakkie_vehicle'] = const FarmServiceRate(
        key: 'bakkie_vehicle',
        label: 'Bakkie',
        unitLabel: 'Per vehicle per day',
        quantityNoun: 'vehicles',
        quantity: 2,
        pricePerUnit: 500,
      ); // 1000
      rates.rates['catering'] = const FarmServiceRate(
        key: 'catering',
        label: 'Catering',
        unitLabel: 'Per day',
        quantityNoun: 'persons',
        quantity: 3,
        pricePerUnit: 250,
      ); // 750
      expect(rates.grandTotal, 1750.0);
    });

    test('fromMap seeds the 9 standard categories then overlays stored rates',
        () {
      final restored = FarmServiceRates.fromMap({
        'outfitterId': outfitterId,
        'rates': {
          'catering': {
            'key': 'catering',
            'label': 'Catering Services',
            'unitLabel': 'Per day',
            'quantityNoun': 'persons',
            'quantity': 4,
            'pricePerUnit': 300,
          },
        },
      }, farmId: farmId);
      // All 9 categories present.
      expect(restored.rates.length, 9);
      // Overlay applied.
      expect(restored.rates['catering']!.quantity, 4);
      expect(restored.rates['catering']!.pricePerUnit, 300);
      expect(restored.rates['catering']!.unitLabel, 'Per day');
      // Untouched category retains the standard label + zeros.
      expect(restored.rates['bakkie_vehicle']!.quantity, 0);
      expect(restored.rates['bakkie_vehicle']!.label,
          'Bakkie / Hunting Vehicle Fees');
    });

    test('fromMap migrates a legacy slaughtering key to slaughtering_big', () {
      final restored = FarmServiceRates.fromMap({
        'outfitterId': outfitterId,
        'rates': {
          'slaughtering': {
            'key': 'slaughtering',
            'label': 'Slaughtering Fees',
            'quantity': 2,
            'pricePerUnit': 600,
          },
        },
      }, farmId: farmId);
      // Legacy key migrated onto the new Big Animals category.
      expect(restored.rates['slaughtering_big'], isNotNull);
      expect(restored.rates['slaughtering_big']!.quantity, 2);
      expect(restored.rates['slaughtering_big']!.pricePerUnit, 600);
      expect(restored.rates['slaughtering_big']!.label,
          'Slaughtering Fees (Big Animals)');
      // The old raw key is NOT left dangling.
      expect(restored.rates.containsKey('slaughtering'), isFalse);
    });

    test('fromMap migrates a legacy overnight_accommodation key to _hunter', () {
      final restored = FarmServiceRates.fromMap({
        'outfitterId': outfitterId,
        'rates': {
          'overnight_accommodation': {
            'key': 'overnight_accommodation',
            'quantity': 3,
            'pricePerUnit': 850,
          },
        },
      }, farmId: farmId);
      expect(restored.rates['overnight_accommodation_hunter'], isNotNull);
      expect(restored.rates['overnight_accommodation_hunter']!.quantity, 3);
      expect(restored.rates['overnight_accommodation_hunter']!.pricePerUnit,
          850);
      expect(restored.rates['overnight_accommodation_hunter']!.label,
          contains('Hunter'));
      expect(restored.rates.containsKey('overnight_accommodation'), isFalse);
    });

    test('fromMap tolerates a missing rates map (seeds 9 zeros)', () {
      final restored = FarmServiceRates.fromMap(
        {'outfitterId': outfitterId},
        farmId: farmId,
      );
      expect(restored.rates.length, 9);
      expect(restored.configuredRates, isEmpty);
    });

    test('toMap / fromMap round-trip preserves the configuration', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      rates.rates['coldroom'] = const FarmServiceRate(
        key: 'coldroom',
        label: 'Coldroom / Cold Storage Fees',
        unitLabel: 'Per day',
        quantityNoun: 'animals',
        quantity: 1,
        pricePerUnit: 800,
      );
      final restored = FarmServiceRates.fromMap(
        rates.toMap(),
        farmId: farmId,
      );
      expect(restored.farmId, farmId);
      expect(restored.rates['coldroom']!.quantity, 1);
      expect(restored.rates['coldroom']!.pricePerUnit, 800);
      expect(restored.rates['coldroom']!.unitLabel, 'Per day');
      // All categories preserved.
      expect(restored.rates.length, 9);
    });

    test('fromFirestore delegates to fromMap with the doc id as farmId', () {
      // fromFirestore just calls fromMap(snap.data(), farmId: snap.id). We
      // can't construct a real DocumentSnapshot (the class is sealed), so we
      // exercise the equivalent fromMap path with the doc id as the farmId --
      // the exact delegation fromFirestore performs.
      final restored = FarmServiceRates.fromMap(
        {
          'outfitterId': outfitterId,
          'rates': {
            'slaughtering_small': {
              'key': 'slaughtering_small',
              'label': 'Slaughtering Fees (Small Animals)',
              'unitLabel': 'Per animal',
              'quantityNoun': 'animals',
              'quantity': 2,
              'pricePerUnit': 600,
            },
          },
        },
        farmId: 'doc-farm-id',
      );
      expect(restored.farmId, 'doc-farm-id');
      expect(restored.rates['slaughtering_small']!.quantity, 2);
      expect(restored.rates['slaughtering_small']!.pricePerUnit, 600);
    });
  });
}
