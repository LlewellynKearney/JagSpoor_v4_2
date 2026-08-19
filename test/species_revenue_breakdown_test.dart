import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/outfitter_analytics_service.dart';

/// Unit tests for the outfitter Species Revenue Breakdown aggregation.
///
/// `OutfitterAnalyticsService.aggregateSpeciesRevenue` is a pure static
/// function over raw booking + package document maps, so the breakdown
/// contract is fully unit-testable without the Firestore emulator (which
/// cannot run in this sandbox -- see AGENTS.md environment constraints).
///
/// Data sources per booking:
/// - Custom harvested species: the booking's own `selectedItemsList`
///   (`name` + `quantity` + `lineTotal` / `unitPriceHunterZAR`), written by
///   `FarmGamePriceListManager.submitCustomPackageBooking`.
/// - Package animals: the linked `packages/{packageId}` doc's `speciesItems`
///   (`speciesName` + `quantity` + `pricePerAnimal` / `total`).
void main() {
  group('OutfitterAnalyticsService.hasInlineSpeciesItems', () {
    test('true when selectedItemsList is a non-empty list', () {
      expect(
        OutfitterAnalyticsService.hasInlineSpeciesItems({
          'selectedItemsList': [
            {'name': 'Impala'},
          ],
        }),
        isTrue,
      );
    });

    test('false when selectedItemsList is missing / empty / not a list', () {
      expect(OutfitterAnalyticsService.hasInlineSpeciesItems({}), isFalse);
      expect(
        OutfitterAnalyticsService.hasInlineSpeciesItems(
            {'selectedItemsList': const []}),
        isFalse,
      );
      expect(
        OutfitterAnalyticsService.hasInlineSpeciesItems(
            {'selectedItemsList': 'not-a-list'}),
        isFalse,
      );
    });
  });

  group('OutfitterAnalyticsService.aggregateSpeciesRevenue', () {
    test('returns empty when there are no bookings', () {
      expect(
        OutfitterAnalyticsService.aggregateSpeciesRevenue(const [], const {}),
        isEmpty,
      );
    });

    test('aggregates marketplace package animals (speciesItems) by species',
        () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {'packageId': 'pkg-1'},
        ],
        {
          'pkg-1': {
            'speciesItems': [
              {
                'speciesName': 'Greater Kudu',
                'quantity': 1,
                'pricePerAnimal': 18500.0,
                'total': 18500.0,
              },
              {
                'speciesName': 'Impala',
                'quantity': 2,
                'pricePerAnimal': 2500.0,
                'total': 5000.0,
              },
            ],
          },
        },
      );

      expect(rows.length, 2);
      // Sorted by revenue desc.
      expect(rows[0]['species'], 'Greater Kudu');
      expect(rows[0]['revenue'], 18500.0);
      expect(rows[0]['count'], 1);
      expect(rows[1]['species'], 'Impala');
      expect(rows[1]['revenue'], 5000.0);
      expect(rows[1]['count'], 2);
    });

    test('falls back to quantity x pricePerAnimal when total is missing', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {'packageId': 'pkg-1'},
        ],
        {
          'pkg-1': {
            'speciesItems': [
              {
                'speciesName': 'Blesbok',
                'quantity': 3,
                'pricePerAnimal': 2000.0,
              },
            ],
          },
        },
      );

      expect(rows.single['species'], 'Blesbok');
      expect(rows.single['revenue'], 6000.0);
      expect(rows.single['count'], 3);
    });

    test('aggregates custom harvested species (selectedItemsList) using '
        'lineTotal', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {
            'packageId': 'CUSTOM_BUILT',
            'isCustomPackage': true,
            'selectedItemsList': [
              {
                'name': 'Common Warthog',
                'quantity': 2,
                'unitPriceHunterZAR': 1500.0,
                'lineTotal': 3000.0,
              },
            ],
          },
        ],
        const {},
      );

      expect(rows.single['species'], 'Common Warthog');
      expect(rows.single['revenue'], 3000.0);
      expect(rows.single['count'], 2);
    });

    test('falls back to unitPriceHunterZAR / hunterPrice x qty when lineTotal '
        'is missing', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {
            'selectedItemsList': [
              {
                'name': 'Springbok',
                'quantity': 2,
                'unitPriceHunterZAR': 1200.0,
              },
              {
                'name': 'Steenbok',
                'quantity': 1,
                'hunterPrice': 1800.0,
              },
            ],
          },
        ],
        const {},
      );

      final bySpecies = {for (final r in rows) r['species'] as String: r};
      expect(bySpecies['Springbok']!['revenue'], 2400.0);
      expect(bySpecies['Steenbok']!['revenue'], 1800.0);
    });

    test('sums revenue + counts across multiple bookings for the same species',
        () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {
            'selectedItemsList': [
              {'name': 'Impala', 'quantity': 1, 'lineTotal': 2500.0},
            ],
          },
          {'packageId': 'pkg-1'},
        ],
        {
          'pkg-1': {
            'speciesItems': [
              {'speciesName': 'Impala', 'quantity': 2, 'total': 5000.0},
            ],
          },
        },
      );

      expect(rows.single['species'], 'Impala');
      expect(rows.single['revenue'], 7500.0);
      expect(rows.single['count'], 3);
    });

    test('mixes custom + marketplace bookings in one breakdown', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {'packageId': 'pkg-1'},
          {
            'packageId': 'CUSTOM_BUILT',
            'selectedItemsList': [
              {'name': 'Nyala', 'quantity': 1, 'lineTotal': 9500.0},
            ],
          },
        ],
        {
          'pkg-1': {
            'speciesItems': [
              {'speciesName': 'Greater Kudu', 'quantity': 1, 'total': 18500.0},
            ],
          },
        },
      );

      expect(rows.length, 2);
      expect(rows[0]['species'], 'Greater Kudu');
      expect(rows[1]['species'], 'Nyala');
    });

    test('skips bookings whose package is missing / deleted', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {'packageId': 'pkg-deleted'},
        ],
        const {},
      );
      expect(rows, isEmpty);
    });

    test('skips a CUSTOM_BUILT booking with no selectedItemsList', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {'packageId': 'CUSTOM_BUILT'},
        ],
        const {},
      );
      expect(rows, isEmpty);
    });

    test('skips line items with a blank species name', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {
            'selectedItemsList': [
              {'name': '   ', 'quantity': 1, 'lineTotal': 500.0},
              {'name': 'Impala', 'quantity': 1, 'lineTotal': 2500.0},
            ],
          },
        ],
        const {},
      );
      expect(rows.single['species'], 'Impala');
    });

    test('resolves the species name from aliases '
        '(speciesName / speciesId) when name is absent', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {
            'selectedItemsList': [
              {'speciesName': 'Eland', 'quantity': 1, 'lineTotal': 12000.0},
              {'speciesId': 'gemsbok', 'quantity': 1, 'lineTotal': 9000.0},
            ],
          },
        ],
        const {},
      );
      final names = rows.map((r) => r['species']).toSet();
      expect(names, containsAll(['Eland', 'gemsbok']));
    });

    test('sorts by revenue desc with an alphabetical tie-break', () {
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {
            'selectedItemsList': [
              {'name': 'Zebra', 'quantity': 1, 'lineTotal': 1000.0},
              {'name': 'Blesbok', 'quantity': 1, 'lineTotal': 2000.0},
              {'name': 'Eland', 'quantity': 1, 'lineTotal': 2000.0},
            ],
          },
        ],
        const {},
      );
      expect(
        rows.map((r) => r['species']).toList(),
        ['Blesbok', 'Eland', 'Zebra'],
      );
    });

    test('a confirmed booking with package animals makes the breakdown '
        'non-empty (the dashboard empty state disappears)', () {
      // The dashboard empty state renders when the breakdown is empty; a
      // single earned booking with valid species data must produce rows.
      final rows = OutfitterAnalyticsService.aggregateSpeciesRevenue(
        [
          {'packageId': 'pkg-1', 'status': 'Confirmed'},
        ],
        {
          'pkg-1': {
            'speciesItems': [
              {'speciesName': 'Impala', 'quantity': 1, 'total': 2500.0},
            ],
          },
        },
      );
      expect(rows, isNotEmpty);
    });
  });
}
