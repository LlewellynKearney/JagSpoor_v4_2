/// Browser CSV delivery (web build only).
///
/// Wraps [content] in a `Blob`, creates an object URL, and clicks a temporary
/// anchor carrying the `download` attribute — the standard way to trigger a
/// file download from a Flutter web app. The object URL is revoked afterwards
/// so the blob does not leak for the page's lifetime.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [content] as [fileName] through the browser.
///
/// Returns `true` on a successful hand-off, `false` when the DOM hand-off
/// throws (never propagates).
Future<bool> deliverCsvImpl({
  required String fileName,
  required String content,
}) async {
  try {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
