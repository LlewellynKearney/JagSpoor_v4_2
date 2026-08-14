import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// Offline topographic map tile cache.
///
/// Backs the on-device topo matrix with a **disk-persistent** tile store under
/// the app's documents directory (`map_tiles_cache/{z}/{x}/{y}.png`). Tiles
/// survive app restarts and process kills so they remain retrievable when the
/// device reports 0 signal in the bushveld. The store is keyed by the canonical
/// `z/x/y` tile coordinate path, which makes both the live [TileLayer] render
/// path (via [CacheFileTileProvider]) and the pre-download path
/// ([downloadTileRange]) hit the same on-disk files.
class OfflineMapCache {
  late CacheStore _cacheStore;
  late CacheOptions cacheOptions;
  late Dio dio;

  /// Root directory holding every cached tile PNG.
  ///
  /// Populated by [initializeCache]. Exposed so [CacheFileTileProvider] and the
  /// pre-download routine can resolve absolute tile paths without re-querying
  /// the path provider on the hot tile-render path.
  late final Directory cacheDirectory;
  late final String _cacheRoot;

  /// Initialize local disk cache folders inside the phone profile.
  ///
  /// Uses the application documents directory (per-app, survives app upgrades)
  /// and creates the `map_tiles_cache` tree on disk. The persistent offline
  /// store is the **deterministic PNG file tree** (`{root}/{z}/{x}/{y}.png`)
  /// written by [writeTile] and read by [CacheFileTileProvider] — that path
  /// survives app restarts and serves tiles with zero network I/O when the
  /// device reports 0 signal. The Dio [MemCacheStore] here is only a short-lived
  /// in-memory HTTP-response cache for the active download path; it is not the
  /// offline persistence layer.
  Future<void> initializeCache() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    cacheDirectory = Directory('${directory.path}/map_tiles_cache');
    _cacheRoot = cacheDirectory.path;
    if (!cacheDirectory.existsSync()) {
      cacheDirectory.createSync(recursive: true);
    }

    _cacheStore = MemCacheStore();

    cacheOptions = CacheOptions(
      store: _cacheStore,
      // Grab local storage if cell networks drop out completely
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [500, 502, 503, 504],
      // Maintain map segments for up to 30 days offline
      maxStale: const Duration(days: 30),
      priority: CachePriority.high,
    );

    dio = Dio()..interceptors.add(DioCacheInterceptor(options: cacheOptions));
  }

  /// Standard OpenTopoMap URL structure for field hunting contours.
  String getTileUrl(int x, int y, int z) =>
      'https://tile.opentopomap.org/$z/$x/$y.png';

  /// Deterministic on-disk path for a tile PNG.
  ///
  /// The layout `{root}/{z}/{x}/{y}.png` mirrors the standard XYZ tile scheme,
  /// so a tile cached at zoom 12 / x 2048 / y 2047 always lives at the same
  /// absolute path regardless of which code path wrote or read it.
  File tileFile(int x, int y, int z) =>
      File('$_cacheRoot/$z/$x/$y.png');

  /// Whether a tile is already present on disk (does not touch the network).
  bool hasTile(int x, int y, int z) => tileFile(x, y, z).existsSync();

  /// Persist raw tile bytes to the deterministic on-disk path.
  ///
  /// Creates the per-zoom / per-x parent directories lazily. Swallows write
  /// failures (best-effort cache) so a disk error never breaks tile rendering.
  void writeTile(int x, int y, int z, List<int> bytes) {
    try {
      final file = tileFile(x, y, z);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
    } catch (e) {
      debugPrint('OfflineMapCache: failed to persist tile $z/$x/$y: $e');
    }
  }

  /// Number of tiles currently cached on disk (for UI diagnostics).
  int get cachedTileCount {
    if (!cacheDirectory.existsSync()) return 0;
    var count = 0;
    cacheDirectory.listSync(recursive: true).forEach((e) {
      if (e is File && e.path.endsWith('.png')) count++;
    });
    return count;
  }

  /// Download every tile covering a lat/lng bounding box at a given zoom level
  /// (and optional extra zoom levels above/below) into the on-disk cache.
  ///
  /// Returns the number of tiles successfully written. Used by the
  /// "Pre-download area for offline use" action so a hunter can cache a topo
  /// region before losing signal. Network failures are skipped per-tile (a
  /// dropped tile does not abort the whole batch).
  Future<int> downloadTileRange({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    required int zoom,
    int extraZoomLevels = 0,
    CancelToken? cancelToken,
  }) async {
    var written = 0;
    for (var z = zoom - extraZoomLevels; z <= zoom + extraZoomLevels; z++) {
      if (z < 0 || z > 19) continue;
      final range = tileRangeForBounds(
        minLat: minLat,
        minLng: minLng,
        maxLat: maxLat,
        maxLng: maxLng,
        zoom: z,
      );
      for (var x = range.minX; x <= range.maxX; x++) {
        for (var y = range.minY; y <= range.maxY; y++) {
          if (hasTile(x, y, z)) {
            written++;
            continue;
          }
          try {
            final response = await dio.get<List<int>>(
              getTileUrl(x, y, z),
              options: Options(responseType: ResponseType.bytes),
              cancelToken: cancelToken,
            );
            if (response.statusCode == 200 && response.data != null) {
              writeTile(x, y, z, response.data!);
              written++;
            }
          } catch (e) {
            debugPrint('OfflineMapCache: tile $z/$x/$y download failed: $e');
          }
        }
      }
    }
    return written;
  }

  /// Convert a lat/lng bounding box to the inclusive XYZ tile range at `zoom`.
  ///
  /// Pure arithmetic (no network) — the same slippy-map projection flutter_map
  /// uses internally to render tiles. Kept here so the pre-download batch
  /// targets exactly the tiles the live [TileLayer] will request.
  static TileRange tileRangeForBounds({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    required int zoom,
  }) {
    // Clamp latitudes to the valid Web Mercator range.
    final north = minLat.clamp(-85.05, 85.05);
    final south = maxLat.clamp(-85.05, 85.05);
    final west = minLng.clamp(-180.0, 180.0);
    final east = maxLng.clamp(-180.0, 180.0);

    final minTileX = lonToTileX(west, zoom);
    final maxTileX = lonToTileX(east, zoom);
    final minTileY = latToTileY(north, zoom);
    final maxTileY = latToTileY(south, zoom);
    return TileRange(
      minX: minTileX < maxTileX ? minTileX : maxTileX,
      maxX: minTileX < maxTileX ? maxTileX : minTileX,
      minY: minTileY < maxTileY ? minTileY : maxTileY,
      maxY: minTileY < maxTileY ? maxTileY : minTileY,
    );
  }

  /// Web Mercator longitude → tile X column at `zoom` (pure arithmetic).
  static int lonToTileX(double lon, int zoom) =>
      ((lon + 180.0) / 360.0 * (1 << zoom)).floor();

  /// Web Mercator latitude → tile Y row at `zoom` (pure arithmetic).
  static int latToTileY(double lat, int zoom) {
    final latRad = lat * 3.141592653589793 / 180.0;
    return ((1.0 -
                (math.log((1.0 + math.sin(latRad)) / (1.0 - math.sin(latRad))) /
                    2.0 /
                    math.pi)) /
            2.0 *
            (1 << zoom))
        .floor();
  }
}

