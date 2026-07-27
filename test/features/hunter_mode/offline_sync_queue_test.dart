import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mock.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:jagspoor_v4_2/features/hunter_mode/services/offline_sync_queue.dart';


void main() {
  group('JagSpoor Offline Activity Sync Queue Tests', () {
    late FakeFirebaseFirestore fakeFirestore;


    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      // Initialize your sync queue local database configuration matrix
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
