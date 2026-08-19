import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/screens/hunter_trophy_browser_screen.dart';

/// Unit tests for the Trophy Registry & Booking browser's farm/location
/// resolvers -- the pure functions that fix the "Unknown Farm" fallback by
/// resolving the actual farm name + town/location from the resolved `farms`
/// document (trophy_stock docs carry only a `farmId`).
///
/// Regression guard for the two bugs fixed together:
///  1. `farmName` was read off the stock doc (where it does not exist), so
///     every card fell back to "Unknown Farm" even though the parent `farms`
///     doc carries the real `name`.
///  2. The province filter ran server-side on `trophy_stock.province` (a
///     field that does not exist there), so any specific province matched
///     ZERO documents. The filter is now applied client-side on the resolved
///     farm location.
void main() {
  group('resolveFarmName', () {
    test('resolves the real farm name from the farms doc (the bug fix)', () {
      // The stock doc carries ONLY a farmId (per the data screenshot); the
      // farm name must come from the resolved farms document.
      expect(
        resolveFarmName(
          {'farmId': '24co460o749zmT7Hl3dtB'},
          {'name': 'Bosveld Ranch'},
        ),
        'Bosveld Ranch',
      );
    });

    test('prefers a denormalised farmName on the stock doc (legacy)', () {
      expect(
        resolveFarmName(
          {'farmId': 'f1', 'farmName': 'Legacy Plains'},
          {'name': 'Bosveld Ranch'},
        ),
        'Legacy Plains',
      );
    });

    test('falls back to Unknown Farm when nothing resolves', () {
      expect(resolveFarmName({'farmId': 'f1'}, null), 'Unknown Farm');
      expect(
        resolveFarmName({'farmId': 'f1', 'farmName': '  '}, {'name': ''}),
        'Unknown Farm',
      );
    });

    test('tolerates a missing farms doc (null farmData)', () {
      expect(resolveFarmName({'farmId': 'f1'}, null), 'Unknown Farm');
    });
  });

  group('resolveTrophyProvince', () {
    test('an explicit province on the stock doc wins', () {
      expect(
        resolveTrophyProvince(
          {'province': 'Limpopo'},
          {'province': 'Mpumalanga'},
        ),
        'Limpopo',
      );
    });

    test('falls back to the farms doc province', () {
      expect(
        resolveTrophyProvince({'farmId': 'f1'}, {'province': 'Limpopo'}),
        'Limpopo',
      );
    });

    test('empty when neither resolves', () {
      expect(resolveTrophyProvince({'farmId': 'f1'}, null), '');
    });
  });

  group('resolveTown', () {
    test('an explicit town on the stock doc wins', () {
      expect(
        resolveTown({'town': 'Mokopane'}, {'town': 'Other', 'district': 'X'}),
        'Mokopane',
      );
    });

    test('falls back to the farm doc town, then district', () {
      expect(
        resolveTown({'farmId': 'f1'}, {'town': 'Mokopane', 'district': 'W'}),
        'Mokopane',
      );
      expect(
        resolveTown({'farmId': 'f1'}, {'district': 'Waterberg'}),
        'Waterberg',
      );
    });

    test('empty when nothing resolves', () {
      expect(resolveTown({'farmId': 'f1'}, null), '');
    });
  });

  group('resolveLocationLabel', () {
    test('renders "farm • town, province"', () {
      expect(
        resolveLocationLabel(
          {'farmId': 'f1'},
          {'name': 'Bosveld Ranch', 'town': 'Mokopane', 'province': 'Limpopo'},
        ),
        'Bosveld Ranch • Mokopane, Limpopo',
      );
    });

    test('omits empty location parts (no dangling separator)', () {
      expect(
        resolveLocationLabel(
          {'farmId': 'f1'},
          {'name': 'Bosveld Ranch'},
        ),
        'Bosveld Ranch',
      );
      expect(
        resolveLocationLabel(
          {'farmId': 'f1'},
          {'name': 'Bosveld Ranch', 'province': 'Limpopo'},
        ),
        'Bosveld Ranch • Limpopo',
      );
    });

    test('still falls back cleanly when no farm resolves', () {
      expect(resolveLocationLabel({'farmId': 'f1'}, null), 'Unknown Farm');
    });
  });

  group('locationLabel (card-level joined fields)', () {
    test('joins the pre-resolved farm + town + province', () {
      expect(
        locationLabel({
          'farmName': 'Bosveld Ranch',
          'town': 'Mokopane',
          'province': 'Limpopo',
        }),
        'Bosveld Ranch • Mokopane, Limpopo',
      );
    });

    test('farm only when no location parts resolve', () {
      expect(
        locationLabel({'farmName': 'Bosveld Ranch', 'town': '', 'province': ''}),
        'Bosveld Ranch',
      );
    });
  });

  group('resolveImageUrl', () {
    test('an explicit imageUrl wins', () {
      expect(
        resolveImageUrl({
          'imageUrl': 'https://x/y.jpg',
          'trophyPhotoUrls': ['https://a/b.jpg'],
        }),
        'https://x/y.jpg',
      );
    });

    test('falls back to the first trophyPhotoUrls entry (syncTrophyStock '
        'writes this array)', () {
      expect(
        resolveImageUrl({
          'trophyPhotoUrls': ['https://a/first.jpg', 'https://a/second.jpg'],
        }),
        'https://a/first.jpg',
      );
    });

    test('empty when no photo resolves', () {
      expect(resolveImageUrl({}), '');
      expect(resolveImageUrl({'trophyPhotoUrls': 'not-a-list'}), '');
      expect(resolveImageUrl({'trophyPhotoUrls': []}), '');
    });

    test('skips blank photo entries', () {
      expect(
        resolveImageUrl({
          'trophyPhotoUrls': ['', '  ', 'https://a/real.jpg'],
        }),
        'https://a/real.jpg',
      );
    });
  });

  group('resolveMeasurement', () {
    test('reads trophyMeasurement (num)', () {
      expect(
        resolveMeasurement({
          'trophyMeasurement': 28.5,
          'trophyLengthInches': 29.0,
        }),
        28.5,
      );
    });

    test('falls back to the trophyLengthInches alias', () {
      expect(resolveMeasurement({'trophyLengthInches': 29.0}), 29.0);
    });

    test('tolerates numeric-string storage', () {
      expect(resolveMeasurement({'trophyMeasurement': '30.25'}), 30.25);
    });

    test('null when absent or unparseable', () {
      expect(resolveMeasurement({}), isNull);
      expect(resolveMeasurement({'trophyMeasurement': 'big'}), isNull);
    });
  });
}
