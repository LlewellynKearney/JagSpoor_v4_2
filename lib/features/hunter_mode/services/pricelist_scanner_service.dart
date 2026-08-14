import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/offline_stream_guard.dart';
import 'gemini_vision_extractor.dart';
import 'pricelist_text_parser.dart';

/// Central AI-driven price list processor and custom tracking service engine.
///
/// Extraction is **dynamic**: the scanned document is sent to Google Gemini
/// Vision (when `GEMINI_API_KEY` is configured) which returns a structured
/// JSON list of species/sex/size/price rows, then routed through the
/// Afrikaans-aware [PricelistTextParser] so South African English + Afrikaans
/// terms map to the project's canonical species IDs while the original
/// scanned display label is preserved. No hardcoded mock species list is
/// returned — output is always a function of the actual document content.
class PricelistScannerService {
  static final PricelistScannerService instance =
      PricelistScannerService._internal();
  PricelistScannerService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Platform commission rate (7.5%)
  static const double platformCommissionRate = 0.075;

  /// Gemini Vision extractor (no-op when `GEMINI_API_KEY` is absent).
  final GeminiVisionExtractor _gemini = GeminiVisionExtractor();

  /// Whether AI (Gemini Vision) extraction is available in this environment.
  bool get isAiExtractionAvailable => _gemini.isAvailable;

  /// Dynamically extracts price-list line items from the scanned [imageFile]
  /// (image or PDF).
  ///
  /// Pipeline:
  /// 1. Send the file to Gemini Vision → structured JSON rows.
  /// 2. Normalise the JSON through [PricelistTextParser] (Afrikaans → system
  ///    species IDs, sex/class bucketing, trophy size ranges, ZAR prices).
  /// 3. Return structured items for the verification screen.
  ///
  /// Throws [StateError] when AI extraction is not configured (no API key),
  /// so the caller can surface a clear "configure GEMINI_API_KEY" message
  /// instead of returning fabricated data.
  Future<List<Map<String, dynamic>>> extractPricelistItems({
    required String farmId,
    required File imageFile,
  }) async {
    final List<PricelistItem> items = await _gemini.extract(imageFile);

    final processedItems = items.map(_itemToExtractedMap).toList();

    print(
      '✅ Pricelist dynamically extracted: ${processedItems.length} items '
      'ready for verification',
    );
    return processedItems;
  }

  /// Parses raw price-list text (e.g. from an on-device OCR engine or a PDF
  /// text layer) into structured items. Exposed so the parser pipeline can be
  /// reused/tested independently of the Gemini Vision call.
  List<Map<String, dynamic>> parseRawText(String rawText) {
    final parser = PricelistTextParser();
    return parser.parse(rawText).map(_itemToExtractedMap).toList();
  }

  Map<String, dynamic> _itemToExtractedMap(PricelistItem item) {
    final basePrice = item.priceZAR;
    final hunterPrice = basePrice * (1 + platformCommissionRate);
    return {
      'name': item.displayLabel,
      'displayLabel': item.displayLabel,
      'speciesName': item.speciesName,
      'speciesId': item.speciesId,
      'sex': item.sex,
      'sexLabel': item.sexLabel,
      'trophySizeRange': item.trophySizeRange,
      'itemType': item.itemType,
      'feeType': item.feeType,
      'outfitterBasePrice': basePrice,
      'hunterDisplayPriceZAR': hunterPrice,
      'basePriceFormatted': 'R${basePrice.toStringAsFixed(0)}',
      'hunterPriceFormatted': 'R${hunterPrice.toStringAsFixed(0)}',
      'commissionZAR': hunterPrice - basePrice,
    };
  }

