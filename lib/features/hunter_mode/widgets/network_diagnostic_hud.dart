import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/offline_sync_queue.dart';
import '../services/advanced_tactical_service.dart';

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

  // Barometric pressure sensor data (simulated for demo)
  double _barometricPressureHpa = 1013.25; // Default atmospheric pressure
  double _pressureDeltaLast3Hours = 0.0;
  double _movementProbability = 50.0;
  int _moonPhasePercent = 50; // Default to half moon
  bool _isMajorSolunarWindow = false;

  // Track previous pressure readings for delta calculation (simulated)
  final List<double> _pressureHistory = [
    1013.25,
    1013.0,
    1012.5,
    1012.0,
    1011.5,
    1011.0,
  ];
  static const int _pressureHistorySize = 6;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _loadQueueSize();
    _updateMoonPhase();
    _simulatePressureUpdates();

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

  // Simulates pressure sensor updates for demonstration
  void _simulatePressureUpdates() {
    // Update pressure every 5 seconds to simulate sensor readings
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Simulate small pressure fluctuations
      final fluctuation = (DateTime.now().second % 10 - 5) * 0.1;
      final newPressure = _barometricPressureHpa + fluctuation;

      _updatePressure(newPressure);
    });
  }

  void _updatePressure(double pressureHpa) {
    // Add to history for delta calculation
    _pressureHistory.add(pressureHpa);
    if (_pressureHistory.length > _pressureHistorySize) {
      _pressureHistory.removeAt(0);
    }

    // Calculate pressure delta over last ~30 minutes
    if (_pressureHistory.length >= 2) {
      _pressureDeltaLast3Hours = _pressureHistory.last - _pressureHistory.first;
    }

    setState(() {
      _barometricPressureHpa = pressureHpa;
      _updateMovementProbability();
    });
  }

  void _updateMovementProbability() {
    // Simulate moon phase (in production, this would come from actual lunar calculations)
    // Simulate solunar windows (in production, this would be calculated based on location/time)
    final hour = DateTime.now().hour;
    _isMajorSolunarWindow =
        (hour >= 5 && hour <= 7) || (hour >= 17 && hour <= 19);

    _movementProbability = AdvancedTacticalService.instance
        .calculateMovementProbability(
          barometricPressureHpa: _barometricPressureHpa,
          pressureDeltaLast3Hours: _pressureDeltaLast3Hours,
          moonPhasePercent: _moonPhasePercent,
          isMajorSolunarWindow: _isMajorSolunarWindow,
        );
  }

  void _updateMoonPhase() {
    // Calculate approximate moon phase based on current date
    // Using a simplified calculation (0% = new moon, 50% = full moon, 100% = new moon)
    final now = DateTime.now();
    final daysSinceNewMoon =
        now.difference(DateTime(2000, 1, 6)).inDays % 29.53;
    _moonPhasePercent = ((daysSinceNewMoon / 29.53) * 100).round().clamp(
      0,
      100,
    );
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final isConnected =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Connection Status Bar
        if (_isOnline) _buildOnlineBar() else _buildOfflineBar(),

        // AI Game Movement Activity Forecaster Row
        _buildGameMovementForecaster(),
      ],
    );
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
                    const Icon(Icons.blur_on, color: Colors.white, size: 18),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
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

  /// Builds the AI Game Movement Activity Forecaster row.
  /// Displays real-time movement probability based on barometric pressure and solunar data.
  Widget _buildGameMovementForecaster() {
    // Determine activity level label and color based on probability
    String activityLabel;
    Color activityColor;
    String activityIcon;

    if (_movementProbability >= 80) {
      activityLabel = 'PEAK MOVEMENT WINDOW';
      activityColor = Colors.green;
      activityIcon = '🔥';
    } else if (_movementProbability >= 65) {
      activityLabel = 'GOOD ACTIVITY';
      activityColor = Colors.lightGreen;
      activityIcon = '🦌';
    } else if (_movementProbability >= 50) {
      activityLabel = 'MODERATE';
      activityColor = Colors.amber;
      activityIcon = '🦌';
    } else if (_movementProbability >= 35) {
      activityLabel = 'LOW ACTIVITY';
      activityColor = Colors.orange;
      activityIcon = '💤';
    } else {
      activityLabel = 'POOR CONDITIONS';
      activityColor = Colors.red;
      activityIcon = '❄️';
    }

    // Add weather condition indicator
    String weatherCondition = '';
    if (_pressureDeltaLast3Hours < -2.0) {
      weatherCondition = 'INCOMING WEATHER FRONT';
    } else if (_pressureDeltaLast3Hours < -1.0) {
      weatherCondition = 'DROPPING PRESSURE';
    } else if (_pressureDeltaLast3Hours > 1.0) {
      weatherCondition = 'PRESSURE RISING';
    } else {
      weatherCondition = 'STABLE CONDITIONS';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            activityColor.withValues(alpha: 0.15),
            activityColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          top: BorderSide(
            color: activityColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // First row: Main forecast
          Row(
            children: [
              // Deer icon
              Text(activityIcon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),

              // Main forecast text
              Expanded(
                child: Text(
                  'AI GAME MOVEMENT ACTIVITY FORECASTER: ',
                  style: TextStyle(
                    color: Color(0xFF2E3D2F),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: activityColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_movementProbability.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: Color(0xFF2E3D2F),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: activityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '($activityLabel)',
                  style: TextStyle(
                    color: Color(0xFF2E3D2F),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Second row: Telemetry data
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Pressure info
                Icon(Icons.speed, color: Color(0xFF2E3D2F), size: 12),
                const SizedBox(width: 4),
                Text(
                  '${_barometricPressureHpa.toStringAsFixed(1)} hPa',
                  style: TextStyle(color: Color(0xFF2E3D2F), fontSize: 11),
                ),
                const SizedBox(width: 8),
                // Weather condition
                Icon(
                  _pressureDeltaLast3Hours < 0
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: Color(0xFF2E3D2F),
                  size: 12,
                ),
                const SizedBox(width: 2),
                Text(
                  weatherCondition,
                  style: TextStyle(color: Color(0xFF2E3D2F), fontSize: 11),
                ),
                const SizedBox(width: 8),
                // Moon phase indicator
                Icon(
                  Icons.nightlight_round,
                  color: Color(0xFF2E3D2F),
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  'Moon $_moonPhasePercent%',
                  style: TextStyle(color: Color(0xFF2E3D2F), fontSize: 11),
                ),
                // Solunar indicator
                if (_isMajorSolunarWindow) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: Color(0xFF2E3D2F),
                          size: 10,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'SOLUNAR',
                          style: TextStyle(
                            color: Color(0xFF2E3D2F),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
