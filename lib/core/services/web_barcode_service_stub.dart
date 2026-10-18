/// Non-web stub for the browser barcode decoder.
///
/// Android / iOS decode licence PDF417 with the ML Kit pipeline inside
/// `mobile_scanner`, so there is no browser decoder to expose here. The stub
/// keeps `web_barcode_service.dart`'s conditional import resolvable on every
/// platform without pulling `dart:js_interop` into the native build.
library;

/// Always `false` off the web — the native ML Kit path is used instead.
const bool isWebBarcodeDecodingAvailableImpl = false;

/// Always `null` off the web. Callers only reach this on the web build.
Future<String?> decodePdf417FromImageUrlImpl(String imageUrl) async => null;