  /// Processes and uploads a price list image to Firestore.
  ///
  /// This method is kept for backward compatibility. New code should use
  /// [extractPricelistItems] followed by
  /// [OutfitterPricelistVerificationScreen] for the proper workflow.
  Future<void> processAndUploadPricelistImage({
    required String farmId,
    required File imageFile,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated to upload price lists');
    }

    // Dynamic extraction (Gemini Vision) — no hardcoded mock.
    final List<PricelistItem> items = await _gemini.extract(imageFile);

    final processedItems = items.map((item) {
      final basePrice = item.priceZAR;
      final hunterPrice = basePrice * (1 + platformCommissionRate);
      return {
        'name': item.displayLabel,
        'displayLabel': item.displayLabel,
        'speciesName': item.speciesName,
        'speciesId': item.speciesId,
        'sex': item.sex,
        'sexLabel': item.sexLabel,
        'trophySizeRange': item.trophySizeRange,
        'itemType': item.itemType,
        'feeType': item.feeType,
        'outfitterBasePrice': basePrice,
        'hunterDisplayPriceZAR': hunterPrice,
        'basePriceFormatted': 'R${basePrice.toStringAsFixed(0)}',
        'hunterPriceFormatted': 'R${hunterPrice.toStringAsFixed(0)}',
        'commissionZAR': hunterPrice - basePrice,
      };
    }).toList();

    // Create structured document for Firestore
    final pricelistData = {
      'outfitterId': currentUser.uid,
      'farmId': farmId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'sourceImage':
          imageFile.path.split('/').last, // Store filename for reference
      'items': processedItems,
      'totalItems': processedItems.length,
      'processingVersion': '2.0.0',
    };

    // Upload to scanned_pricelists collection
    await _firestore.collection('scanned_pricelists').add(pricelistData);

    print('✅ Pricelist processed and uploaded: ${processedItems.length} items');
  }

  /// Submits a custom-built package booking request.
  ///
  /// This is used when hunters select items from scanned price lists
  /// to create a custom itinerary rather than booking a pre-defined package.
  ///
  /// Parameters:
  /// - [farmId]: The farm/concession where the hunt will take place
  /// - [outfitterId]: The UID of the outfitter who owns the farm
  /// - [selectedItems]: List of selected items with pricing from the price list
  /// - [combinedTotalZAR]: Total price including 7.5% platform fee
  ///
  /// Saves to the 'bookings' collection with status 'Pending Approval'
  Future<void> submitCustomPackageBooking({
    required String farmId,
    required String outfitterId,
    required List<Map<String, dynamic>> selectedItems,
    required double combinedTotalZAR,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated to book');
    }

    // Prevent outfitters from booking their own packages
    if (currentUser.uid == outfitterId) {
      throw Exception('Outfitters cannot book their own packages');
    }

    // Validate inputs
    if (selectedItems.isEmpty) {
      throw Exception('At least one item must be selected');
    }
    if (combinedTotalZAR <= 0) {
      throw Exception('Total price must be greater than zero');
    }

    // Calculate commission breakdown
    final double basePrice = combinedTotalZAR / (1 + platformCommissionRate);
    final double platformFee = combinedTotalZAR - basePrice;

    // Build booking payload
    final bookingData = {
      'packageId': 'CUSTOM_BUILT', // Indicates custom itinerary
      'outfitterId': outfitterId,
      'farmId': farmId,
      'hunterId': currentUser.uid,
      'bookingType': 'custom_pricelist',
      'selectedItemsList':
          selectedItems
              .map(
                (item) => {
                  'name': item['name'] ?? 'Unknown',
                  'basePrice': item['outfitterBasePrice'] ?? 0.0,
                  'hunterPrice': item['hunterDisplayPriceZAR'] ?? 0.0,
                },
              )
              .toList(),
      'basePriceRands': basePrice,
      'platformCommissionRands': platformFee,
      'totalHunterPriceRands': combinedTotalZAR,
      'status': 'Pending Approval',
      'bookingTimestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Save to bookings collection
    await _firestore.collection('bookings').add(bookingData);

    print(
      '✅ Custom package booking submitted: ${selectedItems.length} items, Total: R${combinedTotalZAR.toStringAsFixed(2)}',
    );
  }

  /// Retrieves all scanned price lists for a specific farm.
  ///
  /// Parameters:
  /// - [farmId]: The farm/concession to query
  /// - [activeOnly]: If true, only returns active price lists (default: true)
  ///
  /// Returns a list of price list documents
  Future<List<Map<String, dynamic>>> getPriceListsForFarm(
    String farmId, {
    bool activeOnly = true,
  }) async {
    Query query = _firestore
        .collection('scanned_pricelists')
        .where('farmId', isEqualTo: farmId);

    if (activeOnly) {
      query = query.where('status', isEqualTo: 'active');
    }

    final snapshot = await query.orderBy('createdAt', descending: true).get();

    return snapshot.docs.map((doc) {
      final rawData = doc.data();
      final data = Map<String, dynamic>.from(
        rawData is Map ? rawData : <String, dynamic>{},
      );
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// Retrieves all scanned price lists for the current outfitter.
  ///
  /// Returns a list of price list documents created by the authenticated outfitter
  Future<List<Map<String, dynamic>>> getMyPriceLists() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated');
    }

    final snapshot =
        await _firestore
            .collection('scanned_pricelists')
            .where('outfitterId', isEqualTo: currentUser.uid)
            .orderBy('createdAt', descending: true)
            .get();

    return snapshot.docs.map((doc) {
      final rawData = doc.data();
      final data = Map<String, dynamic>.from(
        rawData is Map ? rawData : <String, dynamic>{},
      );
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// Returns a reactive stream of the authenticated outfitter's scanned price
  /// lists, most recent first. Excludes soft-deleted entries.
  ///
  /// Used by [ScannedPriceListHistoryScreen] for the persistent scan history
  /// log. The query is `outfitterId` (equality) + `status` (equality) +
  /// `createdAt` (descending), which requires the `scanned_pricelists`
  /// composite index in `firestore.indexes.json`.
  Stream<List<Map<String, dynamic>>> getMyPriceListsStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      // Unauthenticated callers get a stable empty stream instead of a thrown
      // exception that would crash the history screen's StreamBuilder.
      return Stream.value(const <Map<String, dynamic>>[]);
    }

    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('scanned_pricelists')
          .where('outfitterId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) {
                final data = Map<String, dynamic>.from(doc.data());
                data['id'] = doc.id;
                return data;
              }).toList()),
      fallback: const <Map<String, dynamic>>[],
      debugLabel: 'scanned_pricelists',
    );
  }

