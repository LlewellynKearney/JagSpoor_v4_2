import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/offline_stream_guard.dart';
import '../models/booking_status.dart';
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
  /// is initialized / unauthenticated). Used by BOTH the stream queries and
  /// the booking-submission path, so the booking write can be unit-tested
  /// without a live `FirebaseAuth` app.
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
  /// / `FeedbackFirebaseService`). The same uid resolver backs both the
  /// stream queries and the booking-submission path.
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

  // ── Custom Package booking submission (hunter-mode) ──────────────────────
  //
  // Submits a custom-built package booking request assembled by a hunter from
  // the farm's published `farm_pricelists` (species) + `farm_service_rates`
  // (itemized fees). This is the SOLE booking-write path for the Custom
  // Package Builder -- the builder no longer depends on the outfitter-named
  // `PricelistScannerService` (which has been removed) for submission, so the
  // hunter-facing read + write path is fully consolidated here on the
  // hunter-readable price-list manager. Writes to `bookings` with
  // `status: BookingStatus.pendingApproval`; the booking is owner-scoped to
  // the hunter (`hunterId`) and references the owning outfitter (`outfitterId`)
  // so the outfitter booking dashboard's `Incoming Booking Requests` stream
  // surfaces it for approval.

  /// Submits a custom-built package booking request.
  ///
  /// Used when a hunter assembles their own itinerary from an outfitter's
  /// published farm price list (species/fees with quantities) instead of
  /// booking a pre-defined marketplace package.
  ///
  /// Pricing model: every line item's `unitPriceHunterZAR` equals its base
  /// price (there is no platform commission / markup). The hunter sees
  /// per-item prices and the grand total, which is the base booking cost.
  ///
  /// Parameters:
  /// - [farmId], [farmName]: the concession where the hunt will take place.
  /// - [outfitterId]: the UID of the outfitter who owns the farm/price list.
  /// - [pricelistId]: the price-list source the items were drawn from.
  /// - [selectedItems]: species/trophy lines - each map carries `name`,
  ///   `quantity`, `unitPriceHunterZAR` / `hunterDisplayPriceZAR`, `lineTotal`.
  /// - [lodgingCatering]: itemized fee lines (accommodation / catering /
  ///   vehicle / guide / etc.), same shape as [selectedItems].
  /// - [combinedTotalZAR]: the grand total (base cost; no commission).
  /// - [checkInDate]/[checkOutDate]: ISO-8601 hunt window (drives the
  ///   outfitter dashboard booking-card date banner).
  /// - [huntingDays], [hunterCount], [observerCount]: party + duration meta.
  ///
  /// Returns the new booking document id. Throws if unauthenticated, if the
  /// caller is the owning outfitter (outfitters cannot book their own farms),
  /// if no items are selected, or if the total is non-positive.
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
    final currentUid = _currentUserId;
    if (currentUid == null) {
      throw Exception('User must be authenticated to book');
    }

    // Prevent outfitters from booking their own packages.
    if (currentUid == outfitterId) {
      throw Exception('Outfitters cannot book their own packages');
    }

    if (selectedItems.isEmpty && lodgingCatering.isEmpty) {
      throw Exception('At least one item must be selected');
    }
    if (combinedTotalZAR <= 0) {
      throw Exception('Total price must be greater than zero');
    }

    // The total equals the base booking cost; there is no platform commission.
    final double basePrice = combinedTotalZAR;

    // Normalise a line item into the shape the outfitter booking dashboard
    // already renders (`name` + `hunterPrice` + `quantity`). The builder's
    // gender / horn-tusk / quantity-limit / fee-unit spec fields are passed
    // through (not dropped) so the booked itinerary retains every spec the
    // hunter saw on the price list.
    Map<String, dynamic> normalizeItem(Map<String, dynamic> item) => {
          'name': item['name'] ?? item['displayLabel'] ?? 'Unknown',
          'speciesId': item['speciesId'],
          'sex': item['sex'],
          'sexLabel': item['sexLabel'],
          'trophySizeRange': item['trophySizeRange'],
          'hornTuskLength': item['hornTuskLength'],
          'hornTuskUnit': item['hornTuskUnit'],
          'quantityLimit': item['quantityLimit'],
          'itemType': item['itemType'],
          'feeType': item['feeType'],
          'feeUnitLabel': item['feeUnitLabel'],
          'quantityNoun': item['quantityNoun'],
          'quantity': item['quantity'] ?? 1,
          'unitPriceHunterZAR': item['unitPriceHunterZAR'] ??
              item['hunterDisplayPriceZAR'] ??
              0.0,
          'lineTotal': item['lineTotal'] ?? 0.0,
          // Mirror keys consumed by the existing outfitter dashboard renderer.
          'hunterPrice': item['unitPriceHunterZAR'] ??
              item['hunterDisplayPriceZAR'] ??
              0.0,
          'basePrice': item['outfitterBasePrice'] ?? 0.0,
        };

    final bookingData = {
      'packageId': 'CUSTOM_BUILT',
      'isCustomPackage': true,
      'packageName':
          farmName != null ? 'Custom Package - $farmName' : 'Custom Package',
      'outfitterId': outfitterId,
      'farmId': farmId,
      if (farmName != null) 'farmName': farmName,
      if (pricelistId != null) 'pricelistId': pricelistId,
      'hunterId': currentUid,
      'bookingType': 'custom_pricelist',
      'selectedItemsList': selectedItems.map(normalizeItem).toList(),
      if (lodgingCatering.isNotEmpty)
        'lodgingCateringList': lodgingCatering.map(normalizeItem).toList(),
      // Hunt window. The custom-package builder passes the hunt window as
      // `checkInDate`/`checkOutDate` (ISO-8601 strings). We ALSO mirror them
      // onto `startDate`/`endDate` so every downstream consumer (the calendar
      // resolver, UI cards that read either key) finds a value regardless of
      // which alias it looks for -- matching the dual-key guarantee
      // `PackageBookingManager.bookPackage` writes for marketplace bookings.
      if (checkInDate != null) 'checkInDate': checkInDate,
      if (checkOutDate != null) 'checkOutDate': checkOutDate,
      if (checkInDate != null) 'startDate': checkInDate,
      if (checkOutDate != null) 'endDate': checkOutDate,
      if (checkInDate != null) 'availabilityStart': checkInDate,
      if (checkOutDate != null) 'availabilityEnd': checkOutDate,
      'huntingDays': huntingDays,
      'hunterCount': hunterCount,
      'observerCount': observerCount,
      'basePriceRands': basePrice,
      'totalHunterPriceRands': combinedTotalZAR,
      'status': BookingStatus.pendingApproval,
      'bookingTimestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Resolve the farm's region (district + province) from `farms/{farmId}`
    // so the booking is self-contained for the calendar event's location
    // (buildLocation renders "Farm (district, province)"). Best-effort: a
    // missing farm doc or read failure simply omits the region fields (the
    // calendar falls back to the farm name only). Mirrors the package-booking
    // path's farm-location enrichment.
    if (farmId.isNotEmpty) {
      try {
        final farmSnap =
            await _firestore.collection('farms').doc(farmId).get();
        if (farmSnap.exists) {
          final farmData = farmSnap.data() ?? const <String, dynamic>{};
          final district = (farmData['district'] as String?)?.trim();
          final province = (farmData['province'] as String?)?.trim();
          if (district != null && district.isNotEmpty) {
            bookingData['district'] = district;
          }
          if (province != null && province.isNotEmpty) {
            bookingData['province'] = province;
          }
          // If the caller did not supply a farmName, backfill it from the
          // farm doc so the calendar title carries the "@ Farm" suffix.
          if ((farmName == null || farmName.isEmpty)) {
            final resolvedName = (farmData['name'] as String?)?.trim();
            if (resolvedName != null && resolvedName.isNotEmpty) {
              bookingData['farmName'] = resolvedName;
              bookingData['packageName'] = 'Custom Package - $resolvedName';
            }
          }
        }
      } catch (_) {
        // A farm read failure must never block the booking.
      }
    }

    final docRef = await _firestore.collection('bookings').add(bookingData);
    return docRef.id;
  }
}
