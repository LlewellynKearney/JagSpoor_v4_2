import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
// `foundation` also re-exports `Uint8List` (dart:typed_data).
import 'package:flutter/foundation.dart';
import '../../../core/services/offline_stream_guard.dart';
import '../models/venison_transport_permit.dart';

/// VenisonPermitManager — central engine for the legal South African Venison /
/// Game Transport & Hunt Permit.
///
/// Owns the full issue lifecycle across the TWO role-partitioned Firestore
/// collections (the shared `venison_permits` collection was split so each
/// role queries its own partition without permission conflicts):
/// 1. Write the permit document to `outfitter_venison_permits` (partitioned
///    by `outfitterId`) AND — when the hunter's uid is known — to
///    `hunter_venison_permits` (partitioned by `hunterId`), under the SAME
///    document id so both partitions stay in lock-step.
/// 2. Upload both signature PNGs to Firebase Storage under
///    `permit_signatures/{permitId}/hunter_signature.png` and
///    `permit_signatures/{permitId}/outfitter_signature.png`.
/// 3. Patch both partition documents with the real download URLs + signed
///    timestamps.
///
/// Both Hunters and Outfitters may issue permits; read access is governed by
/// the Firestore rules (the outfitter partition by `outfitterId`, the hunter
/// partition by `hunterId` / its `userId` alias).
class VenisonPermitManager {
  /// Outfitter-partitioned venison permits (filtered by `outfitterId`).
  static const String outfitterCollection = 'outfitter_venison_permits';

  /// Hunter-partitioned venison permits (filtered by `hunterId`).
  static const String hunterCollection = 'hunter_venison_permits';

  /// Legacy pre-partition shared collection. No longer written; read as a
  /// fallback by [getPermitById] so permits issued by older app versions
  /// remain exportable.
  static const String legacyCollection = 'venison_permits';

  VenisonPermitManager._({this.firestoreForTesting, this.currentUserIdResolverForTesting});

  static final VenisonPermitManager _instance = VenisonPermitManager._();
  static VenisonPermitManager get instance => _instance;

  /// Test seam: inject a Firestore instance (e.g. `FakeFirebaseFirestore`) so
  /// the query/write contract can be unit-tested without a live Firebase app.
  /// Lazy so constructing the service before `Firebase.initializeApp()` never
  /// throws `[core/no-app]`. Mirrors the `OpticLogService` test pattern.
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  FirebaseFirestore get _firestore =>
      firestoreForTesting ?? FirebaseFirestore.instance;

  /// Test seam: inject a uid resolver so the null-uid -> empty-stream branch
  /// and the dual-alias hunter query contract can be unit-tested without a
  /// real signed-in user. A wrapped `[core/no-app]` (cold-launch race / widget
  /// test) resolves to null instead of throwing.
  @visibleForTesting
  String? Function()? currentUserIdResolverForTesting;

