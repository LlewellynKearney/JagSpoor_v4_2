import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Central reusable PDF layout engine for every JagSpoor document export.
///
/// Every generated PDF (permits, invoices, trophy stock, analytics) shares the
/// same branded header (JagSpoor logo + document title + document ID +
/// generation date), footer (support email + "Page X of Y" + legal disclaimer),
/// and tactical palette so the whole ecosystem's paperwork looks like one
/// coherent product line.
///
/// Usage:
/// ```
/// final doc = await JagSpoorPdfDocument.create(
///   title: 'Booking Invoice',
///   documentId: 'BK-1234',
/// );
/// doc.addPage(content: myContentWidget);
/// await doc.saveAndShare(filename: 'invoice_BK-1234');
/// ```
class JagSpoorPdfDocument {
  JagSpoorPdfDocument._({
    required this.title,
    required this.documentId,
    required this.logoBytes,
  });

  /// Document title rendered in every page header.
  final String title;

  /// Short document reference rendered in the header (e.g. permit/invoice no.).
  final String documentId;

  /// Cached logo PNG bytes (loaded once from the asset bundle).
  final Uint8List logoBytes;

  final pw.Document _doc = pw.Document();

  /// Loads the engine with the JagSpoor logo so the header can embed it.
  /// Call once per document; the logo bytes are cached for every page.
  static Future<JagSpoorPdfDocument> create({
    required String title,
    required String documentId,
  }) async {
    final logoBytes = await rootBundle.load('assets/app logo/logo1.png');
    return JagSpoorPdfDocument._(
      title: title,
      documentId: documentId,
      logoBytes: logoBytes.buffer.asUint8List(),
    );
  }

  /// Adds a single content page with the standard branded header + footer.
  void addPage({required pw.Widget content, double margin = 32}) {
    _doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(margin),
        header: _buildHeader,
        footer: _buildFooter,
        build: (_) => [content],
      ),
    );
  }

  /// Adds a single content page using a list builder (for multi-page flow).
  void addPages(pw.Widget Function() builder, {double margin = 32}) {
    _doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(margin),
        header: _buildHeader,
        footer: _buildFooter,
        build: (_) => [builder()],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────

  pw.Widget _buildHeader(pw.Context context) {
    final genDate =
        DateTime.now().toLocal().toString().substring(0, 10);
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 40,
              height: 40,
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'JAGSPOOR',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: JagSpoorPdfTheme.accent,
                    ),
                  ),
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: JagSpoorPdfTheme.deepBrown,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Document ID',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: JagSpoorPdfTheme.subtitle,
                  ),
                ),
                pw.Text(
                  documentId,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: JagSpoorPdfTheme.darkSlate,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Generated: $genDate',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: JagSpoorPdfTheme.subtitle,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: JagSpoorPdfTheme.accent,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
      children: [
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 8, bottom: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: JagSpoorPdfTheme.accent, width: 0.75),
            ),
          ),
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'support@jag-spoor.co.za',
              style: pw.TextStyle(
                fontSize: 7,
                color: JagSpoorPdfTheme.deepBrown,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 7, color: JagSpoorPdfTheme.subtitle),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'LEGAL DISCLAIMER: This document is generated by the JagSpoor ecosystem '
          'and is a system-issued record. It does not constitute legal advice. '
          'Statutory permits remain subject to applicable South African national '
          'and provincial environmental legislation. Verify all details before use.',
          style: pw.TextStyle(fontSize: 6, color: JagSpoorPdfTheme.subtitle),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  /// Saves the document to the app documents directory and opens the system
  /// share sheet. Returns the generated [File].
  Future<File> saveAndShare({
    required String filename,
    String? shareSubject,
    String? shareText,
  }) async {
    final bytes = await _doc.save();
    final outputDir = await getApplicationDocumentsDirectory();
    final sanitized = filename.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final file = File('${outputDir.path}/$sanitized.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: shareSubject ?? title,
      text: shareText,
    );
    return file;
  }

  /// Saves the document to bytes without invoking the share sheet.
  Future<Uint8List> saveBytes() => _doc.save();
}

/// Official tactical palette + reusable style tokens for all JagSpoor PDFs.
class JagSpoorPdfTheme {
  JagSpoorPdfTheme._();

