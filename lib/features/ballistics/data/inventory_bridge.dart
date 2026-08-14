import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/optic_profile.dart';
import 'models/rifle_profile.dart';

/// Service layer that mimics data extraction hooks from a
/// Digital Firearm Safe and Ammunition Manager.
/// Provides functions to dynamically feed user dropdown menus.
class InventoryBridge {
  final FirebaseFirestore _firestore;

  InventoryBridge({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// Returns a fallback list of common caliber ammunition records
  /// for offline mode when Firestore queries fail (e.g., DEVELOPER_ERROR).
  List<AmmoProfile> _getFallbackLocalAmmunition() {
    return [
      AmmoProfile(
        id: 'fallback_308',
        rifleId: '',
        bulletWeightGrains: 175,
        velocityMs: 800.0,
        ballisticCoefficient: 0.496,
        remainingStockCount: 20,
      ),
      AmmoProfile(
        id: 'fallback_65creed',
        rifleId: '',
        bulletWeightGrains: 140,
        velocityMs: 835.0,
        ballisticCoefficient: 0.512,
        remainingStockCount: 20,
      ),
      AmmoProfile(
        id: 'fallback_3006',
        rifleId: '',
        bulletWeightGrains: 180,
        velocityMs: 825.0,
        ballisticCoefficient: 0.473,
        remainingStockCount: 20,
      ),
      AmmoProfile(
        id: 'fallback_223rem',
        rifleId: '',
        bulletWeightGrains: 55,
        velocityMs: 980.0,
        ballisticCoefficient: 0.242,
        remainingStockCount: 20,
      ),
      AmmoProfile(
        id: 'fallback_270win',
        rifleId: '',
        bulletWeightGrains: 150,
        velocityMs: 850.0,
        ballisticCoefficient: 0.447,
        remainingStockCount: 20,
      ),
    ];
  }

  /// Fetches all firearms from the user's collection.
  /// Returns an empty list if no firearms are found or on error.
  Future<List<RifleProfile>> fetchSafeFirearms() async {
    try {
      if (_currentUserId == null) {
        debugPrint('InventoryBridge: User not authenticated');
        return [];
      }

      final snapshot =
          await _firestore
              .collection('firearms')
              .where('ownerId', isEqualTo: _currentUserId)
              .orderBy('name')
              .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('InventoryBridge: No firearms found for user');
        return [];
      }

      final rifles =
          snapshot.docs.map((doc) => RifleProfile.fromFirestore(doc)).toList();

      debugPrint('InventoryBridge: Fetched ${rifles.length} firearms for user');
      return rifles;
    } on PlatformException catch (pe) {
      debugPrint('Caught Firebase Platform Exception: $pe');
      return [];
    } catch (e) {
      debugPrint('InventoryBridge: Error fetching firearms: $e');
      return [];
    }
  }

  /// Fetches available ammunition for a specific rifle from the Ammunition sub-collection.
  /// Returns fallback local ammunition on platform exceptions (e.g., DEVELOPER_ERROR).
  Future<List<AmmoProfile>> fetchAvailableAmmunition(String rifleId) async {
    try {
      if (rifleId.isEmpty) {
        debugPrint('InventoryBridge: Empty rifleId provided');
        return _getFallbackLocalAmmunition();
      }

      // Fetch ammunition from the rifle's sub-collection
      final ammoSnapshot =
          await _firestore
              .collection('firearms')
              .doc(rifleId)
              .collection('ammunition')
              .where('remainingStockCount', isGreaterThan: 0)
              .orderBy('bulletWeightGrains')
              .get();

      if (ammoSnapshot.docs.isEmpty) {
        debugPrint('InventoryBridge: No ammunition found for rifle $rifleId');
        return _getFallbackLocalAmmunition();
      }

      final ammoList =
          ammoSnapshot.docs.map((doc) {
            final data = doc.data();
            return AmmoProfile(
              id: doc.id,
              rifleId: rifleId,
              bulletWeightGrains:
                  (data['bulletWeightGrains'] as num?)?.toInt() ?? 0,
              velocityMs: (data['velocityMs'] as num?)?.toDouble() ?? 0.0,
              ballisticCoefficient:
                  (data['ballisticCoefficient'] as num?)?.toDouble() ?? 0.0,
              remainingStockCount:
                  (data['remainingStockCount'] as num?)?.toInt() ?? 0,
            );
          }).toList();

      debugPrint(
        'InventoryBridge: Fetched ${ammoList.length} ammunition for rifle $rifleId',
      );
      return ammoList;
    } on PlatformException catch (pe) {
      debugPrint(
        'InventoryBridge: Platform exception fetching ammunition: $pe',
      );
      return _getFallbackLocalAmmunition();
    } catch (e) {
      debugPrint('InventoryBridge: Error fetching ammunition: $e');
      return _getFallbackLocalAmmunition();
    }
  }

  /// Adds a new rifle to the user's firearm collection.
  Future<String?> addRifleToSafe(RifleProfile rifle) async {
    try {
      if (_currentUserId == null) {
        debugPrint(
          'InventoryBridge: Cannot add rifle - user not authenticated',
        );
        return null;
      }

      final docRef = _firestore.collection('firearms').doc();
      final newRifle = rifle.copyWith(id: docRef.id, ownerId: _currentUserId);
      await docRef.set(newRifle.toFirestore());
      debugPrint('InventoryBridge: Added rifle ${newRifle.name} to collection');
      return docRef.id;
    } catch (e) {
      debugPrint('InventoryBridge: Error adding rifle: $e');
      return null;
    }
  }

  /// Adds a new ammunition to the rifle's sub-collection.
  Future<String?> addAmmunition(AmmoProfile ammo) async {
    try {
      if (ammo.rifleId.isEmpty) {
        debugPrint('InventoryBridge: Cannot add ammunition - rifleId is empty');
        return null;
      }

      final docRef =
          _firestore
              .collection('firearms')
              .doc(ammo.rifleId)
              .collection('ammunition')
              .doc();
      final newAmmo = ammo.copyWith(id: docRef.id, ownerId: _currentUserId);
      await docRef.set(newAmmo.toFirestore());
      debugPrint('InventoryBridge: Added ammunition to rifle ${ammo.rifleId}');
      return docRef.id;
    } catch (e) {
      debugPrint('InventoryBridge: Error adding ammunition: $e');
      return null;
    }
  }

  /// Persists an [OpticProfile] against a firearm by writing it as a nested
  /// `optic` map on the firearm document. Allowed because firearm docs are
  /// owner-scoped (`ownerOrAdmin('ownerId')`) in the Firestore rules.
  ///
  /// The optic is stamped with [rifleId] as its `firearmId` before writing so
  /// the scope configuration is securely bound to the selected firearm and
  /// the linkage survives Firestore re-reads (the binding "travels" with the
  /// rifle). A blank [rifleId] is rejected up-front.
  Future<bool> saveOpticProfile(String rifleId, OpticProfile optic) async {
    try {
      if (_currentUserId == null) {
        debugPrint('InventoryBridge: Cannot save optic - user not authenticated');
        return false;
      }
      if (rifleId.isEmpty) {
        debugPrint('InventoryBridge: Cannot save optic - empty rifleId');
        return false;
      }
      final bound = optic.copyWith(firearmId: rifleId);
      await _firestore
          .collection('firearms')
          .doc(rifleId)
          .set({'optic': bound.toJson()}, SetOptions(merge: true));
      debugPrint('InventoryBridge: Saved optic for rifle $rifleId');
      return true;
    } catch (e) {
      debugPrint('InventoryBridge: Error saving optic: $e');
      return false;
    }
  }

  /// Stream of firearms for reactive UI updates.
  Stream<List<RifleProfile>> watchSafeFirearms() {
    if (_currentUserId == null) {
      return Stream.value(<RifleProfile>[]);
    }

    return _firestore
        .collection('firearms')
        .where('ownerId', isEqualTo: _currentUserId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => RifleProfile.fromFirestore(doc))
              .toList();
        })
        .handleError((error) {
          debugPrint('InventoryBridge: Error watching firearms: $error');
          return <RifleProfile>[];
        });
  }

  /// Stream of ammunition for a specific rifle from the sub-collection.
  /// Uses Firestore snapshots for real-time updates instead of polling.
  /// Returns fallback local ammunition on platform exceptions.
  Stream<List<AmmoProfile>> watchAvailableAmmunition(String rifleId) {
    if (rifleId.isEmpty) {
      return Stream.value(_getFallbackLocalAmmunition());
    }

    return _firestore
        .collection('firearms')
        .doc(rifleId)
        .collection('ammunition')
        .where('remainingStockCount', isGreaterThan: 0)
        .orderBy('bulletWeightGrains')
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            debugPrint(
              'InventoryBridge: No ammunition found for rifle $rifleId',
            );
            return _getFallbackLocalAmmunition();
          }

          final ammoList =
              snapshot.docs.map((doc) {
                final data = doc.data();
                return AmmoProfile(
                  id: doc.id,
                  rifleId: rifleId,
                  bulletWeightGrains:
                      (data['bulletWeightGrains'] as num?)?.toInt() ?? 0,
                  velocityMs: (data['velocityMs'] as num?)?.toDouble() ?? 0.0,
                  ballisticCoefficient:
                      (data['ballisticCoefficient'] as num?)?.toDouble() ?? 0.0,
                  remainingStockCount:
                      (data['remainingStockCount'] as num?)?.toInt() ?? 0,
                );
              }).toList();

          debugPrint(
            'InventoryBridge: Fetched ${ammoList.length} ammunition for rifle $rifleId',
          );
          return ammoList;
        })
        .handleError((error) {
          debugPrint(
            'InventoryBridge: Stream error watching ammunition: $error',
          );
          return _getFallbackLocalAmmunition();
        });
  }
}
