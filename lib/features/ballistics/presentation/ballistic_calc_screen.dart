import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';


class JagspoorTheme {
  static const Color walnutLuxury = Color(0xFF8B4513);
  static const Color thermalGlow = Color(0xFFC5A059);
  static const Color tacticalDark = Color(0xFF121212);
  static const Color hudCardBackground = Color(0xFF1E1E1E);
}


class TrajectoryPoint {
  final double rangeMeters;
  final double dropCm;
  final double windageCm;
  final double velocityMs;


  const TrajectoryPoint({
    required this.rangeMeters,
    required this.dropCm,
    required this.windageCm,
    required this.velocityMs,
  });
}


class BallisticPhysicsEngine {
  static double calculateTrueBallisticRange(double lineOfSightRange, double angleDegrees) {
    if (lineOfSightRange <= 0) return 0.0;
    return lineOfSightRange * math.cos(angleDegrees * math.pi / 180.0);
  }


  static double calculateAirDensityRatio(double altitudeMeters, double tempCelsius) {
    final double altitudeFactor = 1.0 - ((altitudeMeters / 300.0) * 0.03);
    final double tempFactor = 1.0 - (((tempCelsius - 15.0) / 5.0) * 0.01);
    return math.max(0.5, math.min(1.5, altitudeFactor * tempFactor));
  }


  static List<TrajectoryPoint> generateTrajectoryGrid({
    required double muzzleVelocityMs,
    required double ballisticCoefficient,
    required double zeroDistanceMeters,
    required double crossWindMps,
    required double pitchAngleDegrees,
    required double altitudeMeters,
    required double temperatureCelsius,
  }) {
    if (muzzleVelocityMs <= 0 || ballisticCoefficient <= 0) {
      return List.generate(11, (i) => TrajectoryPoint(rangeMeters: i * 50.0, dropCm: 0, windageCm: 0, velocityMs: 0));
    }


    final List<TrajectoryPoint> grid = [];
    final double densityRatio = calculateAirDensityRatio(altitudeMeters, temperatureCelsius);
    final double adjustedBc = ballisticCoefficient / densityRatio;
    final double gravity = 9.80665 * math.cos(pitchAngleDegrees * math.pi / 180.0);


    for (int stepRange = 0; stepRange <= 500; stepRange += 50) {
      final double x = stepRange.toDouble();
      if (x == 0) {
        grid.add(TrajectoryPoint(rangeMeters: 0, dropCm: 0, windageCm: 0, velocityMs: muzzleVelocityMs));
        continue;
      }


      final double velocityAtX = muzzleVelocityMs * math.exp(-x / (adjustedBc * 1500.0));
      final double averageVelocity = (muzzleVelocityMs + velocityAtX) / 2.0;
      final double timeOfFlight = x / averageVelocity;


      double rawDropCm = 0.5 * gravity * math.pow(timeOfFlight, 2) * 100.0;
      final double zeroTime = zeroDistanceMeters / ((muzzleVelocityMs + (muzzleVelocityMs * math.exp(-zeroDistanceMeters / (adjustedBc * 1500.0)))) / 2.0);
      final double zeroDropCompensationAtX = (0.5 * gravity * math.pow(zeroTime, 2) * 100.0) * (x / zeroDistanceMeters);
      
      double dropCorrectionCm = rawDropCm - zeroDropCompensationAtX;
      double windageDriftCm = crossWindMps * timeOfFlight * 10.0;


      if (dropCorrectionCm.isNaN || dropCorrectionCm.isInfinite) dropCorrectionCm = 0.0;
      if (windageDriftCm.isNaN || windageDriftCm.isInfinite) windageDriftCm = 0.0;


      grid.add(TrajectoryPoint(
        rangeMeters: x,
        dropCm: double.parse(dropCorrectionCm.toStringAsFixed(2)),
        windageCm: double.parse(windageDriftCm.toStringAsFixed(2)),
        velocityMs: double.parse(velocityAtX.toStringAsFixed(1)),
      ));
    }
    return grid;
  }
}


class BallisticCalcScreen extends StatefulWidget {
  const BallisticCalcScreen({super.key});


  @override
  State<BallisticCalcScreen> createState() => _BallisticCalcScreenState();
}


