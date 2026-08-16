import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/farm_game_price_entry.dart';

/// Manages the per-farm game price list (`farm_pricelists` Firestore
/// collection).
///
/// Each entry is a single game-species line item (species name + `qty` +
/// `price` in ZAR) linked directly to a [farmId] and stamped with the owning
/// outfitter's uid (`outfitterId`) for ownership scoping.
///
/// The collection is owner-scoped: an outfitter may only read / write the
/// price lists for farms they own (see `firestore.rules`). All write methods
/// require an authenticated user.
class FarmGamePriceListManager {
  static final FarmGamePriceListManager instance =
      FarmGamePriceListManager._internal();

  FarmGamePriceListManager._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  User? get _currentUser => FirebaseAuth.instance.currentUser;
  String? get _currentUserId => _currentUser?.uid;

  /// Reactive stream of price-list entries for a single farm, ordered by
  /// species name. Returns an empty stream for an unauthenticated caller so
  /// the consuming `StreamBuilder` never throws.
  Stream<List<FarmGamePriceEntry>> getFarmPriceListStream(String farmId) {
    if (_currentUserId == null || farmId.isEmpty) {
      return const Stream.empty();
    }
    return _firestore
        .collection('farm_pricelists')
        .where('farmId', isEqualTo: farmId)
        .where('outfitterId', isEqualTo: _currentUserId)
        .orderBy('speciesName')
        .snapshots()
        .map((snap) => snap.docs.map(FarmGamePriceEntry.fromFirestore).toList());
  }

  /// One-shot fetch of a farm's price list (newest-first by species).
  Future<List<FarmGamePriceEntry>> getFarmPriceList(String farmId) async {
    if (_currentUserId == null || farmId.isEmpty) {
      return const [];
    }
    final snap = await _firestore
        .collection('farm_pricelists')
        .where('farmId', isEqualTo: farmId)
        .where('outfitterId', isEqualTo: _currentUserId)
        .orderBy('speciesName')
        .get();
    return snap.docs.map(FarmGamePriceEntry.fromFirestore).toList();
  }

  /// Adds a new game-species entry to the farm's price list. Requires
  /// authentication + a non-empty [speciesName]; [qty] must be ‚â• 0 and
  /// [priceZAR] must be ‚â• 0. [gender] defaults to 'Any' and [hornTuskLength]
  /// is optional (omitted from the doc when empty). [hornTuskUnit] defaults
  /// to 'inches' and is always persisted.
  ///
  /// Returns the new document id. Throws [StateError] if unauthenticated or
  /// [ArgumentError] if the species name is empty.
  Future<String> addEntry({
    required String farmId,
    required String speciesName,
    required int qty,
    required double priceZAR,
    String gender = 'Any',
    String hornTuskLength = '',
    String hornTuskUnit = HornTuskUnit.inches,
  }) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw StateError('User must be authenticated to manage a price list.');
    }
    if (farmId.trim().isEmpty) {
      throw ArgumentError('Farm ID is required.');
    }
    if (speciesName.trim().isEmpty) {
      throw ArgumentError('Species name is required.');
    }
    if (qty < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }
    if (priceZAR < 0) {
      throw ArgumentError('Price cannot be negative.');
    }

    final now = FieldValue.serverTimestamp();
    final docRef = await _firestore.collection('farm_pricelists').add({
      'farmId': farmId,
      'outfitterId': uid,
      'speciesName': speciesName.trim(),
      'qty': qty,
      'price': priceZAR,
      'gender': gender,
      'hornTuskUnit': HornTuskUnit.normalize(hornTuskUnit),
      if (hornTuskLength.trim().isNotEmpty)
        'hornTuskLength': hornTuskLength.trim(),
      'createdAt': now,
      'updatedAt': now,
    });
    return docRef.id;
  }

  /// Updates an existing price-list entry. Only the supplied fields are
  /// written; null fields are skipped so a partial update preserves the
  /// existing values. Pass [hornTuskLength] as an empty string to clear it.
  Future<void> updateEntry({
    required String entryId,
    String? speciesName,
    int? qty,
    double? priceZAR,
    String? gender,
    String? hornTuskLength,
    String? hornTuskUnit,
  }) async {
    if (_currentUserId == null) {
      throw StateError('User must be authenticated to manage a price list.');
    }
    if (entryId.trim().isEmpty) {
      throw ArgumentError('Entry ID is required.');
    }
    if (speciesName != null && speciesName.trim().isEmpty) {
      throw ArgumentError('Species name cannot be empty.');
    }
    if (qty != null && qty < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }
    if (priceZAR != null && priceZAR < 0) {
      throw ArgumentError('Price cannot be negative.');
    }

    final updates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (speciesName != null) updates['speciesName'] = speciesName.trim();
    if (qty != null) updates['qty'] = qty;
    if (priceZAR != null) updates['price'] = priceZAR;
    if (gender != null) updates['gender'] = gender;
    if (hornTuskUnit != null) {
      updates['hornTuskUnit'] = HornTuskUnit.normalize(hornTuskUnit);
    }
    if (hornTuskLength != null) {
      final trimmed = hornTuskLength.trim();
      if (trimmed.isEmpty) {
        updates['hornTuskLength'] = FieldValue.delete();
      } else {
        updates['hornTuskLength'] = trimmed;
      }
    }

    await _firestore.collection('farm_pricelists').doc(entryId).update(updates);
  }

  /// Hard-deletes a price-list entry.
  Future<void> deleteEntry(String entryId) async {
    if (_currentUserId == null) {
      throw StateError('User must be authenticated to manage a price list.');
    }
    if (entryId.trim().isEmpty) {
      throw ArgumentError('Entry ID is required.');
    }
    await _firestore.collection('farm_pricelists').doc(entryId).delete();
  }
}
