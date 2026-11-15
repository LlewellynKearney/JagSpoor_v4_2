/// Native CSV delivery — writes the file to a temp directory and opens the
/// platform share sheet (`share_plus`), so an Android / iOS operator can save
/// the export or forward it (Gmail, Drive, WhatsApp, …).
///
/// `package:web` is intentionally NOT imported here — this file is compiled
/// into native builds, where the DOM does not exist.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [content] to `<temp>/<fileName>` and opens the share sheet.
///
/// Returns `false` (never throws) when the temp directory or the share sheet
/// is unavailable, so the caller can show a clear failure message instead of
/// crashing the portal.
Future<bool> deliverCsvImpl({
  required String fileName,
  required String content,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final sanitized = fileName.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final file = File('${dir.path}/$sanitized');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: sanitized,
      text: 'JagSpoor users export',
    );
    return true;
  } catch (e) {
    debugPrint('deliverCsv (native) failed: $e');
    return false;
  }
}
