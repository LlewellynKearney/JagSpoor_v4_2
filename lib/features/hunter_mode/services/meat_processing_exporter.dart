import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';

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
              'Cold Hanging Weight', '${hangingWeight.toStringAsFixed(1)} kg'),
        ]),

        JagSpoorPdfTheme.sectionBar('Processing Specifications & Portions'),
        if (portionsRequested.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text('No portions requested.', style: JagSpoorPdfTheme.body),
          )
        else
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: portionsRequested
                .map((item) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Text('- $item', style: JagSpoorPdfTheme.body),
                    ))
                .toList(),
          ),
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
}
