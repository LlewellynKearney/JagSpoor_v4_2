import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';
import '../services/outfitter_analytics_service.dart';

/// Revenue & Farm Analytics report PDF, rendered through the universal
/// [JagSpoorPdfDocument] engine. Aggregates gross revenue, net earnings,
/// plus a farm manager directory, for the signed-in outfitter. There is no
/// platform commission; net earnings equal gross revenue.
class RevenueAnalyticsReportExporter {
  /// Generates and shares the revenue & farm analytics report PDF.
  Future<void> generateAndShare() async {
    final outfitterId = FirebaseAuth.instance.currentUser?.uid;
    if (outfitterId == null) {
      throw Exception(
          'User must be authenticated to export the analytics report');
    }

    // Revenue summary (gross / net) from approved bookings.
    final revenue = await OutfitterAnalyticsService.instance
        .getRevenueSummaryStream(outfitterId)
        .first;
    final grossEarnings = (revenue['grossEarnings'] ?? 0.0).toDouble();
    final netEarnings = (revenue['netEarnings'] ?? 0.0).toDouble();
    final totalBookings = (revenue['totalBookings'] ?? 0.0).toInt();

    // Farms.
    final farmSnap = await FirebaseFirestore.instance
        .collection('farms')
        .where('outfitterId', isEqualTo: outfitterId)
        .get();
    final farmNames = <String, String>{};
    for (final f in farmSnap.docs) {
      farmNames[f.id] = (f['name'] ?? 'Unknown Farm') as String;
    }

    // Farm managers directory.
    final managerSnap = await FirebaseFirestore.instance
        .collection('farm_managers')
        .where('outfitterId', isEqualTo: outfitterId)
        .get();
    final managers = managerSnap.docs.map((d) {
      final m = d.data();
      final farmId = (m['farmId'] ?? '') as String;
      return {
        'name': (m['managerName'] ?? m['name'] ?? 'Unknown') as String,
        'cell': (m['managerCell'] ?? m['cellNr'] ?? '') as String,
        'farm': farmNames[farmId] ?? 'Unassigned',
      };
    }).toList();

    // Active packages count.
    final packageSnap = await FirebaseFirestore.instance
        .collection('packages')
        .where('outfitterId', isEqualTo: outfitterId)
        .where('status', isEqualTo: 'active')
        .get();
    final totalPackages = packageSnap.docs.length;

    // Pending bookings count.
    final pendingSnap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('outfitterId', isEqualTo: outfitterId)
        .where('status', isEqualTo: 'Pending Approval')
        .get();
    final pendingBookings = pendingSnap.docs.length;

    final doc = await JagSpoorPdfDocument.create(
      title: 'Revenue & Farm Analytics Report',
      documentId: 'ANALYTICS-${DateTime.now().millisecondsSinceEpoch}',
    );

    doc.addPage(
      margin: 28,
      content: _buildContent(
        grossEarnings: grossEarnings,
        netEarnings: netEarnings,
        totalBookings: totalBookings,
        totalFarms: farmNames.length,
        totalManagers: managers.length,
        totalPackages: totalPackages,
        pendingBookings: pendingBookings,
        managers: managers,
      ),
    );

    await doc.saveAndShare(
      filename: 'JagSpoor_Revenue_Analytics_Report',
      shareSubject: 'JagSpoor Revenue & Farm Analytics Report',
      shareText: 'Outfitter revenue, net earnings & farm manager directory',
    );
  }

  pw.Widget _buildContent({
    required double grossEarnings,
    required double netEarnings,
    required int totalBookings,
    required int totalFarms,
    required int totalManagers,
    required int totalPackages,
    required int pendingBookings,
    required List<Map<String, String>> managers,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Revenue summary ──
        JagSpoorPdfTheme.sectionBar('Revenue Summary (ZAR)'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.currencyRow('Gross Revenue', grossEarnings),
          JagSpoorPdfTheme.currencyRow('Net Earnings', netEarnings,
              bold: true),
        ]),
        pw.SizedBox(height: 4),
        pw.Text(
            'Net earnings equal gross revenue (no platform commission is '
            'deducted). Based on approved bookings.',
            style: JagSpoorPdfTheme.caption),

        // ── Enterprise metrics ──
        JagSpoorPdfTheme.sectionBar('Enterprise Metrics'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Approved Bookings', '$totalBookings'),
          JagSpoorPdfTheme.infoRow('Pending Bookings', '$pendingBookings'),
          JagSpoorPdfTheme.infoRow('Active Packages', '$totalPackages'),
          JagSpoorPdfTheme.infoRow('Registered Farms', '$totalFarms'),
          JagSpoorPdfTheme.infoRow('Assigned Farm Managers', '$totalManagers'),
        ]),

        // ── Farm manager directory ──
        JagSpoorPdfTheme.sectionBar('Farm Manager Directory'),
        if (managers.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text('No farm managers assigned.',
                style: JagSpoorPdfTheme.body),
          )
        else
          JagSpoorPdfTheme.dataTable(
            headers: ['Manager Name', 'Cell Phone', 'Assigned Farm'],
            columnWidths: [160, 130, 130],
            rows: managers
                .map((m) => [
                      m['name']!,
                      m['cell']!.isEmpty ? '-' : m['cell']!,
                      m['farm']!,
                    ])
                .toList(),
          ),
      ],
    );
  }
}
