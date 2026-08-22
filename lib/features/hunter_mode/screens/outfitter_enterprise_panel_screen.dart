import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';
import '../../../core/services/image_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../../services/external_booking_adapter.dart';
import '../../../utils/image_helper.dart';
import '../models/farm_config.dart';
import '../services/booking_availability_service.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../../outfitter_mode/widgets/outfitter_scaffold.dart';

/// Resolves the display photo URL for a `farms` document: the explicit
/// `photoUrl` first, then the first entry of the `photoUrls` array. Returns
/// an empty string when no photo is present (the caller renders a clean
/// placeholder).
String resolveFarmPhotoUrl(Map<String, dynamic> data) {
  final direct = (data['photoUrl'] as String?)?.trim() ?? '';
  if (direct.isNotEmpty) return direct;
  final list = (data['photoUrls'] as List?)?.whereType<String>() ??
      const <String>[];
  for (final url in list) {
    if (url.trim().isNotEmpty) return url.trim();
  }
  return '';
}

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

  // Create-farm sheet controllers (size / contact / registration / cost rates).
  final _createSizeHectaresController = TextEditingController();
  final _createContactNumberController = TextEditingController();
  final _createRegistrationNumberController = TextEditingController();
  final _createDailyRateHunterController = TextEditingController();
  final _createDailyRateObserverController = TextEditingController();
  final _createAccommodationController = TextEditingController();
  final _createCateringController = TextEditingController();
  final _createVehicleFeeController = TextEditingController();
  final _createGuideFeeController = TextEditingController();

  // Edit-farm sheet controllers (reused across edits; populated on open).
  final _editFarmNameController = TextEditingController();
  final _editDistrictController = TextEditingController();
  final _editProvinceController = TextEditingController();
  final _editSizeHectaresController = TextEditingController();
  final _editContactNumberController = TextEditingController();
  final _editRegistrationNumberController = TextEditingController();

  // Per-farm cost config controllers (Edit Farm sheet).
  final _dailyRateHunterController = TextEditingController();
  final _dailyRateObserverController = TextEditingController();
  final _accommodationController = TextEditingController();
  final _cateringController = TextEditingController();
  final _vehicleFeeController = TextEditingController();
  final _guideFeeController = TextEditingController();

  String? _selectedFarmId;
  bool _isAddingFarm = false;
  bool _isAssigningManager = false;
  bool _isUpdatingFarm = false;

  // Booking & ERP Sync settings (external availability integration).
  final _bookingSyncUrlController = TextEditingController();
  ExternalBookingSystemType _bookingSyncType = ExternalBookingSystemType.manual;
  bool _isSavingBookingSync = false;
  bool _isTestingBookingSync = false;
  String? _bookingSyncTestResult;
  bool _bookingSyncTestOk = false;

  /// The outfitter-managed unavailable dates for MANUAL sync mode. Toggle
  /// via the date picker below; persisted under
  /// `users/{uid}.bookingSync.manualBlockedDates`.
  Set<DateTime> _manualBlockedDates = {};

  /// Compressed farm photo picked for the Register New Farm form (camera or
  /// gallery). Uploaded to Firebase Storage on submit and persisted on the
  /// `farms/{farmId}` doc as `photoUrl`.
  File? _farmPhotoFile;

  @override
  void initState() {
    super.initState();
    _loadBookingSyncConfig();
  }

  @override
  void dispose() {
    _bookingSyncUrlController.dispose();
    _farmNameController.dispose();
    _districtController.dispose();
    _provinceController.dispose();
    _managerEmailController.dispose();
    _managerNameController.dispose();
    _managerCellController.dispose();
    _createSizeHectaresController.dispose();
    _createContactNumberController.dispose();
    _createRegistrationNumberController.dispose();
    _createDailyRateHunterController.dispose();
    _createDailyRateObserverController.dispose();
    _createAccommodationController.dispose();
    _createCateringController.dispose();
    _createVehicleFeeController.dispose();
    _createGuideFeeController.dispose();
    _editFarmNameController.dispose();
    _editDistrictController.dispose();
    _editProvinceController.dispose();
    _editSizeHectaresController.dispose();
    _editContactNumberController.dispose();
    _editRegistrationNumberController.dispose();
    _dailyRateHunterController.dispose();
    _dailyRateObserverController.dispose();
    _accommodationController.dispose();
    _cateringController.dispose();
    _vehicleFeeController.dispose();
    _guideFeeController.dispose();
    super.dispose();
  }

  /// Loads the outfitter's persisted Booking & ERP Sync configuration so the
  /// card reflects the saved system type + feed URL on open.
  Future<void> _loadBookingSyncConfig() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final config =
          await BookingAvailabilityService.instance.loadConfig(uid);
      if (!mounted) return;
      setState(() {
        _bookingSyncType = config.systemType;
        _bookingSyncUrlController.text = config.feedUrl;
        _manualBlockedDates = {...config.manualBlockedDates};
      });
    } catch (_) {
      // Non-fatal — the card simply starts from the Manual default.
    }
  }

  ExternalBookingConfig _currentBookingSyncConfig() {
    return ExternalBookingConfig(
      systemType: _bookingSyncType,
      feedUrl: _bookingSyncUrlController.text.trim(),
      manualBlockedDates: {..._manualBlockedDates},
    );
  }

  /// Opens a date picker to mark a day as UNAVAILABLE for hunters (Manual
  /// sync mode). Dates already blocked are ignored on re-pick.
  Future<void> _addManualBlockedDate() async {
    final now = normalizeBookingDate(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'MARK DATE UNAVAILABLE',
    );
    if (picked == null) return;
    setState(() {
      _manualBlockedDates.add(normalizeBookingDate(picked));
    });
  }

  /// Removes a date from the manually-blocked list (Manual sync mode).
  void _removeManualBlockedDate(DateTime day) {
    setState(() {
      _manualBlockedDates.remove(normalizeBookingDate(day));
    });
  }

  /// The manual blocked-dates editor rendered when the outfitter manages
  /// availability by hand (Manual sync mode).
  Widget _buildManualAvailabilityEditor(ThemeController theme) {
    final sorted = _manualBlockedDates.toList()
      ..sort((a, b) => a.compareTo(b));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MANUALLY MANAGED DATES',
          style: TextStyle(
            color: OutfitterUi.subtitleColor(theme),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Mark the dates hunters CANNOT book. Every date not listed stays '
          'available for hunter selection.',
          style: TextStyle(
            color: OutfitterUi.subtitleColor(theme),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        if (sorted.isEmpty)
          Text(
            'No blocked dates — every date is currently bookable.',
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: sorted
                .map(
                  (day) => InputChip(
                    avatar: const Icon(Icons.event_busy_rounded, size: 14),
                    label: Text(
                      DateFormat('d MMM yyyy').format(day),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onDeleted: () => _removeManualBlockedDate(day),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _addManualBlockedDate,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.accentColor,
            side: BorderSide(color: theme.accentColor),
          ),
          icon: const Icon(Icons.event_busy_rounded, size: 18),
          label: const Text(
            'MARK A DATE UNAVAILABLE',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  /// Tests live connectivity to the configured external system (or the mock
  /// simulator) and surfaces the result inline in the card.
  Future<void> _testBookingSyncConnection() async {
    final config = _currentBookingSyncConfig();
    if (config.systemType == ExternalBookingSystemType.manual) {
      setState(() {
        _bookingSyncTestOk = true;
        _bookingSyncTestResult =
            'Manual mode — hunters can select every date you have NOT marked '
            'unavailable (${_manualBlockedDates.length} date(s) currently '
            'blocked). No external connection to test.';
      });
      return;
    }
    if (config.systemType == ExternalBookingSystemType.ical &&
        config.feedUrl.isEmpty) {
      setState(() {
        _bookingSyncTestOk = false;
        _bookingSyncTestResult = 'Enter the iCal feed URL before testing.';
      });
      return;
    }
    setState(() {
      _isTestingBookingSync = true;
      _bookingSyncTestResult = null;
    });
    try {
      final adapter = ExternalBookingAdapters.fromConfig(config);
      final ok = await adapter?.testConnection() ?? false;
      if (!mounted) return;
      setState(() {
        _bookingSyncTestOk = ok;
        _bookingSyncTestResult = ok
            ? (config.systemType == ExternalBookingSystemType.mock
                ? 'Mock test adapter online — deterministic simulated '
                    'availability active. No live API contacted.'
                : 'Connection successful — the iCal feed is reachable and '
                    'returned a valid calendar.')
            : 'Connection failed — the endpoint is unreachable or did not '
                'return a valid iCalendar feed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingSyncTestOk = false;
        _bookingSyncTestResult = 'Connection failed: $e';
      });
    } finally {
      if (mounted) setState(() => _isTestingBookingSync = false);
    }
  }

  /// Saves the Booking & ERP Sync configuration to the outfitter's profile.
  Future<void> _saveBookingSyncConfig() async {
    final config = _currentBookingSyncConfig();
    if (config.systemType == ExternalBookingSystemType.ical &&
        config.feedUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the iCal feed URL before saving.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSavingBookingSync = true);
    try {
      await BookingAvailabilityService.instance.saveConfig(config);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Booking & ERP sync settings saved.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to save booking sync settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingBookingSync = false);
    }
  }

  /// Lets the outfitter capture a farm photo with the camera or select one
  /// from the gallery. The picked image is compressed via [ImageService] and
  /// held in [_farmPhotoFile] until the farm is submitted.
  Future<void> _pickFarmPhoto(ImageSource source) async {
    try {
      final File? compressed = await ImageService.pickAndCompressImage(
        source: source,
        quality: 80,
        minWidth: 1280,
        minHeight: 1280,
      );
      if (compressed == null) return;
      setState(() => _farmPhotoFile = compressed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Could not pick photo: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _removeFarmPhoto() {
    setState(() => _farmPhotoFile = null);
  }

  /// Uploads the picked farm photo to Firebase Storage and returns the
  /// download URL, or `null` when no photo was picked. Upload failures are
  /// non-fatal — the farm is still registered without a photo.
  Future<String?> _uploadFarmPhoto() async {
    final file = _farmPhotoFile;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (file == null || uid == null) return null;
    try {
      final path =
          'farm_photos/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      return await ImageService.uploadCompressedPhoto(
        imageFile: file,
        storagePath: path,
      );
    } catch (e) {
      debugPrint('Farm photo upload failed: $e');
      return null;
    }
  }

  Future<void> _addFarm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isAddingFarm = true;
    });

    double? sizeHectares;
    final sizeText = _createSizeHectaresController.text.trim();
    if (sizeText.isNotEmpty) {
      sizeHectares = double.tryParse(sizeText);
      if (sizeHectares == null) {
        setState(() => _isAddingFarm = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Size must be a valid number'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    // Parse cost-config fields (blank -> null = not configured).
    final hasAnyCostRate = [
      _createDailyRateHunterController,
      _createDailyRateObserverController,
      _createAccommodationController,
      _createCateringController,
      _createVehicleFeeController,
      _createGuideFeeController,
    ].any((c) => c.text.trim().isNotEmpty);
    final costConfig = hasAnyCostRate
        ? FarmCostConfig(
            dailyRateHunter:
                _parseOptDouble(_createDailyRateHunterController.text),
            dailyRateObserver:
                _parseOptDouble(_createDailyRateObserverController.text),
            accommodationPerNight:
                _parseOptDouble(_createAccommodationController.text),
            cateringPerDay: _parseOptDouble(_createCateringController.text),
            vehicleFee: _parseOptDouble(_createVehicleFeeController.text),
            guideFee: _parseOptDouble(_createGuideFeeController.text),
          )
        : null;

    try {
      final photoUrl = await _uploadFarmPhoto();
      await OutfitterEnterpriseManager.instance.addFarm(
        name: _farmNameController.text.trim(),
        district: _districtController.text.trim(),
        province: _provinceController.text.trim(),
        sizeHectares: sizeHectares,
        contactNumber: _createContactNumberController.text.trim().isEmpty
            ? null
            : _createContactNumberController.text.trim(),
        registrationNumber:
            _createRegistrationNumberController.text.trim().isEmpty
                ? null
                : _createRegistrationNumberController.text.trim(),
        costConfig: costConfig,
        photoUrl: photoUrl,
      );

      if (mounted) {
        setState(() => _farmPhotoFile = null);
        _farmNameController.clear();
        _districtController.clear();
        _provinceController.clear();
        _createSizeHectaresController.clear();
        _createContactNumberController.clear();
        _createRegistrationNumberController.clear();
        _createDailyRateHunterController.clear();
        _createDailyRateObserverController.clear();
        _createAccommodationController.clear();
        _createCateringController.clear();
        _createVehicleFeeController.clear();
        _createGuideFeeController.clear();
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

  /// Opens a modal sheet pre-filled with the farm's current details so the
  /// outfitter can edit name, district, province, size, contact, and
  /// registration number. Saving calls [OutfitterEnterpriseManager.updateFarm];
  /// the Registered Farms `StreamBuilder` re-renders automatically on success
  /// (Firestore snapshots).
  void _showEditFarmSheet(Map<String, dynamic> data, String farmId) {
    final theme = widget.theme;
    _editFarmNameController.text = (data['name'] ?? '').toString();
    _editDistrictController.text = (data['district'] ?? '').toString();
    _editProvinceController.text = (data['province'] ?? '').toString();
    final size = data['sizeHectares'];
    _editSizeHectaresController.text =
        (size == null) ? '' : size.toString();
    _editContactNumberController.text =
        (data['contactNumber'] ?? '').toString();
    _editRegistrationNumberController.text =
        (data['registrationNumber'] ?? '').toString();

    // Per-farm cost config.
    final costConfig =
        FarmCostConfig.fromMap((data['costConfig'] as Map?)?.cast());
    _dailyRateHunterController.text = costConfig.dailyRateHunter == null
        ? ''
        : costConfig.dailyRateHunter!.toStringAsFixed(0);
    _dailyRateObserverController.text = costConfig.dailyRateObserver == null
        ? ''
        : costConfig.dailyRateObserver!.toStringAsFixed(0);
    _accommodationController.text = costConfig.accommodationPerNight == null
        ? ''
        : costConfig.accommodationPerNight!.toStringAsFixed(0);
    _cateringController.text = costConfig.cateringPerDay == null
        ? ''
        : costConfig.cateringPerDay!.toStringAsFixed(0);
    _vehicleFeeController.text = costConfig.vehicleFee == null
        ? ''
        : costConfig.vehicleFee!.toStringAsFixed(0);
    _guideFeeController.text = costConfig.guideFee == null
        ? ''
        : costConfig.guideFee!.toStringAsFixed(0);

    final editFormKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Form(
                key: editFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_location_alt_rounded,
                              color: theme.accentColor, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'EDIT FARM DETAILS',
                              style: TextStyle(
                                color: theme.textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                color: OutfitterUi.subtitleColor(theme)),
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _editFarmNameController,
                        style: TextStyle(color: theme.textColor),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'Farm name',
                          label: 'Farm Name *',
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
                      TextFormField(
                        controller: _editDistrictController,
                        style: TextStyle(color: theme.textColor),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'District / region',
                          label: 'District',
                          theme: theme,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _editProvinceController,
                        style: TextStyle(color: theme.textColor),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'Province',
                          label: 'Province',
                          theme: theme,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _editSizeHectaresController,
                        style: TextStyle(color: theme.textColor),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'e.g. 2500',
                          label: 'Size (hectares)',
                          theme: theme,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _editContactNumberController,
                        style: TextStyle(color: theme.textColor),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: '+27 ...',
                          label: 'Contact Number',
                          theme: theme,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _editRegistrationNumberController,
                        style: TextStyle(color: theme.textColor),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'Farm / concession registration no.',
                          label: 'Registration Number',
                          theme: theme,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionHeader(theme, 'COST RATES (PACKAGE BUILDER)',
                          Icons.payments_outlined),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dailyRateHunterController,
                              style: TextStyle(color: theme.textColor),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _inputDecoration(
                                hint: '0',
                                label: 'Daily Rate / Hunter (R)',
                                theme: theme,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _dailyRateObserverController,
                              style: TextStyle(color: theme.textColor),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _inputDecoration(
                                hint: '0',
                                label: 'Daily Rate / Observer (R)',
                                theme: theme,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _accommodationController,
                              style: TextStyle(color: theme.textColor),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _inputDecoration(
                                hint: '0',
                                label: 'Accommodation / Night (R)',
                                theme: theme,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _cateringController,
                              style: TextStyle(color: theme.textColor),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _inputDecoration(
                                hint: '0',
                                label: 'Catering / Day (R)',
                                theme: theme,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _vehicleFeeController,
                              style: TextStyle(color: theme.textColor),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _inputDecoration(
                                hint: '0',
                                label: 'Vehicle Fee (R)',
                                theme: theme,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _guideFeeController,
                              style: TextStyle(color: theme.textColor),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _inputDecoration(
                                hint: '0',
                                label: 'Guide Fee (R)',
                                theme: theme,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // SAVE CHANGES — wrapped in a bottom SafeArea so the
                      // button clears the Android 3-button / iOS gesture nav
                      // bar on every device, with adequate padding + a
                      // high-contrast white-on-accent label (bold).
                      SafeArea(
                        top: false,
                        bottom: true,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton.icon(
                            onPressed: _isUpdatingFarm
                                ? null
                                : () => _submitFarmEdit(
                                      farmId,
                                      editFormKey,
                                      setSheetState,
                                    ),
                            icon: _isUpdatingFarm
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(
                              _isUpdatingFarm ? 'SAVING…' : 'SAVE CHANGES',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.5,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.accentColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  theme.accentColor.withValues(alpha: 0.5),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitFarmEdit(
    String farmId,
    GlobalKey<FormState> formKey,
    void Function(void Function()) setSheetState,
  ) async {
    if (!formKey.currentState!.validate()) return;

    setSheetState(() => _isUpdatingFarm = true);

    double? sizeHectares;
    final sizeText = _editSizeHectaresController.text.trim();
    if (sizeText.isNotEmpty) {
      sizeHectares = double.tryParse(sizeText);
      if (sizeHectares == null) {
        setSheetState(() => _isUpdatingFarm = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Size must be a valid number'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    // Parse cost-config fields (blank -> null = not configured).
    final costConfig = FarmCostConfig(
      dailyRateHunter: _parseOptDouble(_dailyRateHunterController.text),
      dailyRateObserver: _parseOptDouble(_dailyRateObserverController.text),
      accommodationPerNight: _parseOptDouble(_accommodationController.text),
      cateringPerDay: _parseOptDouble(_cateringController.text),
      vehicleFee: _parseOptDouble(_vehicleFeeController.text),
      guideFee: _parseOptDouble(_guideFeeController.text),
    );

    try {
      await OutfitterEnterpriseManager.instance.updateFarm(
        farmId: farmId,
        name: _editFarmNameController.text,
        district: _editDistrictController.text,
        province: _editProvinceController.text,
        sizeHectares: sizeHectares,
        contactNumber: _editContactNumberController.text.trim().isEmpty
            ? null
            : _editContactNumberController.text.trim(),
        registrationNumber:
            _editRegistrationNumberController.text.trim().isEmpty
                ? null
                : _editRegistrationNumberController.text.trim(),
      );

      // Persist per-farm cost config (best-effort, non-fatal).
      try {
        await OutfitterEnterpriseManager.instance
            .updateFarmCosts(farmId: farmId, costConfig: costConfig);
      } catch (_) {
        // Cost-config write is non-fatal; the farm details already saved.
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Farm updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ Failed to update: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setSheetState(() => _isUpdatingFarm = false);
      }
    }
  }

  /// Parses a trimmed text field into a nullable double (blank -> null).
  /// Returns `null` for a non-numeric value (the caller treats null as
  /// "not configured"); the validation is intentionally lenient for optional
  /// cost fields.
  static double? _parseOptDouble(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Widget _sectionHeader(
      ThemeController theme, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: theme.accentColor, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  /// Photo picker for the Register New Farm form: a preview of the picked
  /// farm photo (with a remove button) or two entry tiles to take a photo
  /// with the camera / select one from the gallery.
  Widget _buildFarmPhotoPicker(ThemeController theme) {
    final photo = _farmPhotoFile;
    if (photo != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              photo,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: OutfitterUi.cardColor(theme),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: OutfitterUi.cardBorderColor(theme),
                  ),
                ),
                child: Icon(
                  Icons.broken_image_rounded,
                  color: OutfitterUi.subtitleColor(theme),
                  size: 40,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _removeFarmPhoto,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _farmPhotoTile(
            theme,
            icon: Icons.photo_camera_rounded,
            label: 'Take Photo',
            onTap: () => _pickFarmPhoto(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _farmPhotoTile(
            theme,
            icon: Icons.photo_library_rounded,
            label: 'From Gallery',
            onTap: () => _pickFarmPhoto(ImageSource.gallery),
          ),
        ),
      ],
    );
  }

  /// Thumbnail for a Registered Farms card: the farm's uploaded photo via
  /// the resilient [AdaptiveImage] pipeline, or a clean placeholder icon
  /// when the farm has no photo.
  Widget _farmThumbnail(Map<String, dynamic> data, ThemeController theme) {
    final url = resolveFarmPhotoUrl(data);
    if (url.isEmpty) {
      return Container(
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.landscape_rounded,
          color: theme.accentColor,
          size: 24,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AdaptiveImage(
          imagePath: url,
          fit: BoxFit.cover,
          width: 52,
          height: 52,
          errorWidget: Container(
            width: 52,
            height: 52,
            color: theme.accentColor.withValues(alpha: 0.2),
            child: Icon(
              Icons.landscape_rounded,
              color: theme.accentColor,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _farmPhotoTile(
    ThemeController theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: OutfitterUi.cardColor(theme),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: OutfitterUi.cardBorderColor(theme),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: theme.accentColor, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          '🏡 Farm Control Panel',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: OutfitterUi.titleColor(theme),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: OutfitterUi.titleColor(theme),
        elevation: 0,
        actions: [
          OutfitterActionChip(
            icon: Icons.info_outline_rounded,
            tooltip: 'Screen info',
            iconColor: theme.accentColor,
            onPressed: () => showAppInfoModal(
              context,
              AppScreenHelpScripts.outfitterFarmControlPanel,
            ),
          ),
        ],
      ),
      body: OutfitterBushveldBackground.stack(
        fallbackColor: theme.backgroundColor,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + kToolbarHeight + 16,
              16,
              SafeBottomInset.of(context)),
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _createSizeHectaresController,
                    style: TextStyle(color: theme.textColor),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      hint: 'e.g. 2500',
                      label: 'Size (hectares)',
                      theme: theme,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _createContactNumberController,
                    style: TextStyle(color: theme.textColor),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      hint: '+27 ...',
                      label: 'Contact Number',
                      theme: theme,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _createRegistrationNumberController,
                    style: TextStyle(color: theme.textColor),
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      hint: 'Farm / concession registration no.',
                      label: 'Registration Number',
                      theme: theme,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionHeader(theme, 'FARM PHOTO (OPTIONAL)',
                      Icons.photo_camera_rounded),
                  const SizedBox(height: 12),
                  _buildFarmPhotoPicker(theme),
                  const SizedBox(height: 24),
                  _sectionHeader(theme, 'COST RATES (PACKAGE BUILDER)',
                      Icons.payments_outlined),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _createDailyRateHunterController,
                          style: TextStyle(color: theme.textColor),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration(
                            hint: '0',
                            label: 'Daily Rate / Hunter (R)',
                            theme: theme,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _createDailyRateObserverController,
                          style: TextStyle(color: theme.textColor),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration(
                            hint: '0',
                            label: 'Daily Rate / Observer (R)',
                            theme: theme,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _createAccommodationController,
                          style: TextStyle(color: theme.textColor),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration(
                            hint: '0',
                            label: 'Accommodation / Night (R)',
                            theme: theme,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _createCateringController,
                          style: TextStyle(color: theme.textColor),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration(
                            hint: '0',
                            label: 'Catering / Day (R)',
                            theme: theme,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _createVehicleFeeController,
                          style: TextStyle(color: theme.textColor),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration(
                            hint: '0',
                            label: 'Vehicle Fee (R)',
                            theme: theme,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _createGuideFeeController,
                          style: TextStyle(color: theme.textColor),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDecoration(
                            hint: '0',
                            label: 'Guide Fee (R)',
                            theme: theme,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
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
                            style: TextStyle(color: OutfitterUi.subtitleColor(theme)),
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
                            style: TextStyle(color: OutfitterUi.subtitleColor(theme)),
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
                        final sizeHectares = data['sizeHectares'];
                        final contactNumber = data['contactNumber'];
                        final registrationNumber =
                            data['registrationNumber'];

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showEditFarmSheet(data, doc.id),
                            child: Container(
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _farmThumbnail(data, theme),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            color: OutfitterUi.subtitleColor(theme),
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
                                              ? Colors.green.withValues(
                                                  alpha: 0.2)
                                              : Colors.red.withValues(
                                                  alpha: 0.2),
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
                              // Extended details (size / contact / reg no.) —
                              // only the fields that are set on the document.
                              if (sizeHectares != null ||
                                  (contactNumber is String &&
                                      contactNumber.isNotEmpty) ||
                                  (registrationNumber is String &&
                                      registrationNumber.isNotEmpty)) ...[
                                const SizedBox(height: 8),
                                Divider(
                                  height: 1,
                                  color: OutfitterUi.subtitleColor(theme)
                                      .withValues(alpha: 0.15),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 4,
                                  children: [
                                    if (sizeHectares != null)
                                      _farmDetailChip(
                                        icon: Icons.crop_square_rounded,
                                        label: '$sizeHectares ha',
                                        theme: theme,
                                      ),
                                    if (contactNumber is String &&
                                        contactNumber.isNotEmpty)
                                      _farmDetailChip(
                                        icon: Icons.phone_rounded,
                                        label: contactNumber,
                                        theme: theme,
                                      ),
                                    if (registrationNumber is String &&
                                        registrationNumber.isNotEmpty)
                                      _farmDetailChip(
                                        icon: Icons.badge_outlined,
                                        label: registrationNumber,
                                        theme: theme,
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              // Tap the card or the EDIT button to open the
                              // edit sheet. The whole card is tappable.
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _showEditFarmSheet(data, doc.id),
                                  icon: Icon(Icons.edit_rounded,
                                      size: 18, color: theme.accentColor),
                                  label: Text(
                                    'EDIT',
                                    style: TextStyle(
                                      color: theme.accentColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                            ),
                          ),
                        );
                      }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // External Booking / ERP availability integration.
          _buildSectionCard(
            title: '🗓️ Booking & ERP Sync',
            icon: Icons.sync_rounded,
            theme: theme,
            child: _buildBookingSyncCard(theme),
          ),
          const SizedBox(height: 16),
          const CopyrightFooter(),
        ],
        ),
      ),
    );
  }

  /// The "Booking & ERP Sync" settings card: lets the outfitter pick their
  /// external availability system (Manual / iCal URL / Mock Test), input the
  /// endpoint / feed URL, test live connectivity, and save the config.
  Widget _buildBookingSyncCard(ThemeController theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect your external booking / ERP calendar so hunters see '
          'real-time date availability when booking your packages.',
          style: TextStyle(
            color: OutfitterUi.subtitleColor(theme),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ExternalBookingSystemType>(
          value: _bookingSyncType,
          decoration: _inputDecoration(
            hint: 'Select system type',
            label: 'Availability System',
            theme: theme,
          ),
          dropdownColor: theme.cardColor,
          style: TextStyle(color: theme.textColor),
          items: ExternalBookingSystemType.values
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t.label),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _bookingSyncType = value;
              _bookingSyncTestResult = null;
            });
          },
        ),
        const SizedBox(height: 12),
        if (_bookingSyncType == ExternalBookingSystemType.manual) ...[
          // Manual mode: the outfitter hand-manages unavailable dates;
          // hunters pick from every non-blocked date.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OutfitterUi.cardColor(theme),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: OutfitterUi.cardBorderColor(theme),
              ),
            ),
            child: _buildManualAvailabilityEditor(theme),
          ),
          const SizedBox(height: 12),
        ],
        if (_bookingSyncType != ExternalBookingSystemType.manual) ...[
          TextFormField(
            controller: _bookingSyncUrlController,
            style: TextStyle(color: theme.textColor),
            keyboardType: TextInputType.url,
            decoration: _inputDecoration(
              hint: _bookingSyncType == ExternalBookingSystemType.ical
                  ? 'https://example.com/calendar.ics'
                  : 'Optional seed key (blank = default mock calendar)',
              label: _bookingSyncType == ExternalBookingSystemType.ical
                  ? 'iCal Feed URL'
                  : 'Mock Seed Key',
              theme: theme,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_bookingSyncTestResult != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_bookingSyncTestOk ? Colors.green : Colors.red)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (_bookingSyncTestOk ? Colors.green : Colors.red)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _bookingSyncTestOk
                      ? Icons.check_circle_outline
                      : Icons.error_outline_rounded,
                  color: _bookingSyncTestOk ? Colors.green : Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _bookingSyncTestResult!,
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTestingBookingSync
                    ? null
                    : _testBookingSyncConnection,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.accentColor,
                  side: BorderSide(color: theme.accentColor),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: _isTestingBookingSync
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: const Text(
                  'TEST CONNECTION',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isSavingBookingSync ? null : _saveBookingSyncConfig,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: _isSavingBookingSync
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text(
                  'SAVE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _farmDetailChip({
    required IconData icon,
    required String label,
    required ThemeController theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: OutfitterUi.subtitleColor(theme)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: OutfitterUi.subtitleColor(theme), fontSize: 11),
        ),
      ],
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
        color: OutfitterUi.cardColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OutfitterUi.cardBorderColor(theme)),
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
                    color: OutfitterUi.titleColor(theme),
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
      hintStyle: TextStyle(color: OutfitterUi.subtitleColor(theme)),
      labelStyle: TextStyle(color: theme.accentColor),
      filled: true,
      fillColor: OutfitterUi.cardColor(theme),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: OutfitterUi.cardBorderColor(theme)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: OutfitterUi.cardBorderColor(theme)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.accentColor, width: 2),
      ),
    );
  }
}
