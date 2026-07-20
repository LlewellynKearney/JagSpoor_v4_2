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
  });

  factory WeatherModel.fromJson(Map<String, dynamic> json) {
    final currentWeather = Map<String, dynamic>.from(json['current_weather'] as Map<String, dynamic>);
    final hourly = Map<String, dynamic>.from(json['hourly'] as Map<String, dynamic>);

    final currentTime = currentWeather['time'] as String? ?? '';
    final hourlyTimes = List<String>.from(hourly['time'] as List<dynamic>);
    final timeIndex = hourlyTimes.indexOf(currentTime).clamp(0, hourlyTimes.length - 1);

    final humidity = _doubleFromDynamic(_valueAt(hourly['relativehumidity_2m'] as List<dynamic>?, timeIndex));
    final pressure = _doubleFromDynamic(_valueAt(hourly['surface_pressure'] as List<dynamic>?, timeIndex));
    final gusts = _doubleFromDynamic(_valueAt(hourly['windgusts_10m'] as List<dynamic>?, timeIndex));
    final windDir = _doubleFromDynamic(_valueAt(hourly['winddirection_10m'] as List<dynamic>?, timeIndex));

    return WeatherModel(
      latitude: _doubleFromDynamic(json['latitude']),
      longitude: _doubleFromDynamic(json['longitude']),
      temperatureC: _doubleFromDynamic(currentWeather['temperature']),
      humidityPercent: humidity,
      surfacePressureHpa: pressure,
      windSpeedKmh: _doubleFromDynamic(currentWeather['windspeed']),
      windGustKmh: gusts,
      windDirectionDegrees: windDir,
      fetchedAt: DateTime.now().toUtc(),
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

  static int windDirectionToClock(double degrees) {
    final normalized = (degrees % 360 + 360) % 360;
    final result = ((normalized + 15) / 30).floor() % 12;
    return result == 0 ? 12 : result;
  }

  String get windClockFace => '${windDirectionToClock(windDirectionDegrees)} o\'clock';
}
