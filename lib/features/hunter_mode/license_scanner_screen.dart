import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/web_barcode_service.dart';
import '../../core/theme/app_theme.dart';
import 'services/license_scan_processor.dart';

/// Live PDF417 licence scanner.
///
/// The live camera path is backed by ML Kit / barhopper, which exists only on
/// Android and iOS. In a browser there is no ML Kit, and
/// `MobileScannerController.analyzeImage()` explicitly throws
/// `UnsupportedError` there — which surfaced as an "Unsupported operation"
/// error the moment a web user picked a licence photo.
///
/// On the web this screen therefore skips the native pipeline entirely and
/// renders a fallback panel offering the two things that DO work in a browser:
/// decoding a licence photo through the bundled ZXing decoder
/// ([decodePdf417FromImageUrl]), and returning to manual entry. Android and
/// iOS keep the ML Kit live-scan flow unchanged.
class LicenseScannerScreen extends StatefulWidget {
  final ThemeController theme;

  /// Forces the web fallback panel on any platform. Used by widget tests,
  /// which run on the VM where `kIsWeb` is false.
  final bool forceWebMode;

  const LicenseScannerScreen({
    super.key,
    required this.theme,
    this.forceWebMode = false,
  });

  @override
  State<LicenseScannerScreen> createState() => _LicenseScannerScreenState();
}

class _LicenseScannerScreenState extends State<LicenseScannerScreen> {
  // Live scanner locked to PDF417 (the dense 2D format on SA documents).
  MobileScannerController? _controller;
  final ImagePicker _picker = ImagePicker();

  bool _handled = false;
  bool _torchOn = false;
  bool _hasPermission = false;
  bool _permissionDenied = false;
  bool _isDecodingImage = false;
  String? _status;

  /// Whether the browser fallback panel is used instead of the native
  /// ML Kit pipeline.
  bool get _webMode => widget.forceWebMode || kIsWeb;

  @override
  void initState() {
    super.initState();
    // The browser prompts for camera access itself when a stream is requested,
    // and the web fallback never opens a camera stream — so the native
    // permission dance is skipped there rather than being driven to a
    // misleading "permission required" state.
    if (!_webMode) {
      _checkCameraPermissions();
    }
  }

  /// Runtime camera permission check using permission_handler. Degrades
  /// gracefully to the permission-denied state when the platform plugin is
  /// unavailable (unsupported platform / test harness) instead of throwing.
  Future<void> _checkCameraPermissions() async {
    PermissionStatus status;
    try {
      status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
    } catch (_) {
      status = PermissionStatus.permanentlyDenied;
    }

    if (!mounted) return;

    setState(() {
      if (status.isGranted) {
        _hasPermission = true;
        _permissionDenied = false;
        _initializeScannerController();
      } else {
        // Any non-granted status (denied OR permanentlyDenied) must surface
        // the actionable permission UI; previously a plain denial left the
        // screen stuck on the loading spinner forever.
        _hasPermission = false;
        _permissionDenied = true;
      }
    });
  }

  /// Initialize the scanner controller after permission is granted.
  ///
  /// Uses [LicenseScannerConfig.buildLiveController], which requests a
  /// 1920x1080 analysis frame -- the plugin otherwise defaults CameraX to a
  /// 640x480 analysis frame, too coarse to resolve the dense licence PDF417
  /// (which is why only the full-resolution gallery path decoded).
  void _initializeScannerController() {
    _controller?.dispose();
    _controller = LicenseScannerConfig.buildLiveController();
  }

