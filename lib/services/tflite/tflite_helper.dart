/// Conditional TensorFlow Lite loader.
///
/// `tflite_flutter` (and therefore `dart:ffi`) only exists on native
/// platforms, so the import below resolves to the real implementation on
/// Android / iOS / desktop and to a no-op stub on the web. Nothing outside
/// `lib/services/tflite/` may import `package:tflite_flutter` directly —
/// doing so breaks `flutter build web`.
///
/// `dart.library.html` is the discriminator used by the dart2js web compiler,
/// which is what `flutter build web` uses.
library;

import 'tflite_interface.dart';
import 'tflite_mobile.dart' if (dart.library.html) 'tflite_web.dart';

export 'tflite_interface.dart' show TfliteInterpreter, TflitePlatform;

/// The backend selected for the current platform.
const TflitePlatform tflitePlatform = TflitePlatformImpl();

/// Whether real on-device inference is available in this build.
bool get isTfliteSupported => tflitePlatform.isSupported;

/// Loads a `.tflite` model from the Flutter asset bundle.
///
/// Returns `null` on the web (no LiteRT runtime) or when the asset cannot be
/// loaded, so callers can degrade to a heuristic path.
Future<TfliteInterpreter?> loadTfliteInterpreterFromAsset(String assetPath) async {
  if (!tflitePlatform.isSupported) return null;
  try {
    return await tflitePlatform.loadFromAsset(assetPath);
  } catch (_) {
    return null;
  }
}
