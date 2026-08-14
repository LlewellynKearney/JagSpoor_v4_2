import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../../../core/theme/app_theme.dart';
import '../services/offline_map_cache.dart';
import '../services/offline_sync_queue.dart';
import '../services/map_path_tracer.dart';
import '../services/battery_saver_manager.dart';
import '../services/chat_and_filter_service.dart';
import '../services/advanced_tactical_service.dart';

class OfflineNavigationScreen extends StatefulWidget {
  final ThemeController theme;

  const OfflineNavigationScreen({super.key, required this.theme});

  @override
  State<OfflineNavigationScreen> createState() =>
      _OfflineNavigationScreenState();
}

class _OfflineNavigationScreenState extends State<OfflineNavigationScreen> {
  final OfflineMapCache _offlineMapCache = OfflineMapCache();
  final MapController _mapController = MapController();

  bool _isInitialized = false;
  bool _showOfflineWarning = false;
  bool _isMapReady = false;

  // Default center (South Africa - Kruger National Park area)
  static const LatLng _defaultCenter = LatLng(-24.5, 31.5);
  double _currentZoom = 10.0;
  LatLng _currentCenter = _defaultCenter;

  // Offline tile download settings
  final List<LatLng> _preDownloadedMarkers = [];
  bool _isDownloadingTiles = false;

  // Active waypoints on the map (with type metadata)
  final List<Map<String, dynamic>> _waypointsData = [];
  List<Marker> get _activeWaypointsList =>
      _buildMarkersForFilter(_selectedWaypointFilter);

  // Location tracking subscription
  StreamSubscription<Position>? _locationSubscription;

  // Adaptive battery throttle state — tracks the most recent fix + when the
  // user last moved beyond the stationary threshold, so the Geolocator stream
  // can be dynamically swapped between the active and stationary presets.
  Position? _lastPosition;
  DateTime? _lastMovementAt;
  bool _isMoving = true;
  bool _batterySaverOn = false;

  // GPS live tracking state
  bool _isGpsTrackingActive = false;

  // Compass heading from flutter_compass
  double _currentHeading = 0.0;
  StreamSubscription<CompassEvent>? _compassSubscription;

  // BLE Rangefinder state
  bool _isRangefinderConnected = false;
  bool _isSimulatingRangefinder = false;

  // Waypoint type options
  static const List<String> _waypointTypes = [
    'Kill Site',
    'Camp',
    'Spoor Track',
    'Water Source',
    'Vehicle',
    'Rangefinder Target',
    'Other',
  ];

  // Waypoint filter options for toolbar (includes Rangefinder Target)
  static const List<String> _waypointFilterOptions = [
    'All',
    'Kill Site',
    'Blood Spoor',
    'Water Hole',
    'Camp',
    'Rangefinder Target',
  ];
  String _selectedWaypointFilter = 'All';

  // Advanced Filter State
  bool _showAdvancedFilters = false;

  // Time Range Filter (hours: 0=24h, 1=48h, 2=Unlimited)
  double _timeRangeFilter = 2.0;
  static const List<String> _timeRangeLabels = [
    '24 Hours',
    '48 Hours',
    'All Time',
  ];

  // Radius Filter (km: 0=1km, 1=5km, 2=10km, 3=Unlimited)
  double _radiusFilter = 3.0;
  static const List<String> _radiusLabels = [
    '1 km',
    '5 km',
    '10 km',
    'Unlimited',
  ];

  List<Marker> _buildMarkersForFilter(String filter) {
    // Get filtered waypoints based on advanced filters
    List<Map<String, dynamic>> filteredWaypoints = _applyAdvancedFilters(
      _waypointsData,
    );

    if (filter == 'All') {
      return filteredWaypoints.map((w) => _buildMarkerFromData(w)).toList();
    }
    return filteredWaypoints
        .where((w) => w['type'] == filter)
        .map((w) => _buildMarkerFromData(w))
        .toList();
  }

