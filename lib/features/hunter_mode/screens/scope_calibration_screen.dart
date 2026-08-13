import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../../core/utils/measurement_formatter.dart';
import '../../ballistics/data/inventory_bridge.dart';
import '../../ballistics/data/models/optic_profile.dart';
import '../../shared/utils/firebase_diagnostic.dart';
import '../../ballistics/data/models/rifle_profile.dart';
import '../screens/shot_group_analyzer_screen.dart';
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
  final BallisticSolverService _ballisticSolver =
      BallisticSolverService.instance;

  // Digital Firearm Safe integration
  final InventoryBridge _inventoryBridge = InventoryBridge();

  // Active rifle selection state - preserved across rebuilds
  RifleProfile? _selectedRifle;
  AmmoProfile? _selectedAmmo;

  // Ballistic parameters
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

  // Shot Group Analyzer state — the heavy analysis now lives in the dedicated
  // ShotGroupAnalyzerScreen; this screen only retains the last picked image to
  // pass through to it.
  dynamic _shotGroupImage;

  // Guards a single auto-link of the first safe firearm on initial stream
  // load so barrel length / scope height populate automatically without
  // requiring an explicit dropdown tap.
  bool _didAutoLink = false;

  // Animation
  late AnimationController _dialAnimationController;
  late Animation<double> _dialRotationAnimation;

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

  /// Links the scope settings to a registered Digital Firearm Safe profile
  /// and auto-populates caliber, barrel length, scope height (HOB) and turret
  /// click value from the selected firearm's stored specs.
  ///
  /// - [RifleProfile.caliber] -> bullet caliber (AI shot-group analyzer field).
  /// - [RifleProfile.optic]?.heightOverBoreInches -> scope height used by the
  ///   ballistic solver (falls back to the linked optic's default when present,
  ///   otherwise leaves the user's current value untouched).
  /// - [RifleProfile.optic]?.clickValue (or [RifleProfile.scopeClickValue]) ->
  ///   per-click turret value used by the solver.
  /// - [RifleProfile.barrelLength] is surfaced via the Linked Firearm Specs
  ///   card rendered under the selector.
  void _selectRifle(RifleProfile rifle) {
    final optic = rifle.optic;
    setState(() {
      _selectedRifle = rifle;
      // Auto-populate scope height from the linked optic's height-over-bore.
      if (optic != null) {
        _scopeHeightInches = optic.heightOverBoreInches;
      }
      // Auto-populate turret click value from the linked optic (preferred) or
      // the firearm's stored scope click value.
      _turretClickValue = optic?.clickValue ?? rifle.scopeClickValue;
    });
    _loadAmmunitionForRifle(rifle.id);
    _calculateTrajectory();
  }

  /// Compact card shown under the firearm selector that surfaces the
  /// auto-populated specs from the linked Digital Firearm Safe profile:
  /// caliber, barrel length, and scope height (height over bore).
  Widget _linkedFirearmSpecsCard(RifleProfile rifle) {
    final optic = rifle.optic;
    final hob = optic?.heightOverBoreInches ?? OpticProfile.defaults.heightOverBoreInches;
    Widget specChip(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF141915),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFE6A15C),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          specChip('CALIBER', rifle.caliber.isNotEmpty ? rifle.caliber : '--'),
          const SizedBox(width: 6),
          specChip(
            'BARREL',
            rifle.barrelLength.isNotEmpty ? rifle.barrelLength : '--',
          ),
          const SizedBox(width: 6),
          specChip('SCOPE HOB', '${hob.toStringAsFixed(2)}"'),
        ],
      ),
    );
  }

  // Helper getters for turret direction display
  bool get _isElevationUp => _calculationResults?['isDropPositive'] == true;
  
  int get _elevationClicks => ((_calculationResults?['clicksToDial'] as num?)?.abs() ?? 0).toInt();
  
  int get _windageClicks => ((_calculationResults?['windageClicks'] as num?)?.abs() ?? 0).toInt();
  
  String get _windageDirection {
    final windage = (_calculationResults?['windageMOA'] as num?)?.compareTo(0) ?? 0;
    if (windage < 0) return 'DIAL LEFT';
    if (windage > 0) return 'DIAL RIGHT';
    return 'NO WIND';
  }
  
  IconData get _windageIcon {
    final windage = (_calculationResults?['windageMOA'] as num?)?.compareTo(0) ?? 0;
    if (windage < 0) return Icons.arrow_back;
    if (windage > 0) return Icons.arrow_forward;
    return Icons.remove;
  }

  Future<void> _loadAmmunitionForRifle(String rifleId) async {
    final ammoList = await _inventoryBridge.fetchAvailableAmmunition(rifleId);
    if (mounted) {
      setState(() {
        if (ammoList.isNotEmpty) {
          _selectedAmmo = ammoList.first;
          _muzzleVelocityFps = _selectedAmmo!.velocityMs * 3.28084;
          _ballisticCoefficient = _selectedAmmo!.ballisticCoefficient;
        }
      });
      _calculateTrajectory();
    }
  }

  Future<void> _testFirebaseConnection() async {
    final diagnostic = FirebaseDiagnostic();
    final results = await diagnostic.run();
    
    if (!mounted) return;
    
    final passed = results.where((r) => r.pass).length;
    final total = results.length;
    final allPassed = passed == total;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F1C),
        title: Row(
          children: [
            Icon(
              allPassed ? Icons.check_circle : Icons.error,
              color: allPassed ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(
              allPassed ? 'Firebase OK' : 'Firebase Error',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$passed/$total checks passed',
                  style: TextStyle(
                    color: allPassed ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(),
                ...results.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    r.message,
                    style: TextStyle(
                      color: r.pass ? Colors.green : Colors.red,
                      fontSize: 12,
                    ),
                  ),
                )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(color: Color(0xFFE6A15C))),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: const Color(0xFF141915), // Matte Obsidian Charcoal
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F1C),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFE6A15C).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.gps_fixed,
                color: const Color(0xFFE6A15C),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'SCOPE CALIBRATION HUD',
              style: TextStyle(
                color: const Color(0xFFE6A15C),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showScopeInfoDialog(context),
              child: Icon(
                Icons.info_outline,
                color: const Color(0xFFE6A15C).withValues(alpha: 0.8),
                size: 20,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFE6A15C)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: SafeBottomInset.of(context)),
        child: Column(
          children: [
            // Upper Row: Rifle Profile & Ballistic Parameters
            _buildUpperInputPanel(theme),

            // AI Shot Group Analyzer
            _buildShotGroupAnalyzer(theme),

            // Middle Panel: Visual Turret Dial
            _buildTurretDialPanel(theme),
          ],
        ),
      ),
    );
  }

  // AI Shot Group Analyzer Widget
  Widget _buildShotGroupAnalyzer(ThemeController theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Color(0xFFE6A15C), size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI SHOT GROUP ANALYZER',
                style: TextStyle(
                  color: const Color(0xFFE6A15C),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Camera Capture Button — opens the calibrated analyzer (capture flow).
          GestureDetector(
            onTap: _openShotGroupAnalyzer,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFE6A15C).withValues(alpha: 0.35),
                    const Color(0xFFE6A15C).withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE6A15C), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.camera_alt, color: const Color(0xFFE6A15C), size: 24),
                  SizedBox(width: 10),
                  Text(
                    'TAKE LIVE TARGET PHOTO',
                    style: TextStyle(
                      color: const Color(0xFFE6A15C),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Image Upload Section — opens the calibrated analyzer (gallery flow).
          GestureDetector(
            onTap: _openShotGroupAnalyzer,
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF141915),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
                  style: BorderStyle.solid,
                ),
              ),
              child: _shotGroupImage != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _shotGroupImage!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 120,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6A15C).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'TAP TO RE-OPEN ANALYZER',
                              style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: const Color(0xFFE6A15C).withValues(alpha: 0.6),
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'TAP TO LOAD TARGET IMAGE',
                          style: TextStyle(
                            color: const Color(0xFFE6A15C).withValues(alpha: 0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Calibration pipeline explainer.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141915),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: const Color(0xFFE6A15C).withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tune, color: Color(0xFFE6A15C), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The calibrated analyzer auto-detects shot holes, lets you '
                    'place a 2-point scale reference (coin / 1-inch grid), mark '
                    'your point of aim, and computes true extreme spread, mean '
                    'radius, and center-of-impact offset in MOA or MIL.',
                    style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Analyze Button — opens the full calibrated analyzer.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openShotGroupAnalyzer,
              icon: const Icon(Icons.analytics, size: 18),
              label: const Text('OPEN CALIBRATED ANALYZER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE6A15C).withValues(alpha: 0.2),
                foregroundColor: const Color(0xFFE6A15C),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: const Color(0xFFE6A15C).withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpperInputPanel(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1F1C), const Color(0xFF141915)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Rifle Profile Dropdown - Live from Firearm Safe
          Row(
            children: [
              Expanded(
                child: StreamBuilder<List<RifleProfile>>(
                  stream: _inventoryBridge.watchSafeFirearms(),
                  builder: (context, snapshot) {
                    // Debug: Show connection state
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141915),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFE6A15C),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Loading firearms...',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      );
                    }

                    final rifles = snapshot.data ?? [];
                    final selectedRifle = rifles.contains(_selectedRifle)
                        ? _selectedRifle
                        : (rifles.isNotEmpty ? rifles.first : null);

                    // Auto-link the first safe firearm on initial load so
                    // caliber / barrel length / scope height populate without
                    // requiring an explicit dropdown tap.
                    if (!_didAutoLink && rifles.isNotEmpty && _selectedRifle == null) {
                      _didAutoLink = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _selectRifle(rifles.first);
                      });
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141915),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: DropdownButton<RifleProfile>(
                        value: selectedRifle,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1A1F1C),
                        underline: const SizedBox(),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Color(0xFFE6A15C),
                        ),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        hint: const Text(
                          'Select firearm from safe',
                          style: TextStyle(color: Colors.white54),
                        ),
                        items: rifles.isEmpty
                            ? [
                                const DropdownMenuItem<RifleProfile>(
                                  value: null,
                                  child: Text(
                                    'No firearms found',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                              ]
                            : rifles.map((rifle) {
                                return DropdownMenuItem<RifleProfile>(
                                  value: rifle,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.gavel, color: Color(0xFFE6A15C), size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text('${rifle.name} (${rifle.caliber})')),
                                    ],
                                  ),
                                );
                              }).toList(),
                        onChanged: (rifle) {
                          if (rifle != null) {
                            _selectRifle(rifle);
                          }
                        },
                      ),
                        ),
                        if (selectedRifle != null)
                          _linkedFirearmSpecsCard(selectedRifle),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Debug: Test Firebase Connection Button
          GestureDetector(
            onTap: _testFirebaseConnection,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bug_report, color: Colors.red, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'TEST FIREBASE',
                    style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
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
            color: const Color(0xFFE6A15C).withValues(alpha: 0.7),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            filled: true,
            fillColor: const Color(0xFF1A1512),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: const Color(0xFFE6A15C)),
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
          colors: [const Color(0xFF2D2520), const Color(0xFF1A1512)],
          center: Alignment.center,
          radius: 1.0,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE6A15C).withValues(alpha: 0.1),
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
                    const Color(0xFFE6A15C).withValues(alpha: 0.2),
                    const Color(0xFFE6A15C).withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(color: const Color(0xFFE6A15C), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
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
                          color: const Color(0xFFE6A15C).withValues(alpha: 0.8),
                        ),
                      ),
                    );
                  }),
                  // Center display with directional indicators
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Elevation direction card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141915),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isElevationUp ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: const Color(0xFFE6A15C),
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isElevationUp ? 'DIAL UP' : 'DIAL DOWN',
                                  style: const TextStyle(
                                    color: Color(0xFFE6A15C),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isCalculating ? '---' : '$_elevationClicks',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                letterSpacing: 2,
                              ),
                            ),
                            const Text(
                              'ELEVATION CLICKS',
                              style: TextStyle(
                                color: Color(0xFFE6A15C),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Windage direction card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141915),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _windageIcon,
                              color: const Color(0xFFE6A15C),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_windageDirection:',
                              style: const TextStyle(
                                color: Color(0xFFE6A15C),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_windageClicks CLICKS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
                border: Border.all(color: const Color(0xFFE6A15C).withValues(alpha: 0.35)),
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
                    color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
                  ),
                  _buildMetricDisplay(
                    'MRAD',
                    '${_calculationResults?['totalMRAD'] ?? '0.00'}',
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: const Color(0xFFE6A15C).withValues(alpha: 0.35),
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
                color: const Color(0xFFE6A15C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE6A15C).withValues(alpha: 0.35)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed, color: const Color(0xFFE6A15C), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Barometric Correction Active: ${_calculationResults?['barometricPressureHpa']?.toStringAsFixed(1) ?? '1013.25'} hPa',
                      style: const TextStyle(
                        color: const Color(0xFFE6A15C),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.straighten, color: const Color(0xFFE6A15C), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'True Slant Range: ${MeasurementFormatter.instance.formatDistanceFromYards((_calculationResults?['distanceYards'] as num?)?.toDouble())}',
                      style: const TextStyle(
                        color: const Color(0xFFE6A15C),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_calculationResults?['isUphillShot'] == true) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE6A15C).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.trending_up, color: Color(0xFFE6A15C), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'UPHILL COMPENSATION ACTIVE',
                    style: TextStyle(
                      color: const Color(0xFFE6A15C).withValues(alpha: 0.9),
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
          style: const TextStyle(
            color: Color(0xFFE6A15C),
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

  void _showScopeInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F1C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFFE6A15C).withValues(alpha: 0.5), width: 1),
        ),
        title: Row(
          children: [
            Icon(Icons.gps_fixed, color: const Color(0xFFE6A15C).withValues(alpha: 0.9), size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'AI Ballistic Calibration HUD',
                style: TextStyle(
                  color: const Color(0xFFE6A15C),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'AI BALLISTIC CALIBRATION HUD: Combines on-device sensor data with computer vision processing. Upload a straight-on photo of your target shot group, select your scaling reference object (like a South African coin), and input your shooting distance. The embedded processing engine calculates extreme spread diameter, converts metrics to true MOA values, and updates your mechanical turret adjustment dial indicators automatically.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'GOT IT',
              style: TextStyle(
                color: const Color(0xFFE6A15C),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the dedicated calibrated Shot Group Target Analyzer, passing
  /// through any image the user already captured on this screen. The legacy
  /// mock analyzer (random spread simulation) has been replaced by the real
  /// computer-vision + scale-calibration pipeline in [ShotGroupAnalyzerScreen].
  Future<void> _openShotGroupAnalyzer() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => ShotGroupAnalyzerScreen(
          theme: widget.theme,
          initialImage: _shotGroupImage is File ? _shotGroupImage as File : null,
        ),
      ),
    );
  }
}
