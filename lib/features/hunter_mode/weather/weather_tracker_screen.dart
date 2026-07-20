import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/location_resolver_service.dart';
import 'weather_model.dart';
import 'weather_repository.dart';

class WeatherTrackerScreen extends StatefulWidget {
  final ThemeController theme;

  const WeatherTrackerScreen({super.key, required this.theme});

  @override
  State<WeatherTrackerScreen> createState() => _WeatherTrackerScreenState();
}

class _WeatherTrackerScreenState extends State<WeatherTrackerScreen> {
  final WeatherRepository _weatherRepository = WeatherRepository();
  bool _isLoading = false;
  WeatherModel? _weather;
  Position? _currentPosition;
  String? _failureMessage;
  String? _cachedLocationText;
  String? _resolvedTownName;
  double? _compassHeading;
  StreamSubscription<CompassEvent>? _compassSubscription;

  static const String _prefLatitude = 'cached_latitude';
  static const String _prefLongitude = 'cached_longitude';
  static const String _prefLocationText = 'cached_location_text';
  static const String _prefTownName = 'cached_town_name';
  static const String _prefTemperature = 'cached_temperature';
  static const String _prefSurfacePressure = 'cached_surface_pressure';
  static const String _prefHumidity = 'cached_humidity';
  static const String _prefWindSpeed = 'cached_wind_speed';
  static const String _prefWindDirection = 'cached_wind_direction';
  static const String _prefWindGust = 'cached_wind_gust';
  static const String _prefWeatherFetchedAt = 'cached_weather_fetched_at';

