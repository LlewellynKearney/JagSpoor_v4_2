import 'tflite_interface.dart';

/// Web backend stub.
///
/// TensorFlow Lite has no web implementation (the plugin depends on
/// `dart:ffi`), so model loading is a no-op. Callers detect `isSupported ==
/// false` and use their deterministic heuristic path, which keeps the spoor
/// identifier functional in the browser instead of failing to compile.
class TflitePlatformImpl implements TflitePlatform {
  const TflitePlatformImpl();

  @override
  bool get isSupported => false;

  @override
  Future<TfliteInterpreter?> loadFromAsset(String assetPath) async => null;
}
