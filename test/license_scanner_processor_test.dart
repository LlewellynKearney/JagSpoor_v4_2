import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/license_scanner_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/license_scan_processor.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  group('LicenseScannerConfig', () {
    test('restricts scanning to PDF417', () {
      expect(LicenseScannerConfig.formats, <BarcodeFormat>[
        BarcodeFormat.pdf417,
      ]);
    });

    test('live analysis resolution exceeds the 640x480 plugin default', () {
      // The plugin defaults CameraX ImageAnalysis to 640x480 when
      // cameraResolution is null -- too coarse for a dense licence PDF417.
      // The live stream must request a much higher analysis frame so its
      // decode effectiveness matches the full-resolution gallery path.
      expect(LicenseScannerConfig.liveCameraResolution.width, 1920);
      expect(LicenseScannerConfig.liveCameraResolution.height, 1080);
      expect(
        LicenseScannerConfig.liveCameraResolution.width *
            LicenseScannerConfig.liveCameraResolution.height,
        greaterThan(640 * 480 * 3),
      );
    });

    test('live controller uses the robust real-time decoding parameters', () {
      final MobileScannerController controller =
          LicenseScannerConfig.buildLiveController();
      addTearDown(controller.dispose);

      expect(controller.formats, LicenseScannerConfig.formats);
      expect(controller.cameraResolution,
          LicenseScannerConfig.liveCameraResolution);
      // Analyze + emit every frame (the screen dedupes with its own guard);
      // the pre-fix noDuplicates mode forced detectionTimeoutMs to 0 and
      // routed through the native duplicate filter.
      expect(controller.detectionSpeed, DetectionSpeed.normal);
      expect(controller.detectionTimeoutMs, 250);
    });

    test('image-analysis controller shares the live format restriction', () {
      final MobileScannerController controller =
          LicenseScannerConfig.buildImageAnalysisController();
      addTearDown(controller.dispose);

      expect(controller.formats, LicenseScannerConfig.formats);
      expect(controller.autoStart, isFalse);
    });

    test('live and gallery paths decode the same symbology', () {
      final MobileScannerController live =
          LicenseScannerConfig.buildLiveController();
      final MobileScannerController still =
          LicenseScannerConfig.buildImageAnalysisController();
      addTearDown(live.dispose);
      addTearDown(still.dispose);

      expect(live.formats, still.formats);
    });
  });

  group('LicenseScanProcessor.extractRawValue', () {
    test('accepts a rawValue-only barcode (null rawBytes)', () {
      // REGRESSION GUARD: the pre-fix screen bailed out whenever rawBytes was
      // null, silently discarding live-stream decodes that only carry
      // rawValue. The extractor must accept this shape.
      const Barcode barcode = Barcode(
        format: BarcodeFormat.pdf417,
        rawValue: 'A|B|C',
      );
      expect(LicenseScanProcessor.extractRawValue(barcode), 'A|B|C');
    });

    test('decodes rawBytes when rawValue is absent', () {
      final Barcode barcode = Barcode(
        format: BarcodeFormat.pdf417,
        rawBytes: Uint8List.fromList('X|Y'.codeUnits),
      );
      expect(LicenseScanProcessor.extractRawValue(barcode), 'X|Y');
    });

    test('prefers rawValue over rawBytes when both are present', () {
      final Barcode barcode = Barcode(
        format: BarcodeFormat.pdf417,
        rawValue: 'value',
        rawBytes: Uint8List.fromList('bytes'.codeUnits),
      );
      expect(LicenseScanProcessor.extractRawValue(barcode), 'value');
    });

    test('falls back to rawBytes when rawValue is blank', () {
      final Barcode barcode = Barcode(
        format: BarcodeFormat.pdf417,
        rawValue: '   ',
        rawBytes: Uint8List.fromList('Z'.codeUnits),
      );
      expect(LicenseScanProcessor.extractRawValue(barcode), 'Z');
    });

    test('returns null when neither representation is usable', () {
      expect(
        LicenseScanProcessor.extractRawValue(const Barcode()),
        isNull,
      );
      expect(
        LicenseScanProcessor.extractRawValue(
          const Barcode(rawValue: '   '),
        ),
        isNull,
      );
      expect(
        LicenseScanProcessor.extractRawValue(
          Barcode(rawBytes: Uint8List(0)),
        ),
        isNull,
      );
    });
  });

  group('LicenseScanProcessor.firstReadable', () {
    test('returns null for an empty capture', () {
      expect(
        LicenseScanProcessor.firstReadable(const BarcodeCapture()),
        isNull,
      );
    });

    test('returns the readable barcode from a capture', () {
      const Barcode readable = Barcode(
        format: BarcodeFormat.pdf417,
        rawValue: 'L|I|C',
      );
      const BarcodeCapture capture = BarcodeCapture(barcodes: [readable]);
      expect(LicenseScanProcessor.firstReadable(capture), same(readable));
    });

    test('skips unreadable barcodes and returns the first readable one', () {
      const Barcode junk = Barcode(); // no rawValue, no rawBytes
      const Barcode readable = Barcode(rawValue: 'OK');
      const BarcodeCapture capture = BarcodeCapture(
        barcodes: [junk, readable],
      );
      expect(LicenseScanProcessor.firstReadable(capture), same(readable));
    });

    test('returns null when every barcode is unreadable', () {
      const BarcodeCapture capture = BarcodeCapture(
        barcodes: [Barcode(), Barcode(rawValue: '  ')],
      );
      expect(LicenseScanProcessor.firstReadable(capture), isNull);
    });
  });

  group('LicenseScanProcessor.parseLicense', () {
    test('maps the fixed pipe-delimited positions', () {
      final List<String> parts = List<String>.filled(19, 'NONE');
      parts[0] = 'LICENCE TO POSSESS';
      parts[1] = '9001015009087';
      parts[3] = 'VAN DER MERWE J';
      parts[4] = 'SECTION 15';
      parts[5] = '2020-01-15';
      parts[6] = '2025-01-14';
      parts[7] = 'SN123456';
      parts[8] = 'RIFLE';
      parts[9] = 'TIKKA';
      parts[10] = 'T3X';
      parts[11] = '.308 WIN';
      parts[17] = 'TIKKA OY';
      parts[18] = 'LIC-2020-001';

      final Map<String, dynamic> parsed =
          LicenseScanProcessor.parseLicense(parts.join('|'));

      expect(parsed['isScanned'], isTrue);
      expect(parsed['licenceType'], 'LICENCE TO POSSESS');
      expect(parsed['idNumber'], '9001015009087');
      expect(parsed['holderName'], 'VAN DER MERWE J');
      expect(parsed['licenceSection'], 'SECTION 15');
      expect(parsed['issueDate'], '2020-01-15');
      expect(parsed['expiryDate'], '2025-01-14');
      expect(parsed['serial'], 'SN123456');
      expect(parsed['firearmType'], 'RIFLE');
      expect(parsed['make'], 'TIKKA');
      expect(parsed['model'], 'T3X');
      expect(parsed['caliber'], '.308 WIN');
      expect(parsed['manufacturer'], 'TIKKA OY');
      expect(parsed['licenseNumber'], 'LIC-2020-001');
      expect(parsed['raw'], parts.join('|'));
    });

    test('collapses NONE placeholders to empty strings', () {
      final List<String> parts = List<String>.filled(19, 'NONE');
      parts[9] = 'SAKO';
      final Map<String, dynamic> parsed =
          LicenseScanProcessor.parseLicense(parts.join('|'));

      expect(parsed['licenceType'], '');
      expect(parsed['idNumber'], '');
      expect(parsed['serial'], '');
      expect(parsed['make'], 'SAKO');
    });

    test('tolerates a short payload without throwing', () {
      final Map<String, dynamic> parsed =
          LicenseScanProcessor.parseLicense('A|B');
      expect(parsed['licenceType'], 'A');
      expect(parsed['idNumber'], 'B');
      expect(parsed['holderName'], '');
      expect(parsed['licenseNumber'], '');
      expect(parsed['raw'], 'A|B');
    });

    test('tolerates an empty payload', () {
      final Map<String, dynamic> parsed =
          LicenseScanProcessor.parseLicense('');
      expect(parsed['isScanned'], isTrue);
      expect(parsed['licenceType'], '');
      expect(parsed['raw'], '');
    });

    test('trims whitespace around fields', () {
      final Map<String, dynamic> parsed =
          LicenseScanProcessor.parseLicense(' T | 9001015009087 ');
      expect(parsed['licenceType'], 'T');
      expect(parsed['idNumber'], '9001015009087');
    });
  });

  group('LicenseScannerScreen (widget)', () {
    const MethodChannel permissionChannel = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );

    void mockPermissionChannel({
      required int statusResult,
      int? requestResult,
    }) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (MethodCall call) async {
        if (call.method == 'checkPermissionStatus') return statusResult;
        if (call.method == 'requestPermissions') {
          return <int, int>{1: requestResult ?? statusResult};
        }
        return null;
      });
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, null);
    });

    Future<void> pumpScannerScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LicenseScannerScreen(theme: ThemeController())),
      );
      // Bounded pumps: the indeterminate CircularProgressIndicator shown
      // before permission resolution never settles, and the mocked channel
      // resolves after a microtask or two.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
      'shows the actionable permission UI when camera access is denied',
      (WidgetTester tester) async {
        // Regression guard: a plain (non-permanent) denial previously left
        // the screen stuck on an infinite loading spinner with no way
        // forward.
        mockPermissionChannel(statusResult: 0, requestResult: 0);
        await pumpScannerScreen(tester);

        expect(find.text('Camera Permission Required'), findsOneWidget);
        expect(find.text('OPEN SETTINGS'), findsOneWidget);
        expect(find.text('TRY AGAIN'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'shows the permission UI when camera access is permanently denied',
      (WidgetTester tester) async {
        mockPermissionChannel(statusResult: 4);
        await pumpScannerScreen(tester);

        expect(find.text('Camera Permission Required'), findsOneWidget);
        expect(find.text('OPEN SETTINGS'), findsOneWidget);
        expect(find.text('TRY AGAIN'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'renders the scanner surface (live view or fallback) once granted',
      (WidgetTester tester) async {
        // In the test harness the camera/ML Kit platform channels have no
        // handlers, so the scanner either mounts the live view or the
        // errorBuilder fallback; both prove the granted branch rendered
        // without crashing or hanging on the pre-resolution spinner.
        mockPermissionChannel(statusResult: 1);
        await pumpScannerScreen(tester);

        expect(find.byType(CircularProgressIndicator), findsNothing);
        final bool liveView = find.byType(MobileScanner).evaluate().isNotEmpty;
        final bool errorFallback =
            find.text('SELECT FROM GALLERY').evaluate().isNotEmpty;
        expect(liveView || errorFallback, isTrue);
      },
    );
  });
}
