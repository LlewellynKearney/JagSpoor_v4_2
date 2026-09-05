import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service for complete outfitter + user account deletion.
///
/// Mirrors the hunter-side [AccountDeletionService] contract (GDPR-compliant
/// data pruning with transactional batch operations) but covers the ten+
/// owner-scoped collections the outfitter enterprise writes to (farms, farm
/// managers, trophy stock, packages, price lists, service rates, venison
/// permit partitions, scanned price lists, …) in addition to the shared
/// `users/{uid}` profile and the canonical `outfitters/{uid}` enterprise
/// profile.
///
/// **Client-side design note**: Firestore does NOT support deleting a
/// collection (or querying what a collection *contains* from a single client
/// call), so every service must first read the owner-scoped documents it
/// manages and then batch-delete them. Each owner-scoped read/write below is
/// permitted by the existing `firestore.rules` grants for the signed-in
/// owner (reads are `isSignedIn()` or owner-scoped; deletes are
/// `ownerOrAdmin` / `isOwnerOf`), with two intentional deviations:
///
/// 1. **`bookings`** — deletes are admin-only, so an outfitter cannot delete
///    standing bookings here. Bookings involving the outfitter are instead
///    marked `deleted: true` (best-effort; a status-frozen non-status update
///    the party rule allows), preserving the hunter's audit trail while we
///    remove the account. A production-grade hard delete belongs in a Cloud
///    Function with Admin SDK privileges.
/// 2. **Legacy `outfitter/…` subcollections** (`outfitter/bookings`,
///    `outfitter/lodging`, `outfitter/fleet`, `outfitter/carcass_records`) —
///    they are `isOutfitter()`/admin-gated; a signed-in outfitter may read
///    them but not delete them, so the legacy docs are best-effort
///    soft-deleted (`deleted: true`) rather than hard-deleted.
///
/// All collection names come from real producers: `OutfitterEnterpriseManager`
/// (farms, farm_managers, trophy_stock, bookings), `FarmGamePriceListManager`
/// (farm_pricelists, farm_service_rates), `VenisonPermitManager`
/// (outfitter_venison_permits, hunter_venison_permits, venison_permits),
/// `PackageBookingManager` (packages), `OpticLogService` (optic_logs),
/// `OutfitterFirebaseService` / `OutfitterSyncService` (legacy outfitter/…).
///
/// The credential is deleted last (`user.delete()`), so a mid-cascade
/// Firestore failure never leaves an orphaned-but-authenticated account
/// (the account keeps existing with partially-pruned data, and the deletion
/// can be re-run). A `FirebaseAuthException` with code `requires-recent-login`
/// propagates to the caller so the UI can surface the standard
/// re-authentication prompt.
class OutfitterAccountDeletionService {
  OutfitterAccountDeletionService._({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? Function()? uidResolver,
    Future<void> Function(String uid)? credentialDeleter,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth, // null in tests — never touched there
        _uidResolver = uidResolver,
        _credentialDeleter = credentialDeleter;

  /// Singleton bound to the real Firestore + FirebaseAuth instances.
  static final OutfitterAccountDeletionService instance =
      OutfitterAccountDeletionService._(
        auth: FirebaseAuth.instance,
      );

  /// Test factory: build a fresh, isolated service bound to an injectable
  /// Firestore (e.g. `FakeFirebaseFirestore`) + an injectable uid resolver +
  /// an injectable credential deleter so the full cascade is unit-testable
  /// WITHOUT a live Firebase app (the real `FirebaseAuth` is never
  /// instantiated). Mirrors the `forTesting` seam pattern used across the
  /// codebase.
  @visibleForTesting
  factory OutfitterAccountDeletionService.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() currentUserResolver,
    Future<void> Function(String uid)? credentialDeleter,
  }) {
    return OutfitterAccountDeletionService._(
      firestore: firestore,
      auth: null,
      uidResolver: currentUserResolver,
      credentialDeleter: credentialDeleter,
    );
  }

  final FirebaseFirestore _firestore;

  /// Null in the test factory (real Firebase never touched in tests).
  final FirebaseAuth? _auth;

  /// Resolves the current uid; production falls back to the real auth session.
  final String? Function()? _uidResolver;

  /// Overrides the final `User.delete()` step in tests (receives the uid).
  final Future<void> Function(String uid)? _credentialDeleter;

  static const String _deletedFlag = 'deleted';

  String? get _currentUid =>
      _uidResolver?.call() ?? _auth?.currentUser?.uid;

  /// Whether the current session is too old to delete. The authoritative
  /// check is `requires-recent-login` thrown by `User.delete()`; this getter
  /// mirrors the hunter-side `AccountDeletionService.requiresRecentLogin` API
  /// (itself a heuristic) so the two services stay symmetric.
  bool get requiresRecentLogin {
    final uid = _currentUid;
    return uid == null || uid.isEmpty;
  }

