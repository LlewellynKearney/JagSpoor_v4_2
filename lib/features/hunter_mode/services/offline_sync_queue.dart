import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class OfflineSyncQueue {
  static final OfflineSyncQueue _instance = OfflineSyncQueue._internal();
  static OfflineSyncQueue get instance => _instance;

  Database? _database;
  // Firestore instance used to flush queued actions on reconnect. Lazily
  // resolved to the global instance on first use (so the singleton can be
  // constructed in tests before Firebase.initializeApp() runs); injectable
  // for tests via [resetForTest] / [forTesting] (FakeFirebaseFirestore).
  FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  OfflineSyncQueue._internal();

  /// Injectable constructor for tests (FakeFirebaseFirestore).
  @visibleForTesting
  OfflineSyncQueue.forTesting(FirebaseFirestore firestore)
      : _firestoreOverride = firestore;

  /// Test-only: reset the cached database + (optionally) rebind the Firestore
  /// instance so each test gets a clean SQLite file and a fresh fake.
  @visibleForTesting
  void resetForTest({FirebaseFirestore? firestore}) {
    _database = null;
    _firestoreOverride = firestore;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'offline_queue.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sync_actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            collectionName TEXT NOT NULL,
            operation TEXT NOT NULL,
            payloadJson TEXT NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> enqueueAction(
    String collection,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payloadJson = jsonEncode(payload);

    return await db.insert('sync_actions', {
      'collectionName': collection,
      'operation': operation,
      'payloadJson': payloadJson,
      'timestamp': timestamp,
    });
  }

  Future<List<Map<String, dynamic>>> getAllPendingActions() async {
    final db = await database;
    return await db.query('sync_actions', orderBy: 'timestamp ASC');
  }

  Future<int> getQueueSize() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_actions',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteAction(int id) async {
    final db = await database;
    await db.delete('sync_actions', where: 'id = ?', whereArgs: [id]);
  }

  Future<SyncResult> processQueueWithInternet() async {
    // Ensure the local SQLite fallback buffer is open before draining it.
    await database;
    final actions = await getAllPendingActions();

    int successCount = 0;
    int failureCount = 0;
    List<String> errors = [];

    for (final action in actions) {
      final id = action['id'] as int;
      final collection = action['collectionName'] as String;
      final operation = action['operation'] as String;
      final payloadJson = action['payloadJson'] as String;

      try {
        final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

        switch (operation.toUpperCase()) {
          case 'CREATE':
            await _firestore.collection(collection).add(payload);
            break;
          case 'UPDATE':
            // For UPDATE, payload should contain docId in a special field
            final docId = payload.remove('_docId');
            if (docId != null) {
              await _firestore.collection(collection).doc(docId).update(payload);
            }
            break;
          case 'DELETE':
            final docId = payload['_docId'] as String?;
            if (docId != null) {
              await _firestore.collection(collection).doc(docId).delete();
            }
            break;
          default:
            throw Exception('Unknown operation: $operation');
        }

        await deleteAction(id);
        successCount++;
      } catch (e) {
        failureCount++;
        errors.add('Action $id failed: $e');
      }
    }

    return SyncResult(
      totalProcessed: successCount + failureCount,
      successCount: successCount,
      failureCount: failureCount,
      errors: errors,
    );
  }

  Future<void> clearQueue() async {
    final db = await database;
    await db.delete('sync_actions');
  }
}

class SyncResult {
  final int totalProcessed;
  final int successCount;
  final int failureCount;
  final List<String> errors;

  SyncResult({
    required this.totalProcessed,
    required this.successCount,
    required this.failureCount,
    required this.errors,
  });

  bool get isFullySuccessful => failureCount == 0;
  bool get hasFailures => failureCount > 0;
}
