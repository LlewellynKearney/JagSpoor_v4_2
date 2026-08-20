import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart';
import 'package:jagspoor/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart';

void main() {
  group('resolveFarmPhotoUrl', () {
    test('returns the explicit photoUrl when present', () {
      expect(
        resolveFarmPhotoUrl({'photoUrl': 'https://example.com/farm.jpg'}),
        'https://example.com/farm.jpg',
      );
    });

    test('falls back to the first non-empty photoUrls entry', () {
      expect(
        resolveFarmPhotoUrl({
          'photoUrls': ['', 'https://example.com/farm2.jpg'],
        }),
        'https://example.com/farm2.jpg',
      );
    });

    test('photoUrl wins over photoUrls', () {
      expect(
        resolveFarmPhotoUrl({
          'photoUrl': 'https://example.com/primary.jpg',
          'photoUrls': ['https://example.com/other.jpg'],
        }),
        'https://example.com/primary.jpg',
      );
    });

    test('trims whitespace from the URL', () {
      expect(
        resolveFarmPhotoUrl({'photoUrl': '  https://example.com/f.jpg  '}),
        'https://example.com/f.jpg',
      );
    });

    test('returns empty when no photo fields exist', () {
      expect(resolveFarmPhotoUrl(const {}), '');
      expect(
        resolveFarmPhotoUrl({'photoUrl': '', 'photoUrls': <String>[]}),
        '',
      );
    });

    test('ignores non-string entries in photoUrls', () {
      expect(
        resolveFarmPhotoUrl({
          'photoUrls': [123, null],
        }),
        '',
      );
    });
  });

  group('resolveTrophyStockPhotoUrl', () {
    test('returns the first trophyPhotoUrls entry', () {
      expect(
        resolveTrophyStockPhotoUrl({
          'trophyPhotoUrls': ['https://example.com/t1.jpg', 'https://x/y.jpg'],
        }),
        'https://example.com/t1.jpg',
      );
    });

    test('skips blank entries', () {
      expect(
        resolveTrophyStockPhotoUrl({
          'trophyPhotoUrls': [' ', 'https://example.com/t2.jpg'],
        }),
        'https://example.com/t2.jpg',
      );
    });

    test('falls back to photoUrl when trophyPhotoUrls is empty', () {
      expect(
        resolveTrophyStockPhotoUrl({
          'trophyPhotoUrls': <String>[],
          'photoUrl': 'https://example.com/legacy.jpg',
        }),
        'https://example.com/legacy.jpg',
      );
    });

    test('returns empty when no photo fields exist', () {
      expect(resolveTrophyStockPhotoUrl(const {}), '');
      expect(
        resolveTrophyStockPhotoUrl({
          'trophyPhotoUrls': <String>[],
          'photoUrl': '',
        }),
        '',
      );
    });

    test('ignores non-string entries', () {
      expect(
        resolveTrophyStockPhotoUrl({
          'trophyPhotoUrls': [42],
        }),
        '',
      );
    });
  });
}
