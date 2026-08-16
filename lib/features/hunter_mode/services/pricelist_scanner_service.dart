import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/farm_config.dart';

/// Custom Package Builder service.
///
/// Reads an outfitter's published scanned price lists (the per-farm hunting
/// catalog: species/sex/size/price + fee lines) so hunters can assemble a
/// custom itinerary, and submits the assembled booking request.
///
/// The AI Paper Price List Scanner that previously created these scanned
/// price lists has been removed. The `scanned_pricelists` collection remains
/// the custom-package catalog data source; price lists may be seeded by an
/// admin or a future import flow. All pricing is the base cost - there is no
/// platform commission / markup.
class PricelistScannerService {
  static final PricelistScannerService instance =
      PricelistScannerService._internal();
  PricelistScannerService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Submits a custom-built package booking request.
  ///
  /// Used when hunters assemble their own itinerary from an outfitter's active
  /// scanned price list (species/fees with quantities) instead of booking a
  /// pre-defined marketplace package.
  ///
  /// Pricing model: every line item's `unitPriceHunterZAR` equals its base
  /// price (there is no platform commission / markup). The hunter sees
  /// per-item prices and the grand total, which is the base booking cost.
  ///
  /// Parameters:
  /// - [farmId], [farmName]: the concession where the hunt will take place.
  /// - [outfitterId]: the UID of the outfitter who owns the farm/price list.
  /// - [pricelistId]: the scanned price list the items were drawn from.
  /// - [selectedItems]: species/trophy lines - each map carries `name`,
  ///   `speciesId`, `sex`, `sexLabel`, `trophySizeRange`, `quantity`,
  ///   `unitPriceHunterZAR`, `lineTotal`.
  /// - [lodgingCatering]: fee-type lines (lodging/catering/vehicle/etc.) in
  ///   the same shape as [selectedItems] (may be empty).
  /// - [checkInDate], [checkOutDate]: the requested hunt window (ISO date
  ///   strings, optional).
  /// - [huntingDays]: derived day count (0 when dates are absent).
  /// - [hunterCount], [observerCount]: party size.
  /// - [combinedTotalZAR]: grand total (sum of all line totals). This is the
  ///   amount the hunter is shown and equals the base booking cost.
  ///
  /// Writes the `bookings` document with `isCustomPackage: true` and
  /// `status: 'Pending Approval'` (the canonical "pending" state used across
  /// the booking lifecycle), so the request surfaces in the outfitter's
  /// Incoming Booking Requests list with APPROVE / DECLINE actions. The total
  /// price is stored as the booking cost (no deposit split).
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

    // The total equals the base booking cost; there is no platform commission.
    final double basePrice = combinedTotalZAR;

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
      'packageName': farmName != null ? 'Custom Package - $farmName' : 'Custom Package',
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
      'totalHunterPriceRands': combinedTotalZAR,
      'status': 'Pending Approval',
      'bookingTimestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef =
        await _firestore.collection('bookings').add(bookingData);

    print(
      'Custom package booking submitted: '
      '${selectedItems.length + lodgingCatering.length} items, '
      'Total: R${combinedTotalZAR.toStringAsFixed(2)}',
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

  /// Builds a structured hunting catalog for [farmId] from its most-recent
  /// active scanned price list - the animals available for hunting (species,
  /// sex/class, trophy size tier, price per animal, and quantity limit) plus
  /// the farm's fee lines (daily / accommodation / vehicle / guide / etc.).
  ///
  /// Returns `null` when the farm has no active price list. Used by the Custom
  /// Package Builder to render the species + lodging pickers from the
  /// outfitter's live rates. Readable by signed-in hunters.
  Future<FarmHuntingCatalog?> getFarmHuntingCatalog(String farmId) async {
    final pricelist = await getActivePricelistForFarm(farmId);
    if (pricelist == null) return null;
    return FarmHuntingCatalog.fromPricelist(pricelist);
  }

  /// Calculates the total for selected price list items.
  ///
  /// Parameters:
  /// - [selectedItems]: List of selected items with base prices
  ///
  /// Returns the total price (the sum of the base prices; there is no
  /// platform commission).
  double calculateTotalWithFee(List<Map<String, dynamic>> selectedItems) {
    double baseTotal = 0;

    for (final item in selectedItems) {
      final basePrice = (item['outfitterBasePrice'] ?? 0.0).toDouble();
      baseTotal += basePrice;
    }

    return baseTotal;
  }
}
