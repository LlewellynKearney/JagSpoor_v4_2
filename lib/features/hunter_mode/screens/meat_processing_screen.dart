import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/meat_processing_exporter.dart';

class MeatProcessingScreen extends StatefulWidget {
  final ThemeController theme;
  final String? prefillTagNumber;
  final String? prefillSpecies;
  final double? prefillHangingWeight;

  const MeatProcessingScreen({
    super.key,
    required this.theme,
    this.prefillTagNumber,
    this.prefillSpecies,
    this.prefillHangingWeight,
  });

  @override
  State<MeatProcessingScreen> createState() => _MeatProcessingScreenState();
}

class _MeatProcessingScreenState extends State<MeatProcessingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tagNumberController = TextEditingController();
  final _hunterNameController = TextEditingController();
  final _hangingWeightController = TextEditingController();
  final _specialInstructionsController = TextEditingController();

  String _selectedSpecies = 'Impala';
  final List<String> _selectedPortions = [];
  String _selectedSpiceProfile = 'Traditional Coriander & Vinegar';
  bool _isGenerating = false;

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

  static const List<String> _portionOptions = [
    'Biltong',
    'Droëwors',
    'Steaks',
    'Roast',
    'Mince',
    'Ribs',
    'Brisket',
    'Liver',
    'Heart',
    'Tongue',
    'Offal Mix',
  ];

  static const List<String> _spiceProfiles = [
    'Traditional Coriander & Vinegar',
    'Chili & Garlic',
    'BBQ Spice Blend',
    'Peri-Peri Hot',
    'Mild Paprika & Onion',
    'Black Pepper & Salt Only',
    'Custom Blend',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.prefillTagNumber != null) {
      _tagNumberController.text = widget.prefillTagNumber!;
    }
    if (widget.prefillSpecies != null) {
      _selectedSpecies = widget.prefillSpecies!;
    }
    if (widget.prefillHangingWeight != null) {
      _hangingWeightController.text = widget.prefillHangingWeight!.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _tagNumberController.dispose();
    _hunterNameController.dispose();
    _hangingWeightController.dispose();
    _specialInstructionsController.dispose();
    super.dispose();
  }

  void _togglePortion(String portion) {
    setState(() {
      if (_selectedPortions.contains(portion)) {
        _selectedPortions.remove(portion);
      } else {
        _selectedPortions.add(portion);
      }
    });
  }

  Future<void> _compileAndShareManifest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPortions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select at least one portion type'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final exporter = MeatProcessingExporter();
      await exporter.generateAndShareManifest(
        carcassTag: _tagNumberController.text.trim(),
        hunterName: _hunterNameController.text.trim(),
        species: _selectedSpecies,
        hangingWeight: double.parse(_hangingWeightController.text.trim()),
        portionsRequested: List.from(_selectedPortions),
        spicePreference: _selectedSpiceProfile,
        specialInstructions: _specialInstructionsController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Slaughterhouse Manifest generated and shared!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error generating manifest: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
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
          '🥩 MEAT PROCESSING ORDER',
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCarcassInfoCard(theme),
                const SizedBox(height: 24),
                _buildPortionsSelector(theme),
                const SizedBox(height: 24),
                _buildSpiceConfigurationCard(theme),
                const SizedBox(height: 24),
                _buildSpecialInstructionsCard(theme),
                const SizedBox(height: 32),
                _buildCompileButton(theme),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCarcassInfoCard(ThemeController theme) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_rounded, color: theme.accentColor),
                const SizedBox(width: 10),
                Text(
                  'CARCASS IDENTIFICATION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tag Number
            TextFormField(
              controller: _tagNumberController,
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                labelText: 'Carcass Tag Number',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.tag, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Hunter Name
            TextFormField(
              controller: _hunterNameController,
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                labelText: 'Hunter Name',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.person, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Species Dropdown
            DropdownButtonFormField<String>(
              value: _speciesOptions.contains(_selectedSpecies) ? _selectedSpecies : _speciesOptions.first,
              style: TextStyle(color: theme.textColor),
              dropdownColor: theme.cardColor,
              decoration: InputDecoration(
                labelText: 'Species',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.pets, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: _speciesOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedSpecies = val ?? _selectedSpecies),
            ),
            const SizedBox(height: 12),

            // Hanging Weight
            TextFormField(
              controller: _hangingWeightController,
              style: TextStyle(color: theme.textColor),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cold Hanging Weight (kg)',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.scale, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Required';
                if (double.tryParse(val.trim()) == null) return 'Enter a valid number';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortionsSelector(ThemeController theme) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant_menu, color: theme.accentColor),
                const SizedBox(width: 10),
                Text(
                  'PORTIONS REQUESTED',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select the portions you want from this carcass:',
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _portionOptions.map((portion) {
                final isSelected = _selectedPortions.contains(portion);
                return FilterChip(
                  label: Text(
                    portion,
                    style: TextStyle(
                      color: isSelected ? Colors.black : theme.textColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: theme.accentColor,
                  checkmarkColor: Colors.black,
                  backgroundColor: theme.backgroundColor,
                  side: BorderSide(
                    color: isSelected ? theme.accentColor : theme.subtitleColor.withValues(alpha: 0.3),
                  ),
                  onSelected: (_) => _togglePortion(portion),
                );
              }).toList(),
            ),
            if (_selectedPortions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: theme.accentColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selected: ${_selectedPortions.join(", ")}',
                        style: TextStyle(color: theme.textColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpiceConfigurationCard(ThemeController theme) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department, color: theme.accentColor),
                const SizedBox(width: 10),
                Text(
                  'SPICE CONFIGURATION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _spiceProfiles.contains(_selectedSpiceProfile) ? _selectedSpiceProfile : _spiceProfiles.first,
              style: TextStyle(color: theme.textColor),
              dropdownColor: theme.cardColor,
              decoration: InputDecoration(
                labelText: 'Spice Profile',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.menu_book, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: _spiceProfiles
                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (val) => setState(() => _selectedSpiceProfile = val ?? _selectedSpiceProfile),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.backgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.subtitleColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Traditional biltong spice: Coriander, black pepper, vinegar, salt',
                      style: TextStyle(color: theme.subtitleColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialInstructionsCard(ThemeController theme) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note_add, color: theme.accentColor),
                const SizedBox(width: 10),
                Text(
                  'SPECIAL INSTRUCTIONS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _specialInstructionsController,
              style: TextStyle(color: theme.textColor),
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Additional Notes',
                labelStyle: TextStyle(color: theme.subtitleColor),
                hintText: 'e.g., Keep skins for taxidermy, wrap backstraps separate, etc.',
                hintStyle: TextStyle(color: theme.subtitleColor.withValues(alpha: 0.5)),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompileButton(ThemeController theme) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accentColor,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        icon: _isGenerating
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              )
            : const Icon(Icons.picture_as_pdf_rounded, size: 28),
        label: Text(
          _isGenerating ? 'GENERATING...' : '📋 COMPILE & SHARE SLAUGHTERHOUSE ORDER',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
        onPressed: _isGenerating ? null : _compileAndShareManifest,
      ),
    );
  }
}