  @override
  void initState() {
    super.initState();
    _loadCachedLocation();
    _loadCachedWeather();
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _compassHeading = event.heading;
        });
      }
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_prefLatitude);
    final lon = prefs.getDouble(_prefLongitude);
    final locationText = prefs.getString(_prefLocationText);
    final townName = prefs.getString(_prefTownName);

    if (lat != null && lon != null && mounted) {
      setState(() {
        _currentPosition = Position(
          latitude: lat,
          longitude: lon,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
        _cachedLocationText = locationText;
        _resolvedTownName = townName;
      });
    }
  }

  Future<void> _loadCachedWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final temperature = prefs.getDouble(_prefTemperature);
    final surfacePressure = prefs.getDouble(_prefSurfacePressure);
    final humidity = prefs.getDouble(_prefHumidity);
    final windSpeed = prefs.getDouble(_prefWindSpeed);
    final windDirection = prefs.getDouble(_prefWindDirection);
    final windGust = prefs.getDouble(_prefWindGust);
    final fetchedAtStr = prefs.getString(_prefWeatherFetchedAt);
    final lat = prefs.getDouble(_prefLatitude);
    final lon = prefs.getDouble(_prefLongitude);

    if (temperature != null &&
        surfacePressure != null &&
        humidity != null &&
        windSpeed != null &&
        windDirection != null &&
        windGust != null &&
        fetchedAtStr != null &&
        lat != null &&
        lon != null &&
        mounted) {
      setState(() {
        _weather = WeatherModel(
          latitude: lat,
          longitude: lon,
          temperatureC: temperature,
          surfacePressureHpa: surfacePressure,
          humidityPercent: humidity,
          windSpeedKmh: windSpeed,
          windDirectionDegrees: windDirection,
          windGustKmh: windGust,
          fetchedAt: DateTime.parse(fetchedAtStr),
        );
      });
    }
  }

  Future<void> _saveCachedLocation(
    double lat,
    double lon,
    String? townName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefLatitude, lat);
    await prefs.setDouble(_prefLongitude, lon);
    await prefs.setString(
      _prefLocationText,
      'Lat ${lat.toStringAsFixed(5)}, Lon ${lon.toStringAsFixed(5)}',
    );
    if (townName != null && townName.isNotEmpty) {
      await prefs.setString(_prefTownName, townName);
    }
  }

  Future<void> _saveCachedWeather(WeatherModel weather) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefTemperature, weather.temperatureC);
    await prefs.setDouble(_prefSurfacePressure, weather.surfacePressureHpa);
    await prefs.setDouble(_prefHumidity, weather.humidityPercent);
    await prefs.setDouble(_prefWindSpeed, weather.windSpeedKmh);
    await prefs.setDouble(_prefWindDirection, weather.windDirectionDegrees);
    await prefs.setDouble(_prefWindGust, weather.windGustKmh);
    await prefs.setString(
      _prefWeatherFetchedAt,
      weather.fetchedAt.toIso8601String(),
    );
  }

  Future<void> _updateCurrentWeather() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _failureMessage = null;
    });

    try {
      final position = await _weatherRepository.determineCurrentPosition();

      // Resolve town name from coordinates
      final townName = await LocationResolverService.getClosestTown(
        position.latitude,
        position.longitude,
      );

      await _saveCachedLocation(
        position.latitude,
        position.longitude,
        townName,
      );
      final weather = await _weatherRepository.fetchWeatherForLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await _saveCachedWeather(weather);

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _weather = weather;
          // Only update town name if geocoding succeeded, otherwise keep cached value
          if (townName != null && townName.isNotEmpty) {
            _resolvedTownName = townName;
          }
          _cachedLocationText =
              'Lat ${position.latitude.toStringAsFixed(5)}, Lon ${position.longitude.toStringAsFixed(5)}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failureMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: theme,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'TACTICAL WEATHER TRACKER',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 18,
              ),
            ),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: theme.accentColor,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Stack(
            children: [
              Container(
                width: size.width,
                height: size.height,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.4),
                    radius: 1.2,
                    colors: [
                      theme.accentColor.withAlpha(15),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'LIVE WEATHER TRACKING',
                          style: TextStyle(
                            color: theme.textColor.withAlpha(140),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildStatusCard(theme),
                        const SizedBox(height: 20),
                        _buildUpdateButton(theme),
                        const SizedBox(height: 24),
                        _buildWeatherMetricsGrid(theme),
                        const SizedBox(height: 24),
                        _buildWindSummaryCard(theme),
                        const SizedBox(height: 24),
                        _buildCompassCard(theme),
                        if (_failureMessage != null) ...[
                          const SizedBox(height: 24),
                          _buildErrorCard(theme, _failureMessage!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                Container(
                  width: size.width,
                  height: size.height,
                  color: Colors.black.withValues(alpha: 0.24),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(ThemeController theme) {
    final locationText =
        _cachedLocationText ??
        (_currentPosition != null
            ? 'Lat ${_currentPosition!.latitude.toStringAsFixed(5)}, Lon ${_currentPosition!.longitude.toStringAsFixed(5)}'
            : 'Press update to fetch hunter location.');
    final updatedText = _weather != null
        ? 'Last update ${_weather!.fetchedAt.toLocal().toString().replaceFirst(RegExp(r"\.\d+"), "")}'
        : 'No weather data loaded yet.';
    final townSubtitle =
        _resolvedTownName != null && _resolvedTownName!.isNotEmpty
        ? 'Near $_resolvedTownName${_weather == null ? ' (cached)' : ''}'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.textColor.withAlpha(20), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locationText,
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          if (townSubtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              townSubtitle,
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            updatedText,
            style: TextStyle(
              color: theme.textColor.withAlpha(140),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateButton(ThemeController theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _updateCurrentWeather,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accentColor,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
        ),
        child: Text(
          'UPDATE CURRENT LOCATION',
          style: TextStyle(
            color: theme.backgroundColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherMetricsGrid(ThemeController theme) {
    final temperature = _weather != null
        ? '${_weather!.temperatureC.toStringAsFixed(1)}°C'
        : '--°C';
    final humidity = _weather != null
        ? '${_weather!.humidityPercent.toStringAsFixed(0)}%'
        : '--%';
    final pressure = _weather != null
        ? '${_weather!.surfacePressureHpa.toStringAsFixed(0)} hPa'
        : '-- hPa';
    final windValue = _weather != null
        ? '${_weather!.windSpeedKmh.toStringAsFixed(1)} km/h • Gust ${_weather!.windGustKmh.toStringAsFixed(1)} km/h\n${_weather!.windClockFace}'
        : '--';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                theme: theme,
                label: 'TEMPERATURE',
                value: temperature,
                icon: Icons.thermostat_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                theme: theme,
                label: 'HUMIDITY',
                value: humidity,
                icon: Icons.water_drop_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                theme: theme,
                label: 'SURFACE PRESSURE',
                value: pressure,
                icon: Icons.speed_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                theme: theme,
                label: 'WIND',
                value: windValue,
                icon: Icons.wind_power_rounded,
                multiline: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required ThemeController theme,
    required String label,
    required String value,
    required IconData icon,
    bool multiline = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.textColor.withAlpha(15), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.accentColor.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: theme.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.textColor.withAlpha(128),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                  maxLines: multiline ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindSummaryCard(ThemeController theme) {
    final text = _weather != null
        ? 'Wind from ${_weather!.windClockFace} (${_weather!.windDirectionDegrees.toStringAsFixed(0)}°).'
        : 'Awaiting location update to see wind direction.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.textColor.withAlpha(20), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TACTICAL WIND CLOCK',
            style: TextStyle(
              color: theme.textColor.withAlpha(180),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Use the clock face heading to align your stalking approach and scent control strategy.',
            style: TextStyle(
              color: theme.textColor.withAlpha(140),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeController theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: theme.textColor.withAlpha(180),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompassCard(ThemeController theme) {
    final windBearing = _weather?.windDirectionDegrees ?? 0.0;
    final inverseBearing = (windBearing + 180) % 360;
    final cardinalDirection = _getCardinalDirection(inverseBearing);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.textColor.withAlpha(20), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'TACTICAL COMPASS WHEEL',
                style: TextStyle(
                  color: theme.textColor.withAlpha(180),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showStalkingGuideDialog(context),
                child: Icon(
                  Icons.info_outline,
                  color: theme.accentColor,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildCompassDial(theme),
                _buildWindVectorArrow(theme, windBearing),
                _buildDeviceHeadingIndicator(theme),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildStalkPromptBadge(theme, cardinalDirection, inverseBearing),
        ],
      ),
    );
  }

  void _showStalkingGuideDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: widget.theme.accentColor),
            const SizedBox(width: 8),
            const Text('Stalking Guide'),
          ],
        ),
        content: const Text(
          'Keep the orange wind vector arrow pointing down/away from your phone\'s heading indicator needle to stay downwind of your quarry.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompassDial(ThemeController theme) {
    return SizedBox(
      width: 200,
      height: 200,
      child: CustomPaint(painter: _CompassDialPainter(theme: theme)),
    );
  }

  Widget _buildWindVectorArrow(ThemeController theme, double windBearing) {
    return Transform.rotate(
      angle: (windBearing - 90) * math.pi / 180,
      child: Container(
        width: 200,
        height: 200,
        alignment: Alignment.center,
        child: Icon(
          Icons.arrow_forward_rounded,
          color: Colors.orange.withValues(alpha: 0.8),
          size: 40,
        ),
      ),
    );
  }

  Widget _buildDeviceHeadingIndicator(ThemeController theme) {
    final heading = _compassHeading ?? 0.0;
    return Transform.rotate(
      angle: heading * math.pi / 180,
      child: Container(
        width: 200,
        height: 200,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.navigation_rounded, color: theme.accentColor, size: 32),
            const SizedBox(height: 4),
            Transform.rotate(
              angle: -heading * math.pi / 180,
              child: Text(
                '${heading.toStringAsFixed(0)}°',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStalkPromptBadge(
    ThemeController theme,
    String cardinalDirection,
    double inverseBearing,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Optimal Stalk Path: Approach from $cardinalDirection (${inverseBearing.toStringAsFixed(0)}°) to keep your scent hidden.',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCardinalDirection(double degrees) {
    final normalized = (degrees % 360 + 360) % 360;
    const directions = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSW',
      'SW',
      'WSW',
      'W',
      'WNW',
      'NW',
      'NNW',
    ];
    final index = ((normalized + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }
}

class _CompassDialPainter extends CustomPainter {
  final ThemeController theme;

  _CompassDialPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final dialPaint = Paint()
      ..color = theme.textColor.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final tickPaint = Paint()
      ..color = theme.textColor.withAlpha(60)
      ..strokeWidth = 2;

    final cardinalPaint = Paint()
      ..color = theme.accentColor
      ..strokeWidth = 3;

    final northPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4;

    canvas.drawCircle(center, radius, dialPaint);

    for (int i = 0; i < 360; i += 30) {
      final angle = (i - 90) * math.pi / 180;
      final isNorth = i == 0;
      final isCardinal = i % 90 == 0;
      final tickLength = isNorth ? 20.0 : (isCardinal ? 15.0 : 8.0);
      final paint = isNorth
          ? northPaint
          : (isCardinal ? cardinalPaint : tickPaint);

      final start = Offset(
        center.dx + (radius - tickLength) * math.cos(angle),
        center.dy + (radius - tickLength) * math.sin(angle),
      );
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      canvas.drawLine(start, end, paint);
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    const directions = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < directions.length; i++) {
      final isNorth = i == 0;
      final angle = (i * 90 - 90) * math.pi / 180;
      final labelRadius = radius - 28;
      final x = center.dx + labelRadius * math.cos(angle);
      final y = center.dy + labelRadius * math.sin(angle);

      textPainter.text = TextSpan(
        text: directions[i],
        style: TextStyle(
          color: isNorth ? Colors.red : theme.accentColor,
          fontSize: isNorth ? 20 : 16,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    textPainter.text = TextSpan(
      text: '0°',
      style: TextStyle(
        color: Colors.red.withAlpha(180),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
    textPainter.layout();
    final northAngle = (-90) * math.pi / 180;
    final degreeRadius = radius - 42;
    final degreeX = center.dx + degreeRadius * math.cos(northAngle);
    final degreeY = center.dy + degreeRadius * math.sin(northAngle);
    textPainter.paint(
      canvas,
      Offset(degreeX - textPainter.width / 2, degreeY - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_CompassDialPainter oldDelegate) {
    return false;
  }
}
