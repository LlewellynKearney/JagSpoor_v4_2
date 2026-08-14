import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/data/services/local_database_service.dart';
import '../models/carcass_record.dart';
import '../models/client_profile.dart';
import '../models/guided_hunt_log.dart';

/// CRUD + downstream linking for guided-hunt harvest logs
/// (`guided_hunt_logs` collection).
///
/// Each log is scoped to the signed-in outfitter and explicitly assigned to a
/// [ClientProfile] from the active roster. The manager also provides the two
/// bridges Item #17 requires:
///   * [buildPermitPrefill] — assembles the prefill map that seeds a venison
///     transport permit (hunter + farm block + the harvested species) so the
///     outfitter can generate a permit straight from a hunt log.
///   * [pushToSlaughterhouseManifest] — writes a [CarcassRecord] into the
///     local SQLite `carcass_records` table the Slaghuis Matrix reads, linking
///     the hunt log to the slaughterhouse / coldroom manifest.
class GuidedHuntLogManager {
  GuidedHuntLogManager._();
  static final GuidedHuntLogManager instance = GuidedHuntLogManager._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocalDatabaseService _dbService = LocalDatabaseService();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('guided_hunt_logs');

  String? get _currentUid => _auth.currentUser?.uid;

  /// Reactive list of hunt logs for the signed-in outfitter.
  ///
  /// Errors are deliberately NOT swallowed here: a hard failure (e.g.
  /// permission-denied when the `guided_hunt_logs` rules have not yet been
  /// deployed, or a missing composite index) is propagated to the consuming
  /// `StreamBuilder` so the screen can render an explicit error state with a
  /// retry button instead of an infinite spinner. (The previous
  /// `.handleError` callback returned a value that `handleError` ignores —
  /// silently dropping the error and leaving the stream emitting nothing,
  /// which froze the UI on the loading spinner forever.)
  Stream<List<GuidedHuntLog>> getMyHuntLogsStream() {
    final uid = _currentUid;
    if (uid == null) return Stream.value(const <GuidedHuntLog>[]);
    return _collection
        .where('outfitterId', isEqualTo: uid)
        .orderBy('huntDate', descending: true)
        .snapshots()
        .map((snapshot) {
          final seen = <String>{};
          final out = <GuidedHuntLog>[];
          for (final doc in snapshot.docs) {
            if (seen.add(doc.id)) {
              out.add(GuidedHuntLog.fromFirestore(doc));
            }
          }
          return out;
        });
  }

  /// Fetch a single hunt log by id.
  Future<GuidedHuntLog?> getHuntLogById(String logId) async {
    if (logId.isEmpty) return null;
    final doc = await _collection.doc(logId).get();
    if (!doc.exists) return null;
    return GuidedHuntLog.fromFirestore(doc);
  }

  /// Persists a new hunt log. Returns the new document id (empty on failure).
  Future<String> addHuntLog(GuidedHuntLog log) async {
    final uid = _currentUid;
    if (uid == null) return '';
    final now = DateTime.now();
    final payload = log.copyWith(updatedAt: now).toMap();
    payload['outfitterId'] = uid;
    payload['createdAt'] = Timestamp.fromDate(now);
    payload['updatedAt'] = Timestamp.fromDate(now);
    final ref = await _collection.add(payload);
    return ref.id;
  }

  /// Updates an existing hunt log (merge).
  Future<void> updateHuntLog(GuidedHuntLog log) async {
    final payload = log.copyWith(updatedAt: DateTime.now()).toMap();
    await _collection.doc(log.id).set(payload, SetOptions(merge: true));
  }

  /// Deletes a hunt log.
  Future<void> deleteHuntLog(String logId) async {
    await _collection.doc(logId).delete();
  }

  /// Records the id of a venison permit generated from this hunt log.
  Future<void> linkPermit(String logId, String permitId) async {
    if (logId.isEmpty || permitId.isEmpty) return;
    await _collection.doc(logId).set({
      'permitId': permitId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  /// Records the local carcass-record id pushed to the slaughterhouse
  /// manifest from this hunt log.
  Future<void> linkCarcassRecord(String logId, String carcassRecordId) async {
    if (logId.isEmpty || carcassRecordId.isEmpty) return;
    await _collection.doc(logId).set({
      'carcassRecordId': carcassRecordId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  /// Assembles the prefill map for a [VenisonPermitFormScreen] from a hunt
  /// log + its assigned client + (optionally) the issuing outfitter's farm
  /// block. The venison permit form applies this map directly when opened
  /// from a hunt log, seeding the hunter block + the harvested species list.
  Future<Map<String, dynamic>> buildPermitPrefill({
    required GuidedHuntLog log,
    required ClientProfile client,
  }) async {
    final prefill = <String, dynamic>{
      'hunterName': client.fullName,
      'hunterIdNumber': client.idPassportNumber,
      'hunterCell': client.cellNumber,
      'hunterAddress': client.address,
      'clientId': client.id,
      'guidedHuntLogId': log.id,
      'outfitterId': log.outfitterId,
      // Seed the species list with the harvested species.
      'speciesHuntedAndTransported': [
        {
          'species': log.species,
          'sex': log.sex,
          'quantity': 1,
        }
      ],
    };

    // Outfitter / farm block — read from the outfitters doc when available.
    if (log.outfitterId.isNotEmpty) {
      final outfitterDoc =
          await _firestore.collection('outfitters').doc(log.outfitterId).get();
      if (outfitterDoc.exists) {
        final o = outfitterDoc.data()!;
        prefill['authorizedPersonName'] = o['contactName'] ?? o['name'] ?? '';
        prefill['farmName'] = o['farmName'] ?? o['businessName'] ?? '';
        prefill['farmAddress'] = o['address'] ?? o['farmAddress'] ?? '';
        prefill['farmCell'] = o['cellNumber'] ?? o['phone'] ?? '';
      }
    }
    return prefill;
  }

  /// Writes a [CarcassRecord] into the local SQLite `carcass_records` table
  /// (the data source for the Slaghuis Matrix / slaughterhouse manifest) from
  /// a hunt log + the client on the log. Returns the new local record id
  /// (empty if the log has no carcass weight to manifest).
  Future<String> pushToSlaughterhouseManifest(GuidedHuntLog log) async {
    if (log.carcassWeightKg <= 0) return '';
    final db = await _dbService.database;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final record = CarcassRecord(
      id: id,
      hunterId: log.clientId,
      species: log.species,
      carcassWeight: log.carcassWeightKg,
      slaughterFee: 150.0,
      coldroomDays: 0,
      status: 'In Coldroom',
      isDirty: 1,
    );
    await db.insert('carcass_records', record.toMap());
    await linkCarcassRecord(log.id, id);
    return id;
  }
}