  /// Warm Gold/Bronze (#C68B59) — header accents, dividers.
  static const PdfColor accent = PdfColor.fromInt(0xFFC68B59);

  /// Deep Saddle Brown (#795548) — secondary headers, support text.
  static const PdfColor deepBrown = PdfColor.fromInt(0xFF795548);

  /// Brushed Gold (#D4AF37) — emphasis accents.
  static const PdfColor gold = PdfColor.fromInt(0xFFD4AF37);

  /// Dark slate text (#212121) — body text.
  static const PdfColor darkSlate = PdfColor.fromInt(0xFF212121);

  /// Subtitle grey-brown (#5D4037) — captions, footers.
  static const PdfColor subtitle = PdfColor.fromInt(0xFF5D4037);

  /// Crisp white — table rows.
  static const PdfColor white = PdfColors.white;

  /// Light table band (#F4EFEA) — alternating rows / section cards.
  static const PdfColor band = PdfColor.fromInt(0xFFF4EFEA);

  /// Light divider (#E0E0E0).
  static const PdfColor divider = PdfColor.fromInt(0xFFE0E0E0);

  // ── Reusable style getters ────────────────────────────────────────────

  static pw.TextStyle get sectionTitle => pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: accent,
      );

  static pw.TextStyle get body => const pw.TextStyle(
        fontSize: 10,
        color: darkSlate,
      );

  static pw.TextStyle get caption => pw.TextStyle(
        fontSize: 8,
        color: subtitle,
      );

  static pw.TextStyle get tableHeader => pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: white,
      );

  // ── Reusable widget builders ─────────────────────────────────────────

  /// A section title bar with the accent underline.
  static pw.Widget sectionBar(String label, {PdfColor? color}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
      decoration: pw.BoxDecoration(
        color: color ?? accent,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: white,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// A labelled value row inside a details block.
  static pw.Widget infoRow(String label, String value, {double labelWidth = 130}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: labelWidth,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: deepBrown,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value.isEmpty ? '—' : value, style: body),
          ),
        ],
      ),
    );
  }

  /// A boxed details panel.
  static pw.Widget detailBox(Iterable<pw.Widget> children) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: band,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: divider, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children.toList(),
      ),
    );
  }

  /// A standard data table with accent header row + crisp white body rows.
  static pw.Widget dataTable({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> columnWidths,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: divider, width: 0.5),
      columnWidths: {
        for (int i = 0; i < columnWidths.length; i++)
          i: pw.FixedColumnWidth(columnWidths[i]),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: accent),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(h, style: tableHeader),
                  ))
              .toList(),
        ),
        ...rows.map((row) => pw.TableRow(
              decoration: const pw.BoxDecoration(color: white),
              children: row
                  .map((cell) => pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(cell, style: body),
                      ))
                  .toList(),
            )),
      ],
    );
  }

  /// A currency row for billing summaries.
  static pw.Widget currencyRow(
    String label,
    double amount, {
    bool bold = false,
    bool emphasis = false,
    bool total = false,
  }) {
    final style = pw.TextStyle(
      fontSize: total ? 13 : 10,
      fontWeight: bold || total ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: emphasis ? accent : (total ? white : darkSlate),
    );
    final valueStyle = pw.TextStyle(
      fontSize: total ? 13 : 10,
      fontWeight: pw.FontWeight.bold,
      color: total ? white : (emphasis ? accent : darkSlate),
    );
    final row = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(formatZAR(amount), style: valueStyle),
        ],
      ),
    );
    if (!total) return row;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: accent,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: row,
    );
  }

  /// A signature block with an optional embedded image and a caption underneath.
  static pw.Widget signatureBlock({
    required String label,
    Uint8List? imageBytes,
    double width = 160,
    double height = 60,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: width,
          height: height,
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: darkSlate, width: 0.5),
            ),
          ),
          child: imageBytes == null
              ? pw.Container()
              : pw.Padding(
                  padding: const pw.EdgeInsets.all(2),
                  child:
                      pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.contain),
                ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: subtitle)),
      ],
    );
  }

  /// Formats a ZAR amount with thousands separators and 2 decimals.
  static String formatZAR(double amount) {
    return 'R ${amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    )}';
  }

  /// Formats a date as DD/MM/YYYY, returning '—' for null.
  static String formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
