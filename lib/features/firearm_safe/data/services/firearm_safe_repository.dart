import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/firearm.dart';

/// Owner-scoped repository for the Digital Firearm Safe (`firearms` Firestore
/// collection), mirroring the storage pattern already used by
/// `InventoryBridge` and the safe's own add flow.
///
/// The SAPS approved-application import uses [existsBySerial] + [addFirearm]
/// so an approved licence adds its firearm exactly once (keyed on the serial
/// number) without duplicating a firearm the hunter already registered.
class FirearmSafeRepository {
  final FirebaseFirestore? _injectedFirestore;

  /// Test seam: overrides the signed-in uid resolution so the read/write
  /// paths can be unit-tested against `FakeFirebaseFirestore` without a live
  /// Firebase Auth app.
  @visibleForTesting
  String? Function()? currentUserIdResolverForTesting;

  FirearmSafeRepository({FirebaseFirestore? firestore})
      : _injectedFirestore = firestore;

  /// Lazily resolves Firestore so constructing the repository before
  /// `Firebase.initializeApp()` (cold-launch race / widget-test env) does not
  /// throw `[core/no-app]`.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  String? get _currentUserId {
    final override = currentUserIdResolverForTesting;
    if (override != null) return override();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Test factory backed by an injected [FirebaseFirestore].
  @visibleForTesting
  factory FirearmSafeRepository.forTesting(
    FirebaseFirestore firestore, {
    String? Function()? uidResolver,
  }) {
    final repo = FirearmSafeRepository(firestore: firestore)
      ..currentUserIdResolverForTesting = uidResolver;
    return repo;
  }

  /// Whether a firearm with [serial] already exists in the signed-in user's
  /// safe. Returns false for a blank serial or an unauthenticated caller.
  ///
  /// The comparison is exact (the serial is the natural key); a whitespace /
  /// case difference is normalised so `F004574` and `f004574` collide.
  Future<bool> existsBySerial(String serial) async {
    final key = serial.trim().toUpperCase();
    if (key.isEmpty) return false;
    final uid = _currentUserId;
    if (uid == null) return false;
    try {
      final snapshot = await _firestore
          .collection('firearms')
          .where('ownerId', isEqualTo: uid)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final candidate =
            (data['serial'] ?? data['serialNumber'] ?? '').toString();
        if (candidate.trim().toUpperCase() == key) return true;
      }
      return false;
    } catch (e) {
      debugPrint('FirearmSafeRepository: existsBySerial failed: $e');
      return false;
    }
  }

  /// Adds [firearm] to the signed-in user's safe, stamping `ownerId` +
  /// `createdAt`. Returns the new document id, or null on failure /
  /// unauthenticated caller.
  Future<String?> addFirearm(Firearm firearm) async {
    final uid = _currentUserId;
    if (uid == null) {
      debugPrint('FirearmSafeRepository: cannot add - not authenticated');
      return null;
    }
    try {
      final docRef = _firestore.collection('firearms').doc();
      await docRef.set({
        ...firearm.copyWith(id: docRef.id).toFirestore(),
        'ownerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('FirearmSafeRepository: added firearm ${firearm.serial}');
      return docRef.id;
    } catch (e) {
      debugPrint('FirearmSafeRepository: addFirearm failed: $e');
      return null;
    }
  }
}
