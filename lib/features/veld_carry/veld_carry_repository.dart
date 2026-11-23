import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'models/camp.dart';
import 'models/farm_permit.dart';
import 'models/planted_area.dart';
import 'models/predator_entry.dart';
import 'models/stock_entry.dart';

/// Firestore repository for the Veld & Carrying Capacity feature.
///
/// **Phase 0D — STUB ONLY.** Every method below validates ownership and then
/// returns an empty result. No Firestore read or write is performed yet and
/// no UI calls into this class: the feature stays dark behind
/// [VeldCarryFeatureFlag], which is OFF unless both the compile-time and the
/// control-plane switches are true.
///
/// Ownership contract — enforced here *and* in
/// `firestore.rules.veld_carry.DRAFT`: the caller must be the farm's
/// outfitter. Every method compares [outfitterUid] against the signed-in uid
/// and throws [VeldCarryOwnershipException] when they differ, so a caller can
/// never read or write another outfitter's veld data. The draft rules
/// re-check the same invariant server-side against
/// `farms/{farmId}.outfitterId`, which is why the client check is a guard and
/// not the security boundary.
class VeldCarryRepository {
  VeldCarryRepository._({String? Function()? currentUserIdResolver})
      : _injectedCurrentUserIdResolver = currentUserIdResolver;

  /// Process-wide instance. The lazy getters below keep construction safe
  /// before `Firebase.initializeApp()` (cold launch / widget tests), matching
  /// the other repositories in this app.
  static final VeldCarryRepository instance = VeldCarryRepository._();

  /// Camps live under the farm they belong to.
  static const String campsCollection = 'camps';

  /// Camp children — stock ledger, planted areas and predator records.
  static const String stockCollection = 'stock';
  static const String plantedAreasCollection = 'plantedAreas';
  static const String predatorsCollection = 'predators';

  /// Permits live under the farm (they are farm-wide, not camp-specific).
  static const String permitsCollection = 'permits';

  final String? Function()? _injectedCurrentUserIdResolver;

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

  /// Test seam: inject the uid resolver so the ownership guard can be
  /// exercised without a Firebase app.
  @visibleForTesting
  static VeldCarryRepository forTesting({
    String? Function()? currentUserIdResolver,
  }) =>
      VeldCarryRepository._(currentUserIdResolver: currentUserIdResolver);

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

  /// Saves a camp. STUB — ownership-checked, then a no-op.
  Future<void> saveCamp(String outfitterUid, Camp camp) async {
    requireOwnership(outfitterUid);
    // TODO(veld-carry): Phase 1 — upsert
    // farms/{camp.farmId}/camps/{camp.id} with camp.toMap().
  }

  /// Lists the camps of a farm. STUB — returns an empty list.
  Future<List<Camp>> getCamps(String outfitterUid, String farmId) async {
    requireOwnership(outfitterUid);
    // TODO(veld-carry): Phase 1 — read farms/{farmId}/camps ordered by name.
    return const <Camp>[];
  }

  /// Saves one species row of a camp's stock ledger. STUB.
  Future<void> saveStockEntry(
    String outfitterUid,
    String farmId,
    String campId,
    StockEntry entry,
  ) async {
    requireOwnership(outfitterUid);
    // TODO(veld-carry): Phase 1 — upsert
    // farms/{farmId}/camps/{campId}/stock/{entry.id} with entry.toMap().
  }

  /// Saves one planted area of a camp. STUB.
  Future<void> savePlantedArea(
    String outfitterUid,
    String farmId,
    String campId,
    PlantedArea area,
  ) async {
    requireOwnership(outfitterUid);
    // TODO(veld-carry): Phase 1 — upsert
    // farms/{farmId}/camps/{campId}/plantedAreas/{area.id} with area.toMap().
  }

  /// Saves one predator record of a camp. STUB.
  Future<void> savePredatorEntry(
    String outfitterUid,
    String farmId,
    String campId,
    PredatorEntry entry,
  ) async {
    requireOwnership(outfitterUid);
    // TODO(veld-carry): Phase 1 — upsert
    // farms/{farmId}/camps/{campId}/predators/{entry.id} with entry.toMap().
  }

  /// Saves a farm-wide permit. STUB.
  Future<void> savePermit(
    String outfitterUid,
    String farmId,
    FarmPermit permit,
  ) async {
    requireOwnership(outfitterUid);
    // TODO(veld-carry): Phase 1 — upsert
    // farms/{farmId}/permits/{permit.id} with permit.toMap().
  }

  /// Lists the permits of a farm. STUB — returns an empty list.
  Future<List<FarmPermit>> getPermits(
    String outfitterUid,
    String farmId,
  ) async {
    requireOwnership(outfitterUid);
    // TODO(veld-carry): Phase 1 — read farms/{farmId}/permits. The draft rules
    // additionally expose a permit to a hunter only when
    // `visibility == 'hunter_visible'`; the hunter booking check lands in
    // Phase 5.
    return const <FarmPermit>[];
  }
}

/// Thrown when a caller is not the outfitter that owns the veld data.
class VeldCarryOwnershipException implements Exception {
  const VeldCarryOwnershipException(this.message);

  final String message;

  @override
  String toString() => 'VeldCarryOwnershipException: $message';
}
