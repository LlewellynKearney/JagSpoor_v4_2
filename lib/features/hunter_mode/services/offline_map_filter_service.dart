import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Offline geographic + temporal filter helpers for the off-grid map.
///
/// All operations are pure arithmetic running entirely on-device with no
/// network calls: Haversine radius checks and timestamp-age checks used by
/// the offline navigation screen to filter carcass logs / waypoints by
/// distance from the current centre and by recency.
class OfflineMapFilterService {
  static final OfflineMapFilterService instance =
      OfflineMapFilterService._internal();
  OfflineMapFilterService._internal();

  /// Earth radius in kilometers for Haversine formula calculations.
  static const double earthRadiusKm = 6371.0;

  /// Calculates the distance between two GPS coordinates using the Haversine
  /// formula. Runs entirely offline.
  ///
  /// Returns true if the target coordinate is within [maxRadiusKm] of the
  /// centre coordinate.
  bool isCoordinateWithinRadius({
    required double centerLat,
    required double centerLon,
    required double targetLat,
    required double targetLon,
    required double maxRadiusKm,
  }) {
    final distanceKm = _calculateHaversineDistance(
      lat1: centerLat,
      lon1: centerLon,
      lat2: targetLat,
      lon2: targetLon,
    );
    return distanceKm <= maxRadiusKm;
  }

  double _calculateHaversineDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    final deltaLatRad = _degreesToRadians(lat2 - lat1);
    final deltaLonRad = _degreesToRadians(lon2 - lon1);

    final a =
        math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLonRad / 2) *
            math.sin(deltaLonRad / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  /// Checks if a document timestamp is within [maxHoursFilter] hours from now.
  /// Runs entirely offline.
  bool isTimestampWithinHours({
    required int documentTimestampMillis,
    required int maxHoursFilter,
  }) {
    if (documentTimestampMillis <= 0 || maxHoursFilter <= 0) {
      return false;
    }
    final currentTimeMillis = DateTime.now().millisecondsSinceEpoch;
    final maxAgeMillis = maxHoursFilter * 3600000;
    final ageMillis = currentTimeMillis - documentTimestampMillis;
    return ageMillis < maxAgeMillis;
  }

  bool isTimestampWithinHoursFromTimestamp({
    required Timestamp timestamp,
    required int maxHoursFilter,
  }) {
    return isTimestampWithinHours(
      documentTimestampMillis: timestamp.millisecondsSinceEpoch,
      maxHoursFilter: maxHoursFilter,
    );
  }

  bool isTimestampWithinHoursFromDateTime({
    required DateTime documentDateTime,
    required int maxHoursFilter,
  }) {
    return isTimestampWithinHours(
      documentTimestampMillis: documentDateTime.millisecondsSinceEpoch,
      maxHoursFilter: maxHoursFilter,
    );
  }
}
