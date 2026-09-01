import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/copyright_footer.dart';
import '../../core/services/image_service.dart';
import '../../core/utils/measurement_formatter.dart';
import '../auth/change_password_dialog.dart';
import '../auth/screens/privacy_policy_screen.dart';
import '../authentication/services/auth_gate_service.dart';
import 'services/battery_saver_manager.dart';
import 'services/account_deletion_service.dart';
import 'widgets/hunter_scaffold.dart';

class HunterProfileScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterProfileScreen({super.key, required this.theme});

  @override
  State<HunterProfileScreen> createState() => _HunterProfileScreenState();
}

class _HunterProfileScreenState extends State<HunterProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Contact Info
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
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
  bool _isBatterySaverEnabled = false;
  String? _profileImageUrl;
  bool _isLoading = false;
  bool _isUploading = false;
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadBatterySaverState();
  }

  Future<void> _loadBatterySaverState() async {
    final manager = BatterySaverManager();
    final isEnabled = await manager.isBatterySaverEnabled();
    if (mounted) {
      setState(() => _isBatterySaverEnabled = isEnabled);
    }
  }

  Future<void> _toggleBatterySaver(bool value) async {
    final manager = BatterySaverManager();
    await manager.toggleBatterySaver(value);
    setState(() => _isBatterySaverEnabled = value);
  }

  Widget _buildUnitPreferenceCard() {
    final fmt = MeasurementFormatter.instance;
    return Card(
      color: HunterUi.cardColor(widget.theme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten_rounded,
                    color: widget.theme.accentColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Unit Preference',
                  style: TextStyle(
                    color: HunterUi.titleColor(widget.theme),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Measurement units shown across Hunter Mode (weights, distances, barrel lengths, temperature).',
              style: TextStyle(
                color: HunterUi.subtitleColor(widget.theme),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: fmt,
              builder: (context, _) {
                final isMetric = fmt.isMetric;
                return ToggleButtons(
                  isSelected: [isMetric, !isMetric],
                  onPressed: (index) => fmt.setSystem(
                    index == 0 ? UnitSystem.metric : UnitSystem.imperial,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  borderColor: widget.theme.accentColor.withValues(alpha: 0.3),
                  selectedBorderColor: widget.theme.accentColor,
                  selectedColor: widget.theme.backgroundColor,
                  fillColor: widget.theme.accentColor,
                  color: HunterUi.titleColor(widget.theme),
                  constraints: const BoxConstraints(minHeight: 40),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Metric  kg · m · °C'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Imperial  lbs · yd · °F'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
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
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          // First / last name: prefer the explicit fields, fall back to the
          // legacy single `fullName` (split on the first space) so a
          // returning hunter who completed the pre-split form is not bounced
          // back to onboarding.
          final legacyFull = (data['fullName'] as String?)?.trim() ?? '';
          _firstNameController.text = (data['firstName'] as String?)?.trim() ??
              (data['first_name'] as String?)?.trim() ??
              (data['name'] as String?)?.trim() ??
              (legacyFull.contains(' ')
                  ? legacyFull.substring(0, legacyFull.indexOf(' '))
                  : legacyFull);
          _lastNameController.text = (data['lastName'] as String?)?.trim() ??
              (data['last_name'] as String?)?.trim() ??
              (data['surname'] as String?)?.trim() ??
              (legacyFull.contains(' ')
                  ? legacyFull.substring(legacyFull.indexOf(' ') + 1)
                  : '');
          _fullNameController.text = legacyFull;
          _phoneController.text = data['phone'] ?? data['phoneNumber'] ?? '';
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
      builder:
          (context) => SafeArea(
            bottom: true,
            child: Container(
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
          ),
    );

    if (source == null) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final downloadUrl = await ImageService.pickCompressAndUpload(
        source,
        'users/${user.uid}/profile.jpg',
      );

      if (downloadUrl == null) {
        setState(() => _isUploading = false);
        return;
      }

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

      // Compose the full name from the mandatory first + last name fields.
      final first = _firstNameController.text.trim();
      final last = _lastNameController.text.trim();
      final composedFullName =
          [first, last].where((p) => p.isNotEmpty).join(' ');

      final profileData = {
        'firstName': first,
        'lastName': last,
        'fullName': composedFullName,
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
        return HunterScaffold(
          theme: widget.theme,
          appBar: AppBar(
            title: Text(
              'Hunter Profile',
              style: TextStyle(
                color: HunterUi.titleColor(widget.theme),
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.transparent,
            iconTheme: IconThemeData(color: HunterUi.titleColor(widget.theme)),
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + kToolbarHeight + 8,
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
                      color: HunterUi.subtitleColor(widget.theme),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: HunterUi.cardColor(widget.theme),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: widget.theme.accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        'Dark Mode Ambient',
                        style: TextStyle(color: HunterUi.titleColor(widget.theme)),
                      ),
                      trailing: Switch(
                        value: widget.theme.isDarkMode,
                        onChanged: (v) => widget.theme.setDarkMode(v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildUnitPreferenceCard(),
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
                              color: HunterUi.cardColor(widget.theme),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.theme.accentColor,
                                width: 2,
                              ),
                            ),
                            child:
                                _isUploading
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
                                        errorBuilder: (
                                          context,
                                          error,
                                          stackTrace,
                                        ) {
                                          return Icon(
                                            Icons.person,
                                            size: 60,
                                            color: HunterUi.subtitleColor(widget.theme),
                                          );
                                        },
                                      ),
                                    )
                                    : Icon(
                                      Icons.add_a_photo,
                                      size: 40,
                                      color: HunterUi.subtitleColor(widget.theme),
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
                        color: HunterUi.subtitleColor(widget.theme),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Contact Info Section
                  _buildSectionHeader('CONTACT INFORMATION *'),
                  const SizedBox(height: 4),
                  Text(
                    'Name, Surname, and a contact detail (phone or email) '
                    'are mandatory. You cannot use the app until these are '
                    'completed.',
                    style: TextStyle(
                      color: HunterUi.subtitleColor(widget.theme),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _firstNameController,
                          'First Name *',
                          'Enter your first name',
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'First name is required'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          _lastNameController,
                          'Surname *',
                          'Enter your surname',
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Surname is required'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _phoneController,
                    'Phone Number *',
                    'Enter your phone number',
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final phone = v?.trim() ?? '';
                      final email = _emailController.text.trim();
                      if (phone.isEmpty && email.isEmpty) {
                        return 'Enter a phone number or an email';
                      }
                      return null;
                    },
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
                    'Email Address *',
                    'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final email = v?.trim() ?? '';
                      final phone = _phoneController.text.trim();
                      if (email.isEmpty && phone.isEmpty) {
                        return 'Enter an email or a phone number';
                      }
                      if (email.isNotEmpty &&
                          !RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$')
                              .hasMatch(email)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
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
                      onPressed:
                          _isFetchingLocation ? null : _fetchCurrentLocation,
                      icon:
                          _isFetchingLocation
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

                  // Off-Grid Battery Optimization Mode
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          _isBatterySaverEnabled
                              ? Colors.orange.withValues(alpha: 0.1)
                              : HunterUi.cardColor(widget.theme),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            _isBatterySaverEnabled
                                ? Colors.orange
                                : widget.theme.accentColor.withValues(
                                  alpha: 0.3,
                                ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isBatterySaverEnabled
                              ? Icons.battery_saver
                              : Icons.battery_full,
                          color:
                              _isBatterySaverEnabled
                                  ? Colors.orange
                                  : widget.theme.accentColor,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Off-Grid Battery Optimization',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: HunterUi.titleColor(widget.theme),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isBatterySaverEnabled
                                    ? '⚡ Performance mode active'
                                    : '🔋 Energy conservation active',
                                style: TextStyle(
                                  color:
                                      _isBatterySaverEnabled
                                          ? Colors.orange
                                          : HunterUi.subtitleColor(widget.theme),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isBatterySaverEnabled,
                          onChanged: _toggleBatterySaver,
                          activeTrackColor: Colors.orange.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: Text(
                      'Basic First Aid Certified',
                      style: TextStyle(color: HunterUi.titleColor(widget.theme)),
                    ),
                    value: _hasFirstAid,
                    onChanged:
                        (val) => setState(() => _hasFirstAid = val ?? false),
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
                      child:
                          _isLoading
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
                  const SizedBox(height: 32),

                  // Account Security Section
                  _buildSectionHeader('ACCOUNT SECURITY'),
                  const SizedBox(height: 12),
                  Card(
                    color: HunterUi.cardColor(widget.theme),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: widget.theme.accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.lock_person_outlined,
                        color: widget.theme.accentColor,
                      ),
                      title: Text(
                        'Change Password',
                        style: TextStyle(color: HunterUi.titleColor(widget.theme)),
                      ),
                      subtitle: Text(
                        'Re-authenticate and set a new password.',
                        style: TextStyle(
                          color: HunterUi.subtitleColor(widget.theme),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: HunterUi.subtitleColor(widget.theme),
                      ),
                      onTap: _showChangePasswordDialog,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _logout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Privacy & Data - Google Play policy compliance. Exposes
                  // the privacy policy and the in-app account/data deletion
                  // mechanism so users can request erasure without leaving
                  // the app (required by the Google Play Data safety +
                  // account-deletion policy).
                  _buildSectionHeader('PRIVACY & DATA'),
                  const SizedBox(height: 12),
                  Card(
                    color: HunterUi.cardColor(widget.theme),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: widget.theme.accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.privacy_tip_outlined,
                            color: widget.theme.accentColor,
                          ),
                          title: Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: HunterUi.titleColor(widget.theme),
                            ),
                          ),
                          subtitle: Text(
                            'How JagSpoor collects, uses and protects your data.',
                            style: TextStyle(
                              color: HunterUi.subtitleColor(widget.theme),
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: HunterUi.subtitleColor(widget.theme),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrivacyPolicyScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            Icons.delete_sweep_outlined,
                            color: Colors.red.shade400,
                          ),
                          title: Text(
                            'Delete My Account & Data',
                            style: TextStyle(
                              color: HunterUi.titleColor(widget.theme),
                            ),
                          ),
                          subtitle: Text(
                            'Permanently erase your account and all associated '
                            'personal data (in-app, no web form required).',
                            style: TextStyle(
                              color: HunterUi.subtitleColor(widget.theme),
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: HunterUi.subtitleColor(widget.theme),
                          ),
                          onTap: _showDeleteAccountDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Delete Account & All Personal Data - Danger Zone
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'DANGER ZONE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Permanently delete your account and all associated personal data from the JagSpoor ecosystem.',
                          style: TextStyle(
                            fontSize: 12,
                            color: HunterUi.subtitleColor(widget.theme),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showDeleteAccountDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.delete_forever, size: 20),
                            label: const Text(
                              'DELETE ACCOUNT & ALL PERSONAL DATA',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const CopyrightFooter(),
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
        color: HunterUi.subtitleColor(widget.theme),
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: HunterUi.titleColor(widget.theme)),
      keyboardType: keyboardType,
      enabled: enabled,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: HunterUi.subtitleColor(widget.theme).withValues(alpha: 0.5),
        ),
        labelStyle: TextStyle(color: HunterUi.subtitleColor(widget.theme)),
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
            color: HunterUi.subtitleColor(widget.theme).withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            backgroundColor: HunterUi.cardColor(widget.theme),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.red.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Delete Account',
                  style: TextStyle(
                    color: HunterUi.titleColor(widget.theme),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This action is IRREVERSIBLE and will permanently wipe ALL records from the system including:',
                  style: TextStyle(
                    color: HunterUi.titleColor(widget.theme),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _buildBulletPoint('Your profile and contact information'),
                _buildBulletPoint('All firearms and ammunition data'),
                _buildBulletPoint('Carcass logs and waypoints'),
                _buildBulletPoint('Processing orders and hunt records'),
                _buildBulletPoint('Your authentication credential'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You will be immediately logged out and cannot recover your account.',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'CANCEL',
                  style: TextStyle(color: HunterUi.subtitleColor(widget.theme)),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'DELETE FOREVER',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _handleAccountDeletion();
    }
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.red, fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: HunterUi.subtitleColor(widget.theme), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    await ChangePasswordDialog.show(context);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: HunterUi.cardColor(widget.theme),
        title: Text(
          'Sign Out',
          style: TextStyle(color: HunterUi.titleColor(widget.theme)),
        ),
        content: Text(
          'Are you sure you want to sign out of your JagSpoor account?',
          style: TextStyle(color: HunterUi.subtitleColor(widget.theme)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'CANCEL',
              style: TextStyle(color: HunterUi.subtitleColor(widget.theme)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await AuthGateService().signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Sign out failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleAccountDeletion() async {
    setState(() => _isLoading = true);

    try {
      final deletionService = AccountDeletionService();
      await deletionService.deleteUserEntireDataPack();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account and all data has been permanently deleted.'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate to login or close the app
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);

      if (mounted) {
        if (e.code == 'requires-recent-login') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.lock_outline, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Security Verification Required: Please log out and sign back in to complete account deletion.',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deletion failed: ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
