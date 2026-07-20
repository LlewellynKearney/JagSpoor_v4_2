import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';

class PdfGenerator {
  /// Generate and share a PDF document listing firearms with professional layout.
  ///
  /// Expects each firearm entry to contain at least: 'make', 'serial', 'barrelLife', 'roundCount', 'expiry'.
  /// Layout: Firearm Make (far left) | Serial Number | Validity | Barrel Life (Rounds Remaining) | % Used
  static Future<void> generateAndShareFirearmsPdf(List<Map<String, String>> firearms) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: pdf.PdfPageFormat.a4,
        build: (contextPdf) {
          final rows = <pw.TableRow>[];

          // Header row with new layout: Make, Serial, Validity, Barrel Life, % Used
          rows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 2),
                ),
              ),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: pw.Text(
                    'Firearm Make',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: pw.Text(
                    'Serial Number',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: pw.Text(
                    'Validity',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: pw.Text(
                    'Barrel Life',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: pw.Text(
                    '% Used',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          );

          // Data rows
          for (final f in firearms) {
            final make = f['make'] ?? 'Unknown';
            final serial = f['serial'] ?? '';
            final expiry = f['expiry'] ?? '';
            final barrelLife = int.tryParse(f['barrelLife'] ?? '') ?? 0;
            final roundCount = int.tryParse(f['roundCount'] ?? '') ?? 0;
            final remaining = barrelLife > 0 ? (barrelLife - roundCount) : 0;
            final usedPct = barrelLife > 0 ? ((roundCount / barrelLife) * 100).clamp(0, 100).toStringAsFixed(1) : 'N/A';

            rows.add(
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(width: 0.5, color: pdf.PdfColors.grey),
                  ),
                ),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: pw.Text(make, style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: pw.Text(serial, style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: pw.Text(_formatValidity(expiry), style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: pw.Text(
                      barrelLife > 0 ? '$remaining rds' : 'Not set',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: pw.Text(
                      barrelLife > 0 ? '$usedPct%' : 'N/A',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            );
          }

          return [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 16),
                  child: pw.Text(
                    'Digital Firearm Safe — Registry',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder.all(width: 0),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(2.5),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FlexColumnWidth(1),
                  },
                  children: rows,
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Generated: ${DateTime.now().toIso8601String().split('T').first}',
                  style: pw.TextStyle(fontSize: 9, color: pdf.PdfColors.grey700),
                ),
              ],
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: 'digital_firearm_safe.pdf');
  }

  static String _formatValidity(String expiry) {
    if (expiry.isEmpty) return 'Unknown';
    try {
      final dt = DateTime.parse(expiry);
      final now = DateTime.now();
      return dt.isBefore(now) ? 'Expired' : 'Valid until ${dt.toIso8601String().split('T').first}';
    } catch (_) {
      return expiry;
    }
  }
}

