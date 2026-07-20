import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'weather_model.dart';

class WeatherRepository {
  // Use the API host (api.open-meteo.com) to avoid 404 responses
  static const _baseUrl = 'https://api.open-meteo.com';

  Future<Position> determineCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions are denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 15),
    );
  }

  Future<WeatherModel> fetchWeatherForLocation({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$_baseUrl/v1/forecast').replace(queryParameters: {
      'latitude': latitude.toStringAsFixed(6),
      'longitude': longitude.toStringAsFixed(6),
      'current_weather': 'true',
      // Request useful hourly fields and request windspeed in km/h for clarity
      'hourly': 'relativehumidity_2m,surface_pressure,windgusts_10m,winddirection_10m',
      'windspeed_unit': 'kmh',
      'timezone': 'auto',
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      // Surface debug info for easier troubleshooting
      throw Exception('Weather fetch failed with status ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return WeatherModel.fromJson(data);
  }
}
