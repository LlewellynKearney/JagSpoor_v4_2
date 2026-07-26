import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../services/carcass_log_manager.dart';
import '../services/offline_sync_queue.dart';
import 'meat_processing_screen.dart';

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Carcass logged to $_selectedChillerPosition'),
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
        });
      }
    } catch (e) {
      // Network link dropped - write to local SQLite storage instead
      try {
        await OfflineSyncQueue.instance.enqueueAction(
          'carcass_logs',
          'CREATE',
          {
            'tagNumber': _tagNumberController.text.trim(),
            'species': _selectedSpecies,
            'fieldWeightKg': double.parse(_fieldWeightController.text.trim()),
            'hangingWeightKg': double.parse(_hangingWeightController.text.trim()),
            'coldStoragePosition': _selectedChillerPosition,
            'status': 'Hanging',
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Saved locally. Carcass queued for sync when back in range.'),
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

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          '🥩 SLAUGHTERHOUSE CARCASS MATRIX',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
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
      color: theme.cardColor,
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
                decoration: _inputDecoration('Tag Number (e.g., TAG-2024-001)', Icons.tag, theme),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Species Dropdown
              DropdownButtonFormField<String>(
                value: _selectedSpecies,
                decoration: InputDecoration(
                  labelText: 'Species',
                  prefixIcon: Icon(Icons.pets, color: theme.accentColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                dropdownColor: theme.cardColor,
                style: TextStyle(color: theme.textColor),
                items: _speciesOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedSpecies = val ?? 'Impala'),
              ),
              const SizedBox(height: 12),

              // Weight Fields Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fieldWeightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: theme.textColor),
                      decoration: _inputDecoration('Field Weight (kg)', Icons.scale, theme),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Required';
                        if (double.tryParse(val.trim()) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hangingWeightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: theme.textColor),
                      decoration: _inputDecoration('Hanging Weight (kg)', Icons.straighten, theme),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Required';
                        if (double.tryParse(val.trim()) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Chiller Hook Assignment
              DropdownButtonFormField<String>(
                value: _selectedChillerPosition,
                decoration: InputDecoration(
                  labelText: 'Cold Storage Position',
                  prefixIcon: Icon(Icons.kitchen, color: theme.accentColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                dropdownColor: theme.cardColor,
                style: TextStyle(color: theme.textColor),
                items: _chillerPositions
                    .map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (val) => setState(() => _selectedChillerPosition = val ?? _chillerPositions.first),
              ),
              const SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.save_rounded, color: Colors.black),
                  label: Text(
                    _isSubmitting ? 'LOGGING...' : 'LOG CARCASS',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
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

  InputDecoration _inputDecoration(String label, IconData icon, ThemeController theme) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.subtitleColor),
      prefixIcon: Icon(icon, color: theme.accentColor),
      filled: true,
      fillColor: theme.cardColor,
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
            child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor)),
          );
        }

        if (snapshot.hasError) {
          return Card(
            color: theme.cardColor,
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
            color: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: theme.subtitleColor),
                    const SizedBox(height: 12),
                    Text(
                      'No active chiller records',
                      style: TextStyle(color: theme.subtitleColor, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Log your first carcass above',
                      style: TextStyle(color: theme.subtitleColor, fontSize: 13),
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
    final timestamp = data['timestamp'] as Timestamp?;

    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MeatProcessingScreen(
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
                  Icon(Icons.inventory_2_rounded, size: 18, color: theme.accentColor),
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
                style: TextStyle(color: theme.accentColor, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Field', style: TextStyle(color: theme.subtitleColor, fontSize: 9)),
                      Text('${fieldWeight.toStringAsFixed(1)} kg', style: TextStyle(color: theme.textColor, fontSize: 11)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Hanging', style: TextStyle(color: theme.subtitleColor, fontSize: 9)),
                      Text('${hangingWeight.toStringAsFixed(1)} kg', style: TextStyle(color: theme.textColor, fontSize: 11)),
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
                        builder: (context) => MeatProcessingScreen(
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
