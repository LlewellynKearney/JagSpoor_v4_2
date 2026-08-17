import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/offline_stream_guard.dart';
import '../models/farm_game_price_entry.dart';
import '../models/farm_service_rate.dart';

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

  FarmGamePriceListManager._internal({
    this.firestoreForTesting,
    this.currentUserIdResolverForTesting,
  });

  /// Test seam: inject a Firestore instance (e.g. `FakeFirebaseFirestore`) so
  /// the stream/query contract can be unit-tested without a live Firebase app.
  /// Defaults to the global instance.
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  FirebaseFirestore get _firestore =>
      firestoreForTesting ?? FirebaseFirestore.instance;

  /// Test seam: inject a uid resolver so the null-uid -> empty-stream branch
  /// and the owner-scoped query contract can be unit-tested without a real
  /// signed-in user. Defaults to the current Firebase user (null when no app
  /// is initialized / no user signed in).
  @visibleForTesting
  String? Function()? currentUserIdResolverForTesting;

  String? get _currentUserId {
    if (currentUserIdResolverForTesting != null) {
      return currentUserIdResolverForTesting!();
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
    }
    return null;
  }

  /// Test-only constructor: build a fresh, isolated manager bound to an
  /// injectable Firestore + uid resolver (mirrors `OpticLogService.forTesting`
  /// / `FeedbackFirebaseService`).
  @visibleForTesting
  factory FarmGamePriceListManager.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() currentUserIdResolver,
  }) {
    return FarmGamePriceListManager._internal(
      firestoreForTesting: firestore,
      currentUserIdResolverForTesting: currentUserIdResolver,
    );
  }

  /// Public accessor for the current authenticated user's uid, used by
  /// callers (e.g. the CSV import flow) that need to stamp the outfitter id
  /// before a batch write. Returns null when unauthenticated.
  String? get currentUserId => _currentUserId;

  /// Reactive stream of price-list entries for a single farm, sorted by
  /// species name (client-side). Returns an empty stream for an
  /// unauthenticated caller so the consuming `StreamBuilder` never throws.
  ///
  /// The query intentionally does NOT use `.orderBy('speciesName')`
  /// server-side: an equality (`.where('farmId')` + `.where('outfitterId')`)
  /// combined with a server-side `orderBy` requires a Firestore composite
  /// index; until that index is deployed the server errors with "Missing
  /// Composite Index" and the stream hangs / surfaces an error. Sorting
  /// client-side in Dart after the equality-only read (which uses the
  /// automatic single-field indexes) avoids the missing-index error entirely.
  /// The stream is wrapped in [OfflineStreamGuard.offlineResilient] so a hard
  /// error (permissions change, offline with no cache) emits the fallback `[]`
  /// and completes instead of hanging the `StreamBuilder`.
  Stream<List<FarmGamePriceEntry>> getFarmPriceListStream(String farmId) {
    if (_currentUserId == null || farmId.isEmpty) {
      return const Stream.empty();
    }
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('farm_pricelists')
          .where('farmId', isEqualTo: farmId)
          .where('outfitterId', isEqualTo: _currentUserId)
          .snapshots()
          .map((snap) {
        final entries =
            snap.docs.map(FarmGamePriceEntry.fromFirestore).toList();
        entries.sort((a, b) => a.speciesName.compareTo(b.speciesName));
        return entries;
      }),
      fallback: const <FarmGamePriceEntry>[],
      debugLabel: 'farm_pricelists.owner',
    );
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

  // ── Hunter-readable read APIs (no owner-scoped filter) ───────────────────
  //
  // The owner-scoped [getFarmPriceList] / [getFarmPriceListStream] above filter
  // by `outfitterId == currentUserId`, so a hunter browsing the Custom Package
  // Builder cannot read an outfitter's price list through them. The methods
  // below query by `farmId` only (the Firestore rule `farm_pricelists` read is
  // `isSignedIn()`, so any signed-in hunter may read any farm's price list --
  // mirroring the `packages` / `farms` / `scanned_pricelists` signed-in read
  // pattern). They are used by the Custom Package Builder farm-selection +
  // builder screens.

  /// Reactive stream of a farm's price-list entries for a hunter browsing the
  /// Custom Package Builder (no owner-scoped filter). Sorted by species name
  /// client-side to avoid the `farmId` + `speciesName` composite-index
  /// requirement (see [getFarmPriceListStream]). Wrapped in
  /// [OfflineStreamGuard.offlineResilient] so a hard error (missing index,
  /// permissions, offline with no cache) emits the fallback `[]` and completes
  /// instead of hanging the consuming `StreamBuilder` (which previously
  /// rendered a blank builder screen).
  Stream<List<FarmGamePriceEntry>> getFarmPriceListStreamForHunter(String farmId) {
    if (_currentUserId == null || farmId.isEmpty) {
      return const Stream.empty();
    }
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('farm_pricelists')
          .where('farmId', isEqualTo: farmId)
          .snapshots()
          .map((snap) {
        final entries =
            snap.docs.map(FarmGamePriceEntry.fromFirestore).toList();
        entries.sort((a, b) => a.speciesName.compareTo(b.speciesName));
        return entries;
      }),
      fallback: const <FarmGamePriceEntry>[],
      debugLabel: 'farm_pricelists.hunter',
    );
  }

  /// One-shot fetch of a farm's price list for a hunter (no owner-scoped
  /// filter). Sorted by species name client-side (no server-side `orderBy` --
  /// see [getFarmPriceListStreamForHunter] for the composite-index rationale).
  Future<List<FarmGamePriceEntry>> getFarmPriceListForHunter(String farmId) async {
    if (_currentUserId == null || farmId.isEmpty) {
      return const [];
    }
    final snap = await _firestore
        .collection('farm_pricelists')
        .where('farmId', isEqualTo: farmId)
        .get();
    final entries = snap.docs.map(FarmGamePriceEntry.fromFirestore).toList();
    entries.sort((a, b) => a.speciesName.compareTo(b.speciesName));
    return entries;
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

  /// Bulk-creates price-list entries for a farm in a single `WriteBatch`
  /// (one round-trip, atomic on the server side). Each entry's `farmId` /
  /// `outfitterId` are re-stamped from the authenticated caller + [farmId] so
  /// a CSV import cannot cross-write into another outfitter's collection.
  /// Returns the number of documents created. Throws [StateError] if
  /// unauthenticated or [ArgumentError] if [farmId] / [entries] are empty.
  Future<int> bulkAddEntries({
    required String farmId,
    required List<FarmGamePriceEntry> entries,
  }) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw StateError('User must be authenticated to manage a price list.');
    }
    if (farmId.trim().isEmpty) {
      throw ArgumentError('Farm ID is required.');
    }
    if (entries.isEmpty) {
      throw ArgumentError('No entries to import.');
    }

    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();
    for (final e in entries) {
      final ref = _firestore.collection('farm_pricelists').doc();
      batch.set(ref, {
        'farmId': farmId,
        'outfitterId': uid,
        'speciesName': e.speciesName.trim(),
        'qty': e.qty,
        'price': e.priceZAR,
        'gender': e.gender,
        'hornTuskUnit': HornTuskUnit.normalize(e.hornTuskUnit),
        if (e.hornTuskLength.trim().isNotEmpty)
          'hornTuskLength': e.hornTuskLength.trim(),
        'createdAt': now,
        'updatedAt': now,
      });
    }
    await batch.commit();
    return entries.length;
  }

  // ── Itemized service rates ──────────────────────────────────────────────

  /// Reactive stream of the farm's itemized service-rate configuration. Emits
  /// a [FarmServiceRates.empty] (all 7 standard categories zeroed) when the
  /// farm has no configured doc yet so the UI can render the full list
  /// immediately. Returns an empty-state rates object for an unauthenticated
  /// caller (never throws).
  Stream<FarmServiceRates> getFarmServiceRatesStream(String farmId) {
    final uid = _currentUserId;
    if (uid == null || farmId.isEmpty) {
      return Stream.value(FarmServiceRates.empty(farmId, ''));
    }
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('farm_service_rates')
          .doc(farmId)
          .snapshots()
          .map((snap) {
        if (!snap.exists) {
          return FarmServiceRates.empty(farmId, uid);
        }
        final data = snap.data() ?? const <String, dynamic>{};
        // Re-stamp the authenticated uid for ownership scoping in case the doc
        // is stale / migrated.
        return FarmServiceRates.fromMap(
          {'outfitterId': uid, ...data},
          farmId: farmId,
        );
      }),
      // A hard error (permissions change / offline with no cache) yields an
      // empty rates object so the builder renders an empty service-rates
      // section instead of hanging the nested StreamBuilder.
      fallback: FarmServiceRates.empty(farmId, uid),
      debugLabel: 'farm_service_rates',
    );
  }

  /// One-shot fetch of the farm's service-rate configuration (null when no doc
  /// exists / unauthenticated).
  Future<FarmServiceRates?> getFarmServiceRates(String farmId) async {
    final uid = _currentUserId;
    if (uid == null || farmId.isEmpty) return null;
    final snap = await _firestore.collection('farm_service_rates').doc(farmId).get();
    if (!snap.exists) return FarmServiceRates.empty(farmId, uid);
    final data = snap.data() ?? const <String, dynamic>{};
    return FarmServiceRates.fromMap(
      {'outfitterId': uid, ...data},
      farmId: farmId,
    );
  }

  /// Persists the full set of itemized service rates for a farm as a single
  /// merged document (`farm_service_rates/{farmId}`). Stamps the authenticated
  /// caller's uid as `outfitterId` for ownership scoping. Throws [StateError]
  /// if unauthenticated or [ArgumentError] if [farmId] is empty.
  Future<void> saveFarmServiceRates({
    required String farmId,
    required FarmServiceRates rates,
  }) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw StateError('User must be authenticated to manage service rates.');
    }
    if (farmId.trim().isEmpty) {
      throw ArgumentError('Farm ID is required.');
    }
    // Always re-stamp the authenticated caller as the owner so a stale / shared
    // doc cannot be hijacked by a different outfitter's data.
    final stamped = FarmServiceRates(
      farmId: farmId,
      outfitterId: uid,
      rates: rates.rates,
      updatedAt: DateTime.now(),
    );
    await _firestore.collection('farm_service_rates').doc(farmId).set(
          {
            'farmId': farmId,
            'outfitterId': uid,
            'rates': {
              for (final r in stamped.rates.values) r.key: r.toMap(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
  }

  /// Convenience: upserts a single service rate into the farm's configuration
  /// without clobbering the other rates. Reads the existing doc (or seeds the
  /// 7 standard categories), applies the [rate], and merges it back.
  Future<void> upsertFarmServiceRate({
    required String farmId,
    required FarmServiceRate rate,
  }) async {
    final existing = await getFarmServiceRates(farmId);
    final base = existing ?? FarmServiceRates.empty(farmId, _currentUserId ?? '');
    base.rates[rate.key] = rate;
    await saveFarmServiceRates(farmId: farmId, rates: base);
  }

  /// Removes a single service rate (sets it back to zeroed) from the farm's
  /// configuration.
  Future<void> removeFarmServiceRate({
    required String farmId,
    required String key,
  }) async {
    final existing = await getFarmServiceRates(farmId);
    if (existing == null) return;
    final cat = FarmServiceCategory.findByKey(key);
    existing.rates[key] = FarmServiceRate(
      key: key,
      label: cat.label,
      unitLabel: cat.unitLabel,
      quantityNoun: cat.quantityNoun,
      quantity: 0,
      pricePerUnit: 0,
    );
    await saveFarmServiceRates(farmId: farmId, rates: existing);
  }
}