class _BallisticCalcScreenState extends State<BallisticCalcScreen> with SingleTickerProviderStateMixin {
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
  double _zeroDistanceMeters = 100.0;


  final List<Map<String, dynamic>> _fallbackAmmunitionCatalog = [
    {'id': '308_win', 'name': '.308 Winchester Professional', 'caliber': '.308', 'velocityMs': 800.0, 'bulletWeightGrains': 175.0, 'ballisticCoefficient': 0.496},
    {'id': '65_cm', 'name': '6.5mm Creedmoor Match Grade', 'caliber': '6.5mm', 'velocityMs': 835.0, 'bulletWeightGrains': 140.0, 'ballisticCoefficient': 0.512},
    {'id': '243_win', 'name': '.243 Winchester Varmint', 'caliber': '.243', 'velocityMs': 900.0, 'bulletWeightGrains': 100.0, 'ballisticCoefficient': 0.395},
    {'id': '270_win', 'name': '.270 Winchester Express', 'caliber': '.270', 'velocityMs': 850.0, 'bulletWeightGrains': 150.0, 'ballisticCoefficient': 0.447},
  ];


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    
    _firearmsStream = FirebaseFirestore.instance
        .collection('firearms')
        .where('ownerId', isEqualTo: currentUid)
        .snapshots();


