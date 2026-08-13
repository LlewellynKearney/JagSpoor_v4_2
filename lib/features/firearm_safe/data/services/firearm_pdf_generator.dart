import 'package:pdf/widgets.dart' as pw;
import '../../../../core/services/pdf_document_engine.dart';

/// Generates the Digital Firearm Safe registry PDF using the shared
/// [JagSpoorPdfDocument] engine (branded header/footer) and [JagSpoorPdfTheme]
/// table styles. All field labels and table cell values are normalized to
/// ASCII via [_toAscii] so the default PDF font never renders missing-glyph
/// blocks.
class FirearmPdfGenerator {
  static Future<void> generateAndShowFirearmsPdf(
    List<Map<String, String>> firearms,
  ) async {
    final now = DateTime.now();
    final docId =
        'FSA-${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}';

    final doc = await JagSpoorPdfDocument.create(
      title: 'Digital Firearm Safe - Registry',
      documentId: docId,
    );

    // Build the registry rows: make, model, serial, FCA licence section,
    // caliber, barrel length. Each value is sanitized to ASCII.
    final rows = <List<String>>[
      for (final f in firearms)
        [
          _toAscii(f['make'] ?? 'Unknown'),
          _toAscii(f['model'] ?? ''),
          _toAscii(f['serial'] ?? ''),
          _toAscii(f['licenceSection'] ?? f['licenseSection'] ?? ''),
          _toAscii(f['caliber'] ?? ''),
          _toAscii(f['barrelLength'] ?? ''),
        ],
    ];

    doc.addPage(
      content: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          JagSpoorPdfTheme.sectionBar('FIREARM REGISTRY'),
          JagSpoorPdfTheme.dataTable(
            headers: const [
              'Make',
              'Model',
              'Serial Number',
              'License Section',
              'Caliber',
              'Barrel Length',
            ],
            rows: rows,
            columnWidths: const [95, 80, 95, 110, 70, 75],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Total Firearms: ${firearms.length}',
            style: JagSpoorPdfTheme.caption,
          ),
        ],
      ),
    );

    await doc.saveAndShare(
      filename: 'digital_firearm_safe_registry',
      shareSubject: 'Digital Firearm Safe - Registry',
      shareText: 'JagSpoor Digital Firearm Safe registry (${firearms.length} '
          'firearms).',
    );
  }

  /// Normalizes a string to printable ASCII so the default PDF font never
  /// renders a missing-glyph block. Common punctuation and Latin-1
  /// diacritics are transliterated to readable ASCII; any remaining
  /// non-ASCII character is replaced with '?'.
  static String _toAscii(String input) {
    var s = input;
    // Box-drawing / block glyphs (the very characters that render as blocks).
    s = s.replaceAll('█', '').replaceAll('│', '|').replaceAll('─', '-');
    // Smart punctuation to ASCII equivalents.
    s = s
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('•', '*')
        .replaceAll('…', '...');
    // Common Latin-1 diacritics to base letters.
    const diacritics = {
      'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Æ': 'AE',
      'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', 'Ì': 'I', 'Í': 'I',
      'Î': 'I', 'Ï': 'I', 'Ñ': 'N', 'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O',
      'Ö': 'O', 'Ø': 'O', 'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ý': 'Y',
      'ß': 'ss', 'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
      'æ': 'ae', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i',
      'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o',
      'õ': 'o', 'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
    };
    diacritics.forEach((k, v) => s = s.replaceAll(k, v));
    // Replace any remaining non-ASCII with '?'.
    return s.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
