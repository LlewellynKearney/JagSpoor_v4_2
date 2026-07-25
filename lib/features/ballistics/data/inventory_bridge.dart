import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/rifle_profile.dart';

/// Service layer that mimics data extraction hooks from a 
/// Digital Firearm Safe and Ammunition Manager.
/// Provides functions to dynamically feed user dropdown menus.
class InventoryBridge {
  final FirebaseFirestore _firestore;

  InventoryBridge({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Fetches all firearms from the Digital Firearm Safe.
  /// Returns an empty list if no firearms are found or on error.
  Future<List<RifleProfile>> fetchSafeFirearms() async {
    try {
      final snapshot = await _firestore
          .collection('firearm_safe')
          .orderBy('name')
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('InventoryBridge: No firearms found in safe');
        return [];
      }

      final rifles = snapshot.docs
          .map((doc) => RifleProfile.fromFirestore(doc))
          .toList();

      debugPrint('InventoryBridge: Fetched ${rifles.length} firearms from safe');
      return rifles;
    } catch (e) {
      debugPrint('InventoryBridge: Error fetching firearms: $e');
      return [];
    }
  }

  /// Fetches available ammunition for a specific rifle from the Ammunition Manager.
  /// Filters ammunition by caliber matching the rifle's caliber.
  /// Returns an empty list if no ammunition is found or on error.
  Future<List<AmmoProfile>> fetchAvailableAmmunition(String rifleId) async {
    try {
      if (rifleId.isEmpty) {
        debugPrint('InventoryBridge: Empty rifleId provided');
        return [];
      }

      // First, get the rifle to determine its caliber
      final rifleDoc = await _firestore
          .collection('firearm_safe')
          .doc(rifleId)
          .get();

      if (!rifleDoc.exists || rifleDoc.data() == null) {
        debugPrint('InventoryBridge: Rifle not found: $rifleId');
        return [];
      }

      final caliber = rifleDoc.data()!['caliber'] as String? ?? '';
      
      if (caliber.isEmpty) {
        debugPrint('InventoryBridge: Rifle has no caliber defined');
        return [];
      }

      // Fetch ammunition matching the rifle's caliber
      final ammoSnapshot = await _firestore
          .collection('ammunition_inventory')
          .where('caliber', isEqualTo: caliber)
          .where('remainingStockCount', isGreaterThan: 0)
          .orderBy('remainingStockCount', descending: true)
          .get();

      if (ammoSnapshot.docs.isEmpty) {
        debugPrint('InventoryBridge: No ammunition found for caliber: $caliber');
        return [];
      }

      final ammoList = ammoSnapshot.docs.map((doc) {
        final data = doc.data();
        return AmmoProfile(
          id: doc.id,
          rifleId: rifleId,
          bulletWeightGrains: data['bulletWeightGrains'] as int? ?? 0,
          velocityMs: (data['velocityMs'] as num?)?.toDouble() ?? 0.0,
          ballisticCoefficient: (data['ballisticCoefficient'] as num?)?.toDouble() ?? 0.0,
          remainingStockCount: data['remainingStockCount'] as int? ?? 0,
        );
      }).toList();

      debugPrint('InventoryBridge: Fetched ${ammoList.length} ammunition for rifle $rifleId');
      return ammoList;
    } catch (e) {
      debugPrint('InventoryBridge: Error fetching ammunition: $e');
      return [];
    }
  }

  /// Fetches all ammunition inventory regardless of rifle.
  /// Useful for ammunition dropdown when no rifle is selected.
  Future<List<AmmoProfile>> fetchAllAmmunition() async {
    try {
      final snapshot = await _firestore
          .collection('ammunition_inventory')
          .where('remainingStockCount', isGreaterThan: 0)
          .orderBy('caliber')
          .orderBy('bulletWeightGrains')
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('InventoryBridge: No ammunition found');
        return [];
      }

      final ammoList = snapshot.docs.map((doc) {
        final data = doc.data();
        return AmmoProfile(
          id: doc.id,
          rifleId: data['rifleId'] as String? ?? '',
          bulletWeightGrains: data['bulletWeightGrains'] as int? ?? 0,
          velocityMs: (data['velocityMs'] as num?)?.toDouble() ?? 0.0,
          ballisticCoefficient: (data['ballisticCoefficient'] as num?)?.toDouble() ?? 0.0,
          remainingStockCount: data['remainingStockCount'] as int? ?? 0,
        );
      }).toList();

      debugPrint('InventoryBridge: Fetched ${ammoList.length} total ammunition');
      return ammoList;
    } catch (e) {
      debugPrint('InventoryBridge: Error fetching all ammunition: $e');
      return [];
    }
  }

  /// Updates the stock count for a specific ammunition.
  Future<bool> updateAmmunitionStock(String ammoId, int newCount) async {
    try {
      await _firestore
          .collection('ammunition_inventory')
          .doc(ammoId)
          .update({'remainingStockCount': newCount});
      debugPrint('InventoryBridge: Updated stock for $ammoId to $newCount');
      return true;
    } catch (e) {
      debugPrint('InventoryBridge: Error updating stock: $e');
      return false;
    }
  }

  /// Adds a new rifle to the firearm safe.
  Future<String?> addRifleToSafe(RifleProfile rifle) async {
    try {
      final docRef = _firestore.collection('firearm_safe').doc();
      final newRifle = rifle.copyWith(id: docRef.id);
      await docRef.set(newRifle.toFirestore());
      debugPrint('InventoryBridge: Added rifle ${newRifle.name} to safe');
      return docRef.id;
    } catch (e) {
      debugPrint('InventoryBridge: Error adding rifle: $e');
      return null;
    }
  }

  /// Adds a new ammunition to the inventory.
  Future<String?> addAmmunition(AmmoProfile ammo) async {
    try {
      final docRef = _firestore.collection('ammunition_inventory').doc();
      final newAmmo = ammo.copyWith(id: docRef.id);
      await docRef.set(newAmmo.toFirestore());
      debugPrint('InventoryBridge: Added ammunition to inventory');
      return docRef.id;
    } catch (e) {
      debugPrint('InventoryBridge: Error adding ammunition: $e');
      return null;
    }
  }

  /// Stream of firearms for reactive UI updates.
  Stream<List<RifleProfile>> watchSafeFirearms() {
    return _firestore
        .collection('firearm_safe')
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

  /// Stream of ammunition for a specific rifle.
  Stream<List<AmmoProfile>> watchAvailableAmmunition(String rifleId) {
    return Stream.periodic(const Duration(milliseconds: 500))
        .asyncMap((_) => fetchAvailableAmmunition(rifleId));
  }
}
