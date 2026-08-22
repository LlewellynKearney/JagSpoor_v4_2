import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/image_service.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../../utils/image_helper.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../services/trophy_inventory_report_exporter.dart';
import '../services/user_role_resolver.dart';
import '../../outfitter_mode/widgets/outfitter_scaffold.dart';

/// Resolves the display photo URL for a trophy-stock document: the first
/// entry of `trophyPhotoUrls` first, then the explicit `photoUrl` fallback.
/// Returns an empty string when no photo is present (the caller renders a
/// clean placeholder).
String resolveTrophyStockPhotoUrl(Map<String, dynamic> data) {
  final list = (data['trophyPhotoUrls'] as List?)?.whereType<String>() ??
      const <String>[];
  for (final url in list) {
    if (url.trim().isNotEmpty) return url.trim();
  }
  final direct = (data['photoUrl'] as String?)?.trim() ?? '';
  if (direct.isNotEmpty) return direct;
  return '';
}

class OutfitterTrophyStockScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterTrophyStockScreen({super.key, required this.theme});

  @override
  State<OutfitterTrophyStockScreen> createState() =>
      _OutfitterTrophyStockScreenState();
}

class _OutfitterTrophyStockScreenState
    extends State<OutfitterTrophyStockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _speciesController = TextEditingController();
  final _countController = TextEditingController();
  final _priceController = TextEditingController();
  final _measurementController = TextEditingController();

  // Edit-sheet controllers (populated on open; reused across edits).
  final _editSpeciesController = TextEditingController();
  final _editCountController = TextEditingController();
  final _editPriceController = TextEditingController();
  final _editMeasurementController = TextEditingController();

  String? _selectedFarmId;
  String? _selectedFarmName;
  bool _isSyncing = false;
  bool _isManager = false;

  // Multi-photo trophy attachments (up to 3).
  static const int _maxTrophyPhotos = 3;
  final List<XFile> _pickedPhotos = [];
  final ImagePicker _imagePicker = ImagePicker();

  // Common species suggestions
  static const List<String> _commonSpecies = [
    'African Lion',
    'Cape Buffalo',
    'African Elephant',
    'White Rhino',
    'Black Rhino',
    'Kudu',
    'Gemsbok',
    'Blue Wildebeest',
    'Zebra',
    'Impala',
    'Springbok',
    'Warthog',
    'Bushpig',
    'Sable Antelope',
    'Roan Antelope',
    'Tsessebe',
    'Red Hartebeest',
    'Waterbuck',
    'Eland',
    'Hippo',
  ];

  @override
  void initState() {
    super.initState();
    _isManager = UserRoleResolver.instance.isManager;
    if (_isManager && UserRoleResolver.instance.assignedFarmId != null) {
      _selectedFarmId = UserRoleResolver.instance.assignedFarmId;
      _loadFarmName();
    }
  }

  Future<void> _loadFarmName() async {
    if (_selectedFarmId == null) return;
    final farmDoc =
        await FirebaseFirestore.instance
            .collection('farms')
            .doc(_selectedFarmId)
            .get();
    if (farmDoc.exists && mounted) {
      setState(() {
        _selectedFarmName = farmDoc.data()?['name'] ?? 'Unknown Farm';
      });
    }
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _countController.dispose();
    _priceController.dispose();
    _measurementController.dispose();
    _editSpeciesController.dispose();
    _editCountController.dispose();
    _editPriceController.dispose();
    _editMeasurementController.dispose();
    super.dispose();
  }

  Future<void> _exportReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating trophy inventory report…')),
    );
    try {
      await TrophyInventoryReportExporter().generateAndShare();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trophy inventory report exported and shared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Opens a modal sheet pre-filled with a trophy stock entry's current
  /// values so the outfitter can edit the species, available count, price per
  /// trophy, and measurement. Saving calls [OutfitterEnterpriseManager
  /// .updateTrophyStock]; the "Current Stock by Farm" `StreamBuilder`
  /// re-renders automatically (Firestore snapshots). A destructive DELETE
  /// action is also offered (with confirmation).
  void _showEditTrophySheet({
    required String trophyId,
    required Map<String, dynamic> data,
  }) {
    final theme = widget.theme;
    _editSpeciesController.text = (data['species'] ?? '').toString();
    _editCountController.text = (data['availableCount'] ?? 0).toString();
    _editPriceController.text = (data['pricePerTrophyRands'] ?? 0).toString();
    final measurement = data['trophyMeasurement'] ?? data['trophyLengthInches'];
    _editMeasurementController.text =
        (measurement == null) ? '' : measurement.toString();

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
                          Icon(Icons.edit_note_rounded,
                              color: theme.accentColor, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'EDIT TROPHY STOCK',
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
                        controller: _editSpeciesController,
                        style: TextStyle(color: theme.textColor),
                        textInputAction: TextInputAction.next,
                        decoration: _editInputDecoration(
                          'Species *', 'e.g. Kudu', theme),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter species';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _editCountController,
                        style: TextStyle(color: theme.textColor),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: _editInputDecoration(
                          'Available Count *', 'e.g. 5', theme),
                        validator: (value) {
                          final n = int.tryParse(value ?? '');
                          if (n == null || n < 0) {
                            return 'Enter a valid count (>= 0)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _editPriceController,
                        style: TextStyle(color: theme.textColor),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: _editInputDecoration(
                          'Price per Trophy (R) *', 'e.g. 12000', theme),
                        validator: (value) {
                          final n = double.tryParse(value ?? '');
                          if (n == null || n < 0) {
                            return 'Enter a valid price (>= 0)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _editMeasurementController,
                        style: TextStyle(color: theme.textColor),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        decoration: _editInputDecoration(
                          'Measurement (inches)', 'optional', theme),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _submitTrophyEdit(
                          trophyId,
                          editFormKey,
                          setSheetState,
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('SAVE CHANGES'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () =>
                            _confirmDeleteTrophy(trophyId, sheetContext),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.red),
                        label: const Text('DELETE ENTRY',
                            style: TextStyle(color: Colors.red)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
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

  InputDecoration _editInputDecoration(String label, String hint, theme) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: theme.accentColor),
      hintStyle: TextStyle(color: OutfitterUi.subtitleColor(theme)),
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

  Future<void> _submitTrophyEdit(
    String trophyId,
    GlobalKey<FormState> formKey,
    void Function(void Function()) setSheetState,
  ) async {
    if (!formKey.currentState!.validate()) return;

    setSheetState(() {});
    try {
      final count = int.parse(_editCountController.text.trim());
      final price = double.parse(_editPriceController.text.trim());
      final measurementText = _editMeasurementController.text.trim();
      final measurement = measurementText.isEmpty
          ? null
          : double.tryParse(measurementText);
      final clearMeasurement =
          measurementText.isEmpty && measurement == null;

      await OutfitterEnterpriseManager.instance.updateTrophyStock(
        trophyId: trophyId,
        species: _editSpeciesController.text.trim(),
        availableCount: count,
        pricePerTrophyRands: price,
        trophyMeasurement: measurement,
        clearMeasurement: clearMeasurement,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Trophy stock updated'),
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
    }
  }

  void _confirmDeleteTrophy(
      String trophyId, BuildContext sheetContext) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text('Delete trophy entry?',
            style: TextStyle(color: widget.theme.textColor)),
        content: Text(
            'This permanently removes the trophy stock entry. This cannot be undone.',
            style: TextStyle(color: OutfitterUi.subtitleColor(widget.theme))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _deleteTrophy(trophyId, sheetContext);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTrophy(
      String trophyId, BuildContext sheetContext) async {
    try {
      await OutfitterEnterpriseManager.instance.deleteTrophyStock(trophyId);
      if (mounted && sheetContext.mounted) {
        // Close both the confirm dialog (already closed) and the edit sheet.
        Navigator.of(sheetContext).pop();
        if (!mounted || !context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Trophy entry deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ Failed to delete: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _syncTrophyStock() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFarmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select a farm first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final count =
          int.tryParse(_countController.text.replaceAll(',', '')) ?? 0;
      final price =
          double.tryParse(
            _priceController.text.replaceAll(',', '').replaceAll('R', ''),
          ) ??
          0;
      // Trophy length/size in inches (horn, tusk, or skull). Optional.
      final measurement =
          double.tryParse(
            _measurementController.text.replaceAll(',', '').trim(),
          );

      // Upload any picked photos to Firebase Storage (up to 3).
      final photoUrls = await _uploadTrophyPhotos();

      await OutfitterEnterpriseManager.instance.syncTrophyStock(
        farmId: _selectedFarmId!,
        species: _speciesController.text.trim(),
        availableCount: count,
        pricePerTrophyRands: price,
        trophyMeasurement: measurement,
        trophyPhotoUrls: photoUrls,
      );

      if (mounted) {
        _speciesController.clear();
        _countController.clear();
        _priceController.clear();
        _measurementController.clear();
        setState(_pickedPhotos.clear);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Trophy stock synced for ${_selectedFarmName ?? "farm"}!',
            ),
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
          _isSyncing = false;
        });
      }
    }
  }

  /// Opens the image picker (gallery, multi-image) and appends up to
  /// [_maxTrophyPhotos] selections to [_pickedPhotos].
  Future<void> _pickTrophyPhotos() async {
    if (_pickedPhotos.length >= _maxTrophyPhotos) return;
    try {
      final remaining = _maxTrophyPhotos - _pickedPhotos.length;
      final picked = await _imagePicker.pickMultipleMedia(
        imageQuality: 80,
        limit: remaining,
      );
      if (picked.isNotEmpty && mounted) {
        setState(() {
          // Cap at the overall limit even if the platform returned extra.
          _pickedPhotos.addAll(picked);
          if (_pickedPhotos.length > _maxTrophyPhotos) {
            _pickedPhotos.removeRange(_maxTrophyPhotos, _pickedPhotos.length);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Image pick failed: $e')),
        );
      }
    }
  }

  /// Opens the device camera and appends a single captured photo to
  /// [_pickedPhotos] (capped at [_maxTrophyPhotos]). Compression is applied
  /// uniformly at upload time in [_uploadTrophyPhotos].
  Future<void> _takeTrophyPhoto() async {
    if (_pickedPhotos.length >= _maxTrophyPhotos) return;
    try {
      final xFile = await _imagePicker.pickImage(source: ImageSource.camera);
      if (xFile != null && mounted) {
        setState(() => _pickedPhotos.add(xFile));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Camera capture failed: $e')),
        );
      }
    }
  }

  /// Removes a picked photo at [index].
  void _removeTrophyPhoto(int index) {
    setState(() => _pickedPhotos.removeAt(index));
  }

  /// Uploads each picked photo to Firebase Storage under
  /// `trophy_photos/{outfitterId}/{timestamp}_{i}.jpg` and returns the download
  /// URLs. Each photo is first downscaled + JPEG-compressed via [ImageService]
  /// (1280px, quality 75) to keep Storage usage and bandwidth low. Photos that
  /// fail to upload are skipped (partial success is OK).
  Future<List<String>> _uploadTrophyPhotos() async {
    if (_pickedPhotos.isEmpty) return const [];
    final outfitterId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];
    for (var i = 0; i < _pickedPhotos.length; i++) {
      final raw = File(_pickedPhotos[i].path);
      if (!await raw.exists()) continue;
      // Compress before upload (downscale to 1280px, JPEG q75).
      final file = await ImageService.compressExisting(raw);
      final ref = FirebaseStorage.instance.ref(
        'trophy_photos/$outfitterId/${timestamp}_$i.jpg',
      );
      try {
        final task = await ref.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final url = await task.ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        // Continue uploading the rest; report the first failure later.
        debugPrint('Trophy photo $i upload failed: $e');
      }
    }
    return urls;
  }

  /// Thumbnail for a "Current Stock by Farm" per-species row: the trophy's
  /// uploaded photo via the resilient [AdaptiveImage] pipeline, or a clean
  /// placeholder icon when the entry has no photo.
  Widget _trophyStockThumbnail(
      Map<String, dynamic> data, ThemeController theme) {
    final url = resolveTrophyStockPhotoUrl(data);
    if (url.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.pets_rounded,
          color: OutfitterUi.subtitleColor(theme),
          size: 18,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 40,
        child: AdaptiveImage(
          imagePath: url,
          fit: BoxFit.cover,
          width: 40,
          height: 40,
          errorWidget: Container(
            width: 40,
            height: 40,
            color: theme.accentColor.withValues(alpha: 0.15),
            child: Icon(
              Icons.pets_rounded,
              color: OutfitterUi.subtitleColor(theme),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeciesPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🎯 Select Species',
                style: TextStyle(
                  color: widget.theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _commonSpecies.length,
                  itemBuilder: (context, index) {
                    final species = _commonSpecies[index];
                    return InkWell(
                      onTap: () {
                        _speciesController.text = species;
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.theme.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          species,
                          style: TextStyle(
                            color: widget.theme.textColor,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
          '🥩 Trophy Inventory Stock',
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
              AppScreenHelpScripts.outfitterTrophyStock,
            ),
          ),
          OutfitterActionChip(
            icon: Icons.picture_as_pdf_rounded,
            tooltip: 'Export Trophy Inventory Report',
            iconColor: theme.accentColor,
            onPressed: _exportReport,
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
          // Trophy Stock Sync Form
          Container(
            decoration: BoxDecoration(
              color: OutfitterUi.cardColor(theme),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: OutfitterUi.cardBorderColor(theme),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sync_rounded,
                        color: theme.accentColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Sync Trophy Availability',
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Farm Dropdown
                        Text(
                          'SELECT FARM',
                          style: TextStyle(
                            color: OutfitterUi.subtitleColor(theme),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<QuerySnapshot>(
                          stream:
                              FirebaseFirestore.instance
                                  .collection('farms')
                                  .where(
                                    'outfitterId',
                                    isEqualTo:
                                        FirebaseAuth.instance.currentUser?.uid,
                                  )
                                  .where('status', isEqualTo: 'active')
                                  .snapshots(),
                          builder: (context, snapshot) {
                            final farms = snapshot.data?.docs ?? [];

                            return DropdownButtonFormField<String>(
                              value: _selectedFarmId,
                              decoration: InputDecoration(
                                hintText:
                                    _isManager
                                        ? 'Locked to assigned farm'
                                        : 'Choose a farm...',
                                hintStyle: TextStyle(
                                  color: OutfitterUi.subtitleColor(theme),
                                ),
                                filled: true,
                                fillColor:
                                    _isManager
                                        ? theme.accentColor.withValues(
                                          alpha: 0.1,
                                        )
                                        : OutfitterUi.cardColor(theme),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: OutfitterUi.cardBorderColor(theme),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: OutfitterUi.cardBorderColor(theme),
                                  ),
                                ),
                                prefixIcon:
                                    _isManager
                                        ? Icon(
                                          Icons.lock_rounded,
                                          color: theme.accentColor,
                                        )
                                        : null,
                              ),
                              dropdownColor: theme.cardColor,
                              style: TextStyle(color: theme.textColor),
                              items:
                                  farms.map((doc) {
                                    final data =
                                        doc.data() as Map<String, dynamic>;
                                    return DropdownMenuItem(
                                      value: doc.id,
                                      child: Text(data['name'] ?? 'Unknown'),
                                    );
                                  }).toList(),
                              onChanged:
                                  _isManager
                                      ? null
                                      : (value) {
                                        if (value == null) return;
                                        final farm = farms.firstWhere(
                                          (doc) => doc.id == value,
                                        );
                                        setState(() {
                                          _selectedFarmId = value;
                                          _selectedFarmName =
                                              (farm.data()
                                                  as Map<
                                                    String,
                                                    dynamic
                                                  >)['name'];
                                        });
                                      },
                              validator: (value) {
                                if (value == null) {
                                  return 'Please select a farm';
                                }
                                return null;
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Species Input with picker
                        Text(
                          'GAME SPECIES',
                          style: TextStyle(
                            color: OutfitterUi.subtitleColor(theme),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _speciesController,
                          style: TextStyle(color: theme.textColor),
                          decoration: InputDecoration(
                            hintText: 'e.g., Kudu, Gemsbok, Impala',
                            hintStyle: TextStyle(
                              color: OutfitterUi.subtitleColor(theme),
                            ),
                            filled: true,
                            fillColor: OutfitterUi.cardColor(theme),
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.list_rounded,
                                color: theme.accentColor,
                              ),
                              onPressed: _showSpeciesPicker,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: OutfitterUi.cardBorderColor(theme),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: OutfitterUi.cardBorderColor(theme),
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter species';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Count and Price Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AVAILABLE COUNT',
                                    style: TextStyle(
                                      color: OutfitterUi.subtitleColor(theme),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _countController,
                                    style: TextStyle(color: theme.textColor),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      hintStyle: TextStyle(
                                        color: OutfitterUi.subtitleColor(theme),
                                      ),
                                      filled: true,
                                      fillColor: OutfitterUi.cardColor(theme),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: OutfitterUi.cardBorderColor(theme),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: OutfitterUi.cardBorderColor(theme),
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PRICE PER TROPHY (ZAR)',
                                    style: TextStyle(
                                      color: OutfitterUi.subtitleColor(theme),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _priceController,
                                    style: TextStyle(color: theme.textColor),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[\d.,]'),
                                      ),
                                    ],
                                    decoration: InputDecoration(
                                      hintText: '25000',
                                      hintStyle: TextStyle(
                                        color: OutfitterUi.subtitleColor(theme),
                                      ),
                                      prefixText: 'R ',
                                      prefixStyle: TextStyle(
                                        color: theme.textColor,
                                      ),
                                      filled: true,
                                      fillColor: OutfitterUi.cardColor(theme),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: OutfitterUi.cardBorderColor(theme),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: OutfitterUi.cardBorderColor(theme),
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Trophy Measurement (horn/tusk/skull length in inches)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TROPHY LENGTH / SIZE (INCHES)',
                              style: TextStyle(
                                color: OutfitterUi.subtitleColor(theme),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _measurementController,
                              style: TextStyle(color: theme.textColor),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.,]'),
                                ),
                              ],
                              decoration: InputDecoration(
                                hintText: 'e.g. 42.5',
                                suffixText: 'in',
                                hintStyle: TextStyle(
                                  color: OutfitterUi.subtitleColor(theme),
                                ),
                                filled: true,
                                fillColor: OutfitterUi.cardColor(theme),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: theme.accentColor.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: theme.accentColor.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Multi-photo trophy attachments (up to 3)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'TROPHY PHOTOS (${_pickedPhotos.length}/$_maxTrophyPhotos)',
                                  style: TextStyle(
                                    color: OutfitterUi.subtitleColor(theme),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _pickedPhotos.length >=
                                              _maxTrophyPhotos
                                          ? null
                                          : _takeTrophyPhoto,
                                      icon: const Icon(Icons.camera_alt_rounded),
                                      label: const Text('Camera'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: theme.accentColor,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _pickedPhotos.length >=
                                              _maxTrophyPhotos
                                          ? null
                                          : _pickTrophyPhotos,
                                      icon:
                                          const Icon(Icons.add_photo_alternate_rounded),
                                      label: const Text('Gallery'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: theme.accentColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (_pickedPhotos.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Attach up to 3 photos of the trophy animal '
                                  '(horn, tusk, or full animal).',
                                  style: TextStyle(
                                    color: OutfitterUi.subtitleColor(theme).withValues(
                                      alpha: 0.7,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                height: 110,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _pickedPhotos.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (context, index) {
                                    return Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(
                                            File(_pickedPhotos[index].path),
                                            width: 110,
                                            height: 110,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stack) =>
                                                    Container(
                                              width: 110,
                                              height: 110,
                                              color: theme.backgroundColor,
                                              child: Icon(
                                                Icons.broken_image_rounded,
                                                color: OutfitterUi.subtitleColor(theme),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () =>
                                                _removeTrophyPhoto(index),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Sync Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSyncing ? null : _syncTrophyStock,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon:
                                _isSyncing
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.cloud_sync_rounded),
                            label: const Text(
                              'SYNC TROPHY STOCK',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
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

          // Current Stock List
          Container(
            decoration: BoxDecoration(
              color: OutfitterUi.cardColor(theme),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: OutfitterUi.cardBorderColor(theme),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_rounded,
                        color: theme.accentColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Current Stock by Farm',
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
                StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection(OutfitterEnterpriseManager
                              .trophyStockCollection)
                          .where(
                            'outfitterId',
                            isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                          )
                          .orderBy('lastUpdated', descending: true)
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.green),
                        ),
                      );
                    }

                    // A failed query (e.g. a missing composite index) must not be
                    // mistaken for an empty result — otherwise existing stock
                    // shows as "No trophy stock synced". Surface the error.
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
                                'Unable to load stock.\n'
                                'If this persists, deploy the Firestore indexes.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: OutfitterUi.subtitleColor(theme)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final trophies = snapshot.data?.docs ?? [];

                    if (trophies.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.grass_rounded,
                                color: theme.accentColor.withValues(alpha: 0.5),
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No trophy stock synced yet',
                                style: TextStyle(color: OutfitterUi.subtitleColor(theme)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // Group trophies by farmId so the summary renders per-farm
                    // tallies (the section is titled "Current Stock by Farm").
                    // Carry the document id on each entry (under a private key)
                    // so the per-species row can open the edit sheet for that
                    // exact trophy doc.
                    final byFarm = <String, List<Map<String, dynamic>>>{};
                    for (final doc in trophies) {
                      final data = doc.data() as Map<String, dynamic>;
                      data['_docId'] = doc.id;
                      final farmId = (data['farmId'] ?? '') as String;
                      byFarm.putIfAbsent(farmId, () => []).add(data);
                    }

                    // Resolve farm names: fetch all the user's farms once into a
                    // farmId → name map. Re-runs when the trophy stream emits.
                    return FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('farms')
                          .where(
                            'outfitterId',
                            isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                          )
                          .get(),
                      builder: (context, farmSnapshot) {
                        final farmNames = <String, String>{};
                        for (final f in farmSnapshot.data?.docs ?? const []) {
                          final fd = f.data() as Map<String, dynamic>;
                          farmNames[f.id] = (fd['name'] ?? 'Unknown Farm') as String;
                        }

                        final farmIds = byFarm.keys.toList();
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: farmIds.length,
                          separatorBuilder:
                              (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final farmId = farmIds[index];
                            final farmTrophies = byFarm[farmId]!;
                            final farmName = farmNames[farmId] ??
                                (farmId.isEmpty
                                    ? 'Unassigned'
                                    : 'Farm ${farmId.substring(0, farmId.length > 6 ? 6 : farmId.length)}…');
                            final farmTotal = farmTrophies.fold<int>(
                              0,
                              (total, t) =>
                                  total + ((t['availableCount'] ?? 0) as num).toInt(),
                            );

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.backgroundColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: farmTotal > 0
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                          Icons.agriculture_rounded,
                                          color: theme.accentColor,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          farmName,
                                          style: TextStyle(
                                            color: theme.textColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: farmTotal > 0
                                              ? Colors.green.withValues(alpha: 0.2)
                                              : Colors.red.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '$farmTotal total',
                                          style: TextStyle(
                                            color: farmTotal > 0
                                                ? Colors.green
                                                : Colors.red,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Per-species breakdown within this farm.
                                  // Tap a row to edit that trophy entry
                                  // (count, price, measurement, species).
                                  ...farmTrophies.map((data) {
                                    final species = data['species'] ?? 'Unknown';
                                    final count =
                                        (data['availableCount'] ?? 0) as num;
                                    final price =
                                        (data['pricePerTrophyRands'] ?? 0)
                                            .toDouble();
                                    final measurement =
                                        (data['trophyMeasurement'] ??
                                                data['trophyLengthInches'])
                                            ?.toDouble();
                                    final photos =
                                        (data['trophyPhotoUrls'] as List?)
                                            ?.cast<String>() ??
                                        const <String>[];
                                    final trophyId =
                                        data['_docId'] as String? ?? '';
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(6),
                                          onTap: trophyId.isEmpty
                                              ? null
                                              : () => _showEditTrophySheet(
                                                    trophyId: trophyId,
                                                    data: data,
                                                  ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4, horizontal: 4),
                                            child: Row(
                                              children: [
                                                _trophyStockThumbnail(
                                                    data, theme),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '$species — ${count.toInt()} available'
                                                    '${measurement != null ? " · ${measurement.toStringAsFixed(1)}in" : ""}'
                                                    '${photos.isNotEmpty ? " · ${photos.length} photo${photos.length > 1 ? "s" : ""}" : ""}',
                                                    style: TextStyle(
                                                      color: theme.textColor,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  'R ${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                                                  style: const TextStyle(
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(Icons.edit_rounded,
                                                    size: 16,
                                                    color: theme.accentColor
                                                        .withValues(alpha: 0.7)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const CopyrightFooter(),
        ],
        ),
      ),
    );
  }
}
