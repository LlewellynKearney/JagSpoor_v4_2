import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/offline_stream_guard.dart';
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
  OpticLogService._({this.firestoreForTesting, this.currentUserIdResolverForTesting});
  static final OpticLogService instance = OpticLogService._();

  /// Test seam: inject a Firestore instance (e.g. `FakeFirebaseFirestore`)
  /// so the stream/query contract can be unit-tested without a live Firebase
  /// app. Defaults to the global instance.
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  FirebaseFirestore get _firestore => firestoreForTesting ?? FirebaseFirestore.instance;

  /// Test seam: inject a uid resolver so the null-uid -> empty-stream branch
  /// and the owner-scoped query contract can be unit-tested without a real
  /// signed-in user. Defaults to the current Firebase user.
  @visibleForTesting
  String? Function()? currentUserIdResolverForTesting;

  String? get _currentUserId =>
      currentUserIdResolverForTesting != null
          ? currentUserIdResolverForTesting!()
          : FirebaseAuth.instance.currentUser?.uid;

  /// Test-only constructor: build a fresh, isolated service (not the
  /// process-wide singleton) bound to an injectable Firestore + uid resolver.
  /// Mirrors the `FeedbackFirebaseService` test pattern so each test owns its
  /// own fake-backed instance (avoids `FieldValuePlatform` cross-test
  /// pollution that occurs when the singleton is reused across tests).
  @visibleForTesting
  factory OpticLogService.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() currentUserIdResolver,
  }) {
    return OpticLogService._(
      firestoreForTesting: firestore,
      currentUserIdResolverForTesting: currentUserIdResolver,
    );
  }

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
  ///
  /// The Firestore query is wrapped in [OfflineStreamGuard.offlineResilient]
  /// so a hard error (missing composite index, permissions change, offline
  /// with no cache) emits the fallback `[]` and completes -- letting the
  /// consuming `StreamBuilder` exit `ConnectionState.waiting` and render the
  /// empty state. The previous `.handleError` callback's return value was
  /// ignored (it only discards the error; it does NOT emit the returned
  /// list), so an errored stream never emitted and never completed -- the
  /// history surface showed an indefinite spinner / "empty after save"
  /// even though `logSave` had written the doc. The resilient guard fixes
  /// that hang.
  Stream<List<OpticLogEntry>> getMyOpticLogsStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value(const <OpticLogEntry>[]);
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('optic_logs')
          .where('userId', isEqualTo: uid)
          .orderBy('savedAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => OpticLogEntry.fromFirestore(doc))
              .toList()),
      fallback: const <OpticLogEntry>[],
      debugLabel: 'optic_logs',
    );
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