/// Inclusive XYZ tile range covering a lat/lng bounding box at a given zoom.
class TileRange {
  const TileRange({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  /// Total number of tiles spanned by this range (for UI / quota display).
  int get tileCount => (maxX - minX + 1) * (maxY - minY + 1);
}

/// flutter_map [TileProvider] that serves topographic tiles from the on-disk
/// cache and, on a cache miss, downloads + persists the tile for future
/// offline use.
///
/// This is the tile-render path used by the off-grid navigation map. When the
/// device has signal, missing tiles are fetched from the network and written to
/// [OfflineMapCache]; when signal drops to 0, previously-cached tiles render
/// straight from disk via [FileImage] with no network call at all.
class CacheFileTileProvider extends TileProvider {
  CacheFileTileProvider({required this.cache, super.headers});

  final OfflineMapCache cache;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final file = cache.tileFile(coordinates.x, coordinates.y, coordinates.z);

    // Hot path: tile already on disk → render with zero network I/O.
    if (file.existsSync()) return FileImage(file);

    // Cold path: download via the cache-backed Dio instance, persist to disk,
    // and return a network image for the current frame. The downloaded bytes
    // are also written to the deterministic path so the next render is offline.
    final url = getTileUrl(coordinates, options);
    final fallbackUrl = getTileFallbackUrl(coordinates, options);
    return _CacheAndRenderNetworkImage(
      url: fallbackUrl ?? url,
      primaryUrl: url,
      cache: cache,
      coordinates: coordinates,
    );
  }
}

/// [ImageProvider] that fetches a tile over the network, persists the raw bytes
/// to the on-disk cache for offline reuse, then decodes them for rendering.
class _CacheAndRenderNetworkImage
    extends ImageProvider<_CacheAndRenderNetworkImage> {
  _CacheAndRenderNetworkImage({
    required this.url,
    required this.primaryUrl,
    required this.cache,
    required this.coordinates,
  });

  final String url;
  final String primaryUrl;
  final OfflineMapCache cache;
  final TileCoordinates coordinates;

  @override
  Future<_CacheAndRenderNetworkImage> obtainKey(
    ImageConfiguration configuration,
  ) async => this;

  @override
  bool operator ==(Object other) =>
      other is _CacheAndRenderNetworkImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  ImageStreamCompleter loadImage(
    _CacheAndRenderNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAndCache(key, decode),
      scale: 1.0,
      informationCollector: () sync* {
        yield ErrorDescription(
          'Tile ${coordinates.z}/${coordinates.x}/${coordinates.y}',
        );
      },
    );
  }

  Future<Codec> _loadAndCache(
    _CacheAndRenderNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await _fetchBytes(url);
    // Persist for offline reuse (best-effort; a write failure does not block
    // rendering the current frame).
    cache.writeTile(coordinates.x, coordinates.y, coordinates.z, bytes);
    final buffer = await ImmutableBuffer.fromUint8List(
      Uint8List.fromList(bytes),
    );
    return decode(buffer);
  }

  Future<List<int>> _fetchBytes(String tileUrl) async {
    final response = await cache.dio.get<List<int>>(
      tileUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }
    throw StateError('Tile fetch failed (${response.statusCode}): $tileUrl');
  }
}
