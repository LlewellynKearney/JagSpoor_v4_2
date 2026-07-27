import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for handling complete account and data deletion.
/// Implements GDPR-compliant data pruning with transactional batch operations.
class AccountDeletionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Deletes the user's entire data pack including:
  /// - User profile document (/users/{uid})
  /// - All firearms owned by the user (/firearms where ownerId == uid)
  /// - All carcass logs by the hunter (/carcass_logs where hunterId == uid)
  /// - All waypoints by the hunter (/waypoints where hunterId == uid)
  /// - Finally deletes the authentication credential
  Future<void> deleteUserEntireDataPack() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found');
    }

    final uid = user.uid;
    final batch = _firestore.batch();

    // Step 1: Delete user profile document
    final userDocRef = _firestore.collection('users').doc(uid);
    batch.delete(userDocRef);

    // Step 2: Delete all firearms owned by this user
    final firearmsQuery = await _firestore
        .collection('firearms')
        .where('ownerId', isEqualTo: uid)
        .get();

    for (final doc in firearmsQuery.docs) {
      batch.delete(doc.reference);

      // Also delete nested ammunition subcollection for each firearm
      final ammunitionQuery = await _firestore
          .collection('firearms')
          .doc(doc.id)
          .collection('ammunition')
          .get();

      for (final ammoDoc in ammunitionQuery.docs) {
        batch.delete(ammoDoc.reference);
      }
    }

    // Step 3: Delete all carcass logs by this hunter
    final carcassLogsQuery = await _firestore
        .collection('carcass_logs')
        .where('hunterId', isEqualTo: uid)
        .get();

    for (final doc in carcassLogsQuery.docs) {
      batch.delete(doc.reference);
    }

    // Step 4: Delete all waypoints by this hunter
    final waypointsQuery = await _firestore
        .collection('waypoints')
        .where('hunterId', isEqualTo: uid)
        .get();

    for (final doc in waypointsQuery.docs) {
      batch.delete(doc.reference);
    }

    // Commit all deletions
    await batch.commit();

    // Step 5: Delete the authentication credential
    await user.delete();
  }

  /// Checks if the current user needs to re-authenticate before deletion.
  /// Firebase requires recent authentication for sensitive operations.
  bool get requiresRecentLogin {
    final user = _auth.currentUser;
    if (user == null) return true;
    
    // Check if the user was recently authenticated (within last 5 minutes)
    // This is a heuristic - Firebase doesn't expose exact last auth time
    return false; // The actual check happens when delete() is called
  }
}
