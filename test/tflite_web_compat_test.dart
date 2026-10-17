import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/services/tflite/tflite_helper.dart';
import 'package:jagspoor/services/tflite/tflite_interface.dart';

/// Guards the web-compatibility contract for TensorFlow Lite.
///
/// `tflite_flutter` imports `dart:ffi`, which does not exist on the web, so
/// the package is isolated behind `tflite_helper.dart`'s conditional import.
/// These tests run on the VM (where the real implementation is selected) and
/// assert the structural invariants that keep `flutter build web` compiling.
void main() {
  group('tflite platform selection', () {
    test('the VM selects a supported (native) backend', () {
      // On the Dart VM (test runner / Android / iOS / desktop) `dart.library.html`
      // is false, so the mobile implementation is imported.
      expect(isTfliteSupported, isTrue);
      expect(tflitePlatform.isSupported, isTrue);
    });

    test('the backend is a TflitePlatform implementation', () {
      expect(tflitePlatform, isA<TflitePlatform>());
    });

    test('loadTfliteInterpreterFromAsset returns null for a missing asset', () async {
      // The helper must never throw for an unloadable asset — callers rely on
      // a null result to fall back to their heuristic scorer.
      final interpreter =
          await loadTfliteInterpreterFromAsset('assets/does_not_exist.tflite');
      expect(interpreter, isNull);
    });
  });
}
