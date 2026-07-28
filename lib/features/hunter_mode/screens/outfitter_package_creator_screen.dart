import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../services/package_booking_manager.dart';

class OutfitterPackageCreatorScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterPackageCreatorScreen({super.key, required this.theme});

  @override
  State<OutfitterPackageCreatorScreen> createState() => _OutfitterPackageCreatorScreenState();
}

class _OutfitterPackageCreatorScreenState extends State<OutfitterPackageCreatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final List<String> _inclusions = [];
  final _inclusionController = TextEditingController();

  String? _selectedFarmId;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _inclusionController.dispose();
    super.dispose();
  }

  void _addInclusion() {
    final inclusion = _inclusionController.text.trim();
    if (inclusion.isNotEmpty && !_inclusions.contains(inclusion)) {
      setState(() {
        _inclusions.add(inclusion);
        _inclusionController.clear();
      });
    }
  }

  void _removeInclusion(String inclusion) {
    setState(() {
      _inclusions.remove(inclusion);
    });
  }

  Future<void> _publishPackage() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFarmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select a farm for this package'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_inclusions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one inclusion'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final priceText = _priceController.text.replaceAll(',', '').replaceAll('R', '').trim();
      final basePrice = double.tryParse(priceText) ?? 0.0;

      await PackageBookingManager.instance.publishPackage(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        basePriceRands: basePrice,
        inclusions: List<String>.from(_inclusions),
        farmId: _selectedFarmId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Package published successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to publish: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          '🏕️ Publish Package',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Farm Selection (Mandatory)
            _buildSectionLabel('BIND TO FARM *', theme),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('farms')
                  .where('outfitterId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .where('status', isEqualTo: 'active')
                  .snapshots(),
              builder: (context, snapshot) {
                final farms = snapshot.data?.docs ?? [];
                
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.green),
                    ),
                  );
                }

                if (farms.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No farms registered. Register a farm first in Enterprise Panel.',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return DropdownButtonFormField<String>(
                  value: _selectedFarmId,
                  decoration: _inputDecoration(
                    hint: 'Select farm for this package...',
                    theme: theme,
                  ),
                  dropdownColor: theme.cardColor,
                  style: TextStyle(color: theme.textColor),
                  items: farms.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(data['name'] ?? 'Unknown'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedFarmId = value;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            // Package Title
            _buildSectionLabel('PACKAGE TITLE', theme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              style: TextStyle(color: theme.textColor),
              decoration: _inputDecoration(
                hint: 'e.g., 5-Day Kalahari Lion Hunt',
                theme: theme,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a package title';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Description
            _buildSectionLabel('DESCRIPTION', theme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              style: TextStyle(color: theme.textColor),
              maxLines: 4,
              decoration: _inputDecoration(
                hint: 'Describe the hunting experience, terrain, trophy expectations...',
                theme: theme,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Base Price
            _buildSectionLabel('BASE PRICE (ZAR)', theme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceController,
              style: TextStyle(color: theme.textColor),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: _inputDecoration(
                hint: '25000',
                prefix: 'R ',
                theme: theme,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a price';
                }
                final price = double.tryParse(value.replaceAll(',', '').replaceAll('R', ''));
                if (price == null || price <= 0) {
                  return 'Please enter a valid price';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Inclusions
            _buildSectionLabel('PACKAGE INCLUSIONS', theme),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _inclusionController,
                    style: TextStyle(color: theme.textColor),
                    decoration: _inputDecoration(
                      hint: 'e.g., Transport, Accommodation, Meals',
                      theme: theme,
                    ),
                    onFieldSubmitted: (_) => _addInclusion(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addInclusion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Text('ADD'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Inclusion Tags
            if (_inclusions.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _inclusions.map((inclusion) {
                  return Chip(
                    label: Text(
                      inclusion,
                      style: TextStyle(color: theme.textColor),
                    ),
                    backgroundColor: theme.accentColor.withValues(alpha: 0.2),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => _removeInclusion(inclusion),
                  );
                }).toList(),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'No inclusions added yet',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            const SizedBox(height: 32),

            // Publish Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _publishPackage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.publish_rounded),
                          SizedBox(width: 8),
                          Text(
                            'PUBLISH PACKAGE',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, ThemeController theme) {
    return Text(
      label,
      style: TextStyle(
        color: theme.subtitleColor,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required ThemeController theme,
    String? prefix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: theme.subtitleColor.withValues(alpha: 0.5)),
      prefixText: prefix,
      prefixStyle: TextStyle(color: theme.textColor),
      filled: true,
      fillColor: theme.cardColor,
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
        borderSide: BorderSide(color: theme.accentColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }
}
