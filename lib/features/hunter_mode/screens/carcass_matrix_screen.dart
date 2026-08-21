import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../services/carcass_log_manager.dart';
import '../services/offline_sync_queue.dart';
import '../services/map_path_tracer.dart';
import 'meat_processing_screen.dart';
import 'meat_processing_order_history_screen.dart';
import '../../../core/utils/measurement_formatter.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';

class CarcassMatrixScreen extends StatefulWidget {
  final ThemeController theme;

  const CarcassMatrixScreen({super.key, required this.theme});

  @override
  State<CarcassMatrixScreen> createState() => _CarcassMatrixScreenState();
}

class _CarcassMatrixScreenState extends State<CarcassMatrixScreen> {
  final CarcassLogManager _carcassLogManager = CarcassLogManager();
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _tagNumberController = TextEditingController();
  final _fieldWeightController = TextEditingController();
  final _hangingWeightController = TextEditingController();

  String _selectedSpecies = 'Impala';
  String _selectedChillerPosition = 'Chiller A - Hook 1';
  bool _isSubmitting = false;
  bool _isLocationCapturing = false;

  // Harvest location coordinates
  double? _capturedLatitude;
  double? _capturedLongitude;
  String _locationStatusText = 'No location pinned';

  Future<void> _pinHarvestLocation() async {
    setState(() {
      _isLocationCapturing = true;
      _locationStatusText = 'Acquiring GPS signal...';
    });

    try {
      // Check permissions first
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services disabled');
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _capturedLatitude = position.latitude;
        _capturedLongitude = position.longitude;
        _locationStatusText =
            "Coordinates Locked: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}";
        _isLocationCapturing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 ${_locationStatusText}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Fallback to MapPathTracer last known location
      final lastPath = MapPathTracer.instance.currentPath;
      if (lastPath.isNotEmpty) {
        final lastPoint = lastPath.last;
        setState(() {
          _capturedLatitude = lastPoint.latitude;
          _capturedLongitude = lastPoint.longitude;
          _locationStatusText =
              "Fallback: ${lastPoint.latitude.toStringAsFixed(4)}, ${lastPoint.longitude.toStringAsFixed(4)} (from trail)";
          _isLocationCapturing = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📍 Using last known trail coordinates'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        setState(() {
          _locationStatusText = 'Failed to capture location';
          _isLocationCapturing = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  static const List<String> _speciesOptions = [
    'Impala',
    'Kudu',
    'Wildebeest',
    'Zebra',
    'Warthog',
    'Bushpig',
    'Eland',
    'Gemsbok',
    'Springbok',
    'Blesbok',
    'Waterbuck',
    'Red Hartebeest',
    'Black Wildebeest',
    'Sable Antelope',
    'Roan Antelope',
    'Nyala',
    'Buffalo',
    'Hippo',
    'Crocodile',
    'Other',
  ];

  static const List<String> _chillerPositions = [
    'Chiller A - Hook 1',
    'Chiller A - Hook 2',
    'Chiller A - Hook 3',
    'Chiller A - Hook 4',
    'Chiller A - Hook 5',
    'Chiller A - Hook 6',
    'Chiller A - Hook 7',
    'Chiller A - Hook 8',
    'Chiller A - Hook 9',
    'Chiller A - Hook 10',
    'Chiller A - Hook 11',
    'Chiller A - Hook 12',
    'Chiller A - Hook 13',
    'Chiller A - Hook 14',
    'Chiller A - Hook 15',
    'Chiller B - Hook 1',
    'Chiller B - Hook 2',
    'Chiller B - Hook 3',
    'Chiller B - Hook 4',
    'Chiller B - Hook 5',
    'Chiller B - Hook 6',
    'Chiller B - Hook 7',
    'Chiller B - Hook 8',
    'Chiller B - Hook 9',
    'Chiller B - Hook 10',
    'Chiller B - Hook 11',
    'Chiller B - Hook 12',
    'Chiller B - Hook 13',
    'Chiller B - Hook 14',
    'Chiller B - Hook 15',
  ];

  @override
  void dispose() {
    _tagNumberController.dispose();
    _fieldWeightController.dispose();
    _hangingWeightController.dispose();
    super.dispose();
  }

  Future<void> _submitCarcassLog() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await _carcassLogManager.logCarcass(
        tagNumber: _tagNumberController.text.trim(),
        species: _selectedSpecies,
        fieldWeight: double.parse(_fieldWeightController.text.trim()),
        hangingWeight: double.parse(_hangingWeightController.text.trim()),
        coldStoragePosition: _selectedChillerPosition,
      );

      // If coordinates were captured, also save a Kill Site waypoint
      if (_capturedLatitude != null && _capturedLongitude != null) {
        try {
          await FirebaseFirestore.instance.collection('waypoints').add({
            'hunterId': FirebaseAuth.instance.currentUser?.uid,
            'name':
                'Harvest: ${_tagNumberController.text.trim()} (${_selectedSpecies})',
            'type': 'Kill Site',
            'lat': _capturedLatitude,
            'lon': _capturedLongitude,
            'timestamp': FieldValue.serverTimestamp(),
          });
        } catch (waypointError) {
          // Queue waypoint if network fails
          await OfflineSyncQueue.instance.enqueueAction('waypoints', 'CREATE', {
            'name':
                'Harvest: ${_tagNumberController.text.trim()} (${_selectedSpecies})',
            'type': 'Kill Site',
            'lat': _capturedLatitude,
            'lon': _capturedLongitude,
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _capturedLatitude != null
                  ? '✅ Carcass logged + Kill Site waypoint created'
                  : '✅ Carcass logged to $_selectedChillerPosition',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _formKey.currentState!.reset();
        _tagNumberController.clear();
        _fieldWeightController.clear();
        _hangingWeightController.clear();
        setState(() {
          _selectedSpecies = 'Impala';
          _selectedChillerPosition = 'Chiller A - Hook 1';
          _capturedLatitude = null;
          _capturedLongitude = null;
          _locationStatusText = 'No location pinned';
        });
      }
    } catch (e) {
      // Network link dropped - write to local SQLite storage instead
      try {
        // Queue Carcass Log
        await OfflineSyncQueue.instance
            .enqueueAction('carcass_logs', 'CREATE', {
              'tagNumber': _tagNumberController.text.trim(),
              'species': _selectedSpecies,
              'fieldWeightKg': double.parse(_fieldWeightController.text.trim()),
              'hangingWeightKg': double.parse(
                _hangingWeightController.text.trim(),
              ),
              'coldStoragePosition': _selectedChillerPosition,
              'status': 'Hanging',
            });

        // Queue Associated Map Pin Waypoint if coordinates captured
        if (_capturedLatitude != null && _capturedLongitude != null) {
          await OfflineSyncQueue.instance.enqueueAction('waypoints', 'CREATE', {
            'name':
                'Harvest: ${_tagNumberController.text.trim()} (${_selectedSpecies})',
            'type': 'Kill Site',
            'lat': _capturedLatitude,
            'lon': _capturedLongitude,
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _capturedLatitude != null
                    ? '📱 Saved locally. Carcass + Kill Site queued for sync.'
                    : '📱 Saved locally. Carcass queued for sync when back in range.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          _formKey.currentState!.reset();
          _tagNumberController.clear();
          _fieldWeightController.clear();
          _hangingWeightController.clear();
          setState(() {
            _selectedSpecies = 'Impala';
            _selectedChillerPosition = 'Chiller A - Hook 1';
            _capturedLatitude = null;
            _capturedLongitude = null;
            _locationStatusText = 'No location pinned';
          });
        }
      } catch (queueError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error saving carcass: $queueError'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return HunterScaffold(
      theme: widget.theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: Text(
          '🥩 SLAUGHTERHOUSE CARCASS MATRIX',
          style: TextStyle(
            color: HunterUi.titleColor(theme),
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: HunterUi.titleColor(widget.theme)),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Order Logs',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      MeatProcessingOrderHistoryScreen(theme: theme),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick Log Form Panel
              _buildLogFormCard(theme),
              const SizedBox(height: 24),

              // Active Chiller Records
              Text(
                '📦 ACTIVE CHILLER INVENTORY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.subtitleColor,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildChillerRecordsStream(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogFormCard(ThemeController theme) {
    return Card(
      color: HunterUi.cardColor(theme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.add_box_rounded, color: theme.accentColor),
                  const SizedBox(width: 10),
                  Text(
                    'QUICK LOG ENTRY',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.textColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tag Number
              TextFormField(
                controller: _tagNumberController,
                style: TextStyle(color: theme.textColor),
                decoration: _inputDecoration(
                  'Tag Number (e.g., TAG-2024-001)',
                  Icons.tag,
                  theme,
                ),
                validator:
                    (val) =>
                        val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Species Dropdown
              DropdownButtonFormField<String>(
                value: _selectedSpecies,
                decoration: InputDecoration(
                  labelText: 'Species',
                  prefixIcon: Icon(Icons.pets, color: theme.accentColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                dropdownColor: HunterUi.cardColor(theme),
                style: TextStyle(color: theme.textColor),
                items:
                    _speciesOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                onChanged:
                    (val) => setState(() => _selectedSpecies = val ?? 'Impala'),
              ),
              const SizedBox(height: 12),

              // Weight Fields Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fieldWeightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: TextStyle(color: theme.textColor),
                      decoration: _inputDecoration(
                        'Field Weight (kg)',
                        Icons.scale,
                        theme,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty)
                          return 'Required';
                        if (double.tryParse(val.trim()) == null)
                          return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hangingWeightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: TextStyle(color: theme.textColor),
                      decoration: _inputDecoration(
                        'Hanging Weight (kg)',
                        Icons.straighten,
                        theme,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty)
                          return 'Required';
                        if (double.tryParse(val.trim()) == null)
                          return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Pin Harvest Location Button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Colors.amber.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'HARVEST GPS LOCATION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _locationStatusText,
                            style: TextStyle(
                              color: theme.subtitleColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed:
                              _isLocationCapturing ? null : _pinHarvestLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon:
                              _isLocationCapturing
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(
                                    Icons.location_searching,
                                    size: 18,
                                  ),
                          label: Text(
                            _capturedLatitude != null
                                ? 'RE-PIN'
                                : 'PIN LOCATION',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Chiller Hook Assignment
              DropdownButtonFormField<String>(
                value: _selectedChillerPosition,
                decoration: InputDecoration(
                  labelText: 'Cold Storage Position',
                  prefixIcon: Icon(Icons.kitchen, color: theme.accentColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                dropdownColor: HunterUi.cardColor(theme),
                style: TextStyle(color: theme.textColor),
                items:
                    _chillerPositions
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              p,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                onChanged:
                    (val) => setState(
                      () =>
                          _selectedChillerPosition =
                              val ?? _chillerPositions.first,
                    ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon:
                      _isSubmitting
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                          : const Icon(Icons.save_rounded, color: Colors.black),
                  label: Text(
                    _isSubmitting ? 'LOGGING...' : 'LOG CARCASS',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submitCarcassLog,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon,
    ThemeController theme,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.subtitleColor),
      prefixIcon: Icon(icon, color: theme.accentColor),
      filled: true,
      fillColor: HunterUi.cardColor(theme),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }

  Widget _buildChillerRecordsStream(ThemeController theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _carcassLogManager.getActiveChillerLogs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            color: HunterUi.cardColor(theme),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '⚠️ Error loading chiller records: ${snapshot.error}',
                style: TextStyle(color: theme.textColor),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Card(
            color: HunterUi.cardColor(theme),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: theme.subtitleColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No active chiller records',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Log your first carcass above',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildChillerCard(data, theme);
          },
        );
      },
    );
  }

  Widget _buildChillerCard(Map<String, dynamic> data, ThemeController theme) {
    final species = data['species'] ?? 'Unknown';
    final tagNumber = data['tagNumber'] ?? 'N/A';
    final position = data['coldStoragePosition'] ?? 'N/A';
    final fieldWeight = data['fieldWeightKg'] ?? 0.0;
    final hangingWeight = data['hangingWeightKg'] ?? 0.0;

    return Card(
      color: HunterUi.cardColor(theme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => MeatProcessingScreen(
                    theme: widget.theme,
                    prefillTagNumber: tagNumber,
                    prefillSpecies: species,
                    prefillHangingWeight: hangingWeight,
                  ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    size: 18,
                    color: theme.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      species,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.textColor,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tag: $tagNumber',
                style: TextStyle(color: theme.subtitleColor, fontSize: 11),
              ),
              Text(
                position,
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Field',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 9,
                        ),
                      ),
                      Text(
                        MeasurementFormatter.instance.formatWeight(fieldWeight),
                        style: TextStyle(color: theme.textColor, fontSize: 11),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Hanging',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 9,
                        ),
                      ),
                      Text(
                        MeasurementFormatter.instance
                            .formatWeight(hangingWeight),
                        style: TextStyle(color: theme.textColor, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: const Icon(Icons.restaurant_menu, size: 14),
                  label: const Text(
                    'PROCESS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => MeatProcessingScreen(
                              theme: widget.theme,
                              prefillTagNumber: tagNumber,
                              prefillSpecies: species,
                              prefillHangingWeight: hangingWeight,
                            ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
