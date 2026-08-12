import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Central AI-driven price list processor and custom tracking service engine.
/// Handles OCR-style text extraction from price list images and manages custom package bookings.
class PricelistScannerService {
  static final PricelistScannerService instance =
      PricelistScannerService._internal();
  PricelistScannerService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Platform commission rate (7.5%)
  static const double platformCommissionRate = 0.075;

  /// Simulates high-fidelity text extraction from price list images.
  ///
  /// In production, this would integrate with Google ML Kit, AWS Textract,
  /// or similar OCR services to extract text from the uploaded image.
  ///
  /// For demo purposes, this simulates extraction of common trophy species
  /// and daily rates commonly found in South African hunting price lists.
  ///
  /// Parameters:
  /// - [farmId]: The farm/concession ID this price list belongs to
  /// - [imageFile]: The image file containing the price list (for future OCR integration)
  ///
  /// Processing steps:
  /// 1. Simulate text extraction from image
  /// 2. Parse raw strings into structured data
  /// 3. Return extracted items for verification
  Future<List<Map<String, dynamic>>> extractPricelistItems({
    required String farmId,
    required File imageFile,
  }) async {
    // Simulate high-fidelity text extraction
    // In production, replace with actual OCR integration (ML Kit, AWS Textract, etc.)
    final List<Map<String, dynamic>> simulatedLines = _simulateTextExtraction();

    // Process and clean extracted data
    final List<Map<String, dynamic>> processedItems = [];

    for (final line in simulatedLines) {
      final speciesName = line['species'] as String;
      final basePrice = (line['basePrice'] as num).toDouble();

      // Store base price (display price will be calculated on save)
      processedItems.add({
        'name': speciesName,
        'outfitterBasePrice': basePrice,
      });
    }

    print(
      '✅ Pricelist extracted: ${processedItems.length} items ready for verification',
    );
    return processedItems;
  }

  /// Processes and uploads a price list image to Firestore.
  ///
  /// This method is kept for backward compatibility.
  /// New code should use extractPricelistItems() followed by
  /// OutfitterPricelistVerificationScreen for proper workflow.
  ///
  /// Parameters:
  /// - [farmId]: The farm/concession ID this price list belongs to
  /// - [imageFile]: The image file containing the price list (for future OCR integration)
  ///
  /// Processing steps:
  /// 1. Simulate text extraction from image
  /// 2. Parse raw strings into structured data
  /// 3. Calculate 7.5% platform fee for each item
  /// 4. Upload structured document to Firestore
  Future<void> processAndUploadPricelistImage({
    required String farmId,
    required File imageFile,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be authenticated to upload price lists');
    }

    // Simulate high-fidelity text extraction
    // In production, replace with actual OCR integration (ML Kit, AWS Textract, etc.)
    final List<Map<String, dynamic>> simulatedLines = _simulateTextExtraction();

    // Process and clean extracted data
    final List<Map<String, dynamic>> processedItems = [];

    for (final line in simulatedLines) {
      final speciesName = line['species'] as String;
      final basePrice = (line['basePrice'] as num).toDouble();

      // Calculate hunter display price with 7.5% platform fee
      final double hunterPrice = basePrice * (1 + platformCommissionRate);

      processedItems.add({
        'name': speciesName,
        'outfitterBasePrice': basePrice,
        'hunterDisplayPriceZAR': hunterPrice,
        'basePriceFormatted': 'R${basePrice.toStringAsFixed(0)}',
        'hunterPriceFormatted': 'R${hunterPrice.toStringAsFixed(0)}',
        'commissionZAR': hunterPrice - basePrice,
      });
    }

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
      'processingVersion': '1.0.0',
    };

    // Upload to scanned_pricelists collection
    await _firestore.collection('scanned_pricelists').add(pricelistData);

    print('✅ Pricelist processed and uploaded: ${processedItems.length} items');
  }

  /// Simulates OCR text extraction from a price list image.
  /// Returns a list of raw price entries that would be extracted from the image.
  ///
  /// Production implementation would:
  /// 1. Upload image to cloud storage
  /// 2. Call OCR service (Google ML Kit, AWS Textract, etc.)
  /// 3. Parse returned text blocks into structured data
  List<Map<String, dynamic>> _simulateTextExtraction() {
    // Simulated extracted lines from OCR processing
    // These would normally come from actual OCR results
    return [
      // Trophy Species Pricing
      {'species': 'African Elephant', 'basePrice': 85000.0},
      {'species': 'Cape Buffalo', 'basePrice': 45000.0},
      {'species': 'White Rhino', 'basePrice': 65000.0},
      {'species': 'Lion', 'basePrice': 35000.0},
      {'species': 'Leopard', 'basePrice': 18000.0},
      {'species': 'Kudu', 'basePrice': 15000.0},
      {'species': 'Sable Antelope', 'basePrice': 22000.0},
      {'species': 'Eland', 'basePrice': 12000.0},
      {'species': 'Gemsbok', 'basePrice': 8500.0},
      {'species': 'Blue Wildebeest', 'basePrice': 5500.0},
      {'species': 'Zebra', 'basePrice': 4500.0},
      {'species': 'Warthog', 'basePrice': 2500.0},
      {'species': 'Impala', 'basePrice': 3500.0},
      {'species': 'Springbok', 'basePrice': 2800.0},
      {'species': 'Waterbuck', 'basePrice': 7500.0},
      {'species': 'Red Hartebeest', 'basePrice': 6500.0},
      {'species': 'Blesbok', 'basePrice': 4200.0},
      {'species': 'Black Wildebeest', 'basePrice': 5800.0},
      {'species': 'Nyala', 'basePrice': 9500.0},
      {'species': 'Bushpig', 'basePrice': 3200.0},
      // Daily Rates & Services
      {'species': 'Daily Rate (PH Included)', 'basePrice': 2000.0},
      {'species': 'Daily Rate (Self-Guided)', 'basePrice': 1200.0},
      {'species': 'Trophy Fees (Per Animal)', 'basePrice': 0.0}, // Variable
      {'species': 'Accommodation (Per Night)', 'basePrice': 1500.0},
      {'species': 'Meals (Per Day)', 'basePrice': 450.0},
      {'species': 'Transport (Airport Transfer)', 'basePrice': 2500.0},
    ];
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
      throw Exception('User must be authenticated');
    }

    return _firestore
        .collection('scanned_pricelists')
        .where('outfitterId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return data;
            }).toList());
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
      'processingVersion': '1.0.0',
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
