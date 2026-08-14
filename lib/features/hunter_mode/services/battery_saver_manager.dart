import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Battery-saver + stationary-detection throttle for the off-grid GPS tracking
/// loop.
///
/// The bushveld tracking loop historically ran [Geolocator.getPositionStream]
/// at a fixed `LocationAccuracy.high` / 5 m distance filter regardless of
/// whether the hunter was actually moving. When the user is stationary (e.g.
/// glassing from a hide for an hour), that high-frequency fix stream burns
/// battery for no map benefit. This manager centralises the adaptive policy:
///
/// - **Battery saver on** → use the stationary preset immediately (coarse
///   accuracy, larger distance filter) regardless of motion.
/// - **Moving** (recent displacement beyond [stationaryDistanceMeters]) → use
///   the active preset (high accuracy, tight filter) for live breadcrumb
///   recording.
/// - **Stationary** (under the threshold for [stationaryWindowSeconds]) →
///   downgrade to the stationary preset to conserve battery.
///
/// The decision logic ([resolveTrackingSettings]) is pure-Dart and
/// dependency-free (the Geolocator types it returns are plain value holders),
/// so it is fully unit-testable without device hardware.
class BatterySaverManager {
  static const String _batterySaverKey = 'is_off_grid_battery_saver_active';

  /// Minimum displacement (meters) between two fixes that counts as "moving".
  static const double stationaryDistanceMeters = 15.0;

  /// How long the user must be under the displacement threshold before the
  /// stream is throttled to the stationary preset.
  static const int stationaryWindowSeconds = 90;

  /// Active (moving) GPS stream preset.
  static const LocationSettings activePreset = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5, // update every 5 m
  );

  /// Stationary / battery-saver GPS stream preset.
  static const LocationSettings stationaryPreset = LocationSettings(
    accuracy: LocationAccuracy.medium,
    distanceFilter: 50, // update every 50 m only
  );

  // Toggle the energy saver flag state inside local device memory
  Future<void> toggleBatterySaver(bool active) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_batterySaverKey, active);

    if (active) {
      debugPrint('🔋 ENERGY CONSERVATION STATE ACTIVE: Polling throttled.');
    } else {
      debugPrint('⚡ PERFORMANCE MODE ENGAGED: Real-time telemetry active.');
    }
  }

  Future<bool> isBatterySaverEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_batterySaverKey) ?? false;
  }

  /// Resolve which [LocationSettings] the tracking loop should use right now.
  ///
  /// [batterySaverOn] is the persisted user toggle; [moving] is whether the
  /// most recent displacement exceeded the stationary threshold within the
  /// stationary window. Battery saver short-circuits to the stationary preset;
  /// otherwise the moving/stationary presets drive the trade-off.
  static LocationSettings resolveTrackingSettings({
    required bool batterySaverOn,
    required bool moving,
  }) {
    if (batterySaverOn) return stationaryPreset;
    return moving ? activePreset : stationaryPreset;
  }

  /// Determine whether the latest fix counts as movement vs the previous one.
  ///
  /// Pure function over [Position] values: compares the great-circle
  /// displacement to [stationaryDistanceMeters] using Geolocator's
  /// distanceBetween helper (which is itself pure arithmetic, no network).
  static bool isMoving(Position? previous, Position current) {
    if (previous == null) return true;
    final meters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );
    return meters > stationaryDistanceMeters;
  }
}
