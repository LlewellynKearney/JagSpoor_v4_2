import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    final pw.Document pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'JAGSPOOR SLAUGHTERHOUSE MANIFEST',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 15),
                pw.Text(
                  'Hunter Name: $hunterName',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.Text(
                  'Carcass Tag ID: $carcassTag',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.Text(
                  'Species: $species',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.Text(
                  'Cold Hanging Weight: ${hangingWeight.toStringAsFixed(1)} kg',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'PROCESSING SPECIFICATIONS & PORTIONS REQUESTED:',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children:
                      portionsRequested
                          .map(
                            (item) => pw.Text(
                              '• $item',
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          )
                          .toList(),
                ),
                pw.SizedBox(height: 15),
                pw.Text(
                  'Spice Profile: $spicePreference',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 15),
                pw.Text(
                  'Special Instructions / Notes:',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  specialInstructions,
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Spacer(),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Date Generated: ${DateTime.now().toLocal().toString().substring(0, 16)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'Generated via JagSpoor Ecosystem',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    // Save PDF directly to local system application storage document profiles
    final Directory outputDir = await getApplicationDocumentsDirectory();
    final File pdfFile = File(
      "${outputDir.path}/Slaughterhouse_Manifest_$carcassTag.pdf",
    );
    await pdfFile.writeAsBytes(await pdf.save());

    // Trigger phone OS native sharing/email dialog box instantly
    await Share.shareXFiles(
      [XFile(pdfFile.path)],
      text:
          'JagSpoor Processing Requirements Manifest for Carcass Tag: $carcassTag',
      subject: 'Meat Processing Order: $carcassTag',
    );
  }
}
