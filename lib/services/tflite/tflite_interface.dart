/// Platform-agnostic TensorFlow Lite surface.
///
/// `tflite_flutter` imports `dart:ffi`, which does not exist on the web, so
/// the package cannot be referenced from code that must also compile for
/// `flutter build web`. The spoor classifier therefore talks to TensorFlow
/// Lite only through this abstraction, and `tflite_helper.dart` selects the
/// real (mobile/desktop) or stub (web) implementation at compile time.
library;

/// A loaded TensorFlow Lite model ready for inference.
abstract class TfliteInterpreter {
  /// Runs one inference pass.
  ///
  /// [input] and [output] follow the `tflite_flutter` convention: nested
  /// `List`s shaped `[1, height, width, channels]` for the input and
  /// `[1, labelCount]` for the output. The output buffer is written in place.
  void run(Object input, Object output);

  /// Releases the underlying interpreter. Safe to call more than once.
  void close();
}

/// The platform-specific TensorFlow Lite backend.
abstract class TflitePlatform {
  /// Whether real on-device inference is available on this platform.
  bool get isSupported;

  /// Loads a `.tflite` model from the Flutter asset bundle.
  ///
  /// Returns `null` when the platform cannot run inference (web) or the asset
  /// cannot be loaded, so callers fall back to their heuristic path instead of
  /// crashing.
  Future<TfliteInterpreter?> loadFromAsset(String assetPath);
}
