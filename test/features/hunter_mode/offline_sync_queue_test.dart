import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/offline_sync_queue.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('JagSpoor Offline Activity Sync Queue Tests', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUpAll(() {
      // Point sqflite at the FFI (in-process SQLite) implementation so the
      // real OfflineSyncQueue opens a genuine SQLite database on the desktop
      // test runner — exercising the real queue code paths, not a mock.
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      // The service opens `<databasesPath>/offline_queue.db`. Isolate each test
      // by deleting that file before the singleton reopens it, and bind the
      // fake Firestore so the queue flush writes to the in-memory fake, not the
      // real backend.
      final tempDir = await databaseFactory.getDatabasesPath();
      final testDbPath = p.join(tempDir, 'offline_queue.db');
      await databaseFactory.deleteDatabase(testDbPath);
      OfflineSyncQueue.instance.resetForTest(
        firestore: fakeFirestore,
        // ignore: invalid_use_of_visible_for_testing_member
      );
      await OfflineSyncQueue.instance.clearQueue();
    });


    test('Test 1: Enqueue action handles off-grid data capture perfectly', () async {
      final Map<String, dynamic> testPayload = {
        'name': 'Kill Site Alpha',
        'type': 'Spoor Track',
        'lat': -24.5,
        'lon': 31.5
      };


      // Simulate dropping a waypoint pin with zero cellular coverage
      await OfflineSyncQueue.instance.enqueueAction('waypoints', 'CREATE', testPayload);


      // Verify that the record caught inside the local SQLite fallback buffer
      final int queueSize = await OfflineSyncQueue.instance.getQueueSize();
      expect(queueSize, equals(1));


      final List<Map<String, dynamic>> pending = await OfflineSyncQueue.instance.getAllPendingActions();
      expect(pending.first['collectionName'], equals('waypoints'));
    });


    test('Test 2: Reconnected network flushes SQLite queue straight to Firestore', () async {
      final Map<String, dynamic> testCarcass = {
        'tagNumber': 'TAG-9982',
        'species': 'Kudu',
        'fieldWeightKg': 210.0,
      };


      // Queue an off-grid carcass log row
      await OfflineSyncQueue.instance.enqueueAction('carcass_logs', 'CREATE', testCarcass);


      // Trigger your background network connection restorer script manually
      final syncResult = await OfflineSyncQueue.instance.processQueueWithInternet();


      // Verify that the sync tracker reports absolute data transmission success
      expect(syncResult.successCount, equals(1));
      
      // Verify that local memory has been freed up and cleared of stale cache files
      final int finalQueueSize = await OfflineSyncQueue.instance.getQueueSize();
      expect(finalQueueSize, equals(0));
    });
  });
}
