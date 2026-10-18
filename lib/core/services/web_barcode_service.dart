/// Conditional browser barcode decoder for the web build.
///
/// The licence scanner's live camera path is backed by ML Kit / barhopper,
/// which only exists on Android and iOS. On the web the app must not attempt
/// it, and `MobileScannerController.analyzeImage()` explicitly throws
/// `UnsupportedError` there. This façade exposes a browser-side decoder so the
/// "SELECT FROM GALLERY" path still works in a browser.
///
/// The web implementation uses the ZXing library — the same library
/// `mobile_scanner` itself loads on the web — which decodes PDF417.
///
/// The conditional import keeps `dart:js_interop` / `package:web` out of the
/// native build, mirroring `lib/features/billing/payfast_form.dart`.
library;

import 'web_barcode_service_stub.dart'
    if (dart.library.js_interop) 'web_barcode_service_web.dart';

/// Whether a barcode image can be decoded in the current build.
///
/// `true` on the web, `false` on Android / iOS (which use ML Kit instead).
bool get isWebBarcodeDecodingAvailable => isWebBarcodeDecodingAvailableImpl;

/// Decode a PDF417 payload from [imageUrl] in the browser.
///
/// [imageUrl] is any URL the browser can load — a `blob:` object URL from
/// `image_picker`, a `data:` URL, or an `http(s)` URL.
///
/// Returns the decoded text, or `null` when the library cannot be loaded, the
/// image holds no readable PDF417 symbol, or anything else fails. Never
/// throws, so callers can surface a single "no barcode found" message.
Future<String?> decodePdf417FromImageUrl(String imageUrl) =>
    decodePdf417FromImageUrlImpl(imageUrl);
