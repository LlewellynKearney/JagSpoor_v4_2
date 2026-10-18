/// Browser barcode decoder (web build only).
///
/// Decodes a PDF417 payload from an image URL using the ZXing JavaScript
/// library — the same decoder `mobile_scanner` loads for its own web camera
/// path. ML Kit / barhopper is Android + iOS only, so this is the only way to
/// read a licence barcode inside a browser.
///
/// The library is served from the app's own origin (`vendor/zxing.min.js`,
/// copied out of `web/`) so an offline or CDN-blocked browser still decodes.
/// The public CDN is kept as a fallback.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Browsers can always attempt a decode; failures surface as a `null` result.
const bool isWebBarcodeDecodingAvailableImpl = true;

/// Id of the injected `<script>` tag, so the library is loaded at most once.
///
/// Public so `web/index.html` and the contract tests can assert the vendored
/// copy is the file this loader references.
const String zxingScriptId = 'jagspoor-zxing-barcode-reader';

/// Candidate script URLs, tried in order. The bundled copy is first so the
/// scanner keeps working offline; the CDN mirrors what `mobile_scanner`
/// already fetches for the live web camera.
const List<String> _scriptUrls = <String>[
  'vendor/zxing.min.js',
  'https://unpkg.com/@zxing/library@0.21.3',
];

/// Upper bound on how long the library load may take before the caller shows
/// its "could not read the image" message instead of hanging.
const Duration _loadTimeout = Duration(seconds: 20);

/// Decode a PDF417 payload from [imageUrl].
///
/// [imageUrl] may be a `blob:` object URL (what `image_picker` returns on the
/// web), a `data:` URL, or an `http(s)` URL. Returns the decoded text, or
/// `null` when the library is unavailable, the image holds no readable PDF417
/// symbol, or anything else goes wrong. Never throws.
Future<String?> decodePdf417FromImageUrlImpl(String imageUrl) async {
  if (imageUrl.trim().isEmpty) {
    return null;
  }

  try {
    final JSObject? zxing = await _ensureLibrary();
    if (zxing == null) {
      return null;
    }

    final JSObject? reader = _buildReader(zxing);
    if (reader == null) {
      return null;
    }

    final JSPromise<JSAny?> pending = reader
        .callMethod<JSPromise<JSAny?>>('decodeFromImageUrl'.toJS, imageUrl.toJS);

    final JSAny? result = await pending.toDart;
    return _resultText(result);
  } catch (_) {
    // A rejected decode (no symbol found) and any interop/load failure are
    // reported identically to the caller: "no barcode in that image".
    return null;
  }
}

/// Read the decoded text out of a ZXing `Result`.
///
/// ZXing exposes both a `text` field and a `getText()` accessor; try the field
/// first and fall back to the method so a library version bump cannot silently
/// break decoding.
String? _resultText(JSAny? result) {
  if (result == null || result.isUndefinedOrNull) {
    return null;
  }

  final JSObject obj = result as JSObject;

  final JSAny? direct = obj.getProperty<JSAny?>('text'.toJS);
  final String? viaField = direct?.dartify() as String?;
  if (viaField != null && viaField.trim().isNotEmpty) {
    return viaField;
  }

  final JSFunction? getter = obj.getProperty<JSFunction?>('getText'.toJS);
  if (getter != null && getter.isDefinedAndNotNull) {
    final JSAny? viaMethod = getter.callAsFunction(obj);
    final String? text = viaMethod?.dartify() as String?;
    if (text != null && text.trim().isNotEmpty) {
      return text;
    }
  }

  return null;
}

/// Build a `BrowserMultiFormatReader` restricted to PDF417.
///
/// `DecodeHintType.POSSIBLE_FORMATS` (2) narrows the search to PDF417 — the
/// symbology on SA licences — and `TRY_HARDER` (3) enables the slower,
/// higher-recall scan a dense barcode needs. ZXing reads hints from a real JS
/// `Map`, so one is constructed through the global `Map` constructor.
JSObject? _buildReader(JSObject zxing) {
  final JSObject? barcodeFormat =
      zxing.getProperty<JSObject?>('BarcodeFormat'.toJS);
  final JSObject? decodeHintType =
      zxing.getProperty<JSObject?>('DecodeHintType'.toJS);
  final JSFunction? readerCtor =
      zxing.getProperty<JSFunction?>('BrowserMultiFormatReader'.toJS);

  if (barcodeFormat == null ||
      decodeHintType == null ||
      readerCtor == null ||
      readerCtor.isUndefinedOrNull) {
    return null;
  }

  final JSAny? pdf417 = barcodeFormat.getProperty<JSAny?>('PDF_417'.toJS);
  final JSAny? possibleFormats =
      decodeHintType.getProperty<JSAny?>('POSSIBLE_FORMATS'.toJS);
  final JSAny? tryHarder =
      decodeHintType.getProperty<JSAny?>('TRY_HARDER'.toJS);

  if (pdf417 == null || possibleFormats == null || tryHarder == null) {
    return null;
  }

  final JSFunction? mapCtor =
      globalContext.getProperty<JSFunction?>('Map'.toJS);
  if (mapCtor == null || mapCtor.isUndefinedOrNull) {
    return null;
  }

  final JSObject hints = mapCtor.callAsConstructor<JSObject>();
  hints.callMethod<JSAny?>('set'.toJS, possibleFormats, <JSAny?>[pdf417].toJS);
  hints.callMethod<JSAny?>('set'.toJS, tryHarder, true.toJS);

  return readerCtor.callAsConstructor<JSObject>(hints);
}

/// Resolve the ZXing namespace, loading the library first when needed.
Future<JSObject?> _ensureLibrary() async {
  final JSObject? loaded = _zxingNamespace();
  if (loaded != null) {
    return loaded;
  }

  for (final String url in _scriptUrls) {
    await _loadScript(url);
    final JSObject? namespace = _zxingNamespace();
    if (namespace != null) {
      return namespace;
    }
  }

  return null;
}

/// The global `ZXing` namespace, or null when the library is not loaded yet.
JSObject? _zxingNamespace() {
  final JSAny? namespace = globalContext.getProperty<JSAny?>('ZXing'.toJS);
  if (namespace == null || namespace.isUndefinedOrNull) {
    return null;
  }
  return namespace as JSObject;
}

/// Inject a `<script>` for [url] and wait for it to load.
///
/// Resolves either way: a failed load is not an error, because the next
/// candidate URL is tried. A missing `document.head` also resolves so the
/// caller reports "no barcode" rather than hanging.
Future<void> _loadScript(String url) async {
  final web.HTMLHeadElement? head = web.document.head;
  if (head == null) {
    return;
  }

  // Reuse an in-flight/loaded tag so concurrent calls cannot double-inject.
  final web.Element? existing = web.document.querySelector(
    'script[data-jagspoor-src="$url"]',
  );
  if (existing != null) {
    return;
  }

  final Completer<void> completer = Completer<void>();

  final web.HTMLScriptElement script = web.HTMLScriptElement()
    ..id = zxingScriptId
    ..setAttribute('data-jagspoor-src', url)
    ..src = url
    ..async = true;

  script.onload = (web.Event _) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }.toJS;

  script.onerror = (web.Event _) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }.toJS;

  head.appendChild(script);

  await completer.future.timeout(_loadTimeout, onTimeout: () {});
}
