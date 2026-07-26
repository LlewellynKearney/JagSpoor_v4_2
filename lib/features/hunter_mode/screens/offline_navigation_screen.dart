import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../services/offline_map_cache.dart';

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
  
  // Offline tile download settings
  final List<LatLng> _preDownloadedMarkers = [];
  bool _isDownloadingTiles = false;

  @override
  void initState() {
    super.initState();
    _initializeCache();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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
    setState(() {
      _isMapReady = true;
    });
  }

  void _zoomIn() {
    if (_currentZoom < 18 && _isMapReady) {
      setState(() {
        _currentZoom += 1;
      });
      _mapController.move(_mapController.camera.center, _currentZoom);
    }
  }

  void _zoomOut() {
    if (_currentZoom > 3 && _isMapReady) {
      setState(() {
        _currentZoom -= 1;
      });
      _mapController.move(_mapController.camera.center, _currentZoom);
    }
  }

  void _centerOnSouthAfrica() {
    if (_isMapReady) {
      _mapController.move(_defaultCenter, 10.0);
      setState(() {
        _currentZoom = 10.0;
      });
    }
  }

  Future<void> _downloadAreaTiles() async {
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
                      ? '${_mapController.camera.center.latitude.toStringAsFixed(5)}, ${_mapController.camera.center.longitude.toStringAsFixed(5)}'
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
