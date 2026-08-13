import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Active measurement system for the hunter.
///
/// All canonical/internal values are stored in SI units (kilograms, metres,
/// millimetres, degrees Celsius). The active [UnitSystem] only controls how
/// those values are *displayed* to the user, never how they are persisted, so
/// toggling the preference is display-only and cannot corrupt stored data.
enum UnitSystem { metric, imperial }

/// Centralized, app-wide measurement formatter.
///
/// A singleton [ChangeNotifier] so the Hunter Profile toggle can drive it and
/// any screen can read the current system / call the format helpers without
/// threading a controller through every constructor. The preference is
/// persisted to [SharedPreferences] (key `jagspoor_unit_system`) and loaded once
/// at startup via [init] (mirrors [ThemeController]).
///
/// Internal canonical units:
///   weight        -> kilograms
///   distance      -> metres
///   barrel length -> millimetres
///   temperature   -> degrees Celsius
class MeasurementFormatter extends ChangeNotifier {
  static const String _prefsKey = 'jagspoor_unit_system';

  static final MeasurementFormatter instance = MeasurementFormatter._();

  MeasurementFormatter._();

  UnitSystem _system = UnitSystem.metric;
  bool _initialized = false;

  UnitSystem get system => _system;
  bool get isMetric => _system == UnitSystem.metric;
  bool get isImperial => _system == UnitSystem.imperial;

  /// Load the persisted unit preference. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _system = UnitSystem.values.firstWhere(
        (u) => u.name == prefs.getString(_prefsKey),
        orElse: () => UnitSystem.metric,
      );
    } catch (_) {
      _system = UnitSystem.metric;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _system.name);
    } catch (_) {}
  }

  void setSystem(UnitSystem system) {
    if (_system == system) return;
    _system = system;
    _initialized = true;
    _persist();
    notifyListeners();
  }

  void toggle() =>
      setSystem(isMetric ? UnitSystem.imperial : UnitSystem.metric);

  // --- unit suffixes (for relabeling input hints / headers) ---
  String get weightUnit => isMetric ? 'kg' : 'lbs';
  String get distanceUnit => isMetric ? 'm' : 'yd';
  String get barrelLengthUnit => isMetric ? 'mm' : 'in';
  String get temperatureUnit => isMetric ? '°C' : '°F';

  // --- conversions (static, reusable by services) ---
  static double kgToLbs(double kg) => kg * 2.20462262185;
  static double mToYards(double m) => m * 1.0936132983;
  static double yardsToM(double y) => y * 0.9144;
  static double mmToInches(double mm) => mm / 25.4;
  static double inchesToMm(double i) => i * 25.4;
  static double celsiusToFahrenheit(double c) => c * 9.0 / 5.0 + 32.0;

  // --- display formatters (accept canonical SI input) ---
  String formatWeight(double? kg, {int decimals = 1}) {
    if (kg == null) return '--';
    final v = isMetric ? kg : kgToLbs(kg);
    return '${v.toStringAsFixed(decimals)} $weightUnit';
  }

  String formatDistance(double? meters, {int decimals = 0}) {
    if (meters == null) return '--';
    final v = isMetric ? meters : mToYards(meters);
    return '${v.toStringAsFixed(decimals)} $distanceUnit';
  }

  /// Format a distance the caller already has in yards (e.g. ballistic solver
  /// output). Converts to metres first so the active system is honoured.
  String formatDistanceFromYards(double? yards, {int decimals = 0}) {
    if (yards == null) return '--';
    return formatDistance(yardsToM(yards), decimals: decimals);
  }

  /// Format a temperature the caller has in degrees Celsius.
  String formatTemperature(double? celsius, {int decimals = 1}) {
    if (celsius == null) return '--$temperatureUnit';
    final v = isMetric ? celsius : celsiusToFahrenheit(celsius);
    return '${v.toStringAsFixed(decimals)}$temperatureUnit';
  }

  /// Best-effort barrel-length formatter. Barrel length is stored as free text
  /// (e.g. "410", "410mm", "16.5\"", "18 in"). This parses the leading number,
  /// detects an explicit `mm` / `in` suffix, converts to the active system, and
  /// falls back to the raw string when it cannot parse. A bare number with no
  /// suffix is treated as millimetres (the common SA rifle-barrel convention).
  String formatBarrelLength(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    final lower = trimmed.toLowerCase();
    final hasInches = lower.contains('in') || trimmed.contains('"');
    final parsed = double.tryParse(trimmed.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (parsed == null) return raw;
    final valueMm = hasInches ? inchesToMm(parsed) : parsed;
    if (isMetric) return '${valueMm.toStringAsFixed(0)} mm';
    return '${mmToInches(valueMm).toStringAsFixed(2)} in';
  }
}
