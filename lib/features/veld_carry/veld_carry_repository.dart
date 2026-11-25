import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:jagspoor/features/hunter_mode/models/booking_status.dart';

import 'models/camp.dart';
import 'models/farm_permit.dart';
import 'models/planted_area.dart';
import 'models/predator_entry.dart';
import 'models/rainfall_entry.dart';
import 'models/stock_entry.dart';
import 'models/stock_movement.dart';
import 'models/veld_alert.dart';
import 'species_defaults.dart';
import 'veld_carry_alerts.dart';
import 'veld_carry_calculator.dart';
import 'veld_carry_report.dart';

/// Firestore repository for the Veld & Carrying Capacity feature.
///
/// **Phase 2 — real Firestore I/O.** Every read and write below is scoped to
/// the signed-in outfitter and lives *inside that user's own document*, so no
/// new top-level collection is introduced:
///
/// ```text
/// users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}
/// users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}/stock/{speciesId}
/// users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}/plantedAreas/{areaId}
/// users/{outfitterUid}/farms/{farmId}/veldCamps/{campId}/predators/{predatorId}
/// users/{outfitterUid}/farms/{farmId}/permits/{permitId}
/// ```
///
/// The layout deliberately differs from the Phase 0D draft
/// (`firestore.rules.veld_carry.DRAFT`, which nests under the top-level
/// `farms/{farmId}`). The live ruleset is untouched in this phase; the
/// go-live ruleset must mirror these `users/{uid}/farms/...` paths before the
/// feature is switched on. Until then every read and write here is denied by
/// the default-deny catch-all, which is the correct posture for a dark
/// feature.
///
/// Ownership contract — enforced here *and* to be enforced by the go-live
/// rules: the caller must be the farm's outfitter. Every method compares
/// [outfitterUid] against the signed-in uid and throws
/// [VeldCarryOwnershipException] when they differ, so a caller can never read
/// or write another outfitter's veld data.
///
/// Error policy: Firestore failures are **rethrown**, never swallowed. A
/// failed read must surface to the UI so the operator sees an error state
/// instead of an empty camp list that looks like "no data".
class VeldCarryRepository {
  VeldCarryRepository._({
    String? Function()? currentUserIdResolver,
    FirebaseFirestore? firestore,
  })  : _injectedCurrentUserIdResolver = currentUserIdResolver,
        _injectedFirestore = firestore;

  /// Process-wide instance. The lazy getters below keep construction safe
  /// before `Firebase.initializeApp()` (cold launch / widget tests), matching
  /// the other repositories in this app.
  static final VeldCarryRepository instance = VeldCarryRepository._();

  /// The signed-in user's own document — the parent of every veld path.
  static const String usersCollection = 'users';

  /// Farm documents nested under the user document.
  static const String farmsCollection = 'farms';

  /// Camps live under the farm they belong to.
  static const String campsCollection = 'veldCamps';

  /// Camp children — stock ledger, planted areas and predator records.
  static const String stockCollection = 'stock';
  static const String plantedAreasCollection = 'plantedAreas';
  static const String predatorsCollection = 'predators';

  /// Permits live under the farm (they are farm-wide, not camp-specific).
  static const String permitsCollection = 'permits';

  final String? Function()? _injectedCurrentUserIdResolver;
  final FirebaseFirestore? _injectedFirestore;

  /// Signed-in uid, or null when Firebase is unavailable.
  String? get _currentUserId {
    final resolver = _injectedCurrentUserIdResolver;
    if (resolver != null) return resolver();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Test seam: inject the uid resolver and/or a Firestore instance so the
  /// ownership guard, the path builders and the write payloads can be
  /// exercised without a Firebase app.
  @visibleForTesting
  static VeldCarryRepository forTesting({
    String? Function()? currentUserIdResolver,
    FirebaseFirestore? firestore,
  }) =>
      VeldCarryRepository._(
        currentUserIdResolver: currentUserIdResolver,
        firestore: firestore,
      );

  /// Throws unless [outfitterUid] is the signed-in user.
  ///
  /// Public so the guard itself is unit-testable without Firestore.
  void requireOwnership(String outfitterUid) {
    final currentUid = _currentUserId;
    if (currentUid == null || currentUid.isEmpty) {
      throw const VeldCarryOwnershipException(
        'No signed-in user — veld data is owner-scoped.',
      );
    }
    if (outfitterUid != currentUid) {
      throw VeldCarryOwnershipException(
        'Outfitter uid does not match the signed-in user '
        '(requested: ${outfitterUid.isEmpty ? '<empty>' : outfitterUid}).',
      );
    }
  }

  // ── Path builders ─────────────────────────────────────────────────────
  //
  // Pure string builders so the storage layout is asserted in one place and
  // the tests can verify it without Firestore.

  /// `users/{uid}/farms/{farmId}/veldCamps/{campId}`
  static String campPath(String outfitterUid, String farmId, String campId) =>
      '$usersCollection/$outfitterUid/$farmsCollection/$farmId/'
      '$campsCollection/$campId';

  /// `users/{uid}/farms/{farmId}/veldCamps/{campId}/stock/{entryId}`
  static String stockPath(
    String outfitterUid,
    String farmId,
    String campId,
    String entryId,
  ) =>
      '${campPath(outfitterUid, farmId, campId)}/$stockCollection/$entryId';

  /// `users/{uid}/farms/{farmId}/veldCamps/{campId}/plantedAreas/{areaId}`
  static String plantedAreaPath(
    String outfitterUid,
    String farmId,
    String campId,
    String areaId,
  ) =>
      '${campPath(outfitterUid, farmId, campId)}/$plantedAreasCollection/'
      '$areaId';

  /// `users/{uid}/farms/{farmId}/veldCamps/{campId}/predators/{predatorId}`
  static String predatorPath(
    String outfitterUid,
    String farmId,
    String campId,
    String predatorId,
  ) =>
      '${campPath(outfitterUid, farmId, campId)}/$predatorsCollection/'
      '$predatorId';

  /// `users/{uid}/farms/{farmId}/permits/{permitId}`
  static String permitPath(
    String outfitterUid,
    String farmId,
    String permitId,
  ) =>
      '$usersCollection/$outfitterUid/$farmsCollection/$farmId/'
      '$permitsCollection/$permitId';

  /// Generates a document id for a new camp / child record.
  ///
  /// The UI needs a stable id before the first write because the models carry
  /// their own `id` and the repository signatures return `void`.
  static String newId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = Random().nextInt(0x7fffffff).toRadixString(36);
    return 'vc_${micros}_$suffix';
  }

  /// The single write-payload rule used by every upsert:
  /// `updatedAt` is always "now"; `createdAt` is written only for a NEW
  /// document so an edit can never move the creation timestamp.
  ///
  /// Pure so the rule is unit-testable without Firestore.
  static Map<String, dynamic> buildUpsertPayload({
    required Map<String, dynamic> base,
    required bool isNew,
    DateTime? now,
  }) {
    final payload = Map<String, dynamic>.from(base);
    payload['updatedAt'] = Timestamp.fromDate(now ?? DateTime.now());
    if (!isNew) {
      payload.remove('createdAt');
    }
    return payload;
  }

