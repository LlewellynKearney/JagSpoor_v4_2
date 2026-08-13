class WeatherModel {
  final double latitude;
  final double longitude;
  final double temperatureC;
  final double humidityPercent;
  final double surfacePressureHpa;
  final double windSpeedKmh;
  final double windGustKmh;
  final double windDirectionDegrees;
  final DateTime fetchedAt;

  // Solar forecast (today's sunrise/sunset, local time).
  final DateTime? sunrise;
  final DateTime? sunset;

  // Lunar forecast: illuminated fraction (0 = new, 0.5 = quarter, 1 = full)
  // and a human-readable phase name.
  final double moonPhaseFraction;
  final String moonPhaseName;

  WeatherModel({
    required this.latitude,
    required this.longitude,
    required this.temperatureC,
    required this.humidityPercent,
    required this.surfacePressureHpa,
    required this.windSpeedKmh,
    required this.windGustKmh,
    required this.windDirectionDegrees,
    required this.fetchedAt,
    this.sunrise,
    this.sunset,
    this.moonPhaseFraction = 0.0,
    this.moonPhaseName = 'New Moon',
  });

  factory WeatherModel.fromJson(Map<String, dynamic> json) {
    final currentWeather = Map<String, dynamic>.from(
      json['current_weather'] as Map<String, dynamic>,
    );
    final hourly = Map<String, dynamic>.from(
      json['hourly'] as Map<String, dynamic>,
    );

    final currentTime = currentWeather['time'] as String? ?? '';
    final hourlyTimes = List<String>.from(hourly['time'] as List<dynamic>);
    final timeIndex = hourlyTimes
        .indexOf(currentTime)
        .clamp(0, hourlyTimes.length - 1);

    final humidity = _doubleFromDynamic(
      _valueAt(hourly['relativehumidity_2m'] as List<dynamic>?, timeIndex),
    );
    final pressure = _doubleFromDynamic(
      _valueAt(hourly['surface_pressure'] as List<dynamic>?, timeIndex),
    );
    final gusts = _doubleFromDynamic(
      _valueAt(hourly['windgusts_10m'] as List<dynamic>?, timeIndex),
    );
    final windDir = _doubleFromDynamic(
      _valueAt(hourly['winddirection_10m'] as List<dynamic>?, timeIndex),
    );

    // Solar forecast (today's sunrise/sunset) from the daily block.
    DateTime? sunrise;
    DateTime? sunset;
    if (json['daily'] is Map) {
      final daily = Map<String, dynamic>.from(json['daily'] as Map);
      final sunriseList = daily['sunrise'] as List<dynamic>?;
      final sunsetList = daily['sunset'] as List<dynamic>?;
      if (sunriseList != null && sunriseList.isNotEmpty) {
        sunrise = _tryParseTime(sunriseList.first);
      }
      if (sunsetList != null && sunsetList.isNotEmpty) {
        sunset = _tryParseTime(sunsetList.first);
      }
    }

    final fetchedAt = DateTime.now().toUtc();
    final moonFraction = _moonPhaseFraction(fetchedAt);
    final moonName = _moonPhaseName(moonFraction);

    return WeatherModel(
      latitude: _doubleFromDynamic(json['latitude']),
      longitude: _doubleFromDynamic(json['longitude']),
      temperatureC: _doubleFromDynamic(currentWeather['temperature']),
      humidityPercent: humidity,
      surfacePressureHpa: pressure,
      windSpeedKmh: _doubleFromDynamic(currentWeather['windspeed']),
      windGustKmh: gusts,
      windDirectionDegrees: windDir,
      fetchedAt: fetchedAt,
      sunrise: sunrise,
      sunset: sunset,
      moonPhaseFraction: moonFraction,
      moonPhaseName: moonName,
    );
  }

  static double _doubleFromDynamic(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  static dynamic _valueAt(List<dynamic>? list, int index) {
    if (list == null || list.isEmpty) return 0.0;
    final safeIndex = index.clamp(0, list.length - 1);
    return list[safeIndex];
  }

  static DateTime? _tryParseTime(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  /// Illuminated fraction of the moon (0 = new, 1 = full) computed from the
  /// standard synodic-month approximation referenced to the 2000-01-06 new
  /// moon. Pure astronomical calc — no network needed, works fully offline.
  static double _moonPhaseFraction(DateTime date) {
    // Known new moon: 2000-01-06 18:14 UTC.
    final knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
    const synodicDays = 29.530588853;
    final elapsedDays =
        date.toUtc().difference(knownNewMoon).inMilliseconds /
        86400000.0;
    var phase = (elapsedDays % synodicDays) / synodicDays;
    if (phase < 0) phase += 1;
    return phase;
  }

  static String _moonPhaseName(double phase) {
    return moonPhaseNameFor(phase);
  }

  /// Human-readable moon-phase name for a phase fraction in [0,1).
  /// Public so cached values can resolve a name without re-deriving it.
  static String moonPhaseNameFor(double phase) {
    // phase in [0,1): 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter
    final p = phase;
    if (p < 0.0375 || p >= 0.9625) return 'New Moon';
    if (p < 0.2125) return 'Waxing Crescent';
    if (p < 0.2875) return 'First Quarter';
    if (p < 0.4625) return 'Waxing Gibbous';
    if (p < 0.5375) return 'Full Moon';
    if (p < 0.7125) return 'Waning Gibbous';
    if (p < 0.7875) return 'Last Quarter';
    return 'Waning Crescent';
  }

  static int windDirectionToClock(double degrees) {
    final normalized = (degrees % 360 + 360) % 360;
    final result = ((normalized + 15) / 30).floor() % 12;
    return result == 0 ? 12 : result;
  }

  String get windClockFace =>
      '${windDirectionToClock(windDirectionDegrees)} o\'clock';

  /// "HH:mm" formatted sunrise for display.
  String get sunriseText =>
      sunrise == null ? '—' : _formatHm(sunrise!.toLocal());

  /// "HH:mm" formatted sunset for display.
  String get sunsetText =>
      sunset == null ? '—' : _formatHm(sunset!.toLocal());

  /// Illuminated percentage (0–100).
  int get moonIlluminationPercent => (moonPhaseFraction * 100).round();

  String _formatHm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
