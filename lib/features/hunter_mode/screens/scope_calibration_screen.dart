import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../services/ballistic_solver_service.dart';

class ScopeCalibrationScreen extends StatefulWidget {
  final ThemeController theme;

  const ScopeCalibrationScreen({super.key, required this.theme});

  @override
  State<ScopeCalibrationScreen> createState() => _ScopeCalibrationScreenState();
}

class _ScopeCalibrationScreenState extends State<ScopeCalibrationScreen>
    with SingleTickerProviderStateMixin {
  // Ballistic solver service
  final BallisticSolverService _ballisticSolver = BallisticSolverService.instance;

  // Rifle profile selection
  String _selectedRifleProfile = '.308 Win';
  double _muzzleVelocityFps = 2700.0;
  double _ballisticCoefficient = 0.45;
  double _scopeHeightInches = 1.8;
  double _turretClickValue = 0.25; // 1/4 MOA

  // Shot parameters
  double _distanceYards = 200.0;
  double _angleDegrees = 0.0;
  double _barometricPressureHpa = 1013.25;

  // Calculated results
  Map<String, dynamic>? _calculationResults;
  bool _isCalculating = false;

  // Rangefinder memory
  double? _lastRangefinderDistance;
  double? _lastRangefinderAngle;

  // Animation
  late AnimationController _dialAnimationController;
  late Animation<double> _dialRotationAnimation;

  // Predefined rifle profiles
  static const Map<String, Map<String, double>> _rifleProfiles = {
    '.308 Win': {'muzzleVelocity': 2700.0, 'ballisticCoefficient': 0.45},
    '6.5 Creedmoor': {'muzzleVelocity': 2900.0, 'ballisticCoefficient': 0.52},
    '30-06 Springfield': {'muzzleVelocity': 2800.0, 'ballisticCoefficient': 0.48},
    '.300 Win Mag': {'muzzleVelocity': 3100.0, 'ballisticCoefficient': 0.55},
    '.243 Win': {'muzzleVelocity': 3100.0, 'ballisticCoefficient': 0.40},
    '.270 Win': {'muzzleVelocity': 3060.0, 'ballisticCoefficient': 0.46},
  };

  @override
  void initState() {
    super.initState();
    _dialAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _dialRotationAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _dialAnimationController, curve: Curves.easeOut),
    );
    _calculateTrajectory();
  }

  @override
  void dispose() {
    _dialAnimationController.dispose();
    super.dispose();
  }

  void _selectRifleProfile(String profile) {
    final profileData = _rifleProfiles[profile];
    if (profileData != null) {
      setState(() {
        _selectedRifleProfile = profile;
        _muzzleVelocityFps = profileData['muzzleVelocity']!;
        _ballisticCoefficient = profileData['ballisticCoefficient']!;
      });
      _calculateTrajectory();
    }
  }

  void _calculateTrajectory() {
    setState(() {
      _isCalculating = true;
    });

    // Simulate async calculation
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;

      final results = _ballisticSolver.calculateScopeAdjustments(
        distanceYards: _distanceYards,
        angleDegrees: _angleDegrees,
        muzzleVelocityFps: _muzzleVelocityFps,
        ballisticCoefficient: _ballisticCoefficient,
        scopeHeightInches: _scopeHeightInches,
        turretClickValue: _turretClickValue,
        barometricPressureHpa: _barometricPressureHpa,
      );

      setState(() {
        _calculationResults = results;
        _isCalculating = false;
      });

      // Animate dial
      _dialAnimationController.forward(from: 0);
    });
  }

  void _pullLastRangefinderTarget() {
    // In production, this would pull from AdvancedTacticalService memory
    // For demo, simulate with random values
    setState(() {
      _lastRangefinderDistance = 250.0 + (DateTime.now().millisecond % 200);
      _lastRangefinderAngle = (DateTime.now().millisecond % 30) - 15.0;
      _distanceYards = _lastRangefinderDistance!;
      _angleDegrees = _lastRangefinderAngle!;
    });
    _calculateTrajectory();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🎯 Target pulled: ${_distanceYards.toStringAsFixed(0)}y @ ${_angleDegrees.toStringAsFixed(1)}°',
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1512), // Walnut dark background
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2520),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.gps_fixed, color: Colors.orange, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'BALLISTIC SCOPE CALIBRATION',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.orange),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Upper Row: Rifle Profile & Ballistic Parameters
          _buildUpperInputPanel(theme),

          // Middle Panel: Visual Turret Dial
          Expanded(
            child: _buildTurretDialPanel(theme),
          ),

          // Bottom Row: Quick Actions
          _buildBottomActionRow(theme),
        ],
      ),
    );
  }

  Widget _buildUpperInputPanel(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2D2520),
            const Color(0xFF1A1512),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(
            color: Colors.orange.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Rifle Profile Dropdown
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1512),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedRifleProfile,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2D2520),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.orange),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    items: _rifleProfiles.keys.map((profile) {
                      return DropdownMenuItem(
                        value: profile,
                        child: Row(
                          children: [
                            const Icon(Icons.radio_button_checked, 
                                color: Colors.orange, size: 16),
                            const SizedBox(width: 8),
                            Text(profile),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) _selectRifleProfile(value);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Ballistic Parameters Row
          Row(
            children: [
              // Muzzle Velocity
              Expanded(
                child: _buildInputField(
                  label: 'MV (fps)',
                  value: _muzzleVelocityFps.toStringAsFixed(0),
                  onChanged: (v) {
                    final val = double.tryParse(v);
                    if (val != null) {
                      setState(() {
                        _muzzleVelocityFps = val.clamp(500, 5000);
                      });
                      _calculateTrajectory();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Ballistic Coefficient
              Expanded(
                child: _buildInputField(
                  label: 'BC',
                  value: _ballisticCoefficient.toStringAsFixed(2),
                  onChanged: (v) {
                    final val = double.tryParse(v);
                    if (val != null) {
                      setState(() {
                        _ballisticCoefficient = val.clamp(0.05, 2.0);
                      });
                      _calculateTrajectory();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Distance
              Expanded(
                child: _buildInputField(
                  label: 'Yards',
                  value: _distanceYards.toStringAsFixed(0),
                  onChanged: (v) {
                    final val = double.tryParse(v);
                    if (val != null) {
                      setState(() {
                        _distanceYards = val.clamp(50, 2000);
                      });
                      _calculateTrajectory();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Angle
              Expanded(
                child: _buildInputField(
                  label: 'Angle°',
                  value: _angleDegrees.toStringAsFixed(1),
                  onChanged: (v) {
                    final val = double.tryParse(v);
                    if (val != null) {
                      setState(() {
                        _angleDegrees = val.clamp(-90, 90);
                      });
                      _calculateTrajectory();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String value,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.orange.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.-]')),
          ],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            filled: true,
            fillColor: const Color(0xFF1A1512),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: Colors.orange.withValues(alpha: 0.4),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: Colors.orange.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Colors.orange),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTurretDialPanel(ThemeController theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            const Color(0xFF2D2520),
            const Color(0xFF1A1512),
          ],
          center: Alignment.center,
          radius: 1.0,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Main Turret Display
          AnimatedBuilder(
            animation: _dialRotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _dialRotationAnimation.value * math.pi / 6,
                child: child,
              );
            },
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.orange.withValues(alpha: 0.2),
                    Colors.orange.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: Colors.orange,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Turret markings
                  ...List.generate(12, (i) {
                    return Transform.rotate(
                      angle: i * math.pi / 6,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 2,
                          height: 15,
                          color: Colors.orange.withValues(alpha: 0.8),
                        ),
                      ),
                    );
                  }),
                  // Center display
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _calculationResults?['isDropPositive'] == true
                            ? 'DIAL UP'
                            : 'HOLD',
                        style: TextStyle(
                          color: Colors.orange.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isCalculating
                            ? '---'
                            : '${_calculationResults?['clicksToDial'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 4,
                        ),
                      ),
                      Text(
                        'CLICKS',
                        style: TextStyle(
                          color: Colors.orange.withValues(alpha: 0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // MOA/MRAD Display
          if (_calculationResults != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMetricDisplay(
                    'MOA',
                    '${_calculationResults?['totalMOA'] ?? '0.00'}',
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                  _buildMetricDisplay(
                    'MRAD',
                    '${_calculationResults?['totalMRAD'] ?? '0.00'}',
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                  _buildMetricDisplay(
                    'DROP',
                    '${_calculationResults?['dropInches'] ?? '0.00'}',
                    suffix: '"',
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Barometric Correction Bar
          if (_calculationResults != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.speed,
                    color: Colors.orange.withValues(alpha: 0.8),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Barometric Correction Active: ${_calculationResults?['barometricPressureHpa']?.toStringAsFixed(1) ?? '1013.25'} hPa',
                    style: TextStyle(
                      color: Colors.orange.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.straighten,
                    color: Colors.orange.withValues(alpha: 0.8),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'True Slant Range: ${_calculationResults?['distanceYards']?.toStringAsFixed(0) ?? '0'}y',
                    style: TextStyle(
                      color: Colors.orange.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          if (_calculationResults?['isUphillShot'] == true) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.trending_up, color: Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'UPHILL COMPENSATION ACTIVE',
                    style: TextStyle(
                      color: Colors.amber.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricDisplay(String label, String value, {String suffix = ''}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.orange.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$value$suffix',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionRow(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1512),
            const Color(0xFF2D2520),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: Colors.orange.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Quick Sync Button
          Expanded(
            child: GestureDetector(
              onTap: _pullLastRangefinderTarget,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withValues(alpha: 0.3),
                      Colors.orange.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.gps_fixed,
                      color: Colors.orange,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        const Text(
                          'PULL LAST RANGEFINDER TARGET',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        if (_lastRangefinderDistance != null)
                          Text(
                            'Last: ${_lastRangefinderDistance!.toStringAsFixed(0)}y @ ${_lastRangefinderAngle!.toStringAsFixed(1)}°',
                            style: TextStyle(
                              color: Colors.orange.withValues(alpha: 0.7),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
