import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/client_profile.dart';

/// Firestore CRUD for the outfitter's client roster (`client_roster`).
///
/// All queries are scoped to the signed-in outfitter's uid via `outfitterId`
/// so each PH only sees their own clients. The list stream orders by
/// `createdAt` desc and de-duplicates by document id defensively.
class ClientRosterManager {
  ClientRosterManager._();
  static final ClientRosterManager instance = ClientRosterManager._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('client_roster');

  String? get _currentUid => _auth.currentUser?.uid;

  /// Reactive list of clients for the signed-in outfitter.
  ///
  /// Errors are deliberately NOT swallowed here: a hard failure (e.g.
  /// permission-denied when the `client_roster` rules have not yet been
  /// deployed, or a missing composite index) is propagated to the consuming
  /// `StreamBuilder` so the screen can render an explicit error state with a
  /// retry button instead of an infinite spinner. (The previous
  /// `.handleError` callback returned a value that `handleError` ignores —
  /// silently dropping the error and leaving the stream emitting nothing,
  /// which froze the UI on the loading spinner forever.)
  Stream<List<ClientProfile>> getMyClientsStream() {
    final uid = _currentUid;
    if (uid == null) {
      return Stream.value(const <ClientProfile>[]);
    }
    return _collection
        .where('outfitterId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          // De-duplicate by document id (defensive against duplicate emits).
          final seen = <String>{};
          final out = <ClientProfile>[];
          for (final doc in snapshot.docs) {
            if (seen.add(doc.id)) {
              out.add(ClientProfile.fromFirestore(doc));
            }
          }
          return out;
        });
  }

  /// Fetch a single client by id (null if missing).
  Future<ClientProfile?> getClientById(String clientId) async {
    if (clientId.isEmpty) return null;
    final doc = await _collection.doc(clientId).get();
    if (!doc.exists) return null;
    return ClientProfile.fromFirestore(doc);
  }

  /// Adds a new client. Returns the new document id (empty on failure).
  Future<String> addClient(ClientProfile client) async {
    final uid = _currentUid;
    if (uid == null) return '';
    final now = DateTime.now();
    final payload = client
        .copyWith(updatedAt: now)
        .toMap();
    payload['outfitterId'] = uid;
    payload['createdAt'] = Timestamp.fromDate(now);
    payload['updatedAt'] = Timestamp.fromDate(now);
    final ref = await _collection.add(payload);
    return ref.id;
  }

  /// Updates an existing client (merges fields).
  Future<void> updateClient(ClientProfile client) async {
    final payload = client.copyWith(updatedAt: DateTime.now()).toMap();
    await _collection.doc(client.id).set(payload, SetOptions(merge: true));
  }

  /// Soft-hard delete: removes the roster entry. Linked hunt logs / permits
  /// are left intact (they keep their own hunterId/clientId snapshot).
  Future<void> deleteClient(String clientId) async {
    await _collection.doc(clientId).delete();
  }

  /// Appends a venison-permit id to the client's `permitReferenceIds` running
  /// list (used when a hunt log generates a permit for this client).
  Future<void> addPermitReference(String clientId, String permitId) async {
    if (clientId.isEmpty || permitId.isEmpty) return;
    final ref = _collection.doc(clientId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final ids = ((snap.data()?['permitReferenceIds'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toSet()
        ..add(permitId);
      tx.update(ref, {
        'permitReferenceIds': ids.toList(),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });
  }
}
