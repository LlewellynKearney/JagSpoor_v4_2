import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../services/outfitter_enterprise_manager.dart';

class OutfitterEnterprisePanelScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterEnterprisePanelScreen({super.key, required this.theme});

  @override
  State<OutfitterEnterprisePanelScreen> createState() =>
      _OutfitterEnterprisePanelScreenState();
}

class _OutfitterEnterprisePanelScreenState
    extends State<OutfitterEnterprisePanelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _farmNameController = TextEditingController();
  final _districtController = TextEditingController();
  final _provinceController = TextEditingController();
  final _managerEmailController = TextEditingController();
  final _managerNameController = TextEditingController();
  final _managerCellController = TextEditingController();

  String? _selectedFarmId;
  bool _isAddingFarm = false;
  bool _isAssigningManager = false;

  @override
  void dispose() {
    _farmNameController.dispose();
    _districtController.dispose();
    _provinceController.dispose();
    _managerEmailController.dispose();
    _managerNameController.dispose();
    _managerCellController.dispose();
    super.dispose();
  }

  Future<void> _addFarm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isAddingFarm = true;
    });

    try {
      await OutfitterEnterpriseManager.instance.addFarm(
        name: _farmNameController.text.trim(),
        district: _districtController.text.trim(),
        province: _provinceController.text.trim(),
      );

      if (mounted) {
        _farmNameController.clear();
        _districtController.clear();
        _provinceController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Farm registered successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingFarm = false;
        });
      }
    }
  }

  Future<void> _assignManager() async {
    if (_selectedFarmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select a farm first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_managerEmailController.text.trim().isEmpty ||
        _managerNameController.text.trim().isEmpty ||
        _managerCellController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please fill in manager name, email and cell number'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isAssigningManager = true;
    });

    try {
      await OutfitterEnterpriseManager.instance.assignManager(
        farmId: _selectedFarmId!,
        managerEmail: _managerEmailController.text.trim(),
        managerName: _managerNameController.text.trim(),
        managerCell: _managerCellController.text.trim(),
      );

      if (mounted) {
        _managerEmailController.clear();
        _managerNameController.clear();
        _managerCellController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Manager assigned successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAssigningManager = false;
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
          '🏡 Enterprise Control Panel',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
        children: [
          // Farm Registration Section
          _buildSectionCard(
            title: '🏗️ Register New Farm',
            icon: Icons.agriculture_rounded,
            theme: theme,
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _farmNameController,
                    style: TextStyle(color: theme.textColor),
                    decoration: _inputDecoration(
                      hint: 'Farm Name (e.g., Kgalagadi Game Farm)',
                      label: 'Farm Name',
                      theme: theme,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter farm name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _districtController,
                          style: TextStyle(color: theme.textColor),
                          decoration: _inputDecoration(
                            hint: 'District',
                            label: 'District',
                            theme: theme,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _provinceController,
                          style: TextStyle(color: theme.textColor),
                          decoration: _inputDecoration(
                            hint: 'Province',
                            label: 'Province',
                            theme: theme,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isAddingFarm ? null : _addFarm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon:
                          _isAddingFarm
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.add_business_rounded),
                      label: const Text(
                        'REGISTER FARM',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Manager Assignment Section
          _buildSectionCard(
            title: '👤 Assign Farm Manager',
            icon: Icons.person_add_rounded,
            theme: theme,
            child: Column(
              children: [
                // Farm Dropdown
                StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('farms')
                          .where(
                            'outfitterId',
                            isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                          )
                          .where('status', isEqualTo: 'active')
                          .snapshots(),
                  builder: (context, snapshot) {
                    final farms = snapshot.data?.docs ?? [];

                    return DropdownButtonFormField<String>(
                      value: _selectedFarmId,
                      decoration: _inputDecoration(
                        hint: 'Select Farm',
                        label: 'Select Farm',
                        theme: theme,
                      ),
                      dropdownColor: theme.cardColor,
                      style: TextStyle(color: theme.textColor),
                      items:
                          farms.map((doc) {
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerNameController,
                  style: TextStyle(color: theme.textColor),
                  decoration: _inputDecoration(
                    hint: 'Manager Full Name',
                    label: 'Manager Name',
                    theme: theme,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerEmailController,
                  style: TextStyle(color: theme.textColor),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration(
                    hint: 'manager@example.com',
                    label: 'Manager Email',
                    theme: theme,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _managerCellController,
                  style: TextStyle(color: theme.textColor),
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(
                    hint: 'e.g. +27 82 123 4567',
                    label: 'Cell Phone Number',
                    theme: theme,
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Please enter a cell number';
                    }
                    // Accept digits, spaces, +, -, ( and ). A loose check keeps
                    // international formats valid without a phone-library dep.
                    final digits = trimmed.replaceAll(RegExp(r'[\s+\-()]'), '');
                    if (digits.length < 9 ||
                        int.tryParse(digits) == null) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAssigningManager ? null : _assignManager,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon:
                        _isAssigningManager
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text(
                      'ASSIGN MANAGER',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Registered Farms List
          _buildSectionCard(
            title: '📋 Registered Farms',
            icon: Icons.list_alt_rounded,
            theme: theme,
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('farms')
                      .where(
                        'outfitterId',
                        isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                      )
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: Colors.green),
                    ),
                  );
                }

                // A failed query (e.g. a missing composite index) must not be
                // mistaken for an empty result — otherwise existing farms show
                // as "No farms registered". Surface the error explicitly.
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: Colors.red.withValues(alpha: 0.7),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Unable to load farms.\n'
                            'If this persists, deploy the Firestore indexes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.subtitleColor),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final farms = snapshot.data?.docs ?? [];

                if (farms.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.landscape_rounded,
                            color: theme.accentColor.withValues(alpha: 0.5),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No farms registered yet',
                            style: TextStyle(color: theme.subtitleColor),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children:
                      farms.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final farmStatus = data['status'] ?? 'active';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  farmStatus == 'active'
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.accentColor.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.landscape_rounded,
                                  color: theme.accentColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['name'] ?? 'Unknown Farm',
                                      style: TextStyle(
                                        color: theme.textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${data['district'] ?? ""}, ${data['province'] ?? ""}',
                                      style: TextStyle(
                                        color: theme.subtitleColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      farmStatus == 'active'
                                          ? Colors.green.withValues(alpha: 0.2)
                                          : Colors.red.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  farmStatus.toUpperCase(),
                                  style: TextStyle(
                                    color:
                                        farmStatus == 'active'
                                            ? Colors.green
                                            : Colors.red,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required ThemeController theme,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: theme.accentColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required String label,
    required ThemeController theme,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      hintStyle: TextStyle(color: theme.subtitleColor.withValues(alpha: 0.5)),
      labelStyle: TextStyle(color: theme.accentColor),
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
        borderSide: BorderSide(color: theme.accentColor, width: 2),
      ),
    );
  }
}