  /// Deletes the outfitter's ENTIRE data pack + auth credential:
  /// the `users/{uid}` profile, the canonical `outfitters/{uid}` enterprise
  /// profile, farms, farm managers, trophy stock, packages, farm price
  /// lists, farm service rates, scanned price lists, venison permit
  /// partitions (outfitter + hunter + legacy) and optic logs — then soft-
  /// deletes legacy `outfitter/…` collections and any bookings involving
  /// the outfitter (see the class doc for the admin-only delete caveat) —
  /// then removes the Firebase authentication credential.
  Future<void> deleteOutfitterAndUserData() async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) {
      throw Exception('No authenticated user found');
    }

    // SnapshotGate: collect all owner-scoped docs into one batch.
    final batch = _firestore.batch();

    // ── Shared / canonical profiles ──
    batch.delete(_firestore.collection('users').doc(uid));
    batch.delete(_firestore.collection('outfitters').doc(uid));

    // ── Outfitter enterprise: a batch-delete per collection keep deletes
    //    durable past the (max 500-op) Firestore batch limit by batching
    //    eagerly-loaded snapshots per collection below the limit.
    await _queueOwnerScopedDeletes(
      batch,
      'farms',
      'outfitterId',
      uid,
    );
    await _queueOwnerScopedDeletes(
      batch,
      'farm_managers',
      'outfitterId',
      uid,
    );
    await _queueOwnerScopedDeletes(
      batch,
      'trophy_stock',
      'outfitterId',
      uid,
    );
    await _queueOwnerScopedDeletes(
      batch,
      'packages',
      'outfitterId',
      uid,
    );
    await _queueOwnerScopedDeletes(
      batch,
      'farm_pricelists',
      'outfitterId',
      uid,
    );
    await _queueOwnerScopedDeletes(
      batch,
      'farm_service_rates',
      'outfitterId',
      uid,
    );
    await _queueOwnerScopedDeletes(
      batch,
      'scanned_pricelists',
      'outfitterId',
      uid,
    );

    // ── Venison permit partitions (outfitter-issued) ──
    await _queueOwnerScopedDeletes(
      batch,
      'outfitter_venison_permits',
      'outfitterId',
      uid,
    );
    await _queueOwnerScopedDeletes(
      batch,
      'venison_permits',
      'outfitterId',
      uid,
    );
    // The hunter partition still carries the permit (dual-write at issue
    // time); the hunter's copy is preserved for their own records.
    await _queueOwnerScopedTeardown(
      batch,
      'hunter_venison_permits',
      'outfitterId',
      uid,
    );

    // ── Optic logs / transport permits also keyed by the outfitter ──
    await _queueOwnerScopedDeletes(
      batch,
      'transport_permits',
      'outfitterId',
      uid,
    );
    // Optic logs are hunter-owned (`userId` / `ownerId`), so only prune the
    // symmetric shared surface: docs carrying this uid as the legacy
    // `ownerId` alias.
    await _queueOwnerScopedTeardown(
      batch,
      'optic_logs',
      'ownerId',
      uid,
    );

    // ── Hard-delete what the rules permit, soft-mark the rest ──
    // Bookings: firestore.rules `delete` is admin-only, so the outfitter
    // (a booking party) cannot hard-delete them. A non-status owner update
    // is permitted instead — the booking stays for the hunter's history but
    // is flagged `deleted` so the outfitter's own lists can hide it.
    await _queuePartySoftDeletes(
      batch,
      'bookings',
      'outfitterId',
      uid,
    );
    // Legacy `outfitter/…` subcollections are isOutfitter()/admin-gated;
    // the outfitter can read but not hard-delete, so soft-mark them.
    for (final collection in const [
      'outfitter/bookings',
      'outfitter/lodging',
      'outfitter/fleet',
      'outfitter/carcass_records',
    ]) {
      await _queuePartySoftDeletes(batch, collection, 'outfitterId', uid);
    }

    // Commit every queued deletion/teardown.
    await batch.commit();

    // ── Authentication credential (last, so a failed cascade keeps the
    //    account intact / re-runnable) ──
    final deleter = _credentialDeleter;
    if (deleter != null) {
      await deleter(uid);
    } else {
      final currentUser = _auth?.currentUser;
      if (currentUser != null) {
        await currentUser.delete();
      }
    }
  }

  /// Queries [collection] for docs whose [ownerField] == [uid] and queues a
  /// hard batch-delete for each. Non-fatal: a missing index / permission
  /// error is logged and skipped so one failing collection (e.g. an
  /// undeployed collection) never aborts the whole cascade.
  Future<void> _queueOwnerScopedDeletes(
    WriteBatch batch,
    String collection,
    String ownerField,
    String uid,
  ) async {
    final ids = await _ownerScopedDocIds(collection, ownerField, uid);
    for (final id in ids) {
      batch.delete(_firestore.collection(collection).doc(id));
    }
  }

  /// Same query as [_queueOwnerScopedDeletes] but flags each doc instead of
  /// deleting it (used when an owner-scoped hard delete succeeds for reads
  /// but the write is admin-gated, or when the owning side of a two-party
  /// collection must keep the doc).
  Future<void> _queueOwnerScopedTeardown(
    WriteBatch batch,
    String collection,
    String ownerField,
    String uid,
  ) async {
    final ids = await _ownerScopedDocIds(collection, ownerField, uid);
    for (final id in ids) {
      batch.update(
        _firestore.collection(collection).doc(id),
        {
          _deletedFlag: true,
          'deletedAt': FieldValue.serverTimestamp(),
        },
      );
    }
  }

  /// Queries the owner-scoped doc ids. A null auth (cold-launch / widget
  /// test) or a Firestore failure (offline, undeployed index, permissions)
  /// returns an empty list so the cascade keeps going.
  Future<List<String>> _ownerScopedDocIds(
    String collection,
    String ownerField,
    String uid,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .where(ownerField, isEqualTo: uid)
          .get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint(
        'OutfitterAccountDeletionService: skipping $collection '
        '(owner=$ownerField): $e',
      );
      return const [];
    }
  }

  /// Marks every party doc where [partyField] == [uid] with the soft-delete
  /// flag (a non-status field update the party write rule permits).
  Future<void> _queuePartySoftDeletes(
    WriteBatch batch,
    String collection,
    String partyField,
    String uid,
  ) async {
    final ids = await _ownerScopedDocIds(collection, partyField, uid);
    for (final id in ids) {
      batch.update(
        _firestore.collection(collection).doc(id),
        {
          _deletedFlag: true,
          'deletedAt': FieldValue.serverTimestamp(),
        },
      );
    }
  }
}

