import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:jagspoor/core/services/pdf_document_engine.dart';
import 'package:jagspoor/features/hunter_mode/services/revenue_analytics_report_exporter.dart';

/// Unit tests for the Enterprise Business Intelligence (Revenue & Farm
/// Analytics) PDF exporter's Farm Revenue Breakdown.
///
/// `RevenueAnalyticsReportExporter.aggregateFarmRevenue` is a pure static
/// function over raw booking document maps + a farmId->name map, so the
/// per-farm revenue contract is fully unit-testable without the Firestore
/// emulator (which cannot run in this sandbox -- see AGENTS.md environment
/// constraints). The PDF content builder is exercised by rendering the full
/// branded document to bytes (mirrors `farm_price_list_pdf_exporter_test`).
void main() {
  // The PDF engine loads the logo via rootBundle, which requires the Flutter
  // platform binding to be initialized before the asset bundle is read.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RevenueAnalyticsReportExporter.aggregateFarmRevenue', () {
    test('returns empty when there are no farms and no bookings', () {
      expect(
        RevenueAnalyticsReportExporter.aggregateFarmRevenue(
            const [], const {}),
        isEmpty,
      );
    });

    test('lists every registered farm at R 0.00 when there are no bookings',
        () {
      final rows = RevenueAnalyticsReportExporter.aggregateFarmRevenue(
        const [],
        const {'farm-1': 'Bosveld Ranch', 'farm-2': 'Karoo Plains'},
      );
      expect(rows.length, 2);
      for (final row in rows) {
        expect(row['revenue'], 0.0);
        expect(row['bookings'], 0);
      }
      // Alphabetical tie-break at zero revenue.
      expect(rows[0]['farm'], 'Bosveld Ranch');
      expect(rows[1]['farm'], 'Karoo Plains');
    });

    test('aggregates booking revenue per farmId (base price preferred)', () {
      final rows = RevenueAnalyticsReportExporter.aggregateFarmRevenue(
        [
          {
            'farmId': 'farm-1',
            'basePriceRands': 10000.0,
            'totalHunterPriceRands': 10750.0, // legacy marked-up total ignored
          },
          {
            'farmId': 'farm-1',
            'basePriceRands': 5000.0,
          },
          {
            'farmId': 'farm-2',
            'basePriceRands': 8000.0,
          },
        ],
        const {'farm-1': 'Bosveld Ranch', 'farm-2': 'Karoo Plains'},
      );

      expect(rows.length, 2);
      // Sorted by revenue desc.
      expect(rows[0]['farm'], 'Bosveld Ranch');
      expect(rows[0]['revenue'], 15000.0);
      expect(rows[0]['bookings'], 2);
      expect(rows[1]['farm'], 'Karoo Plains');
      expect(rows[1]['revenue'], 8000.0);
      expect(rows[1]['bookings'], 1);
    });

    test('falls back to the stored total when the base price is absent', () {
      final rows = RevenueAnalyticsReportExporter.aggregateFarmRevenue(
        [
          {'farmId': 'farm-1', 'totalHunterPriceRands': 7500.0},
        ],
        const {'farm-1': 'Bosveld Ranch'},
      );
      expect(rows.single['revenue'], 7500.0);
    });

    test('groups bookings with a missing / unknown farmId under '
        'Unassigned / Other', () {
      final rows = RevenueAnalyticsReportExporter.aggregateFarmRevenue(
        [
          {'basePriceRands': 3000.0}, // no farmId
          {'farmId': 'farm-deleted', 'basePriceRands': 2000.0},
          {'farmId': 'farm-1', 'basePriceRands': 10000.0},
        ],
        const {'farm-1': 'Bosveld Ranch'},
      );

      expect(rows.length, 2);
      expect(rows[0]['farm'], 'Bosveld Ranch');
      expect(rows[1]['farm'], 'Unassigned / Other');
      expect(rows[1]['revenue'], 5000.0);
      expect(rows[1]['bookings'], 2);
    });

    test('omits the Unassigned / Other row when every booking maps to a '
        'registered farm', () {
      final rows = RevenueAnalyticsReportExporter.aggregateFarmRevenue(
        [
          {'farmId': 'farm-1', 'basePriceRands': 10000.0},
        ],
        const {'farm-1': 'Bosveld Ranch'},
      );
      expect(rows.length, 1);
      expect(rows.single['farm'], 'Bosveld Ranch');
    });

    test('keeps zero-revenue farms listed after revenue-generating farms', () {
      final rows = RevenueAnalyticsReportExporter.aggregateFarmRevenue(
        [
          {'farmId': 'farm-2', 'basePriceRands': 8000.0},
        ],
        const {'farm-1': 'Bosveld Ranch', 'farm-2': 'Karoo Plains'},
      );
      expect(rows.length, 2);
      expect(rows[0]['farm'], 'Karoo Plains');
      expect(rows[0]['revenue'], 8000.0);
      expect(rows[1]['farm'], 'Bosveld Ranch');
      expect(rows[1]['revenue'], 0.0);
    });

    test('a booking with no farmId but farms registered still rolls up to '
        'Unassigned / Other', () {
      final rows = RevenueAnalyticsReportExporter.aggregateFarmRevenue(
        [
          {'basePriceRands': 4000.0},
        ],
        const {'farm-1': 'Bosveld Ranch'},
      );
      expect(rows.length, 2);
      final unassigned =
          rows.firstWhere((r) => r['farm'] == 'Unassigned / Other');
      expect(unassigned['revenue'], 4000.0);
    });
  });

  group('RevenueAnalyticsReportExporter.buildContent', () {
    RevenueAnalyticsReportExporter exporter() =>
        RevenueAnalyticsReportExporter();

    test('returns a pw.Widget with farm revenue rows (does not throw)', () {
      final widget = exporter().buildContent(
        grossEarnings: 15000.0,
        netEarnings: 15000.0,
        totalBookings: 2,
        totalFarms: 1,
        totalManagers: 0,
        totalPackages: 3,
        pendingBookings: 1,
        managers: const [],
        farmRevenue: const [
          {
            'farmId': 'farm-1',
            'farm': 'Bosveld Ranch',
            'revenue': 15000.0,
            'bookings': 2,
          },
        ],
      );
      expect(widget, isA<pw.Widget>());
    });

    test('handles an empty farm revenue list (no farms registered)', () {
      final widget = exporter().buildContent(
        grossEarnings: 0.0,
        netEarnings: 0.0,
        totalBookings: 0,
        totalFarms: 0,
        totalManagers: 0,
        totalPackages: 0,
        pendingBookings: 0,
        managers: const [],
        farmRevenue: const [],
      );
      expect(widget, isA<pw.Widget>());
    });
  });

  group('RevenueAnalyticsReportExporter — full branded PDF render', () {
    // Renders the exporter's content through the real JagSpoorPdfDocument
    // engine (logo header + footer + the content) and saves the bytes.
    Future<List<int>> renderToBytes({
      required List<Map<String, dynamic>> farmRevenue,
    }) async {
      final doc = await JagSpoorPdfDocument.create(
        title: 'Revenue & Farm Analytics Report',
        documentId: 'ANALYTICS-test',
      );
      doc.addPage(
        margin: 28,
        content: RevenueAnalyticsReportExporter().buildContent(
          grossEarnings: 23000.0,
          netEarnings: 23000.0,
          totalBookings: 3,
          totalFarms: 2,
          totalManagers: 1,
          totalPackages: 4,
          pendingBookings: 1,
          managers: const [
            {'name': 'Pieter', 'cell': '0820000000', 'farm': 'Bosveld Ranch'},
          ],
          farmRevenue: farmRevenue,
        ),
      );
      return doc.saveBytes();
    }

    test('renders the farm revenue breakdown to a valid PDF', () async {
      final bytes = await renderToBytes(
        farmRevenue: const [
          {
            'farmId': 'farm-1',
            'farm': 'Bosveld Ranch',
            'revenue': 15000.0,
            'bookings': 2,
          },
          {
            'farmId': 'farm-2',
            'farm': 'Karoo Plains',
            'revenue': 8000.0,
            'bookings': 1,
          },
        ],
      );
      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header.startsWith('%PDF-'), isTrue,
          reason: 'Output must be a valid PDF (got: $header)');
    });

    test('renders with an empty farm revenue list to a valid PDF', () async {
      final bytes = await renderToBytes(farmRevenue: const []);
      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header.startsWith('%PDF-'), isTrue);
    });
  });
}
