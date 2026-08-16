import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:jagspoor/core/widgets/copyright_footer.dart';
import '../../ballistics/data/ballistics_engine.dart';

/// JagspoorTheme provides dynamic theme colors that can be overridden
/// by the hunter profile's ThemeController for consistent styling.
class JagspoorTheme {
  // Primary theme colors - can be overridden dynamically
  static Color walnutLuxury = const Color(0xFF8B4513);
  static Color thermalGlow = const Color(0xFFC5A059);
  static Color tacticalDark = const Color(0xFF121212);
  static Color hudCardBackground = const Color(0xFF1E1E1E);

  /// Updates theme colors dynamically from Theme.of(context) (hunter profile HUD settings)
  static void applyHunterTheme({
    required Color backgroundColor,
    required Color accentColor,
    required Color cardColor,
    required Color textColor,
  }) {
    thermalGlow = accentColor;
    walnutLuxury = accentColor.withValues(alpha: 0.6);
    tacticalDark = backgroundColor;
    hudCardBackground = cardColor;
  }
}

class TrajectoryPoint {
  final double rangeMeters;
  final double dropCm;
  final double windageCm;
  final double velocityMs;
  final double energyJoules;

  const TrajectoryPoint({
    required this.rangeMeters,
    required this.dropCm,
    required this.windageCm,
    required this.velocityMs,
    this.energyJoules = 0.0,
  });
}

class BallisticPhysicsEngine {
  static double calculateTrueBallisticRange(
    double lineOfSightRange,
    double angleDegrees,
  ) {
    if (lineOfSightRange <= 0) return 0.0;
    return lineOfSightRange * math.cos(angleDegrees * math.pi / 180.0);
  }

  /// Air-density ratio relative to the ICAO sea-level standard, computed by
  /// the [BallisticsEngine] ICAO atmosphere (temperature / pressure / humidity
  /// / altitude). Kept for the legacy single-ratio consumers.
  static double calculateAirDensityRatio(
    double altitudeMeters,
    double tempCelsius, {
    double pressureHpa = 1013.25,
    double relativeHumidity = 0.0,
  }) {
    return BallisticsEngine.instance.airDensityRatio(Atmosphere(
      temperatureCelsius: tempCelsius,
      pressureHpa: pressureHpa,
      relativeHumidity: relativeHumidity,
      altitudeMeters: altitudeMeters,
    ));
  }

  /// Calculates ballistic coefficient adjustment based on bullet weight.
  /// Heavier bullets maintain velocity better and have higher effective BC.
  static double calculateBulletWeightAdjustment(
    double bulletWeightGrains,
    double baseBc,
  ) {
    // Heavier bullets (higher grain weight) generally retain momentum better
    // This is a simplified model - real BC depends on bullet shape
    const double referenceWeight = 150.0; // Reference weight in grains
    final double weightRatio = bulletWeightGrains / referenceWeight;
    // Adjust BC by weight ratio with diminishing returns
    return baseBc * math.pow(weightRatio, 0.15);
  }

  /// Calculates ballistic coefficient adjustment based on muzzle velocity.
  /// Affects the drag model at different velocity ranges.
  static double calculateMuzzleVelocityAdjustment(
    double muzzleVelocityMs,
    double baseBc,
  ) {
    // Velocity affects drag - higher velocity means more drag initially
    // but also more energy delivery downrange
    const double referenceVelocity = 800.0; // m/s
    final double velocityRatio = muzzleVelocityMs / referenceVelocity;
    // At higher velocities, effective BC increases slightly
    return baseBc * (1.0 + 0.05 * (velocityRatio - 1.0));
  }