  /// Request camera permission again
  Future<void> _requestCameraPermission() async {
    PermissionStatus status;
    try {
      status = await Permission.camera.request();
    } catch (_) {
      status = PermissionStatus.permanentlyDenied;
    }

    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _permissionDenied = false;
      });
      _initializeScannerController();
    } else {
      setState(() {
        _permissionDenied = true;
      });
    }
  }

  /// Open app settings
  Future<void> _openSettings() async {
    await openAppSettings();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcode = LicenseScanProcessor.firstReadable(capture);
    if (barcode == null) return;
    _finish(barcode);
  }

  void _finish(Barcode barcode) {
    if (_handled) return;
    // Tolerate a null rawBytes payload: the live ML Kit stream frequently
    // returns PDF417 results with only rawValue populated, and discarding
    // those decodes is what made live scanning appear dead.
    final raw = LicenseScanProcessor.extractRawValue(barcode);
    if (raw == null) {
      setState(
        () => _status = 'Barcode found but could not be read. Try again.',
      );
      return;
    }
    _handled = true;
    if (!mounted) return;
    Navigator.pop(context, LicenseScanProcessor.parseLicense(raw));
  }

  Future<void> _scanFromGallery() async {
    if (_controller == null) return;
    setState(() => _status = null);
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      // The fallback decodes the picked photo at its full capture resolution
      // with the same PDF417 format restriction as the live stream.
      final BarcodeCapture? capture = await _controller!.analyzeImage(
        file.path,
        formats: LicenseScannerConfig.formats,
      );
      if (capture == null) {
        setState(
          () =>
              _status =
                  'No PDF417 barcode found in that image. Use a sharp, straight, fully-visible shot.',
        );
        return;
      }
      final barcode = LicenseScanProcessor.firstReadable(capture);
      if (barcode == null) {
        setState(
          () =>
              _status =
                  'No PDF417 barcode found in that image. Use a sharp, straight, fully-visible shot.',
        );
        return;
      }
      _finish(barcode);
    } catch (e) {
      setState(() => _status = 'Could not read image: $e');
    }
  }

  /// Web equivalent of [_scanFromGallery].
  ///
  /// `analyzeImage()` throws `UnsupportedError` in a browser, so the picked
  /// photo is decoded by the bundled ZXing library instead. `image_picker`
  /// returns a `blob:` object URL on the web, which the browser can load
  /// directly.
  Future<void> _scanFromGalleryWeb() async {
    if (_isDecodingImage) return;
    setState(() {
      _status = null;
      _isDecodingImage = true;
    });

    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        if (mounted) setState(() => _isDecodingImage = false);
        return;
      }

      final String? raw = await decodePdf417FromImageUrl(file.path);
      if (!mounted) return;

      if (raw == null || raw.trim().isEmpty) {
        setState(() {
          _isDecodingImage = false;
          _status =
              'No PDF417 barcode found in that image. Use a sharp, straight, fully-visible shot.';
        });
        return;
      }

      _isDecodingImage = false;
      _handled = true;
      Navigator.pop(context, LicenseScanProcessor.parseLicense(raw));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDecodingImage = false;
        _status = 'Could not read image: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    if (_controller == null) return;
    try {
      await _controller!.toggleTorch();
      setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // Torch unavailable on this device/camera; ignore.
    }
  }

  /// The browser fallback panel.
  ///
  /// A browser cannot run ML Kit, so instead of a live viewfinder the user is
  /// offered the two paths that work on the web: decoding a licence photo with
  /// the bundled ZXing decoder, and returning to the manual entry form.
  Widget _buildWebFallback(ThemeController theme) {
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'SCAN LICENSE',
          style: TextStyle(
            color: theme.textColor,
            fontFamily: 'Mono',
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.phone_android_rounded,
                size: 64,
                color: theme.accentColor,
              ),
              const SizedBox(height: 20),
              Text(
                'Auto-scan is only available on Android',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'A browser has no ML Kit barcode engine, so the live licence '
                'camera cannot run here. On the web you can still:',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.subtitleColor, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _webStep(
                theme,
                icon: Icons.photo_library_rounded,
                text: '1. Select a photo of the licence and decode it here.',
              ),
              const SizedBox(height: 10),
              _webStep(
                theme,
                icon: Icons.edit_note_rounded,
                text: '2. Or type the licence details in manually.',
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                key: const ValueKey('webScannerSelectFromGalleryButton'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: theme.isDarkMode ? Colors.black : Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _isDecodingImage
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.image_rounded),
                label: Text(
                  _isDecodingImage ? 'READING PHOTO…' : 'SELECT FROM GALLERY',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _isDecodingImage ? null : _scanFromGalleryWeb,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('webScannerManualEntryButton'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.accentColor, width: 1.5),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Icon(Icons.edit_rounded, color: theme.accentColor),
                label: Text(
                  'ENTER LICENSE MANUALLY',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // The scanner is always opened from the manual form, so
                // popping returns the user to the fields they can type into.
                onPressed: () => Navigator.maybePop(context),
              ),
              if (_status != null) ...[
                const SizedBox(height: 20),
                Text(
                  _status!,
                  key: const ValueKey('webScannerStatusMessage'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFE6A15C)),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Tip: for automatic scanning, use the JagSpoor Android app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.subtitleColor, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One numbered "what you can do instead" row on the web fallback panel.
  Widget _webStep(ThemeController theme, {
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.accentColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: theme.textColor, fontSize: 14),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    // Browser: there is no ML Kit, so render the fallback panel instead of the
    // native camera pipeline. This is the branch that stops the "Unsupported
    // operation" error a web user previously hit.
    if (_webMode) {
      return _buildWebFallback(theme);
    }

    // Show loading while checking permission
    if (!_hasPermission && !_permissionDenied) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('SCAN LICENSE', style: TextStyle(color: theme.textColor)),
          backgroundColor: theme.backgroundColor,
          iconTheme: IconThemeData(color: theme.accentColor),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFE6A15C)),
        ),
      );
    }
    
    // Show permission denied screen
    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('SCAN LICENSE', style: TextStyle(color: theme.textColor)),
          backgroundColor: theme.backgroundColor,
          iconTheme: IconThemeData(color: theme.accentColor),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined, size: 72, color: Color(0xFFE6A15C)),
                const SizedBox(height: 16),
                const Text(
                  'Camera Permission Required',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Camera access is needed to scan license barcodes. Please enable camera permission in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE6A15C),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('OPEN SETTINGS'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _requestCameraPermission,
                  child: const Text('TRY AGAIN', style: TextStyle(color: Color(0xFFE6A15C))),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'SCAN LICENSE',
          style: TextStyle(
            color: theme.textColor,
            fontFamily: 'Mono',
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: theme.accentColor,
            ),
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
            errorBuilder:
                (context, error, child) => _CameraError(
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
            bottom: MediaQuery.of(context).padding.bottom + 32,
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
                  Text(
                    _status!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.amberAccent),
                  ),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.accentColor, width: 1.5),
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: Colors.black54,
                  ),
                  icon: Icon(
                    Icons.photo_library_rounded,
                    color: theme.accentColor,
                  ),
                  label: Text(
                    'SELECT FROM GALLERY',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
  const _CameraError({
    required this.error,
    required this.theme,
    required this.onPickGallery,
  });

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
          Icon(
            Icons.no_photography_rounded,
            size: 72,
            color: theme.accentColor,
          ),
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
            label: Text(
              'SELECT FROM GALLERY',
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: onPickGallery,
          ),
        ],
      ),
    );
  }
}
