import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';

class HunterTrophyBrowserScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterTrophyBrowserScreen({super.key, required this.theme});

  @override
  State<HunterTrophyBrowserScreen> createState() =>
      _HunterTrophyBrowserScreenState();
}

class _HunterTrophyBrowserScreenState extends State<HunterTrophyBrowserScreen> {
  String? _selectedProvince;
  String _searchQuery = '';
  List<Map<String, dynamic>> _trophies = [];
  final Set<String> _selectedTrophyIds = {};
  bool _isLoading = true;

  // South African provinces
  static const List<String> _provinces = [
    'All Provinces',
    'Limpopo',
    'Mpumalanga',
    'Gauteng',
    'North West',
    'Free State',
    'KwaZulu-Natal',
    'Eastern Cape',
    'Western Cape',
    'Northern Cape',
  ];

  @override
  void initState() {
    super.initState();
    _loadTrophies();
  }

  Future<void> _loadTrophies() async {
    setState(() => _isLoading = true);
    try {
      QuerySnapshot snapshot;

      // Load from unified /trophies collection
      if (_selectedProvince != null &&
          _selectedProvince!.isNotEmpty &&
          _selectedProvince != 'All Provinces') {
        snapshot =
            await FirebaseFirestore.instance
                .collection('trophies')
                .where('province', isEqualTo: _selectedProvince)
                .where('availableCount', isGreaterThan: 0)
                .get();
      } else {
        snapshot =
            await FirebaseFirestore.instance
                .collection('trophies')
                .where('availableCount', isGreaterThan: 0)
                .get();
      }

      final List<Map<String, dynamic>> loadedTrophies = [];

      for (final trophyDoc in snapshot.docs) {
        final trophyData = trophyDoc.data() as Map<String, dynamic>?;
        if (trophyData == null) continue;
        loadedTrophies.add({
          'id': trophyDoc.id,
          'farmId': trophyData['farmId'] ?? '',
          'farmName': trophyData['farmName'] ?? 'Unknown Farm',
          'province': trophyData['province'] ?? '',
          'species': trophyData['species'] ?? 'Unknown',
          'available': trophyData['availableCount'] ?? 0,
          'pricePerTrophy': trophyData['pricePerTrophyRands'] ?? 0.0,
          'sex': trophyData['sex'] ?? 'Mixed',
          'outfitterId': trophyData['outfitterId'] ?? '',
          'imageUrl': trophyData['imageUrl']?.toString() ?? '',
        });
      }

      setState(() {
        _trophies = loadedTrophies;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading trophies: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredTrophies {
    if (_searchQuery.isEmpty) return _trophies;
    return _trophies.where((t) {
      final species = (t['species'] as String).toLowerCase();
      final farm = (t['farmName'] as String).toLowerCase();
      final query = _searchQuery.toLowerCase();
      return species.contains(query) || farm.contains(query);
    }).toList();
  }

  void _toggleTrophySelection(String trophyId) {
    setState(() {
      if (_selectedTrophyIds.contains(trophyId)) {
        _selectedTrophyIds.remove(trophyId);
      } else {
        _selectedTrophyIds.add(trophyId);
      }
    });
  }

  Future<void> _addToBookingLog() async {
    if (_selectedTrophyIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one trophy'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog with selected items
    final selectedTrophies =
        _filteredTrophies
            .where((t) => _selectedTrophyIds.contains(t['id']))
            .toList();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: widget.theme.cardColor,
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Add to Booking Log',
                  style: TextStyle(color: widget.theme.textColor),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected ${selectedTrophies.length} trophy(ies):',
                    style: TextStyle(color: widget.theme.subtitleColor),
                  ),
                  const SizedBox(height: 8),
                  ...selectedTrophies.map(
                    (t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${t['species']} from ${t['farmName']}',
                        style: TextStyle(color: widget.theme.textColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      // TODO: Save to booking log collection
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${selectedTrophies.length} trophy(ies) to your booking log!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _selectedTrophyIds.clear();
      });
    }
  }

  /// High-contrast dark amber bordered fallback visual placeholder container for missing trophy images
  Widget _buildTrophyPlaceholder(ThemeController theme) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF23180C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade800, width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Corner HUD markers
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.amber.shade700, width: 2),
                  left: BorderSide(color: Colors.amber.shade700, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.amber.shade700, width: 2),
                  right: BorderSide(color: Colors.amber.shade700, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.amber.shade700, width: 2),
                  left: BorderSide(color: Colors.amber.shade700, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.amber.shade700, width: 2),
                  right: BorderSide(color: Colors.amber.shade700, width: 2),
                ),
              ),
            ),
          ),
          // Center icon inside dark amber bordered frame
          const Icon(Icons.pets, color: Colors.amber, size: 32),
        ],
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
          '🦌 Trophy Registry & Booking',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        actions: [
          if (_selectedTrophyIds.isNotEmpty)
            TextButton.icon(
              onPressed: _addToBookingLog,
              icon: const Icon(Icons.add_shopping_cart, color: Colors.green),
              label: Text(
                '${_selectedTrophyIds.length} Selected',
                style: const TextStyle(color: Colors.green),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(
                bottom: BorderSide(
                  color: theme.accentColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                // Search Field
                TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: TextStyle(color: theme.textColor),
                  decoration: InputDecoration(
                    hintText: 'Search species or farm...',
                    hintStyle: TextStyle(color: theme.subtitleColor),
                    prefixIcon: Icon(Icons.search, color: theme.accentColor),
                    filled: true,
                    fillColor: theme.backgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Province Filter
                Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: theme.accentColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: theme.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedProvince ?? 'All Provinces',
                            isExpanded: true,
                            dropdownColor: theme.cardColor,
                            style: TextStyle(color: theme.textColor),
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: theme.accentColor,
                            ),
                            items:
                                _provinces.map((province) {
                                  return DropdownMenuItem(
                                    value: province,
                                    child: Text(
                                      province,
                                      style: TextStyle(color: theme.textColor),
                                    ),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedProvince =
                                    value == 'All Provinces' ? null : value;
                              });
                              _loadTrophies();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Trophy List
          Expanded(
            child:
                _isLoading
                    ? const Center(
                      child: CircularProgressIndicator(color: Colors.green),
                    )
                    : _filteredTrophies.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.pets_rounded,
                            color: theme.subtitleColor.withValues(alpha: 0.5),
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No trophies available',
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Outfitters will load trophy stock soon',
                            style: TextStyle(color: theme.subtitleColor),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredTrophies.length,
                      itemBuilder: (context, index) {
                        final trophy = _filteredTrophies[index];
                        final trophyId = trophy['id'] as String;
                        final isSelected = _selectedTrophyIds.contains(
                          trophyId,
                        );
                        final price =
                            (trophy['pricePerTrophy'] as num?)?.toDouble() ??
                            0.0;
                        final available =
                            (trophy['available'] as num?)?.toInt() ?? 0;
                        final String imageUrl =
                            trophy['imageUrl']?.toString() ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: theme.cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color:
                                  isSelected
                                      ? Colors.green
                                      : theme.accentColor.withValues(
                                        alpha: 0.2,
                                      ),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: InkWell(
                            onTap:
                                available > 0
                                    ? () => _toggleTrophySelection(trophyId)
                                    : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Trophy Image with Tactical HUD Placeholder
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.accentColor.withValues(
                                          alpha: 0.5,
                                        ),
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child:
                                          imageUrl.isNotEmpty
                                              ? Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                                cacheWidth: 800,
                                                headers: const {
                                                  'Cache-Control': 'no-cache',
                                                },
                                                errorBuilder: (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) {
                                                  return _buildTrophyPlaceholder(
                                                    theme,
                                                  );
                                                },
                                              )
                                              : _buildTrophyPlaceholder(theme),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Trophy Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (isSelected)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                  size: 18,
                                                ),
                                              ),
                                            Expanded(
                                              child: Text(
                                                trophy['species'] as String? ??
                                                    'Unknown',
                                                style: TextStyle(
                                                  color: theme.textColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on_rounded,
                                              color: theme.subtitleColor,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${trophy['farmName']} • ${trophy['province']}',
                                                style: TextStyle(
                                                  color: theme.subtitleColor,
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    available > 0
                                                        ? Colors.green
                                                            .withValues(
                                                              alpha: 0.2,
                                                            )
                                                        : Colors.red.withValues(
                                                          alpha: 0.2,
                                                        ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                available > 0
                                                    ? '$available Available'
                                                    : 'Sold Out',
                                                style: TextStyle(
                                                  color:
                                                      available > 0
                                                          ? Colors.green
                                                          : Colors.red,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: theme.accentColor
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                trophy['sex'] as String? ??
                                                    'Mixed',
                                                style: TextStyle(
                                                  color: theme.accentColor,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Price
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'R ${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        'per trophy',
                                        style: TextStyle(
                                          color: theme.subtitleColor,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      bottomNavigationBar:
          _selectedTrophyIds.isNotEmpty
              ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: ElevatedButton(
                    onPressed: _addToBookingLog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_shopping_cart),
                        const SizedBox(width: 8),
                        Text(
                          'Add ${_selectedTrophyIds.length} Trophy(ies) to Booking Log',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              : null,
    );
  }
}
