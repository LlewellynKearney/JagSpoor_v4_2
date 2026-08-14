import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../services/pricelist_scanner_service.dart';

/// Post-scan verification grid editor for reviewing and editing extracted price list items.
/// Allows outfitters to verify species names and base prices before saving to Firestore.
class OutfitterPricelistVerificationScreen extends StatefulWidget {
  final ThemeController theme;
  final List<Map<String, dynamic>> extractedItems;
  final String? farmId;
  final String? farmName;
  final String? imageFileName;

  const OutfitterPricelistVerificationScreen({
    super.key,
    required this.theme,
    required this.extractedItems,
    this.farmId,
    this.farmName,
    this.imageFileName,
  });

  @override
  State<OutfitterPricelistVerificationScreen> createState() =>
      _OutfitterPricelistVerificationScreenState();
}

class _OutfitterPricelistVerificationScreenState
    extends State<OutfitterPricelistVerificationScreen> {
  final PricelistScannerService _pricelistService =
      PricelistScannerService.instance;
  final _formKey = GlobalKey<FormState>();

  late List<Map<String, dynamic>> _editableItems;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Create a deep copy of the items for editing
    _editableItems =
        widget.extractedItems
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
  }

  void _updateItem(int index, {String? name, double? basePrice}) {
    setState(() {
      if (name != null) {
        _editableItems[index]['name'] = name;
      }
      if (basePrice != null) {
        _editableItems[index]['outfitterBasePrice'] = basePrice;
        // Recalculate display price with 7.5% platform fee
        final double displayPrice = basePrice * 1.075;
        _editableItems[index]['hunterDisplayPriceZAR'] = displayPrice;
        _editableItems[index]['hunterPriceFormatted'] =
            'R${displayPrice.toStringAsFixed(0)}';
        _editableItems[index]['commissionZAR'] = displayPrice - basePrice;
      }
      _hasChanges = true;
    });
  }

  Future<void> _saveToFirestore() async {
    if (!_formKey.currentState!.validate()) {
      _showError('Please fix validation errors before saving');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Build processed items with 7.5% commission split
      final List<Map<String, dynamic>> processedItems = [];

      for (final item in _editableItems) {
        final speciesName = item['name'] as String;
        final basePrice =
            (item['outfitterBasePrice'] as num?)?.toDouble() ?? 0.0;

        // Calculate display price with 7.5% platform fee
        final double displayPrice = basePrice * 1.075;

        processedItems.add({
          'name': speciesName,
          'displayLabel': item['displayLabel'] ?? speciesName,
          'speciesName': item['speciesName'] ?? '',
          'speciesId': item['speciesId'] ?? '',
          'sex': item['sex'] ?? '',
          'sexLabel': item['sexLabel'] ?? '',
          'trophySizeRange': item['trophySizeRange'] ?? '',
          'itemType': item['itemType'] ?? 'species',
          'feeType': item['feeType'] ?? '',
          'outfitterBasePrice': basePrice,
          'hunterDisplayPriceZAR': displayPrice,
          'basePriceFormatted': 'R${basePrice.toStringAsFixed(0)}',
          'hunterPriceFormatted': 'R${displayPrice.toStringAsFixed(0)}',
          'commissionZAR': displayPrice - basePrice,
        });
      }

      // Persist via the centralized service method (writes scanned_pricelists)
      await _pricelistService.saveVerifiedPricelist(
        items: processedItems,
        farmId: widget.farmId,
        farmName: widget.farmName,
        imageFileName: widget.imageFileName,
      );

      if (mounted) {
        _showSuccess(
          'Price list saved successfully! ${processedItems.length} items uploaded.',
        );
        // Return the user deterministically to the outfitter dashboard (where
        // the Scan History Log card lives) so the freshly-saved scan is
        // visible. Previously this used `popUntil((route) => route.isFirst)`,
        // which is a fragile navigation-stack reset: depending on how the
        // scanner was reached, `isFirst` could resolve to the splash/auth
        // screen, kicking the user back to login after a successful save.
        // `pushNamedAndRemoveUntil('/outfitter_dashboard', (_) => false)`
        // guarantees a clean, authenticated landing on the dashboard — never
        // splash/role-selection/login — and remounts the dashboard so its
        // scan-history StreamBuilder re-subscribes and shows the new scan.
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/outfitter_dashboard', (_) => false);
        });
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to save: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('⚠️ $message'), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ $message'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.theme.backgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.edit_document, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Post-Scan Verification',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: widget.theme.backgroundColor,
        foregroundColor: widget.theme.textColor,
        elevation: 0,
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset to original',
              onPressed: () {
                setState(() {
                  _editableItems =
                      widget.extractedItems
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList();
                  _hasChanges = false;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Info Banner
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.theme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: widget.theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Review and edit extracted items. 7.5% commission will be applied on save.',
                    style: TextStyle(
                      color: widget.theme.subtitleColor,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Form
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    16, 0, 16, SafeBottomInset.of(context)),
                itemCount: _editableItems.length,
                itemBuilder: (context, index) {
                  return _EditablePriceItem(
                    index: index,
                    item: _editableItems[index],
                    theme: widget.theme,
                    onUpdate:
                        (name, basePrice) => _updateItem(
                          index,
                          name: name,
                          basePrice: basePrice,
                        ),
                  );
                },
              ),
            ),
          ),

          // Save Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveToFirestore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.theme.accentColor,
                    foregroundColor: widget.theme.backgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon:
                      _isSaving
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.save_rounded),
                  label: Text(
                    _isSaving ? 'SAVING...' : 'SAVE PRICE LIST',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditablePriceItem extends StatefulWidget {
  final int index;
  final Map<String, dynamic> item;
  final ThemeController theme;
  final void Function(String? name, double? basePrice) onUpdate;

  const _EditablePriceItem({
    required this.index,
    required this.item,
    required this.theme,
    required this.onUpdate,
  });

  @override
  State<_EditablePriceItem> createState() => _EditablePriceItemState();
}

class _EditablePriceItemState extends State<_EditablePriceItem> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.item['name'] as String? ?? '',
    );
    _priceController = TextEditingController(
      text:
          (widget.item['outfitterBasePrice'] as num?)
              ?.toDouble()
              .toStringAsFixed(0) ??
          '0',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    widget.onUpdate(value, null);
  }

  void _onPriceChanged(String value) {
    final price = double.tryParse(value) ?? 0.0;
    widget.onUpdate(null, price);
  }

  Widget _badge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> get _metaBadges {
    final badges = <Widget>[];
    final itemType = (widget.item['itemType'] ?? 'species').toString();
    final sexLabel = (widget.item['sexLabel'] ?? '').toString();
    final sex = (widget.item['sex'] ?? '').toString();
    final sizeRange = (widget.item['trophySizeRange'] ?? '').toString();
    final speciesId = (widget.item['speciesId'] ?? '').toString();
    final feeType = (widget.item['feeType'] ?? '').toString();

    if (itemType == 'fee') {
      badges.add(_badge(
        feeType.isEmpty ? 'FEE' : feeType.toUpperCase(),
        Icons.payments_outlined,
        Colors.indigo,
      ));
    } else {
      badges.add(_badge('SPECIES', Icons.pets, widget.theme.accentColor));
    }
    if (sexLabel.isNotEmpty || sex.isNotEmpty) {
      badges.add(_badge(
        sexLabel.isNotEmpty ? sexLabel.toUpperCase() : sex.toUpperCase(),
        Icons.male,
        Colors.blue,
      ));
    }
    if (sizeRange.isNotEmpty) {
      badges.add(_badge(sizeRange, Icons.straighten, Colors.teal));
    }
    if (speciesId.isNotEmpty) {
      badges.add(_badge(speciesId, Icons.tag, widget.theme.subtitleColor));
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final basePrice =
        (widget.item['outfitterBasePrice'] as num?)?.toDouble() ?? 0.0;
    final displayPrice = basePrice * 1.075;
    final commission = displayPrice - basePrice;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row number indicator
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.theme.accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${widget.index + 1}',
                  style: TextStyle(
                    color: widget.theme.accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '7.5% Fee: R${commission.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.amber.shade700, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Extracted metadata badges (sex/class, trophy size tier, species id, type)
          if (_metaBadges.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _metaBadges,
            ),
            const SizedBox(height: 12),
          ],

          // Species Name Field
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SPECIES NAME',
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _nameController,
                      onChanged: _onNameChanged,
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: widget.theme.backgroundColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: widget.theme.accentColor,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Base Price Field
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BASE PRICE (R)',
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _priceController,
                      onChanged: _onPriceChanged,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: widget.theme.backgroundColor,
                        prefixText: 'R ',
                        prefixStyle: TextStyle(
                          color: widget.theme.subtitleColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: widget.theme.accentColor,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price < 0) {
                          return 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Display Price Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.theme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hunter Display Price (incl. 7.5%):',
                  style: TextStyle(
                    color: widget.theme.subtitleColor,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'R ${displayPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