  /// Generates a trajectory grid (0–1000 m, 50 m steps) using the
  /// [BallisticsEngine] point-mass integrator with G1/G7 drag models, ICAO
  /// density altitude (temperature / pressure / humidity / altitude), and
  /// powder-temperature muzzle-velocity correction. Returns drop, windage,
  /// remaining velocity, and kinetic energy at each step.
  static List<TrajectoryPoint> generateTrajectoryGrid({
    required double muzzleVelocityMs,
    required double ballisticCoefficient,
    required double bulletWeightGrains,
    required double zeroDistanceMeters,
    required double crossWindMps,
    required double pitchAngleDegrees,
    required double altitudeMeters,
    required double temperatureCelsius,
    DragModel dragModel = DragModel.g1,
    double barometricPressureHpa = 1013.25,
    double relativeHumidity = 0.0,
    double powderTempCelsius = 15.0,
    double powderTempCoefficientFpsPerF = 1.5,
    double scopeHeightMeters = 0.045,
  }) {
    if (muzzleVelocityMs <= 0 || ballisticCoefficient <= 0) {
      return List.generate(
        21,
        (i) => TrajectoryPoint(
          rangeMeters: i * 50.0,
          dropCm: 0,
          windageCm: 0,
          velocityMs: 0,
        ),
      );
    }

    // Apply the legacy bullet-weight / muzzle-velocity BC heuristic on top of
    // the published BC so existing per-load tuning is preserved.
    final double weightAdjustedBc = calculateBulletWeightAdjustment(
      bulletWeightGrains,
      ballisticCoefficient,
    );
    final double velocityAdjustedBc = calculateMuzzleVelocityAdjustment(
      muzzleVelocityMs,
      weightAdjustedBc,
    );

    final trajectory = BallisticsEngine.instance.trajectoryTable(
      bullet: BulletProfile(
        muzzleVelocityMs: muzzleVelocityMs,
        ballisticCoefficient: velocityAdjustedBc,
        bulletWeightGrains: bulletWeightGrains,
        zeroDistanceMeters: zeroDistanceMeters,
        crossWindMps: crossWindMps,
        pitchAngleDegrees: pitchAngleDegrees,
        scopeHeightMeters: scopeHeightMeters,
        powderTempCelsius: powderTempCelsius,
        powderTempCoefficientFpsPerF: powderTempCoefficientFpsPerF,
      ),
      atmosphere: Atmosphere(
        temperatureCelsius: temperatureCelsius,
        pressureHpa: barometricPressureHpa,
        relativeHumidity: relativeHumidity,
        altitudeMeters: altitudeMeters,
      ),
      dragModel: dragModel,
      startMeters: 50.0,
      endMeters: 1000.0,
      stepMeters: 50.0,
    );

    return trajectory
        .map((p) => TrajectoryPoint(
              rangeMeters: p.rangeMeters,
              dropCm: p.dropCm,
              windageCm: p.windageCm,
              velocityMs: p.velocityMs,
              energyJoules: p.energyJoules,
            ))
        .toList();
  }
}

class BallisticCalcScreen extends StatefulWidget {
  const BallisticCalcScreen({super.key});

  @override
  State<BallisticCalcScreen> createState() => _BallisticCalcScreenState();
}

