import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pricelist_scanner_service.dart';

class HunterCustomPackageBuilderScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterCustomPackageBuilderScreen({super.key, required this.theme});

  @override
  State<HunterCustomPackageBuilderScreen> createState() =>
      _HunterCustomPackageBuilderScreenState();
}

class _HunterCustomPackageBuilderScreenState
    extends State<HunterCustomPackageBuilderScreen> {
  final PricelistScannerService _pricelistService =
      PricelistScannerService.instance;

  final Set<String> _selectedItemIds = {};
  final List<Map<String, dynamic>> _allItems = [];
  double _runningTotal = 0;
  bool _isSubmitting = false;
  String? _selectedPricelistId;
  Map<String, dynamic>? _selectedPricelist;
  List<Map<String, dynamic>> _availablePricelists = [];

  @override
  void initState() {
    super.initState();
    _loadPricelists();
  }

  Future<void> _loadPricelists() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('scanned_pricelists')
            .where('status', isEqualTo: 'active')
            .orderBy('createdAt', descending: true)
            .get();

    if (mounted) {
      setState(() {
        _availablePricelists =
            snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();

        // Auto-select first pricelist if available
        if (_availablePricelists.isNotEmpty && _selectedPricelistId == null) {
          _selectPricelist(_availablePricelists.first);
        }
      });
    }
  }

  void _selectPricelist(Map<String, dynamic> pricelist) {
    setState(() {
      _selectedPricelistId = pricelist['id'] as String;
      _selectedPricelist = pricelist;
      _allItems.clear();
      _selectedItemIds.clear();
      _runningTotal = 0;

      // Extract items from the pricelist
      final items = pricelist['items'] as List<dynamic>? ?? [];
      for (var i = 0; i < items.length; i++) {
        final item = items[i] as Map<String, dynamic>;
        _allItems.add({...item, 'itemId': '${pricelist['id']}_$i'});
      }
    });
  }

  void _toggleItem(String itemId, double price) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
        _runningTotal -= price;
      } else {
        _selectedItemIds.add(itemId);
        _runningTotal += price;
      }
    });
  }

  bool _isSelected(String itemId) {
    return _selectedItemIds.contains(itemId);
  }

  Future<void> _submitBooking() async {
    if (_selectedItemIds.isEmpty) {
      _showError('Please select at least one item');
      return;
    }

    if (_selectedPricelist == null) {
      _showError('Please select a price list');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showError('Please log in to continue');
      return;
    }

    // Get selected items with full details
    final selectedItems =
        _allItems
            .where((item) => _selectedItemIds.contains(item['itemId']))
            .map(
              (item) => {
                'name': item['name'] ?? 'Unknown',
                'outfitterBasePrice': item['outfitterBasePrice'] ?? 0.0,
                'hunterDisplayPriceZAR': item['hunterDisplayPriceZAR'] ?? 0.0,
              },
            )
            .toList();

    setState(() => _isSubmitting = true);

    try {
      await _pricelistService.submitCustomPackageBooking(
        farmId: _selectedPricelist!['farmId'] as String,
        outfitterId: _selectedPricelist!['outfitterId'] as String,
        selectedItems: selectedItems,
        combinedTotalZAR: _runningTotal,
      );

      if (mounted) {
        _showSuccess('Custom itinerary booking submitted successfully!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to submit booking: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
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
        title: const Text(
          '🦌 Custom Package Builder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: widget.theme.backgroundColor,
        foregroundColor: widget.theme.textColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Price List Selector
          if (_availablePricelists.isNotEmpty) _buildPricelistSelector(),

          // Items List
          Expanded(child: _buildItemsList()),

          // Bottom HUD Sticker Bar
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildPricelistSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        border: Border(
          bottom: BorderSide(
            color: widget.theme.accentColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SELECT PRICE LIST',
            style: TextStyle(
              color: widget.theme.subtitleColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedPricelistId,
            decoration: InputDecoration(
              filled: true,
              fillColor: widget.theme.backgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: widget.theme.accentColor.withValues(alpha: 0.3),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            dropdownColor: widget.theme.cardColor,
            style: TextStyle(color: widget.theme.textColor, fontSize: 14),
            items:
                _availablePricelists.map((pricelist) {
                  return DropdownMenuItem(
                    value: pricelist['id'] as String,
                    child: Text(
                      '${pricelist['farmId'] ?? 'Farm'} - ${pricelist['totalItems'] ?? 0} items',
                    ),
                  );
                }).toList(),
            onChanged: (value) {
              if (value == null) return;
              final pricelist = _availablePricelists.firstWhere(
                (p) => p['id'] == value,
              );
              _selectPricelist(pricelist);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    if (_allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.list_alt_rounded,
              color: widget.theme.accentColor.withValues(alpha: 0.5),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No price lists available',
              style: TextStyle(
                color: widget.theme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Outfitters will upload price lists soon',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allItems.length,
      itemBuilder: (context, index) {
        final item = _allItems[index];
        final itemId = item['itemId'] as String;
        final name = item['name'] as String? ?? 'Unknown';
        final price =
            (item['hunterDisplayPriceZAR'] as num?)?.toDouble() ?? 0.0;
        final isSelected = _isSelected(itemId);

        return Card(
          color: widget.theme.cardColor,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color:
                  isSelected
                      ? widget.theme.accentColor
                      : widget.theme.textColor.withValues(alpha: 0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => _toggleItem(itemId, price),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Checkbox
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleItem(itemId, price),
                    activeColor: widget.theme.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  // Item Name
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),

                  // Price
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? widget.theme.accentColor.withValues(alpha: 0.15)
                              : widget.theme.backgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'R ${price.toStringAsFixed(0)}',
                      style: TextStyle(
                        color:
                            isSelected
                                ? widget.theme.accentColor
                                : widget.theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        border: Border(
          top: BorderSide(
            color: widget.theme.accentColor.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedItemIds.length} items selected',
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Estimated Combined Booking Total:',
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  'R ${_runningTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: widget.theme.accentColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed:
                    _selectedItemIds.isEmpty || _isSubmitting
                        ? null
                        : _submitBooking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.accentColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: widget.theme.accentColor.withValues(
                    alpha: 0.3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child:
                    _isSubmitting
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Text(
                          'Submit Custom Itinerary Booking',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
