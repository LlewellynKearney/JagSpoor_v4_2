import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/offline_sync_queue.dart';
import '../services/advanced_tactical_service.dart';
import 'hunter_scaffold.dart';

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
  Timer? _pressureTimer;
  void _simulatePressureUpdates() {
    // Update pressure every 5 seconds to simulate sensor readings
    _pressureTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
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

  /// Best-effort queue-size read: an offline-persistence failure (e.g. no
  /// sqflite database factory on web / an uninitialized test env or a cold
  /// launch) is swallowed — the HUD simply shows the previous count.
  Future<void> _loadQueueSize() async {
    try {
      final queueSize = await OfflineSyncQueue.instance.getQueueSize();
      if (mounted) {
        setState(() => _pendingQueueCount = queueSize);
      }
    } catch (_) {
      // Persistence unavailable — leave the displayed count unchanged.
    }
  }

  @override
  void dispose() {
    _pressureTimer?.cancel();
    _connectivitySubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the effective mode from the ambient theme (the MaterialApp
    // light/dark theme pair driven by ThemeController), so the banner picks
    // high-contrast colors in both Day and Night without a hardcoded palette.
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Connection Status Bar
        if (_isOnline)
          _buildOnlineBar(isDarkMode)
        else
          _buildOfflineBar(isDarkMode),

        // AI Game Movement Activity Forecaster Row
        _buildGameMovementForecaster(),
      ],
    );
  }

  /// The online "CLOUD SYNC TELEMETRY ONLINE" banner.
  ///
  /// Mode-aware solid wrapper so the banner never blends into the Solitary
  /// Acacia background photo/scrim: in Light Mode a warm cream/off-white
  /// card surface with a defined deep-green border + deep espresso text; in
  /// Dark Mode a solid very-dark olive surface with a bright-green border.
  /// The SYNCED pill is likewise solid high-contrast in both modes.
  Widget _buildOnlineBar(bool isDarkMode) {
    final surfaceColor =
        isDarkMode ? const Color(0xFF1E3011) : HunterUi.lightCard;
    final borderColor =
        isDarkMode ? const Color(0xFF7CB342) : const Color(0xFF4F6E33);
    final titleColor =
        isDarkMode ? const Color(0xFFCDEBA8) : HunterUi.lightTitle;
    final iconColor =
        isDarkMode ? const Color(0xFF7CB342) : const Color(0xFF2E4A1C);
    final pillSurface =
        isDarkMode ? const Color(0xFF7CB342) : const Color(0xFF2E4A1C);
    final pillContent =
        isDarkMode ? const Color(0xFF18250A) : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border.all(color: borderColor, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.5 : 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.satellite_alt,
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'CLOUD SYNC TELEMETRY ONLINE',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: titleColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: pillSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_done, color: pillContent, size: 14),
                const SizedBox(width: 4),
                Text(
                  'SYNCED',
                  style: TextStyle(
                    color: pillContent,
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


  /// The offline "CELL DISCONNECTED" banner — the same status component in
  /// its disconnected state. It gets the same mode-aware solid wrapper
  /// treatment as the online bar so it stays high-contrast in both modes.
  Widget _buildOfflineBar(bool isDarkMode) {
    final gradientColors = isDarkMode
        ? [const Color(0xFF8B0000), Colors.amber.shade800]
        : [const Color(0xFFF7E3D7), const Color(0xFFEFD3C2)];
    final borderColor =
        isDarkMode ? const Color(0xFFFFB74D) : const Color(0xFF8B1A1A);
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF7A1410);
    final iconColor = isDarkMode ? Colors.white : const Color(0xFF8B1A1A);
    final dotColor = isDarkMode ? Colors.white : const Color(0xFFB71C1C);
    final queueSurface = isDarkMode
        ? Colors.black.withValues(alpha: 0.3)
        : const Color(0xFF3E2118);
    final queueIconColor =
        isDarkMode ? Colors.amber.shade200 : Colors.amber.shade300;
    final queueTextColor =
        isDarkMode ? Colors.amber.shade100 : Colors.amber.shade200;
    final waitSurface =
        isDarkMode ? Colors.red.shade700 : const Color(0xFF8B1A1A);
    final waitTextColor = Colors.white;
    final shadowColor = isDarkMode
        ? Colors.amber.withValues(alpha: 0.4)
        : Colors.red.withValues(alpha: 0.25);

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
                colors: gradientColors,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border.all(color: borderColor, width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
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
                    Icon(Icons.blur_on, color: iconColor, size: 18),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'CELL DISCONNECTED - P2P BLUETOOTH MESH ACTIVE',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildPulsingDot(dotColor),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: queueSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sync_disabled,
                        color: queueIconColor,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Offline Sync Queue: $_pendingQueueCount pending',
                        style: TextStyle(
                          color: queueTextColor,
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
                            color: waitSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'WAIT',
                            style: TextStyle(
                              color: waitTextColor,
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

  Widget _buildPulsingDot(Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: (value * 0.8) + 0.2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: value * 0.5),
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
