import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';
import '../../../core/utils/measurement_formatter.dart';

/// A requested meat-processing portion with an optional target weight (kg)
/// and a selected spice / flavour profile (may be a named SA profile or a
/// free-text custom blend).
class ProcessingPortion {
  final String name;
  final double? targetWeightKg;
  final String spice;

  const ProcessingPortion({
    required this.name,
    this.targetWeightKg,
    this.spice = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (targetWeightKg != null) 'targetWeightKg': targetWeightKg,
        if (spice.isNotEmpty) 'spice': spice,
      };
}

class MeatProcessingExporter {
  // Compile processing requirements into a formal, printable PDF document matrix
  Future<void> generateAndShareManifest({
    required String carcassTag,
    required String hunterName,
    required String species,
    required double hangingWeight,
    required List<ProcessingPortion>
        portions, // per-portion target weights + spice notes
    String spicePreference = '', // default/global spice note (optional)
    String specialInstructions = '',
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
        portions: portions,
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
    required List<ProcessingPortion> portions,
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
          JagSpoorPdfTheme.infoRow('Cold Hanging Weight',
              MeasurementFormatter.instance.formatWeight(hangingWeight)),
        ]),

        JagSpoorPdfTheme.sectionBar('Processing Specifications & Portions'),
        _buildPortionTable(portions),
        if (spicePreference.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          JagSpoorPdfTheme.detailBox([
            JagSpoorPdfTheme.infoRow('Default Spice Profile', spicePreference),
          ]),
        ],

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

  /// Renders the requested portions as a table with each portion's target
  /// weight and spice / flavour note displayed alongside the portion name.
  pw.Widget _buildPortionTable(List<ProcessingPortion> portions) {
    if (portions.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(10),
        child: pw.Text('No portions requested.', style: JagSpoorPdfTheme.body),
      );
    }

    final rows = portions.map((p) {
      final weightStr = p.targetWeightKg == null
          ? '-'
          : MeasurementFormatter.instance.formatWeight(p.targetWeightKg);
      return [
        p.name,
        weightStr,
        p.spice.isEmpty ? '-' : p.spice,
      ];
    }).toList();

    return JagSpoorPdfTheme.dataTable(
      headers: const ['Portion', 'Target Weight', 'Spice / Flavour'],
      rows: rows,
      columnWidths: const [150, 110, 200],
    );
  }
}
