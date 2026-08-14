import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Status of a sync record indicating whether it needs synchronization.
enum SyncStatus { synced, pending, error }

/// Represents a record that may need synchronization.
class SyncRecord {
  final String id;
  final String collection;
  final SyncStatus status;
  final DateTime lastModified;

  const SyncRecord({
    required this.id,
    required this.collection,
    required this.status,
    required this.lastModified,
  });
}

/// Service that monitors synchronization status for outfitter records.
/// Provides stream-driven status alerts for dirty (unsynced) records.
class OutfitterSyncService {
  final FirebaseFirestore _firestore;

  // Stream controllers for sync status updates
  final _syncStatusController = StreamController<int>.broadcast();
  final _dirtyRecordsController =
      StreamController<List<SyncRecord>>.broadcast();

  // Cache of dirty records pending sync.
  List<SyncRecord> _dirtyRecords = [];

  Timer? _pollTimer;
  bool _isDisposed = false;

  OutfitterSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Stream of dirty record count (records pending sync).
  /// Emits the count of records where isDirty == 1.
  Stream<int> get dirtyCountStream => _syncStatusController.stream;

  /// Stream of dirty records list.
  Stream<List<SyncRecord>> get dirtyRecordsStream =>
      _dirtyRecordsController.stream;

  /// Current count of dirty records.
  int get dirtyCount => _dirtyRecords.length;

  /// Current dirty records.
  List<SyncRecord> get dirtyRecords => List.unmodifiable(_dirtyRecords);

  /// Starts polling for sync status updates.
  /// [interval] is the polling interval in seconds (default: 30).
  void startPolling({int intervalSeconds = 30}) {
    if (_isDisposed) return;

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => checkSyncStatus(),
    );

    // Initial check
    checkSyncStatus();
  }

  /// Stops polling for sync status updates.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Checks the current sync status for all outfitter collections.
  Future<void> checkSyncStatus() async {
    if (_isDisposed) return;

    try {
      final List<SyncRecord> dirtyRecords = [];

      // Check all outfitter collections for dirty records
      final collections = [
        'outfitter/bookings',
        'outfitter/lodging',
        'outfitter/fleet',
        'outfitter/carcass_records',
      ];

      for (final collection in collections) {
        final snapshot =
            await _firestore
                .collection(collection)
                .where('isDirty', isEqualTo: 1)
                .get();

        for (final doc in snapshot.docs) {
          dirtyRecords.add(
            SyncRecord(
              id: doc.id,
              collection: collection,
              status: SyncStatus.pending,
              lastModified:
                  doc.data()['lastModified'] != null
                      ? (doc.data()['lastModified'] as Timestamp).toDate()
                      : DateTime.now(),
            ),
          );
        }
      }

      _dirtyRecords = dirtyRecords;
      _syncStatusController.add(dirtyRecords.length);
      _dirtyRecordsController.add(dirtyRecords);

      debugPrint(
        'OutfitterSyncService: Found ${dirtyRecords.length} dirty records',
      );
    } catch (e) {
      debugPrint('OutfitterSyncService: Error checking status: $e');
    }
  }

  /// Marks a record as synced (sets isDirty to 0).
  Future<bool> markAsSynced(String collection, String docId) async {
    try {
      await _firestore.collection(collection).doc(docId).update({
        'isDirty': 0,
        'lastSynced': FieldValue.serverTimestamp(),
      });

      // Update local state
      _dirtyRecords.removeWhere(
        (r) => r.id == docId && r.collection == collection,
      );
      _syncStatusController.add(_dirtyRecords.length);
      _dirtyRecordsController.add(_dirtyRecords);

      debugPrint('OutfitterSyncService: Marked $docId as synced');
      return true;
    } catch (e) {
      debugPrint('OutfitterSyncService: Error marking as synced: $e');
      return false;
    }
  }

  /// Marks all dirty records as synced.
  Future<int> syncAll() async {
    int successCount = 0;

    for (final record in _dirtyRecords.toList()) {
      final success = await markAsSynced(record.collection, record.id);
      if (success) successCount++;
    }

    return successCount;
  }

  /// Marks a record as dirty (needing sync).
  Future<bool> markAsDirty(String collection, String docId) async {
    try {
      await _firestore.collection(collection).doc(docId).update({
        'isDirty': 1,
        'lastModified': FieldValue.serverTimestamp(),
      });

      // Refresh status
      await checkSyncStatus();
      return true;
    } catch (e) {
      debugPrint('OutfitterSyncService: Error marking as dirty: $e');
      return false;
    }
  }

  /// Disposes of resources.
  void dispose() {
    _isDisposed = true;
    _pollTimer?.cancel();
    _syncStatusController.close();
    _dirtyRecordsController.close();
  }
}
