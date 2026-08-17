import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/measurement_formatter.dart';
import '../../../core/widgets/copyright_footer.dart';
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  // True when there is no network connectivity (zero-signal bushveld).
  bool _isOffline = false;
  // Target bearing (direction to the quarry) used for crosswind assessment.
  // When [_trackHeadingForTarget] is true this is ignored in favour of the
  // live device heading.
  double _targetBearing = 0.0;
  bool _trackHeadingForTarget = true;

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
  static const String _prefSunrise = 'cached_sunrise';
  static const String _prefSunset = 'cached_sunset';
  static const String _prefMoonPhase = 'cached_moon_phase';

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
    // Monitor connectivity so we can fall back to cached data when offline.
    Connectivity().checkConnectivity().then(_onConnectivityChanged);
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (mounted && offline != _isOffline) {
      setState(() {
        _isOffline = offline;
        // When going offline, surface a graceful fallback message instead of a
        // hard error — the last cached reading remains visible.
        if (offline && _weather != null) {
          _failureMessage = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
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
    final sunriseStr = prefs.getString(_prefSunrise);
    final sunsetStr = prefs.getString(_prefSunset);
    final moonFraction = prefs.getDouble(_prefMoonPhase);

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
          sunrise: _tryParseDateTime(sunriseStr),
          sunset: _tryParseDateTime(sunsetStr),
          moonPhaseFraction: moonFraction ?? 0.0,
          moonPhaseName: moonFraction == null
              ? 'New Moon'
              : WeatherModel.moonPhaseNameFor(moonFraction),
        );
      });
    }
  }

  static DateTime? _tryParseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  /// "HH:mm" of the last cached weather fetch, for the offline badge.
  String? get _cachedUpdatedTime => _weather == null
      ? null
      : '${_weather!.fetchedAt.toLocal().hour.toString().padLeft(2, '0')}:'
          '${_weather!.fetchedAt.toLocal().minute.toString().padLeft(2, '0')}';

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
    // Solar + lunar cache (offline fallback for the bushveld).
    if (weather.sunrise != null) {
      await prefs.setString(_prefSunrise, weather.sunrise!.toIso8601String());
    }
    if (weather.sunset != null) {
      await prefs.setString(_prefSunset, weather.sunset!.toIso8601String());
    }
    await prefs.setDouble(_prefMoonPhase, weather.moonPhaseFraction);
  }

  Future<void> _updateCurrentWeather() async {
    if (_isLoading) return;

    // Offline (zero-signal bushveld): fall back seamlessly to the last cached
    // reading rather than attempting a doomed network round-trip.
    if (_isOffline) {
      if (mounted) {
        setState(() {
          _failureMessage = _weather == null
              ? 'No connectivity — and no cached weather yet. Reconnect to fetch.'
              : null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _weather == null
                  ? 'Offline — no cached weather available.'
                  : 'Offline — showing last cached weather reading '
                      '(${_cachedUpdatedTime ?? 'unknown'}).',
            ),
            backgroundColor:
                _weather == null ? Colors.redAccent : Colors.orange,
          ),
        );
      }
      return;
    }

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
          // When a fetch fails but cached data exists, fall back gracefully
          // rather than masking the reading with a hard error.
          if (_weather != null) {
            _failureMessage =
                'Live fetch failed — showing last cached reading. ($error)';
          } else {
            _failureMessage = error.toString();
          }
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
                        if (_isOffline) _buildOfflineBadge(theme),
                        _buildStatusCard(theme),
                        const SizedBox(height: 20),
                        _buildUpdateButton(theme),
                        const SizedBox(height: 24),
                        _buildWeatherMetricsGrid(theme),
                        const SizedBox(height: 24),
                        _buildSolarLunarCard(theme),
                        const SizedBox(height: 24),
                        _buildWindSummaryCard(theme),
                        const SizedBox(height: 24),
                        _buildCompassCard(theme),
                        if (_failureMessage != null) ...[
                          const SizedBox(height: 24),
                          _buildErrorCard(theme, _failureMessage!),
                        ],
                        const CopyrightFooter(),
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

  Widget _buildOfflineBadge(ThemeController theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _weather == null
                  ? 'Offline — no cached data yet'
                  : 'Offline / Cached Data (Last updated: $_cachedUpdatedTime)',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSolarLunarCard(ThemeController theme) {
    final sunrise = _weather?.sunriseText ?? '—';
    final sunset = _weather?.sunsetText ?? '—';
    final moonName = _weather?.moonPhaseName ?? '—';
    final moonPct = _weather?.moonIlluminationPercent;

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
          Row(
            children: [
              Icon(Icons.wb_sunny_rounded, color: theme.accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'SOLAR & LUNAR FORECAST',
                style: TextStyle(
                  color: theme.textColor.withAlpha(180),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  theme: theme,
                  label: 'SUNRISE',
                  value: sunrise,
                  icon: Icons.wb_twilight_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  theme: theme,
                  label: 'SUNSET',
                  value: sunset,
                  icon: Icons.nights_stay_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.nightlight_rounded,
                    color: theme.accentColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        moonName,
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        moonPct == null
                            ? 'Illumination unavailable'
                            : '$moonPct% illuminated',
                        style: TextStyle(
                          color: theme.textColor.withAlpha(140),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (moonPct != null)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      value: (moonPct / 100).clamp(0.0, 1.0),
                      strokeWidth: 3,
                      backgroundColor:
                          theme.textColor.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(theme.accentColor),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeController theme) {
    final locationText =
        _cachedLocationText ??
        (_currentPosition != null
            ? 'Lat ${_currentPosition!.latitude.toStringAsFixed(5)}, Lon ${_currentPosition!.longitude.toStringAsFixed(5)}'
            : 'Press update to fetch hunter location.');
    final updatedText =
        _weather != null
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
    final temperature =
        _weather != null
            ? MeasurementFormatter.instance
                .formatTemperature(_weather!.temperatureC)
            : MeasurementFormatter.instance.formatTemperature(null);
    final humidity =
        _weather != null
            ? '${_weather!.humidityPercent.toStringAsFixed(0)}%'
            : '--%';
    final pressure =
        _weather != null
            ? '${_weather!.surfacePressureHpa.toStringAsFixed(0)} hPa'
            : '-- hPa';
    final windValue =
        _weather != null
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
    final text =
        _weather != null
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
    final windSpeed = _weather?.windSpeedKmh ?? 0.0;
    final heading = _compassHeading ?? 0.0;
    final targetBearing = _trackHeadingForTarget ? heading : _targetBearing;
    final windToward = (windBearing + 180) % 360;
    final crosswind =
        _computeCrosswind(windBearing, targetBearing, windSpeed);

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
                'TACTICAL COMPASS ROSE',
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
          const SizedBox(height: 10),
          // Live numeric heading + wind-from readouts.
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _headingChip(
                theme,
                label: 'HEADING',
                value:
                    '${heading.toStringAsFixed(0)}° ${_getCardinalDirection(heading)}',
                color: theme.accentColor,
              ),
              _headingChip(
                theme,
                label: 'WIND FROM',
                value:
                    '${windBearing.toStringAsFixed(0)}° ${_getCardinalDirection(windBearing)}',
                color: Colors.orange,
              ),
              _headingChip(
                theme,
                label: 'TARGET',
                value:
                    '${targetBearing.toStringAsFixed(0)}° ${_getCardinalDirection(targetBearing)}',
                color: Colors.amber,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 264,
            height: 264,
            child: CustomPaint(
              painter: _TacticalCompassPainter(
                theme: theme,
                windBearing: windBearing,
                windSpeed: windSpeed,
                targetBearing: targetBearing,
                heading: heading,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildTargetBearingControl(theme, heading),
          const SizedBox(height: 16),
          _buildCrosswindPanel(
            theme,
            crosswind: crosswind,
            targetBearing: targetBearing,
            windBearing: windBearing,
            windToward: windToward,
            windSpeed: windSpeed,
          ),
          const SizedBox(height: 16),
          _buildStalkPromptBadge(
            theme,
            _getCardinalDirection(windToward),
            windToward,
          ),
        ],
      ),
    );
  }

  Widget _headingChip(
    ThemeController theme, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(120), width: 1),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
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
          'WEATHER & WIND HUD LOGISTICS: Utilizes your phone\'s internal hardware barometric sensor and magnetometer to determine off-grid stalking profiles. Scent Cone Vectors display local drift direction. Cross-reference your micro-climate readouts to remain downwind of plains game during close-range approaches.\n\nThe compass rose shows explicit numeric headings (0°–360°) with cardinal markers. The orange arrow is the wind-flow vector (direction the wind is blowing TOWARD). The amber reticle is your target bearing; the gold needle is your live device heading. The crosswind panel reports the wind component perpendicular to your shot line — the value that drifts your bullet.',
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

  /// Target-bearing control: a toggle to track the live device heading, or a
  /// slider to dial in a fixed target bearing manually.
  Widget _buildTargetBearingControl(ThemeController theme, double heading) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withAlpha(90), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed, color: Colors.amber.shade300, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TARGET BEARING',
                  style: TextStyle(
                    color: theme.textColor.withAlpha(180),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Switch(
                value: _trackHeadingForTarget,
                activeColor: Colors.amber,
                onChanged: (v) => setState(() => _trackHeadingForTarget = v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _trackHeadingForTarget
                ? 'Tracking live device heading (${heading.toStringAsFixed(0)}°).'
                : 'Manual: ${_targetBearing.toStringAsFixed(0)}° ${_getCardinalDirection(_targetBearing)}.',
            style: TextStyle(color: theme.textColor, fontSize: 12),
          ),
          if (!_trackHeadingForTarget) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _targetBearing,
                    min: 0,
                    max: 359,
                    divisions: 359,
                    activeColor: Colors.amber,
                    label: '${_targetBearing.toStringAsFixed(0)}°',
                    onChanged: (v) => setState(() => _targetBearing = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Sync to current heading',
                  icon: Icon(Icons.sync, color: theme.accentColor, size: 20),
                  onPressed: () => setState(() {
                    _targetBearing = heading.roundToDouble();
                  }),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Crosswind alignment panel: reports the wind component perpendicular to the
  /// shot line (the value that drifts the bullet), colour-coded by severity.
  Widget _buildCrosswindPanel(
    ThemeController theme, {
    required _Crosswind crosswind,
    required double targetBearing,
    required double windBearing,
    required double windToward,
    required double windSpeed,
  }) {
    final severity = crosswind.severity;
    final color = severity == _CrosswindSeverity.low
        ? Colors.green
        : severity == _CrosswindSeverity.moderate
            ? Colors.orange
            : Colors.redAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(120), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                'CROSSWIND ALIGNMENT',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (windSpeed <= 0)
            Text(
              'No wind data — awaiting location update.',
              style: TextStyle(color: theme.textColor.withAlpha(160), fontSize: 12),
            )
          else ...[
            _crosswindRow(
              theme,
              label: 'Shot line',
              value:
                  '${targetBearing.toStringAsFixed(0)}° ${_getCardinalDirection(targetBearing)}',
            ),
            _crosswindRow(
              theme,
              label: 'Wind flow toward',
              value:
                  '${windToward.toStringAsFixed(0)}° ${_getCardinalDirection(windToward)}',
            ),
            _crosswindRow(
              theme,
              label: 'Wind from (rel. target)',
              value:
                  '${crosswind.fromRelativeAbs.toStringAsFixed(0)}° ${crosswind.fromSide}',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _crosswindRow(
                    theme,
                    label: 'Crosswind',
                    value:
                        '${crosswind.componentKmh.toStringAsFixed(1)} km/h (${(crosswind.fraction * 100).toStringAsFixed(0)}%)',
                    emphasize: true,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    crosswind.driftLeft
                        ? Icons.arrow_back_rounded
                        : Icons.arrow_forward_rounded,
                    color: color,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      crosswind.fraction < 0.15
                          ? 'Near head/tail wind — minimal lateral drift.'
                          : 'Wind from your ${crosswind.fromSide} → drift ${crosswind.driftLeft ? 'LEFT' : 'RIGHT'}.',
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _crosswindRow(
    ThemeController theme, {
    required String label,
    required String value,
    bool emphasize = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.textColor.withAlpha(150),
              fontSize: emphasize ? 12 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? theme.textColor,
              fontSize: emphasize ? 13 : 12,
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
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

  /// Computes the crosswind component perpendicular to the shot line.
  /// [windBearing] is the meteorological wind-FROM bearing; [targetBearing]
  /// is the direction to the target (shot line). Returns the relative wind
  /// angle, the lateral fraction (|sin|), the crosswind speed, and the drift
  /// direction (wind from hunter's left pushes the bullet right, and vice
  /// versa).
  _Crosswind _computeCrosswind(
    double windBearing,
    double targetBearing,
    double windSpeed,
  ) {
    // Wind-FROM bearing relative to the shot line, normalised to [-180, 180].
    final fromRelative =
        ((windBearing - targetBearing + 540) % 360) - 180;
    final fromRelativeAbs = fromRelative.abs();
    final fraction = (math.sin(fromRelative * math.pi / 180)).abs();
    final componentKmh = windSpeed * fraction;

    // Wind from the hunter's RIGHT (positive relative) drifts the bullet LEFT.
    final driftLeft = fromRelative > 0;
    final fromSide = driftLeft ? 'RIGHT' : 'LEFT';

    final severity = fraction < 0.25
        ? _CrosswindSeverity.low
        : fraction < 0.75
            ? _CrosswindSeverity.moderate
            : _CrosswindSeverity.high;

    return _Crosswind(
      fromRelativeAbs: fromRelativeAbs,
      fraction: fraction,
      componentKmh: componentKmh,
      driftLeft: driftLeft,
      fromSide: fromSide,
      severity: severity,
    );
  }
}

/// Crosswind solution for the shot line vs. wind vector.
class _Crosswind {
  final double fromRelativeAbs;
  final double fraction;
  final double componentKmh;
  final bool driftLeft;
  final String fromSide;
  final _CrosswindSeverity severity;

  const _Crosswind({
    required this.fromRelativeAbs,
    required this.fraction,
    required this.componentKmh,
    required this.driftLeft,
    required this.fromSide,
    required this.severity,
  });
}

enum _CrosswindSeverity { low, moderate, high }

/// High-precision tactical compass rose. Renders:
/// - A fixed bearing rose with 8 cardinal/intercardinal labels (N, NE, E, SE,
///   S, SW, W, NW) and numeric degree headings every 30° (0–330), plus minor
///   ticks every 15°.
/// - The live device-heading needle (gold).
/// - The target-bearing reticle + shot line (amber, dashed).
/// - The wind-flow vector arrow (orange→red by speed) showing the direction
///   the wind is blowing TOWARD, with a FROM tick.
class _TacticalCompassPainter extends CustomPainter {
  final ThemeController theme;
  final double windBearing;
  final double windSpeed;
  final double targetBearing;
  final double heading;

  _TacticalCompassPainter({
    required this.theme,
    required this.windBearing,
    required this.windSpeed,
    required this.targetBearing,
    required this.heading,
  });

  static const _cardinals = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  double _degToRad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 14;

    // Outer bezel rings.
    final bezelPaint = Paint()
      ..color = theme.textColor.withAlpha(28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, bezelPaint);
    canvas.drawCircle(center, radius - 6, Paint()..color = theme.textColor.withAlpha(12));

    // Tick marks: minor every 15°, major every 30°.
    final minorTick = Paint()
      ..color = theme.textColor.withAlpha(50)
      ..strokeWidth = 1;
    final majorTick = Paint()
      ..color = theme.textColor.withAlpha(110)
      ..strokeWidth = 1.6;

    for (int d = 0; d < 360; d += 15) {
      final angle = _degToRad(d - 90);
      final isMajor = d % 30 == 0;
      final len = isMajor ? 10.0 : 5.0;
      final paint = isMajor ? majorTick : minorTick;
      final start = Offset(
        center.dx + (radius - len) * math.cos(angle),
        center.dy + (radius - len) * math.sin(angle),
      );
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(start, end, paint);
    }

    // Cardinal labels (outer) + numeric degree headings every 30° (inner).
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < _cardinals.length; i++) {
      final deg = i * 45;
      final isNorth = i == 0;
      final angle = _degToRad(deg - 90);
      final labelR = radius - 22;
      final x = center.dx + labelR * math.cos(angle);
      final y = center.dy + labelR * math.sin(angle);
      tp.text = TextSpan(
        text: _cardinals[i],
        style: TextStyle(
          color: isNorth ? Colors.red : theme.accentColor,
          fontSize: isNorth ? 16 : 12,
          fontWeight: FontWeight.w900,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    for (int d = 0; d < 360; d += 30) {
      // Skip positions already carrying a cardinal letter.
      if (d % 45 == 0) continue;
      final angle = _degToRad(d - 90);
      final r = radius - 22;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      tp.text = TextSpan(
        text: '$d°',
        style: TextStyle(
          color: theme.textColor.withAlpha(150),
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    // ---- Target bearing: dashed shot line + reticle (amber) ----
    final targetAngle = _degToRad(targetBearing - 90);
    final targetEdge = Offset(
      center.dx + (radius - 8) * math.cos(targetAngle),
      center.dy + (radius - 8) * math.sin(targetAngle),
    );
    _drawDashedLine(canvas, center, targetEdge, Colors.amber, 2, 6, 4);
    // Reticle ring + cross at the target edge.
    final reticlePaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(targetEdge, 7, reticlePaint);
    canvas.drawLine(
      Offset(targetEdge.dx - 10, targetEdge.dy),
      Offset(targetEdge.dx + 10, targetEdge.dy),
      reticlePaint,
    );
    canvas.drawLine(
      Offset(targetEdge.dx, targetEdge.dy - 10),
      Offset(targetEdge.dx, targetEdge.dy + 10),
      reticlePaint,
    );

    // ---- Wind-flow vector (orange→red by speed) ----
    // WindDirectionDegrees is the FROM bearing; flow is toward FROM+180.
    final windToward = (windBearing + 180) % 360;
    final windAngle = _degToRad(windToward - 90);
    final windLen = (radius - 26);
    final windTip = Offset(
      center.dx + windLen * math.cos(windAngle),
      center.dy + windLen * math.sin(windAngle),
    );
    final windColor = _windColor(windSpeed);
    final windPaint = Paint()
      ..color = windColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, windTip, windPaint);
    _drawArrowHead(canvas, windTip, windAngle, 12, windColor);
    // Small FROM tick on the rim opposite the flow.
    final fromAngle = _degToRad(windBearing - 90);
    final fromTick = Paint()
      ..color = windColor.withAlpha(160)
      ..strokeWidth = 3;
    final fStart = Offset(
      center.dx + (radius - 4) * math.cos(fromAngle),
      center.dy + (radius - 4) * math.sin(fromAngle),
    );
    final fEnd = Offset(
      center.dx + radius * math.cos(fromAngle),
      center.dy + radius * math.sin(fromAngle),
    );
    canvas.drawLine(fStart, fEnd, fromTick);

    // ---- Device heading needle (gold) ----
    final headAngle = _degToRad(heading - 90);
    final headTip = Offset(
      center.dx + (radius - 30) * math.cos(headAngle),
      center.dy + (radius - 30) * math.sin(headAngle),
    );
    final headPaint = Paint()
      ..color = theme.accentColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, headTip, headPaint);
    _drawArrowHead(canvas, headTip, headAngle, 9, theme.accentColor);

    // Center hub.
    canvas.drawCircle(
      center,
      5,
      Paint()..color = theme.textColor.withAlpha(120),
    );
    canvas.drawCircle(center, 2, Paint()..color = theme.backgroundColor);
  }

  Color _windColor(double speed) {
    if (speed >= 25) return Colors.redAccent;
    if (speed >= 15) return Colors.deepOrange;
    return Colors.orange;
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset tip,
    double angle,
    double size,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - size * math.cos(angle - 0.4),
        tip.dy - size * math.sin(angle - 0.4),
      )
      ..lineTo(
        tip.dx - size * 0.5 * math.cos(angle),
        tip.dy - size * 0.5 * math.sin(angle),
      )
      ..lineTo(
        tip.dx - size * math.cos(angle + 0.4),
        tip.dy - size * math.sin(angle + 0.4),
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
    double dash,
    double gap,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final total = math.sqrt(dx * dx + dy * dy);
    final step = dash + gap;
    final ux = dx / total;
    final uy = dy / total;
    double dist = 0;
    while (dist < total) {
      final d0 = dist;
      final d1 = math.min(dist + dash, total);
      canvas.drawLine(
        Offset(start.dx + ux * d0, start.dy + uy * d0),
        Offset(start.dx + ux * d1, start.dy + uy * d1),
        paint,
      );
      dist += step;
    }
  }

  @override
  bool shouldRepaint(_TacticalCompassPainter oldDelegate) {
    return oldDelegate.windBearing != windBearing ||
        oldDelegate.windSpeed != windSpeed ||
        oldDelegate.targetBearing != targetBearing ||
        oldDelegate.heading != heading;
  }
}
