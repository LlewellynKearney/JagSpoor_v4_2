import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoicePdfService {
  static const double markup = 1.05; // 5% marketplace commission

  static Future<Uint8List> generateInvoice({
    required String clientName,
    required String packageName,
    required double packageBasePrice,
    required List<Map<String, dynamic>> extras,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          double totalAmount = (packageBasePrice * markup);
          
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pwContainer(
                color: PdfColorsbrown
                padding: const pwEdgeInsetsall(),
                child: pwRow(
                  mainAxisAlignment: pwMainAxisAlignmentspaceBetween,
                  children: [
                    pwText('JAGSPOOR HUNTING INVOICE', 
                        style: pwTextStyle(color: PdfColorswhite, fontSize: fontWeight: pwFontWeightbold)),
                    pwText('Client: $clientName', 
                        style: pwTextStyle(color: PdfColorswhite, fontWeight: pwFontWeightbold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Text('1. Base Package (Includes 5% Commission)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.TableHelper.fromTextArray(
                data: [
                  ['Description', 'Price (ZAR)'],
                  [packageName, 'R ${totalAmounttoStringAsFixed()}'],
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Text('2. Field Extras & Butchery Items', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['Item Description', 'Qty', 'Unit Price', 'Subtotal (ZAR)'],
                data: extras.map((item) {
                  final double rawPrice = (item['price'] is num) ? (item['price'] as num).toDouble() : 0.0;
                  final double hunterPrice = rawPrice * markup;
                  final int qty = (item['multiplier'] is num) ? (item['multiplier'] as num).toInt() : 1;
                  final double subtotal = hunterPrice * qty;
                  totalAmount += subtotal;
                  
                  return [
                    item['name'] ?? 'Extra Item',
                    qty.toString(),
                    'R ${hunterPrice.toStringAsFixed(2)}',
                    'R ${subtotal.toStringAsFixed(2)}',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 30),
              pw.Divider(color: PdfColors.grey500),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('TOTAL AMOUNT DUE: R ${totalAmount.toStringAsFixed(2)}', 
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.brown900)),
              ),
            ],
          );
        },
      ),
    );
    return await pdf.save();
  }
}
