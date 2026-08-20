import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/image_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../../utils/image_helper.dart';
import '../models/farm_config.dart';
import '../services/outfitter_enterprise_manager.dart';

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

  /// Compressed farm photo picked for the Register New Farm form (camera or
  /// gallery). Uploaded to Firebase Storage on submit and persisted on the
  /// `farms/{farmId}` doc as `photoUrl`.
  File? _farmPhotoFile;

  @override
  void dispose() {
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
                                color: theme.subtitleColor),
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
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.broken_image_rounded,
                  color: theme.subtitleColor,
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
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.accentColor.withValues(alpha: 0.35),
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
      appBar: AppBar(
        title: const Text(
          '🏡 Farm Control Panel',
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
                                  color: theme.subtitleColor
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
          const CopyrightFooter(),
        ],
      ),
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
        Icon(icon, size: 14, color: theme.subtitleColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: theme.subtitleColor, fontSize: 11),
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