    _factoryAmmoStream = FirebaseFirestore.instance
        .collection('factory_ammunition')
        .snapshots();
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  bool _evaluateCaliberMatch(String? rifleCaliber, String? cartridgeCaliber) {
    if (rifleCaliber == null || cartridgeCaliber == null) return false;
    String normalize(String s) => s.replaceAll(RegExp(r'[\s\-\.]'), '').toLowerCase();
    final String rClean = normalize(rifleCaliber);
    final String cClean = normalize(cartridgeCaliber);
    return rClean.contains(cClean) || cClean.contains(rClean);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JagspoorTheme.tacticalDark,
      appBar: AppBar(
        backgroundColor: JagspoorTheme.walnutLuxury,
        title: const Text('HUD BALLISTIC DATA SYSTEM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: JagspoorTheme.thermalGlow,
          labelColor: JagspoorTheme.thermalGlow,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.layers), text: 'FACTORY CARTRIDGE'),
            Tab(icon: Icon(Icons.tune), text: 'CUSTOM AMMO DATA'),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🏹 TACTICAL PROFILE DATA MATRIX', style: TextStyle(color: JagspoorTheme.thermalGlow, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              
              StreamBuilder<QuerySnapshot>(
                stream: _firearmsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildHardwareDropdownContainer(
                      label: 'Select Firearm Vault Location',
                      child: const Text('OFFLINE SAFE MODULE ACTIVE', style: TextStyle(color: JagspoorTheme.thermalGlow, fontSize: 14)),
                    );
                  }
                  
                  final docs = snapshot.data!.docs;
                  return _buildHardwareDropdownContainer(
                    label: 'Select Firearm Vault Location',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('CHOOSE FIREARM', style: TextStyle(color: Colors.white70)),
                        dropdownColor: JagspoorTheme.hudCardBackground,
                        value: _selectedFirearmId,
                        items: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(
                              '${data['name'] ?? 'Unknown'} | ${data['caliber'] ?? 'N/A'}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final doc = docs.firstWhere((d) => d.id == id);
                          setState(() {
                            _selectedFirearmId = id;
                            _selectedFirearmData = doc.data() as Map<String, dynamic>;
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
                        const Text('RANGE', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('${_targetRangeMeters.toInt()} m', style: const TextStyle(color: JagspoorTheme.thermalGlow, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _targetRangeMeters,
                      min: 50,
                      max: 1000,
                      divisions: 19,
                      activeColor: JagspoorTheme.thermalGlow,
                      inactiveColor: JagspoorTheme.hudCardBackground,
                      onChanged: (v) => setState(() => _targetRangeMeters = v),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              _buildHardwareDropdownContainer(
                label: 'Environmental Parameters',
                child: Column(
                  children: [
                    _buildParameterRow('Wind Speed (m/s)', _crossWindMps, 0, 20, (v) => setState(() => _crossWindMps = v)),
                    const SizedBox(height: 8),
                    _buildParameterRow('Altitude (m)', _altitudeMeters, 0, 5000, (v) => setState(() => _altitudeMeters = v)),
                    const SizedBox(height: 8),
                    _buildParameterRow('Temperature (°C)', _temperatureCelsius, -40, 60, (v) => setState(() => _temperatureCelsius = v)),
                    const SizedBox(height: 8),
                    _buildParameterRow('Zero Distance (m)', _zeroDistanceMeters, 50, 300, (v) => setState(() => _zeroDistanceMeters = v)),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              if (_selectedFirearmData != null) ...[
                const Text('📊 TRAJECTORY COMPUTATION GRID', style: TextStyle(color: JagspoorTheme.thermalGlow, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                
                StreamBuilder<QuerySnapshot>(
                  stream: _factoryAmmoStream,
                  builder: (context, snapshot) {
                    List<Map<String, dynamic>> ammoCatalog = _fallbackAmmunitionCatalog;
                    if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                      ammoCatalog = snapshot.data!.docs
                          .map((doc) => doc.data() as Map<String, dynamic>)
                          .where((a) => _evaluateCaliberMatch(_selectedFirearmData!['caliber'], a['caliber']))
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
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHardwareDropdownContainer({required String label, required Widget child}) {
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
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
  
  Widget _buildParameterRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          flex: 3,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / 10).round(),
            activeColor: JagspoorTheme.thermalGlow,
            inactiveColor: JagspoorTheme.walnutLuxury.withAlpha(77),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTrajectoryChart(List<Map<String, dynamic>> ammoCatalog) {
    final double v0 = (_selectedAmmunitionData?['velocityMs'] as num?)?.toDouble() ?? ammoCatalog.first['velocityMs'].toDouble();
    final double bc = (_selectedAmmunitionData?['ballisticCoefficient'] as num?)?.toDouble() ?? ammoCatalog.first['ballisticCoefficient'].toDouble();
    final double muzzleVelocity = v0;
    final double ballisticCoef = bc;
    
    final trajectoryGrid = BallisticPhysicsEngine.generateTrajectoryGrid(
      muzzleVelocityMs: muzzleVelocity,
      ballisticCoefficient: ballisticCoef,
      zeroDistanceMeters: _zeroDistanceMeters,
      crossWindMps: _crossWindMps,
      pitchAngleDegrees: _barrelPitchDegrees,
      altitudeMeters: _altitudeMeters,
      temperatureCelsius: _temperatureCelsius,
    );
    
    final dropSpots = trajectoryGrid
        .map((p) => FlSpot(p.rangeMeters, p.dropCm))
        .toList();
    
    final windageSpots = trajectoryGrid
        .map((p) => FlSpot(p.rangeMeters, p.windageCm))
        .toList();
    
    final maxY = [...dropSpots, ...windageSpots]
        .map((s) => s.y.abs())
        .fold<double>(0, (a, b) => math.max(a, b));
    
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
              const Text('DROP & WINDAGE vs RANGE', style: TextStyle(color: Colors.white70, fontSize: 12)),
              if (ammoCatalog.isNotEmpty)
                Text(ammoCatalog.first['name'] ?? '', style: const TextStyle(color: JagspoorTheme.thermalGlow, fontSize: 11)),
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
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: JagspoorTheme.walnutLuxury.withAlpha(51),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: JagspoorTheme.walnutLuxury.withAlpha(51),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}m',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: JagspoorTheme.walnutLuxury.withAlpha(128)),
                ),
                minX: 0,
                maxX: 500,
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
                    getTooltipColor: (touchedSpot) => JagspoorTheme.hudCardBackground,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final label = spot.barIndex == 0 ? 'Drop' : 'Wind';
                      return LineTooltipItem(
                        '$label: ${spot.y.toStringAsFixed(2)} cm',
                        TextStyle(color: spot.barIndex == 0 ? JagspoorTheme.thermalGlow : Colors.blueAccent, fontSize: 12),
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
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, color: JagspoorTheme.walnutLuxury, size: 64),
            SizedBox(height: 16),
            Text('SELECT FIREARM TO ACTIVATE', style: TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 1.2)),
            Text('TRAJECTORY COMPUTATION ENGINE', style: TextStyle(color: JagspoorTheme.thermalGlow, fontSize: 12)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 16, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
