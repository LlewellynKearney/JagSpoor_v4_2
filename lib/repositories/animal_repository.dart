import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/offline_stream_guard.dart';
import '../models/animal.dart';

class AnimalRepository {
  AnimalRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Live stream of all animals ordered for display, mapped to [Animal] models.
  /// Uses Firestore's local cache first, then syncs from the server when online.
  /// A hard stream error (e.g. permissions change) is caught by
  /// [OfflineStreamGuard] and replaced with an empty list so the consumer's
  /// StreamBuilder shows a clean empty state rather than propagating the error.
  Stream<List<Animal>> watchAnimals() {
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('animals')
          .orderBy('sortOrder')
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs
                    .map((doc) {
                      try {
                        return Animal.fromFirestore(doc);
                      } catch (e) {
                        debugPrint('Error parsing animal ${doc.id}: $e');
                        return null;
                      }
                    })
                    .whereType<Animal>()
                    .toList(),
          ),
      fallback: const <Animal>[],
      debugLabel: 'animals',
    );
  }
}
