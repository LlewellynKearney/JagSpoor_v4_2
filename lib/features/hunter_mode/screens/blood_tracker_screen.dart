import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../services/offline_sync_queue.dart';

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
  bool _isDroppingPin = false;
  FlashMode _flashMode = FlashMode.off;

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

      // Enqueue waypoint to OfflineSyncQueue
      await OfflineSyncQueue.instance.enqueueAction(
        'waypoints',
        'CREATE',
        {
          'name': 'Blood Spoor',
          'type': 'Blood Trail',
          'lat': position.latitude,
          'lon': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (mounted) {
        _showToast(
          '🩸 Blood waypoint dropped at ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
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

          // Red color isolation overlay
          _buildColorIsolationOverlay(),

          // HUD status bar at top
          _buildTopStatusBar(theme),

          // Tactical radar HUD controls
          _buildHudDashboard(theme),

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
    const colorMatrix = <double>[
      // Red channel - enhance red, reduce green/blue contribution
      1.5, -0.2, -0.1, 0, 0,
      // Green channel - desaturate green
      -0.1, 0.3, 0.1, 0, 0,
      // Blue channel - reduce blue contribution
      -0.2, 0.1, 0.2, 0, 0,
      // Alpha channel
      0, 0, 0, 1, 0,
    ];

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
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
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
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Torch toggle button
          _buildHudButton(
            icon: _isTorchOn ? Icons.flashlight_on : Icons.flashlight_off,
            label: _isTorchOn ? 'ON' : 'OFF',
            backgroundColor: _isTorchOn
                ? Colors.amber.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.6),
            iconColor: _isTorchOn ? Colors.amber : Colors.white70,
            onTap: _toggleTorch,
          ),

          // Blood drop pin button
          _buildBloodPinButton(theme),

          // Zoom indicator placeholder
          _buildHudButton(
            icon: Icons.zoom_in,
            label: '1.0x',
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            iconColor: Colors.white70,
            onTap: () {},
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
        width: 72,
        height: 72,
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
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
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
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF8C00),
              Color(0xFFFF6B00),
            ],
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
}
