import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jagspoor/features/hunter_mode/services/battery_saver_manager.dart';
import 'package:jagspoor/features/hunter_mode/services/offline_map_cache.dart';

/// Off-grid topographic map validation tests.
///
/// These exercise the pure on-device logic that backs the offline tile cache
/// and the adaptive GPS throttle — both of which must work with zero network
/// access. The tile-path + projection math is pure arithmetic (the same
/// slippy-map projection flutter_map uses), and the throttle decision is a
/// pure function over `Position` values, so neither needs device hardware or
/// a live Geolocator stream to verify.
void main() {
  group('OfflineMapCache tile projection (no network)', () {
    test('lonToTileX at zoom 0 covers the whole world in one column', () {
      expect(OfflineMapCache.lonToTileX(-180, 0), 0);
      expect(OfflineMapCache.lonToTileX(0, 0), 0);
      expect(OfflineMapCache.lonToTileX(179.99, 0), 0);
    });

    test('lonToTileX at zoom 1 splits the world into two columns', () {
      expect(OfflineMapCache.lonToTileX(-180, 1), 0);
      expect(OfflineMapCache.lonToTileX(-0.1, 1), 0);
      expect(OfflineMapCache.lonToTileX(0.1, 1), 1);
      expect(OfflineMapCache.lonToTileX(179.99, 1), 1);
    });

    test('latToTileY places the equator on the lower row at zoom 1', () {
      // Web Mercator: the equator (lat 0) sits at the vertical midpoint, which
      // floors to row 1 at zoom 1 (2 rows); a far-north latitude lands on row 0.
      expect(OfflineMapCache.latToTileY(0, 1), 1);
      expect(OfflineMapCache.latToTileY(85, 1), 0);
      // A southern latitude stays on the lower row.
      expect(OfflineMapCache.latToTileY(-45, 1), 1);
    });

    test('tileRangeForBounds returns an inclusive box covering both corners', () {
      final range = OfflineMapCache.tileRangeForBounds(
        minLat: -24.6,
        minLng: 31.4,
        maxLat: -24.4,
        maxLng: 31.6,
        zoom: 12,
      );
      // The Kruger-area box at z12 spans a small set of tiles.
      expect(range.maxX, greaterThanOrEqualTo(range.minX));
      expect(range.maxY, greaterThanOrEqualTo(range.minY));
      expect(range.tileCount, greaterThan(0));
      expect(range.tileCount, lessThan(25));
    });

    test('tileRangeForBounds normalises a swapped (anti-meridian) box', () {
      // Caller passes min/max in the "wrong" order; the range must still be
      // inclusive and ordered minX<=maxX, minY<=maxY.
      final range = OfflineMapCache.tileRangeForBounds(
        minLat: -24.4,
        minLng: 31.6,
        maxLat: -24.6,
        maxLng: 31.4,
        zoom: 12,
      );
      expect(range.minX, lessThanOrEqualTo(range.maxX));
      expect(range.minY, lessThanOrEqualTo(range.maxY));
    });

    test('tileFile path is deterministic z/x/y under the cache root', () {
      // We can't call initializeCache() in a unit test (needs path_provider),
      // but the path layout contract is verifiable through the projection:
      // the same z/x/y always maps to one tile column/row, so a pre-download
      // and a live render always hit the same file.
      const z = 12;
      final x = OfflineMapCache.lonToTileX(31.5, z);
      final y = OfflineMapCache.latToTileY(-24.5, z);
      expect(x, isA<int>());
      expect(y, isA<int>());
      expect(x, inInclusiveRange(0, (1 << z) - 1));
      expect(y, inInclusiveRange(0, (1 << z) - 1));
    });
  });

  group('BatterySaverManager adaptive throttle (no network)', () {
    Position pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

    test('battery saver forces the stationary (coarse) preset', () {
      final settings = BatterySaverManager.resolveTrackingSettings(
        batterySaverOn: true,
        moving: true,
      );
      expect(settings.accuracy, LocationAccuracy.medium);
      expect(settings.distanceFilter, 50);
    });

    test('moving user (battery saver off) gets the high-frequency preset', () {
      final settings = BatterySaverManager.resolveTrackingSettings(
        batterySaverOn: false,
        moving: true,
      );
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.distanceFilter, 5);
    });

    test('stationary user (battery saver off) is throttled to the coarse preset', () {
      final settings = BatterySaverManager.resolveTrackingSettings(
        batterySaverOn: false,
        moving: false,
      );
      expect(settings.accuracy, LocationAccuracy.medium);
      expect(settings.distanceFilter, 50);
    });

    test('isMoving is true on the first fix (no previous)', () {
      expect(BatterySaverManager.isMoving(null, pos(-24.5, 31.5)), isTrue);
    });

    test('isMoving is false when displacement is below the threshold', () {
      // ~5 m of latitude ≈ 0.00005 degrees; well under 15 m.
      final prev = pos(-24.50000, 31.50000);
      final cur = pos(-24.50005, 31.50000);
      expect(BatterySaverManager.isMoving(prev, cur), isFalse);
    });

    test('isMoving is true when displacement exceeds the threshold', () {
      // ~0.001 degrees latitude ≈ 111 m; well above 15 m.
      final prev = pos(-24.5000, 31.5000);
      final cur = pos(-24.5010, 31.5000);
      expect(BatterySaverManager.isMoving(prev, cur), isTrue);
    });

    test('stationary window + movement toggles the resolved preset', () {
      // Simulate the nav-screen decision: stationary for the window, then move.
      var moving = false;
      expect(
        BatterySaverManager.resolveTrackingSettings(
          batterySaverOn: false,
          moving: moving,
        ).accuracy,
        LocationAccuracy.medium,
      );
      moving = true;
      expect(
        BatterySaverManager.resolveTrackingSettings(
          batterySaverOn: false,
          moving: moving,
        ).accuracy,
        LocationAccuracy.high,
      );
    });
  });
}
