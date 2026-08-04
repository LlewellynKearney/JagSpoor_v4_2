import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    final pw.Document pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    'SOUTH AFRICAN GAME TRANSPORT PERMIT',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    '(Issued in terms of Provincial Environmental Management Legislation)',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 10),

                // Section A: Landowner
                pw.Text(
                  'SECTION A: OWNER / AUTHORISED ISSUER DETAILS',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Concession Property / Farm Name: $farmName'),
                pw.Text('CAE / Exemption / Permit Number: $exemptionNumber'),
                pw.SizedBox(height: 15),

                // Section B: Hunter
                pw.Text(
                  'SECTION B: RECEIVER / HUNTER DETAILS',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Full Name & Surname: $hunterName'),
                pw.Text('National ID / Passport Number: $hunterIdNumber'),
                pw.Text('Physical Residential Address: $hunterAddress'),
                pw.SizedBox(height: 15),

                // Section C: Transport
                pw.Text(
                  'SECTION C: TRANSPORTER & VEHICLE DETAILS',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Vehicle Make & Model: $vehicleMake'),
                pw.Text('Vehicle Registration Number: $vehicleReg'),
                pw.SizedBox(height: 15),

                // Section D: Carcass Table
                pw.Text(
                  'SECTION D: SPECIFICATION OF GAME MEAT / CARCASSES',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),

                // Table
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Species',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Quantity',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Sex',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    ...speciesList.map((item) {
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(item['species']?.toString() ?? ''),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(item['quantity']?.toString() ?? ''),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(item['sex']?.toString() ?? ''),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 15),

                // Section E: Destination
                pw.Text(
                  'SECTION E: FINAL DESTINATION DELIVERY ADDRESS',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(destinationAddress),

                pw.Spacer(),
                pw.Divider(),
                pw.SizedBox(height: 5),
                pw.Text(
                  'LEGAL DECLARATION: By transporting this game meat/carcasses, the transporter declares that the products listed above were harvested legally in full compliance with national and provincial biodiversity frameworks.',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 20),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        landownerSignatureBytes != null
                            ? pw.Container(
                              width: 150,
                              height: 60,
                              child: pw.Image(
                                pw.MemoryImage(landownerSignatureBytes),
                                fit: pw.BoxFit.contain,
                              ),
                            )
                            : pw.Container(
                              width: 120,
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(
                                  bottom: pw.BorderSide(
                                    width: 0.5,
                                    color: PdfColors.black,
                                  ),
                                ),
                              ),
                            ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Signature: Issuer/Owner',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 120,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                width: 0.5,
                                color: PdfColors.black,
                              ),
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Signature: Transporter',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 15),
                pw.Center(
                  child: pw.Text(
                    'Permit Reference ID: $permitId | Generated via JagSpoor Ecosystem',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final Directory outputDir = await getApplicationDocumentsDirectory();
    final File permitFile = File(
      "${outputDir.path}/SA_Game_Transport_Permit_$permitId.pdf",
    );
    await permitFile.writeAsBytes(await pdf.save());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(permitFile.path)],
        text: 'Statutory SA Game Transport Permit for Hunter: $hunterName',
        subject: 'SA Game Transport Permit: $farmName',
      ),
    );
  }
}
