import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jagspoor/core/widgets/contextual_info_icon.dart';
import '../../core/theme/app_theme.dart';
import '../track/data/track_taxonomy.dart';
import '../track/data/services/spoor_ai_service.dart';
import 'services/spoor_identifier_service.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';

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

  /// Pre-selected morphological track category (null = unfiltered).
  TrackCategory? _selectedCategory;

  /// Optional scale-reference object placed beside the track, used to
  /// calibrate pixel → millimetre measurements for exact species-size matching.
  /// null = no reference (focal-scaling estimate used instead).
  static const List<({String label, double mm})> _scaleReferences = [
    (label: 'None', mm: 0),
    (label: '5-Rand Coin', mm: 26.0),
    (label: '1-Rand Coin', mm: 23.0),
    (label: '9mm Case', mm: 19.0),
    (label: '.308 Case', mm: 51.0),
    (label: 'Box of Matches', mm: 50.0),
  ];
  int _selectedScaleIndex = 0;
  double? get _scaleReferenceMm {
    final ref = _scaleReferences[_selectedScaleIndex];
    return ref.mm > 0 ? ref.mm : null;
  }

  /// Ranked top-3 predictions from the last scan (empty if unavailable).
  List<SpoorPrediction> _topPredictions = const [];

  /// Geometric metrics from the last scan (for displaying measured mm).
  dynamic _lastMetrics;

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

      final nativeResult = await SpoorIdentifierService.instance
          .classifySpoorTrack(
        capturedImage,
        category: _selectedCategory,
        scaleReferenceMm: _scaleReferenceMm,
      );
      final bool success = nativeResult['success'] as bool? ?? true;
      final String trackingResult =
          nativeResult['trackingResult'] as String? ??
          'Identified Spoor: Unknown Track';
      final double confidence =
          (nativeResult['confidence'] as num?)?.toDouble() ?? 0.0;
      final List<SpoorPrediction> top =
          (nativeResult['topPredictions'] as List?)
              ?.whereType<SpoorPrediction>()
              .toList() ??
          const <SpoorPrediction>[];
      final metrics = nativeResult['metrics'];

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _isScanning = false;
        _showResults = true;
        _matchedAnimal =
            '$trackingResult (${(confidence * 100).toStringAsFixed(1)}%)';
        _topPredictions = top;
        _lastMetrics = metrics;
        _scanTimestamp = DateTime.now().toIso8601String();
        _latitude = position.latitude;
        _longitude = position.longitude;

        if (!success) {
          _confidenceWarning =
              '⚠ Low confidence match (${(confidence * 100).toStringAsFixed(1)}%). Reposition and try again.';
        }
      });

      if (success) {
        await _saveScanToFirestore(_matchedAnimal!, position);
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

  Future<void> _saveScanToFirestore(
    String animalName,
    Position position,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('spoor_scans').add({
        'userId': FirebaseAuth.instance.currentUser?.uid,
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
      _topPredictions = const [];
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
        return HunterScaffold(
          theme: widget.theme,
          padBodyForAppBar: true,
          appBar: AppBar(
            title: Text(
              'Track (Spoor) Identifier',
              style: TextStyle(
                color: HunterUi.titleColor(widget.theme),
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.transparent,
            iconTheme: IconThemeData(color: HunterUi.titleColor(widget.theme)),
            elevation: 0,
            actions: [
              AppInfoIconButton(
                screenKey: AppScreenHelpScripts.hunterSpoorIdentification,
                iconColor: widget.theme.accentColor,
              ),
              IconButton(
                icon: Icon(
                  Icons.history_rounded,
                  color: widget.theme.accentColor,
                ),
                onPressed: () => _showScanHistory(context),
              ),
            ],
          ),
          body:
              _isCameraInitialized
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
            bottom: MediaQuery.of(context).padding.bottom + 40,
            left: 16,
            right: 16,
            child: Center(
              child:
                  _isScanning
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
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCategorySelector(),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isAIInitialized ? _scanSpoor : null,
                            icon: Icon(
                              Icons.camera_alt_rounded,
                              color: widget.theme.backgroundColor,
                            ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                        ],
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
        painter: ReticlePainter(color: widget.theme.accentColor),
      ),
    );
  }

  Widget _buildCategorySelector() {
    final accent = widget.theme.accentColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HunterUi.cardColor(widget.theme).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TRACK CATEGORY (pre-filter)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: widget.theme.subtitleColor,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              ContextualInfoIcon(
                title: 'Morphological Categories',
                iconColor: widget.theme.subtitleColor,
                description:
                    'Pre-filters the species database by track morphology so the matcher only compares against anatomically plausible candidates. Choosing the wrong category is the most common cause of misidentification.',
                concepts: const [
                  ExplanationConcept(
                    label: 'Paw / Carnivore',
                    detail: 'Symmetrical pads with toe beans and claw marks (may show 4-5 toes).',
                  ),
                  ExplanationConcept(
                    label: 'Cloven-Hoofed / Ungulate',
                    detail: 'Two split dewclaws forming a heart/paired outline — antelope, deer, sheep, cattle, pigs.',
                  ),
                  ExplanationConcept(
                    label: 'Solid Hoof / Equine',
                    detail: 'Single rounded undivided hoof — horse, zebra, donkey.',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectedCategory == null
                ? 'Auto (no filter — may cross types)'
                : categoryHint(_selectedCategory!),
            style: TextStyle(fontSize: 11, color: widget.theme.subtitleColor),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _categoryChip(null, 'Auto', accent),
              for (final c in TrackCategory.values)
                _categoryChip(c, categoryLabel(c), accent),
            ],
          ),
          const SizedBox(height: 16),
          // On-screen track scale reference for mm measurement.
          Row(
            children: [
              Expanded(
                child: Text(
                  'SCALE REFERENCE (place beside track)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: widget.theme.subtitleColor,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              ContextualInfoIcon(
                title: 'Scale Reference Calibration',
                iconColor: widget.theme.subtitleColor,
                description:
                    'A coin or casing of known size placed beside the track gives the image a real-world dimension. The app measures how many pixels that object occupies and computes a millimetres-per-pixel factor, which it then uses to convert the track\'s pixel dimensions into true length and width in mm.',
                concepts: const [
                  ExplanationConcept(
                    label: 'Known object',
                    detail: 'A coin or cartridge casing placed in the same plane as the track.',
                  ),
                  ExplanationConcept(
                    label: 'Pixel ratio',
                    detail: 'mm-per-pixel = knownObjectMm ÷ knownObjectPixels.',
                  ),
                  ExplanationConcept(
                    label: 'Track size',
                    detail: 'lengthMm = trackPixels × mm-per-pixel (same for width).',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _scaleReferences.length; i++)
                _scaleReferenceChip(i, _scaleReferences[i], accent),
            ],
          ),
          if (_lastMetrics != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      _scaleReferenceMm == null
                          ? 'Measured: ${_mmString('printLengthMm')} × ${_mmString('printWidthMm')} mm '
                              '(estimate)'
                          : 'Measured: ${_mmString('printLengthMm')} × ${_mmString('printWidthMm')} mm '
                              '· Circ ${_mmString('circularity')} · Aspect ${_mmString('aspectRatio')}'
                              ' (calibrated to ${_scaleReferences[_selectedScaleIndex].label})',
                      style: TextStyle(fontSize: 11, color: widget.theme.subtitleColor),
                    ),
                  ),
                  ContextualInfoIcon(
                    title: 'Contour Circularity Metric',
                    iconColor: widget.theme.subtitleColor,
                    iconSize: 15,
                    description:
                        'A dimensionless shape factor that describes how close the track contour is to a perfect circle. It helps distinguish compact, rounded pads (carnivores) from elongated or split outlines (ungulates) even when absolute size is uncertain.',
                    concepts: const [
                      ExplanationConcept(
                        label: 'Formula',
                        detail: 'circularity = 4πA ÷ P²  (A = contour area, P = perimeter).',
                      ),
                      ExplanationConcept(
                        label: 'Circle',
                        detail: 'A perfect circle scores 1.0; any departure from circular lowers the value.',
                      ),
                      ExplanationConcept(
                        label: 'Low score',
                        detail: 'Elongated or split (cloven) outlines score well below 1, signalling an ungulate.',
                      ),
                      ExplanationConcept(
                        label: 'Aspect ratio',
                        detail: 'Length ÷ width — complements circularity to flag elongated tracks.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _mmString(String field) {
    final m = _lastMetrics;
    if (m == null) return '—';
    try {
      final v = (m as dynamic)[field];
      if (v is num) return v.toStringAsFixed(1);
      return v.toString();
    } catch (_) {
      return '—';
    }
  }

  Widget _scaleReferenceChip(
    int index,
    ({String label, double mm}) ref,
    Color accent,
  ) {
    final selected = _selectedScaleIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedScaleIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.3)
              : HunterUi.cardColor(widget.theme).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : accent.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          ref.mm > 0 ? '${ref.label} (${ref.mm}mm)' : ref.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : widget.theme.subtitleColor,
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(TrackCategory? c, String label, Color accent) {
    final selected = _selectedCategory == c;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : accent.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? widget.theme.backgroundColor : widget.theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildResultsOverlay() {
    final isLowConfidence = _matchedAnimal == null;

    return Container(
      color: widget.theme.backgroundColor.withValues(alpha: 0.95),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isLowConfidence
                  ? Icons.warning_rounded
                  : Icons.check_circle_rounded,
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
            if (_topPredictions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'TOP MATCHES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: widget.theme.subtitleColor,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < _topPredictions.length; i++)
                _buildPredictionRow(_topPredictions[i], i == 0),
            ],
            if (_selectedCategory != null) ...[
              const SizedBox(height: 20),
              _buildVerificationPrompts(),
            ],
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
            style: TextStyle(fontSize: 14, color: widget.theme.textColor),
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

  Widget _buildPredictionRow(SpoorPrediction p, bool isTop) {
    final pct = p.confidencePercent.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isTop ? Icons.military_tech_rounded : Icons.label_outline,
            size: 18,
            color:
                isTop ? widget.theme.accentColor : widget.theme.subtitleColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.species,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                color:
                    isTop ? widget.theme.textColor : widget.theme.subtitleColor,
              ),
            ),
          ),
          Text(
            '$pct%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color:
                  isTop ? widget.theme.accentColor : widget.theme.subtitleColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationPrompts() {
    final accent = widget.theme.accentColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verify anatomical features (${categoryLabel(_selectedCategory!)})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: widget.theme.textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final prompt in verificationPrompts(_selectedCategory!))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_box_outline_blank,
                    size: 18,
                    color: widget.theme.subtitleColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      prompt,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.theme.subtitleColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
    final paint =
        Paint()
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
        return HunterScaffold(
          theme: theme,
          padBodyForAppBar: true,
          appBar: AppBar(
            title: Text(
              'Scan Log History',
              style: TextStyle(
                color: HunterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.transparent,
            iconTheme: IconThemeData(color: HunterUi.titleColor(theme)),
            elevation: 0,
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
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
                        style: TextStyle(fontSize: 18, color: theme.textColor),
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
                  final animalName =
                      data['resolvedAnimalName'] as String? ?? 'Unknown';
                  final latitude = (data['latitude'] as num?)?.toDouble();
                  final longitude = (data['longitude'] as num?)?.toDouble();

                  return Card(
                    color: HunterUi.cardColor(theme),
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
