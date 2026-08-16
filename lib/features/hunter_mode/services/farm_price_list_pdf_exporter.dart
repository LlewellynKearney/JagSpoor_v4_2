import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/pdf_document_engine.dart';
import '../models/farm_game_price_entry.dart';
import '../models/farm_service_rate.dart';

/// Professional branded PDF exporter for a single farm's game price list +
/// itemized service rates. Renders via the shared [JagSpoorPdfDocument]
/// engine (logo header, theme palette, page footer) so the output matches
/// every other JagSpoor document line.
///
/// The exporter is split into a pure content builder (`buildContent`) -- which
/// is fully unit-testable in isolation -- and a thin platform wrapper
/// (`generateAndShare`) that loads the logo + invokes the OS share sheet.
class FarmPriceListPdfExporter {
  /// Builds the printable PDF document and invokes the native share sheet.
  /// [farmName] is the header title; [species] is the game-species price list;
  /// [services] is the optional itemized service-rate configuration. A farm
  /// with no species AND no configured services still exports a valid (empty)
  /// document so the outfitter can confirm the layout.
  Future<void> generateAndShare({
    required String farmName,
    required List<FarmGamePriceEntry> species,
    FarmServiceRates? services,
    String? farmId,
  }) async {
    final doc = await JagSpoorPdfDocument.create(
      title: 'Farm Game Price List',
      documentId: farmId != null && farmId.isNotEmpty
          ? 'FPL-$farmId'
          : 'FPL-${DateTime.now().millisecondsSinceEpoch}',
    );

    doc.addPage(
      margin: 28,
      content: buildContent(
        farmName: farmName,
        species: species,
        services: services,
      ),
    );

    final safeName = farmName.replaceAll(RegExp(r'[^\w\-]'), '_');
    await doc.saveAndShare(
      filename: 'JagSpoor_Price_List_$safeName',
      shareSubject: 'JagSpoor Price List · $farmName',
      shareText: 'Game price list and service rates for $farmName.',
    );
  }

  /// Pure content builder -- returns a `pw.Widget` tree that the engine wraps
  /// in the standard branded header + footer. Stateless + side-effect free so
  /// it can be exercised in a unit test by rendering the document to bytes.
  pw.Widget buildContent({
    required String farmName,
    required List<FarmGamePriceEntry> species,
    FarmServiceRates? services,
  }) {
    final configuredServices = services?.configuredRates ?? const <FarmServiceRate>[];
    final servicesTotal = configuredServices.fold<double>(0.0, (s, r) => s + r.total);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Farm header ───────────────────────────────────────────────────
        JagSpoorPdfTheme.sectionBar('FARM GAME PRICE LIST'),
        pw.SizedBox(height: 6),
        pw.Text(
          farmName,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: JagSpoorPdfTheme.darkSlate,
          ),
        ),
        pw.Text(
          'Issued ${JagSpoorPdfTheme.formatDate(DateTime.now())}',
          style: JagSpoorPdfTheme.caption,
        ),
        pw.SizedBox(height: 14),

        // ── Table 1: Game Species ────────────────────────────────────────
        JagSpoorPdfTheme.sectionBar('Game Species'),
        pw.SizedBox(height: 6),
        species.isEmpty
            ? _emptyHint('No game species priced yet.')
            : JagSpoorPdfTheme.dataTable(
                headers: ['Species', 'Gender', 'Horn / Tusk', 'Qty', 'Price (ZAR)'],
                columnWidths: const [150, 60, 90, 40, 90],
                rows: species
                    .map((e) => [
                          e.speciesName,
                          e.gender,
                          e.hornTuskDisplayLabel.isEmpty
                              ? '-'
                              : e.hornTuskDisplayLabel,
                          e.qty.toString(),
                          JagSpoorPdfTheme.formatZAR(e.priceZAR),
                        ])
                    .toList(),
              ),
        pw.SizedBox(height: 18),

        // ── Table 2: Itemized Services ───────────────────────────────────
        JagSpoorPdfTheme.sectionBar('Itemized Services'),
        pw.SizedBox(height: 6),
        configuredServices.isEmpty
            ? _emptyHint('No itemized service rates configured.')
            : pw.Column(
                children: [
                  JagSpoorPdfTheme.dataTable(
                    headers: ['Service', 'Qty', 'Rate (ZAR)', 'Total (ZAR)'],
                    columnWidths: const [230, 40, 80, 90],
                    rows: configuredServices
                        .map((r) => [
                              r.label,
                              r.quantity.toString(),
                              JagSpoorPdfTheme.formatZAR(r.pricePerUnit),
                              JagSpoorPdfTheme.formatZAR(r.total),
                            ])
                        .toList(),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Services Total: ',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: JagSpoorPdfTheme.darkSlate,
                        ),
                      ),
                      pw.Text(
                        JagSpoorPdfTheme.formatZAR(servicesTotal),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: JagSpoorPdfTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        pw.SizedBox(height: 24),

        // ── Copyright footer line ─────────────────────────────────────────
        pw.Container(
          width: double.infinity,
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: JagSpoorPdfTheme.band,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Center(
            child: pw.Text(
              '© 2026 JagSpoor. All Rights Reserved.',
              style: pw.TextStyle(
                fontSize: 8,
                color: JagSpoorPdfTheme.subtitle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _emptyHint(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: JagSpoorPdfTheme.band,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        message,
        style: pw.TextStyle(
          fontSize: 9,
          fontStyle: pw.FontStyle.italic,
          color: JagSpoorPdfTheme.subtitle,
        ),
      ),
    );
  }
}
