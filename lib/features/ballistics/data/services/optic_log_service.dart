import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/optic_profile.dart';
import '../models/rifle_profile.dart';

/// A single optic-profile save event -- the audit entry written whenever the
/// user taps "Save Optic" in the Optical Suite. Captures the full optic
/// configuration snapshot, the host firearm it was bound to, and a timestamp
/// so the user can review their saved optics and configuration changes over
/// time.
class OpticLogEntry {
  final String? id;
  final String userId;
  final String firearmId;
  final String firearmLabel;
  final OpticProfile optic;
  final DateTime savedAt;

  const OpticLogEntry({
    this.id,
    required this.userId,
    required this.firearmId,
    required this.firearmLabel,
    required this.optic,
    required this.savedAt,
  });

  factory OpticLogEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return OpticLogEntry.fromMap(doc.data() ?? const <String, dynamic>{}, id: doc.id);
  }

  /// Snapshot-free constructor used by tests (and by [fromFirestore]) so the
  /// parsing contract is unit-testable without a Firestore emulator. Accepts
  /// the raw doc map + an optional doc id.
  factory OpticLogEntry.fromMap(Map<String, dynamic> data, {String? id}) {
    return OpticLogEntry(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      firearmId: (data['firearmId'] as String?) ?? '',
      firearmLabel: (data['firearmLabel'] as String?) ??
          (data['firearmName'] as String?) ??
          'Unknown firearm',
      optic: _opticFromMap(data['optic']),
      savedAt: (data['savedAt'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  static OpticProfile _opticFromMap(dynamic raw) {
    if (raw is Map) {
      return OpticProfile.fromJson(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return OpticProfile.defaults;
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'firearmId': firearmId,
        'firearmLabel': firearmLabel,
        'optic': optic.toJson(),
        'savedAt': FieldValue.serverTimestamp(),
      };

  OpticLogEntry copyWith({
    String? id,
    String? userId,
    String? firearmId,
    String? firearmLabel,
    OpticProfile? optic,
    DateTime? savedAt,
  }) =>
      OpticLogEntry(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        firearmId: firearmId ?? this.firearmId,
        firearmLabel: firearmLabel ?? this.firearmLabel,
        optic: optic ?? this.optic,
        savedAt: savedAt ?? this.savedAt,
      );
}

/// Service that owns the optic save / audit log. Writes an [OpticLogEntry] to
/// the owner-scoped `optic_logs` Firestore collection whenever the user saves
/// an optic profile from the Optical Suite, and exposes a reactive stream so
/// the "View Optic History" surface can render the saved optics + their
/// configuration changes.
class OpticLogService {
  OpticLogService._();
  static final OpticLogService instance = OpticLogService._();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// Appends an optic save audit entry to `optic_logs/{userId}`-scoped
  /// collection. Best-effort: a write failure is swallowed + logged so it
  /// never blocks the optic save itself (the caller has already persisted
  /// the optic to the firearm doc by the time this is invoked).
  Future<void> logSave({
    required String firearmId,
    required String firearmLabel,
    required OpticProfile optic,
  }) async {
    final uid = _currentUserId;
    if (uid == null || firearmId.isEmpty) return;
    try {
      await _firestore.collection('optic_logs').add({
        'userId': uid,
        'firearmId': firearmId,
        'firearmLabel': firearmLabel,
        'optic': optic.toJson(),
        'savedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('OpticLogService: failed to write optic log entry: $e');
    }
  }

  /// Reactive stream of the current user's optic save history (newest first).
  /// Returns an empty stream for an unauthenticated caller so the history
  /// surface renders its empty state instead of throwing.
  Stream<List<OpticLogEntry>> getMyOpticLogsStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value(const <OpticLogEntry>[]);
    return _firestore
        .collection('optic_logs')
        .where('userId', isEqualTo: uid)
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => OpticLogEntry.fromFirestore(doc))
            .toList())
        .handleError((e) {
      debugPrint('OpticLogService: error reading optic logs: $e');
      return const <OpticLogEntry>[];
    });
  }
}

/// Pure helper that builds the human-readable label for an optic log entry's
/// host firearm from a [RifleProfile] (the same "make model (calibre)"
/// formatting the Optical Suite dropdown uses). Extracted so the audit log
/// entry carries a stable, human-readable firearm reference even if the
/// underlying firearm doc is later deleted.
String firearmLabelForOpticLog(RifleProfile? rifle) {
  if (rifle == null) return 'Unknown firearm';
  return rifle.displayName;
}
