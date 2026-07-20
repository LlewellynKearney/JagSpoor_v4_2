import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../data/services/spoor_ai_service.dart';
import 'classification_result_widget.dart';

class SpoorDetectionHudScreen extends StatefulWidget {
  final ThemeController theme;
  const SpoorDetectionHudScreen({super.key, required this.theme});

  @override
  State<SpoorDetectionHudScreen> createState() => _SpoorDetectionHudScreenState();
}

class _SpoorDetectionHudScreenState extends State<SpoorDetectionHudScreen> {
  CameraController? _cameraController;
  final SpoorAIService _spoorAIService = SpoorAIService();
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  bool _isAIInitialized = false;
  
  String? _latitude;
  String? _longitude;
  Map<String, dynamic>? _predictionResult;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeAI();
    _fetchLocation();
  }

  Future<void> _initializeAI() async {
    try {
      await _spoorAIService.initialize();
      if (mounted) {
        setState(() => _isAIInitialized = true);
      }
    } catch (e) {
      debugPrint('AI initialization failed: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras[0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() => _isCameraInitialized = true);
        }
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  Future<void> _fetchLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude.toStringAsFixed(6);
          _longitude = position.longitude.toStringAsFixed(6);
        });
      }
    } catch (e) {
      debugPrint('Location fetch error: $e');
    }
  }

  Future<void> _scanSpoor() async {
    if (_cameraController == null || !_isCameraInitialized) return;
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _predictionResult = null;
    });

    try {
      final image = await _cameraController!.takePicture();
      final result = await _spoorAIService.predictSpoor(image);
      
      if (mounted) {
        setState(() {
          _isScanning = false;
          _predictionResult = result;
        });
      }
    } catch (e) {
      debugPrint('Scan spoor error: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.theme,
      builder: (context, _) {
        final modeText = _getHudModeText();
        final scanColor = widget.theme.accentColor;

        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          body: Stack(
            children: [
              // Live camera background
              if (_isCameraInitialized && _cameraController != null)
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    color: Colors.black87,
                    child: Center(
                      child: CircularProgressIndicator(color: scanColor),
                    ),
                  ),
                ),

              // HUD Reticle Overlay
              if (!_isScanning && _predictionResult == null)
                Center(
                  child: CustomPaint(
                    size: const Size(260, 260),
                    painter: HudReticlePainter(color: scanColor),
                  ),
                ),

              // Scanning Overlay
              if (_isScanning)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: scanColor),
                        const SizedBox(height: 16),
                        Text(
                          'ANALYZING SPOOR SIGNATURE...',
                          style: TextStyle(
                            color: scanColor,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // SafeArea contents
              SafeArea(
                child: Column(
                  children: [
                    // Top Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: scanColor.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _isAIInitialized ? Colors.green : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  modeText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    
                    // Main Hud scrollable area for overlays
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_predictionResult != null) ...[
                              ClassificationResultWidget(
                                speciesName: _predictionResult!['species'] ?? 'Unknown',
                                confidence: (_predictionResult!['confidence'] as num?)?.toDouble() ?? 0.0,
                                theme: widget.theme,
                                gpsCoordinates: _latitude != null && _longitude != null 
                                    ? '$_latitude, $_longitude' 
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() => _predictionResult = null);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black87,
                                  side: BorderSide(color: scanColor),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'RESET SCANNER',
                                  style: TextStyle(color: scanColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ] else ...[
                              // Tactical Data Overlay Card
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: scanColor.withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTacticalRow('LATITUDE', _latitude ?? 'ACQUIRING GPS...'),
                                    const SizedBox(height: 8),
                                    _buildTacticalRow('LONGITUDE', _longitude ?? 'ACQUIRING GPS...'),
                                    const SizedBox(height: 8),
                                    _buildTacticalRow('SYS ENGINE', _isAIInitialized ? 'TFLITE OPTIMIZED' : 'INITIALIZING...'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Capture/Scan Trigger Button
                              GestureDetector(
                                onTap: _scanSpoor,
                                child: Center(
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 4),
                                      color: scanColor.withValues(alpha: 0.4),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: scanColor,
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt_rounded,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'ALIGN RETICLE WITH ANIMAL TRACK',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getHudModeText() {
    switch (widget.theme.currentConcept) {
      case HuntingConcept.thermalGlow:
        return 'THERMAL IMAGING ACTIVE';
      case HuntingConcept.neonShock:
        return 'NIGHT VISION SYSTEM';
      case HuntingConcept.walnutLuxury:
        return 'OPTICS HUD ACTIVE';
    }
  }

  Widget _buildTacticalRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: widget.theme.accentColor.withValues(alpha: 0.7),
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class HudReticlePainter extends CustomPainter {
  final Color color;
  const HudReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer corners/brackets
    final bracketLength = 24.0;
    canvas.drawLine(Offset(0, 0), Offset(bracketLength, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(0, bracketLength), paint);

    canvas.drawLine(Offset(size.width, 0), Offset(size.width - bracketLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, bracketLength), paint);

    canvas.drawLine(Offset(0, size.height), Offset(bracketLength, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - bracketLength), paint);

    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - bracketLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - bracketLength), paint);

    // Crosshairs
    canvas.drawLine(Offset(center.dx - 15, center.dy), Offset(center.dx - 5, center.dy), paint);
    canvas.drawLine(Offset(center.dx + 5, center.dy), Offset(center.dx + 15, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - 15), Offset(center.dx, center.dy - 5), paint);
    canvas.drawLine(Offset(center.dx, center.dy + 5), Offset(center.dx, center.dy + 15), paint);

    // Inner circle
    canvas.drawCircle(center, radius * 0.4, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
