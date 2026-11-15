/// Cross-platform CSV delivery façade.
///
/// Mirrors the repo's established conditional-import pattern
/// (`lib/core/router/browser_path.dart`, `lib/core/services/web_barcode_service.dart`,
/// `lib/features/billing/payfast_form.dart`): the web build downloads the file
/// through the browser (a Blob + an anchor with the `download` attribute),
/// while native builds write the file to a temporary directory and open the
/// platform share sheet so the operator can save it or send it on.
///
/// The conditional import keeps `package:web` / `dart:js_interop` out of the
/// native build entirely.
library;

import 'dart:async';

import 'csv_export_stub.dart'
    if (dart.library.js_interop) 'csv_export_web.dart';

/// Delivers a CSV document named [fileName] with the given [content].
///
/// Returns `true` when the file was handed off successfully, `false` when the
/// platform refused the hand-off (the caller surfaces a failure snackbar).
/// Never throws.
Future<bool> deliverCsv({
  required String fileName,
  required String content,
}) =>
    deliverCsvImpl(fileName: fileName, content: content);
