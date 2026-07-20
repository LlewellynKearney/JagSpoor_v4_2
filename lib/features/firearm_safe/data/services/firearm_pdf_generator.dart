import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';

class FirearmPdfGenerator {
  static Future<void> generateAndShowFirearmsPdf(
    List<Map<String, String>> firearms,
  ) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (contextPdf) {
          final rows = <pw.TableRow>[];

          rows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: pdf.PdfColors.grey200,
                border: pw.Border(
                  bottom: pw.BorderSide(width: 2),
                ),
              ),
              children: [
                _buildHeaderCell('Firearm Make & Model', pw.TextAlign.left),
                _buildHeaderCell('Serial Number', pw.TextAlign.left),
                _buildHeaderCell('Validity Status / Expiry', pw.TextAlign.center),
                _buildHeaderCell('Barrel Life (Rounds Remaining)', pw.TextAlign.center),
                _buildHeaderCell('% Lifetime Used', pw.TextAlign.right),
              ],
            ),
          );

          for (final firearm in firearms) {
            final make = firearm['make'] ?? 'Unknown';
            final model = firearm['model'] ?? '';
            final serial = firearm['serial'] ?? '';
            final expiry = firearm['expiry'] ?? '';
            final barrelLife = int.tryParse(firearm['barrelLife'] ?? '') ?? 0;
            final roundCount = int.tryParse(firearm['roundCount'] ?? '') ?? 0;
            final remaining = barrelLife > 0 ? (barrelLife - roundCount) : 0;
            final usedPct = barrelLife > 0
                ? ((roundCount / barrelLife) * 100).clamp(0, 100).toStringAsFixed(1)
                : 'N/A';

            rows.add(
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(width: 0.5, color: pdf.PdfColors.grey400),
                  ),
                ),
                children: [
                  _buildDataCell('$make $model'.trim(), pw.TextAlign.left),
                  _buildDataCell(serial, pw.TextAlign.left),
                  _buildDataCell(_formatValidity(expiry), pw.TextAlign.center),
                  _buildDataCell(
                    barrelLife > 0 ? '$remaining rds' : 'Not set',
                    pw.TextAlign.center,
                  ),
                  _buildDataCell(
                    barrelLife > 0 ? '$usedPct%' : 'N/A',
                    pw.TextAlign.right,
                  ),
                ],
              ),
            );
          }

          return [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Digital Firearm Safe — Registry',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: pdf.PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Generated: ${_formatDate(DateTime.now())}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: pdf.PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5, color: pdf.PdfColors.grey400),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2.5),
                    1: const pw.FlexColumnWidth(2.2),
                    2: const pw.FlexColumnWidth(2.3),
                    3: const pw.FlexColumnWidth(2.0),
                    4: const pw.FlexColumnWidth(1.0),
                  },
                  defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                  children: rows,
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  'Total Firearms: ${firearms.length}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: pdf.PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'digital_firearm_safe_registry',
    );
  }

  static pw.Widget _buildHeaderCell(String text, pw.TextAlign align) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
          color: pdf.PdfColors.black,
        ),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _buildDataCell(String text, pw.TextAlign align) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          color: pdf.PdfColors.black,
        ),
        textAlign: align,
      ),
    );
  }

  static String _formatValidity(String expiry) {
    if (expiry.isEmpty) return 'Unknown';
    try {
      final dt = DateTime.parse(expiry);
      final now = DateTime.now();
      if (dt.isBefore(now)) {
        return 'Expired (${dt.toIso8601String().split('T').first})';
      }
      return 'Valid until ${dt.toIso8601String().split('T').first}';
    } catch (_) {
      return expiry;
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
