import 'dart:async';
import 'dart:math' show sin, cos, atan2, sqrt, pi;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../data/inventory_bridge.dart';
import '../data/models/rifle_profile.dart';
import '../data/scope_calculator.dart';

/// ScopeToolsBottomSheet provides a modal interface for configuring
/// rifle scope settings including reticle type, adjustment values,
/// gyroscopic barrel leveler, and AI target scanner.
class ScopeToolsBottomSheet extends StatefulWidget {
  const ScopeToolsBottomSheet({super.key});

  @override
  State<ScopeToolsBottomSheet> createState() => _ScopeToolsBottomSheetState();
}

class _ScopeToolsBottomSheetState extends State<ScopeToolsBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Inventory Bridge for firearm and ammunition data
  final InventoryBridge _inventoryBridge = InventoryBridge();
  
  // Persistent stream references - initialized once in initState to prevent rebuild loops
  late Stream<List<RifleProfile>> _firearmsStream;
  Stream<List<AmmoProfile>>? _ammunitionStream;
  
  // State variables
  String? _selectedRifleId;
  String? _selectedAmmoId;
  RifleProfile? _selectedRifle;

  // Scope reticle type selection
  String _selectedReticle = 'Mil-Dot';
  static const List<String> _reticleTypes = [
    'Mil-Dot',
    'MOA',
    'BDC (Bullet Drop Compensator)',
    'German #4',
    'Ballistic Plex',
    'Tactical Milling',
  ];

  // Scope adjustment settings
  double _clickValue = 0.25; // MOA per click
  double _tubeDiameter = 30.0; // mm
  double _objectiveDiameter = 50.0; // mm

  // Gyro barrel angle settings
  double _barrelAngle = 0.0; // degrees
  double _lineOfSightDistance = 200.0; // meters

  // Gyroscope sensor state (v20.1)
  StreamSubscription<AccelerometerEvent>? _gyroLevelerSubscription;
  bool _isLiveGyroRadarActive = false;
  
  // AI target scanner settings
  double _targetDistance = 100.0; // meters
  String _scopeUnitType = 'MOA';
  List<Map<String, double>> _scanData = [];
  Map<String, double>? _groupCenter;
  String? _correctionResult;

  // Turret settings
  double _elevationAdjustment = 0.0; // MOA
  double _windageAdjustment = 0.0; // MOA

  // Parallax settings
  double _parallaxDistance = 100.0; // yards

  // Illumination settings
  bool _isIlluminated = false;
  double _illuminationLevel = 5.0;

  // Calculated gyro values
  GyroHoldoverResult? _gyroResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Initialize firearms stream once at lifecycle bootup to prevent rebuild loops
    _firearmsStream = _inventoryBridge.watchSafeFirearms();
  }

  @override
  void dispose() {
    // Cleanly cancel the gyro subscription to eliminate battery drain
    _gyroLevelerSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onRifleSelected(String? rifleId) {
    if (rifleId == null) return;
    
    // Create new ammunition stream for the selected rifle
    // This is assigned in setState to trigger a rebuild with the new stream
    setState(() {
      _selectedRifleId = rifleId;
      _selectedAmmoId = null;
      _ammunitionStream = _inventoryBridge.watchAvailableAmmunition(rifleId);
    });
  }

  void _updateRifleFromSnapshots(List<RifleProfile> rifles) {
    if (_selectedRifleId == null) return;
    
    final selectedRifle = rifles.where((r) => r.id == _selectedRifleId).firstOrNull;
    if (selectedRifle != null && selectedRifle.id != _selectedRifle?.id) {
      setState(() {
        _selectedRifle = selectedRifle;
        _clickValue = selectedRifle.scopeClickValue;
      });
    }
  }

  void _onAmmoSelected(String? ammoId) {
    if (ammoId == null) return;
    setState(() => _selectedAmmoId = ammoId);
  }

  void _updateGyroCalculation() {
    final result = ScopeCalculator.calculateGyroHoldover(
      lineOfSightDistance: _lineOfSightDistance,
      barrelAngleDegrees: _barrelAngle,
      clickValueUnit: _clickValue,
    );
    setState(() => _gyroResult = result);
  }

  /// Toggles the live gyroscope leveler sensor (v20.1)
  void _toggleLiveGyroLeveler(bool active) {
    if (active) {
      // Start listening to accelerometer events
      _gyroLevelerSubscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          // Calculate vertical incline angle from raw physical gravity metrics
          // Device orientation when rested flat along rifle chassis:
          //   - event.x: lateral acceleration (left/right tilt)
          //   - event.z: vertical acceleration (forward/backward tilt)
          final double calculatedPitch = atan2(-event.x, event.z) * 180.0 / pi;
          
          // Clamp values securely between -45.0 and 45.0 to filter mechanical tracking spikes
          final double clampedPitch = calculatedPitch.clamp(-45.0, 45.0);
          
          // Map live sensor reading directly to barrel angle variable
          setState(() {
            _barrelAngle = clampedPitch;
          });
          
          // Recalculate gyro values with live sensor data
          _updateGyroCalculation();
        },
        onError: (error) {
          debugPrint('Gyroscope sensor error: $error');
        },
      );
      
      setState(() {
        _isLiveGyroRadarActive = true;
      });
      
      debugPrint('Gyro radar leveler activated - hardware accelerometer streaming');
    } else {
      // Cancel the subscription to eliminate battery drain in the field
      _gyroLevelerSubscription?.cancel();
      _gyroLevelerSubscription = null;
      
      setState(() {
        _isLiveGyroRadarActive = false;
      });
      
      debugPrint('Gyro radar leveler deactivated - hardware accelerometer stream stopped');
    }
  }

  void _runTargetScan() {
    final scanData = ScopeCalculator.simulateTargetScanData(
      targetDistanceMeters: _targetDistance,
    );
    final center = ScopeCalculator.calculateGroupCenter(scanData);
    
    final correction = ScopeCalculator.calculateMoaTargetCorrection(
      deviationX_cm: center['x']!,
      deviationY_cm: center['y']!,
      targetDistanceMeters: _targetDistance,
      scopeUnitType: _scopeUnitType,
    );

    setState(() {
      _scanData = scanData;
      _groupCenter = center;
      _correctionResult = correction.tacticalString;
    });
  }

  double _calculateResolutionFactor() {
    return (_tubeDiameter / 25.4) * sqrt(_objectiveDiameter / 50.0);
  }

  double _calculateReticleGroupSize() {
    const double baseSize = 2.0;
    final resolutionFactor = _calculateResolutionFactor();
    return baseSize / resolutionFactor;
  }

  double _calculateEffectiveRange() {
    return (_parallaxDistance / 100) * 500;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: const Color(0xFFC5A059).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.center_focus_strong,
                    color: Color(0xFFC5A059),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '🎯 SCOPE SETTINGS & TOOLS',
                      style: TextStyle(
                        color: Color(0xFFC5A059),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF8B4513).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFC5A059).withValues(alpha: 0.3),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFFC5A059),
                  borderRadius: BorderRadius.circular(6),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.black,
                unselectedLabelColor: const Color(0xFFC5A059),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                tabs: const [
                  Tab(text: 'SCOPE CONFIG'),
                  Tab(text: '🔄 GYRO LEVELER'),
                  Tab(text: '📷 AI SCANNER'),
                ],
              ),
            ),
            
            // Inventory Selectors with Reactive Streams
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Firearm Stream Dropdown - uses persistent _firearmsStream reference
                  StreamBuilder<List<RifleProfile>>(
                    stream: _firearmsStream,
                    builder: (context, riflesSnapshot) {
                      // Handle error states with Thermal Glow recovery label
                      if (riflesSnapshot.hasError) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInventoryDropdown(
                              label: 'Select Weapon from Safe',
                              value: null,
                              items: [],
                              onChanged: null,
                              isLoading: false,
                              errorMessage: riflesSnapshot.error?.toString() ?? 'Unknown Error',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Offline Mode Active',
                              style: TextStyle(
                                color: const Color(0xFFC5A059),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      }
                      
                      // Handle loading and no data states
                      if (!riflesSnapshot.hasData || riflesSnapshot.connectionState == ConnectionState.waiting) {
                        return _buildInventoryDropdown(
                          label: 'Select Weapon from Safe',
                          value: null,
                          items: [],
                          onChanged: null,
                          isLoading: true,
                        );
                      }
                      
                      final rifles = riflesSnapshot.data ?? [];
                      
                      // Update selected rifle when stream data changes
                      if (rifles.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!context.mounted) return;
                          _updateRifleFromSnapshots(rifles);
                        });
                      }
                      
                      return _buildInventoryDropdown(
                        label: 'Select Weapon from Safe',
                        value: _selectedRifleId,
                        items: rifles.map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.name} (${r.caliber})'),
                        )).toList(),
                        onChanged: (id) {
                          if (!context.mounted) return;
                          _onRifleSelected(id);
                        },
                        isLoading: false,
                        onSeedRequested: rifles.isEmpty
                            ? () => _seedDefaultVaultHardware(context)
                            : null,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  
                  // Ammunition Stream Dropdown - uses persistent _ammunitionStream reference
                  StreamBuilder<List<AmmoProfile>>(
                    stream: _ammunitionStream ?? Stream.value([]),
                    builder: (context, ammoSnapshot) {
                      // Handle error states with Thermal Glow recovery label
                      if (ammoSnapshot.hasError) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInventoryDropdown(
                              label: 'Select Loaded Ammunition',
                              value: null,
                              items: [],
                              onChanged: null,
                              isLoading: false,
                              errorMessage: ammoSnapshot.error?.toString() ?? 'Unknown Error',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Offline Mode Active',
                              style: TextStyle(
                                color: const Color(0xFFC5A059),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      }
                      
                      // Handle loading and no data states
                      if (!ammoSnapshot.hasData || ammoSnapshot.connectionState == ConnectionState.waiting) {
                        return _buildInventoryDropdown(
                          label: 'Select Loaded Ammunition',
                          value: null,
                          items: [],
                          onChanged: null,
                          isLoading: true,
                        );
                      }
                      
                      final ammoList = ammoSnapshot.data ?? [];
                      
                      return _buildInventoryDropdown(
                        label: 'Select Loaded Ammunition',
                        value: _selectedAmmoId,
                        items: ammoList.map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.bulletWeightGrains}gr (${a.remainingStockCount} remaining)'),
                        )).toList(),
                        onChanged: (id) {
                          if (!context.mounted) return;
                          _onAmmoSelected(id);
                        },
                        isLoading: false,
                      );
                    },
                  ),
                ],
              ),
            ),
            
            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildScopeConfigTab(),
                  _buildGyroLevelerTab(),
                  _buildAiScannerTab(),
                ],
              ),
            ),
            
            // Footer Action Buttons
            _buildFooterButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
    required bool isLoading,
    VoidCallback? onSeedRequested,
    String? errorMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFC5A059),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF8B4513).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: errorMessage != null 
                  ? const Color(0xFFB22222).withValues(alpha: 0.5)
                  : const Color(0xFFC5A059).withValues(alpha: 0.3),
            ),
          ),
          child: isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFC5A059),
                      ),
                    ),
                  ),
                )
              : errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        errorMessage,
                        style: const TextStyle(color: Color(0xFFC5A059)),
                      ),
                    )
                  : items.isEmpty
                      ? _buildSeedButton(onSeedRequested)
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: value,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2A2A2A),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            hint: const Text('No items available', style: TextStyle(color: Colors.grey)),
                            items: items,
                            onChanged: onChanged,
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildSeedButton(VoidCallback? onSeedRequested) {
    if (onSeedRequested == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No data available', style: TextStyle(color: Colors.grey)),
      );
    }
    
    return InkWell(
      onTap: onSeedRequested,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFC5A059).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFC5A059)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_download, color: Color(0xFFC5A059), size: 18),
            SizedBox(width: 8),
            Text(
              'Seed Default Vault Hardware',
              style: TextStyle(
                color: Color(0xFFC5A059),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedDefaultVaultHardware(BuildContext context) async {
    if (!context.mounted) return;
    
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seeding default vault hardware...'),
        backgroundColor: Color(0xFFC5A059),
        duration: Duration(seconds: 2),
      ),
    );
    
    try {
      // Add default rifles
      final tikkaRifle = RifleProfile(
        id: '',
        name: 'Tikka 6.5 CM',
        caliber: '6.5mm Creedmoor',
        scopeClickValue: 0.25,
        serialNumber: 'TIKKA-2024-001',
      );
      final sakoRifle = RifleProfile(
        id: '',
        name: 'Sako .308',
        caliber: '.308 Winchester',
        scopeClickValue: 0.25,
        serialNumber: 'SAKO-2024-001',
      );
      
      final tikkaId = await _inventoryBridge.addRifleToSafe(tikkaRifle);
      final sakoId = await _inventoryBridge.addRifleToSafe(sakoRifle);
      
      if (!context.mounted) return;
      
      // Add default ammunition for each rifle
      if (tikkaId != null) {
        final tikkaAmmo = AmmoProfile(
          id: '',
          rifleId: tikkaId,
          bulletWeightGrains: 140,
          velocityMs: 810.0,
          ballisticCoefficient: 0.487,
          remainingStockCount: 20,
        );
        await _inventoryBridge.addAmmunition(tikkaAmmo);
      }
      
      if (sakoId != null) {
        final sakoAmmo = AmmoProfile(
          id: '',
          rifleId: sakoId,
          bulletWeightGrains: 175,
          velocityMs: 800.0,
          ballisticCoefficient: 0.435,
          remainingStockCount: 15,
        );
        await _inventoryBridge.addAmmunition(sakoAmmo);
      }
      
      if (!context.mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default vault hardware seeded successfully!'),
          backgroundColor: Color(0xFF4CAF50),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error seeding vault: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildScopeConfigTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 
            MediaQuery.of(context).padding.bottom + 16,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reticle Type Selection
          _buildSectionHeader('Reticle Configuration'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF8B4513).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFC5A059).withValues(alpha: 0.2),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedReticle,
                isExpanded: true,
                dropdownColor: const Color(0xFF2A2A2A),
                style: const TextStyle(color: Colors.white),
                items: _reticleTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  if (!context.mounted) return;
                  setState(() => _selectedReticle = value!);
                },
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Scope Dimensions
          _buildSectionHeader('Scope Dimensions'),
          const SizedBox(height: 8),
          _buildSliderTile(
            label: 'Tube Diameter',
            value: _tubeDiameter,
            unit: 'mm',
            min: 25.0,
            max: 40.0,
            onChanged: (v) => setState(() => _tubeDiameter = v),
          ),
          _buildSliderTile(
            label: 'Objective Diameter',
            value: _objectiveDiameter,
            unit: 'mm',
            min: 40.0,
            max: 60.0,
            onChanged: (v) => setState(() => _objectiveDiameter = v),
          ),

          const SizedBox(height: 20),

          // Click Value Settings
          _buildSectionHeader('Adjustment Settings'),
          const SizedBox(height: 8),
          _buildSliderTile(
            label: 'Click Value',
            value: _clickValue,
            unit: 'MOA',
            min: 0.1,
            max: 1.0,
            divisions: 9,
            onChanged: (v) => setState(() => _clickValue = v),
          ),

          const SizedBox(height: 20),

          // Turret Adjustments
          _buildSectionHeader('Turret Adjustments'),
          const SizedBox(height: 8),
          _buildSliderTile(
            label: 'Elevation',
            value: _elevationAdjustment,
            unit: 'MOA',
            min: -20.0,
            max: 20.0,
            onChanged: (v) => setState(() => _elevationAdjustment = v),
          ),
          _buildSliderTile(
            label: 'Windage',
            value: _windageAdjustment,
            unit: 'MOA',
            min: -20.0,
            max: 20.0,
            onChanged: (v) => setState(() => _windageAdjustment = v),
          ),

          const SizedBox(height: 20),

          // Parallax Settings
          _buildSectionHeader('Parallax Correction'),
          const SizedBox(height: 8),
          _buildSliderTile(
            label: 'Parallax Distance',
            value: _parallaxDistance,
            unit: 'yd',
            min: 50.0,
            max: 300.0,
            divisions: 25,
            onChanged: (v) => setState(() => _parallaxDistance = v),
          ),

          const SizedBox(height: 20),

          // Illumination Settings
          _buildSectionHeader('Illumination'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text(
              'Illuminated Reticle',
              style: TextStyle(color: Colors.white),
            ),
            value: _isIlluminated,
            activeTrackColor: const Color(0xFFC5A059),
            onChanged: (v) {
              if (!context.mounted) return;
              setState(() => _isIlluminated = v);
            },
          ),
          if (_isIlluminated)
            _buildSliderTile(
              label: 'Brightness Level',
              value: _illuminationLevel,
              unit: '',
              min: 1.0,
              max: 10.0,
              divisions: 9,
              onChanged: (v) => setState(() => _illuminationLevel = v),
            ),

          const SizedBox(height: 24),

          // Calculated Values Display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFC5A059).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFC5A059).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CALCULATED VALUES',
                  style: TextStyle(
                    color: Color(0xFFC5A059),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                _buildCalcRow(
                  'Resolution Factor',
                  _calculateResolutionFactor().toStringAsFixed(3),
                ),
                _buildCalcRow(
                  'Reticle Group Size',
                  '${_calculateReticleGroupSize().toStringAsFixed(3)} MOA',
                ),
                _buildCalcRow(
                  'Effective Range',
                  '${_calculateEffectiveRange().toStringAsFixed(0)} yards',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildGyroLevelerTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 
            MediaQuery.of(context).padding.bottom + 16,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // HUD Ring Widget
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF8B4513).withValues(alpha: 0.3),
              border: Border.all(
                color: const Color(0xFFC5A059),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC5A059).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Crosshairs
                CustomPaint(
                  size: const Size(260, 260),
                  painter: _GyroCrosshairPainter(),
                ),
                // Angle indicator
                Transform.rotate(
                  angle: _barrelAngle * pi / 180.0,
                  child: Container(
                    width: 160,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _barrelAngle.abs() < 1
                          ? const Color(0xFFC5A059)
                          : (_barrelAngle > 0 ? Colors.green : Colors.red),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: (_barrelAngle > 0 ? Colors.green : Colors.red)
                              .withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                // Center bubble
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _barrelAngle.abs() < 1
                        ? const Color(0xFFC5A059)
                        : Colors.grey,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                ),
                // Angle text
                Positioned(
                  top: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_barrelAngle.toStringAsFixed(1)}°',
                      style: const TextStyle(
                        color: Color(0xFFC5A059),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ⚡ ACTIVATE CORE GYRO RADAR LEVELER Toggle Card (v20.1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isLiveGyroRadarActive 
                  ? Colors.green.withValues(alpha: 0.2)
                  : const Color(0xFF8B4513).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isLiveGyroRadarActive
                    ? Colors.green
                    : const Color(0xFFC5A059).withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: Row(
                    children: [
                      Icon(
                        _isLiveGyroRadarActive 
                            ? Icons.sensors 
                            : Icons.sensors_off,
                        color: const Color(0xFFC5A059),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '⚡ ACTIVATE CORE GYRO RADAR LEVELER',
                          style: TextStyle(
                            color: Color(0xFFC5A059),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: _isLiveGyroRadarActive
                      ? const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber, 
                                   color: Colors.amber, 
                                   size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '⚠️ HARDWARE GYRO ACTIVE • PLACE FLAT ON BARREL CHASSIS',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Uses built-in accelerometer for real-time pitch detection',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                  value: _isLiveGyroRadarActive,
                  activeThumbColor: const Color(0xFFC5A059),
                  activeTrackColor: const Color(0xFFC5A059).withValues(alpha: 0.5),
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                  onChanged: _toggleLiveGyroLeveler,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Barrel Angle Slider
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF8B4513).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFC5A059).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                _buildSectionHeader('Gyroscopic Barrel Sensor'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('-45°', style: TextStyle(color: Colors.white54)),
                    Expanded(
                      child: Slider(
                        value: _barrelAngle,
                        min: -45.0,
                        max: 45.0,
                        divisions: 90,
                        thumbColor: const Color(0xFFC5A059),
                        inactiveColor: Colors.grey.withValues(alpha: 0.3),
                        onChanged: (v) {
                          // Silent execution gate preserves values when gyro is active
                          if (_isLiveGyroRadarActive) return;
                          setState(() => _barrelAngle = v);
                          _updateGyroCalculation();
                        },
                      ),
                    ),
                    const Text('+45°', style: TextStyle(color: Colors.white54)),
                  ],
                ),
                const SizedBox(height: 8),
                _buildSliderTile(
                  label: 'Line of Sight',
                  value: _lineOfSightDistance,
                  unit: 'm',
                  min: 50.0,
                  max: 500.0,
                  divisions: 45,
                  onChanged: (v) {
                    // Silent execution gate preserves values when gyro is active
                    if (_isLiveGyroRadarActive) return;
                    setState(() => _lineOfSightDistance = v);
                    _updateGyroCalculation();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Calculated Result
          if (_gyroResult != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFC5A059).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFC5A059).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HOLD DIRECTION',
                    style: TextStyle(
                      color: Color(0xFFC5A059),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCalcRow('True Horizontal', '${_gyroResult!.trueHorizontalDistance.toStringAsFixed(1)} m'),
                  _buildCalcRow('Direction', _gyroResult!.direction),
                  _buildCalcRow('Click Adjustment', '${_gyroResult!.clickUnits.toStringAsFixed(1)} clicks'),
                  const Divider(color: Color(0xFFC5A059), height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B4513),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _gyroResult!.tacticalOutput,
                      style: const TextStyle(
                        color: Color(0xFFC5A059),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAiScannerTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 
            MediaQuery.of(context).padding.bottom + 16,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Camera Capture Overlay
          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFC5A059),
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                // Grid overlay
                CustomPaint(
                  size: const Size(double.infinity, 220),
                  painter: _ScannerGridPainter(),
                ),
                // Center crosshair
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFC5A059),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.center_focus_strong,
                        color: Color(0xFFC5A059),
                        size: 30,
                      ),
                    ),
                  ),
                ),
                // Corner brackets
                Positioned(
                  top: 10,
                  left: 10,
                  child: _buildCornerBracket(),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Transform.scale(
                    scaleX: -1,
                    child: _buildCornerBracket(),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: Transform.scale(
                    scaleY: -1,
                    child: _buildCornerBracket(),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Transform.scale(
                    scaleX: -1,
                    scaleY: -1,
                    child: _buildCornerBracket(),
                  ),
                ),
                // Scan button
                if (_scanData.isEmpty)
                  Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC5A059),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      onPressed: _runTargetScan,
                      icon: const Icon(Icons.camera_alt, color: Colors.black),
                      label: const Text(
                        '📷 SCAN TARGET SHEET',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                // Scanned data visualization
                if (_scanData.isNotEmpty && _groupCenter != null)
                  CustomPaint(
                    size: const Size(double.infinity, 220),
                    painter: _ShotGroupPainter(
                      hits: _scanData,
                      center: _groupCenter!,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Target Distance Settings
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF8B4513).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFC5A059).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                _buildSectionHeader('Target Parameters'),
                const SizedBox(height: 12),
                _buildSliderTile(
                  label: 'Target Distance',
                  value: _targetDistance,
                  unit: 'm',
                  min: 50.0,
                  max: 500.0,
                  divisions: 45,
                  onChanged: (v) => setState(() => _targetDistance = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Scope Type:',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'MOA', label: Text('MOA')),
                          ButtonSegment(value: 'MRAD', label: Text('MRAD')),
                        ],
                        selected: {_scopeUnitType},
                        onSelectionChanged: (v) {
                          setState(() => _scopeUnitType = v.first);
                        },
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return const Color(0xFFC5A059);
                            }
                            return Colors.transparent;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Correction Results
          if (_correctionResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFC5A059).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFC5A059).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI TARGET CORRECTION',
                    style: TextStyle(
                      color: Color(0xFFC5A059),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_groupCenter != null) ...[
                    _buildCalcRow('Group Center X', '${_groupCenter!['x']!.toStringAsFixed(2)} cm'),
                    _buildCalcRow('Group Center Y', '${_groupCenter!['y']!.toStringAsFixed(2)} cm'),
                    _buildCalcRow('Shot Count', '${_scanData.length}'),
                  ],
                  const Divider(color: Color(0xFFC5A059), height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B4513),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _correctionResult!,
                      style: const TextStyle(
                        color: Color(0xFFC5A059),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Re-scan button
          if (_scanData.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFC5A059)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _runTargetScan,
              icon: const Icon(Icons.refresh, color: Color(0xFFC5A059)),
              label: const Text(
                'RESCAN TARGET',
                style: TextStyle(color: Color(0xFFC5A059)),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCornerBracket() {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFC5A059), width: 2),
          left: BorderSide(color: Color(0xFFC5A059), width: 2),
        ),
      ),
    );
  }

  Widget _buildFooterButtons() {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 
            MediaQuery.of(context).padding.bottom + 16,
        left: 20,
        right: 20,
        top: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFC5A059).withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFC5A059)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC5A059),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                if (!context.mounted) return;
                _saveScopeSettings();
                Navigator.of(context).pop();
              },
              child: const Text(
                'APPLY SETTINGS',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFFC5A059),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSliderTile({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              thumbColor: const Color(0xFFC5A059),
              inactiveColor: Colors.grey.withValues(alpha: 0.3),
              onChanged: (v) {
                if (!context.mounted) return;
                onChanged(v);
              },
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(
                color: Color(0xFFC5A059),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalcRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFC5A059),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _saveScopeSettings() {
    debugPrint('Scope settings saved:');
    debugPrint('  Rifle: ${_selectedRifle?.name ?? "None"}');
    debugPrint('  Ammo: ${_selectedAmmoId ?? "None"}');
    debugPrint('  Reticle: $_selectedReticle');
    debugPrint('  Click Value: $_clickValue MOA');
    debugPrint('  Tube: $_tubeDiameter mm');
    debugPrint('  Objective: $_objectiveDiameter mm');
    debugPrint('  Elevation: $_elevationAdjustment MOA');
    debugPrint('  Windage: $_windageAdjustment MOA');
    debugPrint('  Parallax: $_parallaxDistance yd');
    debugPrint('  Illuminated: $_isIlluminated');
  }
}

/// Custom painter for the gyro crosshairs
class _GyroCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC5A059).withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    
    // Horizontal line
    canvas.drawLine(
      Offset(20, center.dy),
      Offset(size.width - 20, center.dy),
      paint,
    );
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, 20),
      Offset(center.dx, size.height - 20),
      paint,
    );
    
    // Inner circle
    canvas.drawCircle(center, 60, paint);
    
    // Degree markers
    final markerPaint = Paint()
      ..color = const Color(0xFFC5A059)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    for (int i = -45; i <= 45; i += 15) {
      final angle = i * pi / 180.0;
      final innerRadius = 80.0;
      final outerRadius = 90.0;
      
      final start = Offset(
        center.dx + innerRadius * sin(angle),
        center.dy - innerRadius * cos(angle),
      );
      final end = Offset(
        center.dx + outerRadius * sin(angle),
        center.dy - outerRadius * cos(angle),
      );
      
      canvas.drawLine(start, end, markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for the scanner grid overlay
class _ScannerGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC5A059).withValues(alpha: 0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Vertical lines
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    
    // Horizontal lines
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for displaying shot group on scanner
class _ShotGroupPainter extends CustomPainter {
  final List<Map<String, double>> hits;
  final Map<String, double> center;

  _ShotGroupPainter({required this.hits, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scale = 10.0; // pixels per cm

    // Draw hit markers
    final hitPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (final hit in hits) {
      final x = centerX + (hit['x'] ?? 0) * scale;
      final y = centerY - (hit['y'] ?? 0) * scale; // Invert Y for screen coordinates
      canvas.drawCircle(Offset(x, y), 4, hitPaint);
    }

    // Draw center marker
    final centerPaint = Paint()
      ..color = const Color(0xFFC5A059)
      ..style = PaintingStyle.fill;

    final cx = centerX + (center['x'] ?? 0) * scale;
    final cy = centerY - (center['y'] ?? 0) * scale;
    canvas.drawCircle(Offset(cx, cy), 6, centerPaint);

    // Draw crosshair at group center
    final crosshairPaint = Paint()
      ..color = const Color(0xFFC5A059)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(cx - 15, cy),
      Offset(cx + 15, cy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(cx, cy - 15),
      Offset(cx, cy + 15),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ShotGroupPainter oldDelegate) {
    return hits != oldDelegate.hits || center != oldDelegate.center;
  }
}
