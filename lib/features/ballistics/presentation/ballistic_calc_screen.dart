import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import '../../../services/ballistics_calculator.dart';

// Design tokens for luxury hunting theme
class AppColors {
  static const Color walnutLuxury = Color(0xFF8B4513); // Primary graph bounds
  static const Color thermalGlow = Color(0xFFC5A059); // Trace trajectories
  static const Color midnightSlate = Color(0xFF2F3640); // Background accents
  static const Color forestDrab = Color(0xFF556B2F); // Secondary elements
}

// Offline ammunition fallback data for App Check / network error scenarios
class OfflineAmmunitionData {
  static const List<Map<String, dynamic>> commonFactoryAmmunition = [
    {'brand': 'Federal', 'description': 'Power-Shok', 'caliber': '.308 Winchester', 'bullet_grain': 150, 'muzzle_velocity': 2820, 'bc': 0.418},
    {'brand': 'Federal', 'description': 'Power-Shok', 'caliber': '.308 Winchester', 'bullet_grain': 180, 'muzzle_velocity': 2620, 'bc': 0.475},
    {'brand': 'Remington', 'description': 'Core-Lokt', 'caliber': '.308 Winchester', 'bullet_grain': 150, 'muzzle_velocity': 2790, 'bc': 0.410},
    {'brand': 'Remington', 'description': 'Core-Lokt', 'caliber': '.308 Winchester', 'bullet_grain': 180, 'muzzle_velocity': 2620, 'bc': 0.465},
    {'brand': 'Hornady', 'description': 'American Whitetail', 'caliber': '.308 Winchester', 'bullet_grain': 150, 'muzzle_velocity': 2830, 'bc': 0.415},
    {'brand': 'Hornady', 'description': 'American Whitetail', 'caliber': '.308 Winchester', 'bullet_grain': 180, 'muzzle_velocity': 2550, 'bc': 0.480},
    {'brand': 'Winchester', 'description': 'Power-Point', 'caliber': '.308 Winchester', 'bullet_grain': 150, 'muzzle_velocity': 2820, 'bc': 0.420},
    {'brand': 'Winchester', 'description': 'Power-Point', 'caliber': '.308 Winchester', 'bullet_grain': 180, 'muzzle_velocity': 2620, 'bc': 0.470},
    {'brand': 'Federal', 'description': 'Power-Shok', 'caliber': '.243 Winchester', 'bullet_grain': 95, 'muzzle_velocity': 3100, 'bc': 0.355},
    {'brand': 'Federal', 'description': 'Power-Shok', 'caliber': '.243 Winchester', 'bullet_grain': 100, 'muzzle_velocity': 2960, 'bc': 0.380},
    {'brand': 'Remington', 'description': 'Core-Lokt', 'caliber': '.243 Winchester', 'bullet_grain': 100, 'muzzle_velocity': 2960, 'bc': 0.370},
    {'brand': 'Hornady', 'description': 'American Whitetail', 'caliber': '.243 Winchester', 'bullet_grain': 95, 'muzzle_velocity': 3100, 'bc': 0.355},
    {'brand': 'Winchester', 'description': 'Ballistic Silvertip', 'caliber': '.308 Winchester', 'bullet_grain': 168, 'muzzle_velocity': 2700, 'bc': 0.475},
    {'brand': 'Nosler', 'description': 'Partition', 'caliber': '.308 Winchester', 'bullet_grain': 180, 'muzzle_velocity': 2600, 'bc': 0.490},
    {'brand': 'Barnes', 'description': 'TSX', 'caliber': '.308 Winchester', 'bullet_grain': 165, 'muzzle_velocity': 2680, 'bc': 0.480},
  ];

  static const List<Map<String, dynamic>> commonCalibers = [
    {'id': 'cal_001', 'name': '.308 Winchester', 'caliber': '.308 Winchester'},
    {'id': 'cal_002', 'name': '.243 Winchester', 'caliber': '.243 Winchester'},
    {'id': 'cal_003', 'name': '6.5mm Creedmoor', 'caliber': '6.5mm Creedmoor'},
    {'id': 'cal_004', 'name': '.270 Winchester', 'caliber': '.270 Winchester'},
    {'id': 'cal_005', 'name': '.30-06 Springfield', 'caliber': '.30-06 Springfield'},
    {'id': 'cal_006', 'name': '.300 Win Mag', 'caliber': '.300 Win Mag'},
  ];
}

bool checkCaliberMatch(String? weaponCaliber, String? dbCaliber) {
  if (weaponCaliber == null || dbCaliber == null) return false;
  String clean(String s) => s.replaceAll(RegExp(r'[\s\-\.]'), '').toLowerCase();
  String wClean = clean(weaponCaliber);
  String dClean = clean(dbCaliber);
  if ((wClean == "243" || wClean == "6mm") && (dClean.contains("243") || dClean.contains("6mm"))) return true;
  if ((wClean == "308" || wClean == "7.62") && (dClean.contains("308") || dClean.contains("7.62"))) return true;
  return wClean.contains(dClean) || dClean.contains(wClean);
}

