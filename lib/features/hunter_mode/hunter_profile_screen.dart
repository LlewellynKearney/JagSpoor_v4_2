import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

class HunterProfileScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterProfileScreen({super.key, required this.theme});

  @override
  State<HunterProfileScreen> createState() => _HunterProfileScreenState();
}

class _HunterProfileScreenState extends State<HunterProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Contact Info
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altContactController = TextEditingController();
  final _emailController = TextEditingController();

  // Location Info
  final _addressController = TextEditingController();
  final _farmNameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  // Emergency Medical
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _medicalAidController = TextEditingController();
  final _emergencyContactController = TextEditingController();

  // Legal Compliance
  final _idNumberController = TextEditingController();
  final _hunterStatusController = TextEditingController();
  final _provincialPermitsController = TextEditingController();

  bool _hasFirstAid = false;
  String? _profileImageUrl;
  bool _isLoading = false;
  bool _isUploading = false;
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _altContactController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _farmNameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _medicalAidController.dispose();
    _emergencyContactController.dispose();
    _idNumberController.dispose();
    _hunterStatusController.dispose();
    _provincialPermitsController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Try loading from cache first
      final prefs = await SharedPreferences.getInstance();
      final cachedProfile = prefs.getString('cached_profile_$user.uid');

      if (cachedProfile != null) {
        _populateProfileFromCache(cachedProfile);
      }

      // Load from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _fullNameController.text = data['fullName'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _altContactController.text = data['altContact'] ?? '';
          _emailController.text = data['email'] ?? '';
          _addressController.text = data['address'] ?? '';
          _farmNameController.text = data['farmName'] ?? '';
          _latitudeController.text = data['latitude'] ?? '';
          _longitudeController.text = data['longitude'] ?? '';
          _bloodTypeController.text = data['bloodType'] ?? '';
          _allergiesController.text = data['allergies'] ?? '';
          _medicalAidController.text = data['medicalAid'] ?? '';
          _emergencyContactController.text = data['emergencyContact'] ?? '';
          _idNumberController.text = data['idNumber'] ?? '';
          _hunterStatusController.text = data['hunterStatus'] ?? '';
          _provincialPermitsController.text = data['provincialPermits'] ?? '';
          _hasFirstAid = data['hasFirstAid'] ?? false;
          _profileImageUrl = data['profileImageUrl'];
        });

        // Cache the profile data
        await _cacheProfileData(data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    }
  }

  void _populateProfileFromCache(String cachedJson) {
    // Basic cache population - will be updated by Firestore
  }

  Future<void> _cacheProfileData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Cache key fields for offline use
    await prefs.setString('cached_profile_${user.uid}', data.toString());
  }

  Future<void> _pickImage() async {
    if (!mounted) return;

    // Show bottom sheet to choose between camera and gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('profile.jpg');

      final uploadTask = storageRef.putFile(File(pickedFile.path));
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _profileImageUrl = downloadUrl;
        _isUploading = false;
      });
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error uploading image: $e')));
      }
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled.')),
          );
        }
        setState(() => _isFetchingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied.')),
            );
          }
          setState(() => _isFetchingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied.'),
            ),
          );
        }
        setState(() => _isFetchingLocation = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
        _isFetchingLocation = false;
      });
    } catch (e) {
      setState(() => _isFetchingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final profileData = {
        'fullName': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'altContact': _altContactController.text.trim(),
        'email': _emailController.text.trim(),
        'address': _addressController.text.trim(),
        'farmName': _farmNameController.text.trim(),
        'latitude': _latitudeController.text.trim(),
        'longitude': _longitudeController.text.trim(),
        'bloodType': _bloodTypeController.text.trim(),
        'allergies': _allergiesController.text.trim(),
        'medicalAid': _medicalAidController.text.trim(),
        'emergencyContact': _emergencyContactController.text.trim(),
        'idNumber': _idNumberController.text.trim(),
        'hunterStatus': _hunterStatusController.text.trim(),
        'provincialPermits': _provincialPermitsController.text.trim(),
        'hasFirstAid': _hasFirstAid,
        'profileImageUrl': _profileImageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(profileData, SetOptions(merge: true));

      // Update cache
      await _cacheProfileData(profileData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'Hunter Profile',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: widget.theme.backgroundColor,
            iconTheme: IconThemeData(color: widget.theme.accentColor),
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Theme Settings Section (moved to top)
                  Text(
                    'HUD VISUAL SETTINGS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: widget.theme.subtitleColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: widget.theme.cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: widget.theme.accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        'Dark Mode Ambient',
                        style: TextStyle(color: widget.theme.textColor),
                      ),
                      trailing: Switch(
                        value: widget.theme.isDarkMode,
                        activeThumbColor: widget.theme.accentColor,
                        onChanged: (v) => widget.theme.toggleThemeMode(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: widget.theme.cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: widget.theme.accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          ElevatedButton(
                            onPressed: () => widget.theme.setConcept(
                              HuntingConcept.thermalGlow,
                            ),
                            child: const Text('Thermal'),
                          ),
                          ElevatedButton(
                            onPressed: () => widget.theme.setConcept(
                              HuntingConcept.walnutLuxury,
                            ),
                            child: const Text('Walnut'),
                          ),
                          ElevatedButton(
                            onPressed: () => widget.theme.setConcept(
                              HuntingConcept.neonShock,
                            ),
                            child: const Text('Neon'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Profile Photo Section
                  Center(
                    child: GestureDetector(
                      onTap: _isUploading ? null : _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: widget.theme.cardColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.theme.accentColor,
                                width: 2,
                              ),
                            ),
                            child: _isUploading
                                ? Center(
                                    child: CircularProgressIndicator(
                                      color: widget.theme.accentColor,
                                    ),
                                  )
                                : _profileImageUrl != null
                                ? ClipOval(
                                    child: Image.network(
                                      _profileImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Icon(
                                              Icons.person,
                                              size: 60,
                                              color: widget.theme.subtitleColor,
                                            );
                                          },
                                    ),
                                  )
                                : Icon(
                                    Icons.add_a_photo,
                                    size: 40,
                                    color: widget.theme.subtitleColor,
                                  ),
                          ),
                          if (!_isUploading)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.theme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 20,
                                  color: widget.theme.backgroundColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Tap to upload photo',
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Contact Info Section
                  _buildSectionHeader('CONTACT INFORMATION'),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _fullNameController,
                    'Full Name',
                    'Enter your full name',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _phoneController,
                    'Phone Number',
                    'Enter your phone number',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _altContactController,
                    'Alternative Field/Radio Contact',
                    'Alternative contact number',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _emailController,
                    'Email Address',
                    'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 24),

                  // Location Info Section
                  _buildSectionHeader('LOCATION INFORMATION'),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _addressController,
                    'Home Address',
                    'Enter your home address',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _farmNameController,
                    'Hunting Farm/Camp Name',
                    'Name of your hunting location',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _latitudeController,
                          'Latitude',
                          'GPS latitude',
                          keyboardType: TextInputType.number,
                          enabled: !_isFetchingLocation,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _longitudeController,
                          'Longitude',
                          'GPS longitude',
                          keyboardType: TextInputType.number,
                          enabled: !_isFetchingLocation,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isFetchingLocation
                          ? null
                          : _fetchCurrentLocation,
                      icon: _isFetchingLocation
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: widget.theme.backgroundColor,
                              ),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(
                        _isFetchingLocation
                            ? 'Fetching...'
                            : 'Fetch Current Location',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.accentColor,
                        foregroundColor: widget.theme.backgroundColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Emergency Medical Section
                  _buildSectionHeader('EMERGENCY MEDICAL INFORMATION'),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _bloodTypeController,
                    'Blood Type',
                    'e.g., A+, O-, etc.',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _allergiesController,
                    'Allergies',
                    'List any known allergies',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _medicalAidController,
                    'Medical Aid Details',
                    'Medical aid scheme and number',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _emergencyContactController,
                    'Emergency Contact',
                    'Name and phone number',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 24),

                  // Legal Compliance Section
                  _buildSectionHeader('LEGAL COMPLIANCE'),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _idNumberController,
                    'SA ID Number',
                    '13-digit South African ID',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _hunterStatusController,
                    'Dedicated Hunter Status Number',
                    'Your dedicated hunter status',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _provincialPermitsController,
                    'Active Provincial Permit Numbers',
                    'Comma-separated permit numbers',
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: Text(
                      'Basic First Aid Certified',
                      style: TextStyle(color: widget.theme.textColor),
                    ),
                    value: _hasFirstAid,
                    onChanged: (val) =>
                        setState(() => _hasFirstAid = val ?? false),
                    activeColor: widget.theme.accentColor,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 32),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.accentColor,
                        foregroundColor: widget.theme.backgroundColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'SAVE PROFILE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: widget.theme.subtitleColor,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: widget.theme.textColor),
      keyboardType: keyboardType,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: widget.theme.subtitleColor.withValues(alpha: 0.5),
        ),
        labelStyle: TextStyle(color: widget.theme.subtitleColor),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: widget.theme.accentColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: widget.theme.accentColor.withValues(alpha: 0.5),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: widget.theme.subtitleColor.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
