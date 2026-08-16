import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/models/farm_service_rate.dart';
import 'package:jagspoor/features/hunter_mode/models/package_pricing.dart';

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
        quantity: 3,
        pricePerUnit: 250.75,
      );
      final restored = FarmServiceRate.fromMap(rate.toMap());
      expect(restored.key, rate.key);
      expect(restored.label, rate.label);
      expect(restored.quantity, rate.quantity);
      expect(restored.pricePerUnit, rate.pricePerUnit);
      expect(restored.total, rate.total);
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
        quantity: 2,
        pricePerUnit: 500,
      );
      final updated = rate.copyWith(quantity: 4);
      expect(updated.quantity, 4);
      expect(updated.pricePerUnit, 500); // unchanged
      expect(updated.key, 'k');
    });
  });

  group('FarmServiceRates', () {
    test('empty() seeds all 7 standard categories at zero', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      expect(rates.rates.length, ItemizedBreakdownCategory.all.length);
      for (final cat in ItemizedBreakdownCategory.all) {
        expect(rates.rates[cat.key], isNotNull);
        expect(rates.rates[cat.key]!.label, cat.label);
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

    test('configuredRates returns only qty>0+price>0, in category order', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      rates.rates['catering'] = const FarmServiceRate(
        key: 'catering',
        label: 'Catering Services',
        quantity: 3,
        pricePerUnit: 250,
      );
      rates.rates['bakkie_vehicle'] = const FarmServiceRate(
        key: 'bakkie_vehicle',
        label: 'Bakkie / Hunting Vehicle Fees',
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
        quantity: 2,
        pricePerUnit: 500,
      ); // 1000
      rates.rates['catering'] = const FarmServiceRate(
        key: 'catering',
        label: 'Catering',
        quantity: 3,
        pricePerUnit: 250,
      ); // 750
      expect(rates.grandTotal, 1750.0);
    });

    test('fromMap seeds the 7 standard categories then overlays stored rates', () {
      final restored = FarmServiceRates.fromMap({
        'outfitterId': outfitterId,
        'rates': {
          'catering': {
            'key': 'catering',
            'label': 'Catering Services',
            'quantity': 4,
            'pricePerUnit': 300,
          },
        },
      }, farmId: farmId);
      // All 7 categories present.
      expect(restored.rates.length, 7);
      // Overlay applied.
      expect(restored.rates['catering']!.quantity, 4);
      expect(restored.rates['catering']!.pricePerUnit, 300);
      // Untouched category retains the standard label + zeros.
      expect(restored.rates['bakkie_vehicle']!.quantity, 0);
      expect(restored.rates['bakkie_vehicle']!.label,
          'Bakkie / Hunting Vehicle Fees');
    });

    test('fromMap tolerates a missing rates map (seeds 7 zeros)', () {
      final restored = FarmServiceRates.fromMap(
        {'outfitterId': outfitterId},
        farmId: farmId,
      );
      expect(restored.rates.length, 7);
      expect(restored.configuredRates, isEmpty);
    });

    test('toMap / fromMap round-trip preserves the configuration', () {
      final rates = FarmServiceRates.empty(farmId, outfitterId);
      rates.rates['coldroom'] = const FarmServiceRate(
        key: 'coldroom',
        label: 'Coldroom / Cold Storage Fees',
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
      // All categories preserved.
      expect(restored.rates.length, 7);
    });

    test('fromFirestore delegates to fromMap with the doc id as farmId', () {
      // fromFirestore just calls fromMap(snap.data(), farmId: snap.id). We
      // can't construct a real DocumentSnapshot (the class is sealed), so we
      // exercise the equivalent fromMap path with the doc id as the farmId --
      // the exact delegation fromFirestore performs. The _FakeDocSnapshot
      // approach is avoided because DocumentSnapshot is sealed.
      final restored = FarmServiceRates.fromMap(
        {
          'outfitterId': outfitterId,
          'rates': {
            'slaughtering': {
              'key': 'slaughtering',
              'label': 'Slaughtering Fees',
              'quantity': 2,
              'pricePerUnit': 600,
            },
          },
        },
        farmId: 'doc-farm-id',
      );
      expect(restored.farmId, 'doc-farm-id');
      expect(restored.rates['slaughtering']!.quantity, 2);
      expect(restored.rates['slaughtering']!.pricePerUnit, 600);
    });
  });
}
