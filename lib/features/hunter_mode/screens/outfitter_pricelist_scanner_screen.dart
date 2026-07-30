import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pricelist_scanner_service.dart';
import '../services/user_role_resolver.dart';
import 'outfitter_pricelist_verification_screen.dart';

class OutfitterPricelistScannerScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterPricelistScannerScreen({super.key, required this.theme});

  @override
  State<OutfitterPricelistScannerScreen> createState() => _OutfitterPricelistScannerScreenState();
}

class _OutfitterPricelistScannerScreenState extends State<OutfitterPricelistScannerScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final PricelistScannerService _pricelistService = PricelistScannerService.instance;

  String? _selectedFarmId;
  String? _selectedFarmName;
  bool _isLoading = false;
  bool _isManager = false;
  List<Map<String, dynamic>> _farms = [];

  @override
  void initState() {
    super.initState();
    _isManager = UserRoleResolver.instance.isManager;
    if (_isManager && UserRoleResolver.instance.assignedFarmId != null) {
      _selectedFarmId = UserRoleResolver.instance.assignedFarmId;
    }
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final farmsQuery = _isManager
        ? FirebaseFirestore.instance.collection('farms').where('outfitterId', isEqualTo: currentUser.uid)
        : FirebaseFirestore.instance.collection('farms').where('outfitterId', isEqualTo: currentUser.uid);

    final snapshot = await farmsQuery.where('status', isEqualTo: 'active').get();
    
    if (mounted) {
      setState(() {
        _farms = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        
        // Auto-select farm name for managers
        if (_isManager && _selectedFarmId != null) {
          final farm = _farms.firstWhere(
            (f) => f['id'] == _selectedFarmId,
            orElse: () => {'name': 'Unknown'},
          );
          _selectedFarmName = farm['name'] as String?;
        }
      });
    }
  }

  Future<void> _takePhoto() async {
    if (_selectedFarmId == null) {
      _showError('Please select a farm first');
      return;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      
      if (image != null) {
        await _processImage(File(image.path));
      }
    } catch (e) {
      _showError('Failed to capture image: $e');
    }
  }

  Future<void> _chooseFromGallery() async {
    if (_selectedFarmId == null) {
      _showError('Please select a farm first');
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        await _processImage(File(result.files.first.path!));
      }
    } catch (e) {
      _showError('Failed to pick file: $e');
    }
  }

  Future<void> _processImage(File file) async {
    setState(() => _isLoading = true);

    try {
      // Extract items for verification instead of directly saving
      final extractedItems = await _pricelistService.extractPricelistItems(
        farmId: _selectedFarmId!,
        imageFile: file,
      );

      if (mounted && extractedItems.isNotEmpty) {
        // Navigate to verification screen with extracted items
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OutfitterPricelistVerificationScreen(
              theme: widget.theme,
              extractedItems: extractedItems,
              farmId: _selectedFarmId,
              farmName: _selectedFarmName,
              imageFileName: file.path.split('/').last,
            ),
          ),
        );
      } else if (mounted) {
        _showError('No items could be extracted from the image');
      }
    } catch (e) {
      if (mounted) {
        _showError('Processing failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚠️ $message'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $message'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          '📸 AI Price List Scanner',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: widget.theme.backgroundColor,
        foregroundColor: widget.theme.textColor,
        elevation: 0,
      ),
      body: _isLoading ? _buildLoadingState() : _buildMainContent(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              color: widget.theme.accentColor,
              strokeWidth: 4,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'AI Text Analysis Matrix',
            style: TextStyle(
              color: widget.theme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Extracting... Applying 5% Platform Fees...',
            style: TextStyle(
              color: widget.theme.subtitleColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.theme.accentColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.document_scanner_rounded,
                  color: widget.theme.accentColor,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI-DRIVEN PRICE EXTRACTION',
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload or photograph your paper price list to instantly digitize species and pricing data.',
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Farm Selection
          Text(
            'SELECT FARM / CONCESSION',
            style: TextStyle(
              color: widget.theme.subtitleColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: widget.theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isManager 
                    ? widget.theme.accentColor.withValues(alpha: 0.5)
                    : widget.theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: _isManager
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded, color: widget.theme.accentColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFarmName ?? 'Loading...',
                                style: TextStyle(
                                  color: widget.theme.textColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Locked to assigned farm',
                                style: TextStyle(
                                  color: widget.theme.subtitleColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedFarmId,
                      isExpanded: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      hint: Text(
                        'Choose a farm...',
                        style: TextStyle(color: widget.theme.subtitleColor),
                      ),
                      dropdownColor: widget.theme.cardColor,
                      style: TextStyle(color: widget.theme.textColor),
                      items: _farms.map((farm) {
                        return DropdownMenuItem(
                          value: farm['id'] as String,
                          child: Text(farm['name'] as String? ?? 'Unknown'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        final farm = _farms.firstWhere((f) => f['id'] == value);
                        setState(() {
                          _selectedFarmId = value;
                          _selectedFarmName = farm['name'] as String?;
                        });
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 32),

          // Scanning Tools
          Text(
            'SCANNING TOOLS',
            style: TextStyle(
              color: widget.theme.subtitleColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),

          // Take Photo Button
          _buildToolCard(
            icon: Icons.camera_alt_rounded,
            title: '📸 TAKE PHOTO OF PRICE LIST',
            subtitle: 'Use camera to capture physical price list document',
            onTap: _takePhoto,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),

          // Choose from Gallery
          _buildToolCard(
            icon: Icons.folder_open_rounded,
            title: '📂 CHOOSE FROM GALLERY / PDF',
            subtitle: 'Select image or PDF from device storage',
            onTap: _chooseFromGallery,
            color: Colors.orange,
          ),
          const SizedBox(height: 32),

          // Info Panel
          Container(
            padding: const EdgeInsets.all(16),
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '5% platform commission will be automatically applied to all extracted prices.',
                    style: TextStyle(
                      color: widget.theme.subtitleColor,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      color: widget.theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
