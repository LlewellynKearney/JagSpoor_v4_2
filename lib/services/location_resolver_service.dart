import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationResolverService {
  static const String _cachePrefix = 'location_cache_';
  static const int _cacheExpiryHours = 24;

  /// In-memory cache for fast lookups during app session
  static final Map<String, String> _memoryCache = {};

  /// Get the closest town name from GPS coordinates
  /// Returns the town name or null if lookup fails
  static Future<String?> getClosestTown(double lat, double lng) async {
    // Create a cache key based on GPS sector (rounded to 2 decimal places)
    final cacheKey = _getCacheKey(lat, lng);

    // Check memory cache first
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    // Check persistent cache
    final cachedTown = await _getCachedTown(cacheKey);
    if (cachedTown != null) {
      _memoryCache[cacheKey] = cachedTown;
      return cachedTown;
    }

    // Perform geocoding lookup
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;

        // Prefer locality (town/city name), fall back to administrative area
        String? townName =
            placemark.locality ??
            placemark.subAdministrativeArea ??
            placemark.administrativeArea;

        if (townName != null && townName.isNotEmpty) {
          // Cache the result
          await _cacheTown(cacheKey, townName);
          _memoryCache[cacheKey] = townName;
          return townName;
        }
      }
    } catch (e) {
      // Geocoding failed - likely offline or network error
      // Return null to allow fallback to coordinates
      return null;
    }

    return null;
  }

  /// Format coordinates as a fallback string when town lookup fails
  static String formatCoordinatesFallback(double lat, double lng) {
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  /// Generate a cache key based on GPS sector (rounded coordinates)
  static String _getCacheKey(double lat, double lng) {
    final latSector = (lat * 100).round() / 100;
    final lngSector = (lng * 100).round() / 100;
    return '$_cachePrefix${latSector}_$lngSector';
  }

  /// Get cached town from persistent storage
  static Future<String?> _getCachedTown(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null) {
        // Parse the cached data (format: "townName|timestamp")
        final parts = cachedData.split('|');
        if (parts.length == 2) {
          final timestamp = int.tryParse(parts[1]);
          if (timestamp != null) {
            final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
            final maxAge = _cacheExpiryHours * 60 * 60 * 1000;

            // Return cached town if not expired
            if (cacheAge < maxAge) {
              return parts[0];
            } else {
              // Remove expired cache entry
              await prefs.remove(cacheKey);
            }
          }
        }
      }
    } catch (e) {
      // If cache read fails, just return null
    }
    return null;
  }

  /// Cache town name with timestamp
  static Future<void> _cacheTown(String cacheKey, String townName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(cacheKey, '$townName|$timestamp');
    } catch (e) {
      // If cache write fails, continue without caching
    }
  }

  /// Clear all cached location data
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_cachePrefix)) {
          await prefs.remove(key);
        }
      }

      _memoryCache.clear();
    } catch (e) {
      // If cache clear fails, continue
    }
  }
}
