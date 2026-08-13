import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'meat_processing_exporter.dart';

/// A persisted meat-processing / slaughterhouse order, stored per hunter under
/// the `meat_processing_orders` Firestore collection.
class MeatProcessingOrder {
  final String id;
  final String hunterId;
  final String hunterName;
  final String carcassTag;
  final String species;
  final double hangingWeight;
  final List<ProcessingPortion> portions;
  final String spicePreference;
  final String specialInstructions;
  final String status;
  final DateTime? orderTimestamp;

  const MeatProcessingOrder({
    required this.id,
    required this.hunterId,
    required this.hunterName,
    required this.carcassTag,
    required this.species,
    required this.hangingWeight,
    required this.portions,
    required this.spicePreference,
    required this.specialInstructions,
    required this.status,
    required this.orderTimestamp,
  });

  factory MeatProcessingOrder.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final portionsRaw = data['portions'];
    final portions = <ProcessingPortion>[];
    if (portionsRaw is List) {
      for (final p in portionsRaw) {
        if (p is Map) {
          portions.add(ProcessingPortion(
            name: (p['name'] ?? '').toString(),
            targetWeightKg: (p['targetWeightKg'] as num?)?.toDouble(),
            spice: (p['spice'] ?? '').toString(),
          ));
        }
      }
    }
    final ts = data['orderTimestamp'];
    DateTime? tsValue;
    if (ts is Timestamp) tsValue = ts.toDate();
    return MeatProcessingOrder(
      id: doc.id,
      hunterId: (data['hunterId'] ?? '').toString(),
      hunterName: (data['hunterName'] ?? '').toString(),
      carcassTag: (data['carcassTag'] ?? '').toString(),
      species: (data['species'] ?? '').toString(),
      hangingWeight: (data['hangingWeight'] as num?)?.toDouble() ?? 0.0,
      portions: portions,
      spicePreference: (data['spicePreference'] ?? '').toString(),
      specialInstructions: (data['specialInstructions'] ?? '').toString(),
      status: (data['status'] ?? 'Submitted').toString(),
      orderTimestamp: tsValue,
    );
  }

  /// Statuses follow the slaughterhouse workflow.
  static const List<String> statuses = [
    'Submitted',
    'Acknowledged',
    'Processing',
    'Ready for Collection',
    'Collected',
    'Cancelled',
  ];
}

/// Owns the lifecycle of [MeatProcessingOrder] records in Firestore
/// (`meat_processing_orders`), scoped to the signed-in hunter.
class MeatProcessingOrderManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('meat_processing_orders');

  /// Persists a submitted slaughterhouse order. Returns the new doc id.
  Future<String> saveOrder({
    required String hunterName,
    required String carcassTag,
    required String species,
    required double hangingWeight,
    required List<ProcessingPortion> portions,
    required String spicePreference,
    required String specialInstructions,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User must be authenticated to log a meat order.');
    }

    final doc = _collection.doc();
    final data = <String, dynamic>{
      'hunterId': uid,
      'hunterName': hunterName,
      'carcassTag': carcassTag,
      'species': species,
      'hangingWeight': hangingWeight,
      'portions': portions.map((p) => p.toJson()).toList(),
      'spicePreference': spicePreference,
      'specialInstructions': specialInstructions,
      'status': 'Submitted',
      'orderTimestamp': FieldValue.serverTimestamp(),
    };
    await doc.set(data);
    return doc.id;
  }

  /// Reactive stream of the hunter's orders, newest first.
  Stream<List<MeatProcessingOrder>> getMyOrdersStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _collection
        .where('hunterId', isEqualTo: uid)
        .orderBy('orderTimestamp', descending: true)
        .snapshots()
        .map((qs) =>
            qs.docs.map(MeatProcessingOrder.fromFirestore).toList());
  }

  Future<void> updateOrderStatus(String orderId, String status) {
    return _collection.doc(orderId).update({'status': status});
  }

  Future<void> deleteOrder(String orderId) {
    return _collection.doc(orderId).delete();
  }
}
