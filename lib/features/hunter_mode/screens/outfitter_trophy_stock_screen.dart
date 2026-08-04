import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../services/user_role_resolver.dart';

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

  String? _selectedFarmId;
  String? _selectedFarmName;
  bool _isSyncing = false;
  bool _isManager = false;

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
        _selectedFarmName =
            (farmDoc.data() as Map<String, dynamic>?)?['name'] ??
            'Unknown Farm';
      });
    }
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _countController.dispose();
    _priceController.dispose();
    super.dispose();
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

      await OutfitterEnterpriseManager.instance.syncTrophyStock(
        farmId: _selectedFarmId!,
        species: _speciesController.text.trim(),
        availableCount: count,
        pricePerTrophyRands: price,
      );

      if (mounted) {
        _speciesController.clear();
        _countController.clear();
        _priceController.clear();
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
      appBar: AppBar(
        title: const Text(
          '🥩 Trophy Inventory Stock',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Trophy Stock Sync Form
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.2),
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
                            color: theme.subtitleColor,
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
                                  color: theme.subtitleColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                filled: true,
                                fillColor:
                                    _isManager
                                        ? theme.accentColor.withValues(
                                          alpha: 0.1,
                                        )
                                        : theme.backgroundColor,
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
                            color: theme.subtitleColor,
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
                              color: theme.subtitleColor.withValues(alpha: 0.5),
                            ),
                            filled: true,
                            fillColor: theme.backgroundColor,
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
                                color: theme.accentColor.withValues(alpha: 0.3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: theme.accentColor.withValues(alpha: 0.3),
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
                                      color: theme.subtitleColor,
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
                                        color: theme.subtitleColor.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: theme.backgroundColor,
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
                                      color: theme.subtitleColor,
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
                                        color: theme.subtitleColor.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      prefixText: 'R ',
                                      prefixStyle: TextStyle(
                                        color: theme.textColor,
                                      ),
                                      filled: true,
                                      fillColor: theme.backgroundColor,
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
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.2),
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
                          .collection('trophies')
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
                                style: TextStyle(color: theme.subtitleColor),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: trophies.length,
                      separatorBuilder:
                          (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final trophy = trophies[index];
                        final data = trophy.data() as Map<String, dynamic>;
                        final species = data['species'] ?? 'Unknown';
                        final count = data['availableCount'] ?? 0;
                        final price =
                            (data['pricePerTrophyRands'] ?? 0).toDouble();
                        final farmId = data['farmId'] ?? '';

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  count > 0
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
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
                                  Icons.pets_rounded,
                                  color: theme.accentColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      species,
                                      style: TextStyle(
                                        color: theme.textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Farm: ${farmId.substring(0, farmId.length > 6 ? 6 : farmId.length)}...',
                                      style: TextStyle(
                                        color: theme.subtitleColor,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          count > 0
                                              ? Colors.green.withValues(
                                                alpha: 0.2,
                                              )
                                              : Colors.red.withValues(
                                                alpha: 0.2,
                                              ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$count available',
                                      style: TextStyle(
                                        color:
                                            count > 0
                                                ? Colors.green
                                                : Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'R ${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
