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
  /// Used when hunters assemble their own itinerary from an outfitter's active
  /// scanned price list (species/fees with quantities) instead of booking a
  /// pre-defined marketplace package.
  ///
  /// Pricing model: every line item's `unitPriceHunterZAR` already carries the
  /// **absorbed** 7.5% platform markup (it is the `hunterDisplayPriceZAR`
  /// written at scan-save time = `basePrice * 1.075`). The hunter therefore
  /// never sees an explicit "Platform Fee" line — only per-item prices and the
  /// grand total. The booking document still stores the underlying
  /// base/commission split (`basePriceRands`, `platformCommissionRands`) so the
  /// outfitter financial dashboard retains full commission visibility.
  ///
  /// Parameters:
  /// - [farmId], [farmName]: the concession where the hunt will take place.
  /// - [outfitterId]: the UID of the outfitter who owns the farm/price list.
  /// - [pricelistId]: the scanned price list the items were drawn from.
  /// - [selectedItems]: species/trophy lines — each map carries `name`,
  ///   `speciesId`, `sex`, `sexLabel`, `trophySizeRange`, `quantity`,
  ///   `unitPriceHunterZAR`, `lineTotal`.
  /// - [lodgingCatering]: fee-type lines (lodging/catering/vehicle/etc.) in
  ///   the same shape as [selectedItems] (may be empty).
  /// - [checkInDate], [checkOutDate]: the requested hunt window (ISO date
  ///   strings, optional).
  /// - [huntingDays]: derived day count (0 when dates are absent).
  /// - [hunterCount], [observerCount]: party size.
  /// - [combinedTotalZAR]: grand total **incl. the absorbed 7.5% markup**
  ///   (sum of all line totals). This is the amount the hunter is shown.
  ///
  /// Writes the `bookings` document with `isCustomPackage: true` and
  /// `status: 'Pending Approval'` (the canonical "pending" state used across
  /// the booking lifecycle), so the request surfaces in the outfitter's
  /// Incoming Booking Requests list with APPROVE / DECLINE actions. The 25%
  /// non-refundable deposit split is stored so the hunter can pay it via
  /// PayFast once the outfitter approves.
  Future<String> submitCustomPackageBooking({
    required String farmId,
    required String outfitterId,
    required List<Map<String, dynamic>> selectedItems,
    required double combinedTotalZAR,
    String? farmName,
    String? pricelistId,
    List<Map<String, dynamic>> lodgingCatering = const [],
    String? checkInDate,
    String? checkOutDate,
    int huntingDays = 0,
    int hunterCount = 1,
    int observerCount = 0,
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
    if (selectedItems.isEmpty && lodgingCatering.isEmpty) {
      throw Exception('At least one item must be selected');
    }
    if (combinedTotalZAR <= 0) {
      throw Exception('Total price must be greater than zero');
    }

    // Recover the absorbed commission breakdown for the outfitter financials.
    // combinedTotalZAR already includes the 7.5% markup, so the base is
    // total / 1.075 and the commission is the remainder.
    final double basePrice = combinedTotalZAR / (1 + platformCommissionRate);
    final double platformFee = combinedTotalZAR - basePrice;
    final double depositAmount = combinedTotalZAR * 0.25;
    final double balanceAmount = combinedTotalZAR - depositAmount;

    // Normalise a line item into the shape the outfitter booking dashboard
    // already renders (`name` + `hunterPrice` + `quantity`).
    Map<String, dynamic> normalizeItem(Map<String, dynamic> item) => {
      'name': item['name'] ?? item['displayLabel'] ?? 'Unknown',
      'speciesId': item['speciesId'],
      'sex': item['sex'],
      'sexLabel': item['sexLabel'],
      'trophySizeRange': item['trophySizeRange'],
      'quantity': item['quantity'] ?? 1,
      'unitPriceHunterZAR': item['unitPriceHunterZAR'] ?? item['hunterDisplayPriceZAR'] ?? 0.0,
      'lineTotal': item['lineTotal'] ?? 0.0,
      // Mirror keys consumed by the existing outfitter dashboard item renderer.
      'hunterPrice': item['unitPriceHunterZAR'] ?? item['hunterDisplayPriceZAR'] ?? 0.0,
      'basePrice': item['outfitterBasePrice'] ?? 0.0,
    };

    final bookingData = {
      'packageId': 'CUSTOM_BUILT',
      'isCustomPackage': true,
      'packageName': farmName != null ? 'Custom Package · $farmName' : 'Custom Package',
      'outfitterId': outfitterId,
      'farmId': farmId,
      if (farmName != null) 'farmName': farmName,
      if (pricelistId != null) 'pricelistId': pricelistId,
      'hunterId': currentUser.uid,
      'bookingType': 'custom_pricelist',
      'selectedItemsList': selectedItems.map(normalizeItem).toList(),
      if (lodgingCatering.isNotEmpty)
        'lodgingCateringList': lodgingCatering.map(normalizeItem).toList(),
      if (checkInDate != null) 'checkInDate': checkInDate,
      if (checkOutDate != null) 'checkOutDate': checkOutDate,
      'huntingDays': huntingDays,
      'hunterCount': hunterCount,
      'observerCount': observerCount,
      'basePriceRands': basePrice,
      'platformCommissionRands': platformFee,
      'platformCommissionRate': platformCommissionRate,
      'totalHunterPriceRands': combinedTotalZAR,
      'depositFraction': 0.25,
      'depositAmountRands': depositAmount,
      'balanceAmountRands': balanceAmount,
      'status': 'Pending Approval',
      'bookingTimestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef =
        await _firestore.collection('bookings').add(bookingData);

    print(
      '✅ Custom package booking submitted: '
      '${selectedItems.length + lodgingCatering.length} items, '
      'Total: R${combinedTotalZAR.toStringAsFixed(2)}, '
      'Deposit: R${depositAmount.toStringAsFixed(2)}',
    );
    return docRef.id;
  }

  /// Returns every active scanned price list, most recent first. Readable by
  /// any signed-in hunter (the price list is the custom-package catalog).
  /// Used by the Custom Package Builder farm-selection screen to discover
  /// which farms an outfitter has published a price list for.
  Future<List<Map<String, dynamic>>> getAllActivePricelists() async {
    final snapshot = await _firestore
        .collection('scanned_pricelists')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  /// Returns the most recent active scanned price list for [farmId], or null
  /// when the farm has no active price list. Readable by signed-in hunters.
  Future<Map<String, dynamic>?> getActivePricelistForFarm(String farmId) async {
    final snapshot = await _firestore
        .collection('scanned_pricelists')
        .where('farmId', isEqualTo: farmId)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final data = Map<String, dynamic>.from(snapshot.docs.first.data());
    data['id'] = snapshot.docs.first.id;
    return data;
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
      final data = Map<String, dynamic>.from(doc.data() as Map);
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
      final data = Map<String, dynamic>.from(doc.data() as Map);
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
