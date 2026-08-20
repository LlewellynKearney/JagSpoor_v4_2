import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/farm_details.dart';

/// Resolves a farm document's full [FarmDetails] snapshot (name, location,
/// size, contact, registration, photos) for hunter-facing detail surfaces.
///
/// The Trophy Registry browser's farm join may be incomplete (or the sheet is
/// opened from a context that does not have a farm join at all), so the
/// confirmation sheet uses this service to fetch `farms/{farmId}` on demand
/// and update reactively. Firestore errors (offline / permissions /
/// `core/no-app`, missing doc) are swallowed and yield an empty-details
/// snapshot keyed to the farmId -- the caller renders graceful fallbacks.
class FarmDetailsResolver {
  FarmDetailsResolver._();
  static final FarmDetailsResolver instance = FarmDetailsResolver._();

  /// Test seam: inject a fake Firestore (e.g. `FakeFirebaseFirestore`).
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  /// Fetches `farms/{farmId}` and resolves it to a [FarmDetails]. Returns an
  /// empty-details snapshot (farmId set) on any failure rather than throwing.
  Future<FarmDetails> resolveFarm(String farmId) async {
    if (farmId.trim().isEmpty) {
      return const FarmDetails();
    }
    try {
      final doc = await _db.collection('farms').doc(farmId).get();
      final data = doc.data() ?? const <String, dynamic>{};
      final details = FarmDetails.fromMap(data);
      return FarmDetails(
        farmId: doc.id,
        outfitterId: details.outfitterId,
        name: details.name,
        district: details.district,
        province: details.province,
        town: details.town,
        contactNumber: details.contactNumber,
        registrationNumber: details.registrationNumber,
        sizeHectares: details.sizeHectares,
        photoUrls: details.photoUrls,
      );
    } catch (e) {
      debugPrint('FarmDetailsResolver.resolveFarm($farmId) failed: $e');
      return FarmDetails(farmId: farmId);
    }
  }
}
