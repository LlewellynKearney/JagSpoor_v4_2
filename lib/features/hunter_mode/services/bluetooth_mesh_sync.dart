import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

class BluetoothMeshSync {
  final Strategy strategy = Strategy.P2P_CLUSTER;

  // Broadcast device state data without internet or cellular connectivity
  Future<void> startBroadcasting({
    required String hunterName,
    required double latitude,
    required double longitude,
    required String lastHarvestTag,
  }) async {
    final Map<String, dynamic> metadata = {
      'lat': latitude,
      'lon': longitude,
      'tag': lastHarvestTag,
    };

    try {
      final payloadStr = jsonEncode(metadata);
      await Nearby().startAdvertising(
        '$hunterName:$payloadStr',
        strategy,
        onConnectionInitiated: (id, info) {
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {},
          );
        },
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
        serviceId: "com.jagspoor.offline_mesh",
      );
    } catch (e) {
      debugPrint("Mesh advertisement initialization failed: $e");
    }
  }

  // Listen for neighboring hunters broadcasting coordinates
  Future<void> startMeshDiscovery(
    Function(String name, Map<String, dynamic> data) onPeerFound,
  ) async {
    try {
      await Nearby().startDiscovery(
        "JagSpoor_Hunter",
        strategy,
        onEndpointFound: (id, name, serviceId) {
          // Trigger when a peer hunter asset registers nearby
          onPeerFound(name, {});
        },
        onEndpointLost: (id) {},
        serviceId: "com.jagspoor.offline_mesh",
      );
    } catch (e) {
      debugPrint("Mesh cluster discovery failed: $e");
    }
  }

  void stopMeshEngine() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
  }
}
