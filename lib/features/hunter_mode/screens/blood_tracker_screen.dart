import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../services/offline_sync_queue.dart';
import '../services/map_path_tracer.dart';
import '../widgets/vital_zone_painter.dart';

class BloodTrackerScreen extends StatefulWidget {
  final ThemeController theme;

  const BloodTrackerScreen({super.key, required this.theme});

  @override
  State<BloodTrackerScreen> createState() => _BloodTrackerScreenState();
}

class _BloodTrackerScreenState extends State<BloodTrackerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isTorchOn = false;
  bool _isNightVisionActive = false;
  bool _isThermalModeActive = false;
  bool _isDroppingPin = false;
  bool _showMapView = false;
  FlashMode _flashMode = FlashMode.off;

  // GPS waypoint tracking
  final List<Map<String, dynamic>> _waypoints = [];
  double _totalDistance = 0;

  // Vital zone anatomy overlay state
  String _selectedSpecies = 'None'; // Options: None, Kudu, Impala, Warthog
  String _currentStanceAngle =
      'Broadside'; // Options: Broadside, Quartering-Towards, Quartering-Away
  double _anatomyScale = 1.0;
  Offset _anatomyOffset = Offset.zero;

  // High-contrast Ironbow pseudo-thermal color filter matrix
  // Maps luminance deltas to hot reds/oranges while crushing greens and lifting cold shadows to deep blue
  final List<double> _thermalMatrix = <double>[
    -1.0, 2.0, 2.0, 0.0, -50.0, // R channel: aggressive luminance amplification
    2.0, -1.0, 0.0, 0.0, -100.0, // G channel: crushes foliage wavelengths
    0.0, 0.0, 3.0, 0.0, 100.0, // B channel: lifts cold shadows to blue/indigo
    0.0, 0.0, 0.0, 1.0, 0.0, // Alpha: transparency stability
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _showErrorSnackBar('No cameras available on this device');
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Camera initialization failed: $e');
      debugPrint('Camera initialization error: $e');
    }
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      _isTorchOn = !_isTorchOn;
      _flashMode = _isTorchOn ? FlashMode.torch : FlashMode.off;
      await _cameraController!.setFlashMode(_flashMode);

      if (mounted) {
        setState(() {});
        _showToast(
          _isTorchOn ? '🔦 Torch activated' : '🔦 Torch deactivated',
          _isTorchOn ? Colors.amber : Colors.grey,
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to toggle torch: $e');
      debugPrint('Torch toggle error: $e');
    }
  }

  void _toggleNightVision() {
    setState(() {
      // Thermal mode overrides night vision - deactivate thermal when switching to night vision
      if (_isThermalModeActive) {
        _isThermalModeActive = false;
      }
      _isNightVisionActive = !_isNightVisionActive;
    });
    _showToast(
      _isNightVisionActive
          ? '🌙 Night Vision ON - Green phosphor mode'
          : '☀️ Day Vision ON - Normal mode',
      _isNightVisionActive ? Colors.green : Colors.red,
    );
  }

  Future<void> _dropBloodPin() async {
    if (_isDroppingPin) return;

    setState(() {
      _isDroppingPin = true;
    });

    try {
      // Get current GPS position
      final position = await _getCurrentPosition();
      if (position == null) {
        _showErrorSnackBar('Could not acquire GPS position');
        setState(() {
          _isDroppingPin = false;
        });
        return;
      }

      // Calculate distance from last waypoint
      double distanceFromLast = 0;
      if (_waypoints.isNotEmpty) {
        final lastLat = _waypoints.last['lat'] as double;
        final lastLon = _waypoints.last['lon'] as double;
        distanceFromLast = _calculateDistance(
          lastLat,
          lastLon,
          position.latitude,
          position.longitude,
        );
        _totalDistance += distanceFromLast;
      }

      // Create waypoint entry
      final waypoint = {
        'lat': position.latitude,
        'lon': position.longitude,
        'timestamp': DateTime.now(),
        'number': _waypoints.length + 1,
        'distanceFromLast': distanceFromLast,
      };

      _waypoints.add(waypoint);

      // Enqueue waypoint to OfflineSyncQueue
      await OfflineSyncQueue.instance.enqueueAction('waypoints', 'CREATE', {
        'name': 'Blood Spoor',
        'type': 'Blood Trail',
        'lat': position.latitude,
        'lon': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Also append to MapPathTracer for drawing the animal's escape route
      MapPathTracer.instance.appendBloodDropNode(
        position.latitude,
        position.longitude,
      );

      if (mounted) {
        setState(() {});
        _showToast(
          '🩸 WP#${waypoint['number']} | ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} | +${distanceFromLast.toStringAsFixed(0)}m',
          const Color(0xFFFF6B00),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to drop blood pin: $e');
      debugPrint('Blood pin error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDroppingPin = false;
        });
      }
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const Distance distance = Distance();
    return distance.as(
      LengthUnit.Meter,
      LatLng(lat1, lon1),
      LatLng(lat2, lon2),
    );
  }

  void _showMapFullScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => _BloodTrailMapScreen(
              waypoints: _waypoints,
              totalDistance: _totalDistance,
              theme: widget.theme,
            ),
      ),
    );
  }

  void _exportGpsData() {
    if (_waypoints.isEmpty) {
      _showErrorSnackBar('No waypoints to export');
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Blood Trail GPS Export');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total Distance: ${_totalDistance.toStringAsFixed(0)}m');
    buffer.writeln('Total Waypoints: ${_waypoints.length}');
    buffer.writeln('');
    buffer.writeln(
      'Waypoint,Latitude,Longitude,Distance from Last (m),Timestamp',
    );

    for (int i = 0; i < _waypoints.length; i++) {
      final wp = _waypoints[i];
      buffer.writeln(
        '${wp['number']},${wp['lat']},${wp['lon']},${(wp['distanceFromLast'] as double).toStringAsFixed(1)},${wp['timestamp']}',
      );
    }

    _showGpsExportDialog(buffer.toString());
  }

  void _showGpsExportDialog(String gpsData) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              '📍 GPS Export',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_waypoints.length} waypoints | ${_totalDistance.toStringAsFixed(0)}m total',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      gpsData,
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
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

  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('GPS timeout'),
      );
    } catch (e) {
      debugPrint('GPS error: $e');
      return null;
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showToast(String message, Color backgroundColor) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera viewport layer
          _buildCameraViewport(),

          // Vital zone anatomy overlay (pinch to scale, drag to move)
          if (_selectedSpecies != 'None')
            Positioned.fill(
              child: GestureDetector(
                onScaleUpdate: (ScaleUpdateDetails details) {
                  setState(() {
                    _anatomyScale = (details.scale * _anatomyScale).clamp(
                      0.5,
                      3.0,
                    );
                    _anatomyOffset += details.focalPointDelta;
                  });
                },
                onDoubleTap: () {
                  setState(() {
                    _anatomyScale = 1.0;
                    _anatomyOffset = Offset.zero;
                  });
                },
                child: CustomPaint(
                  painter: VitalZonePainter(
                    species: _selectedSpecies,
                    scale: _anatomyScale,
                    offset: _anatomyOffset,
                    stanceAngle: _currentStanceAngle,
                  ),
                  child: Container(),
                ),
              ),
            ),

          // Red color isolation overlay
          _buildColorIsolationOverlay(),

          // HUD status bar at top
          _buildTopStatusBar(theme),

          // Tactical radar HUD controls
          _buildHudDashboard(theme),

          // Anatomy selection toolbar
          _buildAnatomySelectionToolbar(theme),

          // Crosshair reticle
          _buildCrosshairReticle(),
        ],
      ),
    );
  }

  Widget _buildCameraViewport() {
    if (!_isInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned.fill(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize?.height ?? 1,
          height: _cameraController!.value.previewSize?.width ?? 1,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  Widget _buildColorIsolationOverlay() {
    // Color matrix that boosts red tones and desaturates other colors
    // This enhances blood trail visibility against green/brown backgrounds
    const redIsolationMatrix = <double>[
      // Red channel - enhance red, reduce green/blue contribution
      1.5, -0.2, -0.1, 0, 0,
      // Green channel - desaturate green
      -0.1, 0.3, 0.1, 0, 0,
      // Blue channel - reduce blue contribution
      -0.2, 0.1, 0.2, 0, 0,
      // Alpha channel
      0, 0, 0, 1, 0,
    ];

    // Night vision green phosphor monochrome matrix
    // Amplifies all luminance but maps it to green channel for night viewing
    const nightVisionMatrix = <double>[
      // Red channel - convert to green luminance
      0.3, 0.59, 0.11, 0, 0,
      // Green channel - boost green significantly
      0.2, 0.8, 0.1, 0, 0,
      // Blue channel - minimal blue contribution
      0.1, 0.3, 0.4, 0, 0,
      // Alpha channel
      0, 0, 0, 1, 0,
    ];

    // Determine which matrix to use: Thermal overrides Night Vision
    List<double> colorMatrix;
    if (_isThermalModeActive) {
      // Ironbow pseudo-thermal palette: hot reds/oranges, crushed greens, deep blue cold shadows
      colorMatrix = _thermalMatrix;
    } else if (_isNightVisionActive) {
      colorMatrix = nightVisionMatrix;
    } else {
      colorMatrix = redIsolationMatrix;
    }

    return Positioned.fill(
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(colorMatrix),
        child: Container(),
      ),
    );
  }

  Widget _buildTopStatusBar(ThemeController theme) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Title
            Row(
              children: [
                const Icon(
                  Icons.visibility_rounded,
                  color: Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '🩸 BLOOD TRAIL TRACKER',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            // GPS status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gps_fixed, color: Colors.green, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'GPS',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudDashboard(ThemeController theme) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 24,
      left: 8,
      right: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Torch toggle button
          _buildHudButton(
            icon: _isTorchOn ? Icons.flashlight_on : Icons.flashlight_off,
            label: _isTorchOn ? 'ON' : 'OFF',
            backgroundColor:
                _isTorchOn
                    ? Colors.amber.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.6),
            iconColor: _isTorchOn ? Colors.amber : Colors.white70,
            onTap: _toggleTorch,
          ),

          // Night Vision toggle button
          _buildHudButton(
            icon:
                _isNightVisionActive ? Icons.nightlight_round : Icons.wb_sunny,
            label: _isNightVisionActive ? 'NV' : 'DAY',
            backgroundColor:
                _isNightVisionActive
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.6),
            iconColor: _isNightVisionActive ? Colors.green : Colors.white70,
            onTap: _toggleNightVision,
          ),

          // Blood drop pin button
          _buildBloodPinButton(theme),

          // Map View button
          _buildHudButton(
            icon: Icons.map,
            label: '${_waypoints.length} WP',
            backgroundColor:
                _showMapView
                    ? Colors.blue.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.6),
            iconColor: _showMapView ? Colors.lightBlueAccent : Colors.white70,
            onTap: _showMapFullScreen,
          ),

          // Export GPS button
          _buildHudButton(
            icon: Icons.download,
            label:
                _totalDistance > 0
                    ? '${_totalDistance.toStringAsFixed(0)}m'
                    : 'GPS',
            backgroundColor:
                _totalDistance > 0
                    ? Colors.green.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.6),
            iconColor:
                _totalDistance > 0 ? Colors.lightGreenAccent : Colors.white70,
            onTap: _exportGpsData,
          ),
        ],
      ),
    );
  }

  Widget _buildHudButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBloodPinButton(ThemeController theme) {
    return GestureDetector(
      onTap: _dropBloodPin,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8C00), Color(0xFFFF6B00)],
          ),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.amber.withValues(alpha: 0.6),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B00).withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child:
            _isDroppingPin
                ? const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                )
                : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.bloodtype_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'PIN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildCrosshairReticle() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Center dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                // Cardinal crosshair lines
                Positioned(
                  top: 0,
                  child: Container(
                    width: 1,
                    height: 20,
                    color: Colors.red.withValues(alpha: 0.6),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 1,
                    height: 20,
                    color: Colors.red.withValues(alpha: 0.6),
                  ),
                ),
                Positioned(
                  left: 0,
                  child: Container(
                    width: 20,
                    height: 1,
                    color: Colors.red.withValues(alpha: 0.6),
                  ),
                ),
                Positioned(
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 1,
                    color: Colors.red.withValues(alpha: 0.6),
                  ),
                ),
                // Corner brackets
                ..._buildCornerBrackets(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCornerBrackets() {
    const bracketLength = 16.0;
    const bracketWidth = 2.0;
    const color = Colors.red;

    return [
      // Top-left bracket
      Positioned(
        top: 25,
        left: 25,
        child: Column(
          children: [
            Container(width: bracketLength, height: bracketWidth, color: color),
            Container(width: bracketWidth, height: bracketLength, color: color),
          ],
        ),
      ),
      // Top-right bracket
      Positioned(
        top: 25,
        right: 25,
        child: Column(
          children: [
            Container(width: bracketLength, height: bracketWidth, color: color),
            Container(width: bracketWidth, height: bracketLength, color: color),
          ],
        ),
      ),
      // Bottom-left bracket
      Positioned(
        bottom: 25,
        left: 25,
        child: Column(
          children: [
            Container(width: bracketWidth, height: bracketLength, color: color),
            Container(width: bracketLength, height: bracketWidth, color: color),
          ],
        ),
      ),
      // Bottom-right bracket
      Positioned(
        bottom: 25,
        right: 25,
        child: Column(
          children: [
            Container(width: bracketWidth, height: bracketLength, color: color),
            Container(width: bracketLength, height: bracketWidth, color: color),
          ],
        ),
      ),
    ];
  }

  /// Anatomy species and stance selection toolbar for vital zone overlays
  Widget _buildAnatomySelectionToolbar(ThemeController theme) {
    return Positioned(
      bottom: 160,
      left: 0,
      right: 0,
      child: Column(
        children: [
          // Stance angle selector row
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.cyan.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Broadside button
                _buildStanceButton(
                  label: 'BROADSIDE (0°)',
                  icon: '🏹',
                  isSelected: _currentStanceAngle == 'Broadside',
                  onTap: () => _setCurrentStanceAngle('Broadside'),
                ),
                // Quartering Towards button
                _buildStanceButton(
                  label: 'TOWARDS (+30°)',
                  icon: '🏹',
                  isSelected: _currentStanceAngle == 'Quartering-Towards',
                  onTap: () => _setCurrentStanceAngle('Quartering-Towards'),
                ),
                // Quartering Away button
                _buildStanceButton(
                  label: 'AWAY (-30°)',
                  icon: '🏹',
                  isSelected: _currentStanceAngle == 'Quartering-Away',
                  onTap: () => _setCurrentStanceAngle('Quartering-Away'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Species selector row
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Kudu button
                _buildAnatomyButton(
                  label: 'KUDU',
                  icon: '🦌',
                  isSelected: _selectedSpecies == 'Kudu',
                  onTap: () => _selectSpecies('Kudu'),
                ),
                // Impala button
                _buildAnatomyButton(
                  label: 'IMPALA',
                  icon: '🦌',
                  isSelected: _selectedSpecies == 'Impala',
                  onTap: () => _selectSpecies('Impala'),
                ),
                // Warthog button
                _buildAnatomyButton(
                  label: 'WARTHOG',
                  icon: '🐗',
                  isSelected: _selectedSpecies == 'Warthog',
                  onTap: () => _selectSpecies('Warthog'),
                ),
                // Hide button
                _buildAnatomyButton(
                  label: 'HIDE',
                  icon: '🚫',
                  isSelected: _selectedSpecies == 'None',
                  onTap: () => _selectSpecies('None'),
                  isRed: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStanceButton({
    required String label,
    required String icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Colors.cyan.withValues(alpha: 0.3)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.cyan : Colors.white38,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.cyan : Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnatomyButton({
    required String label,
    required String icon,
    required bool isSelected,
    required VoidCallback onTap,
    bool isRed = false,
  }) {
    final activeColor = isRed ? Colors.red : Colors.orange;
    final inactiveColor = Colors.white54;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? activeColor.withValues(alpha: 0.3)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : inactiveColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectSpecies(String species) {
    setState(() {
      _selectedSpecies = species;
      // Reset scale and offset when switching species
      _anatomyScale = 1.0;
      _anatomyOffset = Offset.zero;
    });

    if (species == 'None') {
      _showToast('Vital zone overlay hidden', Colors.grey);
    } else {
      _showToast('🦌 $species vital zone overlay active', Colors.orange);
    }
  }

  void _setCurrentStanceAngle(String angle) {
    setState(() {
      _currentStanceAngle = angle;
    });
  }
}

/// Full-screen map view for blood trail visualization
class _BloodTrailMapScreen extends StatefulWidget {
  final List<Map<String, dynamic>> waypoints;
  final double totalDistance;
  final ThemeController theme;

  const _BloodTrailMapScreen({
    required this.waypoints,
    required this.totalDistance,
    required this.theme,
  });

  @override
  State<_BloodTrailMapScreen> createState() => _BloodTrailMapScreenState();
}

class _BloodTrailMapScreenState extends State<_BloodTrailMapScreen> {
  final MapController _mapController = MapController();
  double _currentZoom = 17.0;

  @override
  Widget build(BuildContext context) {
    final center =
        widget.waypoints.isNotEmpty
            ? LatLng(
              widget.waypoints.first['lat'] as double,
              widget.waypoints.first['lon'] as double,
            )
            : const LatLng(-25.7479, 25.4833); // Center of South Africa

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '🩸 Blood Trail Map',
          style: TextStyle(color: widget.theme.accentColor),
        ),
        iconTheme: IconThemeData(color: widget.theme.accentColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.orange),
            onPressed: _centerOnTrail,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatChip('📍', '${widget.waypoints.length}', 'Waypoints'),
                _buildStatChip(
                  '📏',
                  '${widget.totalDistance.toStringAsFixed(0)}m',
                  'Distance',
                ),
                _buildStatChip(
                  '🩸',
                  '${widget.waypoints.length}',
                  'Blood Spots',
                ),
              ],
            ),
          ),
          // Map
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _currentZoom,
                minZoom: 5,
                maxZoom: 19,
                onPositionChanged: (position, hasGesture) {
                  _currentZoom = position.zoom;
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.jagspoor.app',
                ),
                // Blood trail polyline
                if (widget.waypoints.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points:
                            widget.waypoints
                                .map(
                                  (wp) => LatLng(
                                    wp['lat'] as double,
                                    wp['lon'] as double,
                                  ),
                                )
                                .toList(),
                        strokeWidth: 4,
                        color: Colors.red,
                        borderColor: Colors.red[800]!,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                // Waypoint markers
                MarkerLayer(
                  markers:
                      widget.waypoints.map((wp) {
                        final number = wp['number'] as int;
                        final distance = wp['distanceFromLast'] as double;
                        return Marker(
                          point: LatLng(
                            wp['lat'] as double,
                            wp['lon'] as double,
                          ),
                          width: 50,
                          height: 60,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color:
                                      number == 1 ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '$number',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (number > 1)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '+${distance.toStringAsFixed(0)}m',
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
          // Waypoint list
          if (widget.waypoints.isNotEmpty)
            Container(
              height: 150,
              color: Colors.grey[900],
              child: ListView.builder(
                itemCount: widget.waypoints.length,
                itemBuilder: (context, index) {
                  final wp = widget.waypoints[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: index == 0 ? Colors.green : Colors.red,
                      child: Text(
                        '${wp['number']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      '${(wp['lat'] as double).toStringAsFixed(6)}, ${(wp['lon'] as double).toStringAsFixed(6)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    subtitle: Text(
                      index > 0
                          ? '+${(wp['distanceFromLast'] as double).toStringAsFixed(0)}m from last'
                          : 'Start point',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.near_me,
                        color: Colors.orange,
                        size: 18,
                      ),
                      onPressed: () => _navigateToWaypoint(wp),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String icon, String value, String label) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  void _centerOnTrail() {
    if (widget.waypoints.isEmpty) return;

    final center = LatLng(
      widget.waypoints.first['lat'] as double,
      widget.waypoints.first['lon'] as double,
    );

    _mapController.move(center, _currentZoom);
  }

  void _navigateToWaypoint(Map<String, dynamic> wp) {
    _mapController.move(LatLng(wp['lat'] as double, wp['lon'] as double), 18);
  }
}
