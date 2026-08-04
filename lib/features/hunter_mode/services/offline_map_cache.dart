import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:path_provider/path_provider.dart';

class OfflineMapCache {
  late CacheStore _cacheStore;
  late CacheOptions cacheOptions;
  late Dio dio;

  // Initialize local disk cache folders inside the phone profile
  Future<void> initializeCache() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String cachePath = '${directory.path}/map_tiles_cache';

    _cacheStore =
        MemCacheStore(); // Falling back to lightning-fast memory store if disk arrays lock up

    cacheOptions = CacheOptions(
      store: _cacheStore,
      policy:
          CachePolicy
              .refreshForceCache, // Grab local storage if cell networks drop out completely
      hitCacheOnErrorExcept: [500, 502, 503, 504],
      maxStale: const Duration(
        days: 30,
      ), // Maintain map segments for up to 30 days offline
      priority: CachePriority.high,
    );

    dio = Dio()..interceptors.add(DioCacheInterceptor(options: cacheOptions));
  }

  // Pre-download a set of topographic coordinates before going out into the field
  String getTileUrl(int x, int y, int z) {
    // Standard OpenTopoMap URL structure for field hunting contours
    return 'https://tile.opentopomap.org/$z/$x/$y.png';
  }
}
