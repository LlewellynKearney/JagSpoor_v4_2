import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/saps_pdf_generator.dart';

class FirearmRenewalScreen extends StatefulWidget {
  final ThemeController theme;
  final Map<String, String> firearm;

  const FirearmRenewalScreen({
    super.key,
    required this.theme,
    required this.firearm,
  });

  @override
  State<FirearmRenewalScreen> createState() => _FirearmRenewalScreenState();
}

class _FirearmRenewalScreenState extends State<FirearmRenewalScreen> {
  final _formKey = GlobalKey<FormState>();

  // Profile controllers (Section D)
  late TextEditingController _fullNameController;
  late TextEditingController _surnameController;
  late TextEditingController _idNumberController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;

  // Supplemental SAPS fields
  late TextEditingController _policeStationController;
  late TextEditingController _safeTypeController;
  late TextEditingController _associationNoController;
  late TextEditingController _motivationController;

  bool _isLoadingProfile = true;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _surnameController = TextEditingController();
    _idNumberController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();

    _policeStationController = TextEditingController(text: 'Pretoria Central DFO');
    _safeTypeController = TextEditingController(text: 'Wall-mounted SABS 953-1 B1 Safe (Floor Anchored)');
    _associationNoController = TextEditingController();
    _motivationController = TextEditingController(
      text: 'Applicant continues active participation in dedicated hunting and sport shooting activities as registered with accredited hunting association under FCA 60 of 2000.',
    );

    _loadHunterProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _surnameController.dispose();
    _idNumberController.dispose();
    _phoneController.dispose();
    _addressController.dispose();

    _policeStationController.dispose();
    _safeTypeController.dispose();
    _associationNoController.dispose();
    _motivationController.dispose();
    super.dispose();
  }

  Future<void> _loadHunterProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          setState(() {
            _fullNameController.text = data['fullName'] ?? data['name'] ?? '';
            _surnameController.text = data['surname'] ?? '';
            _idNumberController.text = data['idNumber'] ?? '';
            _phoneController.text = data['phone'] ?? data['cell'] ?? '';
            _addressController.text = data['address'] ?? data['physicalAddress'] ?? '';
            if ((data['dfoStation'] ?? '').isNotEmpty) {
              _policeStationController.text = data['dfoStation'];
            }
            if ((data['associationNo'] ?? '').isNotEmpty) {
              _associationNoController.text = data['associationNo'];
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading profile for SAPS 518(a): $e');
      }
    }
    if (mounted) {
      setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _generateSapsForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isGeneratingPdf = true);

    try {
      await SapsPdfGenerator.printOrShare518a(
        firearm: widget.firearm,
        fullName: _fullNameController.text.trim(),
        surname: _surnameController.text.trim(),
        idNumber: _idNumberController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        policeStation: _policeStationController.text.trim(),
        safeType: _safeTypeController.text.trim(),
        associationNo: _associationNoController.text.trim(),
        motivation: _motivationController.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating SAPS 518(a) PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final firearm = widget.firearm;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'SAPS 518(a) RENEWAL COMPILATION',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: _isLoadingProfile
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Firearm Pre-populated Details Card (Section C)
                      _buildHeaderCard(theme, firearm),
                      const SizedBox(height: 20),

                      // Section D: Applicant Details
                      Text(
                        'SECTION D: APPLICANT PROFILE DATA',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.subtitleColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _fullNameController,
                        label: 'Full Name(s)',
                        icon: Icons.person,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _surnameController,
                        label: 'Surname',
                        icon: Icons.person_outline,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _idNumberController,
                        label: 'Identity Number',
                        icon: Icons.badge_outlined,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _phoneController,
                        label: 'Contact Telephone / Cell',
                        icon: Icons.phone_android,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _addressController,
                        label: 'Physical Residential Address',
                        icon: Icons.home_work_outlined,
                        maxLines: 2,
                        theme: theme,
                      ),
                      const SizedBox(height: 24),

                      // Supplemental SAPS Form Fields
                      Text(
                        'SUPPLEMENTAL SAPS MANDATORY DATA',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.subtitleColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _policeStationController,
                        label: 'Nearest Police Station (Home DFO Office)',
                        icon: Icons.local_police_outlined,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _safeTypeController,
                        label: 'Type of Safe Installed (SABS 953-1)',
                        icon: Icons.lock_clock_outlined,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _associationNoController,
                        label: 'Accredited Hunting Association Membership No.',
                        icon: Icons.workspace_premium_outlined,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _motivationController,
                        label: 'Written Renewal Motivation Statement',
                        icon: Icons.article_outlined,
                        maxLines: 4,
                        theme: theme,
                      ),
                      const SizedBox(height: 28),

                      // Submit Button to Compile PDF
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: _isGeneratingPdf
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.print_rounded, color: Colors.black),
                          label: Text(
                            _isGeneratingPdf
                                ? 'COMPILING SAPS 518(a)...'
                                : 'COMPILE & PRINT SAPS 518(a) FORM',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black,
                            ),
                          ),
                          onPressed: _isGeneratingPdf ? null : _generateSapsForm,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderCard(ThemeController theme, Map<String, String> firearm) {
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
                Icon(Icons.assignment_outlined, color: theme.accentColor),
                const SizedBox(width: 10),
                Text(
                  'SECTION C: TARGET FIREARM DATA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Make: ${firearm['make'] ?? 'N/A'} | Caliber: ${firearm['caliber'] ?? 'N/A'}',
                style: TextStyle(color: theme.textColor, fontWeight: FontWeight.w600)),
            Text('Serial Number: ${firearm['serial'] ?? 'N/A'}',
                style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
            Text('Original Licence No: ${firearm['licenceNo'] ?? firearm['licenseNumber'] ?? 'N/A'}',
                style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
            Text('Licence Expiry: ${firearm['expiry'] ?? 'N/A'}',
                style: TextStyle(color: theme.accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ThemeController theme,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: theme.textColor),
      decoration: InputDecoration(
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
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Please enter $label';
        }
        return null;
      },
    );
  }
}
