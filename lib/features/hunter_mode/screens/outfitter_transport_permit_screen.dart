import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:signature/signature.dart';
import '../../../core/theme/app_theme.dart';
import '../services/transport_permit_manager.dart';
import '../services/transport_permit_pdf_exporter.dart';
import '../services/user_role_resolver.dart';

class OutfitterTransportPermitScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterTransportPermitScreen({super.key, required this.theme});

  @override
  State<OutfitterTransportPermitScreen> createState() =>
      _OutfitterTransportPermitScreenState();
}

class _OutfitterTransportPermitScreenState
    extends State<OutfitterTransportPermitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _permitManager = TransportPermitManager.instance;
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  // Form Controllers
  final _hunterNameController = TextEditingController();
  final _hunterIdController = TextEditingController();
  final _hunterAddressController = TextEditingController();
  final _vehicleRegController = TextEditingController();
  final _vehicleMakeController = TextEditingController();
  final _destinationAddressController = TextEditingController();

  // Farm Selection
  String? _selectedFarmId;
  String? _selectedFarmName;
  String? _exemptionNumber;
  List<Map<String, dynamic>> _farms = [];

  // Species List
  final List<Map<String, dynamic>> _speciesList = [];

  // Loading states
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _isManager = false;

  @override
  void initState() {
    super.initState();
    _isManager = UserRoleResolver.instance.isManager;
    if (_isManager && UserRoleResolver.instance.assignedFarmId != null) {
      _selectedFarmId = UserRoleResolver.instance.assignedFarmId;
    }
    _loadFarms();
  }

  @override
  void dispose() {
    _hunterNameController.dispose();
    _hunterIdController.dispose();
    _hunterAddressController.dispose();
    _vehicleRegController.dispose();
    _vehicleMakeController.dispose();
    _destinationAddressController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _loadFarms() async {
    setState(() => _isLoading = true);
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      final snapshot =
          await FirebaseFirestore.instance
              .collection('farms')
              .where('outfitterId', isEqualTo: currentUserId)
              .get();

      setState(() {
        _farms =
            snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading farms: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _addSpecies() {
    showDialog(
      context: context,
      builder:
          (context) => _AddSpeciesDialog(
            onAdd: (species) {
              setState(() {
                _speciesList.add(species);
              });
            },
          ),
    );
  }

  void _removeSpecies(int index) {
    setState(() {
      _speciesList.removeAt(index);
    });
  }

  Future<void> _submitPermit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFarmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a farm'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_speciesList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one species'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Capture signature as bytes
    Uint8List? signatureBytes;
    if (_signatureController.isNotEmpty) {
      signatureBytes = await _signatureController.toPngBytes();
    }

    setState(() => _isSubmitting = true);

    try {
      // Issue the permit and get the document ID
      final permitId = await _permitManager.issueTransportPermit(
        farmId: _selectedFarmId!,
        farmName: _selectedFarmName ?? '',
        exemptionNumber: _exemptionNumber ?? '',
        hunterName: _hunterNameController.text.trim(),
        hunterIdNumber: _hunterIdController.text.trim(),
        hunterAddress: _hunterAddressController.text.trim(),
        vehicleReg: _vehicleRegController.text.trim(),
        vehicleMake: _vehicleMakeController.text.trim(),
        speciesList: _speciesList,
        destinationAddress: _destinationAddressController.text.trim(),
      );

      // Generate and share the PDF permit with signature
      await TransportPermitPdfExporter().generateAndSharePermit(
        permitId: permitId,
        farmName: _selectedFarmName ?? '',
        exemptionNumber: _exemptionNumber ?? '',
        hunterName: _hunterNameController.text.trim(),
        hunterIdNumber: _hunterIdController.text.trim(),
        hunterAddress: _hunterAddressController.text.trim(),
        vehicleReg: _vehicleRegController.text.trim(),
        vehicleMake: _vehicleMakeController.text.trim(),
        speciesList: _speciesList,
        destinationAddress: _destinationAddressController.text.trim(),
        landownerSignatureBytes: signatureBytes,
      );

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error issuing permit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: widget.theme.cardColor,
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Permit Issued',
                  style: TextStyle(color: widget.theme.textColor),
                ),
              ],
            ),
            content: Text(
              'The statutory transport permit has been successfully generated, saved, and shared.',
              style: TextStyle(color: widget.theme.subtitleColor),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Clear form
                  _formKey.currentState?.reset();
                  _hunterNameController.clear();
                  _hunterIdController.clear();
                  _hunterAddressController.clear();
                  _vehicleRegController.clear();
                  _vehicleMakeController.clear();
                  _destinationAddressController.clear();
                  _signatureController.clear();
                  setState(() {
                    _selectedFarmId = null;
                    _selectedFarmName = null;
                    _exemptionNumber = null;
                    _speciesList.clear();
                  });
                },
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          '📝 Game Transport Permit',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.green),
              )
              : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Header Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.accentColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.description_rounded,
                            color: theme.accentColor,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'South African Game Transport Certificate',
                            style: TextStyle(
                              color: theme.textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Complete all fields to issue a statutory transport permit',
                            style: TextStyle(
                              color: theme.subtitleColor,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section 1: Farm Concession Selection
                    _buildSectionHeader(
                      'Farm Concession',
                      Icons.landscape_rounded,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.accentColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedFarmId,
                          isExpanded: true,
                          hint: Text(
                            _isManager
                                ? 'Locked to assigned farm'
                                : 'Select Farm/Concession',
                            style: TextStyle(color: theme.subtitleColor),
                          ),
                          dropdownColor: theme.cardColor,
                          style: TextStyle(color: theme.textColor),
                          icon:
                              _isManager
                                  ? Icon(
                                    Icons.lock_rounded,
                                    color: theme.accentColor,
                                  )
                                  : null,
                          items:
                              _farms.map((farm) {
                                return DropdownMenuItem(
                                  value: farm['id'] as String,
                                  child: Text(
                                    farm['name'] as String? ?? 'Unknown Farm',
                                  ),
                                );
                              }).toList(),
                          onChanged:
                              _isManager
                                  ? null
                                  : (value) {
                                    if (value == null) return;
                                    final farm = _farms.firstWhere(
                                      (f) => f['id'] == value,
                                    );
                                    setState(() {
                                      _selectedFarmId = value;
                                      _selectedFarmName =
                                          farm['name'] as String?;
                                      _exemptionNumber =
                                          farm['exemptionNumber'] as String? ??
                                          farm['caeNumber'] as String?;
                                    });
                                  },
                        ),
                      ),
                    ),
                    if (_exemptionNumber != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              color: theme.accentColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CAE/Exemption: $_exemptionNumber',
                              style: TextStyle(
                                color: theme.textColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Section 2: Hunter Personal Details
                    _buildSectionHeader(
                      'Hunter Personal Details',
                      Icons.person_rounded,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _hunterNameController,
                      label: 'Full Legal Name',
                      icon: Icons.person_outline,
                      theme: theme,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _hunterIdController,
                      label: 'National ID / Passport Number',
                      icon: Icons.badge_rounded,
                      theme: theme,
                      keyboardType: TextInputType.number,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _hunterAddressController,
                      label: 'Physical Residential Address',
                      icon: Icons.home_rounded,
                      theme: theme,
                      maxLines: 2,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),

                    // Section 3: Vehicle Information
                    _buildSectionHeader(
                      'Transport Vehicle Details',
                      Icons.directions_car_rounded,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _vehicleRegController,
                            label: 'License Plate',
                            icon: Icons.confirmation_number_rounded,
                            theme: theme,
                            textCapitalization: TextCapitalization.characters,
                            validator:
                                (v) => v?.isEmpty ?? true ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: _vehicleMakeController,
                            label: 'Vehicle Make & Model',
                            icon: Icons.car_repair_rounded,
                            theme: theme,
                            validator:
                                (v) => v?.isEmpty ?? true ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Section 4: Species Details
                    _buildSectionHeader(
                      'Animal Carcass Details',
                      Icons.pets_rounded,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.accentColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Species List
                          if (_speciesList.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.add_circle_outline,
                                    color: theme.subtitleColor,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No species added yet',
                                    style: TextStyle(
                                      color: theme.subtitleColor,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _speciesList.length,
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final species = _speciesList[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: theme.accentColor
                                        .withValues(alpha: 0.2),
                                    child: Icon(
                                      Icons.pets,
                                      color: theme.accentColor,
                                    ),
                                  ),
                                  title: Text(
                                    species['species'] as String? ?? 'Unknown',
                                    style: TextStyle(color: theme.textColor),
                                  ),
                                  subtitle: Text(
                                    'Qty: ${species['quantity']} | ${species['sex'] ?? 'N/A'}',
                                    style: TextStyle(
                                      color: theme.subtitleColor,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_rounded,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _removeSpecies(index),
                                  ),
                                );
                              },
                            ),
                          // Add Button
                          InkWell(
                            onTap: _addSpecies,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.accentColor.withValues(alpha: 0.1),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_rounded,
                                    color: theme.accentColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add Species',
                                    style: TextStyle(
                                      color: theme.accentColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section 5: Destination
                    _buildSectionHeader(
                      'Final Destination',
                      Icons.location_on_rounded,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _destinationAddressController,
                      label: 'Destination Delivery Address',
                      icon: Icons.flag_rounded,
                      theme: theme,
                      maxLines: 2,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 32),

                    // Section: Landowner Signature
                    _buildSectionHeader(
                      'Landowner Digital Signature',
                      Icons.draw_rounded,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.accentColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                            ),
                            child: SizedBox(
                              height: 150,
                              child: Signature(
                                controller: _signatureController,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(10),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Sign above with your finger',
                                  style: TextStyle(
                                    color: theme.subtitleColor,
                                    fontSize: 12,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _signatureController.clear(),
                                  icon: const Icon(Icons.clear, size: 16),
                                  label: const Text('Clear'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitPermit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            _isSubmitting
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.verified_rounded),
                                    SizedBox(width: 8),
                                    Text(
                                      'Generate & Issue Statutory Transport Permit',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    ThemeController theme,
  ) {
    return Row(
      children: [
        Icon(icon, color: theme.accentColor, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ThemeController theme,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      style: TextStyle(color: theme.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.subtitleColor),
        prefixIcon: Icon(icon, color: theme.accentColor),
        filled: true,
        fillColor: theme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.accentColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
      validator: validator,
    );
  }
}

class _AddSpeciesDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onAdd;

  const _AddSpeciesDialog({required this.onAdd});

  @override
  State<_AddSpeciesDialog> createState() => _AddSpeciesDialogState();
}

class _AddSpeciesDialogState extends State<_AddSpeciesDialog> {
  final _speciesController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _selectedSex = 'Male';

  static const List<String> _sexOptions = ['Male', 'Female'];

  @override
  void dispose() {
    _speciesController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Species'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _speciesController,
            decoration: const InputDecoration(
              labelText: 'Species Name',
              hintText: 'e.g. Kudu',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedSex,
            decoration: const InputDecoration(labelText: 'Sex'),
            items:
                _sexOptions.map((sex) {
                  return DropdownMenuItem(value: sex, child: Text(sex));
                }).toList(),
            onChanged:
                (value) => setState(() => _selectedSex = value ?? 'Male'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_speciesController.text.isEmpty) return;
            widget.onAdd({
              'species': _speciesController.text.trim(),
              'sex': _selectedSex,
              'quantity': int.tryParse(_quantityController.text) ?? 1,
            });
            Navigator.of(context).pop();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
