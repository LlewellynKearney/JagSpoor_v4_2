// ============================================================================
// Off-Grid Mesh Sync Engine — integration test suite (v4.4 Item #4)
// ----------------------------------------------------------------------------
// Tests the REAL BluetoothMeshSyncService code paths against a REAL in-memory
// SQLite database (sqflite_common_ffi) — no mocks of the sync engine itself.
//
// Coverage:
//   1. MeshSyncPayload serialization & deserialization (local queue tx).
//   2. Peer node discovery event broadcasting (ingestion / peer-count streams).
//   3. Conflict resolution when merging offline records (timestamp-wins).
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/services/bluetooth_mesh_sync_service.dart';
import 'package:jagspoor/features/shared/data/services/local_database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Reusable factory-built payload for the broadcast / merge tests.
  MeshSyncPayload makePayload({
    required String sender,
    required int recordId,
    DateTime? timestamp,
    Map<String, dynamic>? data,
  }) {
    return MeshSyncPayload(
      senderDeviceId: sender,
      targetTable: 'carcass_records',
      recordId: recordId,
      payloadJsonString: jsonEncode(data ?? {
        'hunterId': 'hunter-A',
        'species': 'Impala',
        'carcassWeight': 42.5,
        'slaughterFee': 120.0,
        'coldroomDays': 3,
        'status': 'In Coldroom',
      }),
      timestamp: timestamp ?? DateTime.utc(2026, 8, 14, 10, 0),
    );
  }

  setUpAll(() {
    // Point sqflite at the FFI (in-process SQLite) implementation so the real
    // LocalDatabaseService opens a genuine SQLite database on the desktop test
    // runner — exercising the real merge / stream code paths, not a mock.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Isolate each test's DB under a fresh temp path so table state never
    // bleeds between tests.
    final tempDir = await databaseFactory.getDatabasesPath();
    final testDbPath = p.join(tempDir, 'jagspoor_mesh_test.db');
    // Pre-emptively delete any leftover DB file so onCreate runs clean.
    await databaseFactory.deleteDatabase(testDbPath);
    // LocalDatabaseService caches the DB in a static field; reset it so the
    // next access opens the fresh test-path DB.
    LocalDatabaseService.resetForTest();
  });

  tearDown(() async {
    // Tear down the mesh singleton (closes streams, nulls the instance) so the
    // next test gets a clean service with empty signature cache + peer count.
    BluetoothMeshSyncService.instance.dispose();
  });

  group('1. Local queue transaction serialization & deserialization', () {
    test('MeshSyncPayload round-trips through serialize → deserialize', () {
      final original = makePayload(
        sender: 'dev_alpha',
        recordId: 1001,
        timestamp: DateTime.utc(2026, 8, 14, 9, 30),
        data: {
          'hunterId': 'hunter-A',
          'species': 'Greater Kudu',
          'carcassWeight': 78.2,
        },
      );

      final packet = original.serialize();
      expect(packet, isA<String>());
      // A BLE packet is a single JSON object (no raw newlines that would break
      // a transmission frame).
      expect(packet.contains('\n'), isFalse);

      final restored = MeshSyncPayload.deserialize(packet);
      expect(restored.senderDeviceId, original.senderDeviceId);
      expect(restored.targetTable, original.targetTable);
      expect(restored.recordId, original.recordId);
      expect(restored.payloadJsonString, original.payloadJsonString);
      expect(restored.timestamp.toIso8601String(),
          original.timestamp.toIso8601String());
    });

    test('toJson / fromJson preserve every field', () {
      final original = makePayload(
        sender: 'dev_beta',
        recordId: 2002,
        data: {'species': 'Impala', 'carcassWeight': 41.0},
      );

      final json = original.toJson();
      final restored = MeshSyncPayload.fromJson(json);

      expect(restored.senderDeviceId, 'dev_beta');
      expect(restored.recordId, 2002);
      expect(restored.targetTable, 'carcass_records');
      final decodedData =
          jsonDecode(restored.payloadJsonString) as Map<String, dynamic>;
      expect(decodedData['species'], 'Impala');
      expect(decodedData['carcassWeight'], 41.0);
    });

    test('deserialize tolerates an ISO8601 timestamp with timezone offset', () {
      final json = {
        'senderDeviceId': 'dev_gamma',
        'targetTable': 'bookings',
        'recordId': 5,
        'payloadJsonString': '{"clientName":"Test"}',
        'timestamp': '2026-08-14T10:00:00.000Z',
      };
      final restored = MeshSyncPayload.fromJson(json);
      expect(restored.timestamp.toUtc().year, 2026);
    });
  });

  group('2. Peer node discovery event broadcasting', () {
    test(
        'receiveIncomingMeshPayload emits on the ingestion stream '
        'and bumps the peer count', () async {
      final service = BluetoothMeshSyncService.instance;
      await service.initialize(deviceId: 'self_device');

      final Completer<MeshSyncPayload> ingestionCompleter =
          Completer<MeshSyncPayload>();
      final Completer<int> peerCompleter = Completer<int>();

      service.ingestionStream.listen((payload) {
        if (!ingestionCompleter.isCompleted) ingestionCompleter.complete(payload);
      });
      service.peerCountStream.listen((count) {
        if (!peerCompleter.isCompleted) peerCompleter.complete(count);
      });

      final payload = makePayload(sender: 'peer_device', recordId: 9001);
      final accepted =
          await service.receiveIncomingMeshPayload(payload.serialize());

      expect(accepted, isTrue);

      final ingested = await ingestionCompleter.future
          .timeout(const Duration(seconds: 2));
      expect(ingested.senderDeviceId, 'peer_device');
      expect(ingested.recordId, 9001);

      final peers = await peerCompleter.future
          .timeout(const Duration(seconds: 2));
      expect(peers, greaterThan(0));
    });

    test('own broadcasts are skipped (loop prevention)', () async {
      final service = BluetoothMeshSyncService.instance;
      await service.initialize(deviceId: 'self_device');

      var emitted = false;
      service.ingestionStream.listen((_) => emitted = true);

      // A payload whose sender is THIS device must not be re-ingested.
      final ownPayload = makePayload(sender: 'self_device', recordId: 7007);
      final accepted =
          await service.receiveIncomingMeshPayload(ownPayload.serialize());

      expect(accepted, isFalse);
      // Give the (empty) stream a moment to prove nothing was emitted.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted, isFalse);
    });

    test('duplicate payloads are de-duplicated by signature', () async {
      final service = BluetoothMeshSyncService.instance;
      await service.initialize(deviceId: 'self_device');

      var emitCount = 0;
      service.ingestionStream.listen((_) => emitCount++);

      final payload = makePayload(sender: 'peer_dup', recordId: 8008);
      final first =
          await service.receiveIncomingMeshPayload(payload.serialize());
      // Same signature (same sender/table/id/timestamp) → must be skipped.
      final second =
          await service.receiveIncomingMeshPayload(payload.serialize());

      expect(first, isTrue);
      expect(second, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitCount, 1);
    });
  });

  group('3. Conflict resolution when merging offline records', () {
    test(
        'an incoming record that does not exist locally is inserted '
        '(isNewInsert path)', () async {
      final service = BluetoothMeshSyncService.instance;
      await service.initialize(deviceId: 'self_device');

      final payload = MeshSyncPayload(
        senderDeviceId: 'peer_A',
        targetTable: 'carcass_records',
        recordId: 3003,
        payloadJsonString: jsonEncode({
          'hunterId': 'hunter-A',
          'species': 'Impala',
          'carcassWeight': 42.5,
          'slaughterFee': 120.0,
          'coldroomDays': 3,
          'status': 'In Coldroom',
        }),
        timestamp: DateTime.utc(2026, 8, 14, 8, 0),
      );

      final accepted =
          await service.receiveIncomingMeshPayload(payload.serialize());
      expect(accepted, isTrue);

      // Verify the record actually landed in the real local DB.
      final db = await LocalDatabaseService.instance.database;
      final rows = await db.query(
        'carcass_records',
        where: 'id = ?',
        whereArgs: ['3003'],
      );
      expect(rows, hasLength(1));
      // Merged records are marked dirty so the cloud catch-up sync picks them up.
      expect(rows.first['isDirty'], 1);
      // The payload's data fields are stored flat on the row.
      expect(rows.first['species'], 'Impala');
      expect(rows.first['carcassWeight'], 42.5);
    });

    test(
        'an incoming record with an OLDER timestamp does NOT overwrite a '
        'newer local record (last-writer-wins)', () async {
      final service = BluetoothMeshSyncService.instance;
      await service.initialize(deviceId: 'self_device');

      final db = await LocalDatabaseService.instance.database;
      // The merge reads updatedAt (fallback createdAt) to decide conflict
      // resolution. Add those columns to carcass_records in-test so we can
      // seed a controlled "newer" local timestamp (12:00). Tolerant of an
      // already-added column (schema may persist across the shared temp DB).
      await _tryAddColumn(db, 'carcass_records', 'updatedAt TEXT');
      await _tryAddColumn(db, 'carcass_records', 'createdAt TEXT');
      await db.insert(
        'carcass_records',
        {
          'id': '4004',
          'hunterId': 'hunter-local',
          'species': 'Local Bull',
          'carcassWeight': 99.9,
          'status': 'In Coldroom',
          'isDirty': 0,
          'createdAt': DateTime.utc(2026, 8, 14, 6, 0).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 8, 14, 12, 0).toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Incoming payload for the SAME record id but OLDER timestamp (10:00).
      final olderPayload = MeshSyncPayload(
        senderDeviceId: 'peer_B',
        targetTable: 'carcass_records',
        recordId: 4004,
        payloadJsonString: jsonEncode({
          'hunterId': 'hunter-remote',
          'species': 'Remote Cow',
          'carcassWeight': 11.1,
        }),
        timestamp: DateTime.utc(2026, 8, 14, 10, 0),
      );

      final accepted =
          await service.receiveIncomingMeshPayload(olderPayload.serialize());
      // accepted == true: the packet was processed (signature recorded, stream
      // emitted) — but the local newer row must NOT have been overwritten.
      expect(accepted, isTrue);

      final rows = await db.query('carcass_records',
          where: 'id = ?', whereArgs: ['4004']);
      expect(rows, hasLength(1));
      // The local newer record wins — species stays "Local Bull".
      expect(rows.first['species'], 'Local Bull');
    });

    test(
        'an incoming record with a NEWER timestamp DOES overwrite an older '
        'local record (last-writer-wins)', () async {
      final service = BluetoothMeshSyncService.instance;
      await service.initialize(deviceId: 'self_device');

      final db = await LocalDatabaseService.instance.database;
      await _tryAddColumn(db, 'carcass_records', 'updatedAt TEXT');
      await _tryAddColumn(db, 'carcass_records', 'createdAt TEXT');
      // Seed an OLDER local record (updatedAt 08:00).
      await db.insert(
        'carcass_records',
        {
          'id': '5005',
          'hunterId': 'hunter-old',
          'species': 'Stale Impala',
          'carcassWeight': 10.0,
          'status': 'Pending',
          'isDirty': 0,
          'createdAt': DateTime.utc(2026, 8, 14, 4, 0).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 8, 14, 8, 0).toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Incoming payload for the SAME record id but NEWER timestamp (14:00).
      final newerPayload = MeshSyncPayload(
        senderDeviceId: 'peer_C',
        targetTable: 'carcass_records',
        recordId: 5005,
        payloadJsonString: jsonEncode({
          'hunterId': 'hunter-new',
          'species': 'Fresh Impala',
          'carcassWeight': 55.0,
        }),
        timestamp: DateTime.utc(2026, 8, 14, 14, 0),
      );

      final accepted =
          await service.receiveIncomingMeshPayload(newerPayload.serialize());
      expect(accepted, isTrue);

      final rows = await db.query('carcass_records',
          where: 'id = ?', whereArgs: ['5005']);
      expect(rows, hasLength(1));
      // The newer remote record wins — species becomes "Fresh Impala".
      expect(rows.first['species'], 'Fresh Impala');
      // Updated row is re-marked dirty for cloud catch-up.
      expect(rows.first['isDirty'], 1);
    });
  });
}

/// Adds a column to a table, swallowing the "duplicate column name" error so
/// the test is idempotent across tests that share the temp database file
/// (SQLite `ALTER TABLE ADD COLUMN` has no `IF NOT EXISTS` clause).
Future<void> _tryAddColumn(Database db, String table, String columnDef) async {
  try {
    await db.execute('ALTER TABLE $table ADD COLUMN $columnDef');
  } catch (_) {
    // Column already exists — safe to ignore.
  }
}
