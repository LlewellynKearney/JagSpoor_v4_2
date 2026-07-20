import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';

class LicenseScannerScreen extends StatefulWidget {
  final ThemeController theme;
  const LicenseScannerScreen({super.key, required this.theme});

  @override
  State<LicenseScannerScreen> createState() => _LicenseScannerScreenState();
}

class _LicenseScannerScreenState extends State<LicenseScannerScreen> {
  // Live scanner locked to PDF417 (the dense 2D format on SA documents).
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.pdf417],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final ImagePicker _picker = ImagePicker();

  bool _handled = false;
  bool _torchOn = false;
  String? _status;

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first;
    _finish(barcode);
  }

  void _finish(Barcode barcode) {
    if (_handled) return;
    final bytes = switch (barcode.rawDecodedBytes) {
      DecodedBarcodeBytes(:final bytes) => bytes,
      DecodedVisionBarcodeBytes(:final bytes) => bytes,
      null => null,
    };
    final raw = barcode.rawValue ??
        (bytes != null ? String.fromCharCodes(bytes) : '');
    if (raw.isEmpty) {
      setState(() => _status = 'Barcode found but could not be read. Try again.');
      return;
    }
    _handled = true;
    if (!mounted) return;
    Navigator.pop(context, _parseLicense(raw));
  }

  Future<void> _scanFromGallery() async {
    setState(() => _status = null);
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final BarcodeCapture? capture = await _controller.analyzeImage(file.path);
      if (capture == null || capture.barcodes.isEmpty) {
        setState(() => _status =
            'No PDF417 barcode found in that image. Use a sharp, straight, fully-visible shot.');
        return;
      }
      _finish(capture.barcodes.first);
    } catch (e) {
      setState(() => _status = 'Could not read image: $e');
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // Torch unavailable on this device/camera; ignore.
    }
  }

  // SA firearm-licence PDF417 is pipe-delimited with fixed positions. Map the
  // known fields; "NONE" placeholders become empty. Positions confirmed against
  // a real EMC scan; #2 is intentionally ignored and #7/#18 are serial/licence.
  Map<String, dynamic> _parseLicense(String raw) {
    final parts = raw.split('|').map((p) => p.trim()).toList();
    String at(int i) {
      if (i < 0 || i >= parts.length) return '';
      final v = parts[i];
      return v.toUpperCase() == 'NONE' ? '' : v;
    }

    return {
      'isScanned': true,
      'licenceType': at(0),
      'idNumber': at(1),
      'holderName': at(3),
      'licenceSection': at(4),
      'issueDate': at(5),
      'expiryDate': at(6),
      'serial': at(7),
      'firearmType': at(8),
      'make': at(9),
      'model': at(10),
      'caliber': at(11),
      'manufacturer': at(17),
      'licenseNumber': at(18),
      'raw': raw,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('SCAN LICENSE',
            style: TextStyle(
                color: theme.textColor, fontFamily: 'Mono', letterSpacing: 1.2)),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                color: theme.accentColor),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            fit: BoxFit.cover,
            errorBuilder: (context, error) => _CameraError(
              error: error,
              theme: theme,
              onPickGallery: _scanFromGallery,
            ),
          ),
          // Viewfinder frame.
          Center(
            child: Container(
              width: 280,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: theme.accentColor, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Instructions + gallery fallback.
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Hold the PDF417 barcode flat inside the frame.\nKeep it sharp, well-lit, and fully visible.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.amberAccent)),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.accentColor, width: 1.5),
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: Colors.black54,
                  ),
                  icon: Icon(Icons.photo_library_rounded,
                      color: theme.accentColor),
                  label: Text('SELECT FROM GALLERY',
                      style: TextStyle(
                          color: theme.accentColor,
                          fontWeight: FontWeight.bold)),
                  onPressed: _scanFromGallery,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final ThemeController theme;
  final VoidCallback onPickGallery;
  const _CameraError(
      {required this.error, required this.theme, required this.onPickGallery});

  @override
  Widget build(BuildContext context) {
    final isPermission =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.no_photography_rounded,
              size: 72, color: theme.accentColor),
          const SizedBox(height: 16),
          Text(
            isPermission
                ? 'Camera permission is required to scan. Enable it in Settings, then reopen this screen.'
                : 'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: theme.accentColor, width: 1.5),
              minimumSize: const Size.fromHeight(52),
            ),
            icon: Icon(Icons.photo_library_rounded, color: theme.accentColor),
            label: Text('SELECT FROM GALLERY',
                style: TextStyle(
                    color: theme.accentColor, fontWeight: FontWeight.bold)),
            onPressed: onPickGallery,
          ),
        ],
      ),
    );
  }
}
