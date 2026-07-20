import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import '../../core/theme/app_theme.dart';

class EditTrophyScreen extends StatefulWidget {
  final ThemeController theme;
  final Map<String, dynamic> trophy;
  final List<Map<String, String>>? firearms;

  const EditTrophyScreen({
    super.key,
    required this.theme,
    required this.trophy,
    this.firearms,
  });

  @override
  State<EditTrophyScreen> createState() => _EditTrophyScreenState();
}

class _EditTrophyScreenState extends State<EditTrophyScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  late TextEditingController _speciesController;
  late TextEditingController _locationController;
  late TextEditingController _antlerSpreadController;
  late TextEditingController _antlerLengthController;
  late TextEditingController _antlerCircumferenceController;
  late TextEditingController _weightController;
  late TextEditingController _tagsController;

  DateTime? _harvestDate;
  String? _selectedFirearmId;
  String? _selectedFirearmDisplay;
  String? _gpsCoordinates;
  bool _isLoadingGps = false;
  final List<File> _selectedPhotos = [];
  final List<String> _tags = [];
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _speciesController = TextEditingController(
      text: widget.trophy['species'] ?? '',
    );
    _locationController = TextEditingController(
      text: widget.trophy['location'] ?? '',
    );
    _antlerSpreadController = TextEditingController(
      text: widget.trophy['antlerSpread']?.toString() ?? '',
    );
    _antlerLengthController = TextEditingController(
      text: widget.trophy['antlerLength']?.toString() ?? '',
    );
    _antlerCircumferenceController = TextEditingController(
      text: widget.trophy['antlerCircumference']?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: widget.trophy['weight']?.toString() ?? '',
    );
    _tagsController = TextEditingController();

    _harvestDate = widget.trophy['harvestDate'] != null
        ? DateTime.parse(widget.trophy['harvestDate'] as String)
        : null;
    _selectedFirearmId = widget.trophy['firearmId'];
    _selectedFirearmDisplay = widget.trophy['firearmUsed'];
    _gpsCoordinates = widget.trophy['coordinates'];

    if (widget.trophy['tags'] is List) {
      _tags.addAll(List<String>.from(widget.trophy['tags']));
    }
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _locationController.dispose();
    _antlerSpreadController.dispose();
    _antlerLengthController.dispose();
    _antlerCircumferenceController.dispose();
    _weightController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _selectHarvestDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: widget.theme.accentColor,
              surface: widget.theme.backgroundColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _harvestDate) {
      setState(() => _harvestDate = picked);
    }
  }

  Future<void> _fetchGpsCoordinates() async {
    setState(() => _isLoadingGps = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission denied. Enable in device settings.',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: Geolocator.openLocationSettings,
              ),
            ),
          );
        }
        setState(() => _isLoadingGps = false);
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        try {
          final Position position =
              await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 30),
              ).timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw 'GPS timeout - check device settings',
              );

          setState(() {
            _gpsCoordinates =
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
            _locationController.text = _gpsCoordinates ?? '';
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('GPS coordinates updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } on Exception catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('GPS Error: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoadingGps = false);
    }
  }

  Future<void> _takePhoto() async {
    if (_selectedPhotos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum 3 photos allowed'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
      );
      if (photo != null) {
        setState(() => _selectedPhotos.add(File(photo.path)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_selectedPhotos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum 3 photos allowed'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (photo != null) {
        setState(() => _selectedPhotos.add(File(photo.path)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() => _selectedPhotos.removeAt(index));
  }

  void _addTag() {
    final tag = _tagsController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagsController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  void _saveTrophy() {
    if (_formKey.currentState?.validate() ?? false) {
      final updatedTrophy = {
        ...widget.trophy,
        'species': _speciesController.text,
        'harvestDate': _harvestDate?.toIso8601String().split('T').first ?? '',
        'location': _locationController.text,
        'coordinates': _gpsCoordinates ?? '',
        'antlerSpread': _antlerSpreadController.text.isEmpty
            ? null
            : _antlerSpreadController.text,
        'antlerLength': _antlerLengthController.text.isEmpty
            ? null
            : _antlerLengthController.text,
        'antlerCircumference': _antlerCircumferenceController.text.isEmpty
            ? null
            : _antlerCircumferenceController.text,
        'weight': _weightController.text.isEmpty
            ? null
            : _weightController.text,
        'firearmUsed': _selectedFirearmDisplay ?? '',
        'firearmId': _selectedFirearmId,
        'tags': _tags,
        'photos': _selectedPhotos.isNotEmpty
            ? _selectedPhotos.map((f) => f.path).toList()
            : (widget.trophy['photos'] ?? []),
      };

      Navigator.pop(context, updatedTrophy);
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
              'EDIT TROPHY',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: widget.theme.backgroundColor,
            iconTheme: IconThemeData(color: widget.theme.accentColor),
            elevation: 0,
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                children: [
                  // Species field
                  _buildSectionTitle('SPECIES'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _speciesController,
                    decoration: _buildInputDecoration(
                      'e.g., Impala Buck, Kudu Bull',
                    ),
                    style: TextStyle(color: widget.theme.textColor),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Species is required' : null,
                  ),
                  const SizedBox(height: 24),

                  // Harvest date picker
                  _buildSectionTitle('HARVEST DATE'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selectHarvestDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: widget.theme.accentColor.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: widget.theme.accentColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _harvestDate != null
                                ? DateFormat(
                                    'MMM dd, yyyy',
                                  ).format(_harvestDate!)
                                : 'Select date',
                            style: TextStyle(
                              color: _harvestDate != null
                                  ? widget.theme.textColor
                                  : widget.theme.subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Location section
                  _buildSectionTitle('LOCATION / AREA'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _locationController,
                    decoration: _buildInputDecoration('Enter location'),
                    style: TextStyle(color: widget.theme.textColor),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isLoadingGps
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.theme.isDarkMode
                                      ? Colors.black
                                      : Colors.white,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.gps_fixed,
                              color: widget.theme.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                            ),
                      label: Text(
                        _isLoadingGps ? 'Logging GPS...' : 'UPDATE GPS',
                        style: TextStyle(
                          color: widget.theme.isDarkMode
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _isLoadingGps ? null : _fetchGpsCoordinates,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Measurement data section
                  _buildSectionTitle('MEASUREMENT DATA'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _antlerSpreadController,
                    decoration: _buildInputDecoration('Antler Spread (cm)'),
                    style: TextStyle(color: widget.theme.textColor),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _antlerLengthController,
                    decoration: _buildInputDecoration('Antler Length (cm)'),
                    style: TextStyle(color: widget.theme.textColor),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _antlerCircumferenceController,
                    decoration: _buildInputDecoration(
                      'Antler Circumference (cm)',
                    ),
                    style: TextStyle(color: widget.theme.textColor),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Weight field
                  _buildSectionTitle('WEIGHT'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _weightController,
                    decoration: _buildInputDecoration('Weight (kg)'),
                    style: TextStyle(color: widget.theme.textColor),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Firearm dropdown - Firestore stream
                  _buildSectionTitle('FIREARM USED'),
                  const SizedBox(height: 8),
                  _buildFirearmStreamDropdown(),
                  const SizedBox(height: 24),

                  // Tags section
                  _buildSectionTitle('TAGS'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _tagsController,
                          decoration: _buildInputDecoration('Add tag'),
                          style: TextStyle(color: widget.theme.textColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: widget.theme.accentColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.add,
                            color: widget.theme.isDarkMode
                                ? Colors.black
                                : Colors.white,
                          ),
                          onPressed: _addTag,
                        ),
                      ),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: widget.theme.accentColor.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: widget.theme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      color: widget.theme.accentColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => _removeTag(tag),
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: widget.theme.accentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Photos section
                  _buildSectionTitle('PHOTOS'),
                  const SizedBox(height: 8),
                  if (_selectedPhotos.isNotEmpty)
                    Column(
                      children: [
                        SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedPhotos.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: widget.theme.accentColor
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(
                                          _selectedPhotos[index],
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _removePhoto(index),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          padding: const EdgeInsets.all(2),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  if (_selectedPhotos.length < 3)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.theme.accentColor,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: Icon(
                              Icons.camera_alt,
                              color: widget.theme.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            label: Text(
                              'TAKE PHOTO',
                              style: TextStyle(
                                color: widget.theme.isDarkMode
                                    ? Colors.black
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _takePhoto,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.theme.accentColor
                                  .withValues(alpha: 0.7),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: Icon(
                              Icons.image,
                              color: widget.theme.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            label: Text(
                              'GALLERY',
                              style: TextStyle(
                                color: widget.theme.isDarkMode
                                    ? Colors.black
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _pickFromGallery,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(
                        Icons.check,
                        color: widget.theme.isDarkMode
                            ? Colors.black
                            : Colors.white,
                      ),
                      label: Text(
                        'SAVE CHANGES',
                        style: TextStyle(
                          color: widget.theme.isDarkMode
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      onPressed: _saveTrophy,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
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

  Widget _buildFirearmStreamDropdown() {
    return StreamBuilder<QuerySnapshot>(
      stream: _currentUserId != null
          ? FirebaseFirestore.instance
                .collection('firearms')
                .where('ownerId', isEqualTo: _currentUserId)
                .orderBy('createdAt', descending: true)
                .snapshots()
          : const Stream.empty(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.theme.accentColor.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(8),
              color: widget.theme.cardColor,
            ),
            child: Center(
              child: Text(
                'Error loading firearms',
                style: TextStyle(color: widget.theme.subtitleColor),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.theme.accentColor.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(8),
              color: widget.theme.cardColor,
            ),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.theme.accentColor,
                ),
              ),
            ),
          );
        }

        final firearms = snapshot.data?.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return <String, String>{
            'docId': doc.id,
            ...data.map((key, value) => MapEntry(key, value?.toString() ?? '')),
          };
        }).toList();

        if (firearms == null || firearms.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.theme.accentColor.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(8),
              color: widget.theme.cardColor,
            ),
            child: Center(
              child: Text(
                'No firearms available. Add firearms to the Digital Firearm Safe first.',
                style: TextStyle(
                  color: widget.theme.subtitleColor,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return DropdownButtonFormField<String>(
          initialValue: _selectedFirearmId,
          onChanged: (value) {
            if (value != null) {
              final firearm = firearms.firstWhere(
                (f) => (f['docId'] ?? '') == value,
                orElse: () => {},
              );
              setState(() {
                _selectedFirearmId = value;
                _selectedFirearmDisplay =
                    '${firearm['make']} (${firearm['caliber']})';
              });
            }
          },
          items: firearms.map((firearm) {
            final docId = firearm['docId'] ?? '';
            final make = firearm['make'] ?? 'Unknown';
            final caliber = firearm['caliber'] ?? 'N/A';

            return DropdownMenuItem<String>(
              value: docId.isNotEmpty ? docId : make,
              child: Text(
                '$make ($caliber)',
                style: TextStyle(color: widget.theme.textColor),
              ),
            );
          }).toList(),
          decoration: _buildInputDecoration('Select a firearm'),
          dropdownColor: widget.theme.cardColor,
          style: TextStyle(color: widget.theme.textColor),
          icon: Icon(Icons.arrow_drop_down, color: widget.theme.accentColor),
        );
      },
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: widget.theme.subtitleColor),
      filled: true,
      fillColor: widget.theme.cardColor,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: widget.theme.accentColor.withValues(alpha: 0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: widget.theme.accentColor.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: widget.theme.accentColor),
      ),
    );
  }
}
