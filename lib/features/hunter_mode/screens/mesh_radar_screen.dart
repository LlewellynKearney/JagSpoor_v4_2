import 'package:flutter/material.dart';
import '../services/bluetooth_mesh_sync.dart';

class MeshRadarScreen extends StatefulWidget {
  const MeshRadarScreen({super.key});

  @override
  State<MeshRadarScreen> createState() => _MeshRadarScreenState();
}

class _MeshRadarScreenState extends State<MeshRadarScreen> {
  final BluetoothMeshSync _meshSync = BluetoothMeshSync();
  bool _isMeshActive = false;
  final Map<String, Map<String, dynamic>> _discoveredPeers = {};

  @override
  void dispose() {
    _meshSync.stopMeshEngine();
    super.dispose();
  }

  void _toggleMesh(bool value) async {
    setState(() {
      _isMeshActive = value;
    });

    if (_isMeshActive) {
      // Begin broadcasting own simulated position and listen for others
      await _meshSync.startBroadcasting(
        hunterName:
            "Hunter_${DateTime.now().millisecondsSinceEpoch.toString().substring(9)}",
        latitude: -26.5641,
        longitude: 28.0134,
        lastHarvestTag: "NONE",
      );

      _meshSync.startMeshDiscovery((peerName, data) {
        setState(() {
          // Store peer reference data locally in-memory
          _discoveredPeers[peerName] = {
            'lastSeen': DateTime.now(),
            'lat': data['lat'] ?? 0.0,
            'lon': data['lon'] ?? 0.0,
            'tag': data['tag'] ?? 'N/A',
          };
        });
      });
    } else {
      _meshSync.stopMeshEngine();
      setState(() {
        _discoveredPeers.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Off-Grid Team Radar'),
        actions: [
          Switch(
            value: _isMeshActive,
            onChanged: _toggleMesh,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color:
                _isMeshActive
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.red.withValues(alpha: 0.2),
            child: Text(
              _isMeshActive
                  ? '📡 MESH RECEPTOR ACTIVE: Broadcasting & Discovering...'
                  : '🛑 MESH ADAPTER OFF: Offline Telemetry Disabled',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child:
                _discoveredPeers.isEmpty
                    ? const Center(
                      child: Text('No off-grid team members detected nearby.'),
                    )
                    : ListView.builder(
                      itemCount: _discoveredPeers.length,
                      itemBuilder: (context, index) {
                        String peerKey = _discoveredPeers.keys.elementAt(index);
                        var peerInfo = _discoveredPeers[peerKey];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.radar,
                              color: Colors.blueAccent,
                            ),
                            title: Text(
                              peerKey,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Lat: ${peerInfo?['lat']} | Lon: ${peerInfo?['lon']}\nLast Harvest Tag: ${peerInfo?['tag']}',
                            ),
                            trailing: const Icon(
                              Icons.bluetooth_connected,
                              color: Colors.green,
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
