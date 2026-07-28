import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class OutfitterInvoiceExporter {
  /// Generates a PDF billing invoice and shares it via the system share sheet.
  /// 
  /// Parameters:
  /// - [bookingId]: Unique booking identifier
  /// - [packageName]: Name of the hunting package
  /// - [farmName]: Concession/farm property name
  /// - [hunterName]: Hunter/guest name
  /// - [basePrice]: Base package price in Rand
  /// - [platformFee]: 5% platform admin fee
  /// - [totalPrice]: Combined total price
  Future<void> generateAndShareInvoice({
    required String bookingId,
    required String packageName,
    required String farmName,
    required String hunterName,
    required double basePrice,
    required double platformFee,
    required double totalPrice,
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
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'JAGSPOOR HUNTING INVOICE',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green100,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'APPROVED',
                        style: pw.TextStyle(
                          fontSize: 14,
                          color: PdfColors.green800,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Booking ID: $bookingId',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.Text(
                  'Date: ${DateTime.now().toLocal().toString().substring(0, 10)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 24),
                pw.Text(
                  'CLIENT & LOCATION DETAILS:',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Hunter / Guest: $hunterName',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Text(
                  'Concession Property: $farmName',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Text(
                  'Package Reserved: $packageName',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 32),
                pw.Text(
                  'BILLING SUMMARY BREAKDOWN:',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                _buildPriceRow('Base Hunting Package Rate:', basePrice),
                pw.SizedBox(height: 8),
                _buildPriceRow('Platform Admin Booking Fee (5%):', platformFee),
                pw.SizedBox(height: 12),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL AMOUNT DUE:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'R ${totalPrice.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green800,
                      ),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Divider(),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Thank you for booking your safari via JagSpoor Ecosystem.',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'For support, contact support@jagspoor.com',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final Directory outputDir = await getApplicationDocumentsDirectory();
    final String sanitizedBookingId = bookingId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final File invoiceFile = File("${outputDir.path}/Hunting_Invoice_$sanitizedBookingId.pdf");
    await invoiceFile.writeAsBytes(await pdf.save());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(invoiceFile.path)],
        text: 'JagSpoor Hunting Booking Invoice for Confirmation ID: $bookingId',
        subject: 'Hunting Safari Invoice: $bookingId',
      ),
    );
  }

  /// Builds a formatted price row for the invoice
  pw.Widget _buildPriceRow(String label, double amount) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label),
        pw.Text('R ${amount.toStringAsFixed(2)}'),
      ],
    );
  }
}
