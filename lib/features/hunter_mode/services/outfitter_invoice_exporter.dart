import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';
import '../models/package_pricing.dart';

/// Booking invoice / confirmation PDF rendered through the universal
/// [JagSpoorPdfDocument] engine.
///
/// Produces a standardized invoice with:
///  - the itemized line-item breakdown (or all-inclusive total) sourced from
///    the linked hunting package,
///  - the 7.5% platform commission row,
///  - the 25% non-refundable deposit status + balance, and
///  - the date-change history for the booking (if any).
class OutfitterInvoiceExporter {
  /// Generates and shares the invoice PDF.
  ///
  /// [bookingData] is the raw booking document map. The linked package's
  /// pricing breakdown (itemized line items / species / all-inclusive price /
  /// availability window) is fetched from the `packages` collection via
  /// `bookingData['packageId']` so the invoice shows the full breakdown even
  /// though the booking itself only snapshots the base price.
  Future<void> generateAndShareInvoice({
    required String bookingId,
    required Map<String, dynamic> bookingData,
  }) async {
    final packageName =
        bookingData['packageName'] as String? ?? 'Hunting Package';
    final farmName = bookingData['farmName'] as String? ?? 'Outfitter Farm';
    final hunterName = bookingData['hunterName'] as String? ?? 'Hunter';
    final basePrice = (bookingData['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    final platformFee =
        (bookingData['platformCommissionRands'] as num?)?.toDouble() ?? 0.0;
    final totalPrice =
        (bookingData['totalHunterPriceRands'] as num?)?.toDouble() ?? 0.0;
    final depositAmount =
        (bookingData['depositAmountRands'] as num?)?.toDouble() ?? 0.0;
    final balanceAmount =
        (bookingData['balanceAmountRands'] as num?)?.toDouble() ?? 0.0;
    final status = bookingData['status']?.toString() ?? 'Pending Approval';

    // Fetch the linked package to recover the itemized breakdown.
    PackagePricing? pricing;
    final packageId = bookingData['packageId'] as String?;
    if (packageId != null && packageId.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('packages')
            .doc(packageId)
            .get();
        if (snap.exists) {
          pricing = PackagePricing.fromMap(snap.data()!);
        }
      } catch (_) {
        // Non-fatal — falls back to base-price-only invoice.
      }
    }

    final dateChange =
        bookingData['dateChangeRequest'] as Map<String, dynamic>?;

    final doc = await JagSpoorPdfDocument.create(
      title: 'Booking Invoice & Confirmation',
      documentId: bookingId,
    );

    doc.addPage(
      margin: 30,
      content: _buildContent(
        bookingId: bookingId,
        packageName: packageName,
        farmName: farmName,
        hunterName: hunterName,
        basePrice: basePrice,
        platformFee: platformFee,
        totalPrice: totalPrice,
        depositAmount: depositAmount,
        balanceAmount: balanceAmount,
        status: status,
        pricing: pricing,
        dateChange: dateChange,
      ),
    );

    final sanitized = bookingId.replaceAll(RegExp(r'[^\w\-]'), '_');
    await doc.saveAndShare(
      filename: 'JagSpoor_Invoice_$sanitized',
      shareSubject: 'JagSpoor Booking Invoice - $bookingId',
      shareText: 'JagSpoor booking confirmation/invoice for $hunterName',
    );
  }

  pw.Widget _buildContent({
    required String bookingId,
    required String packageName,
    required String farmName,
    required String hunterName,
    required double basePrice,
    required double platformFee,
    required double totalPrice,
    required double depositAmount,
    required double balanceAmount,
    required String status,
    PackagePricing? pricing,
    Map<String, dynamic>? dateChange,
  }) {
    final isItemized =
        pricing != null && pricing.mode == PackagePricingMode.itemized;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Status banner
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: JagSpoorPdfTheme.accent,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'BOOKING CONFIRMATION & INVOICE',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: JagSpoorPdfTheme.white,
                ),
              ),
              pw.Text(
                status.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: JagSpoorPdfTheme.white,
                ),
              ),
            ],
          ),
        ),

        // ── Booking details ──
        JagSpoorPdfTheme.sectionBar('Booking Details'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Booking ID', bookingId),
          JagSpoorPdfTheme.infoRow('Hunter / Guest', hunterName),
          JagSpoorPdfTheme.infoRow('Concession Property', farmName),
          JagSpoorPdfTheme.infoRow('Package Reserved', packageName),
          if (pricing != null) ...[
            JagSpoorPdfTheme.infoRow(
                'Pricing Mode',
                pricing.mode == PackagePricingMode.allInclusive
                    ? 'All-Inclusive'
                    : 'Itemized / Custom Package'),
            JagSpoorPdfTheme.infoRow('Availability Start',
                JagSpoorPdfTheme.formatDate(pricing.availabilityStart)),
            JagSpoorPdfTheme.infoRow('Availability End',
                JagSpoorPdfTheme.formatDate(pricing.availabilityEnd)),
          ],
        ]),

        // ── Fee breakdown ──
        JagSpoorPdfTheme.sectionBar('Fee Breakdown (ZAR)'),
        if (isItemized) ...[
          if (pricing.lineItems.isNotEmpty) ...[
            pw.Text('Itemized Line Items',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: JagSpoorPdfTheme.deepBrown)),
            pw.SizedBox(height: 4),
            JagSpoorPdfTheme.dataTable(
              headers: ['Description', 'Qty', 'Unit Price', 'Subtotal'],
              columnWidths: [200, 50, 80, 80],
              rows: pricing.lineItems
                  .where((i) => i.quantity > 0)
                  .map((i) => [
                        i.label,
                        i.quantity.toString(),
                        JagSpoorPdfTheme.formatZAR(i.pricePerUnit),
                        JagSpoorPdfTheme.formatZAR(i.total),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 8),
          ],
          if (pricing.speciesItems.isNotEmpty) ...[
            pw.Text('Species (per Animal)',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: JagSpoorPdfTheme.deepBrown)),
            pw.SizedBox(height: 4),
            JagSpoorPdfTheme.dataTable(
              headers: ['Species', 'Qty', 'Price / Animal', 'Subtotal'],
              columnWidths: [200, 50, 80, 80],
              rows: pricing.speciesItems
                  .map((s) => [
                        s.speciesName,
                        s.quantity.toString(),
                        JagSpoorPdfTheme.formatZAR(s.pricePerAnimal),
                        JagSpoorPdfTheme.formatZAR(s.total),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 8),
          ],
        ],
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.currencyRow('Outfitter Base Price', basePrice),
          JagSpoorPdfTheme.currencyRow(
              'Platform Commission (7.5%)', platformFee,
              emphasis: true),
          pw.Divider(color: JagSpoorPdfTheme.divider, height: 8),
          JagSpoorPdfTheme.currencyRow(
              'Total Package Value', basePrice + platformFee,
              bold: true),
        ]),

        // ── Deposit status ──
        JagSpoorPdfTheme.sectionBar('Deposit Status (25% Non-Refundable)'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.currencyRow('Total Package Value', totalPrice),
          JagSpoorPdfTheme.currencyRow(
              '25% Non-Refundable Deposit', depositAmount,
              emphasis: true),
          pw.Divider(color: JagSpoorPdfTheme.divider, height: 8),
          JagSpoorPdfTheme.currencyRow('Balance Due on Arrival', balanceAmount),
        ]),
        pw.SizedBox(height: 4),
        pw.Text(
            'A 25% non-refundable deposit secures this booking. The balance is '
            'payable directly to the outfitter on arrival.',
            style: JagSpoorPdfTheme.caption),

        // ── Date change history ──
        if (dateChange != null) ...[
          JagSpoorPdfTheme.sectionBar('Date Change Request History'),
          _dateChangeBlock(dateChange),
        ],
      ],
    );
  }

  pw.Widget _dateChangeBlock(Map<String, dynamic> dc) {
    final requestedStart = _toDate(dc['requestedStartDate']);
    final requestedEnd = _toDate(dc['requestedEndDate']);
    final reason = dc['reason']?.toString() ?? '';
    final status = dc['status']?.toString() ?? 'pending';
    final requestedAt = _toDate(dc['requestedAt']);
    final resolvedAt = _toDate(dc['resolvedAt']);

    return JagSpoorPdfTheme.detailBox([
      JagSpoorPdfTheme.infoRow(
          'Status', status[0].toUpperCase() + status.substring(1)),
      JagSpoorPdfTheme.infoRow(
          'Requested Start', JagSpoorPdfTheme.formatDate(requestedStart)),
      JagSpoorPdfTheme.infoRow(
          'Requested End', JagSpoorPdfTheme.formatDate(requestedEnd)),
      JagSpoorPdfTheme.infoRow('Reason', reason),
      JagSpoorPdfTheme.infoRow(
          'Requested At', JagSpoorPdfTheme.formatDate(requestedAt)),
      JagSpoorPdfTheme.infoRow(
          'Resolved At', JagSpoorPdfTheme.formatDate(resolvedAt)),
    ]);
  }

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