enum AmmoType { factory, custom }

enum DistanceUnit { yards, meters }

enum LengthUnit { inches, cm }

enum SpeedUnit { mph, kph }

class BallisticCalcScreen extends StatefulWidget {
  const BallisticCalcScreen({super.key});
  @override
  State<BallisticCalcScreen> createState() => _BallisticCalcScreenState();
}

class _BallisticCalcScreenState extends State<BallisticCalcScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Persistent stream references to prevent infinite rebuild loops
  late Stream<QuerySnapshot> _firearmsStream;
  late Stream<QuerySnapshot> _factoryAmmunitionStream;
  
  String? _selectedFirearmId;
  String? _selectedAmmunitionId;
  Map<String, dynamic>? _selectedFirearm;
  Map<String, dynamic>? _selectedAmmunition;
  AmmoType _ammoType = AmmoType.factory;

  double zeroingDistance = 100;
  double windMps = 0;
  double altitudeM = 1500;
  double temperatureC = 20;

  DistanceUnit _distanceUnit = DistanceUnit.yards;
  LengthUnit _lengthUnit = LengthUnit.inches;
  SpeedUnit _speedUnit = SpeedUnit.mph;

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize persistent stream references in lifecycle hook
    final user = FirebaseAuth.instance.currentUser;
    _firearmsStream = FirebaseFirestore.instance
        .collection('firearms')
        .where('ownerId', isEqualTo: user?.uid ?? '')
        .snapshots();
    
    // Factory ammunition stream (single source for all factory ammo)
    _factoryAmmunitionStream = FirebaseFirestore.instance
        .collection('factory_ammunition')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ballistic Calculator'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Factory Ammo'),
            Tab(text: 'Custom Load'),
          ],
          onTap: (i) => setState(
            () => _ammoType = i == 0 ? AmmoType.factory : AmmoType.custom,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HUD Selection Grid',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Select your firearm + load',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              _FirearmDropdown(
                firearmsStream: _firearmsStream,
                selectedId: _selectedFirearmId,
                onSelected: (firearmId, firearmData) {
                  setState(() {
                    _selectedFirearmId = firearmId;
                    _selectedFirearm = firearmData;
                    _selectedAmmunitionId = null;
                    _selectedAmmunition = null;
                  });
                },
              ),

              if (_selectedFirearmId != null) ...[
                const SizedBox(height: 12),
                _ammoType == AmmoType.factory
                    ? _FactoryAmmunitionDropdown(
                        factoryAmmunitionStream: _factoryAmmunitionStream,
                        firearmCaliber: _selectedFirearm?['caliber'],
                        selectedId: _selectedAmmunitionId,
                        onSelected: (ammoId, ammoData) {
                          setState(() {
                            _selectedAmmunitionId = ammoId;
                            _selectedAmmunition = ammoData;
                          });
                        },
                      )
                    : _CustomLoadDropdown(
                        firearmId: _selectedFirearmId,
                        firearmCaliber: _selectedFirearm?['caliber'],
                        selectedId: _selectedAmmunitionId,
                        onSelected: (ammoId, ammoData) {
                          setState(() {
                            _selectedAmmunitionId = ammoId;
                            _selectedAmmunition = ammoData;
                          });
                        },
                      ),
              ],

              const SizedBox(height: 16),
              _UnitToggles(
                distanceUnit: _distanceUnit,
                lengthUnit: _lengthUnit,
                speedUnit: _speedUnit,
                onDistanceUnitChanged: (unit) =>
                    setState(() => _distanceUnit = unit),
                onLengthUnitChanged: (unit) =>
                    setState(() => _lengthUnit = unit),
                onSpeedUnitChanged: (unit) => setState(() => _speedUnit = unit),
              ),
              if (_selectedFirearm != null && _selectedAmmunition != null) ...[
                const SizedBox(height: 24),
                _BallisticTrajectorySection(
                  firearm: _selectedFirearm!,
                  ammunition: _selectedAmmunition!,
                  zeroingDistance: zeroingDistance,
                  windMps: windMps,
                  altitudeM: altitudeM,
                  temperatureC: temperatureC,
                  distanceUnit: _distanceUnit,
                  lengthUnit: _lengthUnit,
                  speedUnit: _speedUnit,
                  onZeroingDistanceChanged: (v) =>
                      setState(() => zeroingDistance = v),
                  onWindChanged: (v) => setState(() => windMps = v),
                  onAltitudeChanged: (v) => setState(() => altitudeM = v),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FirearmDropdown extends StatefulWidget {
  final Stream<QuerySnapshot> firearmsStream;
  final String? selectedId;
  final Function(String, Map<String, dynamic>) onSelected;
  const _FirearmDropdown({
    required this.firearmsStream,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_FirearmDropdown> createState() => _FirearmDropdownState();
}

class _FirearmDropdownState extends State<_FirearmDropdown> {
  bool _isOfflineMode = false;
  List<Map<String, dynamic>> _offlineFirearms = [];

  @override
  void initState() {
    super.initState();
    _loadOfflineData();
  }

  void _loadOfflineData() {
    // Provide common firearms for offline mode
    _offlineFirearms = [
      {'make': 'Remington', 'model': '700', 'caliber': '.308 Winchester', 'docId': 'offline_1'},
      {'make': 'Ruger', 'model': 'M77', 'caliber': '.243 Winchester', 'docId': 'offline_2'},
      {'make': 'Browning', 'model': 'A-Bolt', 'caliber': '.308 Winchester', 'docId': 'offline_3'},
      {'make': 'Winchester', 'model': 'Model 70', 'caliber': '.30-06 Springfield', 'docId': 'offline_4'},
    ];
  }

  bool _isAppCheckError(Object? error) {
    if (error == null) return false;
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('appcheck') ||
        errorStr.contains('app check') ||
        errorStr.contains('developer_error') ||
        errorStr.contains('token') ||
        errorStr.contains('unavailable');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.firearmsStream,
      builder: (context, snapshot) {
        // Handle App Check / network errors with offline fallback
        if (snapshot.hasError) {
          if (_isAppCheckError(snapshot.error)) {
            setState(() => _isOfflineMode = true);
            return _buildOfflineFirearmDropdown(context);
          }
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 8),
                  Text(
                    'Firearm data unavailable',
                    style: TextStyle(
                      color: AppColors.thermalGlow,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final firearms = snapshot.data?.docs ?? [];
        if (firearms.isEmpty) {
          // Auto-switch to offline mode when no data available
          setState(() => _isOfflineMode = true);
          return _buildOfflineFirearmDropdown(context);
        }

        _isOfflineMode = false;
        return _buildDropdownCard(
          context,
          label: 'Select Firearm',
          items: firearms,
          selectedId: widget.selectedId,
          itemBuilder: (doc) {
            final data = doc.data() as Map<String, dynamic>;
            return '${data['make'] ?? ''} ${data['model'] ?? ''} • ${data['caliber'] ?? 'N/A'}';
          },
          onSelected: (doc) {
            final data = Map<String, dynamic>.from(doc.data() as Map);
            data['docId'] = doc.id;
            widget.onSelected(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildOfflineFirearmDropdown(BuildContext context) {
    final filtered = _offlineFirearms
        .where((f) => f['caliber'] != null)
        .toList();

    if (filtered.isEmpty) {
      return _buildNoFirearmsWarning(context);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.offline_bolt, color: AppColors.thermalGlow, size: 20),
                const SizedBox(width: 8),
                Text('Offline Mode', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: filtered.any((f) => f['docId'] == widget.selectedId)
                  ? widget.selectedId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: filtered
                  .map((doc) => DropdownMenuItem(
                        value: doc['docId'] as String,
                        child: Text(
                          '${doc['make']} ${doc['model']} • ${doc['caliber']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  final item = filtered.firstWhere((f) => f['docId'] == v);
                  widget.onSelected(v, item);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownCard(
    BuildContext context, {
    required String label,
    required List<QueryDocumentSnapshot> items,
    required String? selectedId,
    required String Function(QueryDocumentSnapshot) itemBuilder,
    required Function(QueryDocumentSnapshot) onSelected,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: items.any((d) => d.id == selectedId) ? selectedId : null,
              isExpanded: true, // FIX OVERFLOW
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: items
                  .map(
                    (doc) => DropdownMenuItem(
                      value: doc.id,
                      child: Text(
                        itemBuilder(doc),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(), // FIX OVERFLOW
              onChanged: (v) {
                if (v != null) onSelected(items.firstWhere((d) => d.id == v));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoFirearmsWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('No firearms found.'),
    );
  }
}

class _FactoryAmmunitionDropdown extends StatefulWidget {
  final Stream<QuerySnapshot> factoryAmmunitionStream;
  final String? firearmCaliber;
  final String? selectedId;
  final Function(String, Map<String, dynamic>) onSelected;
  const _FactoryAmmunitionDropdown({
    required this.factoryAmmunitionStream,
    required this.firearmCaliber,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_FactoryAmmunitionDropdown> createState() => _FactoryAmmunitionDropdownState();
}

class _FactoryAmmunitionDropdownState extends State<_FactoryAmmunitionDropdown> {
  bool _isOfflineMode = false;

  bool _isAppCheckError(Object? error) {
    if (error == null) return false;
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('appcheck') ||
        errorStr.contains('app check') ||
        errorStr.contains('developer_error') ||
        errorStr.contains('token') ||
        errorStr.contains('unavailable');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.factoryAmmunitionStream,
      builder: (context, snapshot) {
        // Intercept App Check / Security failures and provide offline tracking fallbacks
        if (snapshot.hasError) {
          if (_isAppCheckError(snapshot.error)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isOfflineMode = true);
            });
            return _buildOfflineAmmunitionDropdown(context);
          }
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 8),
                  Text(
                    'Ammunition data unavailable',
                    style: TextStyle(color: AppColors.thermalGlow),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingWidget(context);
        }

        final docs = snapshot.data?.docs ?? [];
        final filtered = docs
            .where(
              (doc) => checkCaliberMatch(
                widget.firearmCaliber ?? '',
                (doc.data() as Map)['caliber'] ?? '',
              ),
            )
            .toList();

        if (filtered.isEmpty) {
          // Switch to offline mode if no matching caliber found
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isOfflineMode = true);
          });
          return _buildOfflineAmmunitionDropdown(context);
        }

        _isOfflineMode = false;
        return _buildDropdownCard(
          context,
          label: 'Select Factory Ammunition',
          items: filtered,
          selectedId: widget.selectedId,
          itemBuilder: (doc) {
            final d = doc.data() as Map<String, dynamic>;
            final grain = d['bullet_grain'] ?? d['bulletGrain'] ?? 'N/A';
            final vel = d['muzzle_velocity'] ?? d['muzzleVelocity'] ?? 'N/A';
            final bc = d['bc'];
            final bcText = bc != null ? ' • BC: $bc' : '';
            return '${d['brand']} ${d['description']} • ${grain}gr • ${vel}fps$bcText';
          },
          onSelected: (doc) =>
              widget.onSelected(doc.id, doc.data() as Map<String, dynamic>),
        );
      },
    );
  }

  Widget _buildOfflineAmmunitionDropdown(BuildContext context) {
    final caliber = widget.firearmCaliber ?? '';
    final filtered = OfflineAmmunitionData.commonFactoryAmmunition
        .where((a) => checkCaliberMatch(caliber, a['caliber'] as String?))
        .toList();

    if (filtered.isEmpty) {
      return _buildEmptyState(context);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.offline_bolt, color: AppColors.thermalGlow, size: 20),
                const SizedBox(width: 8),
                Text('Offline Mode', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: filtered.isNotEmpty ? 'offline_0' : null,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: filtered.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return DropdownMenuItem(
                  value: 'offline_$index',
                  child: Text(
                    '${item['brand']} ${item['description']} • ${item['bullet_grain']}gr • ${item['muzzle_velocity']}fps',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  final index = int.tryParse(v.replaceFirst('offline_', '')) ?? 0;
                  if (index < filtered.length) {
                    widget.onSelected(v, Map<String, dynamic>.from(filtered[index]));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Loading ammunition...',
              style: TextStyle(
                color: AppColors.thermalGlow,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'No factory ammo found for this caliber',
              style: TextStyle(
                color: AppColors.thermalGlow,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownCard(
    BuildContext context, {
    required String label,
    required List<QueryDocumentSnapshot> items,
    required String? selectedId,
    required String Function(QueryDocumentSnapshot) itemBuilder,
    required Function(QueryDocumentSnapshot) onSelected,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: items.any((d) => d.id == selectedId) ? selectedId : null,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: items
                  .map((doc) => DropdownMenuItem(
                        value: doc.id,
                        child: Text(
                          itemBuilder(doc),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onSelected(items.firstWhere((d) => d.id == v));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomLoadDropdown extends StatefulWidget {
  final String? firearmId;
  final String? firearmCaliber;
  final String? selectedId;
  final Function(String, Map<String, dynamic>) onSelected;
  const _CustomLoadDropdown({
    required this.firearmId,
    required this.firearmCaliber,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_CustomLoadDropdown> createState() => _CustomLoadDropdownState();
}

class _CustomLoadDropdownState extends State<_CustomLoadDropdown> {
  bool _isOfflineMode = false;

  bool _isAppCheckError(Object? error) {
    if (error == null) return false;
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('appcheck') ||
        errorStr.contains('app check') ||
        errorStr.contains('developer_error') ||
        errorStr.contains('token') ||
        errorStr.contains('unavailable');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.firearmId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('firearms')
          .doc(widget.firearmId)
          .collection('ammunition')
          .snapshots(),
      builder: (context, snapshot) {
        // Intercept App Check / Security failures with offline fallback
        if (snapshot.hasError) {
          if (_isAppCheckError(snapshot.error)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isOfflineMode = true);
            });
            return _buildOfflineCustomLoadDropdown(context);
          }
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 8),
                  Text(
                    'Custom load data unavailable',
                    style: TextStyle(color: AppColors.thermalGlow),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingWidget(context);
        }

        final docs = snapshot.data?.docs ?? [];
        final filtered = docs
            .where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return d['type'] == 'custom' &&
                  checkCaliberMatch(
                    widget.firearmCaliber ?? '',
                    d['caliber'] ?? '',
                  );
            })
            .toList();

        if (filtered.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isOfflineMode = true);
          });
          return _buildOfflineCustomLoadDropdown(context);
        }

        _isOfflineMode = false;
        return _buildDropdownCard(
          context,
          label: 'Select Custom Load',
          items: filtered,
          selectedId: widget.selectedId,
          itemBuilder: (doc) {
            final d = doc.data() as Map<String, dynamic>;
            final brand = d['bulletBrand'] ?? d['bullet_brand'] ?? d['brand'] ?? 'Custom';
            final weight = d['bulletWeight'] ?? d['bullet_weight'] ?? d['weightgr'] ?? d['bulletgrain'] ?? 'N/A';
            final vel = d['muzzleVelocity'] ?? d['muzzle_velocity'] ?? d['muzzlevelocityfps'] ?? 'N/A';
            return '$brand Custom • ${weight}gr • ${vel}fps';
          },
          onSelected: (doc) =>
              widget.onSelected(doc.id, doc.data() as Map<String, dynamic>),
        );
      },
    );
  }

  Widget _buildOfflineCustomLoadDropdown(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.thermalGlow),
            const SizedBox(height: 8),
            Text(
              'No custom loads found',
              style: TextStyle(
                color: AppColors.thermalGlow,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Create one in Reloading tab',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Loading custom loads...',
              style: TextStyle(
                color: AppColors.thermalGlow,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownCard(
    BuildContext context, {
    required String label,
    required List<QueryDocumentSnapshot> items,
    required String? selectedId,
    required String Function(QueryDocumentSnapshot) itemBuilder,
    required Function(QueryDocumentSnapshot) onSelected,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: items.any((d) => d.id == selectedId) ? selectedId : null,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: items
                  .map((doc) => DropdownMenuItem(
                        value: doc.id,
                        child: Text(
                          itemBuilder(doc),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onSelected(items.firstWhere((d) => d.id == v));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitToggles extends StatelessWidget {
  final DistanceUnit distanceUnit;
  final LengthUnit lengthUnit;
  final SpeedUnit speedUnit;
  final Function(DistanceUnit) onDistanceUnitChanged;
  final Function(LengthUnit) onLengthUnitChanged;
  final Function(SpeedUnit) onSpeedUnitChanged;

  const _UnitToggles({
    required this.distanceUnit,
    required this.lengthUnit,
    required this.speedUnit,
    required this.onDistanceUnitChanged,
    required this.onLengthUnitChanged,
    required this.onSpeedUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten, color: AppColors.walnutLuxury, size: 20),
                const SizedBox(width: 8),
                Text('Units', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _UnitToggle(
                    label: 'Distance',
                    options: ['Yards', 'Meters'],
                    selectedIndex: distanceUnit == DistanceUnit.yards ? 0 : 1,
                    onChanged: (index) => onDistanceUnitChanged(
                      index == 0 ? DistanceUnit.yards : DistanceUnit.meters,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _UnitToggle(
                    label: 'Length',
                    options: ['Inches', 'CM'],
                    selectedIndex: lengthUnit == LengthUnit.inches ? 0 : 1,
                    onChanged: (index) => onLengthUnitChanged(
                      index == 0 ? LengthUnit.inches : LengthUnit.cm,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _UnitToggle(
                    label: 'Speed',
                    options: ['MPH', 'KPH'],
                    selectedIndex: speedUnit == SpeedUnit.mph ? 0 : 1,
                    onChanged: (index) => onSpeedUnitChanged(
                      index == 0 ? SpeedUnit.mph : SpeedUnit.kph,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selectedIndex;
  final Function(int) onChanged;

  const _UnitToggle({
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.thermalGlow,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.walnutLuxury.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.walnutLuxury.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              final isSelected = index == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      // Walnut Luxury primary fill for active tabs
                      color: isSelected ? AppColors.walnutLuxury : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      option,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        // Thermal Glow text for labels
                        color: isSelected ? Colors.white : AppColors.thermalGlow,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// _BallisticTrajectorySection stays the same as last file I sent you
class _BallisticTrajectorySection extends StatefulWidget {
  final Map<String, dynamic> firearm;
  final Map<String, dynamic> ammunition;
  final double zeroingDistance;
  final double windMps;
  final double altitudeM;
  final double temperatureC;
  final DistanceUnit distanceUnit;
  final LengthUnit lengthUnit;
  final SpeedUnit speedUnit;
  final Function(double) onZeroingDistanceChanged;
  final Function(double) onWindChanged;
  final Function(double) onAltitudeChanged;
  const _BallisticTrajectorySection({
    required this.firearm,
    required this.ammunition,
    required this.zeroingDistance,
    required this.windMps,
    required this.altitudeM,
    required this.temperatureC,
    required this.distanceUnit,
    required this.lengthUnit,
    required this.speedUnit,
    required this.onZeroingDistanceChanged,
    required this.onWindChanged,
    required this.onAltitudeChanged,
  });
  @override
  State<_BallisticTrajectorySection> createState() =>
      _BallisticTrajectorySectionState();
}

class _BallisticTrajectorySectionState
    extends State<_BallisticTrajectorySection> {
  List<FlSpot> _dropSpots = [];
  List<FlSpot> _windDriftSpots = [];
  double _maxDrop = 0;
  double _mpbr = 0;
  List<Point> _trajectory = [];

  @override
  void initState() {
    super.initState();
    _calculateTrajectory();
  }

  @override
  void didUpdateWidget(_BallisticTrajectorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zeroingDistance != widget.zeroingDistance ||
        oldWidget.windMps != widget.windMps ||
        oldWidget.altitudeM != widget.altitudeM ||
        oldWidget.temperatureC != widget.temperatureC) {
      _calculateTrajectory();
    }
  }

  void _calculateTrajectory() {
    // Safely extract and validate muzzle velocity
    final mvRaw = widget.ammunition['muzzle_velocity'] ?? widget.ammunition['muzzleVelocity'] ?? 2700;
    final mvFps = (mvRaw is num) ? mvRaw.toDouble() : (double.tryParse(mvRaw.toString()) ?? 2700.0);
    final safeMvFps = (mvFps.isNaN || mvFps.isInfinite) ? 2700.0 : mvFps;

    // Safely extract and validate ballistic coefficient
    final bcValue = widget.ammunition['bc'];
    double bc = 0.4;
    if (bcValue != null) {
      if (bcValue is double) {
        bc = bcValue;
      } else if (bcValue is num) {
        bc = bcValue.toDouble();
      } else {
        bc = double.tryParse(bcValue.toString()) ?? 0.4;
      }
    }
    final safeBc = (bc.isNaN || bc.isInfinite || bc <= 0) ? 0.4 : bc;

    // Safely handle zeroing distance
    final zeroYards = (widget.zeroingDistance.isNaN || widget.zeroingDistance.isInfinite || widget.zeroingDistance <= 0)
        ? 100.0 * 1.09361
        : widget.zeroingDistance * 1.09361;

    // Safely handle wind speed
    final windMph = (widget.windMps.isNaN || widget.windMps.isInfinite)
        ? 0.0
        : widget.windMps * 2.23694;

    // Calculate trajectory using ballistics_calculator
    _trajectory = calcTrajectory(
      bc: safeBc,
      mv: safeMvFps,
      zero: zeroYards,
      windMph: windMph,
      angleDeg: 0,
    );

    // Convert trajectory points to FlSpot based on selected units
    _dropSpots = _trajectory.map((p) {
      final distance = widget.distanceUnit == DistanceUnit.yards
          ? p.distance
          : p.distance * 0.9144; // yards to meters
      final drop = widget.lengthUnit == LengthUnit.inches
          ? p.drop
          : p.drop * 2.54; // inches to cm
      return FlSpot(distance, drop.isNaN ? 0.0 : drop);
    }).toList();

    _windDriftSpots = _trajectory.map((p) {
      final distance = widget.distanceUnit == DistanceUnit.yards
          ? p.distance
          : p.distance * 0.9144; // yards to meters
      final drift = widget.lengthUnit == LengthUnit.inches
          ? p.windDrift
          : p.windDrift * 2.54; // inches to cm
      return FlSpot(distance, drift.isNaN ? 0.0 : drift);
    }).toList();

    // Calculate max drop (absolute value) in selected unit
    if (_trajectory.isNotEmpty) {
      _maxDrop = _trajectory
          .map(
            (p) {
              final drop = widget.lengthUnit == LengthUnit.inches
                  ? p.drop.abs()
                  : (p.drop.abs() * 2.54);
              return drop.isNaN ? 0.0 : drop;
            },
          )
          .reduce((a, b) => a > b ? a : b);
    } else {
      _maxDrop = 0.0;
    }

    // Calculate MPBR (Maximum Point Blank Range)
    // MPBR is the distance where bullet stays within ±3 inches of line of sight
    _mpbr = _calculateMPBR(_trajectory);
  }

  double _calculateMPBR(List<Point> trajectory) {
    const double mpbrTolerance = 3.0; // inches
    double mpbr = 0;

    for (int i = 0; i < trajectory.length; i++) {
      final point = trajectory[i];
      if (point.drop.abs() <= mpbrTolerance) {
        mpbr = point.distance;
      } else {
        break;
      }
    }

    // Convert to selected distance unit
    return widget.distanceUnit == DistanceUnit.yards
        ? mpbr
        : mpbr * 0.9144; // yards to meters
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ballistic Trajectory',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        // MPBR and Max Drop cards
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MPBR',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_mpbr.toStringAsFixed(0)} ${widget.distanceUnit == DistanceUnit.yards ? 'yd' : 'm'}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Max Point Blank Range',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Max Drop',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_maxDrop.toStringAsFixed(1)}${widget.lengthUnit == LengthUnit.inches ? '"' : ' cm'}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'at ${widget.distanceUnit == DistanceUnit.yards ? '1000' : '914'} ${widget.distanceUnit == DistanceUnit.yards ? 'yd' : 'm'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Action buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveLoad,
                icon: const Icon(Icons.save),
                label: const Text('Save Load'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export PDF'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SliderCard(
          label: 'Zero Distance',
          value: widget.zeroingDistance,
          unit: 'm',
          min: 50,
          max: 300,
          onChanged: widget.onZeroingDistanceChanged,
        ),
        _SliderCard(
          label: 'Wind',
          value: widget.windMps,
          unit: 'm/s',
          min: 0,
          max: 10,
          onChanged: widget.onWindChanged,
        ),
        _SliderCard(
          label: 'Altitude',
          value: widget.altitudeM,
          unit: 'm',
          min: 0,
          max: 3000,
          onChanged: widget.onAltitudeChanged,
        ),
        const SizedBox(height: 20),
        Container(
          height: 280,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.walnutLuxury.withValues(alpha: 0.3)),
          ),
          child: LineChart(
            LineChartData(
              minY: -30,
              maxY: 20,
              lineBarsData: [
                LineChartBarData(
                  spots: _dropSpots,
                  isCurved: true,
                  barWidth: 3,
                  color: AppColors.thermalGlow, // Thermal Glow for trajectory
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: _windDriftSpots,
                  isCurved: true,
                  barWidth: 2,
                  color: AppColors.walnutLuxury, // Walnut Luxury for drift
                  dotData: const FlDotData(show: false),
                  dashArray: [5, 5],
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: widget.distanceUnit == DistanceUnit.yards
                        ? 100
                        : 91.44,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.thermalGlow,
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: widget.lengthUnit == LengthUnit.inches
                        ? 10
                        : 25.4,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.thermalGlow,
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: AppColors.walnutLuxury.withValues(alpha: 0.2),
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: AppColors.walnutLuxury.withValues(alpha: 0.2),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: AppColors.walnutLuxury),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _HoldoverCard(
          trajectory: _trajectory,
          distanceUnit: widget.distanceUnit,
          lengthUnit: widget.lengthUnit,
        ),
      ],
    );
  }

  Future<void> _saveLoad() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to save loads')),
      );
      return;
    }

    final firearmId = widget.firearm['docId'];
    if (firearmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No firearm selected')),
      );
      return;
    }

    final bc = widget.ammunition['bc_g1'] ?? widget.ammunition['bc'] ?? 0.4;
    final mv =
        widget.ammunition['muzzle_velocity'] ??
        widget.ammunition['muzzleVelocity'] ??
        2700;
    final zero = widget.zeroingDistance;

    try {
      await FirebaseFirestore.instance
          .collection('firearms')
          .doc(firearmId)
          .collection('ammunition')
          .add({
            'bulletBrand': widget.ammunition['bulletBrand'] ?? widget.ammunition['bullet_brand'] ?? widget.ammunition['brand'] ?? 'Custom',
            'caliber': widget.firearm['caliber'],
            'bulletWeight': widget.ammunition['bulletWeight'] ?? widget.ammunition['bullet_weight'] ?? widget.ammunition['bulletgrain'] ?? 0,
            'propellantBrand': widget.ammunition['propellantBrand'] ?? 'Custom',
            'propellantType': widget.ammunition['propellantType'] ?? 'Custom',
            'muzzleVelocity': mv,
            'bc': bc,
            'zeroDistance': zero,
            'type': 'custom',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Load saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving load: $e')));
      }
    }
  }

  Future<void> _exportPdf() async {
    final doc = pw.Document();

    final mv =
        widget.ammunition['muzzle_velocity'] ??
        widget.ammunition['muzzleVelocity'] ??
        2700;
    final bc = widget.ammunition['bc_g1'] ?? widget.ammunition['bc'] ?? 0.4;

    doc.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Ballistic Trajectory Report',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Generated: ${DateTime.now().toIso8601String().split('T').first}',
                style: pw.TextStyle(fontSize: 10, color: pdf.PdfColors.grey700),
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                'Firearm: ${widget.firearm['make']} ${widget.firearm['model']}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('Caliber: ${widget.firearm['caliber']}'),
              pw.SizedBox(height: 16),
              pw.Text(
                'Ammunition Data',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('Ballistic Coefficient: $bc'),
              pw.Text('Muzzle Velocity: $mv fps'),
              pw.Text('Zero Distance: ${widget.zeroingDistance} m'),
              pw.SizedBox(height: 16),
              pw.Text(
                'Environmental Conditions',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('Wind: ${widget.windMps} m/s'),
              pw.Text('Altitude: ${widget.altitudeM} m'),
              pw.Text('Temperature: ${widget.temperatureC}°C'),
              pw.SizedBox(height: 16),
              pw.Text(
                'Trajectory Data',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: pdf.PdfColors.grey200),
                    children: [
                      _buildPdfCell(
                        'Distance (${widget.distanceUnit == DistanceUnit.yards ? 'yd' : 'm'})',
                        isHeader: true,
                      ),
                      _buildPdfCell(
                        'Drop (${widget.lengthUnit == LengthUnit.inches ? 'in' : 'cm'})',
                        isHeader: true,
                      ),
                      _buildPdfCell(
                        'Drift (${widget.lengthUnit == LengthUnit.inches ? 'in' : 'cm'})',
                        isHeader: true,
                      ),
                      _buildPdfCell('Velocity (fps)', isHeader: true),
                    ],
                  ),
                  ..._trajectory.map((point) {
                    final distance = widget.distanceUnit == DistanceUnit.yards
                        ? point.distance
                        : point.distance * 0.9144;
                    final drop = widget.lengthUnit == LengthUnit.inches
                        ? point.drop
                        : point.drop * 2.54;
                    final drift = widget.lengthUnit == LengthUnit.inches
                        ? point.windDrift
                        : point.windDrift * 2.54;
                    return pw.TableRow(
                      children: [
                        _buildPdfCell(distance.toStringAsFixed(0)),
                        _buildPdfCell(drop.abs().toStringAsFixed(2)),
                        _buildPdfCell(drift.abs().toStringAsFixed(2)),
                        _buildPdfCell(point.velocity.toStringAsFixed(0)),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'MPBR: ${_mpbr.toStringAsFixed(0)} ${widget.distanceUnit == DistanceUnit.yards ? 'yd' : 'm'}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Max Drop: ${_maxDrop.toStringAsFixed(1)}${widget.lengthUnit == LengthUnit.inches ? '"' : ' cm'}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'ballistic_trajectory',
    );
  }

  pw.Widget _buildPdfCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  const _SliderCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label)),
                Text(
                  '${value.toStringAsFixed(0)} $unit',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) / 10).round(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldoverCard extends StatelessWidget {
  final List<Point> trajectory;
  final DistanceUnit distanceUnit;
  final LengthUnit lengthUnit;
  const _HoldoverCard({
    required this.trajectory,
    required this.distanceUnit,
    required this.lengthUnit,
  });

  double _calculateMOA(double dropInches, double distanceYards) {
    if (distanceYards <= 0) return 0.0;
    return (dropInches / distanceYards) * 100;
  }

  int _calculateClicks(double moa, {double clickSize = 0.25}) {
    return (moa / clickSize).round();
  }

  @override
  Widget build(BuildContext context) {
    // Use 500 yards as a reference distance for holdover calculation
    final referenceDistance = 500.0;
    final referencePoint = trajectory.firstWhere(
      (p) => p.distance >= referenceDistance,
      orElse: () => trajectory.last,
    );

    final dropInches = referencePoint.drop.abs();
    final distanceYards = referencePoint.distance;
    final moa = _calculateMOA(dropInches, distanceYards);
    final clicks = _calculateClicks(moa);

    // Calculate wind drift at 10 mph for the reference distance
    final windDrift10mph = referencePoint.windDrift.abs();

    final distanceDisplay = distanceUnit == DistanceUnit.yards
        ? '${distanceYards.toStringAsFixed(0)} yd'
        : '${(distanceYards * 0.9144).toStringAsFixed(0)} m';

    final driftDisplay = lengthUnit == LengthUnit.inches
        ? '${windDrift10mph.toStringAsFixed(2)}"'
        : '${(windDrift10mph * 2.54).toStringAsFixed(2)} cm';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Holdover Data',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Hold: ${moa.toStringAsFixed(2)} MOA at $distanceDisplay',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Wind 10mph = $driftDisplay drift at $distanceDisplay',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Scope Clicks (1/4 MOA): $clicks clicks',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
