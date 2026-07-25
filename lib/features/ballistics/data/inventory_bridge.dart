import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'models/rifle_profile.dart';

/// Service layer that mimics data extraction hooks from a 
/// Digital Firearm Safe and Ammunition Manager.
/// Provides functions to dynamically feed user dropdown menus.
class InventoryBridge {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  InventoryBridge({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  /// Fetches all firearms from the user's collection.
  /// Returns an empty list if no firearms are found or on error.
  Future<List<RifleProfile>> fetchSafeFirearms() async {
    try {
      if (_currentUserId == null) {
        debugPrint('InventoryBridge: User not authenticated');
        return [];
      }

      final snapshot = await _firestore
          .collection('firearms')
          .where('ownerId', isEqualTo: _currentUserId)
          .orderBy('name')
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('InventoryBridge: No firearms found for user');
        return [];
      }

      final rifles = snapshot.docs
          .map((doc) => RifleProfile.fromFirestore(doc))
          .toList();

      debugPrint('InventoryBridge: Fetched ${rifles.length} firearms for user');
      return rifles;
    } catch (e) {
      debugPrint('InventoryBridge: Error fetching firearms: $e');
      return [];
    }
  }

  /// Fetches available ammunition for a specific rifle from the Ammunition sub-collection.
  /// Returns an empty list if no ammunition is found or on error.
  Future<List<AmmoProfile>> fetchAvailableAmmunition(String rifleId) async {
    try {
      if (rifleId.isEmpty) {
        debugPrint('InventoryBridge: Empty rifleId provided');
        return [];
      }

      // Fetch ammunition from the rifle's sub-collection
      final ammoSnapshot = await _firestore
          .collection('firearms')
          .doc(rifleId)
          .collection('ammunition')
          .where('remainingStockCount', isGreaterThan: 0)
          .orderBy('bulletWeightGrains')
          .get();

      if (ammoSnapshot.docs.isEmpty) {
        debugPrint('InventoryBridge: No ammunition found for rifle $rifleId');
        return [];
      }

      final ammoList = ammoSnapshot.docs.map((doc) {
        final data = doc.data();
        return AmmoProfile(
          id: doc.id,
          rifleId: rifleId,
          bulletWeightGrains: (data['bulletWeightGrains'] as num?)?.toInt() ?? 0,
          velocityMs: (data['velocityMs'] as num?)?.toDouble() ?? 0.0,
          ballisticCoefficient: (data['ballisticCoefficient'] as num?)?.toDouble() ?? 0.0,
          remainingStockCount: (data['remainingStockCount'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      debugPrint('InventoryBridge: Fetched ${ammoList.length} ammunition for rifle $rifleId');
      return ammoList;
    } catch (e) {
      debugPrint('InventoryBridge: Error fetching ammunition: $e');
      return [];
    }
  }

  /// Adds a new rifle to the user's firearm collection.
  Future<String?> addRifleToSafe(RifleProfile rifle) async {
    try {
      if (_currentUserId == null) {
        debugPrint('InventoryBridge: Cannot add rifle - user not authenticated');
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

      final docRef = _firestore
          .collection('firearms')
          .doc(ammo.rifleId)
          .collection('ammunition')
          .doc();
      final newAmmo = ammo.copyWith(id: docRef.id);
      await docRef.set(newAmmo.toFirestore());
      debugPrint('InventoryBridge: Added ammunition to rifle ${ammo.rifleId}');
      return docRef.id;
    } catch (e) {
      debugPrint('InventoryBridge: Error adding ammunition: $e');
      return null;
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
  Stream<List<AmmoProfile>> watchAvailableAmmunition(String rifleId) {
    return Stream.periodic(const Duration(milliseconds: 500))
        .asyncMap((_) => fetchAvailableAmmunition(rifleId));
  }
}
