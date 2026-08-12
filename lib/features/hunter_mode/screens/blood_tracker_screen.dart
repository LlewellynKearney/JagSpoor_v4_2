import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:jagspoor/core/widgets/contextual_info_icon.dart';
import '../../../core/theme/app_theme.dart';
import '../services/offline_sync_queue.dart';
import '../services/map_path_tracer.dart';
import '../services/blood_detection_engine.dart';

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
  bool _isInitializing = false; // re-entrancy guard for camera init
  String? _cameraError; // null = no error; non-null = fallback UI shown
  bool _isTorchOn = false;
  bool _isNightVisionActive = false;
  bool _isThermalModeActive = false;
  bool _isDroppingPin = false;
  final bool _showMapView = false;
  FlashMode _flashMode = FlashMode.off;

  // Live blood detection
  final BloodDetectionEngine _bloodEngine = BloodDetectionEngine();
  bool _isProcessingFrame = false; // throttle: skip frames while busy
  bool _isStreaming = false;
  BloodDetectionResult? _bloodResult;

  // GPS waypoint tracking
  final List<Map<String, dynamic>> _waypoints = [];
  double _totalDistance = 0;

  // High-contrast Ironbow pseudo-thermal color filter matrix
  final List<double> _thermalMatrix = <double>[
    -1.0, 2.0, 2.0, 0.0, -50.0,
    2.0, -1.0, 0.0, 0.0, -100.0,
    0.0, 0.0, 3.0, 0.0, 100.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
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
    _stopImageStream();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Robust lifecycle: dispose the camera when the app is backgrounded, and
    // re-acquire it on resume. Guarded against re-entrant initialization.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopImageStream();
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      if (!_isInitializing) _initializeCamera();
    }
  }

  /// Checks and requests camera permission before any camera access.
  /// Returns true if permission is granted.
  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      _cameraError =
          'Camera permission permanently denied. Enable it in app settings.';
      if (mounted) setState(() {});
      return false;
    }
    final result = await Permission.camera.request();
    if (!result.isGranted) {
      _cameraError = 'Camera permission denied.';
      if (mounted) setState(() {});
      return false;
    }
    return true;
  }

  Future<void> _initializeCamera() async {
    // Re-entrancy guard: never start two init passes concurrently.
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      _cameraError = null;
      if (mounted) setState(() {});

      if (!await _ensureCameraPermission()) {
        return;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _cameraError = 'No cameras available on this device.';
        if (mounted) setState(() {});
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      // Dispose any stale controller before creating a fresh one.
      _cameraController?.dispose();

      // yuv420 supports startImageStream for live blood detection.
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // Begin live blood-detection stream once the preview is live.
        await _startImageStream();
      }
    } on CameraException catch (e) {
      // Hardware lens busy / contention: surface a retryable fallback.
      debugPrint('CameraException: ${e.code} — ${e.description}');
      _cameraError = e.description?.isNotEmpty == true
          ? e.description!
          : 'Camera is busy or unavailable. Try again.';
      _cameraController = null;
      if (mounted) setState(() => _isInitialized = false);
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      _cameraError = 'Camera initialization failed: $e';
      _cameraController = null;
      if (mounted) setState(() => _isInitialized = false);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _startImageStream() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isStreaming) {
      return;
    }
    try {
      await _cameraController!.startImageStream(_onCameraImage);
      _isStreaming = true;
    } catch (e) {
      debugPrint('startImageStream failed: $e');
      // Non-fatal: detection overlay simply won't update; preview still works.
    }
  }

  Future<void> _stopImageStream() async {
    if (_cameraController == null || !_isStreaming) return;
    try {
      await _cameraController!.stopImageStream();
    } catch (e) {
      debugPrint('stopImageStream failed: $e');
    } finally {
      _isStreaming = false;
    }
  }

  /// Processes a single camera frame: converts YUV420 → RGBA grid, runs the
  /// HSV blood mask, and triggers a repaint. Throttled so we never queue
  /// frames faster than we can process them.
  void _onCameraImage(CameraImage image) {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    // Run synchronously on a microtask to keep memory pressure bounded.
    // Conversion is on a 64×64 grid → cheap enough for the UI thread.
    scheduleMicrotask(() {
      try {
        if (image.planes.length < 3) {
          _isProcessingFrame = false;
          return;
        }
        final y = image.planes[0].bytes;
        final u = image.planes[1].bytes;
        final v = image.planes[2].bytes;
        final uvRowStride = image.planes[1].bytesPerRow;
        // For YUV420 the U/V planes are subsampled; pixelStride == bytesPerPixel.
        final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

        final grid = _bloodEngine.thresholds.gridSize;
        final rgba = BloodDetectionEngine.yuv420ToRgbaGrid(
          yPlane: y,
          uPlane: u,
          vPlane: v,
          width: image.width,
          height: image.height,
          uvRowStride: uvRowStride,
          uvPixelStride: uvPixelStride,
          targetGridSize: grid,
        );

        final result = _bloodEngine.detect(
          rgba: rgba,
          width: grid,
          height: grid,
          bytesPerPixel: 4,
        );

        if (mounted) {
          setState(() => _bloodResult = result);
        }
      } catch (e) {
        debugPrint('Blood detection frame error: $e');
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  void _setThresholds({
    double? redHueTolerance,
    double? minSaturation,
    double? minValue,
  }) {
    setState(() {
      _bloodEngine.thresholds = _bloodEngine.thresholds.copyWith(
        redHueTolerance: redHueTolerance,
        minSaturation: minSaturation,
        minValue: minValue,
      );
    });
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
      final position = await _getCurrentPosition();
      if (position == null) {
        _showErrorSnackBar('Could not acquire GPS position');
        setState(() {
          _isDroppingPin = false;
        });
        return;
      }

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

      final waypoint = {
        'lat': position.latitude,
        'lon': position.longitude,
        'timestamp': DateTime.now(),
        'number': _waypoints.length + 1,
        'distanceFromLast': distanceFromLast,
      };

      _waypoints.add(waypoint);

      await OfflineSyncQueue.instance.enqueueAction('waypoints', 'CREATE', {
        'name': 'Blood Spoor',
        'type': 'Blood Trail',
        'lat': position.latitude,
        'lon': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });

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
          // Camera viewport layer (with graceful fallback on init failure)
          _buildCameraViewport(),

          // Live HSV red/hemoglobin blood detection mask overlay
          _buildBloodDetectionOverlay(),

          // Red color isolation filter (night vision / thermal modes)
          _buildColorIsolationOverlay(),

          // HUD status bar at top
          _buildTopStatusBar(theme),

          // Blood detection threshold controls
          _buildThresholdControls(),

          // Tactical radar HUD controls
          _buildHudDashboard(theme),

          // Crosshair reticle
          _buildCrosshairReticle(),
        ],
      ),
    );
  }

  Widget _buildCameraViewport() {
    // Graceful fallback when the camera failed to initialize (permission
    // denied, lens busy, or no hardware). Offers a retry action.
    if (_cameraError != null || !_isInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _cameraError == null
                      ? Icons.videocam
                      : Icons.videocam_off,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _cameraError ?? 'Initializing camera...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                if (_cameraError != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isInitializing ? null : _initializeCamera,
                    icon: const Icon(Icons.refresh),
                    label: const Text('RETRY CAMERA'),
                  ),
                if (_cameraError == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: CircularProgressIndicator(color: Colors.red),
                  ),
              ],
            ),
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

  /// Live HSV blood-detection mask: highlights red/hemoglobin-colored regions
  /// on the camera stream in translucent red. Driven by startImageStream.
  Widget _buildBloodDetectionOverlay() {
    if (!_isInitialized || _bloodResult == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BloodMaskPainter(
            result: _bloodResult!,
            detectionRatio: _bloodResult!.detectionRatio,
          ),
        ),
      ),
    );
  }

  Widget _buildColorIsolationOverlay() {
    const nightVisionMatrix = <double>[
      0.3, 0.59, 0.11, 0, 0,
      0.2, 0.8, 0.1, 0, 0,
      0.1, 0.3, 0.4, 0, 0,
      0, 0, 0, 1, 0,
    ];

    List<double> colorMatrix;
    if (_isThermalModeActive) {
      colorMatrix = _thermalMatrix;
    } else if (_isNightVisionActive) {
      colorMatrix = nightVisionMatrix;
    } else {
      // No whole-frame tint in normal mode — the per-pixel HSV mask overlay
      // is what surfaces blood in daylight.
      return const SizedBox.shrink();
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
            Row(
              children: [
                const Icon(Icons.visibility_rounded, color: Colors.red, size: 20),
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
            Row(
              children: [
                if (_bloodResult != null && _bloodResult!.hasDetection)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red, width: 1),
                    ),
                    child: Text(
                      '🩸 ${(_bloodResult!.detectionRatio * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ],
        ),
      ),
    );
  }

  /// Adjustable HSV threshold sliders for the blood detection mask.
  Widget _buildThresholdControls() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 100,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'BLOOD DETECTION THRESHOLDS',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                ContextualInfoIcon(
                  title: 'HSV Spectrum Thresholding',
                  iconColor: Colors.red,
                  iconSize: 15,
                  description:
                      'Blood (haemoglobin) is isolated in the HSV colour space rather than RGB because hue is far more stable under uneven bush lighting. Three thresholds tune the mask: how wide a hue band to accept, how saturated (pure) the red must be, and how bright it must be to count.',
                  concepts: const [
                    ExplanationConcept(
                      label: 'Hue Tolerance',
                      detail: 'How far either side of the blood-red hue (≈0°/360°) to accept — wider catches faded blood, narrower rejects orange/brown soil.',
                    ),
                    ExplanationConcept(
                      label: 'Min Saturation',
                      detail: 'Rejects grey/white reflections and bleached substrate; only sufficiently pure reds qualify.',
                    ),
                    ExplanationConcept(
                      label: 'Min Value',
                      detail: 'Rejects dark shadow noise so only bright-enough red pixels count as haemoglobin.',
                    ),
                    ExplanationConcept(
                      label: 'Bush tuning',
                      detail: 'Lower saturation/value under deep canopy; tighten hue in bright, high-contrast light.',
                    ),
                  ],
                ),
                Text(
                  _bloodResult == null
                      ? '—'
                      : '${(_bloodResult!.detectionRatio * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildThresholdSlider(
              label: 'Hue Tol',
              value: _bloodEngine.thresholds.redHueTolerance,
              min: 5,
              max: 45,
              onChanged: (v) => _setThresholds(redHueTolerance: v),
            ),
            _buildThresholdSlider(
              label: 'Sat Min',
              value: _bloodEngine.thresholds.minSaturation,
              min: 0.1,
              max: 0.9,
              onChanged: (v) => _setThresholds(minSaturation: v),
            ),
            _buildThresholdSlider(
              label: 'Val Min',
              value: _bloodEngine.thresholds.minValue,
              min: 0.05,
              max: 0.6,
              onChanged: (v) => _setThresholds(minValue: v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) * 20).round(),
              activeColor: Colors.red,
              inactiveColor: Colors.red.withValues(alpha: 0.2),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              value.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white, fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ),
        ],
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
          _buildHudButton(
            icon: _isTorchOn ? Icons.flashlight_on : Icons.flashlight_off,
            label: _isTorchOn ? 'ON' : 'OFF',
            backgroundColor: _isTorchOn
                ? Colors.amber.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.6),
            iconColor: _isTorchOn ? Colors.amber : Colors.white70,
            onTap: _toggleTorch,
          ),
          _buildHudButton(
            icon: _isNightVisionActive
                ? Icons.nightlight_round
                : Icons.wb_sunny,
            label: _isNightVisionActive ? 'NV' : 'DAY',
            backgroundColor: _isNightVisionActive
                ? Colors.green.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.6),
            iconColor: _isNightVisionActive ? Colors.green : Colors.white70,
            onTap: _toggleNightVision,
          ),
          _buildBloodPinButton(theme),
          _buildHudButton(
            icon: Icons.map,
            label: '${_waypoints.length} WP',
            backgroundColor: _showMapView
                ? Colors.blue.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.6),
            iconColor:
                _showMapView ? Colors.lightBlueAccent : Colors.white70,
            onTap: _showMapFullScreen,
          ),
          _buildHudButton(
            icon: Icons.download,
            label: _totalDistance > 0
                ? '${_totalDistance.toStringAsFixed(0)}m'
                : 'GPS',
            backgroundColor: _totalDistance > 0
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.6),
            iconColor: _totalDistance > 0
                ? Colors.lightGreenAccent
                : Colors.white70,
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
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
          border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 2),
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
        child: _isDroppingPin
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
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bloodtype_rounded, color: Colors.white, size: 32),
                  SizedBox(height: 2),
                  Text(
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
              border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
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
}

/// Paints the HSV blood-detection mask as a translucent red grid overlay,
/// aligned to the full-bleed camera preview.
class _BloodMaskPainter extends CustomPainter {
  final BloodDetectionResult result;
  final double detectionRatio;

  _BloodMaskPainter({required this.result, required this.detectionRatio});

  @override
  void paint(Canvas canvas, Size size) {
    if (!result.hasDetection) return;

    final grid = result.gridSize;
    final cellW = size.width / grid;
    final cellH = size.height / grid;

    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    final edgePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int y = 0; y < grid; y++) {
      for (int x = 0; x < grid; x++) {
        if (result.mask[y][x]) {
          final rect = Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);
          canvas.drawRect(rect, paint);
          canvas.drawRect(rect, edgePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BloodMaskPainter oldDelegate) =>
      detectionRatio != oldDelegate.detectionRatio ||
      result.detectionCount != oldDelegate.result.detectionCount;
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
