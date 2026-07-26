import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SapsPdfGenerator {
  /// Generate SAPS 518(a) License Renewal Application PDF document.
  static Future<Uint8List> generateSaps518aPdf({
    required Map<String, String> firearm,
    required String fullName,
    required String surname,
    required String idNumber,
    required String phone,
    required String address,
    required String policeStation,
    required String safeType,
    required String associationNo,
    required String motivation,
  }) async {
    final pdf = pw.Document();

    final licenceNo = firearm['licenceNo'] ?? firearm['licenseNumber'] ?? 'N/A';
    final issueDate = firearm['issueDate'] ?? 'N/A';
    final expiryDate = firearm['expiry'] ?? 'N/A';
    final make = firearm['make'] ?? 'N/A';
    final caliber = firearm['caliber'] ?? 'N/A';
    final serial = firearm['serial'] ?? 'N/A';
    final firearmType = firearm['type'] ?? 'Rifle / Handgun';

    // Build Page 1 - Section A, B, C & D
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Official Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 2, color: PdfColors.black),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'SOUTH AFRICAN POLICE SERVICE',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'SAPS 518(a) — APPLICATION FOR RENEWAL OF FIREARM LICENCE',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Section 24 of the Firearms Control Act, 2000 (Act No 60 of 2000)',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Section C: Firearm Particulars
              _buildSectionHeader('SECTION C: PARTICULARS OF CURRENT LICENCE & FIREARM'),
              pw.SizedBox(height: 8),
              _buildGridTable([
                ['Original Licence Number:', licenceNo],
                ['Date Issued:', issueDate],
                ['Licence Expiry Date:', expiryDate],
                ['Firearm Make:', make],
                ['Calibre:', caliber],
                ['Serial Number:', serial],
                ['Firearm Type / Action:', firearmType],
              ]),
              pw.SizedBox(height: 16),

              // Section D: Applicant Details
              _buildSectionHeader('SECTION D: PARTICULARS OF APPLICANT'),
              pw.SizedBox(height: 8),
              _buildGridTable([
                ['Full Name(s):', fullName],
                ['Surname:', surname],
                ['Identity Number:', idNumber],
                ['Contact Telephone / Cell:', phone],
                ['Physical Residential Address:', address],
                ['Designated Police Station (DFO):', policeStation],
                ['Accredited Hunting Assn. No.:', associationNo],
              ]),
            ],
          );
        },
      ),
    );

    // Build Page 2 - Section E & Section F (Safe Declaration & Motivation)
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('SECTION E: SAFE STORAGE DECLARATION (SABS 953-1 COMPLIANCE)'),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey700),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Installed Safe Configuration:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(safeType, style: const pw.TextStyle(fontSize: 11)),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Declaration: I hereby declare that the prescribed safe/storage facility as per SABS 953-1 specification is installed at the residential address indicated in Section D, and is securely anchored in accordance with FCA Regulation 86.',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              _buildSectionHeader('SECTION F: WRITTEN MOTIVATION FOR LICENCE RENEWAL'),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey700),
                ),
                child: pw.Text(
                  motivation.isEmpty
                      ? 'Applicant continues dedicated hunting and sport shooting activities as registered with accredited hunting associations under FCA Act 60 of 2000.'
                      : motivation,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Build Page 3 & Page 4 with Signatures and Annexure A
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Page 4 - Section G: Applicant Signature Block
              _buildSectionHeader('SECTION G: DECLARATION BY APPLICANT'),
              pw.SizedBox(height: 8),
              pw.Text(
                'I solemnly declare that the information provided in this renewal application is true and correct in every detail.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 24),
              _buildSignatureMarker(
                label: 'Signature of Applicant',
                sectionTag: 'Page 4, Section G',
              ),
              pw.SizedBox(height: 36),

              // Annexure A: Safe Declaration Signature Block
              _buildSectionHeader('ANNEXURE A: SAFE & STORAGE COMPLIANCE DECLARATION'),
              pw.SizedBox(height: 8),
              pw.Text(
                'I, the undersigned owner/licensee, confirm that the safe facility described above remains mounted and in full compliance with Regulation 86.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 24),
              _buildSignatureMarker(
                label: 'Signature of Owner (Safe Declaration)',
                sectionTag: 'Annexure A',
              ),
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('JagSpoor SAPS 518(a) PDF Generator', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  pw.Text('Page 4 of 4', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      color: PdfColors.grey300,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  static pw.Widget _buildGridTable(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: rows.map((r) {
        return pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                r[0],
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(r[1], style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        );
      }).toList(),
    );
  }

  static pw.Widget _buildSignatureMarker({
    required String label,
    required String sectionTag,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '[$sectionTag] OFFICIAL SIGNATURE BLOCK',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red900,
            ),
          ),
          pw.SizedBox(height: 30),
          pw.Divider(thickness: 1, color: PdfColors.black),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              ),
              pw.Text('Date: ____________________', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  /// Print or share the SAPS 518(a) renewal document.
  static Future<void> printOrShare518a({
    required Map<String, String> firearm,
    required String fullName,
    required String surname,
    required String idNumber,
    required String phone,
    required String address,
    required String policeStation,
    required String safeType,
    required String associationNo,
    required String motivation,
  }) async {
    final pdfBytes = await generateSaps518aPdf(
      firearm: firearm,
      fullName: fullName,
      surname: surname,
      idNumber: idNumber,
      phone: phone,
      address: address,
      policeStation: policeStation,
      safeType: safeType,
      associationNo: associationNo,
      motivation: motivation,
    );

    final filename = 'SAPS_518a_Renewal_${firearm['serial'] ?? 'Firearm'}.pdf';
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  }
}
