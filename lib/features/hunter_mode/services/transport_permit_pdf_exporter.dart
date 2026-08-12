import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';

/// SA Game Transport Permit PDF, rendered through the universal
/// [JagSpoorPdfDocument] engine so it carries the branded header + footer and
/// tactical palette alongside the rest of the JagSpoor document line.
class TransportPermitPdfExporter {
  Future<void> generateAndSharePermit({
    required String permitId,
    required String farmName,
    required String exemptionNumber,
    required String hunterName,
    required String hunterIdNumber,
    required String hunterAddress,
    required String vehicleReg,
    required String vehicleMake,
    required List<dynamic>
    speciesList, // Expects lists like [{'species': 'Kudu', 'quantity': 2, 'sex': 'Male'}]
    required String destinationAddress,
    Uint8List? landownerSignatureBytes,
  }) async {
    final doc = await JagSpoorPdfDocument.create(
      title: 'SA Game Transport Permit',
      documentId: exemptionNumber.isEmpty ? permitId : exemptionNumber,
    );

    doc.addPage(
      margin: 30,
      content: _buildContent(
        farmName: farmName,
        exemptionNumber: exemptionNumber,
        hunterName: hunterName,
        hunterIdNumber: hunterIdNumber,
        hunterAddress: hunterAddress,
        vehicleReg: vehicleReg,
        vehicleMake: vehicleMake,
        speciesList: speciesList,
        destinationAddress: destinationAddress,
        landownerSignatureBytes: landownerSignatureBytes,
      ),
    );

    await doc.saveAndShare(
      filename: 'SA_Game_Transport_Permit_$permitId',
      shareSubject: 'SA Game Transport Permit for Hunter: $hunterName',
      shareText: 'Statutory SA Game Transport Permit for Hunter: $hunterName',
    );
  }

  pw.Widget _buildContent({
    required String farmName,
    required String exemptionNumber,
    required String hunterName,
    required String hunterIdNumber,
    required String hunterAddress,
    required String vehicleReg,
    required String vehicleMake,
    required List<dynamic> speciesList,
    required String destinationAddress,
    Uint8List? landownerSignatureBytes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Document purpose banner
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: JagSpoorPdfTheme.band,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                'SOUTH AFRICAN GAME TRANSPORT PERMIT',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: JagSpoorPdfTheme.darkSlate,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Issued in terms of Provincial Environmental Management Legislation',
                style: JagSpoorPdfTheme.caption,
              ),
            ],
          ),
        ),

        // Section A: Landowner
        JagSpoorPdfTheme.sectionBar('SECTION A: OWNER / AUTHORISED ISSUER DETAILS'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow(
              'Concession Property / Farm Name', farmName),
          JagSpoorPdfTheme.infoRow(
              'CAE / Exemption / Permit Number', exemptionNumber),
        ]),

        // Section B: Hunter
        JagSpoorPdfTheme.sectionBar('SECTION B: RECEIVER / HUNTER DETAILS'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Full Name & Surname', hunterName),
          JagSpoorPdfTheme.infoRow('National ID / Passport Number', hunterIdNumber),
          JagSpoorPdfTheme.infoRow('Physical Residential Address', hunterAddress),
        ]),

        // Section C: Transport
        JagSpoorPdfTheme.sectionBar('SECTION C: TRANSPORTER & VEHICLE DETAILS'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Vehicle Make & Model', vehicleMake),
          JagSpoorPdfTheme.infoRow('Vehicle Registration Number', vehicleReg),
        ]),

        // Section D: Carcass Table
        JagSpoorPdfTheme.sectionBar(
            'SECTION D: SPECIFICATION OF GAME MEAT / CARCASSES'),
        if (speciesList.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text('No game meat / carcasses declared.',
                style: JagSpoorPdfTheme.body),
          )
        else
          JagSpoorPdfTheme.dataTable(
            headers: ['Species', 'Quantity', 'Sex'],
            columnWidths: [220, 120, 120],
            rows: speciesList.map((item) {
              return [
                item['species']?.toString() ?? '',
                item['quantity']?.toString() ?? '',
                item['sex']?.toString() ?? '',
              ];
            }).toList(),
          ),

        // Section E: Destination
        JagSpoorPdfTheme.sectionBar(
            'SECTION E: FINAL DESTINATION DELIVERY ADDRESS'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Destination Address', destinationAddress),
        ]),

        // Declaration + signature
        pw.SizedBox(height: 10),
        pw.Text(
          'LEGAL DECLARATION: By transporting this game meat/carcasses, the '
          'transporter declares that the products listed above were harvested '
          'legally in full compliance with national and provincial biodiversity '
          'frameworks.',
          style: JagSpoorPdfTheme.caption,
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            JagSpoorPdfTheme.signatureBlock(
              label: 'Signature: Issuer / Owner',
              imageBytes: landownerSignatureBytes,
              width: 180,
              height: 70,
            ),
            JagSpoorPdfTheme.signatureBlock(
              label: 'Signature: Transporter',
              width: 180,
              height: 70,
            ),
          ],
        ),
      ],
    );
  }
}
