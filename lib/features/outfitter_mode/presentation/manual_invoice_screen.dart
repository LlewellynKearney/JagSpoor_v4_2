import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../shared/data/services/local_database_service.dart';
import '../data/services/invoice_pdf_service.dart';

class ManualInvoiceScreen extends StatefulWidget {
  const ManualInvoiceScreen({super.key});

  @override
  State<ManualInvoiceScreen> createState() => _ManualInvoiceScreenState();
}

class _ManualInvoiceScreenState extends State<ManualInvoiceScreen> {
  final LocalDatabaseService _dbService = LocalDatabaseService();
  final _formKey = GlobalKey<FormState>();
  final _clientNameController = TextEditingController();
  final _packageNameController = TextEditingController();
  final _basePriceController = TextEditingController();
  
  final List<Map<String, dynamic>> _extras = [];
  final List<Map<String, dynamic>> _packages = [];
  bool _isGenerating = false;
  bool _isLoading = true;

  static const Color accentGold = Color(0xFFC5A059);
  static const Color deepWalnut = Color(0xFF3E2723);

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    setState(() => _isLoading = true);
    try {
      final db = await _dbService.database;
      final results = await db.query('outfitter_packages', orderBy: 'createdAt DESC');
      setState(() {
        _packages.clear();
        _packages.addAll(results);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading packages: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _packageNameController.dispose();
    _basePriceController.dispose();
    super.dispose();
  }

  void _selectPackage(Map<String, dynamic> package) {
    setState(() {
      _packageNameController.text = package['packageName'] ?? '';
      _basePriceController.text = (package['basePrice'] ?? 0.0).toStringAsFixed(2);
    });
  }

  // SA Game Guide standard animal types for hunting packages
  static const List<Map<String, dynamic>> _availableAnimals = [
    {'name': 'Impala', 'icon': '🦌'},
    {'name': 'Kudu', 'icon': '🐂'},
    {'name': 'Warthog', 'icon': '🐗'},
    {'name': 'Eland', 'icon': '🦬'},
    {'name': 'Blue Wildebeest', 'icon': '🐃'},
    {'name': 'Zebra', 'icon': '🦓'},
    {'name': 'Wildebeest', 'icon': '🐄'},
    {'name': 'Gemsbok', 'icon': '🦏'},
    {'name': 'Springbok', 'icon': '🐇'},
    {'name': 'Blesbok', 'icon': '🦌'},
  ];

  Future<void> _showPackageForm({Map<String, dynamic>? existingPackage}) async {
    final isEditing = existingPackage != null;
    final nameController = TextEditingController(text: isEditing ? (existingPackage['packageName'] ?? '') : '');
    final locationController = TextEditingController(text: isEditing ? (existingPackage['packageLocation'] ?? '') : '');
    final descController = TextEditingController(text: isEditing ? (existingPackage['packageDescription'] ?? '') : '');
    final priceController = TextEditingController(
      text: isEditing ? ((existingPackage['basePrice'] ?? 0.0) as double).toStringAsFixed(2) : '',
    );
    
    // Cost field controllers
    final slaughterFeeController = TextEditingController(text: '0.00');
    final coldroomFeeController = TextEditingController(text: '0.00');
    final bakkieFeeController = TextEditingController(text: '0.00');
    final phFeeController = TextEditingController(text: '0.00');
    
    // Parse existing included animals from JSON
    List<String> selectedAnimals = [];
    if (isEditing && existingPackage['includedAnimalsJson'] != null) {
      try {
        final decoded = _parseIncludedAnimalsJson(existingPackage['includedAnimalsJson']?.toString() ?? '');
        if (decoded['animals'] != null) {
          selectedAnimals = List<String>.from(decoded['animals']);
        }
        if (decoded['slaughterFee'] != null) {
          slaughterFeeController.text = ((decoded['slaughterFee'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
        }
        if (decoded['coldroomFee'] != null) {
          coldroomFeeController.text = ((decoded['coldroomFee'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
        }
        if (decoded['bakkieFee'] != null) {
          bakkieFeeController.text = ((decoded['bakkieFee'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
        }
        if (decoded['phFee'] != null) {
          phFeeController.text = ((decoded['phFee'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
        }
      } catch (_) {}
    }
    
    DateTime? startDate;
    DateTime? endDate;
    if (isEditing) {
      final startVal = existingPackage['startDate'];
      final endVal = existingPackage['endDate'];
      if (startVal != null) startDate = DateTime.tryParse(startVal.toString());
      if (endVal != null) endDate = DateTime.tryParse(endVal.toString());
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 
                      MediaQuery.of(sheetContext).padding.bottom + 16,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'EDIT PACKAGE' : 'NEW PACKAGE',
                    style: const TextStyle(color: accentGold, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 16),
                  
                  // Package Name
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Package Name',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Location
                  TextField(
                    controller: locationController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Hunting Location / Farm Region',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Description
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Package Description',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Animal Selection Section
                  const Text(
                    'INCLUDED ANIMALS (SA Game Guide)',
                    style: TextStyle(color: accentGold, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableAnimals.map((animal) {
                      final isSelected = selectedAnimals.contains(animal['name']);
                      return FilterChip(
                        selected: isSelected,
                        label: Text('${animal['icon']} ${animal['name']}'),
                        labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 12),
                        backgroundColor: const Color(0xFF2A2A2A),
                        selectedColor: accentGold,
                        checkmarkColor: Colors.black,
                        onSelected: (selected) {
                          setSheetState(() {
                            if (selected) {
                              selectedAnimals.add(animal['name']);
                            } else {
                              selectedAnimals.remove(animal['name']);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  
                  // Cost Fields Section
                  const Text(
                    'PACKAGE COSTS (ZAR)',
                    style: TextStyle(color: accentGold, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  
                  // Base Price
                  TextField(
                    controller: priceController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Base Package Price',
                      prefixText: 'R ',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Cost row: Slaughter & Coldroom
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: slaughterFeeController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Slaughter Fee',
                            prefixText: 'R ',
                            labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: coldroomFeeController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Coldroom Fee',
                            prefixText: 'R ',
                            labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Cost row: Bakkie & PH
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: bakkieFeeController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Bakkie Fee',
                            prefixText: 'R ',
                            labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: phFeeController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'PH Fee',
                            prefixText: 'R ',
                            labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Date Row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setSheetState(() => startDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Start Date',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                            ),
                            child: Text(
                              startDate != null 
                                ? '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}'
                                : 'Select date',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: endDate ?? DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setSheetState(() => endDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'End Date',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                            ),
                            child: Text(
                              endDate != null 
                                ? '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}'
                                : 'Select date',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Selected animals summary
                  if (selectedAnimals.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pets, color: accentGold, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Animals: ${selectedAnimals.join(', ')}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: accentGold),
                      onPressed: () async {
                        if (nameController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Package name required'), backgroundColor: Colors.orange),
                          );
                          return;
                        }
                        
                        // Build includedAnimalsJson
                        final includedAnimalsJson = _buildIncludedAnimalsJson(
                          selectedAnimals,
                          double.tryParse(slaughterFeeController.text) ?? 0,
                          double.tryParse(coldroomFeeController.text) ?? 0,
                          double.tryParse(bakkieFeeController.text) ?? 0,
                          double.tryParse(phFeeController.text) ?? 0,
                        );
                        
                        final now = DateTime.now().toIso8601String();
                        final packageData = {
                          'packageName': nameController.text,
                          'packageLocation': locationController.text,
                          'packageDescription': descController.text,
                          'basePrice': double.tryParse(priceController.text) ?? 0.0,
                          'includedAnimalsJson': includedAnimalsJson,
                          'startDate': startDate?.toIso8601String(),
                          'endDate': endDate?.toIso8601String(),
                          if (isEditing) 'updatedAt': now else 'createdAt': now,
                        };
                        
                        try {
                          final db = await _dbService.database;
                          if (isEditing) {
                            await db.update(
                              'outfitter_packages',
                              packageData,
                              where: 'id = ?',
                              whereArgs: [existingPackage['id']],
                            );
                          } else {
                            packageData['id'] = DateTime.now().millisecondsSinceEpoch.toString();
                            await db.insert('outfitter_packages', packageData);
                          }
                          if (!mounted) return;
                          Navigator.pop(sheetContext);
                          await _loadPackages();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error saving package: $e'), backgroundColor: Colors.red),
                          );
                        }
                      },
                      child: Text(isEditing ? 'UPDATE PACKAGE' : 'CREATE PACKAGE', 
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // Parse JSON string for included animals and costs
  Map<String, dynamic> _parseIncludedAnimalsJson(String jsonStr) {
    final result = <String, dynamic>{};
    try {
      // Simple JSON parsing - extract animals array
      final animalsMatch = RegExp(r'"animals":\[(.*?)\]').firstMatch(jsonStr);
      if (animalsMatch != null) {
        final animalsStr = animalsMatch.group(1) ?? '';
        final animals = animalsStr
            .split(',')
            .map((s) => s.trim().replaceAll('"', ''))
            .where((s) => s.isNotEmpty)
            .toList();
        result['animals'] = animals;
      }
      // Extract numeric values
      final slaughterMatch = RegExp(r'"slaughterFee":([0-9.]+)').firstMatch(jsonStr);
      if (slaughterMatch != null) {
        result['slaughterFee'] = double.tryParse(slaughterMatch.group(1) ?? '0') ?? 0;
      }
      final coldroomMatch = RegExp(r'"coldroomFee":([0-9.]+)').firstMatch(jsonStr);
      if (coldroomMatch != null) {
        result['coldroomFee'] = double.tryParse(coldroomMatch.group(1) ?? '0') ?? 0;
      }
      final bakkieMatch = RegExp(r'"bakkieFee":([0-9.]+)').firstMatch(jsonStr);
      if (bakkieMatch != null) {
        result['bakkieFee'] = double.tryParse(bakkieMatch.group(1) ?? '0') ?? 0;
      }
      final phMatch = RegExp(r'"phFee":([0-9.]+)').firstMatch(jsonStr);
      if (phMatch != null) {
        result['phFee'] = double.tryParse(phMatch.group(1) ?? '0') ?? 0;
      }
    } catch (_) {}
    return result;
  }
  
  // Build JSON string for included animals and costs
  String _buildIncludedAnimalsJson(
    List<String> animals,
    double slaughterFee,
    double coldroomFee,
    double bakkieFee,
    double phFee,
  ) {
    final animalsStr = animals.map((a) => '"$a"').join(',');
    return '{"animals":[$animalsStr],"slaughterFee":$slaughterFee,"coldroomFee":$coldroomFee,"bakkieFee":$bakkieFee,"phFee":$phFee,"totalFees":${slaughterFee + coldroomFee + bakkieFee + phFee}}';
  }

  Future<void> _deletePackage(String packageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Package?', style: TextStyle(color: Colors.white)),
        content: const Text('This action cannot be undone.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final db = await _dbService.database;
        await db.delete('outfitter_packages', where: 'id = ?', whereArgs: [packageId]);
        await _loadPackages();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Package deleted'), backgroundColor: Colors.green),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _addExtra() {
    showDialog(
      context: context,
      builder: (context) {
        final nameController = TextEditingController();
        final priceController = TextEditingController();
        final qtyController = TextEditingController(text: '1');
        
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Add Extra Item', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (ZAR)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accentGold),
              onPressed: () {
                if (nameController.text.isNotEmpty && priceController.text.isNotEmpty) {
                  setState(() {
                    _extras.add({
                      'name': nameController.text,
                      'price': double.tryParse(priceController.text) ?? 0.0,
                      'multiplier': int.tryParse(qtyController.text) ?? 1,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add', style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      },
    );
  }

  void _removeExtra(int index) {
    setState(() {
      _extras.removeAt(index);
    });
  }

  Future<void> _generateInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isGenerating = true);
    
    try {
      final pdfBytes = await InvoicePdfService.generateInvoice(
        clientName: _clientNameController.text,
        packageName: _packageNameController.text,
        packageBasePrice: double.tryParse(_basePriceController.text) ?? 0.0,
        extras: _extras,
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(pdfBytes);
      
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Jagspoor Invoice - ${_clientNameController.text}'),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice generated successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating invoice: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('PRICE CATALOG & INVOICING', 
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
        backgroundColor: deepWalnut,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showPackageForm(),
            tooltip: 'Add Package',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Package Management Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PACKAGE MANAGEMENT',
                  style: TextStyle(color: accentGold, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_circle, color: accentGold, size: 18),
                  label: const Text('NEW', style: TextStyle(color: accentGold)),
                  onPressed: () => _showPackageForm(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: accentGold))
            else if (_packages.isEmpty)
              Card(
                color: const Color(0xFF1A1A1A),
                child: ListTile(
                  title: const Text('No packages yet', style: TextStyle(color: Colors.grey)),
                  subtitle: const Text('Tap + to create your first package', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: const Icon(Icons.inventory_2, color: Colors.grey),
                ),
              )
            else
              ...List.generate(_packages.length, (index) {
                final pkg = _packages[index];
                return Card(
                  color: const Color(0xFF1A1A1A),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(pkg['packageName'] ?? 'Unnamed', 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (pkg['packageLocation'] != null && pkg['packageLocation'].toString().isNotEmpty)
                              Text('📍 ${pkg['packageLocation']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            if (pkg['packageDescription'] != null && pkg['packageDescription'].toString().isNotEmpty)
                              Text(pkg['packageDescription'], style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (pkg['startDate'] != null || pkg['endDate'] != null)
                              Text(
                                '📅 ${pkg['startDate'] ?? '?'} → ${pkg['endDate'] ?? '?'}',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'R ${(pkg['basePrice'] ?? 0.0).toStringAsFixed(2)}',
                              style: const TextStyle(color: accentGold, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                                  onPressed: () => _showPackageForm(existingPackage: pkg),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                  onPressed: () => _deletePackage(pkg['id']),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _selectPackage(pkg),
                      ),
                    ],
                  ),
                );
              }),
            
            const SizedBox(height: 24),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),

            // Invoice Form Section
            const Text(
              'GENERATE INVOICE',
              style: TextStyle(color: accentGold, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _clientNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Client Name',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                prefixIcon: Icon(Icons.person, color: accentGold),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _packageNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Package Name',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                prefixIcon: Icon(Icons.inventory, color: accentGold),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _basePriceController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Base Price (ZAR)',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                prefixIcon: Icon(Icons.attach_money, color: accentGold),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            
            const SizedBox(height: 24),
            
            // Extras Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'FIELD EXTRAS',
                  style: TextStyle(color: accentGold, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: accentGold),
                  onPressed: _addExtra,
                ),
              ],
            ),
            ..._extras.asMap().entries.map((entry) {
              final idx = entry.key;
              final extra = entry.value;
              final withMarkup = (extra['price'] as double) * 1.05;
              return Card(
                color: const Color(0xFF1A1A1A),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(extra['name'], style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Qty: ${extra['multiplier']} × R ${withMarkup.toStringAsFixed(2)} (incl. 5% markup)',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeExtra(idx),
                  ),
                ),
              );
            }),
            
            const SizedBox(height: 24),
            
            // Generate Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGold,
                minimumSize: const Size(double.infinity, 56),
              ),
              onPressed: _isGenerating ? null : _generateInvoice,
              icon: _isGenerating 
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.picture_as_pdf, color: Colors.black),
              label: Text(
                _isGenerating ? 'GENERATING...' : 'GENERATE PDF INVOICE',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            
            const SizedBox(height: 16),
            const Center(
              child: Text(
                '5% marketplace commission included',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
