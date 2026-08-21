import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/meat_processing_exporter.dart';
import '../services/meat_processing_order_manager.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';

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
  // Per-portion target weight (kg) controllers, keyed by portion name.
  final Map<String, TextEditingController> _weightControllers = {};
  // Per-portion spice selection (named profile or 'Custom...'), keyed by name.
  final Map<String, String> _portionSpice = {};
  // Per-portion free-text custom spice controllers, keyed by portion name.
  // Only used when the portion's spice == _customSpiceOption.
  final Map<String, TextEditingController> _customSpiceControllers = {};
  String _selectedSpiceProfile = 'Traditional Biltong';
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

  /// Popular SA spice profiles offered per portion. The sentinel
  /// [_customSpiceOption] triggers a free-text spice entry field.
  static const List<String> _spiceProfiles = [
    'Traditional Biltong',
    'Chakalaka',
    'Garlic & Herb',
    'Chili Bites',
    'Traditional Coriander & Vinegar',
    'Peri-Peri Hot',
    'BBQ Spice Blend',
    'Black Pepper & Salt',
  ];
  static const String _customSpiceOption = 'Custom...';

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
      _hangingWeightController.text = widget.prefillHangingWeight!
          .toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _tagNumberController.dispose();
    _hunterNameController.dispose();
    _hangingWeightController.dispose();
    _specialInstructionsController.dispose();
    for (final c in _weightControllers.values) {
      c.dispose();
    }
    for (final c in _customSpiceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _togglePortion(String portion) {
    setState(() {
      if (_selectedPortions.contains(portion)) {
        _selectedPortions.remove(portion);
        _weightControllers[portion]?.dispose();
        _weightControllers.remove(portion);
        _customSpiceControllers[portion]?.dispose();
        _customSpiceControllers.remove(portion);
        _portionSpice.remove(portion);
      } else {
        _selectedPortions.add(portion);
        _weightControllers[portion] = TextEditingController();
        // New portions inherit the current default spice profile.
        _portionSpice[portion] = _selectedSpiceProfile;
      }
    });
  }

  /// Lazily ensures a free-text spice controller exists for a portion that
  /// has its spice set to [_customSpiceOption].
  TextEditingController _ensureCustomSpiceController(String portion) {
    return _customSpiceControllers.putIfAbsent(
      portion,
      () => TextEditingController(),
    );
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
      // Build per-portion specs (target weight + spice) from the in-memory
      // state and pass them cleanly to the manifest exporter.
      final portions = _selectedPortions.map((name) {
        final weightText = _weightControllers[name]?.text.trim() ?? '';
        final targetWeight = double.tryParse(weightText);
        var spice = _portionSpice[name] ?? '';
        if (spice == _customSpiceOption) {
          spice = _customSpiceControllers[name]?.text.trim() ?? '';
        }
        return ProcessingPortion(
          name: name,
          targetWeightKg: targetWeight,
          spice: spice,
        );
      }).toList();

      final exporter = MeatProcessingExporter();
      await exporter.generateAndShareManifest(
        carcassTag: _tagNumberController.text.trim(),
        hunterName: _hunterNameController.text.trim(),
        species: _selectedSpecies,
        hangingWeight: double.parse(_hangingWeightController.text.trim()),
        portions: portions,
        spicePreference: _selectedSpiceProfile,
        specialInstructions: _specialInstructionsController.text.trim(),
      );

      // Persist the submitted order so it appears in the order history log.
      // Persistence failures are surfaced but never undo a successful share.
      try {
        await MeatProcessingOrderManager().saveOrder(
          hunterName: _hunterNameController.text.trim(),
          carcassTag: _tagNumberController.text.trim(),
          species: _selectedSpecies,
          hangingWeight: double.parse(_hangingWeightController.text.trim()),
          portions: portions,
          spicePreference: _selectedSpiceProfile,
          specialInstructions: _specialInstructionsController.text.trim(),
        );
      } catch (_) {
        // Best-effort; the manifest was already shared.
      }

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

    return HunterScaffold(
      theme: widget.theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: Text(
          '🥩 MEAT PROCESSING ORDER',
          style: TextStyle(
            color: HunterUi.titleColor(theme),
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: HunterUi.titleColor(widget.theme)),
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
      color: HunterUi.cardColor(theme),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator:
                  (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator:
                  (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Species Dropdown
            DropdownButtonFormField<String>(
              value:
                  _speciesOptions.contains(_selectedSpecies)
                      ? _selectedSpecies
                      : _speciesOptions.first,
              style: TextStyle(color: theme.textColor),
              dropdownColor: HunterUi.cardColor(theme),
              decoration: InputDecoration(
                labelText: 'Species',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.pets, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items:
                  _speciesOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
              onChanged:
                  (val) => setState(
                    () => _selectedSpecies = val ?? _selectedSpecies,
                  ),
            ),
            const SizedBox(height: 12),

            // Hanging Weight
            TextFormField(
              controller: _hangingWeightController,
              style: TextStyle(color: theme.textColor),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Cold Hanging Weight (kg)',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.scale, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Required';
                if (double.tryParse(val.trim()) == null)
                  return 'Enter a valid number';
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
      color: HunterUi.cardColor(theme),
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
              children:
                  _portionOptions.map((portion) {
                    final isSelected = _selectedPortions.contains(portion);
                    return FilterChip(
                      label: Text(
                        portion,
                        style: TextStyle(
                          color: isSelected ? Colors.black : theme.textColor,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: theme.accentColor,
                      checkmarkColor: Colors.black,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color:
                            isSelected
                                ? theme.accentColor
                                : theme.subtitleColor.withValues(alpha: 0.3),
                      ),
                      onSelected: (_) => _togglePortion(portion),
                    );
                  }).toList(),
            ),
            if (_selectedPortions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Target weight & spice per portion:',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ..._selectedPortions.map(
                (p) => _buildPortionConfigRow(theme, p),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Per-portion configuration row: a target weight (kg) input plus a spice
  /// dropdown (popular SA profiles + a "Custom..." free-text entry).
  Widget _buildPortionConfigRow(ThemeController theme, String portion) {
    final spice = _portionSpice[portion] ?? _spiceProfiles.first;
    final isCustom = spice == _customSpiceOption;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant, color: theme.accentColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    portion,
                    style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Target weight input (kg).
            TextFormField(
              controller: _weightControllers[portion],
              style: TextStyle(color: theme.textColor),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Target Weight (kg)',
                labelStyle: TextStyle(color: theme.subtitleColor, fontSize: 12),
                suffixText: 'kg',
                suffixStyle:
                    TextStyle(color: theme.subtitleColor, fontSize: 12),
                filled: true,
                fillColor: HunterUi.cardColor(theme),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Per-portion spice dropdown (SA profiles + Custom...).
            DropdownButtonFormField<String>(
              value: _spiceProfiles.contains(spice) || spice == _customSpiceOption
                  ? spice
                  : _spiceProfiles.first,
              style: TextStyle(color: theme.textColor, fontSize: 13),
              dropdownColor: HunterUi.cardColor(theme),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Spice / Flavour',
                labelStyle: TextStyle(color: theme.subtitleColor, fontSize: 12),
                filled: true,
                fillColor: HunterUi.cardColor(theme),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: [
                ..._spiceProfiles.map(
                  (s) => DropdownMenuItem(value: s, child: Text(s)),
                ),
                const DropdownMenuItem(
                  value: _customSpiceOption,
                  child: Text(_customSpiceOption),
                ),
              ],
              onChanged: (val) => setState(() {
                _portionSpice[portion] = val ?? _spiceProfiles.first;
              }),
            ),
            if (isCustom) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _ensureCustomSpiceController(portion),
                style: TextStyle(color: theme.textColor),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Custom Spice Blend',
                  labelStyle: TextStyle(color: theme.subtitleColor, fontSize: 12),
                  hintText: 'e.g., Coriander, chilli, brown sugar...',
                  hintStyle: TextStyle(
                    color: theme.subtitleColor.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: HunterUi.cardColor(theme),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
      color: HunterUi.cardColor(theme),
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
                  'DEFAULT SPICE PROFILE',
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
              'Applied to newly selected portions (override per portion below).',
              style: TextStyle(color: theme.subtitleColor, fontSize: 12),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value:
                  _spiceProfiles.contains(_selectedSpiceProfile)
                      ? _selectedSpiceProfile
                      : _spiceProfiles.first,
              style: TextStyle(color: theme.textColor),
              dropdownColor: HunterUi.cardColor(theme),
              decoration: InputDecoration(
                labelText: 'Default Spice Profile',
                labelStyle: TextStyle(color: theme.subtitleColor),
                prefixIcon: Icon(Icons.menu_book, color: theme.accentColor),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items:
                  _spiceProfiles
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
              onChanged:
                  (val) => setState(
                    () => _selectedSpiceProfile = val ?? _selectedSpiceProfile,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.backgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.subtitleColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Traditional biltong spice: Coriander, black pepper, vinegar, salt',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 12,
                      ),
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
      color: HunterUi.cardColor(theme),
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
                hintText:
                    'e.g., Keep skins for taxidermy, wrap backstraps separate, etc.',
                hintStyle: TextStyle(
                  color: theme.subtitleColor.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: theme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
        icon:
            _isGenerating
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
                : const Icon(Icons.picture_as_pdf_rounded, size: 28),
        label: Text(
          _isGenerating
              ? 'GENERATING...'
              : '📋 COMPILE & SHARE SLAUGHTERHOUSE ORDER',
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