class _BallisticCalcScreenState extends State<BallisticCalcScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Stream<QuerySnapshot> _firearmsStream;
  late Stream<QuerySnapshot> _factoryAmmoStream;

  String? _selectedFirearmId;
  Map<String, dynamic>? _selectedFirearmData;
  Map<String, dynamic>? _selectedAmmunitionData;

  double _targetRangeMeters = 200.0;
  final double _barrelPitchDegrees = 0.0;
  double _crossWindMps = 0.0;
  double _altitudeMeters = 1500.0;
  double _temperatureCelsius = 20.0;
  // Atmospheric + drag-model enhancements (v20.0).
  double _barometricPressureHpa = 1013.25;
  double _relativeHumidity = 50.0; // %
  double _powderTempCelsius = 20.0;
  DragModel _dragModel = DragModel.g1;
  double _zeroDistanceMeters = 100.0;

  // Muzzle velocity and bullet weight controls (v19.0)
  double _muzzleVelocityFps = 2700.0; // Range: 800-5000 fps, Default: 2700
  double _bulletWeightGrains = 300.0; // Range: 300-500 grains, Default: 300

  final List<Map<String, dynamic>> _fallbackAmmunitionCatalog = [
    {
      'id': '308_win',
      'name': '.308 Winchester Professional',
      'caliber': '.308',
      'velocityMs': 800.0,
      'bulletWeightGrains': 175.0,
      'ballisticCoefficient': 0.496,
    },
    {
      'id': '65_cm',
      'name': '6.5mm Creedmoor Match Grade',
      'caliber': '6.5mm',
      'velocityMs': 835.0,
      'bulletWeightGrains': 140.0,
      'ballisticCoefficient': 0.512,
    },
    {
      'id': '243_win',
      'name': '.243 Winchester Varmint',
      'caliber': '.243',
      'velocityMs': 900.0,
      'bulletWeightGrains': 100.0,
      'ballisticCoefficient': 0.395,
    },
    {
      'id': '270_win',
      'name': '.270 Winchester Express',
      'caliber': '.270',
      'velocityMs': 850.0,
      'bulletWeightGrains': 150.0,
      'ballisticCoefficient': 0.447,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    _firearmsStream =
        FirebaseFirestore.instance
            .collection('firearms')
            .where('ownerId', isEqualTo: currentUid)
            .snapshots()
            .asBroadcastStream();

    _factoryAmmoStream = FirebaseFirestore.instance
        .collection('factory_ammunition')
        .snapshots()
        .asBroadcastStream();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _evaluateCaliberMatch(String? rifleCaliber, String? cartridgeCaliber) {
    if (rifleCaliber == null || cartridgeCaliber == null) return false;
    String normalize(String s) =>
        s.replaceAll(RegExp(r'[\s\-\.]'), '').toLowerCase();
    final String rClean = normalize(rifleCaliber);
    final String cClean = normalize(cartridgeCaliber);
    return rClean.contains(cClean) || cClean.contains(rClean);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    JagspoorTheme.applyHunterTheme(
      backgroundColor: theme.scaffoldBackgroundColor,
      accentColor: theme.colorScheme.primary,
      cardColor: theme.cardColor,
      textColor: theme.colorScheme.onSurface,
    );

    return Scaffold(
      backgroundColor: JagspoorTheme.tacticalDark,
      appBar: AppBar(
        backgroundColor: JagspoorTheme.walnutLuxury,
        title: const Text(
          'HUD BALLISTIC DATA SYSTEM',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: JagspoorTheme.thermalGlow,
          labelColor: JagspoorTheme.thermalGlow,
          unselectedLabelColor: Colors.white,
          tabs: const [Tab(icon: Icon(Icons.tune), text: 'Cartridge Data')],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏹 TACTICAL PROFILE DATA MATRIX',
                style: TextStyle(
                  color: JagspoorTheme.thermalGlow,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),

              StreamBuilder<QuerySnapshot>(
                stream: _firearmsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError ||
                      !snapshot.hasData ||
                      snapshot.data!.docs.isEmpty) {
                    return _buildHardwareDropdownContainer(
                      label: 'Select Firearm Vault Location',
                      child: Text(
                        'OFFLINE SAFE MODULE ACTIVE',
                        style: TextStyle(
                          color: JagspoorTheme.thermalGlow,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;

                  // Filter out demo/seeded rifles - only show user's real registered firearms
                  final userDocs =
                      docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final serial =
                            (data['serialNumber']?.toString().toUpperCase() ??
                                '');
                        final name =
                            (data['name']?.toString().toLowerCase() ?? '');
                        // Exclude demo rifles with TIKKA-, SAKO- prefixes
                        if (serial.startsWith('TIKKA-') ||
                            serial.startsWith('SAKO-')) {
                          return false;
                        }
                        // Exclude rifles with "Unknown" in the name
                        if (name.contains('unknown')) {
                          return false;
                        }
                        return true;
                      }).toList();

                  // Show empty state if no real firearms
                  if (userDocs.isEmpty) {
                    return _buildHardwareDropdownContainer(
                      label: 'Select Firearm Vault Location',
                      child: Text(
                        'NO REGISTERED FIREARMS',
                        style: TextStyle(
                          color: JagspoorTheme.thermalGlow,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                  return _buildHardwareDropdownContainer(
                    label: 'Select Firearm Vault Location',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: Text(
                          'CHOOSE FIREARM',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        dropdownColor: JagspoorTheme.hudCardBackground,
                        value: _selectedFirearmId,
                        items:
                            userDocs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final String make =
                                  (data['make'] ??
                                          data['brand'] ??
                                          data['manufacturer'] ??
                                          'Unknown')
                                      .toString();
                              final String model =
                                  (data['model'] ??
                                          data['modelName'] ??
                                          data['name'] ??
                                          'Firearm')
                                      .toString();
                              final String caliber =
                                  (data['caliber'] ?? 'N/A').toString();
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(
                                  '$make $model • [$caliber]',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final doc = userDocs.firstWhere((d) => d.id == id);
                          setState(() {
                            _selectedFirearmId = id;
                            _selectedFirearmData =
                                doc.data() as Map<String, dynamic>;
                            _selectedAmmunitionData = null;
                          });
                        },
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              _buildHardwareDropdownContainer(
                label: 'Target Range (meters)',
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'RANGE',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${_targetRangeMeters.toInt()} m',
                          style: TextStyle(
                            color: JagspoorTheme.thermalGlow,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        inactiveTrackColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.24),
                        overlayColor: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.12),
                        valueIndicatorColor:
                            Theme.of(context).colorScheme.primary,
                        activeTickMarkColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.4),
                        inactiveTickMarkColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: _targetRangeMeters,
                        min: 25,
                        max: 1000,
                        divisions: 39,
                        onChanged:
                            (v) => setState(() => _targetRangeMeters = v),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _buildHardwareDropdownContainer(
                label: 'Environmental Parameters',
                child: Column(
                  children: [
                    _buildParameterRow(
                      'Wind Speed (m/s)',
                      _crossWindMps,
                      0,
                      20,
                      (v) => setState(() => _crossWindMps = v),
                    ),
                    const SizedBox(height: 8),
                    _buildParameterRow(
                      'Altitude (m)',
                      _altitudeMeters,
                      0,
                      5000,
                      (v) => setState(() => _altitudeMeters = v),
                    ),
                    const SizedBox(height: 8),
                    _buildParameterRow(
                      'Temperature (°C)',
                      _temperatureCelsius,
                      -40,
                      60,
                      (v) => setState(() => _temperatureCelsius = v),
                    ),
                    const SizedBox(height: 8),
                    _buildParameterRow(
                      'Zero Distance (m)',
                      _zeroDistanceMeters,
                      25,
                      1000,
                      (v) => setState(() => _zeroDistanceMeters = v),
                    ),
                    const SizedBox(height: 8),
                    _buildParameterRow(
                      'Barometric Pressure (hPa)',
                      _barometricPressureHpa,
                      800,
                      1100,
                      (v) => setState(() => _barometricPressureHpa = v),
                    ),
                    const SizedBox(height: 8),
                    _buildParameterRow(
                      'Relative Humidity (%)',
                      _relativeHumidity,
                      0,
                      100,
                      (v) => setState(() => _relativeHumidity = v),
                    ),
                    const SizedBox(height: 8),
                    _buildParameterRow(
                      'Powder Temperature (°C)',
                      _powderTempCelsius,
                      -40,
                      60,
                      (v) => setState(() => _powderTempCelsius = v),
                    ),
                    const SizedBox(height: 12),
                    // Drag-model selection (G1 vs G7).
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Drag Model',
                            style: TextStyle(
                              color: JagspoorTheme.thermalGlow,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SegmentedButton<DragModel>(
                          segments: const [
                            ButtonSegment(
                              value: DragModel.g1,
                              label: Text('G1'),
                            ),
                            ButtonSegment(
                              value: DragModel.g7,
                              label: Text('G7'),
                            ),
                          ],
                          selected: {_dragModel},
                          onSelectionChanged: (selection) =>
                              setState(() => _dragModel = selection.first),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Muzzle Velocity and Bullet Weight Controls (v19.0)
              _buildHardwareDropdownContainer(
                label: '🚀 MUZZLE VELOCITY (fps)',
                child: Column(
                  children: [
                    _buildParameterRow(
                      'Muzzle Velocity (fps)',
                      _muzzleVelocityFps,
                      800,
                      5000,
                      (v) => setState(() => _muzzleVelocityFps = v),
                    ),
                    const SizedBox(height: 8),
                    _buildParameterRow(
                      'Bullet Weight (Grains)',
                      _bulletWeightGrains,
                      300,
                      500,
                      (v) => setState(() => _bulletWeightGrains = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              if (_selectedFirearmData != null) ...[
                Text(
                  '📊 TRAJECTORY COMPUTATION GRID',
                  style: TextStyle(
                    color: JagspoorTheme.thermalGlow,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: _factoryAmmoStream,
                  builder: (context, snapshot) {
                    List<Map<String, dynamic>> ammoCatalog =
                        _fallbackAmmunitionCatalog;
                    if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                      ammoCatalog =
                          snapshot.data!.docs
                              .map((doc) => doc.data() as Map<String, dynamic>)
                              .where(
                                (a) => _evaluateCaliberMatch(
                                  _selectedFirearmData!['caliber'],
                                  a['caliber'],
                                ),
                              )
                              .toList();
                      if (ammoCatalog.isEmpty) {
                        ammoCatalog = _fallbackAmmunitionCatalog;
                      }
                    }

                    return _buildTrajectoryChart(ammoCatalog);
                  },
                ),
              ] else ...[
                _buildOfflineChartDisplay(),
              ],

              const SizedBox(height: 16),

              // Analytics Summary Footer Card (v17.1)
              _buildAnalyticsSummaryCard(),
              const CopyrightFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the analytics summary footer card with trajectory telemetry data (v19.0)
  Widget _buildAnalyticsSummaryCard() {
    // Calculate values for display
    final double muzzleVelocityFps = _muzzleVelocityFps;
    final double bulletWeight = _bulletWeightGrains;

    // Convert fps to m/s for internal physics calculations
    final double internalMuzzleVelocityMs = muzzleVelocityFps * 0.3048;

    final double bc =
        (_selectedAmmunitionData?['ballisticCoefficient'] ??
                _selectedAmmunitionData?['bc'] ??
                0.45)
            .toDouble();

    final trajectoryGrid = BallisticPhysicsEngine.generateTrajectoryGrid(
      muzzleVelocityMs: internalMuzzleVelocityMs,
      ballisticCoefficient: bc,
      bulletWeightGrains: bulletWeight,
      zeroDistanceMeters: _zeroDistanceMeters,
      crossWindMps: _crossWindMps,
      pitchAngleDegrees: _barrelPitchDegrees,
      altitudeMeters: _altitudeMeters,
      temperatureCelsius: _temperatureCelsius,
      dragModel: _dragModel,
      barometricPressureHpa: _barometricPressureHpa,
      relativeHumidity: _relativeHumidity,
      powderTempCelsius: _powderTempCelsius,
    );

    // Density altitude for the current atmosphere (ICAO).
    final densityAltitudeMeters = BallisticsEngine.instance.densityAltitude(
      Atmosphere(
        temperatureCelsius: _temperatureCelsius,
        pressureHpa: _barometricPressureHpa,
        relativeHumidity: _relativeHumidity,
        altitudeMeters: _altitudeMeters,
      ),
    );

    // Find data point at target range
    TrajectoryPoint? targetPoint;
    for (final point in trajectoryGrid) {
      if (point.rangeMeters >= _targetRangeMeters) {
        targetPoint = point;
        break;
      }
    }
    final double targetDrop = targetPoint?.dropCm ?? 0.0;
    final double targetWindage = targetPoint?.windageCm ?? 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JagspoorTheme.hudCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: JagspoorTheme.thermalGlow.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: JagspoorTheme.thermalGlow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                color: JagspoorTheme.thermalGlow,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '🎯 POSITION STATISTICS SUMMARY (1000m Flight Path)',
                style: TextStyle(
                  color: JagspoorTheme.thermalGlow,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          _buildSummaryRow(
            'Selected Cartridge Load Weight:',
            '${bulletWeight.toStringAsFixed(0)} Grains @ ${muzzleVelocityFps.toStringAsFixed(0)} fps Muzzle Speed',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Calculated Bullet Drop at Target Range:',
            '${targetDrop.toStringAsFixed(1)} cm',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Estimated Cross-windage Displacement:',
            '${targetWindage.toStringAsFixed(1)} cm',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Remaining Velocity at Target Range:',
            '${targetPoint?.velocityMs.toStringAsFixed(0) ?? "0"} m/s',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Remaining Energy at Target Range:',
            '${targetPoint?.energyJoules.toStringAsFixed(0) ?? "0"} J',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Drag Model:',
            _dragModel == DragModel.g7 ? 'G7 (boat-tail / VLD)' : 'G1 (Ingalls)',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Density Altitude (ICAO):',
            '${densityAltitudeMeters.toStringAsFixed(0)} m',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Atmospheric Air Density Profile:',
            '${_altitudeMeters.toStringAsFixed(0)}m @ ${_temperatureCelsius.toStringAsFixed(0)}°C, '
            '${_barometricPressureHpa.toStringAsFixed(0)}hPa, '
            '${_relativeHumidity.toStringAsFixed(0)}% RH',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '• ',
          style: TextStyle(
            color: Color(0xFF1A2421),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            '$label ',
            style: const TextStyle(
              color: Color(0xFF1A2421),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF2E3D2F),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildHardwareDropdownContainer({
    required String label,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JagspoorTheme.hudCardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JagspoorTheme.walnutLuxury.withAlpha(128)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildParameterRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.24),
              overlayColor: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.12),
              valueIndicatorColor: Theme.of(context).colorScheme.primary,
              activeTickMarkColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
              inactiveTickMarkColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / 10).round(),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildTrajectoryChart(List<Map<String, dynamic>> ammoCatalog) {
    final double bc =
        (_selectedAmmunitionData?['ballisticCoefficient'] ??
                _selectedAmmunitionData?['bc'] ??
                (ammoCatalog.isNotEmpty
                    ? (ammoCatalog.first['ballisticCoefficient'] ??
                        ammoCatalog.first['bc'] ??
                        0.45)
                    : 0.45))
            .toDouble();

    // Use the slider fps value, converting to m/s for internal physics
    final double internalMuzzleVelocityMs = _muzzleVelocityFps * 0.3048;
    final double ballisticCoef = bc;

    final trajectoryGrid = BallisticPhysicsEngine.generateTrajectoryGrid(
      muzzleVelocityMs: internalMuzzleVelocityMs,
      ballisticCoefficient: ballisticCoef,
      bulletWeightGrains: _bulletWeightGrains,
      zeroDistanceMeters: _zeroDistanceMeters,
      crossWindMps: _crossWindMps,
      pitchAngleDegrees: _barrelPitchDegrees,
      altitudeMeters: _altitudeMeters,
      temperatureCelsius: _temperatureCelsius,
    );

    final dropSpots =
        trajectoryGrid.map((p) => FlSpot(p.rangeMeters, -p.dropCm)).toList();

    final windageSpots =
        trajectoryGrid.map((p) => FlSpot(p.rangeMeters, p.windageCm)).toList();

    final maxY = [
      ...dropSpots,
      ...windageSpots,
    ].map((s) => s.y.abs()).fold<double>(0, (a, b) => math.max(a, b));

    // Dynamic firearm label: selected firearm make/model/caliber, else prompt.
    final String firearmLabel = _selectedFirearmData == null
        ? 'Select Firearm'
        : '${(_selectedFirearmData!['make'] ?? _selectedFirearmData!['brand'] ?? _selectedFirearmData!['manufacturer'] ?? 'Unknown').toString()} '
            '${(_selectedFirearmData!['model'] ?? _selectedFirearmData!['modelName'] ?? _selectedFirearmData!['name'] ?? 'Firearm').toString()} '
            '[${(_selectedFirearmData!['caliber'] ?? _selectedFirearmData!['calibre'] ?? 'N/A').toString()}]';

    return Container(
      height: 350,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JagspoorTheme.hudCardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JagspoorTheme.walnutLuxury.withAlpha(128)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DROP & WINDAGE vs RANGE',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                firearmLabel,
                style: TextStyle(
                  color: JagspoorTheme.thermalGlow,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: (maxY / 4).clamp(1, double.infinity),
                  verticalInterval: 100,
                  getDrawingHorizontalLine:
                      (value) => FlLine(
                        color: JagspoorTheme.walnutLuxury.withAlpha(51),
                        strokeWidth: 1,
                      ),
                  getDrawingVerticalLine:
                      (value) => FlLine(
                        color: JagspoorTheme.walnutLuxury.withAlpha(51),
                        strokeWidth: 1,
                      ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget:
                          (value, meta) => Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(
                              color: Color(0xFF1A2421),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget:
                          (value, meta) => Text(
                            '${value.toInt()}m',
                            style: const TextStyle(
                              color: Color(0xFF1A2421),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: JagspoorTheme.walnutLuxury.withAlpha(128),
                  ),
                ),
                // Target Range Indicator Line (v17.1) + zero baseline.
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: _targetRangeMeters,
                      color: JagspoorTheme.thermalGlow,
                      strokeWidth: 2,
                      dashArray: [8, 4],
                      label: VerticalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: const TextStyle(
                          color: Color(0xFF1A2421),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        labelResolver:
                            (line) =>
                                'TARGET: ${_targetRangeMeters.toStringAsFixed(0)}m',
                      ),
                    ),
                  ],
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: JagspoorTheme.walnutLuxury.withAlpha(96),
                      strokeWidth: 1.5,
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        style: const TextStyle(
                          color: Color(0xFF1A2421),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        labelResolver: (line) => 'ZERO LINE',
                      ),
                    ),
                  ],
                ),
                minX: 0,
                maxX: 1000,
                minY: -maxY - 10,
                maxY: maxY + 10,
                lineBarsData: [
                  LineChartBarData(
                    spots: dropSpots,
                    isCurved: true,
                    color: JagspoorTheme.thermalGlow,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: JagspoorTheme.thermalGlow.withAlpha(26),
                    ),
                  ),
                  LineChartBarData(
                    spots: windageSpots,
                    isCurved: true,
                    color: Colors.blueAccent,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor:
                        (touchedSpot) => JagspoorTheme.hudCardBackground,
                    getTooltipItems:
                        (spots) =>
                            spots.map((spot) {
                              final isDrop = spot.barIndex == 0;
                              final label = isDrop ? 'Drop' : 'Wind';
                              // Drop spots are negated for display; show the
                              // real drop magnitude (positive = below LOS).
                              final value = isDrop ? -spot.y : spot.y;
                              return LineTooltipItem(
                                '$label: ${value.toStringAsFixed(2)} cm',
                                TextStyle(
                                  color:
                                      isDrop
                                          ? JagspoorTheme.thermalGlow
                                          : Colors.blueAccent,
                                  fontSize: 12,
                                ),
                              );
                            }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('DROP (cm)', JagspoorTheme.thermalGlow),
              const SizedBox(width: 24),
              _buildLegendItem('WIND (cm)', Colors.blueAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineChartDisplay() {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JagspoorTheme.hudCardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JagspoorTheme.walnutLuxury.withAlpha(128)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, color: JagspoorTheme.walnutLuxury, size: 64),
            const SizedBox(height: 16),
            Text(
              'SELECT FIREARM TO ACTIVATE',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'TRAJECTORY COMPUTATION ENGINE',
              style: TextStyle(color: JagspoorTheme.thermalGlow, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1A2421),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
