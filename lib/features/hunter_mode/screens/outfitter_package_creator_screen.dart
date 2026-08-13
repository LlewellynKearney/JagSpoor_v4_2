import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/image_service.dart';
import '../../../models/animal.dart';
import '../models/package_pricing.dart';
import '../services/package_booking_manager.dart';

class OutfitterPackageCreatorScreen extends StatefulWidget {
  final ThemeController theme;

  /// Optional existing package to edit. When non-null the form is prefilled and
  /// the save action updates the package instead of publishing a new one.
  final Map<String, dynamic>? existingPackage;

  /// Package id being edited (populated from [existingPackage]['id'] when
  /// available; accepted explicitly for convenience).
  final String? packageId;

  const OutfitterPackageCreatorScreen({
    super.key,
    required this.theme,
    this.existingPackage,
    this.packageId,
  });

  @override
  State<OutfitterPackageCreatorScreen> createState() =>
      _OutfitterPackageCreatorScreenState();
}

class _OutfitterPackageCreatorScreenState
    extends State<OutfitterPackageCreatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _depositController = TextEditingController(text: '25');
  final List<String> _inclusions = [];
  final _inclusionController = TextEditingController();

  String? _selectedFarmId;
  bool _isLoading = false;

  // Image gallery (up to 5). Mix of newly-picked local files and previously
  // uploaded remote URLs (when editing an existing package).
  static const int _maxImages = 5;
  final List<XFile> _pickedImages = [];
  final List<String> _existingImageUrls = [];
  double _uploadProgress = 0;
  bool _isUploading = false;
  final ImagePicker _imagePicker = ImagePicker();

  // Lifecycle status to save the package as (Active vs Draft).
  PackageStatus _saveStatus = PackageStatus.active;

  // Edit-mode bookkeeping.
  String? _editingPackageId;

  // Pricing mode: All-Inclusive vs Itemized.
  PackagePricingMode _pricingMode = PackagePricingMode.allInclusive;

  // All-inclusive single total price (mirrors _priceController for clarity).
  double get _allInclusivePrice =>
      double.tryParse(_priceController.text.replaceAll(',', '').trim()) ?? 0.0;

  // Itemized breakdown line items keyed by category key.
  final Map<String, ItemizedLineItem> _lineItems = {};

  // Selected species with quantity + price-per-animal.
  final List<SpeciesLineItem> _speciesItems = [];

  // Availability window.
  DateTime? _availabilityStart;
  DateTime? _availabilityEnd;

  // Live catalog of SA Game Guide species for the multi-species selector.
  List<Animal> _speciesCatalog = [];

  @override
  void initState() {
    super.initState();
    _loadSpeciesCatalog();
    _prefillForEdit();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    _inclusionController.dispose();
    super.dispose();
  }

  /// Prefills the form from [widget.existingPackage] when opened in edit mode.
  void _prefillForEdit() {
    final pkg = widget.existingPackage;
    if (pkg == null) return;

    _editingPackageId = widget.packageId ?? pkg['id'] as String?;
    _titleController.text = (pkg['title'] ?? '').toString();
    _descriptionController.text = (pkg['description'] ?? '').toString();

    final mode = PackagePricingMode.fromString(pkg['mode'] as String?);
    _pricingMode = mode;
    if (mode == PackagePricingMode.allInclusive) {
      final price = (pkg['allInclusivePrice'] as num?)?.toDouble() ??
          (pkg['basePriceRands'] as num?)?.toDouble() ??
          0.0;
      _priceController.text =
          price > 0 ? price.toStringAsFixed(2) : '';
    }

    _selectedFarmId = pkg['farmId'] as String?;
    _saveStatus = PackageStatus.fromString(pkg['status'] as String?);

    final depPct = pkg['depositPercentage'];
    if (depPct is num) {
      _depositController.text = depPct.toDouble().toStringAsFixed(0);
    }

    final incl = pkg['inclusions'];
    if (incl is List) {
      _inclusions.addAll(incl.whereType<String>());
    }

    final urls = pkg['imageUrls'];
    if (urls is List) {
      _existingImageUrls
          .addAll(urls.whereType<String>().take(_maxImages));
    }

    final lineItemsRaw = pkg['lineItems'];
    if (lineItemsRaw is List) {
      for (final e in lineItemsRaw.whereType<Map>()) {
        final item = ItemizedLineItem.fromMap(
            Map<String, dynamic>.from(e));
        _lineItems[item.key] = item;
      }
    }

    final speciesRaw = pkg['speciesItems'];
    if (speciesRaw is List) {
      for (final e in speciesRaw.whereType<Map>()) {
        _speciesItems.add(SpeciesLineItem.fromMap(
            Map<String, dynamic>.from(e)));
      }
    }

    final start = pkg['availabilityStart'];
    final end = pkg['availabilityEnd'];
    if (start is Timestamp) _availabilityStart = start.toDate();
    if (end is Timestamp) _availabilityEnd = end.toDate();
  }

  Future<void> _loadSpeciesCatalog() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('animals')
          .orderBy('sortOrder')
          .get();
      if (mounted) {
        setState(() {
          _speciesCatalog = snapshot.docs
              .map((doc) => Animal.fromFirestore(doc))
              .where((a) => a.name.isNotEmpty)
              .toList();
        });
      }
    } catch (_) {
      // Catalog is optional; selector remains usable but empty.
    }
  }

  void _addInclusion() {
    final inclusion = _inclusionController.text.trim();
    if (inclusion.isNotEmpty && !_inclusions.contains(inclusion)) {
      setState(() {
        _inclusions.add(inclusion);
        _inclusionController.clear();
      });
    }
  }

  void _removeInclusion(String inclusion) {
    setState(() {
      _inclusions.remove(inclusion);
    });
  }

  // ── Image gallery management ───────────────────────────────────────────

  int get _totalImageCount => _pickedImages.length + _existingImageUrls.length;
  bool get _canAddImage => _totalImageCount < _maxImages;

  Future<void> _pickPackageImages() async {
    if (!_canAddImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum $_maxImages images reached'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final remaining = _maxImages - _totalImageCount;
    final picked = await _imagePicker.pickMultipleMedia(
      imageQuality: 80,
      limit: remaining,
    );
    if (picked.isEmpty) return;
    setState(() {
      final addable = picked.take(remaining);
      _pickedImages.addAll(addable);
      if (_pickedImages.length + _existingImageUrls.length > _maxImages) {
        _pickedImages.removeRange(
          _maxImages - _existingImageUrls.length,
          _pickedImages.length,
        );
      }
    });
  }

  void _removePickedImage(int index) {
    setState(() => _pickedImages.removeAt(index));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  /// Uploads all newly-picked images to Firebase Storage with per-file
  /// compression and aggregate progress feedback. Returns the full set of
  /// image URLs to store on the package (existing + freshly uploaded).
  Future<List<String>> _uploadPackageImages() async {
    final outfitterId =
        FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final allUrls = List<String>.from(_existingImageUrls);

    if (_pickedImages.isEmpty) return allUrls;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    final totalSteps = _pickedImages.length;
    for (var i = 0; i < _pickedImages.length; i++) {
      final raw = File(_pickedImages[i].path);
      if (!await raw.exists()) continue;
      // Compress before upload (downscale to 1280px, JPEG q75) — keeps
      // Storage usage and Firestore document sizes small.
      final file = await ImageService.compressExisting(raw);
      final ref = FirebaseStorage.instance.ref(
        'package_images/$outfitterId/${timestamp}_$i.jpg',
      );
      try {
        final uploadTask = ref.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        // Drive the progress indicator from the upload task events.
        uploadTask.snapshotEvents.listen((event) {
          if (event.totalBytes > 0) {
            final fileProgress = (i + event.bytesTransferred / event.totalBytes) / totalSteps;
            setState(() => _uploadProgress = fileProgress.clamp(0, 1));
          }
        });
        final snapshot = await uploadTask;
        allUrls.add(await snapshot.ref.getDownloadURL());
      } catch (e) {
        debugPrint('Package image $i upload failed: $e');
      }
    }

    setState(() {
      _isUploading = false;
      _uploadProgress = 0;
    });

    return allUrls;
  }

  /// Resolved base price across both pricing modes.
  double get _resolvedBasePrice {
    if (_pricingMode == PackagePricingMode.allInclusive) {
      return _allInclusivePrice;
    }
    double sum = 0;
    for (final item in _lineItems.values) {
      sum += item.total;
    }
    for (final species in _speciesItems) {
      sum += species.total;
    }
    return sum;
  }

  Future<void> _pickAvailabilityDate(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_availabilityStart ?? now)
        : (_availabilityEnd ?? _availabilityStart ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _availabilityStart = picked;
          if (_availabilityEnd != null &&
              _availabilityEnd!.isBefore(picked)) {
            _availabilityEnd = picked;
          }
        } else {
          _availabilityEnd = picked;
        }
      });
    }
  }

  void _editLineItem(ItemizedBreakdownCategory category) {
    final existing = _lineItems[category.key];
    final qtyController = TextEditingController(
      text: existing != null ? existing.quantity.toString() : '',
    );
    final priceController = TextEditingController(
      text: existing != null
          ? existing.pricePerUnit.toStringAsFixed(2)
          : '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: widget.theme.cardColor,
          title: Text(
            category.label,
            style: TextStyle(
              color: widget.theme.textColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: widget.theme.textColor),
                decoration: _inputDecoration(
                  hint: 'Quantity',
                  theme: widget.theme,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: widget.theme.textColor),
                decoration: _inputDecoration(
                  hint: 'Price per unit (ZAR)',
                  prefix: 'R ',
                  theme: widget.theme,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _lineItems.remove(category.key);
                  });
                  Navigator.pop(dialogContext);
                },
                child: const Text('Remove',
                    style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel',
                  style: TextStyle(color: widget.theme.subtitleColor)),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                final price =
                    double.tryParse(priceController.text.trim()) ?? 0.0;
                if (qty <= 0 || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid quantity and price'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                setState(() {
                  _lineItems[category.key] = ItemizedLineItem(
                    key: category.key,
                    label: category.label,
                    quantity: qty,
                    pricePerUnit: price,
                  );
                });
                Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.theme.accentColor,
                foregroundColor: Colors.black,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _addSpecies() {
    if (_speciesCatalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'SA Game Guide species are still loading or unavailable. Try again shortly.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Animal? selected;
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: widget.theme.cardColor,
              title: Text(
                'Add Species',
                style: TextStyle(
                  color: widget.theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Animal>(
                    value: selected,
                    decoration: _inputDecoration(
                      hint: 'Select species from SA Game Guide...',
                      theme: widget.theme,
                    ),
                    dropdownColor: widget.theme.cardColor,
                    style: TextStyle(color: widget.theme.textColor),
                    items: _speciesCatalog.map((animal) {
                      return DropdownMenuItem<Animal>(
                        value: animal,
                        child: Text(animal.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selected = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: widget.theme.textColor),
                    decoration: _inputDecoration(
                      hint: 'Quantity',
                      theme: widget.theme,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: widget.theme.textColor),
                    decoration: _inputDecoration(
                      hint: 'Price per animal (ZAR)',
                      prefix: 'R ',
                      theme: widget.theme,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancel',
                      style: TextStyle(color: widget.theme.subtitleColor)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selected == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a species'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                    final price =
                        double.tryParse(priceController.text.trim()) ?? 0.0;
                    if (qty <= 0 || price <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Enter a valid quantity and price per animal'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _speciesItems.add(SpeciesLineItem(
                        speciesId: selected!.id,
                        speciesName: selected!.name,
                        quantity: qty,
                        pricePerAnimal: price,
                      ));
                    });
                    Navigator.pop(dialogContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.theme.accentColor,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeSpecies(int index) {
    setState(() {
      _speciesItems.removeAt(index);
    });
  }

  Future<void> _publishPackage() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFarmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select a farm for this package'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_inclusions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one inclusion'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final basePrice = _resolvedBasePrice;
    if (basePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Package price must be greater than zero. Add a price or at least one itemized line.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Deposit percentage validation (0–100, defaults to 25%).
    final depositPct =
        double.tryParse(_depositController.text.trim().replaceAll('%', '')) ??
            25;
    if (depositPct < 0 || depositPct > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deposit percentage must be between 0 and 100'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Upload gallery images (with compression + progress feedback) before
      // persisting the package document.
      final imageUrls = await _uploadPackageImages();

      final pricing = PackagePricing(
        mode: _pricingMode,
        allInclusivePrice: _allInclusivePrice,
        lineItems: _lineItems.values.toList(),
        speciesItems: List<SpeciesLineItem>.from(_speciesItems),
        availabilityStart: _availabilityStart,
        availabilityEnd: _availabilityEnd,
      );

      final isEditing = _editingPackageId != null;

      if (isEditing) {
        await PackageBookingManager.instance.updatePackage(
          packageId: _editingPackageId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          pricing: pricing,
          inclusions: List<String>.from(_inclusions),
          farmId: _selectedFarmId,
          imageUrls: imageUrls,
          depositPercentage: depositPct,
        );
        // Reflect the chosen lifecycle status (e.g. re-activate a draft).
        await PackageBookingManager.instance.setPackageStatus(
          packageId: _editingPackageId!,
          status: _saveStatus,
        );
      } else {
        await PackageBookingManager.instance.publishPackage(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          pricing: pricing,
          inclusions: List<String>.from(_inclusions),
          farmId: _selectedFarmId,
          status: _saveStatus,
          imageUrls: imageUrls,
          depositPercentage: depositPct,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? '✅ Package updated successfully!'
                : '✅ Package ${_saveStatus == PackageStatus.draft ? "saved as draft" : "published"} successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
        title: Text(
          _editingPackageId != null ? '🏕️ Edit Package' : '🏕️ Publish Package',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── IMAGE GALLERY ──────────────────────────────────────────────
            _buildSectionLabel('PACKAGE GALLERY', theme),
            const SizedBox(height: 8),
            _buildImageGallery(theme),
            const SizedBox(height: 24),

            // Farm Selection (Mandatory)
            _buildSectionLabel('BIND TO FARM *', theme),
            const SizedBox(height: 8),
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

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.green),
                    ),
                  );
                }

                if (farms.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No farms registered. Register a farm first in Enterprise Panel.',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return DropdownButtonFormField<String>(
                  value: _selectedFarmId,
                  decoration: _inputDecoration(
                    hint: 'Select farm for this package...',
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
            const SizedBox(height: 24),

            // Package Title
            _buildSectionLabel('PACKAGE TITLE', theme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              style: TextStyle(color: theme.textColor),
              decoration: _inputDecoration(
                hint: 'e.g., 5-Day Kalahari Lion Hunt',
                theme: theme,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a package title';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Description
            _buildSectionLabel('DESCRIPTION', theme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              style: TextStyle(color: theme.textColor),
              maxLines: 4,
              decoration: _inputDecoration(
                hint:
                    'Describe the hunting experience, terrain, trophy expectations...',
                theme: theme,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ── PRICING MODE TOGGLE ──────────────────────────────────────
            _buildSectionLabel('PRICING MODE', theme),
            const SizedBox(height: 8),
            _buildPricingModeToggle(theme),
            const SizedBox(height: 24),

            // ── PRICING BODY ─────────────────────────────────────────────
            if (_pricingMode == PackagePricingMode.allInclusive)
              _buildAllInclusiveSection(theme)
            else
              _buildItemizedSection(theme),

            const SizedBox(height: 24),

            // ── AVAILABILITY WINDOW ──────────────────────────────────────
            _buildSectionLabel('PACKAGE AVAILABILITY', theme),
            const SizedBox(height: 8),
            _buildAvailabilityRow(theme),
            const SizedBox(height: 24),

            // Inclusions
            _buildSectionLabel('PACKAGE INCLUSIONS', theme),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _inclusionController,
                    style: TextStyle(color: theme.textColor),
                    decoration: _inputDecoration(
                      hint: 'e.g., Transport, Accommodation, Meals',
                      theme: theme,
                    ),
                    onFieldSubmitted: (_) => _addInclusion(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addInclusion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('ADD'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Inclusion Tags
            if (_inclusions.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _inclusions.map((inclusion) {
                      return Chip(
                        label: Text(
                          inclusion,
                          style: TextStyle(color: theme.textColor),
                        ),
                        backgroundColor: theme.accentColor.withValues(
                          alpha: 0.2,
                        ),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => _removeInclusion(inclusion),
                      );
                    }).toList(),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'No inclusions added yet',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // ── DUAL PRICING SUMMARY (7.5% platform fee) ────────────────
            _buildPricingSummary(theme),
            const SizedBox(height: 24),

            // ── DEPOSIT PERCENTAGE (per-package, non-refundable) ─────────
            _buildSectionLabel('DEPOSIT PERCENTAGE (%)', theme),
            const SizedBox(height: 8),
            TextFormField(
              controller: _depositController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: theme.textColor),
              decoration: _inputDecoration(
                hint: 'e.g., 25',
                suffix: '%',
                theme: theme,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              validator: (value) {
                final raw = value?.trim().replaceAll('%', '') ?? '';
                final pct = double.tryParse(raw);
                if (pct == null) {
                  return 'Enter a valid deposit percentage';
                }
                if (pct < 0 || pct > 100) {
                  return 'Deposit must be between 0 and 100';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ── LIFECYCLE STATUS (Active vs Draft) ────────────────────────
            _buildSectionLabel('LISTING STATUS', theme),
            const SizedBox(height: 8),
            _buildStatusToggle(theme),
            const SizedBox(height: 24),

            // Publish / Save Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _publishPackage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _isLoading
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_editingPackageId != null
                                ? Icons.save_rounded
                                : Icons.publish_rounded),
                            const SizedBox(width: 8),
                            Text(
                              _editingPackageId != null
                                  ? 'SAVE CHANGES'
                                  : (_saveStatus == PackageStatus.draft
                                      ? 'SAVE AS DRAFT'
                                      : 'PUBLISH PACKAGE'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Image gallery section ──────────────────────────────────────────────
  Widget _buildImageGallery(ThemeController theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isUploading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Uploading images... ${(_uploadProgress * 100).toInt()}%',
                      style: TextStyle(
                          color: theme.subtitleColor, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _uploadProgress,
                  backgroundColor: theme.cardColor,
                  color: theme.accentColor,
                ),
              ],
            ),
          ),
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Existing (already-uploaded) images when editing.
              ..._existingImageUrls.asMap().entries.map((entry) {
                final idx = entry.key;
                final url = entry.value;
                return _imageThumb(
                  theme,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ColoredBox(
                      color: Colors.black26,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                  onRemove: () => _removeExistingImage(idx),
                );
              }),
              // Newly picked local images.
              ..._pickedImages.asMap().entries.map((entry) {
                final idx = entry.key;
                return _imageThumb(
                  theme,
                  child: Image.file(File(entry.value.path), fit: BoxFit.cover),
                  onRemove: () => _removePickedImage(idx),
                );
              }),
              // Add-image button.
              if (_canAddImage)
                GestureDetector(
                  onTap: _pickPackageImages,
                  child: Container(
                    width: 110,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.accentColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded,
                            color: theme.accentColor, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          'Add Photos',
                          style: TextStyle(
                              color: theme.subtitleColor, fontSize: 11),
                        ),
                        Text(
                          '$_totalImageCount/$_maxImages',
                          style: TextStyle(
                              color: theme.subtitleColor, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _imageThumb(ThemeController theme,
      {required Widget child, required VoidCallback onRemove}) {
    return Container(
      width: 110,
      height: 110,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Lifecycle status toggle (Active vs Draft) ─────────────────────────
  Widget _buildStatusToggle(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statusSegment(
              theme,
              label: 'Active',
              icon: Icons.visibility_rounded,
              selected: _saveStatus == PackageStatus.active,
              onTap: () => setState(() => _saveStatus = PackageStatus.active),
            ),
          ),
          Expanded(
            child: _statusSegment(
              theme,
              label: 'Draft',
              icon: Icons.visibility_off_rounded,
              selected: _saveStatus == PackageStatus.draft,
              onTap: () => setState(() => _saveStatus = PackageStatus.draft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusSegment(
    ThemeController theme, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? theme.accentColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? theme.accentColor : theme.subtitleColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.textColor : theme.subtitleColor,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pricing mode segmented toggle ──────────────────────────────────────
  Widget _buildPricingModeToggle(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeSegment(
              theme,
              label: 'All-Inclusive',
              icon: Icons.payments_rounded,
              selected: _pricingMode == PackagePricingMode.allInclusive,
              onTap: () => setState(() {
                _pricingMode = PackagePricingMode.allInclusive;
              }),
            ),
          ),
          Expanded(
            child: _modeSegment(
              theme,
              label: 'Itemized / Custom',
              icon: Icons.list_alt_rounded,
              selected: _pricingMode == PackagePricingMode.itemized,
              onTap: () => setState(() {
                _pricingMode = PackagePricingMode.itemized;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSegment(
    ThemeController theme, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? theme.accentColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: theme.accentColor, width: 1.5)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? theme.accentColor : theme.subtitleColor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.accentColor : theme.subtitleColor,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── All-inclusive single price ─────────────────────────────────────────
  Widget _buildAllInclusiveSection(ThemeController theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('TOTAL PACKAGE PRICE (ZAR)', theme),
        const SizedBox(height: 8),
        TextFormField(
          controller: _priceController,
          style: TextStyle(color: theme.textColor),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          decoration: _inputDecoration(
            hint: '25000',
            prefix: 'R ',
            theme: theme,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a price';
            }
            final price = double.tryParse(
              value.replaceAll(',', '').replaceAll('R', ''),
            );
            if (price == null || price <= 0) {
              return 'Please enter a valid price';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Optional species advertisement (not summed into all-inclusive price).
        _buildSectionLabel('ADVERTISED SPECIES (OPTIONAL)', theme),
        const SizedBox(height: 8),
        _buildSpeciesList(theme),
      ],
    );
  }

  // ── Itemized breakdown + species ───────────────────────────────────────
  Widget _buildItemizedSection(ThemeController theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ITEMIZED BREAKDOWN', theme),
        const SizedBox(height: 8),
        ...ItemizedBreakdownCategory.all.map((category) {
          final item = _lineItems[category.key];
          return _lineItemRow(theme, category, item);
        }),
        const SizedBox(height: 16),

        _buildSectionLabel('SPECIES & ANIMAL RATES', theme),
        const SizedBox(height: 8),
        _buildSpeciesList(theme),
      ],
    );
  }

  Widget _lineItemRow(
    ThemeController theme,
    ItemizedBreakdownCategory category,
    ItemizedLineItem? item,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item != null
              ? theme.accentColor.withValues(alpha: 0.4)
              : theme.accentColor.withValues(alpha: 0.15),
        ),
      ),
      child: ListTile(
        onTap: () => _editLineItem(category),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          category.label,
          style: TextStyle(
            color: theme.textColor,
            fontSize: 14,
            fontWeight: item != null ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: item != null
            ? Text(
                'Qty ${item.quantity} × R ${item.pricePerUnit.toStringAsFixed(2)} = R ${item.total.toStringAsFixed(2)}',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 12,
                ),
              )
            : Text(
                'Tap to add quantity & price',
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
        trailing: Icon(
          item != null ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
          color: item != null ? theme.accentColor : theme.subtitleColor,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildSpeciesList(ThemeController theme) {
    if (_speciesItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Text(
              _pricingMode == PackagePricingMode.itemized
                  ? 'No species added yet'
                  : 'No advertised species added yet',
              style: TextStyle(
                color: theme.subtitleColor,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _addSpecies,
              icon: const Icon(Icons.pets_rounded, size: 18),
              label: const Text('Add Species'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentColor,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ..._speciesItems.asMap().entries.map((entry) {
          final index = entry.key;
          final species = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.pets_rounded,
                    color: theme.accentColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        species.speciesName,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Qty ${species.quantity} × R ${species.pricePerAnimal.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'R ${species.total.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.red,
                  onPressed: () => _removeSpecies(index),
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addSpecies,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another species'),
            style: TextButton.styleFrom(
              foregroundColor: theme.accentColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvailabilityRow(ThemeController theme) {
    return Row(
      children: [
        Expanded(
          child: _dateChip(
            theme,
            label: 'Start Date',
            value: _availabilityStart,
            onTap: () => _pickAvailabilityDate(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dateChip(
            theme,
            label: 'End Date',
            value: _availabilityEnd,
            onTap: () => _pickAvailabilityDate(false),
          ),
        ),
      ],
    );
  }

  Widget _dateChip(
    ThemeController theme, {
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.event_rounded,
                color: theme.accentColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.subtitleColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    value != null
                        ? '${value.day}/${value.month}/${value.year}'
                        : 'Select date',
                    style: TextStyle(
                      color: value != null
                          ? theme.textColor
                          : theme.subtitleColor,
                      fontSize: 14,
                      fontWeight:
                          value != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dual pricing summary: Base + 7.5% = Total ──────────────────────────
  Widget _buildPricingSummary(ThemeController theme) {
    final base = _resolvedBasePrice;
    final fee = base * PackageBookingManager.platformCommissionRate;
    final total = base + fee;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'PACKAGE VALUE (7.5% PLATFORM FEE)',
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _summaryRow(
            theme,
            label: 'Outfitter Base Price',
            value: 'R ${base.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _summaryRow(
            theme,
            label: '7.5% Platform Fee',
            value: 'R ${fee.toStringAsFixed(2)}',
            valueColor: Colors.amber.shade700,
          ),
          const Divider(height: 20),
          _summaryRow(
            theme,
            label: 'Total Package Value',
            value: 'R ${total.toStringAsFixed(2)}',
            valueColor: Colors.green,
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    ThemeController theme, {
    required String label,
    required String value,
    Color? valueColor,
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? theme.textColor : theme.subtitleColor,
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? theme.textColor,
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label, ThemeController theme) {
    return Text(
      label,
      style: TextStyle(
        color: theme.subtitleColor,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required ThemeController theme,
    String? prefix,
    String? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: theme.subtitleColor.withValues(alpha: 0.5)),
      prefixText: prefix,
      prefixStyle: TextStyle(color: theme.textColor),
      suffixText: suffix,
      suffixStyle: TextStyle(color: theme.textColor),
      filled: true,
      fillColor: theme.cardColor,
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }
}
