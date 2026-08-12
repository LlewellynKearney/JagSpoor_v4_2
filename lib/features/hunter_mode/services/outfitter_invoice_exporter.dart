import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class OutfitterInvoiceExporter {
  /// Generates a PDF billing invoice and shares it via the system share sheet.
  /// All amounts are in South African Rand (ZAR).
  ///
  /// Parameters:
  /// - [bookingId]: Unique booking identifier
  /// - [packageName]: Name of the hunting package
  /// - [farmName]: Concession/farm property name
  /// - [hunterName]: Hunter/guest name
  /// - [basePrice]: Base package price in ZAR
  /// - [platformFee]: 7.5% platform admin fee in ZAR
  /// - [totalPrice]: Combined total price in ZAR
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
                // Header with Slaughterhouse Manifest title
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green800,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'JAGSPOOR SLAUGHTERHOUSE MANIFEST',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Official Booking Confirmation Document',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),

                // Status Badge
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green100,
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(
                          color: PdfColors.green800,
                          width: 2,
                        ),
                      ),
                      child: pw.Text(
                        '✅ APPROVED',
                        style: pw.TextStyle(
                          fontSize: 14,
                          color: PdfColors.green800,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 16),

                // Document Info
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'BOOKING ID',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.Text(
                          bookingId,
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'DATE ISSUED',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.Text(
                          DateTime.now().toLocal().toString().substring(0, 10),
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),

                // Client Details Section
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CLIENT & LOCATION DETAILS',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      _buildDetailRow('HUNTER / GUEST', hunterName),
                      _buildDetailRow('CONCESSION PROPERTY', farmName),
                      _buildDetailRow('PACKAGE RESERVED', packageName),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),

                // Billing Summary
                pw.Text(
                  'BILLING SUMMARY (ZAR)',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),

                // Line Items
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      _buildLineItemRow(
                        'Base Hunting Package Rate',
                        'R ${_formatZAR(basePrice)}',
                      ),
                      pw.SizedBox(height: 8),
                      _buildLineItemRow(
                        'Platform Admin Booking Fee (7.5%)',
                        'R ${_formatZAR(platformFee)}',
                        isFee: true,
                      ),
                      pw.SizedBox(height: 12),
                      pw.Divider(thickness: 1),
                      pw.SizedBox(height: 12),
                      _buildLineItemRow(
                        'SUBTOTAL (ZAR)',
                        'R ${_formatZAR(basePrice + platformFee)}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),

                // Total Amount Due
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green800,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL AMOUNT DUE (ZAR):',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        'R ${_formatZAR(totalPrice)}',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'All amounts in South African Rand (ZAR)',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
                pw.Spacer(),

                // Footer
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'Thank you for booking your safari via JagSpoor Ecosystem.',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'For support, contact support@jagspoor.com',
                    style: const pw.TextStyle(
                      fontSize: 9,
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
    final String sanitizedBookingId = bookingId.replaceAll(
      RegExp(r'[^\w\-]'),
      '_',
    );
    final File invoiceFile = File(
      "${outputDir.path}/JagSpoor_Slaughterhouse_Manifest_$sanitizedBookingId.pdf",
    );
    await invoiceFile.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(invoiceFile.path)],
      text: 'JagSpoor Slaughterhouse Manifest - Booking Confirmation: $bookingId',
      subject: 'JagSpoor Slaughterhouse Manifest: $bookingId',
    );
  }

  /// Format amount as ZAR currency
  String _formatZAR(double amount) {
    return amount
        .toStringAsFixed(2)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  /// Builds a detail row for client info
  pw.Widget _buildDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// Builds a line item row for billing
  pw.Widget _buildLineItemRow(
    String label,
    String value, {
    bool isFee = false,
    bool isBold = false,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: isBold ? 12 : 11,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isFee ? PdfColors.amber800 : PdfColors.black,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: isBold ? 12 : 11,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isFee ? PdfColors.amber800 : PdfColors.black,
          ),
        ),
      ],
    );
  }
}
