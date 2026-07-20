import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';

class AmmunitionTypeSelectionScreen extends StatefulWidget {
  final ThemeController theme;
  final Map<String, String> firearm;

  const AmmunitionTypeSelectionScreen({
    super.key,
    required this.theme,
    required this.firearm,
  });

  @override
  State<AmmunitionTypeSelectionScreen> createState() =>
      _AmmunitionTypeSelectionScreenState();
}

class _AmmunitionTypeSelectionScreenState
    extends State<AmmunitionTypeSelectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _muzzleVelocityController = TextEditingController();
  final _primerController = TextEditingController();

  bool _showFactoryForm = false;
  bool _showCustomForm = false;
  String? _editingDocId;

  // Factory Loads selection state
  String? _selectedBrand;
  int? _selectedGrain;
  String? _selectedDescription;

  // Custom Loads selection state
  String? _selectedBulletBrand;
  int? _selectedBulletWeight;
  String? _selectedPropellantBrand;
  String? _selectedPropellantType;

  Future<List<QuerySnapshot>>? _bulletsAndPropellantsFuture;
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  bool isCaliberMatch(String? weaponCaliber, String? dbCaliber) {
    if (weaponCaliber == null || dbCaliber == null) return false;
    String clean(String s) =>
        s.replaceAll(RegExp(r'[\s\-\.]'), '').toLowerCase();
    String wClean = clean(weaponCaliber);
    String dClean = clean(dbCaliber);
    if ((wClean == "243" || wClean == "6mm") &&
        (dClean.contains("243") || dClean.contains("6mm"))) {
      return true;
    }
    return wClean.contains(dClean) || dClean.contains(wClean);
  }

  @override
  void dispose() {
    _muzzleVelocityController.dispose();
    _primerController.dispose();
    super.dispose();
  }

  void _initCustomLoadData() {
    _bulletsAndPropellantsFuture = Future.wait([
      FirebaseFirestore.instance.collection('bullets').get(),
      FirebaseFirestore.instance.collection('propellants').get(),
    ]);
  }

  Future<void> _saveFactoryConfiguration() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBrand == null ||
        _selectedGrain == null ||
        _selectedDescription == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select all ammunition specifications.'),
        ),
      );
      return;
    }

    final userId = _currentUserId;
    final firearmId = widget.firearm['docId'];
    if (userId == null || firearmId == null) return;

    try {
      final collectionRef = FirebaseFirestore.instance
          .collection('firearms')
          .doc(firearmId)
          .collection('ammunition');

      final data = {
        'brand': _selectedBrand,
        'caliber': widget.firearm['caliber'],
        'bulletgrain': _selectedGrain,
        'description': _selectedDescription,
        'muzzleVelocity':
            int.tryParse(_muzzleVelocityController.text.trim()) ?? 0,
        'type': 'factory',
      };

      if (_editingDocId != null) {
        await collectionRef.doc(_editingDocId).update(data);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ammunition configuration updated!')),
        );
      } else {
        final docRef = collectionRef.doc();
        await docRef.set({
          'id': docRef.id,
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ammunition configuration saved!')),
        );
      }

      _resetForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  Future<void> _saveCustomConfiguration() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBulletBrand == null ||
        _selectedBulletWeight == null ||
        _selectedPropellantBrand == null ||
        _selectedPropellantType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select all bullet and propellant specifications.',
          ),
        ),
      );
      return;
    }

    final userId = _currentUserId;
    final firearmId = widget.firearm['docId'];
    if (userId == null || firearmId == null) return;

    try {
      final collectionRef = FirebaseFirestore.instance
          .collection('firearms')
          .doc(firearmId)
          .collection('ammunition');

      final data = {
        'bulletBrand': _selectedBulletBrand,
        'caliber': widget.firearm['caliber'],
        'bulletWeight': _selectedBulletWeight,
        'propellantBrand': _selectedPropellantBrand,
        'propellantType': _selectedPropellantType,
        'muzzleVelocity':
            int.tryParse(_muzzleVelocityController.text.trim()) ?? 0,
        'primer': _primerController.text.trim(),
        'type': 'custom',
      };

      if (_editingDocId != null) {
        await collectionRef.doc(_editingDocId).update(data);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ammunition configuration updated!')),
        );
      } else {
        final docRef = collectionRef.doc();
        await docRef.set({
          'id': docRef.id,
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ammunition configuration saved!')),
        );
      }

      _resetForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  void _resetForm() {
    setState(() {
      _showFactoryForm = false;
      _showCustomForm = false;
      _editingDocId = null;
      _selectedBrand = null;
      _selectedGrain = null;
      _selectedDescription = null;

      _selectedBulletBrand = null;
      _selectedBulletWeight = null;
      _selectedPropellantBrand = null;
      _selectedPropellantType = null;

      _muzzleVelocityController.clear();
      _primerController.clear();
    });
  }

  void _editFactoryVariation(String id, Map<String, dynamic> data) {
    setState(() {
      _showFactoryForm = true;
      _showCustomForm = false;
      _editingDocId = id;
      _selectedBrand = data['brand']?.toString();
      _selectedGrain = int.tryParse(
        data['bulletgrain']?.toString() ??
            data['bulletGrain']?.toString() ??
            '',
      );
      _selectedDescription = data['description']?.toString();
      _muzzleVelocityController.text = (data['muzzleVelocity'] ?? '')
          .toString();
    });
  }

  void _editCustomVariation(String id, Map<String, dynamic> data) {
    setState(() {
      _showFactoryForm = false;
      _showCustomForm = true;
      _editingDocId = id;
      _initCustomLoadData();
      _selectedBulletBrand = data['bulletBrand']?.toString();
      _selectedBulletWeight = int.tryParse(
        data['bulletWeight']?.toString() ??
            data['weightgr']?.toString() ??
            data['weightGr']?.toString() ??
            '',
      );
      _selectedPropellantBrand = data['propellantBrand']?.toString();
      _selectedPropellantType =
          data['propellantType']?.toString() ??
          data['typename']?.toString() ??
          data['typeName']?.toString();
      _muzzleVelocityController.text = (data['muzzleVelocity'] ?? '')
          .toString();
      _primerController.text = data['primer']?.toString() ?? '';
    });
  }

  Future<void> _deleteVariation(String id) async {
    final userId = _currentUserId;
    final firearmId = widget.firearm['docId'];
    if (userId == null || firearmId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.backgroundColor,
        title: Text(
          'DELETE VARIATION',
          style: TextStyle(
            color: widget.theme.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to remove this ammunition variation?',
          style: TextStyle(color: widget.theme.textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'CANCEL',
              style: TextStyle(color: widget.theme.subtitleColor),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('firearms')
            .doc(firearmId)
            .collection('ammunition')
            .doc(id)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ammunition variation deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting variation: $e')),
          );
        }
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
          _editingDocId != null
              ? 'EDIT LOAD CONFIG'
              : (_showFactoryForm
                    ? 'FACTORY LOAD SETUP'
                    : (_showCustomForm
                          ? 'CUSTOM LOAD SETUP'
                          : 'SELECT LOAD TYPE')),
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Firearm Profile Summary Card
              Card(
                color: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACTIVE RIFLE PROFILE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.accentColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.firearm['make']} ${widget.firearm['model']}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Caliber: ${widget.firearm['caliber']}',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (!_showFactoryForm && !_showCustomForm) ...[
                // Load Type Selection Cards
                _buildChoiceCard(
                  title: 'FACTORY AMMUNITION',
                  subtitle:
                      'Select pre-loaded brand and spec database profiles matching caliber.',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => setState(() => _showFactoryForm = true),
                ),
                const SizedBox(height: 16),
                _buildChoiceCard(
                  title: 'CUSTOM HANDLOADS',
                  subtitle:
                      'Define custom cases, propellants, charge weights, and custom bullets.',
                  icon: Icons.science_outlined,
                  onTap: () {
                    setState(() {
                      _showCustomForm = true;
                      _initCustomLoadData();
                    });
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'SAVED AMMUNITION VARIATIONS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.subtitleColor,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSavedVariationsList(),
              ] else if (_showFactoryForm) ...[
                // Factory Ammunition Cascading Form
                Form(
                  key: _formKey,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('factory_ammunition')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(
                          'Error loading options',
                          style: TextStyle(color: theme.subtitleColor),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allAmmo = snapshot.data?.docs ?? [];
                      final caliber = widget.firearm['caliber'] ?? '';
                      final filteredAmmo = allAmmo.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final ammoCal = data['caliber']?.toString() ?? '';
                        return isCaliberMatch(caliber, ammoCal);
                      }).toList();

                      if (filteredAmmo.isEmpty) {
                        return _buildEmptyAmmoWarning();
                      }

                      final brands = filteredAmmo
                          .map(
                            (doc) =>
                                (doc.data() as Map<String, dynamic>)['brand']
                                    ?.toString() ??
                                '',
                          )
                          .where((b) => b.isNotEmpty)
                          .toSet()
                          .toList();

                      if (brands.length == 1 && _selectedBrand == null) {
                        final firstBrand = brands.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedBrand == null) {
                            setState(() => _selectedBrand = firstBrand);
                          }
                        });
                      }

                      final grains = filteredAmmo
                          .where(
                            (doc) =>
                                (doc.data() as Map<String, dynamic>)['brand'] ==
                                _selectedBrand,
                          )
                          .map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final grainVal =
                                data['bulletgrain'] ?? data['bulletGrain'];
                            return int.tryParse(grainVal?.toString() ?? '') ??
                                0;
                          })
                          .where((g) => g > 0)
                          .toSet()
                          .toList();

                      if (grains.length == 1 && _selectedGrain == null) {
                        final firstGrain = grains.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedGrain == null) {
                            setState(() => _selectedGrain = firstGrain);
                          }
                        });
                      }

                      final descriptions = filteredAmmo
                          .where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final grainVal =
                                data['bulletgrain'] ?? data['bulletGrain'];
                            final grainInt =
                                int.tryParse(grainVal?.toString() ?? '') ?? 0;
                            return data['brand'] == _selectedBrand &&
                                grainInt == _selectedGrain;
                          })
                          .map(
                            (doc) =>
                                (doc.data()
                                        as Map<String, dynamic>)['description']
                                    ?.toString() ??
                                '',
                          )
                          .where((d) => d.isNotEmpty)
                          .toSet()
                          .toList();

                      if (descriptions.length == 1 &&
                          _selectedDescription == null) {
                        final firstDesc = descriptions.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedDescription == null) {
                            setState(() => _selectedDescription = firstDesc);
                          }
                        });
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: brands.contains(_selectedBrand) ? _selectedBrand : null,
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Brand'),
                            onChanged: (val) {
                              setState(() {
                                _selectedBrand = val;
                                _selectedGrain = null;
                                _selectedDescription = null;
                              });
                            },
                            items: brands.map((b) {
                              return DropdownMenuItem<String>(
                                value: b,
                                child: Text(
                                  b,
                                  style: TextStyle(color: theme.textColor),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String>(
                            initialValue: widget.firearm['caliber'],
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Caliber (Read-Only)'),
                            onChanged: null,
                            items: [
                              DropdownMenuItem<String>(
                                value: widget.firearm['caliber'],
                                child: Text(
                                  widget.firearm['caliber'] ?? '',
                                  style: TextStyle(color: theme.subtitleColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<int>(
                            initialValue: grains.contains(_selectedGrain) ? _selectedGrain : null,
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Bullet Grain'),
                            onChanged: _selectedBrand == null
                                ? null
                                : (val) {
                                    setState(() {
                                      _selectedGrain = val;
                                      _selectedDescription = null;
                                    });
                                  },
                            items: grains.map((g) {
                              return DropdownMenuItem<int>(
                                value: g,
                                child: Text(
                                  '$g gr',
                                  style: TextStyle(color: theme.textColor),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String>(
                            initialValue: descriptions.contains(_selectedDescription) ? _selectedDescription : null,
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Description'),
                            onChanged: _selectedGrain == null
                                ? null
                                : (val) {
                                    setState(() => _selectedDescription = val);
                                  },
                            items: descriptions.map((d) {
                              return DropdownMenuItem<String>(
                                value: d,
                                child: Text(
                                  d,
                                  style: TextStyle(color: theme.textColor),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _muzzleVelocityController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: theme.textColor),
                            decoration: _inputDecoration('Muzzle Velocity')
                                .copyWith(
                                  suffixText: 'fps',
                                  suffixStyle: TextStyle(
                                    color: theme.accentColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Muzzle velocity is required';
                              }
                              if (int.tryParse(val.trim()) == null) {
                                return 'Please enter a valid number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          ElevatedButton(
                            onPressed: _saveFactoryConfiguration,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.accentColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              _editingDocId != null
                                  ? 'UPDATE CONFIGURATION'
                                  : 'SAVE LOAD CONFIGURATION',
                              style: TextStyle(
                                color: theme.backgroundColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          OutlinedButton(
                            onPressed: _resetForm,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.textColor,
                              side: BorderSide(
                                color: theme.accentColor.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('BACK'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ] else if (_showCustomForm) ...[
                // Custom Handload Form
                Form(
                  key: _formKey,
                  child: FutureBuilder<List<QuerySnapshot>>(
                    future: _bulletsAndPropellantsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(
                          'Error loading custom options',
                          style: TextStyle(color: theme.subtitleColor),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final bulletsDocs = snapshot.data?[0].docs ?? [];
                      final propellantsDocs = snapshot.data?[1].docs ?? [];

                      // Filter bullets by caliber using semantic matching
                      final caliber = widget.firearm['caliber'] ?? '';
                      final filteredBullets = bulletsDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final bulletCal = data['caliber']?.toString() ?? '';
                        return isCaliberMatch(caliber, bulletCal);
                      }).toList();

                      // Compute bullet brands
                      final bulletBrands = filteredBullets
                          .map(
                            (doc) =>
                                (doc.data() as Map<String, dynamic>)['brand']
                                    ?.toString() ??
                                '',
                          )
                          .where((b) => b.isNotEmpty)
                          .toSet()
                          .toList();

                      if (bulletBrands.length == 1 &&
                          _selectedBulletBrand == null) {
                        final firstBulletBrand = bulletBrands.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedBulletBrand == null) {
                            setState(() => _selectedBulletBrand = firstBulletBrand);
                          }
                        });
                      }

                      // Compute bullet weights based on brand
                      final bulletWeights = filteredBullets
                          .where(
                            (doc) =>
                                (doc.data() as Map<String, dynamic>)['brand'] ==
                                _selectedBulletBrand,
                          )
                          .map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final weightVal =
                                data['weightgr'] ?? data['weightGr'];
                            return int.tryParse(weightVal?.toString() ?? '') ??
                                0;
                          })
                          .where((w) => w > 0)
                          .toSet()
                          .toList();

                      if (bulletWeights.length == 1 &&
                          _selectedBulletWeight == null) {
                        final firstBulletWeight = bulletWeights.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedBulletWeight == null) {
                            setState(() => _selectedBulletWeight = firstBulletWeight);
                          }
                        });
                      }

                      // Compute propellant brands
                      final propellantBrands = propellantsDocs
                          .map(
                            (doc) =>
                                (doc.data() as Map<String, dynamic>)['brand']
                                    ?.toString() ??
                                '',
                          )
                          .where((b) => b.isNotEmpty)
                          .toSet()
                          .toList();

                      if (propellantBrands.length == 1 &&
                          _selectedPropellantBrand == null) {
                        final firstPropellantBrand = propellantBrands.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedPropellantBrand == null) {
                            setState(() => _selectedPropellantBrand = firstPropellantBrand);
                          }
                        });
                      }

                      // Compute propellant type names based on brand
                      final propellantTypes = propellantsDocs
                          .where(
                            (doc) =>
                                (doc.data() as Map<String, dynamic>)['brand'] ==
                                _selectedPropellantBrand,
                          )
                          .map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return (data['typename'] ?? data['typeName'] ?? '')
                                .toString();
                          })
                          .where((t) => t.isNotEmpty)
                          .toSet()
                          .toList();

                      if (propellantTypes.length == 1 &&
                          _selectedPropellantType == null) {
                        final firstPropellantType = propellantTypes.first;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedPropellantType == null) {
                            setState(() => _selectedPropellantType = firstPropellantType);
                          }
                        });
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: bulletBrands.contains(_selectedBulletBrand) ? _selectedBulletBrand : null,
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Bullet Brand'),
                            onChanged: (val) {
                              setState(() {
                                _selectedBulletBrand = val;
                                _selectedBulletWeight = null;
                              });
                            },
                            items: bulletBrands.map((b) {
                              return DropdownMenuItem<String>(
                                value: b,
                                child: Text(
                                  b,
                                  style: TextStyle(color: theme.textColor),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String>(
                            initialValue: widget.firearm['caliber'],
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Caliber (Read-Only)'),
                            onChanged: null,
                            items: [
                              DropdownMenuItem<String>(
                                value: widget.firearm['caliber'],
                                child: Text(
                                  widget.firearm['caliber'] ?? '',
                                  style: TextStyle(color: theme.subtitleColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<int>(
                            initialValue: bulletWeights.contains(_selectedBulletWeight) ? _selectedBulletWeight : null,
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Bullet Weight'),
                            onChanged: _selectedBulletBrand == null
                                ? null
                                : (val) {
                                    setState(() => _selectedBulletWeight = val);
                                  },
                            items: bulletWeights.map((w) {
                              return DropdownMenuItem<int>(
                                value: w,
                                child: Text(
                                  '$w gr',
                                  style: TextStyle(color: theme.textColor),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String>(
                            initialValue: propellantBrands.contains(_selectedPropellantBrand) ? _selectedPropellantBrand : null,
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration('Propellant Brand'),
                            onChanged: (val) {
                              setState(() {
                                _selectedPropellantBrand = val;
                                _selectedPropellantType = null;
                              });
                            },
                            items: propellantBrands.map((pb) {
                              return DropdownMenuItem<String>(
                                value: pb,
                                child: Text(
                                  pb,
                                  style: TextStyle(color: theme.textColor),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String>(
                            initialValue: propellantTypes.contains(_selectedPropellantType) ? _selectedPropellantType : null,
                            dropdownColor: theme.backgroundColor,
                            decoration: _inputDecoration(
                              'Propellant Powder/Type',
                            ),
                            onChanged: _selectedPropellantBrand == null
                                ? null
                                : (val) {
                                    setState(
                                      () => _selectedPropellantType = val,
                                    );
                                  },
                            items: propellantTypes.map((pt) {
                              return DropdownMenuItem<String>(
                                value: pt,
                                child: Text(
                                  pt,
                                  style: TextStyle(color: theme.textColor),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _muzzleVelocityController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: theme.textColor),
                            decoration: _inputDecoration('Muzzle Velocity')
                                .copyWith(
                                  suffixText: 'fps',
                                  suffixStyle: TextStyle(
                                    color: theme.accentColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Muzzle velocity is required';
                              }
                              if (int.tryParse(val.trim()) == null) {
                                return 'Please enter a valid number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _primerController,
                            style: TextStyle(color: theme.textColor),
                            decoration: _inputDecoration(
                              'Primer Used (e.g. CCI 200, Federal 210)',
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Primer specification is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          ElevatedButton(
                            onPressed: _saveCustomConfiguration,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.accentColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              _editingDocId != null
                                  ? 'UPDATE CONFIGURATION'
                                  : 'SAVE CUSTOM LOAD',
                              style: TextStyle(
                                color: theme.backgroundColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          OutlinedButton(
                            onPressed: _resetForm,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.textColor,
                              side: BorderSide(
                                color: theme.accentColor.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('BACK'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    final theme = widget.theme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.subtitleColor),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.accentColor),
      ),
    );
  }

  Widget _buildEmptyAmmoWarning() {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        children: [
          Text(
            'No factory ammunition profiles found in database for caliber "${widget.firearm['caliber']}".',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.subtitleColor,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _resetForm,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.textColor,
              side: BorderSide(color: theme.accentColor),
            ),
            child: const Text('BACK'),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = widget.theme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: theme.accentColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: theme.subtitleColor),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: theme.accentColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedVariationsList() {
    final theme = widget.theme;
    final userId = _currentUserId;
    final firearmId = widget.firearm['docId'];

    if (userId == null || firearmId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('firearms')
          .doc(firearmId)
          .collection('ammunition')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Ammo Stream Error: ${snapshot.error}');
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Error loading variations',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Details: ${snapshot.error.toString()}',
                  style: TextStyle(color: theme.subtitleColor, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Firearm ID: $firearmId',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              'No saved ammunition profiles for this firearm yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.subtitleColor,
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final type = data['type'] ?? 'factory';
            final isCustom = type == 'custom';

            final String primaryLabel;
            final String secondaryLabel;

            if (isCustom) {
              final brand = data['bulletBrand'] ?? 'Unknown';
              final weight = data['bulletWeight'] ?? 'N/A';
              final propBrand = data['propellantBrand'] ?? '';
              final propType = data['propellantType'] ?? '';
              primaryLabel = '$brand ($weight gr) — Handload';
              secondaryLabel =
                  'Powder: $propBrand $propType | Velocity: ${data['muzzleVelocity'] ?? 0} fps';
            } else {
              final brand = data['brand'] ?? 'Unknown';
              final grain = data['bulletgrain'] ?? data['bulletGrain'] ?? 'N/A';
              final desc = data['description'] ?? '';
              primaryLabel = '$brand ($grain gr) — Factory';
              secondaryLabel =
                  '$desc | Velocity: ${data['muzzleVelocity'] ?? 0} fps';
            }

            return Card(
              color: theme.cardColor,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: theme.accentColor.withValues(alpha: 0.2),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                title: Text(
                  primaryLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  secondaryLabel,
                  style: TextStyle(color: theme.subtitleColor, fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.edit_outlined,
                        color: theme.accentColor,
                        size: 20,
                      ),
                      onPressed: () {
                        if (isCustom) {
                          _editCustomVariation(doc.id, data);
                        } else {
                          _editFactoryVariation(doc.id, data);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () => _deleteVariation(doc.id),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
