import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';
import '../../../core/utils/measurement_formatter.dart';

class MeatProcessingExporter {
  // Compile processing requirements into a formal, printable PDF document matrix
  Future<void> generateAndShareManifest({
    required String carcassTag,
    required String hunterName,
    required String species,
    required double hangingWeight,
    required List<String>
    portionsRequested, // e.g., ["Biltong", "Droëwors", "Steaks"]
    required String spicePreference, // e.g., "Traditional Coriander & Vinegar"
    required String
    specialInstructions, // e.g., "Keep skins for taxidermy, wrap backstraps separate"
    List<String> allPortionOptions = const [],
  }) async {
    final doc = await JagSpoorPdfDocument.create(
      title: 'Slaughterhouse Manifest',
      documentId: carcassTag,
    );

    doc.addPage(
      margin: 30,
      content: _buildContent(
        carcassTag: carcassTag,
        hunterName: hunterName,
        species: species,
        hangingWeight: hangingWeight,
        portionsRequested: portionsRequested,
        spicePreference: spicePreference,
        specialInstructions: specialInstructions,
        allPortionOptions: allPortionOptions,
      ),
    );

    final sanitized = carcassTag.replaceAll(RegExp(r'[^\w\-.]'), '_');
    await doc.saveAndShare(
      filename: 'JagSpoor_Slaughterhouse_Manifest_$sanitized',
      shareSubject: 'JagSpoor Slaughterhouse Manifest - $carcassTag',
      shareText: 'Meat processing manifest for $hunterName ($species)',
    );
  }

  pw.Widget _buildContent({
    required String carcassTag,
    required String hunterName,
    required String species,
    required double hangingWeight,
    required List<String> portionsRequested,
    required String spicePreference,
    required String specialInstructions,
    List<String> allPortionOptions = const [],
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        JagSpoorPdfTheme.sectionBar('Carcass & Hunter Details'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Hunter Name', hunterName),
          JagSpoorPdfTheme.infoRow('Carcass Tag ID', carcassTag),
          JagSpoorPdfTheme.infoRow('Species', species),
          JagSpoorPdfTheme.infoRow(
              'Cold Hanging Weight', MeasurementFormatter.instance.formatWeight(hangingWeight)),
        ]),

        JagSpoorPdfTheme.sectionBar('Processing Specifications & Portions'),
        _buildPortionChecklist(portionsRequested, allPortionOptions),
        pw.SizedBox(height: 8),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Spice Profile', spicePreference),
        ]),

        JagSpoorPdfTheme.sectionBar('Special Instructions / Notes'),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: JagSpoorPdfTheme.band,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: JagSpoorPdfTheme.divider, width: 0.5),
          ),
          child: pw.Text(
            specialInstructions.isEmpty ? '-' : specialInstructions,
            style: JagSpoorPdfTheme.body,
          ),
        ),
      ],
    );
  }

  /// Renders the requested portions as an ASCII checkbox matrix so the
  /// slaughterhouse can verify selections at a glance. Uses `[X]` (checked)
  /// and `[ ]` (unchecked) — plain ASCII the default PDF font (Helvetica /
  /// WinAnsi) maps cleanly, avoiding the full-block glyph artifacts that
  /// Unicode checkbox chars (U+2610/U+2611) produce.
  pw.Widget _buildPortionChecklist(
    List<String> portionsRequested,
    List<String> allPortionOptions,
  ) {
    if (portionsRequested.isEmpty && allPortionOptions.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(10),
        child: pw.Text('No portions requested.', style: JagSpoorPdfTheme.body),
      );
    }

    final selected = portionsRequested.toSet();
    // Standard option rows, then any custom selections not in the option set.
    final rows = <pw.Widget>[
      ...allPortionOptions.map(
        (option) => _checkRow(selected.contains(option), option),
      ),
      ...portionsRequested
          .where((p) => !allPortionOptions.contains(p))
          .map((p) => _checkRow(true, '$p (custom)')),
    ];

    if (rows.isEmpty) {
      // allPortionOptions was empty but portionsRequested had items — fall back
      // to listing the selected portions as checked rows.
      rows.addAll(portionsRequested.map((p) => _checkRow(true, p)));
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: JagSpoorPdfTheme.band,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: JagSpoorPdfTheme.divider, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  pw.Widget _checkRow(bool checked, String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Text(
        '${checked ? '[X]' : '[ ]'}  $label',
        style: JagSpoorPdfTheme.body,
      ),
    );
  }
}
