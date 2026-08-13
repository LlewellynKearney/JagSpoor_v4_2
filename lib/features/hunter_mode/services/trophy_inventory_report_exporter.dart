import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/pdf_document_engine.dart';

/// Farm-grouped trophy stock report PDF, rendered through the universal
/// [JagSpoorPdfDocument] engine. Lists every trophy entry grouped by farm with
/// species, quantity, price per animal, trophy measurement (inches), and the
/// number of attached photos.
class TrophyInventoryReportExporter {
  /// Generates and shares the trophy inventory report PDF for the signed-in
  /// outfitter. Fetches the outfitter's farms + trophy stock and groups the
  /// entries by farm.
  Future<void> generateAndShare() async {
    final outfitterId = FirebaseAuth.instance.currentUser?.uid;
    if (outfitterId == null) {
      throw Exception('User must be authenticated to export the trophy report');
    }

    final farmNames = <String, String>{};
    final byFarm = <String, List<Map<String, dynamic>>>{};
    double totalStockValue = 0;
    int totalAnimals = 0;
    int totalPhotos = 0;

    // Farms.
    final farmSnap = await FirebaseFirestore.instance
        .collection('farms')
        .where('outfitterId', isEqualTo: outfitterId)
        .get();
    for (final f in farmSnap.docs) {
      farmNames[f.id] = (f['name'] ?? 'Unknown Farm') as String;
      byFarm[f.id] = [];
    }

    // Trophies.
    final trophySnap = await FirebaseFirestore.instance
        .collection('trophies')
        .where('outfitterId', isEqualTo: outfitterId)
        .get();
    for (final t in trophySnap.docs) {
      final data = t.data();
      final farmId = (data['farmId'] ?? '') as String;
      byFarm.putIfAbsent(farmId, () => []).add(data);

      final qty = (data['quantity'] as num?)?.toInt() ?? 1;
      final price = (data['pricePerAnimal'] as num?)?.toDouble() ?? 0.0;
      totalStockValue += price * qty;
      totalAnimals += qty;
      final photos = (data['trophyPhotoUrls'] as List?)?.length ?? 0;
      totalPhotos += photos;
    }

    final doc = await JagSpoorPdfDocument.create(
      title: 'Trophy Inventory Report',
      documentId: 'TROPHY-${DateTime.now().millisecondsSinceEpoch}',
    );

    doc.addPage(
      margin: 28,
      content: _buildContent(
        byFarm: byFarm,
        farmNames: farmNames,
        totalStockValue: totalStockValue,
        totalAnimals: totalAnimals,
        totalPhotos: totalPhotos,
      ),
    );

    await doc.saveAndShare(
      filename: 'JagSpoor_Trophy_Inventory_Report',
      shareSubject: 'JagSpoor Trophy Inventory Report',
      shareText: 'Farm-grouped trophy inventory stock report',
    );
  }

  pw.Widget _buildContent({
    required Map<String, List<Map<String, dynamic>>> byFarm,
    required Map<String, String> farmNames,
    required double totalStockValue,
    required int totalAnimals,
    required int totalPhotos,
  }) {
    final farmIds = byFarm.keys.toList()..sort();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Summary metrics
        JagSpoorPdfTheme.sectionBar('Inventory Summary'),
        JagSpoorPdfTheme.detailBox([
          JagSpoorPdfTheme.infoRow('Farms Registered', '${farmNames.length}'),
          JagSpoorPdfTheme.infoRow('Total Animals in Stock', '$totalAnimals'),
          JagSpoorPdfTheme.infoRow(
              'Total Attached Photos', '$totalPhotos'),
          JagSpoorPdfTheme.infoRow(
              'Estimated Stock Value', JagSpoorPdfTheme.formatZAR(totalStockValue)),
        ]),

        JagSpoorPdfTheme.sectionBar('Trophy Stock by Farm'),
        if (farmIds.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text('No trophy stock recorded.',
                style: JagSpoorPdfTheme.body),
          )
        else
          ...farmIds.map((farmId) => _farmSection(farmId, byFarm[farmId]!,
              farmNames[farmId] ?? _fallbackName(farmId))),
      ],
    );
  }

  pw.Widget _farmSection(
      String farmId, List<Map<String, dynamic>> trophies, String farmName) {
    double farmValue = 0;
    int farmAnimals = 0;
    int farmPhotos = 0;
    for (final t in trophies) {
      final qty = (t['quantity'] as num?)?.toInt() ?? 1;
      final price = (t['pricePerAnimal'] as num?)?.toDouble() ?? 0.0;
      farmValue += price * qty;
      farmAnimals += qty;
      farmPhotos += (t['trophyPhotoUrls'] as List?)?.length ?? 0;
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: JagSpoorPdfTheme.band,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: JagSpoorPdfTheme.divider, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(farmName,
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: JagSpoorPdfTheme.deepBrown)),
              pw.Text(
                  '$farmAnimals animals - ${JagSpoorPdfTheme.formatZAR(farmValue)} - $farmPhotos photos',
                  style: JagSpoorPdfTheme.caption),
            ],
          ),
          pw.SizedBox(height: 6),
          if (trophies.isEmpty)
            pw.Text('No trophy stock on this farm.',
                style: JagSpoorPdfTheme.body)
          else
            JagSpoorPdfTheme.dataTable(
              headers: ['Species', 'Qty', 'Price/Animal', 'Measurement (in)', 'Photos'],
              columnWidths: [150, 40, 80, 90, 50],
              rows: trophies.map((t) {
                final qty = (t['quantity'] as num?)?.toInt() ?? 1;
                final price =
                    (t['pricePerAnimal'] as num?)?.toDouble() ?? 0.0;
                final measurement = (t['trophyMeasurement'] ??
                        t['trophyLengthInches']) as num?;
                final photoCount = (t['trophyPhotoUrls'] as List?)?.length ?? 0;
                return [
                  (t['species'] ?? 'Unknown').toString(),
                  qty.toString(),
                  JagSpoorPdfTheme.formatZAR(price),
                  measurement == null
                      ? '-'
                      : measurement.toStringAsFixed(1),
                  photoCount.toString(),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _fallbackName(String farmId) {
    if (farmId.isEmpty) return 'Unassigned Farm';
    final short = farmId.length > 6 ? farmId.substring(0, 6) : farmId;
    return 'Farm $short…';
  }
}
