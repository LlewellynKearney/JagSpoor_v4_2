import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Shared configuration for the licence PDF417 barcode scanner.
///
/// The SA firearm-licence PDF417 barcode is a dense, high-module-count 2D
/// symbol. The camera pipeline must be configured to give the ML Kit /
/// barhopper decoder enough pixels per module to resolve it, which is exactly
/// what the static gallery-photo path gets for free (the picked photo is
/// decoded at its full capture resolution).
class LicenseScannerConfig {
  LicenseScannerConfig._();

  /// The only symbology the licence scanner accepts.
  static const List<BarcodeFormat> formats = <BarcodeFormat>[
    BarcodeFormat.pdf417,
  ];

  /// Analysis-frame resolution requested for the live camera stream.
  ///
  /// When `cameraResolution` is null the plugin's CameraX `ImageAnalysis`
  /// defaults to a 640x480 analysis frame -- far too coarse to resolve the
  /// module width of a dense PDF417, which is why live streaming never
  /// decoded while a full-resolution gallery photo decoded instantly.
  static const Size liveCameraResolution = Size(1920, 1080);

  /// Analyze + emit every frame (no native duplicate suppression). The screen
  /// already dedupes with its own `_handled` guard, so `normal` gives the
  /// lowest first-decode latency. (The plugin forces `detectionTimeoutMs` to
  /// 0 for `noDuplicates`; `normal` keeps a 250 ms throttle, which is still
  /// effectively real-time and protects older devices.)
  static const DetectionSpeed detectionSpeed = DetectionSpeed.normal;

  /// Throttle between emissions in [DetectionSpeed.normal] mode.
  static const int detectionTimeoutMs = 250;

  /// Build the controller for the live camera preview stream, configured to
  /// decode with the same effectiveness as the static photo-upload path.
  static MobileScannerController buildLiveController() {
    return MobileScannerController(
      formats: formats,
      detectionSpeed: detectionSpeed,
      detectionTimeoutMs: detectionTimeoutMs,
      cameraResolution: liveCameraResolution,
    );
  }

  /// Build the controller used to analyze a static gallery photo. Shares the
  /// format restriction with the live controller so both paths decode
  /// identically.
  static MobileScannerController buildImageAnalysisController() {
    return MobileScannerController(
      formats: formats,
      autoStart: false,
    );
  }
}

/// Pure processing + parsing for licence barcode scans. Dependency-light
/// (mobile_scanner data objects only) so it is fully unit-testable without a
/// camera.
class LicenseScanProcessor {
  LicenseScanProcessor._();

  /// Extract a usable raw string from a decoded [Barcode].
  ///
  /// Prefers `rawValue`; falls back to decoding `rawBytes` as code units.
  ///
  /// The pre-fix screen bailed out whenever `rawBytes` was null, but the live
  /// ML Kit stream frequently returns PDF417 results with a populated
  /// `rawValue` and null `rawBytes` -- silently discarding decodes the
  /// gallery path surfaced. Returns null only when NEITHER representation is
  /// usable.
  static String? extractRawValue(Barcode barcode) {
    final String? rawValue = barcode.rawValue;
    if (rawValue != null && rawValue.trim().isNotEmpty) {
      return rawValue;
    }
    final Uint8List? bytes = barcode.rawBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final String decoded = String.fromCharCodes(bytes);
      if (decoded.trim().isNotEmpty) return decoded;
    }
    return null;
  }

  /// Return the first barcode in [capture] carrying a usable raw value, or
  /// null when the capture holds no decodable barcode. This is the single
  /// gate both the live-stream callback and the gallery-analysis path pass
  /// through before finishing.
  static Barcode? firstReadable(BarcodeCapture capture) {
    for (final Barcode barcode in capture.barcodes) {
      if (extractRawValue(barcode) != null) return barcode;
    }
    return null;
  }

  /// SA firearm-licence PDF417 is pipe-delimited with fixed positions. Map the
  /// known fields; "NONE" placeholders become empty. Positions confirmed
  /// against a real EMC scan; #2 is intentionally ignored and #7/#18 are
  /// serial/licence.
  static Map<String, dynamic> parseLicense(String raw) {
    final List<String> parts =
        raw.split('|').map((String p) => p.trim()).toList();
    String at(int i) {
      if (i < 0 || i >= parts.length) return '';
      final String v = parts[i];
      return v.toUpperCase() == 'NONE' ? '' : v;
    }

    return <String, dynamic>{
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
}
