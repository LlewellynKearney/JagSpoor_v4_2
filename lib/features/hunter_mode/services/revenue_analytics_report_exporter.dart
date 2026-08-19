import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';
import '../models/booking_status.dart';
import '../services/outfitter_analytics_service.dart';
import 'pricing_math.dart';

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
        .where('status', isEqualTo: BookingStatus.pendingApproval)
        .get();
    final pendingBookings = pendingSnap.docs.length;

    // Earned (payment-verified) bookings -- aggregated per farm for the
    // Farm Revenue Breakdown section.
    final earnedSnap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('outfitterId', isEqualTo: outfitterId)
        .where('status',
            whereIn: OutfitterAnalyticsService.earnedBookingStatuses)
        .get();
    final farmRevenue = aggregateFarmRevenue(
      earnedSnap.docs.map((d) => d.data()),
      farmNames,
    );

    final doc = await JagSpoorPdfDocument.create(
      title: 'Revenue & Farm Analytics Report',
      documentId: 'ANALYTICS-${DateTime.now().millisecondsSinceEpoch}',
    );

    doc.addPage(
      margin: 28,
      content: buildContent(
        grossEarnings: grossEarnings,
        netEarnings: netEarnings,
        totalBookings: totalBookings,
        totalFarms: farmNames.length,
        totalManagers: managers.length,
        totalPackages: totalPackages,
        pendingBookings: pendingBookings,
        managers: managers,
        farmRevenue: farmRevenue,
      ),
    );

    await doc.saveAndShare(
      filename: 'JagSpoor_Revenue_Analytics_Report',
      shareSubject: 'JagSpoor Revenue & Farm Analytics Report',
      shareText: 'Outfitter revenue, net earnings & farm manager directory',
    );
  }

  /// Pure content builder -- returns a `pw.Widget` tree that the engine wraps
  /// in the standard branded header + footer. Stateless + side-effect free so
  /// it can be exercised in a unit test by rendering the document to bytes.
  pw.Widget buildContent({
    required double grossEarnings,
    required double netEarnings,
    required int totalBookings,
    required int totalFarms,
    required int totalManagers,
    required int totalPackages,
    required int pendingBookings,
    required List<Map<String, String>> managers,
    required List<Map<String, dynamic>> farmRevenue,
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

        // ── Farm revenue breakdown ──
        JagSpoorPdfTheme.sectionBar('Farm Revenue Breakdown (ZAR)'),
        if (farmRevenue.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text('No farms registered.',
                style: JagSpoorPdfTheme.body),
          )
        else
          JagSpoorPdfTheme.dataTable(
            headers: ['Farm', 'Bookings', 'Revenue (ZAR)'],
            columnWidths: [190, 80, 150],
            rows: farmRevenue
                .map((row) => [
                      (row['farm'] as String?) ?? 'Unknown Farm',
                      '${row['bookings'] ?? 0}',
                      JagSpoorPdfTheme.formatZAR(
                          (row['revenue'] as num?)?.toDouble() ?? 0.0),
                    ])
                .toList(),
          ),
        pw.SizedBox(height: 4),
        pw.Text(
            'Revenue per farm is aggregated from payment-verified (Confirmed '
            '/ Completed) bookings associated with each farmId.',
            style: JagSpoorPdfTheme.caption),

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

  /// Pure aggregation of per-farm revenue from booking records.
  /// Dependency-free so the breakdown can be unit-tested without the
  /// Firestore emulator.
  ///
  /// [bookings] are raw `bookings` document maps (already filtered to the
  /// earned statuses by the caller). [farmNames] maps `farmId` -> the farm's
  /// display name (from the `farms` collection).
  ///
  /// Every registered farm is listed -- a farm with no earned bookings shows
  /// R 0.00 so the report explicitly states how much revenue each farm
  /// generated. Revenue per booking is resolved via
  /// [PricingMath.resolveHunterTotal] (the base price, with the stored total
  /// as a legacy fallback). Bookings whose `farmId` is missing or does not
  /// match a registered farm are grouped under an `Unassigned / Other` row
  /// (appended last) so no revenue is silently dropped.
  ///
  /// Returns rows sorted by revenue descending (farms with zero revenue last,
  /// alphabetical tie-break), each `{farmId, farm, revenue, bookings}`.
  static List<Map<String, dynamic>> aggregateFarmRevenue(
    Iterable<Map<String, dynamic>> bookings,
    Map<String, String> farmNames,
  ) {
    final revenueByFarm = <String, double>{};
    final bookingsByFarm = <String, int>{};

    // Seed every registered farm at zero so it is explicitly listed even
    // when it has no earned bookings yet.
    for (final farmId in farmNames.keys) {
      revenueByFarm[farmId] = 0.0;
      bookingsByFarm[farmId] = 0;
    }

    const unassignedKey = '__unassigned__';
    for (final data in bookings) {
      final rawFarmId = (data['farmId'] as String?)?.trim() ?? '';
      final farmId =
          rawFarmId.isNotEmpty && farmNames.containsKey(rawFarmId)
              ? rawFarmId
              : unassignedKey;
      final revenue = PricingMath.resolveHunterTotal(
        totalHunterPrice:
            (data['totalHunterPriceRands'] as num?)?.toDouble(),
        basePrice: (data['basePriceRands'] as num?)?.toDouble() ?? 0.0,
      );
      revenueByFarm[farmId] = (revenueByFarm[farmId] ?? 0.0) + revenue;
      bookingsByFarm[farmId] = (bookingsByFarm[farmId] ?? 0) + 1;
    }

    String labelFor(String farmId) => farmId == unassignedKey
        ? 'Unassigned / Other'
        : (farmNames[farmId] ?? 'Unknown Farm');

    final rows = revenueByFarm.keys
        // Drop the unassigned bucket entirely when nothing rolled up to it.
        .where((farmId) =>
            farmId != unassignedKey || (bookingsByFarm[farmId] ?? 0) > 0)
        .map((farmId) => <String, dynamic>{
              'farmId': farmId,
              'farm': labelFor(farmId),
              'revenue': revenueByFarm[farmId],
              'bookings': bookingsByFarm[farmId] ?? 0,
            })
        .toList();
    rows.sort((a, b) {
      final byRevenue =
          (b['revenue'] as double).compareTo(a['revenue'] as double);
      if (byRevenue != 0) return byRevenue;
      return (a['farm'] as String).compareTo(b['farm'] as String);
    });
    return rows;
  }
}