  // ── Camps ─────────────────────────────────────────────────────────────

  /// Creates or updates [camp] at `users/{uid}/farms/{farmId}/veldCamps`.
  ///
  /// Merge-write: a later phase can add fields to the camp document without
  /// this call wiping them. `createdAt` is preserved across edits.
  Future<void> saveCamp(String outfitterUid, Camp camp) async {
    requireOwnership(outfitterUid);
    final campId = camp.id.trim();
    final farmId = camp.farmId.trim();
    if (campId.isEmpty) {
      throw const VeldCarryRepositoryException('Camp id is required.');
    }
    if (farmId.isEmpty) {
      throw const VeldCarryRepositoryException('Camp farmId is required.');
    }
    final db = _requireFirestore();
    final ref = db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(farmId)
        .collection(campsCollection)
        .doc(campId);
    await _upsert(ref, camp.toMap());
  }

  /// Lists the camps of a farm, ordered by name.
  Future<List<Camp>> getCamps(String outfitterUid, String farmId) async {
    requireOwnership(outfitterUid);
    final farm = _requireFarmId(farmId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(farm)
        .collection(campsCollection)
        .orderBy('name')
        .get();
    return snapshot.docs
        .map((doc) => Camp.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
  }

  /// Reads one camp, or null when the document does not exist.
  ///
  /// Used by the camp detail screen to refresh its header after an edit
  /// without leaving the screen.
  Future<Camp?> getCamp(
    String outfitterUid,
    String farmId,
    String campId,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return Camp.fromMap(data, id: snapshot.id);
  }

  // ── Camp children ─────────────────────────────────────────────────────

  /// Creates or updates one species row of a camp's stock ledger.
  Future<void> saveStockEntry(
    String outfitterUid,
    String farmId,
    String campId,
    StockEntry entry,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final entryId = entry.id.trim();
    if (entryId.isEmpty) {
      throw const VeldCarryRepositoryException('Stock entry id is required.');
    }
    final db = _requireFirestore();
    final ref = db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(stockCollection)
        .doc(entryId);
    await _upsert(ref, entry.toMap());
  }

  /// Lists a camp's stock ledger, ordered by species name.
  ///
  /// Read-only helper used by the camp list to report real stocking pressure.
  /// The seven Phase 0D signatures above are unchanged.
  Future<List<StockEntry>> getStockEntries(
    String outfitterUid,
    String farmId,
    String campId,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(stockCollection)
        .orderBy('speciesName')
        .get();
    return snapshot.docs
        .map((doc) => StockEntry.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
  }

  /// Lists a camp's planted areas, ordered by feed type.
  ///
  /// Read-only helper used by the camp detail screen and the camp list's
  /// year-round capacity total. Ordered client-side so no composite index is
  /// required.
  Future<List<PlantedArea>> getPlantedAreas(
    String outfitterUid,
    String farmId,
    String campId,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(plantedAreasCollection)
        .get();
    final areas = snapshot.docs
        .map((doc) => PlantedArea.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
    areas.sort((a, b) => a.feedType.compareTo(b.feedType));
    return areas;
  }

  /// Lists a camp's predator records, ordered by predator name.
  Future<List<PredatorEntry>> getPredators(
    String outfitterUid,
    String farmId,
    String campId,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(predatorsCollection)
        .get();
    final predators = snapshot.docs
        .map((doc) => PredatorEntry.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
    predators.sort((a, b) => a.predatorName.compareTo(b.predatorName));
    return predators;
  }

  /// Creates or updates one planted area of a camp.
  Future<void> savePlantedArea(
    String outfitterUid,
    String farmId,
    String campId,
    PlantedArea area,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final areaId = area.id.trim();
    if (areaId.isEmpty) {
      throw const VeldCarryRepositoryException('Planted area id is required.');
    }
    final db = _requireFirestore();
    final ref = db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(plantedAreasCollection)
        .doc(areaId);
    await _upsert(ref, area.toMap());
  }

  /// Creates or updates one predator record of a camp.
  Future<void> savePredatorEntry(
    String outfitterUid,
    String farmId,
    String campId,
    PredatorEntry entry,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final entryId = entry.id.trim();
    if (entryId.isEmpty) {
      throw const VeldCarryRepositoryException(
        'Predator entry id is required.',
      );
    }
    final db = _requireFirestore();
    final ref = db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(predatorsCollection)
        .doc(entryId);
    await _upsert(ref, entry.toMap());
  }

  // ── Stock history (movements) ─────────────────────────────────────────

  /// Per-camp movement history.
  static const String stockHistoryCollection = 'stockHistory';

  /// `users/{uid}/farms/{farmId}/veldCamps/{campId}/stockHistory/{movementId}`
  static String stockMovementPath(
    String outfitterUid,
    String farmId,
    String campId,
    String movementId,
  ) =>
      '${campPath(outfitterUid, farmId, campId)}/$stockHistoryCollection/'
      '$movementId';

  /// `users/{uid}/farms/{farmId}/stockHistory/{movementId}`
  ///
  /// The farm-level mirror of a movement, so the farm-wide history view is a
  /// single read instead of one query per camp. Still nested under the user
  /// document — no new top-level collection.
  static String farmStockMovementPath(
    String outfitterUid,
    String farmId,
    String movementId,
  ) =>
      '$usersCollection/$outfitterUid/$farmsCollection/$farmId/'
      '$stockHistoryCollection/$movementId';

  /// Stable stock-ledger document id for [speciesName] (`Greater Kudu` ->
  /// `greater_kudu`).
  ///
  /// A movement must update the SAME row the stock form writes, so this mirrors
  /// the id derivation used by the stock form. Public (and unit-tested) so the
  /// two can never silently diverge.
  static String speciesStockEntryId(String speciesName) {
    final normalised = speciesName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalised.isEmpty ? newId() : normalised;
  }

  /// Records [movement] and applies its count deltas to the affected camps'
  /// stock ledgers **in one Firestore transaction**.
  ///
  /// A `moved_in` / `moved_out` record touches two camps (source −N,
  /// destination +N); `hunted` / `died` / `sold` touch one (−N); `added` and
  /// `count_adjustment` touch one (+/−N).
  ///
  /// The movement is written to the per-camp history of every camp it affects
  /// AND to the farm-level mirror, all inside the same transaction, so history
  /// and stock can never be left out of sync.
  ///
  /// Throws [StockBelowZeroException] when the result would be negative — the
  /// count is never clamped to zero.
  Future<StockMovement> recordStockMovement(
    String outfitterUid,
    StockMovement movement, {
    DateTime? now,
  }) async {
    requireOwnership(outfitterUid);
    final owner = _requireOutfitterUid(outfitterUid);
    final farm = _requireFarmId(movement.farmId);
    final movementId = movement.id.trim();
    if (movementId.isEmpty) {
      throw const VeldCarryRepositoryException('Movement id is required.');
    }
    final validation = movement.validationError;
    if (validation != null) {
      throw VeldCarryRepositoryException(validation);
    }
    final deltas = StockMovement.campDeltas(movement);
    if (deltas.isEmpty) {
      throw const VeldCarryRepositoryException(
        'The movement does not affect any camp.',
      );
    }
    final speciesId = movement.speciesId.trim().isEmpty
        ? speciesStockEntryId(movement.speciesName)
        : movement.speciesId.trim();
    final stamp = now ?? movement.recordedAt;
    final record = movement.copyWith(
      id: movementId,
      farmId: farm,
      speciesId: speciesId,
      recordedBy: movement.recordedBy ?? owner,
      recordedAt: stamp,
      updatedAt: stamp,
    );
    final db = _requireFirestore();

    await db.runTransaction((transaction) async {
      final pending =
          <({DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> payload})>[];

      for (final delta in deltas.entries) {
        final campId = delta.key;
        final ref = _stockEntryRef(db, owner, farm, campId, speciesId);
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        if (snapshot.exists && data != null) {
          final current = StockEntry.fromMap(data, id: snapshot.id);
          final updated = StockMovement.applyDeltaToStockEntry(
            current,
            delta.value,
            now: stamp,
          );
          pending.add((ref: ref, payload: updated.toMap()));
          continue;
        }
        if (delta.value < 0) {
          throw StockBelowZeroException(
            campId: campId,
            speciesName: record.speciesName,
            currentCount: 0,
            requested: delta.value,
          );
        }
        pending.add((
          ref: ref,
          payload: _newStockEntryFor(record, campId, delta.value, stamp)
              .toMap(),
        ));
      }

      for (final write in pending) {
        transaction.set(write.ref, write.payload, SetOptions(merge: true));
      }

      final historyRefs = <DocumentReference<Map<String, dynamic>>>{
        for (final campId in record.historyCampIds)
          _stockMovementRef(db, owner, farm, campId, movementId),
        _farmStockMovementRef(db, owner, farm, movementId),
      };
      for (final ref in historyRefs) {
        transaction.set(ref, record.toMap(), SetOptions(merge: true));
      }
    });

    return record;
  }

  /// A camp's movements, or the whole farm's when [campId] is null / blank.
  ///
  /// Newest first. The single-field `orderBy('recordedAt')` needs no composite
  /// index (there is no `where` clause).
  Future<List<StockMovement>> getStockMovements(
    String outfitterUid,
    String farmId, {
    String? campId,
    int? limit,
  }) async {
    requireOwnership(outfitterUid);
    final owner = _requireOutfitterUid(outfitterUid);
    final farm = _requireFarmId(farmId);
    final db = _requireFirestore();
    final camp = (campId ?? '').trim();
    final CollectionReference<Map<String, dynamic>> collection = camp.isEmpty
        ? db
            .collection(usersCollection)
            .doc(owner)
            .collection(farmsCollection)
            .doc(farm)
            .collection(stockHistoryCollection)
        : db
            .collection(usersCollection)
            .doc(owner)
            .collection(farmsCollection)
            .doc(farm)
            .collection(campsCollection)
            .doc(camp)
            .collection(stockHistoryCollection);
    Query<Map<String, dynamic>> query =
        collection.orderBy('recordedAt', descending: true);
    if (limit != null && limit > 0) query = query.limit(limit);
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => StockMovement.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
  }

  // ── Rainfall log ──────────────────────────────────────────────────────

  /// Per-camp monthly rainfall records.
  static const String rainfallCollection = 'rainfall';

  /// `users/{uid}/farms/{farmId}/veldCamps/{campId}/rainfall/{month}`
  static String rainfallPath(
    String outfitterUid,
    String farmId,
    String campId,
    String month,
  ) =>
      '${campPath(outfitterUid, farmId, campId)}/$rainfallCollection/$month';

  /// Creates or overwrites the entry for [RainfallEntry.month].
  ///
  /// The document id IS the month key, so recording the same month twice
  /// updates that month instead of adding a duplicate. `createdAt` is preserved
  /// across the overwrite.
  Future<RainfallEntry> saveRainfallEntry(
    String outfitterUid,
    RainfallEntry entry,
  ) async {
    requireOwnership(outfitterUid);
    final owner = _requireOutfitterUid(outfitterUid);
    final farm = _requireFarmId(entry.farmId);
    final camp = entry.campId.trim();
    if (camp.isEmpty) {
      throw const VeldCarryRepositoryException('Camp id is required.');
    }
    final month = RainfallEntry.normalizeMonth(entry.month);
    if (month == null) {
      throw const VeldCarryRepositoryException(
        'Choose a valid month (expected YYYY-MM).',
      );
    }
    final validation = entry.validationError;
    if (validation != null) {
      throw VeldCarryRepositoryException(validation);
    }
    final db = _requireFirestore();
    final record = entry.copyWith(
      id: month,
      farmId: farm,
      campId: camp,
      month: month,
    );
    final ref = db
        .collection(usersCollection)
        .doc(owner)
        .collection(farmsCollection)
        .doc(farm)
        .collection(campsCollection)
        .doc(camp)
        .collection(rainfallCollection)
        .doc(month);
    await _upsert(ref, record.toMap());
    return record;
  }

  /// A camp's rainfall entries, newest month first.
  Future<List<RainfallEntry>> getRainfallEntries(
    String outfitterUid,
    String farmId,
    String campId,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(rainfallCollection)
        .orderBy('month', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => RainfallEntry.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
  }

  /// Total millimetres recorded for [year] (defaults to the current year).
  ///
  /// The sum is produced by `veld_carry_calculator.dart` like every other
  /// number in the feature.
  Future<double> getRainfallTotalForYear(
    String outfitterUid,
    String farmId,
    String campId, {
    int? year,
  }) async {
    final entries = await getRainfallEntries(outfitterUid, farmId, campId);
    return rainfallTotalForYear(entries, year ?? DateTime.now().year);
  }

  DocumentReference<Map<String, dynamic>> _stockEntryRef(
    FirebaseFirestore db,
    String outfitterUid,
    String farmId,
    String campId,
    String entryId,
  ) =>
      db
          .collection(usersCollection)
          .doc(outfitterUid)
          .collection(farmsCollection)
          .doc(farmId)
          .collection(campsCollection)
          .doc(campId)
          .collection(stockCollection)
          .doc(entryId);

  DocumentReference<Map<String, dynamic>> _stockMovementRef(
    FirebaseFirestore db,
    String outfitterUid,
    String farmId,
    String campId,
    String movementId,
  ) =>
      db
          .collection(usersCollection)
          .doc(outfitterUid)
          .collection(farmsCollection)
          .doc(farmId)
          .collection(campsCollection)
          .doc(campId)
          .collection(stockHistoryCollection)
          .doc(movementId);

  DocumentReference<Map<String, dynamic>> _farmStockMovementRef(
    FirebaseFirestore db,
    String outfitterUid,
    String farmId,
    String movementId,
  ) =>
      db
          .collection(usersCollection)
          .doc(outfitterUid)
          .collection(farmsCollection)
          .doc(farmId)
          .collection(stockHistoryCollection)
          .doc(movementId);

  /// A brand-new stock row for a movement that introduces a species to a camp.
  ///
  /// Weights, feeding class and grazer/browser split come from
  /// `species_defaults.dart`; the per-animal LSU / GU / BU figures come from
  /// `veld_carry_calculator.dart` — never invented here, and never left at zero
  /// (a zeroed row would silently drop out of the carrying-capacity total).
  StockEntry _newStockEntryFor(
    StockMovement movement,
    String campId,
    int count,
    DateTime now,
  ) {
    final species = speciesDefaultFor(movement.speciesName);
    final weight = species?.avgWeightKg ?? 0.0;
    final grazer = species?.grazerPct ?? 0.5;
    final browser = species?.browserPct ?? 0.5;
    return StockEntry(
      id: movement.speciesId,
      campId: campId,
      speciesName: species?.speciesName ?? movement.speciesName,
      scientificName: species?.scientificName,
      feedingClass: species?.feedingClass ?? StockEntry.feedingClassMixed,
      count: count,
      avgWeightKg: weight,
      grazerPct: grazer,
      browserPct: browser,
      isOmnivore: species?.isOmnivore,
      isCounted: species?.isCounted,
      lsuPerAnimal: lsuPerAnimal(weight),
      guPerAnimal: guPerAnimal(weight, grazer),
      buPerAnimal: buPerAnimal(weight, browser),
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── Farm-wide permits ─────────────────────────────────────────────────

  /// Creates or updates a farm-wide permit.
  Future<void> savePermit(
    String outfitterUid,
    String farmId,
    FarmPermit permit,
  ) async {
    requireOwnership(outfitterUid);
    final farm = _requireFarmId(farmId);
    final permitId = permit.id.trim();
    if (permitId.isEmpty) {
      throw const VeldCarryRepositoryException('Permit id is required.');
    }
    final db = _requireFirestore();
    final ref = db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(farm)
        .collection(permitsCollection)
        .doc(permitId);
    await _upsert(ref, permit.toMap());
  }

  /// Lists the permits of a farm, ordered by permit type.
  Future<List<FarmPermit>> getPermits(
    String outfitterUid,
    String farmId,
  ) async {
    requireOwnership(outfitterUid);
    final farm = _requireFarmId(farmId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(farm)
        .collection(permitsCollection)
        .orderBy('permitType')
        .get();
    return snapshot.docs
        .map((doc) => FarmPermit.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
  }

  // ── Derived read models: alerts + veld report ─────────────────────────
  //
  // Alerts and reports are DERIVED: they load the same records the screens
  // already load and hand them to the pure builders in
  // `veld_carry_alerts.dart` / `veld_carry_report.dart`. Nothing is written
  // back, so an alert or a report can never drift from the live data.

  /// Builds the farm's live alerts, most urgent first. Read-only.
  ///
  /// A camp whose child records cannot be read is treated as "unknown" (its
  /// alerts are skipped) so one failed child read cannot hide the farm's other
  /// alerts — `buildAlerts` only raises `no_*_recorded` for a camp it could
  /// read and found genuinely empty.
  Future<List<VeldAlert>> getAlertsForFarm(
    String outfitterUid,
    String farmId, {
    DateTime? now,
  }) async {
    requireOwnership(outfitterUid);
    final farm = _requireFarmId(farmId);
    final camps = await getCamps(outfitterUid, farm);

    final stockByCamp = <String, List<StockEntry>>{};
    final rainfallByCamp = <String, List<RainfallEntry>>{};
    for (final camp in camps) {
      try {
        stockByCamp[camp.id] =
            await getStockEntries(outfitterUid, farm, camp.id);
      } catch (e) {
        debugPrint(
          'VeldCarryRepository.getAlertsForFarm: stock read failed for camp '
          '${camp.id}: $e',
        );
      }
      try {
        rainfallByCamp[camp.id] =
            await getRainfallEntries(outfitterUid, farm, camp.id);
      } catch (e) {
        debugPrint(
          'VeldCarryRepository.getAlertsForFarm: rainfall read failed for '
          'camp ${camp.id}: $e',
        );
      }
    }

    final permits = await getPermits(outfitterUid, farm);
    return buildAlerts(
      camps: camps,
      stockByCamp: stockByCamp,
      permits: permits,
      rainfallByCamp: rainfallByCamp,
      now: now,
    );
  }

  /// Builds the whole-farm veld report. Read-only.
  ///
  /// Unlike [getAlertsForFarm], a failed child read is rethrown: a report that
  /// silently showed zero stock for an unreadable camp would be worse than no
  /// report at all.
  Future<VeldReport> getVeldReportForFarm(
    String outfitterUid,
    Farm farm, {
    DateTime? now,
  }) async {
    requireOwnership(outfitterUid);
    final farmId = _requireFarmId(farm.id);
    final camps = await getCamps(outfitterUid, farmId);
    final permits = await getPermits(outfitterUid, farmId);
    return _buildReport(
      outfitterUid: outfitterUid,
      farm: farm,
      camps: camps,
      permits: permits,
      now: now,
    );
  }

  /// Builds a single-camp veld report. Read-only.
  ///
  /// Permits are narrowed to those that name this camp or carry no camp
  /// restriction (farm-wide).
  Future<VeldReport> getVeldReportForCamp(
    String outfitterUid,
    Farm farm,
    String campId, {
    DateTime? now,
  }) async {
    requireOwnership(outfitterUid);
    final farmId = _requireFarmId(farm.id);
    final campIds = _requireCampIds(farmId: farmId, campId: campId);
    final camp = await getCamp(outfitterUid, farmId, campIds.campId);
    if (camp == null) {
      throw const VeldCarryRepositoryException('Camp not found.');
    }
    final permits = await getPermits(outfitterUid, farmId);
    final relevant = permits
        .where((p) => p.campIds.isEmpty || p.campIds.contains(campIds.campId))
        .toList(growable: false);
    return _buildReport(
      outfitterUid: outfitterUid,
      farm: farm,
      camps: <Camp>[camp],
      permits: relevant,
      now: now,
    );
  }

  Future<VeldReport> _buildReport({
    required String outfitterUid,
    required Farm farm,
    required List<Camp> camps,
    required List<FarmPermit> permits,
    DateTime? now,
  }) async {
    final farmId = _requireFarmId(farm.id);
    final stockByCamp = <String, List<StockEntry>>{};
    final plantedByCamp = <String, List<PlantedArea>>{};
    final predatorsByCamp = <String, List<PredatorEntry>>{};
    final rainfallByCamp = <String, List<RainfallEntry>>{};
    for (final camp in camps) {
      stockByCamp[camp.id] =
          await getStockEntries(outfitterUid, farmId, camp.id);
      plantedByCamp[camp.id] =
          await getPlantedAreas(outfitterUid, farmId, camp.id);
      predatorsByCamp[camp.id] =
          await getPredators(outfitterUid, farmId, camp.id);
      rainfallByCamp[camp.id] =
          await getRainfallEntries(outfitterUid, farmId, camp.id);
    }
    return buildVeldReport(
      farm: farm,
      camps: camps,
      stockByCamp: stockByCamp,
      plantedByCamp: plantedByCamp,
      predatorsByCamp: predatorsByCamp,
      permits: permits,
      rainfallByCamp: rainfallByCamp,
      now: now,
    );
  }

  // ── Hunter-safe reads ────────────────────────────────────────────────
  //
  // The hunter view (`veld_carry_hunter_view_screen.dart`) is READ-ONLY and
  // must NEVER call the ownership-gated methods above: a hunter is not the
  // farm's outfitter. These reads skip [requireOwnership] and take the
  // outfitter uid explicitly (the hunter already has it from the package /
  // farm document it is allowed to read).
  //
  // The live Firestore rules enforce the hunter visibility, and the hunter
  // reads fail closed on a booking relationship (see
  // [hunterHasBookingForFarm]). These methods are a client-side convenience,
  // not the security boundary: they only ever return hunter-safe data and the
  // UI renders a restricted subset (no GPS, no weights, no permit number /
  // file).
  //
  // QUERY SHAPE MATTERS. Firestore rules are not filters: a rule that inspects
  // a field (`resource.data.visibility == 'hunter_visible'`) can only serve a
  // QUERY that constrains the same field. `getPermitsForHunter` therefore
  // issues a `where('visibility', ...)` query — an unconstrained read would be
  // rejected with `permission-denied` for a non-owner, not silently narrowed.
  // The camp rule inspects `resource.data.allowedHunterUids`, so
  // `getCampsForHunter` issues `.where('allowedHunterUids', arrayContains:
  // hunterUid)`. Stock / plantedAreas need no `where()`: their rule resolves
  // the allow-list through a `get()` on the fully-specified parent camp path.

  // ── Booking gate (hunter reads) ───────────────────────────────────────
  //
  // Go-live relationship check: a hunter may only read a farm's veld data when
  // they hold a booking on that farm. The ruleset cannot express this (a rule
  // cannot read another collection), so it is enforced here, client-side, and
  // fails closed.

  /// The app's real booking store (top-level `bookings` collection, written by
  /// `PackageBookingManager` / `FarmGamePriceListManager`).
  static const String bookingsCollection = 'bookings';

  /// Booking statuses that grant a hunter access to a farm's veld data.
  ///
  /// Canonical [BookingStatus] values only; the legacy `Paid` spelling is
  /// accepted too because [BookingStatus.normalize] maps it to
  /// [BookingStatus.confirmed].
  static const List<String> veldAccessBookingStatuses = [
    BookingStatus.confirmed,
    BookingStatus.completed,
  ];

  /// True when [hunterUid] holds a `confirmed` / `completed` booking on
  /// [farmId].
  ///
  /// The query constrains `hunterId` only — a single-field equality, which uses
  /// the automatic index and needs no composite index — and filters `farmId` +
  /// the status client-side. That is the established project pattern for a
  /// multi-condition read (see `OutfitterAnalyticsService`).
  ///
  /// Fails CLOSED: a blank uid / farmId, an unavailable Firestore or a read
  /// error all resolve to `false`, so the caller hides the data rather than
  /// serving it to a caller with no verified relationship to the farm.
  Future<bool> hunterHasBookingForFarm(
    String hunterUid,
    String farmId,
  ) async {
    final hunter = hunterUid.trim();
    final farm = farmId.trim();
    if (hunter.isEmpty || farm.isEmpty) return false;
    try {
      final db = _requireFirestore();
      final snapshot = await db
          .collection(bookingsCollection)
          .where('hunterId', isEqualTo: hunter)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if ((data['farmId'] ?? '').toString().trim() != farm) continue;
        final status = BookingStatus.normalize(data['status'] as String?);
        if (veldAccessBookingStatuses.contains(status)) return true;
      }
      return false;
    } catch (e) {
      debugPrint(
        'VeldCarryRepository: booking check failed ($e) — fail closed.',
      );
      return false;
    }
  }

  /// Whether a hunter read should be served.
  ///
  /// A null [hunterUid] means "no booking gate requested" (the outfitter's own
  /// screens and the pre-Phase-6 call sites), so the read proceeds. A non-null
  /// uid is gated on [hunterHasBookingForFarm] and fails closed.
  ///
  /// NOTE: [getCampsForHunter] is stricter — it short-circuits to an empty list
  /// on a null / blank uid BEFORE reaching this gate, because its query must
  /// carry the `allowedHunterUids` constraint.
  Future<bool> _hunterReadAllowed(String? hunterUid, String farmId) async {
    if (hunterUid == null) return true;
    return hunterHasBookingForFarm(hunterUid, farmId);
  }

  // ── Denormalised hunter access (`allowedHunterUids`) ─────────────────────
  //
  // The rules cannot read `bookings`, so the booking relationship is mirrored
  // onto every camp of the farm as an array of hunter uids. The go-live rule
  // can then gate a hunter read with
  // `request.auth.uid in resource.data.allowedHunterUids`.
  //
  // The client-side gate above stays in place as the primary enforcement: the
  // array is a denormalisation that must be SYNCED before it can grant access.

  /// The camp document field holding the allow-list.
  static const String allowedHunterUidsField = Camp.allowedHunterUidsField;

  /// Timestamp field stamped by [syncAllowedHuntersForFarm] so an operator can
  /// see when the allow-list was last refreshed.
  static const String allowedHunterUidsSyncedAtField =
      'allowedHunterUidsSyncedAt';

  /// Union semantics identical to `FieldValue.arrayUnion`: existing entries are
  /// preserved, duplicates are dropped, order is stable.
  ///
  /// Pure so the contract the rule relies on is unit-testable.
  static List<String> mergeAllowedHunterUids(
      Object? current, Object? incoming) {
    final merged = <String>[];
    for (final uid in Camp.normalizeAllowedHunterUids(current)) {
      if (!merged.contains(uid)) merged.add(uid);
    }
    for (final uid in Camp.normalizeAllowedHunterUids(incoming)) {
      if (!merged.contains(uid)) merged.add(uid);
    }
    return merged;
  }

  /// Hunters holding a `confirmed` / `completed` booking on [farmId], as
  /// recorded against the outfitter's own bookings.
  ///
  /// The query constrains `outfitterId` only (single-field equality — automatic
  /// index, and the shape the party-scoped `bookings` rule can serve); `farmId`
  /// and the status are filtered client-side. Pending / awaiting-payment /
  /// declined / cancelled bookings never grant access.
  Future<List<String>> collectAllowedHunterUidsForFarm(
    String outfitterUid,
    String farmId,
  ) async {
    final owner = _requireOutfitterUid(outfitterUid);
    final farm = _requireFarmId(farmId);
    final db = _requireFirestore();
    final snapshot = await db
        .collection(bookingsCollection)
        .where('outfitterId', isEqualTo: owner)
        .get();
    final hunterUids = <String>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if ((data['farmId'] ?? '').toString().trim() != farm) continue;
      final status = BookingStatus.normalize(data['status'] as String?);
      if (!veldAccessBookingStatuses.contains(status)) continue;
      final hunter = (data['hunterId'] ?? '').toString().trim();
      if (hunter.isEmpty || hunterUids.contains(hunter)) continue;
      hunterUids.add(hunter);
    }
    return List<String>.unmodifiable(hunterUids);
  }

  /// Writes the farm's confirmed-hunter allow-list onto EVERY camp of [farmId].
  ///
  /// [outfitterUid] defaults to the signed-in user; the caller must be the
  /// farm's outfitter (the veld data lives in their own document).
  ///
  /// **Removal policy — deliberately additive.** A hunter is ADDED on a
  /// confirmed/completed booking and is NEVER auto-removed when a booking is
  /// cancelled or refunded. Keeping access is the safer failure mode (a hunter
  /// losing mid-trip access to the camp data would be worse than stale access),
  /// and a cancellation is often followed by a rebooking. Removing access is an
  /// explicit operator action, not an automatic side effect.
  ///
  /// Writes are additive too: `allowedHunterUids` is merged with
  /// `FieldValue.arrayUnion`, so a hunter already on the list stays there and
  /// no duplicate can appear. When the farm has no confirmed hunter, the field
  /// is seeded as `[]` (never left absent) so the go-live rule evaluates a list
  /// instead of a missing field and fails closed cleanly.
  Future<VeldHunterAccessSyncResult> syncAllowedHuntersForFarm(
    String farmId, {
    String? outfitterUid,
  }) async {
    final farm = _requireFarmId(farmId);
    final owner = _requireOutfitterUid(outfitterUid ?? _currentUserId ?? '');
    requireOwnership(owner);

    final db = _requireFirestore();
    final hunterUids = await collectAllowedHunterUidsForFarm(owner, farm);
    final campsRef = db
        .collection(usersCollection)
        .doc(owner)
        .collection(farmsCollection)
        .doc(farm)
        .collection(campsCollection);
    final camps = await campsRef.get();

    var campsTouched = 0;
    for (final doc in camps.docs) {
      final data = doc.data();
      final hasField = data.containsKey(allowedHunterUidsField);
      final current = Camp.normalizeAllowedHunterUids(
        data[allowedHunterUidsField],
      );
      final needsWrite = hunterUids.isEmpty
          ? !hasField
          : hunterUids.any((uid) => !current.contains(uid));
      if (!needsWrite) continue;

      if (hunterUids.isEmpty) {
        // Seed the list so the rule never evaluates a missing field.
        await doc.reference.set(
          {
            allowedHunterUidsField: <String>[],
            allowedHunterUidsSyncedAtField: FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        // arrayUnion is atomic and duplicate-free (union semantics).
        await doc.reference.set(
          {
            allowedHunterUidsField: FieldValue.arrayUnion(hunterUids),
            allowedHunterUidsSyncedAtField: FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      campsTouched++;
    }

    return VeldHunterAccessSyncResult(
      farmId: farm,
      hunterUids: hunterUids,
      campCount: camps.docs.length,
      campsTouched: campsTouched,
    );
  }

  /// Camps of [farmId], read for a hunter (no ownership check).
  ///
  /// The Phase 7D rule gates a camp on
  /// `request.auth.uid in resource.data.allowedHunterUids`, and Firestore rules
  /// are not filters: the QUERY must constrain the same field or the read is
  /// rejected with `permission-denied`. The read therefore issues
  /// `.where('allowedHunterUids', arrayContains: hunterUid)`.
  ///
  /// Fails CLOSED on a missing uid: a null / blank [hunterUid] returns an empty
  /// list and never runs an unconstrained query.
  ///
  /// The allow-list membership is re-checked client-side before a camp is
  /// returned. That is a SECOND DEFENCE, not the security boundary — the
  /// Firestore rule is authoritative.
  Future<List<Camp>> getCampsForHunter(
    String farmId, {
    required String outfitterUid,
    String? hunterUid,
  }) async {
    final farm = _requireFarmId(farmId);
    final owner = _requireOutfitterUid(outfitterUid);
    final hunter = (hunterUid ?? '').trim();
    if (hunter.isEmpty) return const <Camp>[];
    if (!await _hunterReadAllowed(hunter, farm)) return const <Camp>[];
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(owner)
        .collection(farmsCollection)
        .doc(farm)
        .collection(campsCollection)
        .where(allowedHunterUidsField, arrayContains: hunter)
        .get();
    final camps = snapshot.docs
        .map((doc) => Camp.fromMap(doc.data(), id: doc.id))
        .where((camp) => camp.allowedHunterUids.contains(hunter))
        .toList(growable: false);
    return List<Camp>.of(camps)..sort((a, b) => a.name.compareTo(b.name));
  }

  /// One camp of [farmId], read for a hunter (no ownership check).
  ///
  /// Returns null when the camp does not exist, or when [hunterUid] is supplied
  /// and has no booking on the farm (fail closed).
  Future<Camp?> getCampForHunter(
    String farmId,
    String campId, {
    required String outfitterUid,
    String? hunterUid,
  }) async {
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final owner = _requireOutfitterUid(outfitterUid);
    if (!await _hunterReadAllowed(hunterUid, camp.farmId)) return null;
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(owner)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return Camp.fromMap(data, id: snapshot.id);
  }

  /// A camp's stock ledger, read for a hunter (no ownership check).
  ///
  /// The caller must render ONLY `speciesName` + `count` — the weights and the
  /// GU/BU split stay on the outfitter side.
  ///
  /// An empty list is returned when [hunterUid] is supplied and has no booking
  /// on the farm (fail closed).
  Future<List<StockEntry>> getStockForHunter(
    String farmId,
    String campId, {
    required String outfitterUid,
    String? hunterUid,
  }) async {
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final owner = _requireOutfitterUid(outfitterUid);
    if (!await _hunterReadAllowed(hunterUid, camp.farmId)) {
      return const <StockEntry>[];
    }
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(owner)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(stockCollection)
        .get();
    final stock = snapshot.docs
        .map((doc) => StockEntry.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
    return List<StockEntry>.of(stock)
      ..sort((a, b) => a.speciesName.compareTo(b.speciesName));
  }

  /// A camp's planted areas, read for a hunter (no ownership check).
  ///
  /// Needed so the hunter-facing capacity total matches the outfitter screen
  /// (year-round planted areas add to the veld capacity). Feed type + hectares
  /// are not sensitive; no location data is exposed.
  ///
  /// An empty list is returned when [hunterUid] is supplied and has no booking
  /// on the farm (fail closed).
  Future<List<PlantedArea>> getPlantedAreasForHunter(
    String farmId,
    String campId, {
    required String outfitterUid,
    String? hunterUid,
  }) async {
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final owner = _requireOutfitterUid(outfitterUid);
    if (!await _hunterReadAllowed(hunterUid, camp.farmId)) {
      return const <PlantedArea>[];
    }
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(owner)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(plantedAreasCollection)
        .get();
    final areas = snapshot.docs
        .map((doc) => PlantedArea.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
    return List<PlantedArea>.of(areas)
      ..sort((a, b) => a.feedType.compareTo(b.feedType));
  }

  /// A farm's permits, read for a hunter (no ownership check).
  ///
  /// Only `hunter_visible` permits are returned — a `private` permit can never
  /// reach the hunter view. The UI additionally renders ONLY the permit type,
  /// expiry date and status (never the permit number, the issuing authority or
  /// the attached file).
  ///
  /// The `where('visibility', ...)` constraint is REQUIRED, not an
  /// optimisation: the go-live permit rule is
  /// `resource.data.visibility == 'hunter_visible'`, and Firestore rejects an
  /// unconstrained non-owner read of a `resource.data`-guarded collection with
  /// `permission-denied`. The client-side [hunterVisiblePermits] filter is kept
  /// as a second line of defence — the query is never trusted on its own.
  ///
  /// An empty list is returned when [hunterUid] is supplied and has no booking
  /// on the farm (fail closed).
  Future<List<FarmPermit>> getPermitsForHunter(
    String farmId, {
    required String outfitterUid,
    String? hunterUid,
  }) async {
    final farm = _requireFarmId(farmId);
    final owner = _requireOutfitterUid(outfitterUid);
    if (!await _hunterReadAllowed(hunterUid, farm)) {
      return const <FarmPermit>[];
    }
    final db = _requireFirestore();
    final snapshot = await db
        .collection(usersCollection)
        .doc(owner)
        .collection(farmsCollection)
        .doc(farm)
        .collection(permitsCollection)
        .where('visibility', isEqualTo: FarmPermit.visibilityHunterVisible)
        .get();
    final permits = snapshot.docs
        .map((doc) => FarmPermit.fromMap(doc.data(), id: doc.id))
        .toList(growable: false);
    // Defence in depth: filter again in Dart. A query is a request, not a
    // guarantee — a mis-set document, a cached/offline read or a future rule
    // change must never let a private permit through.
    return hunterVisiblePermits(permits);
  }

  /// Filters [permits] down to the hunter-visible subset.
  ///
  /// Pure so the "a private permit never reaches the hunter" contract is
  /// unit-testable without Firestore.
  static List<FarmPermit> hunterVisiblePermits(Iterable<FarmPermit> permits) {
    final visible = <FarmPermit>[];
    for (final permit in permits) {
      if (permit.visibility == FarmPermit.visibilityHunterVisible) {
        visible.add(permit);
      }
    }
    return visible;
  }

  /// Species availability across every camp of [farmId], read for a hunter.
  ///
  /// Answers "which species can I hunt on this farm, and how many are there"
  /// without exposing anything else: the result carries only the species name,
  /// its scientific name, the total count and the camps it was counted on.
  /// No weights, no GU/BU, no camp sizes, no capacity and — critically — no
  /// coordinates.
  ///
  /// [outfitterUid] is required because the veld data lives inside the
  /// outfitter's own document (`users/{outfitterUid}/farms/{farmId}/...`); the
  /// hunter already holds it from the package document it may read.
  ///
  /// Two exclusions keep the list honest:
  ///
  ///  * **present-only species** (Baboon / Vervet / Porcupine / Aardvark) —
  ///    recorded for information, never huntable, so they are not offered;
  ///  * **zero counts** — a species with nothing counted is not "available".
  ///
  /// Fails CLOSED: a blank uid / farmId, a hunter with no booking on the farm
  /// or a Firestore error all resolve to an empty list.
  Future<List<SpeciesAvailability>> getSpeciesAvailabilityForHunter(
    String farmId,
    String? hunterUid, {
    required String outfitterUid,
  }) async {
    final farm = _requireFarmId(farmId);
    final owner = _requireOutfitterUid(outfitterUid);
    if (!await _hunterReadAllowed(hunterUid, farm)) {
      return const <SpeciesAvailability>[];
    }

    final camps = await getCampsForHunter(
      farm,
      outfitterUid: owner,
      hunterUid: hunterUid,
    );

    final stockByCampName = <String, List<StockEntry>>{};
    for (final camp in camps) {
      try {
        stockByCampName[camp.name.isEmpty ? 'Unnamed camp' : camp.name] =
            await getStockForHunter(
          farm,
          camp.id,
          outfitterUid: owner,
          hunterUid: hunterUid,
        );
      } catch (e) {
        // One unreadable camp must not hide the rest of the farm's species.
        debugPrint(
          'VeldCarryRepository: species availability stock read failed for '
          'camp ${camp.id}: $e',
        );
      }
    }

    return aggregateSpeciesAvailability(stockByCampName);
  }

  /// Aggregates per-camp stock ledgers into one hunter-facing species list.
  ///
  /// [stockByCampName] maps a camp's display name to that camp's stock rows.
  /// Present-only rows and zero counts are dropped; the remainder is grouped
  /// case-insensitively by species so the same species counted on two camps
  /// reports one row with the summed count and both camp names.
  ///
  /// Pure, so the aggregation contract is unit-testable without Firestore.
  static List<SpeciesAvailability> aggregateSpeciesAvailability(
    Map<String, List<StockEntry>> stockByCampName,
  ) {
    final counts = <String, int>{};
    final displayNames = <String, String>{};
    final scientificNames = <String, String>{};
    final campsBySpecies = <String, List<String>>{};

    final campNames = stockByCampName.keys.toList()..sort();
    for (final campName in campNames) {
      for (final entry in stockByCampName[campName] ?? const <StockEntry>[]) {
        // Present-only species are recorded for information, never hunted.
        if (!entry.isCounted) continue;
        // Nothing counted on the farm means the species is not available.
        if (entry.count <= 0) continue;

        final key = entry.speciesName.trim().toLowerCase();
        if (key.isEmpty) continue;

        displayNames.putIfAbsent(key, () => speciesDisplayName(entry.speciesName));
        scientificNames.putIfAbsent(
          key,
          () => entry.scientificName?.trim().isNotEmpty == true
              ? entry.scientificName!.trim()
              : (speciesDefaultFor(entry.speciesName)?.scientificName ?? ''),
        );
        counts[key] = (counts[key] ?? 0) + entry.count;
        final camps = campsBySpecies.putIfAbsent(key, () => <String>[]);
        if (!camps.contains(campName)) camps.add(campName);
      }
    }

    final species = counts.keys
        .map(
          (key) => SpeciesAvailability(
            speciesName: displayNames[key] ?? key,
            scientificName: scientificNames[key] ?? '',
            totalCount: counts[key] ?? 0,
            campNames: List<String>.unmodifiable(campsBySpecies[key] ?? const []),
          ),
        )
        .toList(growable: false);

    // Most abundant first; alphabetical tie-break keeps the order stable.
    return List<SpeciesAvailability>.of(species)
      ..sort((a, b) {
        final byCount = b.totalCount.compareTo(a.totalCount);
        if (byCount != 0) return byCount;
        return a.speciesName.toLowerCase().compareTo(b.speciesName.toLowerCase());
      });
  }

  // ── Deletes ───────────────────────────────────────────────────────────

  /// Deletes one stock row of a camp.
  Future<void> deleteStockEntry(
    String outfitterUid,
    String farmId,
    String campId,
    String entryId,
  ) =>
      _deleteChild(
        outfitterUid,
        farmId: farmId,
        campId: campId,
        collection: stockCollection,
        docId: entryId,
      );

  /// Deletes one planted area of a camp.
  Future<void> deletePlantedArea(
    String outfitterUid,
    String farmId,
    String campId,
    String areaId,
  ) =>
      _deleteChild(
        outfitterUid,
        farmId: farmId,
        campId: campId,
        collection: plantedAreasCollection,
        docId: areaId,
      );

  /// Deletes one predator record of a camp.
  Future<void> deletePredatorEntry(
    String outfitterUid,
    String farmId,
    String campId,
    String predatorId,
  ) =>
      _deleteChild(
        outfitterUid,
        farmId: farmId,
        campId: campId,
        collection: predatorsCollection,
        docId: predatorId,
      );

  /// Deletes one farm-wide permit.
  Future<void> deletePermit(
    String outfitterUid,
    String farmId,
    String permitId,
  ) async {
    requireOwnership(outfitterUid);
    final farm = _requireFarmId(farmId);
    final id = permitId.trim();
    if (id.isEmpty) {
      throw const VeldCarryRepositoryException('Permit id is required.');
    }
    final db = _requireFirestore();
    await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(farm)
        .collection(permitsCollection)
        .doc(id)
        .delete();
  }

  /// Deletes a camp document.
  ///
  /// Firestore does not cascade a delete to subcollections, so the child
  /// documents (stock / planted areas / predators) are **not** removed here.
  /// The camp detail screen deletes each child explicitly before calling this
  /// method; anything a client cannot remove (a rules-denied document, a
  /// concurrent write) is surfaced by the caller rather than silently orphaned.
  Future<void> deleteCamp(
    String outfitterUid,
    String farmId,
    String campId,
  ) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final db = _requireFirestore();
    await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .delete();
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Future<void> _deleteChild(
    String outfitterUid, {
    required String farmId,
    required String campId,
    required String collection,
    required String docId,
  }) async {
    requireOwnership(outfitterUid);
    final camp = _requireCampIds(farmId: farmId, campId: campId);
    final id = docId.trim();
    if (id.isEmpty) {
      throw const VeldCarryRepositoryException('Document id is required.');
    }
    final db = _requireFirestore();
    await db
        .collection(usersCollection)
        .doc(outfitterUid)
        .collection(farmsCollection)
        .doc(camp.farmId)
        .collection(campsCollection)
        .doc(camp.campId)
        .collection(collection)
        .doc(id)
        .delete();
  }

  Future<void> _upsert(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> base,
  ) async {
    final snapshot = await ref.get();
    final payload = buildUpsertPayload(base: base, isNew: !snapshot.exists);
    await ref.set(payload, SetOptions(merge: true));
  }

  FirebaseFirestore _requireFirestore() {
    final injected = _injectedFirestore;
    if (injected != null) return injected;
    try {
      return FirebaseFirestore.instance;
    } catch (e) {
      throw VeldCarryRepositoryException(
        'Firestore is not available — veld data cannot be read or written '
        '($e).',
      );
    }
  }

  String _requireOutfitterUid(String outfitterUid) {
    final trimmed = outfitterUid.trim();
    if (trimmed.isEmpty) {
      throw const VeldCarryRepositoryException('Outfitter uid is required.');
    }
    return trimmed;
  }

  String _requireFarmId(String farmId) {
    final trimmed = farmId.trim();
    if (trimmed.isEmpty) {
      throw const VeldCarryRepositoryException('Farm id is required.');
    }
    return trimmed;
  }

  ({String farmId, String campId}) _requireCampIds({
    required String farmId,
    required String campId,
  }) {
    final farm = _requireFarmId(farmId);
    final camp = campId.trim();
    if (camp.isEmpty) {
      throw const VeldCarryRepositoryException('Camp id is required.');
    }
    return (farmId: farm, campId: camp);
  }
}

/// One species a hunter can hunt on a farm, with the camps it was counted on.
///
/// The hunter-facing shape is deliberately narrow: name, scientific name, total
/// count and camp names. It never carries a weight, a GU/BU split, a camp size,
/// a capacity figure or a coordinate — those stay on the outfitter side.
class SpeciesAvailability {
  const SpeciesAvailability({
    required this.speciesName,
    required this.scientificName,
    required this.totalCount,
    required this.campNames,
  });

  /// Display name (`Chacma Baboon` -> `Baboon`, otherwise the canonical name).
  final String speciesName;

  /// Binomial / trinomial name, or `''` when not recorded.
  final String scientificName;

  /// Total head counted across every camp on the farm.
  final int totalCount;

  /// Camps the species was counted on, alphabetical.
  final List<String> campNames;

  /// `Available on: North Camp, South Camp`.
  String get availableOnLabel => campNames.isEmpty
      ? 'Available on: —'
      : 'Available on: ${campNames.join(', ')}';
}

/// Thrown when a caller is not the outfitter that owns the veld data.
class VeldCarryOwnershipException implements Exception {
  const VeldCarryOwnershipException(this.message);

  final String message;

  @override
  String toString() => 'VeldCarryOwnershipException: $message';
}

/// Thrown when a veld operation is rejected before reaching Firestore
/// (missing id, missing farm id, Firestore unavailable).
class VeldCarryRepositoryException implements Exception {
  const VeldCarryRepositoryException(this.message);

  final String message;

  @override
  String toString() => 'VeldCarryRepositoryException: $message';
}

/// Outcome of [VeldCarryRepository.syncAllowedHuntersForFarm].
///
/// Reported to the outfitter so a manual sync is never a silent no-op: they see
/// how many hunters are on the list, how many camps exist and how many camps
/// were actually rewritten.
class VeldHunterAccessSyncResult {
  const VeldHunterAccessSyncResult({
    required this.farmId,
    required this.hunterUids,
    required this.campCount,
    required this.campsTouched,
  });

  final String farmId;

  /// Hunters granted access by the sync (confirmed / completed bookings).
  final List<String> hunterUids;

  /// Camps on the farm.
  final int campCount;

  /// Camps whose allow-list was written by this run (0 = already in sync).
  final int campsTouched;

  bool get hasHunters => hunterUids.isNotEmpty;

  /// `3 hunters · 4 camps (2 updated)`.
  String get summary {
    final hunters = hunterUids.isEmpty
        ? 'no confirmed hunters'
        : '${hunterUids.length} hunter${hunterUids.length == 1 ? '' : 's'}';
    return '$hunters · $campCount camp${campCount == 1 ? '' : 's'} '
        '($campsTouched updated)';
  }

  @override
  String toString() =>
      'VeldHunterAccessSyncResult($farmId, ${hunterUids.length} hunters, '
      '$campsTouched/$campCount camps)';
}