  List<Map<String, dynamic>> _applyAdvancedFilters(
    List<Map<String, dynamic>> waypoints,
  ) {
    return waypoints.where((waypoint) {
      // Skip if no position data
      if (!waypoint.containsKey('position') || waypoint['position'] == null) {
        return true; // Keep waypoints without position
      }

      final position = waypoint['position'] as LatLng;
      final createdAtMillis = waypoint['createdAtMillis'] as int? ?? 0;

      // Apply time filter
      int hoursFilter;
      if (_timeRangeFilter < 0.5) {
        hoursFilter = 24;
      } else if (_timeRangeFilter < 1.5) {
        hoursFilter = 48;
      } else {
        hoursFilter = 999999; // Unlimited
      }

      final passesTimeFilter = ChatAndFilterService.instance
          .isTimestampWithinHours(
            documentTimestampMillis: createdAtMillis,
            maxHoursFilter: hoursFilter,
          );

      // Apply radius filter
      double maxRadiusKm;
      if (_radiusFilter < 0.5) {
        maxRadiusKm = 1.0;
      } else if (_radiusFilter < 1.5) {
        maxRadiusKm = 5.0;
      } else if (_radiusFilter < 2.5) {
        maxRadiusKm = 10.0;
      } else {
        maxRadiusKm = double.infinity; // Unlimited
      }

      final passesRadiusFilter =
          maxRadiusKm == double.infinity ||
          ChatAndFilterService.instance.isCoordinateWithinRadius(
            centerLat: _currentCenter.latitude,
            centerLon: _currentCenter.longitude,
            targetLat: position.latitude,
            targetLon: position.longitude,
            maxRadiusKm: maxRadiusKm,
          );

      return passesTimeFilter && passesRadiusFilter;
    }).toList();
  }

