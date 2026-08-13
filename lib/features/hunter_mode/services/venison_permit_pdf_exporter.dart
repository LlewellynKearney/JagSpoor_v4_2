import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';
import '../models/venison_transport_permit.dart';
import '../services/venison_permit_manager.dart';

/// Legal SA Venison / Game Transport & Hunt Permit PDF, rendered through the
/// universal [JagSpoorPdfDocument] engine so it carries the branded header +
/// footer, tactical palette, and embedded hunter & outfitter digital signature
/// images.
class VenisonPermitPdfExporter {
  /// Generates and shares the permit PDF. Signature images are fetched from
  /// their Firebase Storage URLs and embedded inline. Either may be absent
  /// when only one party has signed — the block renders as a blank signature
  /// line in that case.
  Future<void> generateAndShare({
    required String permitId,
    required VenisonTransportPermit permit,
  }) async {
    final doc = await JagSpoorPdfDocument.create(
      title: 'Venison / Game Transport & Hunt Permit',
      documentId: permit.permitNumber.isEmpty ? permitId : permit.permitNumber,
    );

    // Fetch signature PNGs (best-effort — either may be null).
    final hunterSig =
        await _fetchImage(permit.hunterSignatureUrl);
    final outfitterSig =
        await _fetchImage(permit.outfitterSignatureUrl);

    doc.addPage(
      margin: 28,
      content: _buildPermitContent(permit, hunterSig, outfitterSig),
    );

    await doc.saveAndShare(
      filename: 'Venison_Transport_Permit_${permit.permitNumber.isEmpty ? permitId : permit.permitNumber}',
      shareSubject: 'SA Venison Transport Permit - ${permit.hunterName}',
      shareText:
          'Legal SA Venison / Game Transport & Hunt Permit for ${permit.hunterName}',
    );
  }

  pw.Widget _buildPermitContent(
    VenisonTransportPermit permit,
    Uint8List? hunterSig,
    Uint8List? outfitterSig,
  ) {
    final fmtDate = JagSpoorPdfTheme.formatDate;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Document purpose banner
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: JagSpoorPdfTheme.band,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                'SOUTH AFRICAN VENISON / GAME TRANSPORT & HUNT PERMIT',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: JagSpoorPdfTheme.darkSlate,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Issued under applicable national and provincial environmental '
                'management legislation',
                style: JagSpoorPdfTheme.caption,
              ),
            ],
          ),
        ),

        // ── Hunter details ──
        JagSpoorPdfTheme.sectionBar('SECTION A: Hunter Details'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Full Name & Surname', permit.hunterName),
          JagSpoorPdfTheme.infoRow(
              'National ID / Passport', permit.hunterIdNumber),
          JagSpoorPdfTheme.infoRow('Cell Phone Number', permit.hunterCell),
          JagSpoorPdfTheme.infoRow('Residential Address', permit.hunterAddress),
        ]),

        // ── Authorized person / farm ──
        JagSpoorPdfTheme.sectionBar('SECTION B: Authorized Person / Farm'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow(
              'Authorized Person', permit.authorizedPersonName),
          JagSpoorPdfTheme.infoRow('Farm Name', permit.farmName),
          JagSpoorPdfTheme.infoRow('Farm Address', permit.farmAddress),
          JagSpoorPdfTheme.infoRow('Farm / Contact Cell', permit.farmCell),
        ]),

        // ── Hunt window ──
        JagSpoorPdfTheme.sectionBar('SECTION C: Hunt Window'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Hunt Start Date', fmtDate(permit.huntStartDate)),
          JagSpoorPdfTheme.infoRow('Hunt End Date', fmtDate(permit.huntEndDate)),
        ]),

        // ── Species hunted and transported ──
        JagSpoorPdfTheme.sectionBar('SECTION D: Species Hunted and Transported'),
        _speciesTable(permit),

        pw.SizedBox(height: 16),

        // ── Signatures ──
        JagSpoorPdfTheme.sectionBar('SECTION E: Signatures & Declaration'),
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            'By signing below, both parties declare that the species listed '
            'above were hunted and transported legally in compliance with all '
            'applicable South African environmental legislation.',
            style: JagSpoorPdfTheme.caption,
          ),
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            JagSpoorPdfTheme.signatureBlock(
              label: 'Hunter Signature',
              imageBytes: hunterSig,
              width: 180,
              height: 70,
            ),
            JagSpoorPdfTheme.signatureBlock(
              label: 'Authorized Person (Outfitter) Signature',
              imageBytes: outfitterSig,
              width: 180,
              height: 70,
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Hunter signed: ${fmtDate(permit.hunterSignedDate)}',
              style: JagSpoorPdfTheme.caption,
            ),
            pw.Text(
              'Outfitter signed: ${fmtDate(permit.outfitterSignedDate)}',
              style: JagSpoorPdfTheme.caption,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _speciesTable(VenisonTransportPermit permit) {
    if (permit.speciesHuntedAndTransported.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: JagSpoorPdfTheme.band,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('No species declared', style: JagSpoorPdfTheme.body),
      );
    }
    return JagSpoorPdfTheme.dataTable(
      headers: ['Species', 'Quantity', 'Sex'],
      columnWidths: [220, 120, 120],
      rows: permit.speciesHuntedAndTransported.map((s) {
        return [
          s['species']?.toString() ?? 'Unknown',
          s['quantity']?.toString() ?? '1',
          s['sex']?.toString() ?? '-',
        ];
      }).toList(),
    );
  }

  /// Best-effort fetch of a signature PNG from a storage download URL.
  Future<Uint8List?> _fetchImage(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {
      // Non-fatal — falls back to a blank signature line.
    }
    return null;
  }
}

/// Convenience top-level helper used by the permit list/details screen to
/// export a permit PDF directly from its ID (fetches the permit first).
Future<void> exportVenisonPermitPdf(String permitId) async {
  final permit =
      await VenisonPermitManager.instance.getPermitById(permitId);
  if (permit == null) return;
  await VenisonPermitPdfExporter().generateAndShare(
    permitId: permitId,
    permit: permit,
  );
}
