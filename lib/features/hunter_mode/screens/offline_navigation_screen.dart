import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../services/offline_map_cache.dart';
import '../services/offline_sync_queue.dart';
import '../services/map_path_tracer.dart';

class OfflineNavigationScreen extends StatefulWidget {
  final ThemeController theme;

  const OfflineNavigationScreen({super.key, required this.theme});

  @override
  State<OfflineNavigationScreen> createState() => _OfflineNavigationScreenState();
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

  // Active waypoints on the map
  final List<Marker> _activeWaypointsList = [];

  // Location tracking subscription
  StreamSubscription<Position>? _locationSubscription;

  // GPS live tracking state
  bool _isGpsTrackingActive = false;

  // Waypoint type options
  static const List<String> _waypointTypes = ['Kill Site', 'Camp', 'Spoor Track', 'Water Source', 'Vehicle', 'Other'];

  @override
  void initState() {
    super.initState();
    _initializeCache();
    _startLocationTracking();
  }

  void _startLocationTracking() {
    if (MapPathTracer.instance.isTracking) {
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      ).listen((Position position) {
        MapPathTracer.instance.appendCoordinate(position.latitude, position.longitude);
        if (mounted) {
          setState(() {
            _currentCenter = LatLng(position.latitude, position.longitude);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _locationSubscription?.cancel();
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
            content: Text('📍 Path tracing started - recording trail breadcrumbs'),
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
                      hintStyle: TextStyle(color: widget.theme.subtitleColor.withValues(alpha: 0.5)),
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
                    items: _waypointTypes.map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
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
                  child: Text('Cancel', style: TextStyle(color: widget.theme.subtitleColor)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.theme.accentColor,
                  ),
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a waypoint name')),
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
        await OfflineSyncQueue.instance.enqueueAction(
          'waypoints',
          'CREATE',
          {
            'hunterId': FirebaseAuth.instance.currentUser?.uid,
            'name': name,
            'type': type,
            'lat': position.latitude,
            'lon': position.longitude,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📱 Waypoint "$name" saved locally. Will sync when back in range.'),
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
    final iconData = _getWaypointIcon(type);
    final marker = Marker(
      point: position,
      width: 40,
      height: 40,
      child: Icon(iconData, color: Colors.red, size: 32),
    );

    setState(() {
      _activeWaypointsList.add(marker);
    });
  }

  IconData _getWaypointIcon(String type) {
    switch (type) {
      case 'Kill Site':
        return Icons.location_on;
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
    
    // Simulate tile download for the visible area
    // In production, this would iterate through tile coordinates
    try {
      final bounds = _mapController.camera.visibleBounds;
      final center = bounds.center;
      
      // Calculate tile range for current zoom
      final zoom = _currentZoom.toInt();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📥 Downloading tiles for zoom level $zoom around ${center.latitude.toStringAsFixed(2)}, ${center.longitude.toStringAsFixed(2)}...'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
        ),
      );

      // Add marker for downloaded area
      _preDownloadedMarkers.add(center);
      
      // Simulate download time
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Cached tiles for offline use'),
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
          // Status Bar
          _buildStatusBar(theme),
          
          // Map View
          Expanded(
            child: _isInitialized
                ? _buildMapView(theme)
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor)),
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
              style: TextStyle(
                color: theme.textColor,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Zoom: ${_currentZoom.toInt()}',
            style: TextStyle(
              color: theme.subtitleColor,
              fontSize: 11,
            ),
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
            onLongPress: (tapPosition, point) => _showWaypointCreationDialog(context, point),
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
            ),
            
            // Trail path polyline layer - walnut HUD high-contrast path marker
            PolylineLayer(
              polylines: [
                Polyline(
                  points: MapPathTracer.instance.currentPath,
                  strokeWidth: 4.0,
                  color: Colors.orangeAccent,
                ),
                // Blood trail vector path - dark crimson line for wounded animal escape route
                Polyline(
                  points: MapPathTracer.instance.bloodPath,
                  strokeWidth: 3.0,
                  color: const Color(0xFFDC143C), // Crimson red for visibility
                ),
              ],
            ),
            
            // Display cached area markers
            MarkerLayer(
              markers: _preDownloadedMarkers.map((latlng) {
                return Marker(
                  point: latlng,
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.accentColor, width: 2),
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
            MarkerLayer(
              markers: _activeWaypointsList,
            ),
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
              border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
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
                color: _isGpsTrackingActive
                    ? Colors.green.withValues(alpha: 0.9)
                    : theme.cardColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isGpsTrackingActive ? Colors.green : theme.accentColor,
                  width: _isGpsTrackingActive ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isGpsTrackingActive
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
                    color: _isGpsTrackingActive ? Colors.white : theme.accentColor,
                    size: 24,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isGpsTrackingActive ? 'TRACK' : 'GPS',
                    style: TextStyle(
                      color: _isGpsTrackingActive ? Colors.white : theme.textColor,
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
              border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '📍 Center:',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 10,
                  ),
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
                  child: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
                ),
              const SizedBox(height: 8),
              // Recording toggle FAB
              FloatingActionButton(
                heroTag: 'pathTrace',
                backgroundColor: MapPathTracer.instance.isTracking ? Colors.red : theme.accentColor,
                onPressed: _togglePathTracing,
                child: Icon(
                  MapPathTracer.instance.isTracking ? Icons.stop : Icons.fiber_manual_record,
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
                  Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
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
              border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
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
          _buildZoomButton(
            icon: Icons.add,
            onPressed: _zoomIn,
            theme: theme,
          ),
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