  Marker _buildMarkerFromData(Map<String, dynamic> data) {
    final type = data['type'] as String;
    final color = _getWaypointColor(type);
    return Marker(
      point: data['position'] as LatLng,
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => _showWaypointDetails(data),
        child: Container(
          decoration: BoxDecoration(
            color: color.withAlpha(200),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 4),
            ],
          ),
          child: Icon(_getWaypointIcon(type), color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Color _getWaypointColor(String type) {
    switch (type) {
      case 'Kill Site':
        return Colors.red;
      case 'Blood Spoor':
        return Colors.deepOrange;
      case 'Water Hole':
        return Colors.blue;
      case 'Camp':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeCache();
    _initBatterySaverThenStartTracking();
    _startCompassTracking();
  }

  /// Loads the persisted battery-saver toggle, then starts the location stream
  /// with the matching preset. The toggle is read once at start; per-fix
  /// motion state then drives the active↔stationary swap.
  Future<void> _initBatterySaverThenStartTracking() async {
    _batterySaverOn = await BatterySaverManager().isBatterySaverEnabled();
    if (mounted) _startLocationTracking();
  }

  void _startLocationTracking() {
    if (!MapPathTracer.instance.isTracking) return;

    final settings = BatterySaverManager.resolveTrackingSettings(
      batterySaverOn: _batterySaverOn,
      moving: _isMoving,
    );
    _locationSubscription?.cancel();
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((Position position) {
      MapPathTracer.instance.appendCoordinate(
        position.latitude,
        position.longitude,
      );

      // Adaptive throttle: compare this fix to the previous one; if the user
      // has been stationary for the window, downgrade to the coarse preset,
      // and restore the high-frequency preset once they move again.
      final now = DateTime.now();
      final moved = BatterySaverManager.isMoving(_lastPosition, position);
      if (moved) {
        _lastMovementAt = now;
        _isMoving = true;
      } else {
        final last = _lastMovementAt ?? now;
        if (now.difference(last).inSeconds >=
            BatterySaverManager.stationaryWindowSeconds) {
          _isMoving = false;
        }
      }
      _lastPosition = position;

      // If the resolved preset differs from the one currently streaming,
      // restart the stream on the new preset (throttle up on movement, down
      // on stationary). Skipped while battery saver is forced on (already
      // on the stationary preset).
      if (!_batterySaverOn) {
        final desired = BatterySaverManager.resolveTrackingSettings(
          batterySaverOn: false,
          moving: _isMoving,
        );
        if (desired.accuracy != settings.accuracy ||
            desired.distanceFilter != settings.distanceFilter) {
          _startLocationTracking();
          return; // this fix is consumed by the restarted stream's first emit
        }
      }

      if (mounted) {
        setState(() {
          _currentCenter = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  void _startCompassTracking() {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted && event.heading != null) {
        setState(() {
          _currentHeading = event.heading!;
        });
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _locationSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  void _togglePathTracing() {
    final tracer = MapPathTracer.instance;
    if (tracer.isTracking) {
      tracer.stopPathTracing();
      _locationSubscription?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🛑 Path tracing stopped'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      tracer.startNewPathTracing();
      _startLocationTracking();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '📍 Path tracing started - recording trail breadcrumbs',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    setState(() {});
  }

  void _clearRecordedPath() {
    MapPathTracer.instance.clearRecordedPath();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🗑️ Trail path cleared'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Simulates a rangefinder trigger event for testing BLE rangefinder integration.
  /// Captures current location and heading, projects target coordinates,
  /// and adds a 'Rangefinder Target' waypoint to the map and sync queue.
  Future<void> _simulateRangefinderTrigger() async {
    setState(() {
      _isSimulatingRangefinder = true;
    });

    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Simulate a random distance between 50-500 yards for testing
      final simulatedDistance =
          50.0 + (DateTime.now().millisecond % 450).toDouble();

      // Project target coordinates using the tactical service
      final projectedCoords = AdvancedTacticalService.instance
          .projectTargetCoordinates(
            startLat: position.latitude,
            startLon: position.longitude,
            bearingDegrees: _currentHeading,
            distanceYards: simulatedDistance,
          );

      // Add as rangefinder target waypoint
      await _addRangefinderTarget(
        targetLat: projectedCoords['lat']!,
        targetLon: projectedCoords['lon']!,
        distanceYards: simulatedDistance,
        bearingDegrees: _currentHeading,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎯 Rangefinder target projected: ${simulatedDistance.toStringAsFixed(0)}y @ ${_currentHeading.toStringAsFixed(0)}°',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Rangefinder error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSimulatingRangefinder = false;
      });
    }
  }

  /// Adds a rangefinder target waypoint to the map and syncs to offline queue.
  Future<void> _addRangefinderTarget({
    required double targetLat,
    required double targetLon,
    required double distanceYards,
    required double bearingDegrees,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final waypointId = 'rf_${timestamp}_$userId';

    final waypointData = {
      'id': waypointId,
      'position': LatLng(targetLat, targetLon),
      'type': 'Rangefinder Target',
      'hunterId': userId,
      'createdAtMillis': timestamp,
      'distanceYards': distanceYards,
      'bearingDegrees': bearingDegrees,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Add to local map markers
    _waypointsData.add(waypointData as Map<String, dynamic>);

    // Sync to offline queue for later cloud sync
    await OfflineSyncQueue.instance.enqueueAction('waypoints', 'create', {
      'documentId': waypointId,
      'hunterId': userId,
      'position': {'lat': targetLat, 'lon': targetLon},
      'type': 'Rangefinder Target',
      'createdAtMillis': timestamp,
      'distanceYards': distanceYards,
      'bearingDegrees': bearingDegrees,
    });

    setState(() {});
  }

  Future<void> _initializeCache() async {
    try {
      await _offlineMapCache.initializeCache();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing map cache: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _showOfflineWarning = true;
        });
      }
    }
  }

  void _onMapReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isMapReady = true;
        _currentCenter = _defaultCenter;
      });
    });
  }

  void _zoomIn() {
    if (_currentZoom < 18 && _isMapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentZoom += 1;
          });
          _mapController.move(_currentCenter, _currentZoom);
        }
      });
    }
  }

  void _zoomOut() {
    if (_currentZoom > 3 && _isMapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentZoom -= 1;
          });
          _mapController.move(_currentCenter, _currentZoom);
        }
      });
    }
  }

  void _centerOnSouthAfrica() {
    if (_isMapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentZoom = 10.0;
            _currentCenter = _defaultCenter;
          });
          _mapController.move(_defaultCenter, 10.0);
        }
      });
    }
  }

  Future<void> _centerOnMyLocation() async {
    try {
      // Check if GPS tracking is already active - toggle it off
      if (_isGpsTrackingActive) {
        _locationSubscription?.cancel();
        setState(() {
          _isGpsTrackingActive = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🛰️ GPS tracking deactivated'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Get current GPS position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('GPS timeout'),
      );

      // Auto-start movement tracking
      MapPathTracer.instance.startNewPathTracing();

      // Center map on user position
      final userLatLng = LatLng(position.latitude, position.longitude);
      _mapController.move(userLatLng, 16.0);

      setState(() {
        _currentCenter = userLatLng;
        _currentZoom = 16.0;
        _isGpsTrackingActive = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Centered on location - GPS tracking active'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Start live GPS stream for auto-centering
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((Position pos) {
        if (!mounted) return;
        setState(() {
          final newPos = LatLng(pos.latitude, pos.longitude);
          MapPathTracer.instance.appendCoordinate(pos.latitude, pos.longitude);
          _currentCenter = newPos;
          _mapController.move(newPos, _mapController.camera.zoom);
        });
      });
    } catch (e) {
      debugPrint('GPS error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ GPS error: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showWaypointCreationDialog(BuildContext context, LatLng position) {
    final titleController = TextEditingController();
    String selectedType = 'Kill Site';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: widget.theme.cardColor,
              title: Text(
                '📍 Drop Waypoint',
                style: TextStyle(color: widget.theme.textColor),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    style: TextStyle(color: widget.theme.textColor),
                    decoration: InputDecoration(
                      labelText: 'Waypoint Name',
                      labelStyle: TextStyle(color: widget.theme.subtitleColor),
                      hintText: 'e.g. Large Kudu Spoor',
                      hintStyle: TextStyle(
                        color: widget.theme.subtitleColor.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Waypoint Type',
                      labelStyle: TextStyle(color: widget.theme.subtitleColor),
                    ),
                    dropdownColor: widget.theme.cardColor,
                    style: TextStyle(color: widget.theme.textColor),
                    items:
                        _waypointTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '📍 ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      color: widget.theme.subtitleColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: widget.theme.subtitleColor),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.theme.accentColor,
                  ),
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a waypoint name'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext);
                    await _saveWaypoint(
                      titleController.text.trim(),
                      selectedType,
                      position,
                    );
                  },
                  child: const Text('Save Waypoint'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveWaypoint(String name, String type, LatLng position) async {
    try {
      // Live Firestore write attempt
      await FirebaseFirestore.instance.collection('waypoints').add({
        'hunterId': FirebaseAuth.instance.currentUser?.uid,
        'name': name,
        'type': type,
        'lat': position.latitude,
        'lon': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Waypoint "$name" saved to cloud!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Network link dropped - fall back to offline sync queue instantly
      try {
        await OfflineSyncQueue.instance.enqueueAction('waypoints', 'CREATE', {
          'hunterId': FirebaseAuth.instance.currentUser?.uid,
          'name': name,
          'type': type,
          'lat': position.latitude,
          'lon': position.longitude,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '📱 Waypoint "$name" saved locally. Will sync when back in range.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }

        // Add to local map markers
        _addWaypointMarker(name, type, position);
      } catch (queueError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error saving waypoint: $queueError'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _addWaypointMarker(String name, String type, LatLng position) {
    final waypointData = {
      'name': name,
      'type': type,
      'position': position,
      'timestamp': DateTime.now(),
    };

    setState(() {
      _waypointsData.add(waypointData);
    });
  }

  void _showWaypointDetails(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(data['name'] ?? 'Waypoint'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type: ${data['type']}'),
                Text(
                  'Position: ${(data['position'] as LatLng).latitude.toStringAsFixed(5)}, ${(data['position'] as LatLng).longitude.toStringAsFixed(5)}',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  IconData _getWaypointIcon(String type) {
    switch (type) {
      case 'Kill Site':
        return Icons.whatshot;
      case 'Camp':
        return Icons.cabin;
      case 'Spoor Track':
        return Icons.directions_walk;
      case 'Water Source':
        return Icons.water_drop;
      case 'Vehicle':
        return Icons.directions_car;
      default:
        return Icons.push_pin;
    }
  }

  Future<void> _downloadAreaTiles() async {
    if (!_isMapReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Map is still loading...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isDownloadingTiles = true);

    try {
      final bounds = _mapController.camera.visibleBounds;
      final center = bounds.center;

      // Pre-download every tile covering the visible bounds at the current zoom
      // (plus one level above/below for a usable offline zoom range) into the
      // on-disk cache. This replaces the prior simulated download — tiles are
      // now genuinely persisted under map_tiles_cache/{z}/{x}/{y}.png and are
      // served from disk by [CacheFileTileProvider] when signal drops to 0.
      final zoom = _currentZoom.round().clamp(3, 17);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '📥 Downloading topo tiles for zoom $zoom around '
            '${center.latitude.toStringAsFixed(2)}, '
            '${center.longitude.toStringAsFixed(2)}...',
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );

      final written = await _offlineMapCache.downloadTileRange(
        minLat: bounds.south,
        minLng: bounds.west,
        maxLat: bounds.north,
        maxLng: bounds.east,
        zoom: zoom,
        extraZoomLevels: 1,
      );

      // Record the cached area so the "downloaded" marker renders on the map.
      _preDownloadedMarkers.add(center);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              written > 0
                  ? '✅ Cached $written topo tiles for offline use'
                  : '✅ Area already cached for offline use',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error caching tiles: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingTiles = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          '🗺️ OFF-GRID TOPOGRAPHIC MAP',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.my_location, color: theme.accentColor),
            onPressed: _centerOnSouthAfrica,
            tooltip: 'Center on South Africa',
          ),
          IconButton(
            icon: Icon(Icons.download_rounded, color: theme.accentColor),
            onPressed: _isDownloadingTiles ? null : _downloadAreaTiles,
            tooltip: 'Cache visible area for offline',
          ),
        ],
      ),
      body: Column(
        children: [
          // Waypoint Filter Toolbar
          _buildWaypointFilterToolbar(theme),

          // Status Bar
          _buildStatusBar(theme),

          // Map View
          Expanded(
            child:
                _isInitialized
                    ? _buildMapView(theme)
                    : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.accentColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Initializing offline cache...',
                            style: TextStyle(color: theme.textColor),
                          ),
                        ],
                      ),
                    ),
          ),

          // Zoom Controls
          _buildZoomControls(theme),
        ],
      ),
    );
  }

  Widget _buildWaypointFilterToolbar(ThemeController theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Filter Chips Row
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(
                color: theme.accentColor.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              // Category Filter Chips
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        _waypointFilterOptions.map((filter) {
                          final isSelected = _selectedWaypointFilter == filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                filter,
                                style: TextStyle(
                                  color:
                                      isSelected
                                          ? Colors.white
                                          : theme.textColor,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedWaypointFilter = filter;
                                });
                              },
                              backgroundColor: theme.backgroundColor,
                              selectedColor: _getFilterChipColor(filter, theme),
                              checkmarkColor: Colors.white,
                              side: BorderSide(
                                color:
                                    isSelected
                                        ? _getFilterChipColor(filter, theme)
                                        : theme.accentColor.withValues(
                                          alpha: 0.3,
                                        ),
                              ),
                              avatar: Icon(
                                _getFilterChipIcon(filter),
                                size: 16,
                                color:
                                    isSelected
                                        ? Colors.white
                                        : theme.accentColor,
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ),
              // Advanced Filter Toggle Button
              Container(
                decoration: BoxDecoration(
                  color:
                      _showAdvancedFilters
                          ? theme.accentColor.withValues(alpha: 0.2)
                          : theme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        _showAdvancedFilters
                            ? theme.accentColor
                            : theme.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _showAdvancedFilters = !_showAdvancedFilters;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune,
                          size: 18,
                          color:
                              _showAdvancedFilters
                                  ? theme.accentColor
                                  : theme.textColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Filters',
                          style: TextStyle(
                            color:
                                _showAdvancedFilters
                                    ? theme.accentColor
                                    : theme.textColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Advanced Filter Panel (Slider)
        if (_showAdvancedFilters) _buildAdvancedFilterPanel(theme),
      ],
    );
  }

  Widget _buildAdvancedFilterPanel(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time Range Slider
          Row(
            children: [
              Icon(Icons.access_time, color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Time Range:',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _timeRangeLabels[_timeRangeFilter.round().clamp(0, 2)],
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _timeRangeFilter,
            min: 0,
            max: 2,
            divisions: 2,
            activeColor: theme.accentColor,
            inactiveColor: theme.accentColor.withValues(alpha: 0.3),
            onChanged: (value) {
              setState(() {
                _timeRangeFilter = value;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children:
                _timeRangeLabels.map((label) {
                  return Text(
                    label,
                    style: TextStyle(color: theme.subtitleColor, fontSize: 10),
                  );
                }).toList(),
          ),

          const SizedBox(height: 16),

          // Radius Range Slider
          Row(
            children: [
              Icon(Icons.radar, color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Distance:',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _radiusLabels[_radiusFilter.round().clamp(0, 3)],
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _radiusFilter,
            min: 0,
            max: 3,
            divisions: 3,
            activeColor: theme.accentColor,
            inactiveColor: theme.accentColor.withValues(alpha: 0.3),
            onChanged: (value) {
              setState(() {
                _radiusFilter = value;
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children:
                _radiusLabels.map((label) {
                  return Text(
                    label,
                    style: TextStyle(color: theme.subtitleColor, fontSize: 10),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Color _getFilterChipColor(String filter, ThemeController theme) {
    switch (filter) {
      case 'Kill Site':
        return Colors.red;
      case 'Blood Spoor':
        return Colors.deepOrange;
      case 'Water Hole':
        return Colors.blue;
      case 'Camp':
        return Colors.green;
      default:
        return theme.accentColor;
    }
  }

  IconData _getFilterChipIcon(String filter) {
    switch (filter) {
      case 'Kill Site':
        return Icons.whatshot;
      case 'Blood Spoor':
        return Icons.bloodtype;
      case 'Water Hole':
        return Icons.water_drop;
      case 'Camp':
        return Icons.cabin;
      default:
        return Icons.location_on;
    }
  }

  Widget _buildStatusBar(ThemeController theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.cardColor,
      child: Row(
        children: [
          Icon(
            _showOfflineWarning ? Icons.cloud_off : Icons.cloud_done,
            size: 16,
            color: _showOfflineWarning ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _showOfflineWarning
                  ? '⚠️ Cache unavailable - using online tiles'
                  : '📦 Offline mode: Using cached tiles when available',
              style: TextStyle(color: theme.textColor, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Zoom: ${_currentZoom.toInt()}',
            style: TextStyle(color: theme.subtitleColor, fontSize: 11),
          ),
          const SizedBox(width: 8),
          if (_preDownloadedMarkers.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_preDownloadedMarkers.length} areas cached',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapView(ThemeController theme) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: _currentZoom,
            minZoom: 3,
            maxZoom: 18,
            onMapReady: _onMapReady,
            onLongPress:
                (tapPosition, point) =>
                    _showWaypointCreationDialog(context, point),
            onPositionChanged: (position, hasGesture) {
              if (hasGesture && mounted) {
                setState(() {
                  _currentZoom = position.zoom;
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.jagspoor.app',
              fallbackUrl: 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
              maxZoom: 18,
              // Serve topo tiles from the on-disk cache when offline; download +
              // persist on miss when online. See [CacheFileTileProvider].
              tileProvider: CacheFileTileProvider(cache: _offlineMapCache),
            ),

            // Trail path polyline layer - walnut HUD high-contrast path marker
            PolylineLayer(
              polylines: [
                Polyline(
                  points: MapPathTracer.instance.currentPath,
                  strokeWidth: 4.0,
                  color: Colors.orangeAccent,
                ),
              ],
            ),

            // Display cached area markers
            MarkerLayer(
              markers:
                  _preDownloadedMarkers.map((latlng) {
                    return Marker(
                      point: latlng,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.accentColor.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.accentColor,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.download_done,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    );
                  }).toList(),
            ),

            // Active user waypoint markers
            MarkerLayer(markers: _activeWaypointsList),
          ],
        ),

        // Compass Overlay
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.cardColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.navigation, color: theme.accentColor, size: 24),
                const SizedBox(height: 4),
                Text(
                  'N',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Center on My Location & GPS Track Button
        Positioned(
          top: 16,
          right: 70,
          child: GestureDetector(
            onTap: _centerOnMyLocation,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    _isGpsTrackingActive
                        ? Colors.green.withValues(alpha: 0.9)
                        : theme.cardColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      _isGpsTrackingActive ? Colors.green : theme.accentColor,
                  width: _isGpsTrackingActive ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        _isGpsTrackingActive
                            ? Colors.green.withValues(alpha: 0.4)
                            : Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.my_location,
                    color:
                        _isGpsTrackingActive ? Colors.white : theme.accentColor,
                    size: 24,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isGpsTrackingActive ? 'TRACK' : 'GPS',
                    style: TextStyle(
                      color:
                          _isGpsTrackingActive ? Colors.white : theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bluetooth Rangefinder Sync Button
        Positioned(
          top: 16,
          right: 134,
          child: GestureDetector(
            onTap:
                _isSimulatingRangefinder ? null : _simulateRangefinderTrigger,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    _isRangefinderConnected
                        ? Colors.blue.withValues(alpha: 0.9)
                        : theme.cardColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      _isRangefinderConnected ? Colors.blue : theme.accentColor,
                  width: _isRangefinderConnected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        _isRangefinderConnected
                            ? Colors.blue.withValues(alpha: 0.4)
                            : Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child:
                  _isSimulatingRangefinder
                      ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.accentColor,
                        ),
                      )
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bluetooth_searching,
                            color:
                                _isRangefinderConnected
                                    ? Colors.white
                                    : theme.accentColor,
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'RF',
                            style: TextStyle(
                              color:
                                  _isRangefinderConnected
                                      ? Colors.white
                                      : theme.textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),

        // Coordinates Display
        Positioned(
          bottom: 80,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '📍 Center:',
                  style: TextStyle(color: theme.subtitleColor, fontSize: 10),
                ),
                Text(
                  _isMapReady
                      ? '${_currentCenter.latitude.toStringAsFixed(5)}, ${_currentCenter.longitude.toStringAsFixed(5)}'
                      : 'Loading...',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Path Tracing Toggle FAB
        Positioned(
          bottom: 140,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Clear path button
              if (MapPathTracer.instance.currentPath.isNotEmpty)
                FloatingActionButton.small(
                  heroTag: 'clearPath',
                  backgroundColor: theme.cardColor,
                  onPressed: _clearRecordedPath,
                  child: Icon(
                    Icons.delete_outline,
                    color: Colors.red.shade400,
                    size: 20,
                  ),
                ),
              const SizedBox(height: 8),
              // Recording toggle FAB
              FloatingActionButton(
                heroTag: 'pathTrace',
                backgroundColor:
                    MapPathTracer.instance.isTracking
                        ? Colors.red
                        : theme.accentColor,
                onPressed: _togglePathTracing,
                child: Icon(
                  MapPathTracer.instance.isTracking
                      ? Icons.stop
                      : Icons.fiber_manual_record,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Tracking indicator
        if (MapPathTracer.instance.isTracking)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    color: Colors.white,
                    size: 12,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'RECORDING',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildZoomControls(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.cardColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Zoom Out Button
          _buildZoomButton(
            icon: Icons.remove,
            onPressed: _zoomOut,
            theme: theme,
          ),
          const SizedBox(width: 24),

          // Zoom Level Indicator
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'ZOOM',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '${_currentZoom.toInt()}',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),

          // Zoom In Button
          _buildZoomButton(icon: Icons.add, onPressed: _zoomIn, theme: theme),
        ],
      ),
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onPressed,
    required ThemeController theme,
  }) {
    return Material(
      color: theme.accentColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.black, size: 24),
        ),
      ),
    );
  }
}
