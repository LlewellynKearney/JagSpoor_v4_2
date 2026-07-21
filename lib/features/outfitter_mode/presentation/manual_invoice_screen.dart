import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../data/services/invoice_pdf_service.dart';

class ManualInvoiceScreen extends StatefulWidget {
  const ManualInvoiceScreen({super.key});

  @override
  State<ManualInvoiceScreen> createState() => _ManualInvoiceScreenState();
}

class _ManualInvoiceScreenState extends State<ManualInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientNameController = TextEditingController();
  final _packageNameController = TextEditingController();
  final _basePriceController = TextEditingController();
  
  final List<Map<String, dynamic>> _extras = [];
  bool _isGenerating = false;

  static const Color accentGold = Color(0xFFC5A059);
  static const Color deepWalnut = Color(0xFF3E2723);

  // Sample price catalog for hunting packages
  static const List<Map<String, dynamic>> _priceCatalog = [
    {'name': 'Plains Game Package', 'basePrice': 25000.0, 'description': '5 day plains game hunt'},
    {'name': 'Big Five Package', 'basePrice': 45000.0, 'description': '7 day big five safari'},
    {'name': 'Bird Shooting Package', 'basePrice': 8500.0, 'description': '3 day bird hunting'},
    {'name': 'Trophy Hunt Package', 'basePrice': 55000.0, 'description': '10 day trophy hunt'},
  ];

  @override
  void dispose() {
    _clientNameController.dispose();
    _packageNameController.dispose();
    _basePriceController.dispose();
    super.dispose();
  }

  void _selectPackage(Map<String, dynamic> package) {
    setState(() {
      _packageNameController.text = package['name'];
      _basePriceController.text = package['basePrice'].toStringAsFixed(2);
    });
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

      // Save to temp directory and share
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(pdfBytes);
      
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Jagspoor Invoice - ${_clientNameController.text}'),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating invoice: $e'),
          backgroundColor: Colors.red,
        ),
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
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Price Catalog Section
            const Text(
              'PRICE CATALOG',
              style: TextStyle(color: accentGold, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            ..._priceCatalog.map((pkg) => Card(
              color: const Color(0xFF1A1A1A),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(pkg['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(pkg['description'], style: const TextStyle(color: Colors.grey)),
                trailing: Text(
                  'R ${(pkg['basePrice'] as double).toStringAsFixed(2)}',
                  style: const TextStyle(color: accentGold, fontWeight: FontWeight.bold),
                ),
                onTap: () => _selectPackage(pkg),
              ),
            )),
            
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
