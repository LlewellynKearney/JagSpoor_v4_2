import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CarcassLogManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Log a new carcass entry into the slaughterhouse tracking array
  Future<void> logCarcass({
    required String tagNumber,
    required String species,
    required double fieldWeight,
    required double hangingWeight,
    required String coldStoragePosition, // e.g., "Chiller A - Hook 14"
  }) async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User must be authenticated to log game.");

    final Map<String, dynamic> carcassData = {
      'hunterId': uid,
      'tagNumber': tagNumber,
      'species': species,
      'fieldWeightKg': fieldWeight,
      'hangingWeightKg': hangingWeight,
      'coldStoragePosition': coldStoragePosition,
      'status':
          'Hanging', // Workflow states: Hanging -> Skinning -> Processing -> Dispatched
      'timestamp': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('carcass_logs').add(carcassData);
  }

  // Fetch real-time chiller inventories for the hunter. With offline
  // persistence enabled the stream serves cached records when the network
  // drops; an unauthenticated caller gets a stable empty stream rather than
  // querying for a null hunterId.
  Stream<QuerySnapshot> getActiveChillerLogs() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('carcass_logs')
        .where('hunterId', isEqualTo: uid)
        .where('status', isEqualTo: 'Hanging')
        .snapshots();
  }
}
