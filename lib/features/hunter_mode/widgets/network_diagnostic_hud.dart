import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/offline_sync_queue.dart';

class NetworkDiagnosticHud extends StatefulWidget {
  const NetworkDiagnosticHud({super.key});

  @override
  State<NetworkDiagnosticHud> createState() => _NetworkDiagnosticHudState();
}

class _NetworkDiagnosticHudState extends State<NetworkDiagnosticHud>
    with SingleTickerProviderStateMixin {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  bool _isPulsing = false;
  int _pendingQueueCount = 0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _loadQueueSize();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _pulseController.repeat(reverse: true);
  }

  void _initConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _updateConnectionStatus(results);
      },
      onError: (error) {
        setState(() => _isOnline = false);
      },
    );
    
    // Check initial connectivity
    Connectivity().checkConnectivity().then(_updateConnectionStatus);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final isConnected = results.isNotEmpty && 
        !results.contains(ConnectivityResult.none);
    
    setState(() {
      _isOnline = isConnected;
      _isPulsing = !isConnected;
    });
    
    _loadQueueSize();
  }

  Future<void> _loadQueueSize() async {
    final queueSize = await OfflineSyncQueue.instance.getQueueSize();
    if (mounted) {
      setState(() => _pendingQueueCount = queueSize);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline) {
      return _buildOnlineBar();
    } else {
      return _buildOfflineBar();
    }
  }

  Widget _buildOnlineBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2E4A1C), // Dark Olive Green
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.satellite_alt,
            color: Color(0xFF7CB342), // Light green
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            'CLOUD SYNC TELEMETRY ONLINE',
            style: TextStyle(
              color: Colors.green.shade200,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_done, color: Colors.green.shade300, size: 14),
                const SizedBox(width: 4),
                Text(
                  'SYNCED',
                  style: TextStyle(
                    color: Colors.green.shade300,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBar() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _isPulsing ? _pulseAnimation.value : 1.0,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF8B0000), // Dark Crimson
                  Colors.amber.shade800,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.blur_on,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'CELL DISCONNECTED - P2P BLUETOOTH MESH ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildPulsingDot(),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sync_disabled,
                        color: Colors.amber.shade200,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Offline Sync Queue: $_pendingQueueCount pending',
                        style: TextStyle(
                          color: Colors.amber.shade100,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_pendingQueueCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'WAIT',
                            style: TextStyle(
                              color: Colors.red.shade100,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPulsingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: (value * 0.8) + 0.2),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: value * 0.5),
                blurRadius: 4 * value,
                spreadRadius: 2 * value,
              ),
            ],
          ),
        );
      },
      onEnd: () {
        if (mounted && !_isOnline) {
          setState(() {});
        }
      },
    );
  }
}
