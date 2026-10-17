import 'package:tflite_flutter/tflite_flutter.dart' as tflite;

import 'tflite_interface.dart';

/// TensorFlow Lite backend for Android / iOS / macOS / Windows / Linux, where
/// `dart:ffi` is available and the native LiteRT runtime can be loaded.
class TflitePlatformImpl implements TflitePlatform {
  const TflitePlatformImpl();

  @override
  bool get isSupported => true;

  @override
  Future<TfliteInterpreter?> loadFromAsset(String assetPath) async {
    final interpreter = await tflite.Interpreter.fromAsset(assetPath);
    return _FfiInterpreter(interpreter);
  }
}

class _FfiInterpreter implements TfliteInterpreter {
  _FfiInterpreter(this._interpreter);

  final tflite.Interpreter _interpreter;

  @override
  void run(Object input, Object output) => _interpreter.run(input, output);

  @override
  void close() => _interpreter.close();
}
