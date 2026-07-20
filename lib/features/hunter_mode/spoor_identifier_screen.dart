import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../track/data/services/spoor_ai_service.dart';

class SpoorIdentifierScreen extends StatefulWidget {
  final ThemeController theme;
  const SpoorIdentifierScreen({super.key, required this.theme});

  @override
  State<SpoorIdentifierScreen> createState() => _SpoorIdentifierScreenState();
}

class _SpoorIdentifierScreenState extends State<SpoorIdentifierScreen> {
  CameraController? _cameraController;
  SpoorAIService? _spoorAIService;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  bool _showResults = false;
  String? _matchedAnimal;
  String? _scanTimestamp;
  double? _latitude;
  double? _longitude;
  String? _confidenceWarning;
  bool _isAIInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeAI();
  }

  Future<void> _initializeAI() async {
    try {
      _spoorAIService = SpoorAIService();
      await _spoorAIService!.initialize();
      if (mounted) {
        setState(() {
          _isAIInitialized = true;
        });
      }
      debugPrint('✓ SpoorAI initialized and ready for inference');
    } catch (e) {
      debugPrint('✗ SpoorAI initialization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI initialization failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  Future<void> _scanSpoor() async {
    if (_spoorAIService == null || !_isAIInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI model not initialized. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      final XFile capturedImage = await _cameraController!.takePicture();

      setState(() {
        _isScanning = true;
        _confidenceWarning = null;
      });

      final result = await _spoorAIService!.predictSpoor(capturedImage);
      final bool success = result['success'] as bool? ?? false;
      final String species = result['species'] as String? ?? 'Unknown';
      final double confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
      final String? prediction = success ? '$species (${(confidence * 100).toStringAsFixed(1)}%)' : null;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _isScanning = false;
        _showResults = true;
        _matchedAnimal = prediction;
        _scanTimestamp = DateTime.now().toIso8601String();
        _latitude = position.latitude;
        _longitude = position.longitude;

        if (!success) {
          _confidenceWarning =
              '⚠ Low confidence match (${(confidence * 100).toStringAsFixed(1)}%). Reposition and try again.';
        }
      });

      if (success) {
        await _saveScanToFirestore('$species (${(confidence * 100).toStringAsFixed(1)}%)', position);
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      debugPrint('Scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _saveScanToFirestore(String animalName, Position position) async {
    try {
      await FirebaseFirestore.instance
          .collection('spoor_scans')
          .add({
        'timestamp': FieldValue.serverTimestamp(),
        'resolvedAnimalName': animalName,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
    } catch (e) {
      debugPrint('Error saving scan to Firestore: $e');
    }
  }

  void _resetScan() {
    setState(() {
      _showResults = false;
      _matchedAnimal = null;
      _scanTimestamp = null;
      _latitude = null;
      _longitude = null;
      _confidenceWarning = null;
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _spoorAIService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'Track (Spoor) Identifier',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: widget.theme.backgroundColor,
            iconTheme: IconThemeData(color: widget.theme.accentColor),
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.history_rounded, color: widget.theme.accentColor),
                onPressed: () => _showScanHistory(context),
              ),
            ],
          ),
          body: _isCameraInitialized
              ? _buildCameraView()
              : Center(
                  child: CircularProgressIndicator(
                    color: widget.theme.accentColor,
                  ),
                ),
        );
      },
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _cameraController!.value.previewSize!.height,
              height: _cameraController!.value.previewSize!.width,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
        _buildReticleOverlay(),
        if (!_showResults)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: _isScanning
                  ? Column(
                      children: [
                        CircularProgressIndicator(
                          color: widget.theme.accentColor,
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Running AI classification...',
                          style: TextStyle(
                            color: widget.theme.textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : ElevatedButton.icon(
                      onPressed: _isAIInitialized ? _scanSpoor : null,
                      icon: Icon(Icons.camera_alt_rounded, color: widget.theme.backgroundColor),
                      label: Text(
                        'Scan Spoor',
                        style: TextStyle(
                          color: widget.theme.backgroundColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
            ),
          ),
        if (_showResults) _buildResultsOverlay(),
      ],
    );
  }

  Widget _buildReticleOverlay() {
    return Center(
      child: CustomPaint(
        size: const Size(300, 300),
        painter: ReticlePainter(
          color: widget.theme.accentColor,
        ),
      ),
    );
  }

  Widget _buildResultsOverlay() {
    final isLowConfidence = _matchedAnimal == null;

    return Container(
      color: widget.theme.backgroundColor.withValues(alpha: 0.95),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isLowConfidence ? Icons.warning_rounded : Icons.check_circle_rounded,
            color: isLowConfidence ? Colors.orange : widget.theme.accentColor,
            size: 64,
          ),
          const SizedBox(height: 24),
          Text(
            isLowConfidence ? 'LOW CONFIDENCE' : 'MATCH FOUND',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: widget.theme.subtitleColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _matchedAnimal ?? 'Unable to classify',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: widget.theme.textColor,
            ),
          ),
          if (_confidenceWarning != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: Text(
                _confidenceWarning!,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildInfoRow('Timestamp', _formatTimestamp(_scanTimestamp)),
          const SizedBox(height: 12),
          _buildInfoRow('Latitude', _latitude?.toStringAsFixed(6) ?? 'N/A'),
          const SizedBox(height: 12),
          _buildInfoRow('Longitude', _longitude?.toStringAsFixed(6) ?? 'N/A'),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _resetScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.theme.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Scan Another',
                    style: TextStyle(
                      color: widget.theme.backgroundColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: widget.theme.subtitleColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value ?? 'N/A',
            style: TextStyle(
              fontSize: 14,
              color: widget.theme.textColor,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return 'N/A';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  void _showScanHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanHistoryScreen(theme: widget.theme),
      ),
    );
  }
}

class ReticlePainter extends CustomPainter {
  final Color color;

  ReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * 0.6, paint);

    canvas.drawLine(
      Offset(center.dx - radius - 10, center.dy),
      Offset(center.dx + radius + 10, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius - 10),
      Offset(center.dx, center.dy + radius + 10),
      paint,
    );

    final bracketSize = 30.0;
    final cornerOffset = radius + 10;

    canvas.drawLine(
      Offset(center.dx - cornerOffset, center.dy - cornerOffset + bracketSize),
      Offset(center.dx - cornerOffset, center.dy - cornerOffset),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - cornerOffset, center.dy - cornerOffset),
      Offset(center.dx - cornerOffset + bracketSize, center.dy - cornerOffset),
      paint,
    );

    canvas.drawLine(
      Offset(center.dx + cornerOffset, center.dy - cornerOffset + bracketSize),
      Offset(center.dx + cornerOffset, center.dy - cornerOffset),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + cornerOffset, center.dy - cornerOffset),
      Offset(center.dx + cornerOffset - bracketSize, center.dy - cornerOffset),
      paint,
    );

    canvas.drawLine(
      Offset(center.dx - cornerOffset, center.dy + cornerOffset - bracketSize),
      Offset(center.dx - cornerOffset, center.dy + cornerOffset),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - cornerOffset, center.dy + cornerOffset),
      Offset(center.dx - cornerOffset + bracketSize, center.dy + cornerOffset),
      paint,
    );

    canvas.drawLine(
      Offset(center.dx + cornerOffset, center.dy + cornerOffset - bracketSize),
      Offset(center.dx + cornerOffset, center.dy + cornerOffset),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + cornerOffset, center.dy + cornerOffset),
      Offset(center.dx + cornerOffset - bracketSize, center.dy + cornerOffset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ScanHistoryScreen extends StatelessWidget {
  final ThemeController theme;
  const ScanHistoryScreen({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'Scan Log History',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: theme.backgroundColor,
            iconTheme: IconThemeData(color: theme.accentColor),
            elevation: 0,
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('spoor_scans')
                .orderBy('timestamp', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: theme.accentColor),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 64,
                        color: theme.subtitleColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No scan history yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: theme.textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start scanning footprints to build your log',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.subtitleColor,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;

                  final timestamp = data['timestamp'] as Timestamp?;
                  final animalName = data['resolvedAnimalName'] as String? ?? 'Unknown';
                  final latitude = (data['latitude'] as num?)?.toDouble();
                  final longitude = (data['longitude'] as num?)?.toDouble();

                  return Card(
                    color: theme.cardColor,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Icon(
                        Icons.visibility_rounded,
                        color: theme.accentColor,
                        size: 32,
                      ),
                      title: Text(
                        animalName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.textColor,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            _formatHistoryTimestamp(timestamp),
                            style: TextStyle(
                              color: theme.subtitleColor,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (latitude != null && longitude != null)
                            Text(
                              'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                              style: TextStyle(
                                color: theme.subtitleColor,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  String _formatHistoryTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown time';
    final dt = timestamp.toDate();
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
