import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';

class CustomHandloadsFormScreen extends StatefulWidget {
  final ThemeController theme;
  final Map<String, String> firearm;

  const CustomHandloadsFormScreen({
    super.key,
    required this.theme,
    required this.firearm,
  });

  @override
  State<CustomHandloadsFormScreen> createState() =>
      _CustomHandloadsFormScreenState();
}

class _CustomHandloadsFormScreenState extends State<CustomHandloadsFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _muzzleVelocityController = TextEditingController();
  final _primerController = TextEditingController();
  final _roundTplController = TextEditingController();

  String? _selectedBulletBrand;
  int? _selectedBulletWeight;
  String? _selectedPropellantBrand;
  String? _selectedPropellantType;

  bool _isSaving = false;

  @override
  void dispose() {
    _muzzleVelocityController.dispose();
    _primerController.dispose();
    _roundTplController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomHandload() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final firearmId = widget.firearm['docId'];
    if (userId == null || firearmId == null) return;

    setState(() => _isSaving = true);

    try {
      final roundTPL = double.tryParse(_roundTplController.text.trim()) ?? 0.0;
      final muzzleVelocity =
          int.tryParse(_muzzleVelocityController.text.trim()) ?? 0;

      final data = {
        'bulletBrand': _selectedBulletBrand ?? 'Custom',
        'caliber': widget.firearm['caliber'] ?? '',
        'bulletWeight': _selectedBulletWeight ?? 0,
        'propellantBrand': _selectedPropellantBrand ?? '',
        'propellantType': _selectedPropellantType ?? '',
        'muzzleVelocity': muzzleVelocity,
        'primer': _primerController.text.trim(),
        'roundTPL': roundTPL,
        'type': 'custom',
        'ownerId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('firearms')
          .doc(firearmId)
          .collection('ammunition')
          .add(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom Handload saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving custom handload: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDecoration(String labelText) {
    final theme = widget.theme;
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: theme.subtitleColor),
      filled: true,
      fillColor: theme.backgroundColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.accentColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return HunterScaffold(
      theme: widget.theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: const Text('Custom Handloads Form'),
        backgroundColor: Colors.transparent,
        foregroundColor: HunterUi.titleColor(theme),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, SafeBottomInset.of(context)),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'FIREARM: ${widget.firearm['make']} ${widget.firearm['model']} (${widget.firearm['caliber']})',
                style: TextStyle(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _muzzleVelocityController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: theme.textColor),
                decoration: _inputDecoration('Muzzle Velocity (fps)'),
                validator: (val) {
                  if (val == null || val.trim().isEmpty)
                    return 'Muzzle velocity is required';
                  if (int.tryParse(val.trim()) == null)
                    return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _primerController,
                style: TextStyle(color: theme.textColor),
                decoration: _inputDecoration('Primer Specification'),
                validator: (val) {
                  if (val == null || val.trim().isEmpty)
                    return 'Primer spec is required';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Dedicated TextFormField for Round TPL (Total Product Length / mm)
              TextFormField(
                controller: _roundTplController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(color: theme.textColor),
                decoration: _inputDecoration(
                  'Round TPL (Total Product Length / mm)',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Round TPL is required';
                  }
                  if (double.tryParse(val.trim()) == null) {
                    return 'Enter a valid numeric value';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isSaving ? null : _saveCustomHandload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child:
                    _isSaving
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : Text(
                          'SAVE HANDLOAD SPECIFICATION',
                          style: TextStyle(
                            color: theme.backgroundColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