  String? get _currentUserId {
    if (currentUserIdResolverForTesting != null) {
      return currentUserIdResolverForTesting!();
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  // Storage is resolved lazily so a test / cold-launch construction never
  // touches FirebaseStorage before the app (or test harness) is initialized.
  FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Test-only constructor: build a fresh, isolated manager (not the
  /// process-wide singleton) bound to an injectable Firestore + uid resolver.
  @visibleForTesting
  factory VenisonPermitManager.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() currentUserIdResolver,
  }) {
    return VenisonPermitManager._(
      firestoreForTesting: firestore,
      currentUserIdResolverForTesting: currentUserIdResolver,
    );
  }

  /// Resolves the uid of the hunter the permit is issued to.
  ///
  /// Priority: (1) an explicit `permitHunterId` (carried on the model when the
  /// permit was opened from a booking); (2) when the issuing user is NOT the
  /// outfitter (i.e. the hunter self-issues their own permit), the issuer's
  /// own uid; (3) `null` -- an outfitter issuing a permit without a booking
  /// context has no uid to stamp until the hunter countersigns.
  ///
  /// Pure / unit-testable; no I/O.
  static String? resolveHunterUid({
    String? permitHunterId,
    required String issuerUid,
    required String outfitterId,
  }) {
    final explicit = permitHunterId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (issuerUid.isNotEmpty && issuerUid != outfitterId) return issuerUid;
    return null;
  }

  /// Issues a new venison transport permit. Both signature PNGs are optional —
  /// a permit can be saved unsigned and countersigned later, but a fully legal
  /// permit requires both signatures.
  ///
  /// Returns the new permit document ID.
  Future<String> issueVenisonPermit({
    required VenisonTransportPermit permit,
    Uint8List? hunterSignatureBytes,
    Uint8List? outfitterSignatureBytes,
  }) async {
    final issuerUid = _currentUserId;
    if (issuerUid == null) {
      throw Exception('User must be authenticated to issue a permit');
    }

    // Resolve + dual-stamp the hunter's uid under BOTH `hunterId` and
    // `userId` so the hunter's permit list (and the Firestore read rules)
    // match the permit regardless of which alias a consumer queries. The
    // resolution uses `effectiveHunterId` so a model carrying ONLY the
    // `userId` alias also stamps correctly. Without this, permits issued
    // without a booking context carried no hunter uid at all and were
    // invisible to the hunter.
    final effectiveHunterUid = resolveHunterUid(
      permitHunterId: permit.effectiveHunterId,
      issuerUid: issuerUid,
      outfitterId: permit.outfitterId,
    );

    // 1. Reserve a stable permitId, then write the SAME permit document id
    //    into the outfitter partition (always) and the hunter partition (when
    //    the designated hunter's uid is known). Both partitions carry the
    //    full field set + both party ids, so each role's own stream (and the
    //    role-partitioned Firestore rules) match without permission
    //    conflicts.
    final baseData = {
      ...permit.toMap(),
      'outfitterId': permit.outfitterId,
      if (effectiveHunterUid != null) ...{
        'hunterId': effectiveHunterUid,
        'userId': effectiveHunterUid,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final permitId =
        _firestore.collection(outfitterCollection).doc().id;
    final outfitterRef =
        _firestore.collection(outfitterCollection).doc(permitId);
    await outfitterRef.set(baseData);
    if (effectiveHunterUid != null) {
      await _firestore
          .collection(hunterCollection)
          .doc(permitId)
          .set(baseData);
    }

    String? hunterSignatureUrl;
    String? outfitterSignatureUrl;

    // 2. Upload signatures (if provided) to permit_signatures/{permitId}/.
    if (hunterSignatureBytes != null) {
      hunterSignatureUrl = await _uploadSignature(
        permitId: permitId,
        role: 'hunter',
        bytes: hunterSignatureBytes,
      );
    }
    if (outfitterSignatureBytes != null) {
      outfitterSignatureUrl = await _uploadSignature(
        permitId: permitId,
        role: 'outfitter',
        bytes: outfitterSignatureBytes,
      );
    }

    // 3. Patch every partition copy with signature URLs + signed timestamps.
    final patch = {
      if (hunterSignatureUrl != null) 'hunterSignatureUrl': hunterSignatureUrl,
      if (outfitterSignatureUrl != null)
        'outfitterSignatureUrl': outfitterSignatureUrl,
      if (hunterSignatureBytes != null)
        'hunterSignedDate': FieldValue.serverTimestamp(),
      if (outfitterSignatureBytes != null)
        'outfitterSignedDate': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.batch();
    batch.update(outfitterRef, patch);
    if (effectiveHunterUid != null) {
      batch.update(
        _firestore.collection(hunterCollection).doc(permitId),
        patch,
      );
    }
    await batch.commit();

    return permitId;
  }

  /// Uploads a single signature PNG and returns its download URL.
  Future<String> _uploadSignature({
    required String permitId,
    required String role,
    required Uint8List bytes,
  }) async {
    final ref = _storage.ref().child(
      'permit_signatures/$permitId/${role}_signature.png',
    );
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/png'),
    );
    return task.ref.getDownloadURL();
  }

  /// Generates a unique permit number in the JagSpoor venison-permit format.
  String generatePermitNumber() {
    final now = DateTime.now();
    final year = now.year.toString();
    final random = now.millisecondsSinceEpoch.toString().substring(6);
    return 'JSV-$year-$random';
  }

  /// Reactive stream of permits for the authenticated user, served from the
  /// caller's role-partitioned collection:
  /// - Outfitters read `outfitter_venison_permits` filtered by `outfitterId`;
  /// - Hunters read `hunter_venison_permits` filtered by the canonical
  ///   `hunterId` OR its `userId` alias (both are dual-stamped at issue
  ///   time), so permits written by any app version still render for the
  ///   designated hunter.
  ///
  /// The query intentionally does NOT use `.orderBy('createdAt')` server-side:
  /// an equality/OR + orderBy combo requires a composite index; sorting
  /// client-side after the single-field-equality read avoids the missing-index
  /// error entirely (the established project pattern). The stream is wrapped
  /// in [OfflineStreamGuard.offlineResilient] so a hard error emits the
  /// fallback instead of hanging the consuming StreamBuilder.
  Stream<List<VenisonTransportPermit>> getMyPermitsStream({
    required bool isOutfitter,
  }) {
    final uid = _currentUserId;
    if (uid == null) return Stream.value(const <VenisonTransportPermit>[]);

    final query = isOutfitter
        ? _firestore
            .collection(outfitterCollection)
            .where('outfitterId', isEqualTo: uid)
        : _firestore.collection(hunterCollection).where(
              Filter.or(
                Filter('hunterId', isEqualTo: uid),
                Filter('userId', isEqualTo: uid),
              ),
            );

    return OfflineStreamGuard.offlineResilient(
      query.snapshots().map(_snapshotToPermits),
      fallback: const <VenisonTransportPermit>[],
      debugLabel: isOutfitter ? outfitterCollection : hunterCollection,
    );
  }

  /// Maps a snapshot to the permit list: de-duplicated by document id (so a
  /// permit stamped with BOTH aliases, which satisfies both OR branches,
  /// renders once) and sorted newest-first client-side.
  static List<VenisonTransportPermit> _snapshotToPermits(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final byId = <String, VenisonTransportPermit>{};
    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      byId[doc.id] = VenisonTransportPermit.fromMap(data);
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final permits = byId.values.toList()
      ..sort(
        (a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch),
      );
    return permits;
  }

  /// Fetch a single permit by ID. Reads cache-first so an offline lookup
  /// still resolves a recently-viewed permit, falling back to the server.
  /// Searches the outfitter partition first, then the hunter partition, then
  /// the legacy shared collection (permits issued by older app versions).
  Future<VenisonTransportPermit?> getPermitById(String permitId) async {
    for (final collection in const [
      outfitterCollection,
      hunterCollection,
      legacyCollection,
    ]) {
      final docRef = _firestore.collection(collection).doc(permitId);
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await docRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        doc = await docRef.get();
      }
      if (!doc.exists) continue;
      final data = Map<String, dynamic>.from(doc.data()!);
      data['id'] = doc.id;
      return VenisonTransportPermit.fromMap(data);
    }
    return null;
  }

  /// Update permit status (e.g. 'Issued' → 'Voided' / 'Completed') in EVERY
  /// partition that carries the document, so both roles' views stay in sync.
  Future<void> updatePermitStatus({
    required String permitId,
    required String newStatus,
  }) async {
    final patch = {
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.batch();
    var matched = 0;
    for (final collection in const [
      outfitterCollection,
      hunterCollection,
      legacyCollection,
    ]) {
      final ref = _firestore.collection(collection).doc(permitId);
      final doc = await ref.get();
      if (!doc.exists) continue;
      batch.update(ref, patch);
      matched++;
    }
    if (matched == 0) {
      throw Exception('Permit $permitId not found');
    }
    await batch.commit();
  }

  /// Delete a permit from EVERY partition (and its stored signatures).
  Future<void> deletePermit(String permitId) async {
    // Best-effort cleanup of signature storage.
    try {
      final folder = _storage.ref().child('permit_signatures/$permitId');
      final items = await folder.listAll();
      for (final item in items.items) {
        await item.delete();
      }
    } catch (_) {
      // Non-fatal — the Firestore doc is the source of truth.
    }
    final batch = _firestore.batch();
    var matched = 0;
    for (final collection in const [
      outfitterCollection,
      hunterCollection,
      legacyCollection,
    ]) {
      final ref = _firestore.collection(collection).doc(permitId);
      final doc = await ref.get();
      if (!doc.exists) continue;
      batch.delete(ref);
      matched++;
    }
    if (matched > 0) await batch.commit();
  }

  /// Pre-fills permit fields from a booking + the linked user/outfitter docs.
  ///
  /// Returns a partial map of field hints that the form can apply. Used when a
  /// permit is opened in the context of an active booking.
  Future<Map<String, dynamic>> prefillFromBooking(String bookingId) async {
    final result = <String, dynamic>{};

    final bookingDoc =
        await _firestore.collection('bookings').doc(bookingId).get();
    if (!bookingDoc.exists) return result;
    final booking = bookingDoc.data()!;

    final outfitterId = booking['outfitterId'] as String?;
    final hunterId = booking['hunterId'] as String?;
    final packageName = booking['packageName'] as String?;

    result
      ..['bookingId'] = bookingId
      ..['outfitterId'] = outfitterId ?? ''
      ..['hunterId'] = hunterId ?? '';

    // Outfitter / farm details.
    if (outfitterId != null) {
      final outfitterDoc =
          await _firestore.collection('outfitters').doc(outfitterId).get();
      if (outfitterDoc.exists) {
        final o = outfitterDoc.data()!;
        result['authorizedPersonName'] = o['contactName'] ?? o['name'] ?? '';
        result['farmName'] = o['farmName'] ?? o['businessName'] ?? '';
        result['farmAddress'] = o['address'] ?? o['farmAddress'] ?? '';
        result['farmCell'] = o['cellNumber'] ?? o['phone'] ?? '';
      }
    }

    // Hunter details.
    if (hunterId != null) {
      final userDoc = await _firestore.collection('users').doc(hunterId).get();
      if (userDoc.exists) {
        final u = userDoc.data()!;
        result['hunterName'] = u['fullName'] ?? u['name'] ?? '';
        result['hunterCell'] = u['phoneNumber'] ?? u['cellNumber'] ?? '';
        result['hunterAddress'] = u['address'] ?? '';
        result['hunterIdNumber'] = u['idNumber'] ?? '';
      }
    }

    if (packageName != null) result['packageName'] = packageName;
    return result;
  }
}
