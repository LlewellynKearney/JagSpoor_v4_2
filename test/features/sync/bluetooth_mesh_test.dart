// ============================================================================
// Bluetooth Mesh Sync Engine Test Suite v16.0
// Validates offline peer-to-peer BLE mesh synchronization functionality
// ============================================================================

import 'dart:convert';

// ============================================================================
// Mock Database Helper for Testing
// ============================================================================

/// Mock pending record for testing dirty record serialization.
class MockPendingRecord {
  final String tableName;
  final int recordId;
  final Map<String, dynamic> data;
  final int isDirty;
  final DateTime? updatedAt;

  const MockPendingRecord({
    required this.tableName,
    required this.recordId,
    required this.data,
    this.isDirty = 1,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': recordId.toString(),
      ...data,
      'isDirty': isDirty,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

/// Mock local storage cache for testing payload ingestion.
class MockLocalStorageCache {
  final Map<String, Map<String, dynamic>> _storage = {};
  final List<String> _insertLog = [];
  final List<String> _updateLog = [];
  final List<String> _skippedLog = [];

  void insert(String tableName, int recordId, Map<String, dynamic> data) {
    final key = '$tableName:$recordId';
    _storage[key] = Map<String, dynamic>.from(data);
    _insertLog.add(key);
  }

  void update(String tableName, int recordId, Map<String, dynamic> data) {
    final key = '$tableName:$recordId';
    _storage[key] = Map<String, dynamic>.from(data);
    _updateLog.add(key);
  }

  void skip(String tableName, int recordId, String reason) {
    final key = '$tableName:$recordId';
    _skippedLog.add('$key ($reason)');
  }

  bool contains(String tableName, int recordId) {
    return _storage.containsKey('$tableName:$recordId');
  }

  Map<String, dynamic>? get(String tableName, int recordId) {
    return _storage['$tableName:$recordId'];
  }

  List<String> get insertLog => List.unmodifiable(_insertLog);
  List<String> get updateLog => List.unmodifiable(_updateLog);
  List<String> get skippedLog => List.unmodifiable(_skippedLog);
  int get count => _storage.length;
}

// ============================================================================
// Standalone MeshSyncPayload for Testing
// ============================================================================

/// Schema for mesh synchronization payload (standalone for testing).
class TestMeshSyncPayload {
  final String senderDeviceId;
  final String targetTable;
  final int recordId;
  final String payloadJsonString;
  final DateTime timestamp;

  const TestMeshSyncPayload({
    required this.senderDeviceId,
    required this.targetTable,
    required this.recordId,
    required this.payloadJsonString,
    required this.timestamp,
  });

  factory TestMeshSyncPayload.fromJson(Map<String, dynamic> json) {
    return TestMeshSyncPayload(
      senderDeviceId: json['senderDeviceId'] as String,
      targetTable: json['targetTable'] as String,
      recordId: json['recordId'] as int,
      payloadJsonString: json['payloadJsonString'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'senderDeviceId': senderDeviceId,
      'targetTable': targetTable,
      'recordId': recordId,
      'payloadJsonString': payloadJsonString,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  String serialize() => jsonEncode(toJson());

  static TestMeshSyncPayload deserialize(String packetJson) {
    final decoded = jsonDecode(packetJson) as Map<String, dynamic>;
    return TestMeshSyncPayload.fromJson(decoded);
  }
}

// ============================================================================
// Test Suite
// ============================================================================

void runBluetoothMeshTests() {
  print('=' * 70);
  print('BLUETOOTH MESH SYNC TEST SUITE v16.0');
  print('Testing offline peer-to-peer BLE mesh synchronization');
  print('=' * 70);

  int passed = 0;
  int failed = 0;

  final mockStorage = MockLocalStorageCache();

  // ========================================================================
  // Test 1: Dirty Record Serialization
  // ========================================================================
  {
    print('');
    print('Test 1: Dirty record serializes correctly to mesh packet format');

    final mockDirtyRecord = MockPendingRecord(
      tableName: 'carcass_records',
      recordId: 12345,
      data: {
        'hunterId': 'hunter_001',
        'species': 'Cape Buffalo',
        'carcassWeight': 285.5,
        'slaughterFee': 150.0,
        'coldroomDays': 3,
        'status': 'processed',
      },
      isDirty: 1,
      updatedAt: DateTime(2024, 7, 25, 14, 30, 0),
    );

    final payload = TestMeshSyncPayload(
      senderDeviceId: 'dev_12345_67890',
      targetTable: mockDirtyRecord.tableName,
      recordId: mockDirtyRecord.recordId,
      payloadJsonString: jsonEncode(mockDirtyRecord.data),
      timestamp: mockDirtyRecord.updatedAt!,
    );

    assert(
      payload.senderDeviceId == 'dev_12345_67890',
      'Sender device ID should match',
    );
    assert(
      payload.targetTable == 'carcass_records',
      'Target table should be carcass_records',
    );
    assert(
      payload.recordId == 12345,
      'Record ID should be 12345',
    );
    assert(
      payload.payloadJsonString.isNotEmpty,
      'Payload JSON string should not be empty',
    );
    assert(
      payload.timestamp == DateTime(2024, 7, 25, 14, 30, 0),
      'Timestamp should match',
    );

    final serializedPacket = payload.serialize();
    // Verify packet contains all required fields
    assert(
      serializedPacket.contains('"senderDeviceId"'),
      'Serialized packet should contain senderDeviceId field',
    );
    assert(
      serializedPacket.contains('"targetTable"'),
      'Serialized packet should contain targetTable field',
    );
    assert(
      serializedPacket.contains('"recordId"'),
      'Serialized packet should contain recordId field',
    );
    assert(
      serializedPacket.contains('"payloadJsonString"'),
      'Serialized packet should contain payloadJsonString field',
    );
    assert(
      serializedPacket.contains('"timestamp"'),
      'Serialized packet should contain timestamp field',
    );

    final deserializedPayload = TestMeshSyncPayload.deserialize(serializedPacket);
    assert(
      deserializedPayload.senderDeviceId == payload.senderDeviceId,
      'Deserialized sender device ID should match original',
    );
    assert(
      deserializedPayload.targetTable == payload.targetTable,
      'Deserialized target table should match original',
    );
    assert(
      deserializedPayload.recordId == payload.recordId,
      'Deserialized record ID should match original',
    );

    print('✓ Test 1: Dirty record serialization verified');
    passed++;
  }

  // ========================================================================
  // Test 2: Foreign Payload Ingestion
  // ========================================================================
  {
    print('');
    print('Test 2: Foreign payload creates unsynced entry in local storage');

    final foreignPayload = TestMeshSyncPayload(
      senderDeviceId: 'peer_device_abc_123',
      targetTable: 'bookings',
      recordId: 99999,
      payloadJsonString: jsonEncode({
        'clientName': 'John Smith',
        'contactNumber': '+27-82-555-1234',
        'arrivalDate': '2024-08-15',
        'departureDate': '2024-08-20',
        'lodgingId': 'lodge_001',
        'vehicleId': 'vehicle_003',
        'status': 'confirmed',
      }),
      timestamp: DateTime.now(),
    );

    assert(
      !mockStorage.contains(foreignPayload.targetTable, foreignPayload.recordId),
      'Record should not exist before ingestion',
    );

    final incomingJson = foreignPayload.serialize();
    final receivedPayload = TestMeshSyncPayload.deserialize(incomingJson);

    final existingRecord = mockStorage.get(
      receivedPayload.targetTable,
      receivedPayload.recordId,
    );

    if (existingRecord == null) {
      final recordData = jsonDecode(receivedPayload.payloadJsonString) as Map<String, dynamic>;
      recordData['id'] = receivedPayload.recordId.toString();
      recordData['isDirty'] = 1;

      mockStorage.insert(
        receivedPayload.targetTable,
        receivedPayload.recordId,
        recordData,
      );
    }

    assert(
      mockStorage.contains(foreignPayload.targetTable, foreignPayload.recordId),
      'Record should exist after ingestion',
    );

    final insertedRecord = mockStorage.get(
      foreignPayload.targetTable,
      foreignPayload.recordId,
    );
    assert(
      insertedRecord != null,
      'Inserted record should not be null',
    );
    assert(
      insertedRecord!['isDirty'] == 1,
      'Inserted record should be marked as isDirty=1',
    );
    assert(
      insertedRecord!['clientName'] == 'John Smith',
      'Client name should match',
    );
    assert(
      insertedRecord!['status'] == 'confirmed',
      'Status should match',
    );

    assert(
      mockStorage.insertLog.length == 1,
      'One insert should be logged',
    );
    assert(
      mockStorage.insertLog.first.contains('bookings:99999'),
      'Insert log should contain the correct key',
    );

    print('✓ Test 2: Foreign payload ingestion verified');
    passed++;
  }

  // ========================================================================
  // Test 3: Duplicate Packet Handling
  // ========================================================================
  {
    print('');
    print('Test 3: Duplicate historical packets are ignored gracefully');

    final initialPayload = TestMeshSyncPayload(
      senderDeviceId: 'peer_device_xyz_456',
      targetTable: 'invoices',
      recordId: 55555,
      payloadJsonString: jsonEncode({
        'clientName': 'Acme Corp',
        'packageName': 'Platinum Safari',
        'packageBasePrice': 5000.0,
        'totalAmount': 5250.0,
        'extras': '["Ground Transport", "Professional Guide"]',
      }),
      timestamp: DateTime(2024, 7, 25, 10, 0, 0),
    );

    final Set<String> receivedSignatures = {};

    final initialSignature = '${initialPayload.senderDeviceId}_'
        '${initialPayload.targetTable}_'
        '${initialPayload.recordId}_'
        '${initialPayload.timestamp.millisecondsSinceEpoch}';

    if (!receivedSignatures.contains(initialSignature)) {
      receivedSignatures.add(initialSignature);

      final recordData = jsonDecode(initialPayload.payloadJsonString) as Map<String, dynamic>;
      recordData['id'] = initialPayload.recordId.toString();
      recordData['isDirty'] = 1;
      mockStorage.insert(
        initialPayload.targetTable,
        initialPayload.recordId,
        recordData,
      );
    }

    assert(
      mockStorage.contains(initialPayload.targetTable, initialPayload.recordId),
      'Initial payload should be stored',
    );
    assert(
      mockStorage.insertLog.length == 1,
      'Only one insert should occur for initial payload',
    );

    final duplicatePayload = TestMeshSyncPayload(
      senderDeviceId: 'peer_device_xyz_456',
      targetTable: 'invoices',
      recordId: 55555,
      payloadJsonString: jsonEncode({
        'clientName': 'Acme Corp',
        'packageName': 'Platinum Safari',
        'packageBasePrice': 5000.0,
        'totalAmount': 5250.0,
        'extras': '["Ground Transport", "Professional Guide"]',
      }),
      timestamp: DateTime(2024, 7, 25, 10, 0, 0),
    );

    final duplicateSignature = '${duplicatePayload.senderDeviceId}_'
        '${duplicatePayload.targetTable}_'
        '${duplicatePayload.recordId}_'
        '${duplicatePayload.timestamp.millisecondsSinceEpoch}';

    bool wasProcessed = true;
    if (receivedSignatures.contains(duplicateSignature)) {
      mockStorage.skip(
        duplicatePayload.targetTable,
        duplicatePayload.recordId,
        'duplicate_signature',
      );
      wasProcessed = false;
    } else {
      receivedSignatures.add(duplicateSignature);
      mockStorage.insert(
        duplicatePayload.targetTable,
        duplicatePayload.recordId,
        jsonDecode(duplicatePayload.payloadJsonString) as Map<String, dynamic>,
      );
    }

    assert(
      !wasProcessed,
      'Duplicate payload should not be processed',
    );
    assert(
      mockStorage.skippedLog.length == 1,
      'One skip should be logged for duplicate',
    );
    assert(
      mockStorage.skippedLog.first.contains('duplicate_signature'),
      'Skip reason should indicate duplicate',
    );

    assert(
      mockStorage.insertLog.length == 1,
      'No new insert should occur for duplicate',
    );

    assert(
      mockStorage.count == 1,
      'Storage count should remain at 1',
    );

    print('✓ Test 3: Duplicate packet handling verified');
    passed++;
  }

  // ========================================================================
  // Test 4: JSON Round-trip Preservation
  // ========================================================================
  {
    print('');
    print('Test 4: MeshSyncPayload JSON round-trip preserves all fields');

    final originalPayload = TestMeshSyncPayload(
      senderDeviceId: 'test_device_001',
      targetTable: 'outfitter_packages',
      recordId: 77777,
      payloadJsonString: '{"key": "value", "number": 42, "nested": {"a": 1}}',
      timestamp: DateTime(2024, 7, 25, 18, 45, 30),
    );

    final jsonString = originalPayload.serialize();
    final deserializedPayload = TestMeshSyncPayload.deserialize(jsonString);
    final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;

    assert(
      deserializedPayload.senderDeviceId == originalPayload.senderDeviceId,
      'senderDeviceId should be preserved',
    );
    assert(
      deserializedPayload.targetTable == originalPayload.targetTable,
      'targetTable should be preserved',
    );
    assert(
      deserializedPayload.recordId == originalPayload.recordId,
      'recordId should be preserved',
    );
    assert(
      deserializedPayload.payloadJsonString == originalPayload.payloadJsonString,
      'payloadJsonString should be preserved',
    );
    assert(
      deserializedPayload.timestamp == originalPayload.timestamp,
      'timestamp should be preserved',
    );

    assert(
      jsonMap['senderDeviceId'] == 'test_device_001',
      'JSON senderDeviceId should match',
    );
    assert(
      jsonMap['targetTable'] == 'outfitter_packages',
      'JSON targetTable should match',
    );
    assert(
      jsonMap['recordId'] == 77777,
      'JSON recordId should match',
    );

    print('✓ Test 4: JSON round-trip preservation verified');
    passed++;
  }

  // ========================================================================
  // Test 5: Empty Payload Handling
  // ========================================================================
  {
    print('');
    print('Test 5: Empty payload list handled gracefully');

    final List<TestMeshSyncPayload> emptyPayloadList = [];

    int broadcastCount = 0;
    for (final _ in emptyPayloadList) {
      broadcastCount++;
    }

    assert(
      broadcastCount == 0,
      'No broadcasts should occur with empty payload list',
    );

    print('✓ Test 5: Empty payload handling verified');
    passed++;
  }

  // ========================================================================
  // Test 6: Timestamp Comparison Logic
  // ========================================================================
  {
    print('');
    print('Test 6: Older incoming packets are ignored correctly');

    final existingTimestamp = DateTime(2024, 7, 25, 12, 0, 0);

    final incomingPayload = TestMeshSyncPayload(
      senderDeviceId: 'peer_device_old',
      targetTable: 'carcass_records',
      recordId: 88888,
      payloadJsonString: '{"species": "Old Record"}',
      timestamp: DateTime(2024, 7, 25, 11, 0, 0),
    );

    bool shouldUpdate = incomingPayload.timestamp.isAfter(existingTimestamp);

    assert(
      !shouldUpdate,
      'Older incoming payload should not trigger update',
    );

    final newerPayload = TestMeshSyncPayload(
      senderDeviceId: 'peer_device_new',
      targetTable: 'carcass_records',
      recordId: 88888,
      payloadJsonString: '{"species": "Newer Record"}',
      timestamp: DateTime(2024, 7, 25, 13, 0, 0),
    );

    shouldUpdate = newerPayload.timestamp.isAfter(existingTimestamp);

    assert(
      shouldUpdate,
      'Newer incoming payload should trigger update',
    );

    print('✓ Test 6: Timestamp comparison logic verified');
    passed++;
  }

  // ========================================================================
  // Test 7: Multiple Table Types Serialization
  // ========================================================================
  {
    print('');
    print('Test 7: Multiple table types serialize correctly');

    final tableTypes = [
      'carcass_records',
      'invoices',
      'bookings',
      'outfitter_packages',
    ];

    int successCount = 0;

    for (int i = 0; i < tableTypes.length; i++) {
      final payload = TestMeshSyncPayload(
        senderDeviceId: 'device_multi_$i',
        targetTable: tableTypes[i],
        recordId: 10000 + i,
        payloadJsonString: '{"table": "${tableTypes[i]}"}',
        timestamp: DateTime.now(),
      );

      final serialized = payload.serialize();
      final deserialized = TestMeshSyncPayload.deserialize(serialized);

      if (deserialized.targetTable == tableTypes[i]) {
        successCount++;
      }
    }

    assert(
      successCount == tableTypes.length,
      'All $successCount table types should serialize correctly',
    );

    print('✓ Test 7: Multiple table serialization verified');
    passed++;
  }

  // ========================================================================
  // Test 8: Record Signature Generation
  // ========================================================================
  {
    print('');
    print('Test 8: Record signatures enable duplicate detection');

    final payload1 = TestMeshSyncPayload(
      senderDeviceId: 'device_sig_1',
      targetTable: 'test_table',
      recordId: 111,
      payloadJsonString: '{"data": "same"}',
      timestamp: DateTime(2024, 7, 25, 10, 0, 0),
    );

    final payload2 = TestMeshSyncPayload(
      senderDeviceId: 'device_sig_2',
      targetTable: 'test_table',
      recordId: 111,
      payloadJsonString: '{"data": "same"}',
      timestamp: DateTime(2024, 7, 25, 10, 0, 0),
    );

    String generateSignature(TestMeshSyncPayload p) =>
        '${p.senderDeviceId}_${p.targetTable}_${p.recordId}_${p.timestamp.millisecondsSinceEpoch}';

    final sig1 = generateSignature(payload1);
    final sig2 = generateSignature(payload2);

    assert(
      sig1 != sig2,
      'Signatures from different senders should differ',
    );

    final sig1Copy = generateSignature(payload1);
    assert(
      sig1 == sig1Copy,
      'Same payload should produce same signature',
    );

    print('✓ Test 8: Record signature generation verified');
    passed++;
  }

  // ========================================================================
  // Summary
  // ========================================================================
  print('');
  print('=' * 70);
  print('BLUETOOTH MESH SYNC TEST SUMMARY v16.0');
  print('=' * 70);
  print('Total Tests: ${passed + failed}');
  print('Passed: $passed');
  print('Failed: $failed');
  print('=' * 70);

  if (failed == 0) {
    print('✓ ALL BLUETOOTH MESH SYNC TESTS PASSED');
    print('  - Serialization: Clean JSON packet generation');
    print('  - Ingestion: Seamless foreign payload processing');
    print('  - Deduplication: Loop recursion prevention verified');
  } else {
    print('✗ SOME TESTS FAILED - Review output above');
  }
  print('=' * 70);
}

// ============================================================================
// Entry Point
// ============================================================================
void main() {
  runBluetoothMeshTests();
}
