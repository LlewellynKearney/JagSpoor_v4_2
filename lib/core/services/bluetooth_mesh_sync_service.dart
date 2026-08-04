import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../features/shared/data/services/local_database_service.dart';

/// Schema for mesh synchronization payload.
/// Tracks record data for peer-to-peer BLE transmission.
class MeshSyncPayload {
  /// Unique identifier of the sending device.
  final String senderDeviceId;

  /// Target database table name for the record.
  final String targetTable;

  /// Unique record identifier within the target table.
  final int recordId;

  /// JSON-encoded record payload string.
  final String payloadJsonString;

  /// Timestamp when the payload was created.
  final DateTime timestamp;

  const MeshSyncPayload({
    required this.senderDeviceId,
    required this.targetTable,
    required this.recordId,
    required this.payloadJsonString,
    required this.timestamp,
  });

  /// Creates a MeshSyncPayload from JSON map.
  factory MeshSyncPayload.fromJson(Map<String, dynamic> json) {
    return MeshSyncPayload(
      senderDeviceId: json['senderDeviceId'] as String,
      targetTable: json['targetTable'] as String,
      recordId: json['recordId'] as int,
      payloadJsonString: json['payloadJsonString'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Converts the payload to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'senderDeviceId': senderDeviceId,
      'targetTable': targetTable,
      'recordId': recordId,
      'payloadJsonString': payloadJsonString,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Serializes the payload to a JSON string for BLE transmission.
  String serialize() => jsonEncode(toJson());

  /// Deserializes a JSON string back to a MeshSyncPayload.
  static MeshSyncPayload deserialize(String packetJson) {
    final decoded = jsonDecode(packetJson) as Map<String, dynamic>;
    return MeshSyncPayload.fromJson(decoded);
  }

  @override
  String toString() {
    return 'MeshSyncPayload(sender: $senderDeviceId, table: $targetTable, '
        'recordId: $recordId, timestamp: $timestamp)';
  }
}

/// Represents a pending dirty record in the local database.
class PendingRecord {
  final String tableName;
  final int recordId;
  final Map<String, dynamic> data;
  final DateTime lastModified;

  const PendingRecord({
    required this.tableName,
    required this.recordId,
    required this.data,
    required this.lastModified,
  });
}

/// Callback type for successful peer data reception.
typedef OnMeshDataReceived =
    void Function(MeshSyncPayload payload, bool isNewInsert);

/// Callback type for mesh broadcast events.
typedef OnMeshBroadcast = void Function(List<MeshSyncPayload> payloads);

/// Offline peer-to-peer Bluetooth Low Energy mesh synchronization service.
/// Provides local network adapter functionality for zero-signal environments.
class BluetoothMeshSyncService {
  static BluetoothMeshSyncService? _instance;

  final LocalDatabaseService _databaseService;
  final _broadcastController =
      StreamController<List<MeshSyncPayload>>.broadcast();
  final _ingestionController = StreamController<MeshSyncPayload>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  String _deviceId = '';
  Timer? _discoveryTimer;
  bool _isInitialized = false;
  bool _isPolling = false;

  // Track received record hashes to prevent duplicate processing
  final Set<String> _receivedRecordSignatures = {};

  // Callbacks for HUD integration
  OnMeshDataReceived? _onDataReceived;
  OnMeshBroadcast? _onBroadcast;

  // List of tables to sync
  static const List<String> _syncTables = [
    'carcass_records',
    'invoices',
    'bookings',
    'outfitter_packages',
  ];

  BluetoothMeshSyncService._internal({LocalDatabaseService? databaseService})
    : _databaseService = databaseService ?? LocalDatabaseService.instance;

  /// Gets the singleton instance of the BluetoothMeshSyncService.
  static BluetoothMeshSyncService get instance {
    _instance ??= BluetoothMeshSyncService._internal();
    return _instance!;
  }

  /// Gets the unique device identifier for this device.
  String get deviceId => _deviceId;

  /// Stream of broadcast payloads ready for mesh transmission.
  Stream<List<MeshSyncPayload>> get broadcastStream =>
      _broadcastController.stream;

  /// Stream of received mesh payloads.
  Stream<MeshSyncPayload> get ingestionStream => _ingestionController.stream;

  /// Stream of active peer count for HUD dashboard.
  Stream<int> get peerCountStream => _peerCountController.stream;

  /// Current active peer count.
  int _activePeerCount = 0;
  int get activePeerCount => _activePeerCount;

  /// Initializes the service with a device identifier.
  Future<void> initialize({String? deviceId}) async {
    if (_isInitialized) return;

    if (deviceId != null) {
      _deviceId = deviceId;
    } else {
      _deviceId = await _getOrCreateDeviceId();
    }

    _isInitialized = true;
    debugPrint(
      'BluetoothMeshSyncService: Initialized with device ID $_deviceId',
    );
  }

  /// Retrieves or creates a persistent device identifier.
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var storedId = prefs.getString('mesh_device_id');

    if (storedId == null) {
      // Generate a unique device ID based on timestamp and random
      storedId =
          'dev_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomSuffix()}';
      await prefs.setString('mesh_device_id', storedId);
    }

    return storedId;
  }

  /// Generates a random suffix for device ID uniqueness.
  String _generateRandomSuffix() {
    final random = DateTime.now().microsecondsSinceEpoch % 100000;
    return random.toString().padLeft(5, '0');
  }

  /// Sets callbacks for mesh data events (HUD integration).
  void setCallbacks({
    OnMeshDataReceived? onDataReceived,
    OnMeshBroadcast? onBroadcast,
  }) {
    _onDataReceived = onDataReceived;
    _onBroadcast = onBroadcast;
  }

  /// Starts the discovery polling loop for broadcasting dirty records.
  /// [intervalSeconds] determines the polling frequency (default: 15).
  void startDiscoveryPolling({int intervalSeconds = 15}) {
    if (_isPolling) return;

    _isPolling = true;
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => broadcastLocalDirtyRecords(),
    );

    // Immediate initial broadcast
    broadcastLocalDirtyRecords();
    debugPrint(
      'BluetoothMeshSyncService: Discovery polling started (interval: ${intervalSeconds}s)',
    );
  }

  /// Stops the discovery polling loop.
  void stopDiscoveryPolling() {
    _isPolling = false;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    debugPrint('BluetoothMeshSyncService: Discovery polling stopped');
  }

  /// Scans local database for dirty records and broadcasts them as mesh packets.
  /// Simulates BLE advertising packet push for each dirty record.
  Future<List<MeshSyncPayload>> broadcastLocalDirtyRecords() async {
    if (!_isInitialized) {
      await initialize();
    }

    final List<MeshSyncPayload> payloads = [];

    try {
      final db = await _databaseService.database;

      for (final tableName in _syncTables) {
        final dirtyRecords = await _getPendingRecordsFromTable(db, tableName);

        for (final record in dirtyRecords) {
          final payload = MeshSyncPayload(
            senderDeviceId: _deviceId,
            targetTable: tableName,
            recordId: record.recordId,
            payloadJsonString: jsonEncode(record.data),
            timestamp: record.lastModified,
          );

          payloads.add(payload);

          // Simulate BLE advertising packet push
          _simulateBleAdvertisementPush(payload);
        }
      }

      if (payloads.isNotEmpty) {
        _broadcastController.add(payloads);
        _onBroadcast?.call(payloads);
        debugPrint(
          'BluetoothMeshSyncService: Broadcast ${payloads.length} dirty records',
        );
      }
    } catch (e) {
      debugPrint(
        'BluetoothMeshSyncService: Error broadcasting dirty records: $e',
      );
    }

    return payloads;
  }

  /// Retrieves pending (dirty) records from a specific table.
  Future<List<PendingRecord>> _getPendingRecordsFromTable(
    Database db,
    String tableName,
  ) async {
    final List<PendingRecord> records = [];

    try {
      final result = await db.query(
        tableName,
        where: 'isDirty = ?',
        whereArgs: [1],
      );

      for (final row in result) {
        final recordIdIndex = row.keys.toList().indexOf('id');
        final int recordId;

        if (recordIdIndex >= 0 &&
            row.values.elementAt(recordIdIndex) is String) {
          // Convert string ID to int hash for compatibility
          recordId = row.values.elementAt(recordIdIndex).hashCode;
        } else {
          // Find auto-increment id column
          final idIndex = row.keys.toList().indexOf('id');
          if (idIndex >= 0) {
            final idValue = row.values.elementAt(idIndex);
            recordId = idValue is int ? idValue : idValue.hashCode;
          } else {
            continue;
          }
        }

        // Get last modified timestamp
        DateTime lastModified = DateTime.now();
        final updatedAtIndex = row.keys.toList().indexOf('updatedAt');
        final createdAtIndex = row.keys.toList().indexOf('createdAt');

        if (updatedAtIndex >= 0) {
          final updatedAt = row.values.elementAt(updatedAtIndex);
          if (updatedAt != null) {
            lastModified =
                DateTime.tryParse(updatedAt.toString()) ?? DateTime.now();
          }
        } else if (createdAtIndex >= 0) {
          final createdAt = row.values.elementAt(createdAtIndex);
          if (createdAt != null) {
            lastModified =
                DateTime.tryParse(createdAt.toString()) ?? DateTime.now();
          }
        }

        // Build record data (excluding isDirty flag)
        final recordData = Map<String, dynamic>.from(row);
        recordData.remove('isDirty');

        records.add(
          PendingRecord(
            tableName: tableName,
            recordId: recordId,
            data: recordData,
            lastModified: lastModified,
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'BluetoothMeshSyncService: Error querying table $tableName: $e',
      );
    }

    return records;
  }

  /// Simulates a BLE advertising packet push.
  /// In production, this would interface with actual BLE stack.
  void _simulateBleAdvertisementPush(MeshSyncPayload payload) {
    debugPrint(
      'BluetoothMeshSyncService: [BLE ADVERT] Sending packet for ${payload.targetTable} record ${payload.recordId}',
    );
  }

  /// Processes an incoming mesh payload from a peer device.
  /// Implements merge logic: only insert if record doesn't exist or is older.
  Future<bool> receiveIncomingMeshPayload(String packetJson) async {
    try {
      final payload = MeshSyncPayload.deserialize(packetJson);

      // Skip own broadcasts (loop prevention)
      if (payload.senderDeviceId == _deviceId) {
        debugPrint(
          'BluetoothMeshSyncService: Skipping own broadcast from $_deviceId',
        );
        return false;
      }

      // Check for duplicate record signature
      final signature = _generateRecordSignature(payload);
      if (_receivedRecordSignatures.contains(signature)) {
        debugPrint(
          'BluetoothMeshSyncService: Duplicate record detected, ignoring',
        );
        return false;
      }

      // Add to received signatures (limit size to prevent memory issues)
      if (_receivedRecordSignatures.length > 1000) {
        _receivedRecordSignatures.clear();
      }
      _receivedRecordSignatures.add(signature);

      // Process the incoming payload
      final isNewInsert = await _mergePayloadIntoLocalDb(payload);

      // Notify listeners
      _ingestionController.add(payload);
      _onDataReceived?.call(payload, isNewInsert);

      // Increment peer count for HUD
      _incrementPeerCount();

      debugPrint(
        'BluetoothMeshSyncService: Received payload for ${payload.targetTable} record ${payload.recordId}',
      );

      return true;
    } catch (e) {
      debugPrint(
        'BluetoothMeshSyncService: Error processing incoming payload: $e',
      );
      return false;
    }
  }

  /// Generates a unique signature for a record to detect duplicates.
  String _generateRecordSignature(MeshSyncPayload payload) {
    return '${payload.senderDeviceId}_${payload.targetTable}_${payload.recordId}_${payload.timestamp.millisecondsSinceEpoch}';
  }

  /// Merges an incoming payload into the local database.
  /// Returns true if a new record was inserted, false if skipped or updated.
  Future<bool> _mergePayloadIntoLocalDb(MeshSyncPayload payload) async {
    try {
      final db = await _databaseService.database;
      final tableName = payload.targetTable;

      // Check if table exists and record exists
      final existingRecords = await db.query(
        tableName,
        where: 'id = ?',
        whereArgs: [payload.recordId.toString()],
      );

      bool isNewInsert = existingRecords.isEmpty;

      if (isNewInsert) {
        // Insert new record with isDirty = 1 (needs sync to cloud)
        final recordData =
            jsonDecode(payload.payloadJsonString) as Map<String, dynamic>;
        recordData['id'] = payload.recordId.toString();
        recordData['isDirty'] = 1;

        await db.insert(
          tableName,
          recordData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        debugPrint(
          'BluetoothMeshSyncService: Inserted new record ${payload.recordId} in $tableName',
        );
      } else {
        // Check timestamp - only update if incoming is newer
        final existingRecord = existingRecords.first;
        DateTime existingTimestamp = DateTime.now();

        final updatedAtIndex = existingRecord.keys.toList().indexOf(
          'updatedAt',
        );
        final createdAtIndex = existingRecord.keys.toList().indexOf(
          'createdAt',
        );

        if (updatedAtIndex >= 0) {
          final updatedAt = existingRecord.values.elementAt(updatedAtIndex);
          if (updatedAt != null) {
            existingTimestamp =
                DateTime.tryParse(updatedAt.toString()) ?? DateTime.now();
          }
        } else if (createdAtIndex >= 0) {
          final createdAt = existingRecord.values.elementAt(createdAtIndex);
          if (createdAt != null) {
            existingTimestamp =
                DateTime.tryParse(createdAt.toString()) ?? DateTime.now();
          }
        }

        if (payload.timestamp.isAfter(existingTimestamp)) {
          // Update existing record with newer data
          final recordData =
              jsonDecode(payload.payloadJsonString) as Map<String, dynamic>;
          recordData['id'] = payload.recordId.toString();
          recordData['isDirty'] = 1; // Mark as dirty for cloud sync

          await db.update(
            tableName,
            recordData,
            where: 'id = ?',
            whereArgs: [payload.recordId.toString()],
          );

          debugPrint(
            'BluetoothMeshSyncService: Updated record ${payload.recordId} in $tableName (newer data)',
          );
        } else {
          debugPrint(
            'BluetoothMeshSyncService: Skipped record ${payload.recordId} (existing data is newer or equal)',
          );
        }
      }

      return isNewInsert;
    } catch (e) {
      debugPrint(
        'BluetoothMeshSyncService: Error merging payload into local DB: $e',
      );
      return false;
    }
  }

  /// Increments the active peer count for HUD dashboard integration.
  void _incrementPeerCount() {
    _activePeerCount++;
    _peerCountController.add(_activePeerCount);
  }

  /// Resets the peer count (call after sync cycle completes).
  void resetPeerCount() {
    _activePeerCount = 0;
    _peerCountController.add(_activePeerCount);
  }

  /// Gets all pending (dirty) records from the local database.
  /// Provides access for testing and verification.
  Future<List<PendingRecord>> getPendingRecords() async {
    final List<PendingRecord> allRecords = [];

    try {
      final db = await _databaseService.database;

      for (final tableName in _syncTables) {
        final records = await _getPendingRecordsFromTable(db, tableName);
        allRecords.addAll(records);
      }
    } catch (e) {
      debugPrint('BluetoothMeshSyncService: Error getting pending records: $e');
    }

    return allRecords;
  }

  /// Clears the received record signature cache.
  void clearSignatureCache() {
    _receivedRecordSignatures.clear();
    debugPrint('BluetoothMeshSyncService: Cleared signature cache');
  }

  /// Disposes of service resources.
  void dispose() {
    stopDiscoveryPolling();
    _broadcastController.close();
    _ingestionController.close();
    _peerCountController.close();
    _instance = null;
  }
}
