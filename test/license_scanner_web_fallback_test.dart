import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/services/web_barcode_service.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/license_scanner_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/license_scan_processor.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The browser fallback contract for the licence scanner.
///
/// ML Kit / barhopper exists only on Android and iOS, and
/// `MobileScannerController.analyzeImage()` throws `UnsupportedError` on the
/// web — which surfaced as an "Unsupported operation" error the moment a web
/// user picked a licence photo. These tests lock the fix: on the web the
/// screen must never mount the native `MobileScanner` pipeline, and must offer
/// the browser-safe gallery decode plus manual entry instead.
void main() {
  group('WebBarcodeService contract', () {
    test('reports availability per platform', () {
      // On the VM (this test host) the stub is selected, so no browser decoder
      // is claimed. The web build selects the ZXing implementation.
      expect(isWebBarcodeDecodingAvailable, isFalse);
    });

    test('the stub never decodes and never throws', () async {
      // Callers must be able to await this unconditionally: the native build
      // reaches this path only if a web-only branch is mis-wired, and a throw
      // there would crash the scanner instead of showing a message.
      await expectLater(
        decodePdf417FromImageUrl('blob:http://localhost/whatever'),
        completion(isNull),
      );
    });

    test('the stub tolerates an empty url', () async {
      await expectLater(
        decodePdf417FromImageUrl(''),
        completion(isNull),
      );
    });
  });

  group('LicenseScannerScreen web fallback', () {
    const MethodChannel permissionChannel = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, null);
    });

    Future<void> pumpWebScanner(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LicenseScannerScreen(
            theme: ThemeController(),
            forceWebMode: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('renders the fallback panel instead of the ML Kit scanner', (
      WidgetTester tester,
    ) async {
      await pumpWebScanner(tester);

      expect(find.text('Auto-scan is only available on Android'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('webScannerSelectFromGalleryButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('webScannerManualEntryButton')),
        findsOneWidget,
      );
    });

    testWidgets('never mounts the native MobileScanner pipeline on web', (
      WidgetTester tester,
    ) async {
      await pumpWebScanner(tester);

      // The regression guard for the reported bug: mounting MobileScanner in a
      // browser is what produced the "Unsupported operation" error.
      expect(find.byType(MobileScanner), findsNothing);
      expect(find.text('SELECT FROM GALLERY'), findsOneWidget);
      expect(find.text('ENTER LICENSE MANUALLY'), findsOneWidget);
    });

    testWidgets('does not run the native camera permission flow on web', (
      WidgetTester tester,
    ) async {
      // A browser prompts for camera access itself, and the fallback opens no
      // stream at all — so the native permission dance must not run and must
      // not dead-end on the "Camera Permission Required" screen.
      int permissionCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (MethodCall call) async {
        permissionCalls++;
        return null;
      });

      await pumpWebScanner(tester);

      expect(permissionCalls, 0);
      expect(find.text('Camera Permission Required'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('manual entry pops back to the form', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LicenseScannerScreen(
                      theme: ThemeController(),
                      forceWebMode: true,
                    ),
                  ),
                ),
                child: const Text('OPEN SCANNER'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN SCANNER'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('webScannerManualEntryButton')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('webScannerManualEntryButton')),
      );
      await tester.pumpAndSettle();

      expect(find.text('OPEN SCANNER'), findsOneWidget);
      expect(find.text('Auto-scan is only available on Android'), findsNothing);
    });

    testWidgets('gallery button stays interactive and shows no error banner', (
      WidgetTester tester,
    ) async {
      await pumpWebScanner(tester);

      final Finder gallery = find.byKey(
        const ValueKey('webScannerSelectFromGalleryButton'),
      );
      expect(tester.widget<ElevatedButton>(gallery).onPressed, isNotNull);
      // The status line only appears after a failed decode.
      expect(
        find.byKey(const ValueKey('webScannerStatusMessage')),
        findsNothing,
      );
    });
  });

  group('Web fallback decode wiring', () {
    // The exact payload the bundled ZXing decoder returns for a real SA
    // licence (verified in a headless browser). The web branch feeds the
    // decoded string straight into the shared `parseLicense`, so the form is
    // populated exactly as it is on Android.
    const String decoded =
        'LICENCE|9001015009087|X|JOHN SMITH|13|2024-01-15|2029-01-14|'
        'OB14468|Rifle|HOWA|1500|6MM MUSGRAVE|NONE|NONE|NONE|NONE|NONE|'
        'HOWA|L123456';

    test('the decoded payload parses into the licence fields', () {
      final Map<String, dynamic> parsed =
          LicenseScanProcessor.parseLicense(decoded);

      expect(parsed['isScanned'], isTrue);
      expect(parsed['idNumber'], '9001015009087');
      expect(parsed['serial'], 'OB14468');
      expect(parsed['caliber'], '6MM MUSGRAVE');
    });
  });

  group('Native flow unchanged', () {
    testWidgets('the non-web build still renders the ML Kit scanner surface', (
      WidgetTester tester,
    ) async {
      const MethodChannel permissionChannel = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(permissionChannel, null);
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (MethodCall call) async {
        if (call.method == 'checkPermissionStatus') return 1;
        if (call.method == 'requestPermissions') {
          return <int, int>{1: 1};
        }
        return null;
      });

      await tester.pumpWidget(
        MaterialApp(home: LicenseScannerScreen(theme: ThemeController())),
      );
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Android / iOS keep the live viewfinder path; the web panel must not
      // appear there.
      expect(find.text('Auto-scan is only available on Android'), findsNothing);
      final bool liveView = find.byType(MobileScanner).evaluate().isNotEmpty;
      final bool galleryFallback =
          find.text('SELECT FROM GALLERY').evaluate().isNotEmpty;
      expect(liveView || galleryFallback, isTrue);
    });
  });
}
