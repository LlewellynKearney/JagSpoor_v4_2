import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import '../../core/theme/app_theme.dart';
import '../../repositories/animal_repository.dart';
import '../../models/animal.dart';

class AddTrophyScreen extends StatefulWidget {
  final ThemeController theme;
  final List<Map<String, String>>? firearms;
  final Animal? initialAnimal;
  final String? initialGpsCoordinates;
  final String? initialFirearmId;

  const AddTrophyScreen({
    super.key,
    required this.theme,
    this.firearms,
    this.initialAnimal,
    this.initialGpsCoordinates,
    this.initialFirearmId,
  });

  @override
  State<AddTrophyScreen> createState() => _AddTrophyScreenState();
}

class _AddTrophyScreenState extends State<AddTrophyScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final AnimalRepository _animalRepository = AnimalRepository();

  // Form field controllers
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

  // Species selection state
  Animal? _selectedAnimal;
  final TextEditingController _speciesSearchController =
      TextEditingController();
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _speciesController = TextEditingController();
    _locationController = TextEditingController();
    _antlerSpreadController = TextEditingController();
    _antlerLengthController = TextEditingController();
    _antlerCircumferenceController = TextEditingController();
    _weightController = TextEditingController();
    _tagsController = TextEditingController();

    if (widget.initialAnimal != null) {
      _selectedAnimal = widget.initialAnimal;
      _speciesController.text = widget.initialAnimal!.name;
    }
    if (widget.initialGpsCoordinates != null) {
      _gpsCoordinates = widget.initialGpsCoordinates;
    }
    if (widget.initialFirearmId != null) {
      _selectedFirearmId = widget.initialFirearmId;
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
    _speciesSearchController.dispose();
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
      // Step 1: Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location services are disabled. Please enable them.',
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

      // Step 2: Request permission if not already granted
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // Request permission
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied by user.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() => _isLoadingGps = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission permanently denied. Enable in Settings.',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: Geolocator.openAppSettings,
              ),
            ),
          );
        }
        setState(() => _isLoadingGps = false);
        return;
      }

      // Step 3: Fetch the current position
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        try {
          final Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 30),
          );

          if (mounted) {
            setState(() {
              _gpsCoordinates =
                  '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
              _locationController.text = _gpsCoordinates ?? '';
              _isLoadingGps = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('GPS coordinates logged successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } on LocationServiceDisabledException catch (_) {
          if (mounted) {
            setState(() => _isLoadingGps = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Location services are disabled.'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: 'Enable',
                  onPressed: Geolocator.openLocationSettings,
                ),
              ),
            );
          }
        } on PlatformException catch (e) {
          if (mounted) {
            setState(() => _isLoadingGps = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Platform error: ${e.message}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } on TimeoutException catch (_) {
          if (mounted) {
            setState(() => _isLoadingGps = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'GPS timeout. Ensure you have a clear view of the sky.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isLoadingGps = false);
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
        setState(() => _isLoadingGps = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Photo captured successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Photo selected successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
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

  void _saveTrophy() {
    if (_formKey.currentState?.validate() ?? false) {
      final trophy = {
        'species': _selectedAnimal?.name ?? _speciesController.text,
        'speciesId': _selectedAnimal?.id,
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
        'photos': _selectedPhotos.map((f) => f.path).toList(),
      };

      Navigator.pop(context, trophy);
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
              'ADD TROPHY',
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
                  // Species field - searchable dropdown
                  _buildSectionTitle('SPECIES'),
                  const SizedBox(height: 8),
                  _buildSpeciesDropdown(),
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

                  // Location section with dual input (manual + GPS)
                  _buildSectionTitle('LOCATION / AREA'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _locationController,
                    decoration: _buildInputDecoration(
                      'Enter location manually or use GPS',
                    ),
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
                        _isLoadingGps ? 'Logging GPS...' : 'GPS LOGGING',
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
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.theme.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.theme.accentColor.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Maximum 3 photos added',
                          style: TextStyle(
                            color: widget.theme.accentColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Photos: ${_selectedPhotos.length}/3',
                    style: TextStyle(
                      color: widget.theme.subtitleColor,
                      fontSize: 12,
                    ),
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
                        'SAVE TROPHY',
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

  Future<void> _showSpeciesBottomSheet() async {
    _speciesSearchController.clear();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AnimatedBuilder(
              animation: widget.theme,
              builder: (context, _) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    color: widget.theme.cardColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'SELECT SPECIES',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.theme.textColor,
                                letterSpacing: 1.2,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: widget.theme.textColor),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      // Search bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: TextField(
                          controller: _speciesSearchController,
                          decoration: InputDecoration(
                            hintText: 'Search species (English or Afrikaans)...',
                            hintStyle: TextStyle(color: widget.theme.subtitleColor),
                            prefixIcon: Icon(Icons.search, color: widget.theme.accentColor),
                            suffixIcon: _speciesSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: widget.theme.accentColor),
                                    onPressed: () {
                                      _speciesSearchController.clear();
                                      setModalState(() {});
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: widget.theme.backgroundColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: widget.theme.accentColor),
                            ),
                          ),
                          style: TextStyle(color: widget.theme.textColor),
                          onChanged: (val) {
                            setModalState(() {});
                          },
                        ),
                      ),
                      const Divider(),
                      // List
                      Expanded(
                        child: StreamBuilder<List<Animal>>(
                          stream: _animalRepository.watchAnimals(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Text(
                                  'Error loading species',
                                  style: TextStyle(color: widget.theme.subtitleColor),
                                ),
                              );
                            }
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(widget.theme.accentColor),
                                ),
                              );
                            }

                            final animals = snapshot.data ?? [];
                            final searchString = _speciesSearchController.text.trim().toLowerCase();
                            final filtered = animals.where((animal) {
                              final nameMatch = animal.name.toLowerCase().contains(searchString);
                              final afrikaansMatch = animal.afrikaansName?.toLowerCase().contains(searchString) ?? false;
                              return nameMatch || afrikaansMatch;
                            }).toList();

                            if (filtered.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    'No matching species found',
                                    style: TextStyle(color: widget.theme.subtitleColor),
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              itemCount: filtered.length,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              itemBuilder: (context, index) {
                                final animal = filtered[index];
                                final isSelected = _selectedAnimal?.id == animal.id;
                                return Card(
                                  color: isSelected
                                      ? widget.theme.accentColor.withValues(alpha: 0.15)
                                      : widget.theme.cardColor,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: isSelected
                                          ? widget.theme.accentColor
                                          : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      animal.name,
                                      style: TextStyle(
                                        color: widget.theme.textColor,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: animal.afrikaansName != null
                                        ? Text(
                                            animal.afrikaansName!,
                                            style: TextStyle(
                                              color: widget.theme.subtitleColor,
                                              fontSize: 13,
                                            ),
                                          )
                                        : null,
                                    trailing: isSelected
                                        ? Icon(Icons.check_circle_rounded, color: widget.theme.accentColor)
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _selectedAnimal = animal;
                                        _speciesController.text = animal.name;
                                      });
                                      Navigator.pop(context);
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSpeciesDropdown() {
    return FormField<Animal>(
      initialValue: _selectedAnimal,
      validator: (value) => _selectedAnimal == null ? 'Species is required' : null,
      builder: (FormFieldState<Animal> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                await _showSpeciesBottomSheet();
                state.didChange(_selectedAnimal);
              },
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: _buildInputDecoration('Tap to select species...').copyWith(
                  errorText: state.errorText,
                  suffixIcon: Icon(Icons.arrow_drop_down, color: widget.theme.accentColor),
                ),
                child: Text(
                  _selectedAnimal?.name ?? 'Tap to select species...',
                  style: TextStyle(
                    color: _selectedAnimal != null ? widget.theme.textColor : widget.theme.subtitleColor,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
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

        if (firearms != null && firearms.isNotEmpty && _selectedFirearmId != null && _selectedFirearmDisplay == null) {
          final initialFirearm = firearms.firstWhere(
            (f) => (f['docId'] ?? '') == _selectedFirearmId,
            orElse: () => {},
          );
          if (initialFirearm.isNotEmpty) {
            _selectedFirearmDisplay = '${initialFirearm['make']} (${initialFirearm['caliber']})';
          }
        }

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
          decoration: InputDecoration(
            hintText: 'Select a firearm',
            hintStyle: TextStyle(color: widget.theme.subtitleColor),
            filled: true,
            fillColor: widget.theme.cardColor,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),
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
          ),
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