  /// Persists a verified/edited price list to the `scanned_pricelists`
  /// collection. Centralised so both the verification screen and the history
  /// re-export flow write through one path.
  ///
  /// Parameters:
  /// - [items]: parsed species/line items with `name`, `outfitterBasePrice`,
  ///   `hunterDisplayPriceZAR`, `commissionZAR` (7.5% split).
  /// - [farmId], [farmName], [imageFileName]: provenance metadata.
  Future<String> saveVerifiedPricelist({
    required List<Map<String, dynamic>> items,
    String? farmId,
    String? farmName,
    String? imageFileName,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated to save price list');
    }

    final pricelistData = {
      'outfitterId': currentUser.uid,
      'farmId': farmId ?? '',
      'farmName': farmName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'sourceImage': imageFileName ?? 'unknown',
      'items': items,
      'totalItems': items.length,
      'processingVersion': '2.0.0',
    };

    final docRef =
        await _firestore.collection('scanned_pricelists').add(pricelistData);
    return docRef.id;
  }

  /// Calculates the total for selected price list items including 7.5% platform fee.
  ///
  /// Parameters:
  /// - [selectedItems]: List of selected items with base prices
  ///
  /// Returns the total price including platform fee
  double calculateTotalWithFee(List<Map<String, dynamic>> selectedItems) {
    double baseTotal = 0;

    for (final item in selectedItems) {
      final basePrice = (item['outfitterBasePrice'] ?? 0.0).toDouble();
      baseTotal += basePrice;
    }

    return baseTotal * (1 + platformCommissionRate);
  }

  /// Deletes (archives) a scanned price list by setting status to 'deleted'.
  ///
  /// Parameters:
  /// - [pricelistId]: The document ID of the price list to delete
  Future<void> deletePriceList(String pricelistId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated');
    }

    // Verify ownership before deletion
    final doc =
        await _firestore
            .collection('scanned_pricelists')
            .doc(pricelistId)
            .get();
    if (!doc.exists) {
      throw Exception('Price list not found');
    }

    final data = doc.data();
    if (data == null || data['outfitterId'] != currentUser.uid) {
      throw Exception('You can only delete your own price lists');
    }

    // Soft delete by updating status
    await _firestore.collection('scanned_pricelists').doc(pricelistId).update({
      'status': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
