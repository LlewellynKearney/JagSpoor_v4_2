import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/package_booking_manager.dart';
import '../services/outfitter_analytics_service.dart';

class HunterPackageMarketplaceScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterPackageMarketplaceScreen({super.key, required this.theme});

  @override
  State<HunterPackageMarketplaceScreen> createState() => _HunterPackageMarketplaceScreenState();
}

class _HunterPackageMarketplaceScreenState extends State<HunterPackageMarketplaceScreen> {
  String? _selectedProvince;

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
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          '🎯 Package Marketplace',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Province Filter Dropdown
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
            child: Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
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
                        icon: Icon(Icons.arrow_drop_down, color: theme.accentColor),
                        items: _provinces.map((province) {
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
                            _selectedProvince = value == 'All Provinces' ? null : value;
                          });
                        },
                      ),
                    ),
                  ),
                ),
                if (_selectedProvince != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.clear_rounded, color: theme.subtitleColor),
                    onPressed: () {
                      setState(() {
                        _selectedProvince = null;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          // Package List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: OutfitterAnalyticsService.instance.getFilteredPackagesStream(
                province: _selectedProvince,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.green),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading packages',
                          style: TextStyle(color: theme.textColor),
                        ),
                      ],
                    ),
                  );
                }

                final packages = snapshot.data ?? [];

                if (packages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.terrain_rounded,
                          color: theme.accentColor.withValues(alpha: 0.5),
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedProvince != null
                              ? 'No packages in $_selectedProvince'
                              : 'No packages available',
                          style: TextStyle(
                            color: theme.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Check back soon for hunting packages',
                          style: TextStyle(color: theme.subtitleColor),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final packageData = packages[index];
                    final packageId = packageData['packageId'] as String;
                    final data = packageData['packageData'] as Map<String, dynamic>;
                    final farmName = packageData['farmName'] as String? ?? '';
                    final province = packageData['province'] as String? ?? '';

                    return _PackageCard(
                      packageId: packageId,
                      data: data,
                      farmName: farmName,
                      province: province,
                      theme: theme,
                      onTap: () => _showBookingSheet(context, packageId, data),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingSheet(BuildContext context, String packageId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingConfirmationSheet(
        packageId: packageId,
        data: data,
        theme: widget.theme,
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final String packageId;
  final Map<String, dynamic> data;
  final String farmName;
  final String province;
  final ThemeController theme;
  final VoidCallback onTap;

  const _PackageCard({
    required this.packageId,
    required this.data,
    required this.farmName,
    required this.province,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = data['title'] ?? 'Untitled Package';
    final description = data['description'] ?? '';
    final price = (data['basePriceRands'] ?? 0).toDouble();
    final inclusions = List<String>.from(data['inclusions'] ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.cabin_rounded,
                      color: theme.accentColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: theme.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Location info
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              color: theme.subtitleColor,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              farmName.isNotEmpty
                                  ? '$farmName${province.isNotEmpty ? ', $province' : ''}'
                                  : province.isNotEmpty
                                      ? province
                                      : 'Location TBD',
                              style: TextStyle(
                                color: theme.subtitleColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'R ${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                description,
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Inclusions Tags
              if (inclusions.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: inclusions.take(4).map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          color: theme.accentColor,
                          fontSize: 11,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (inclusions.length > 4) ...[
                  const SizedBox(height: 4),
                  Text(
                    '+${inclusions.length - 4} more inclusions',
                    style: TextStyle(
                      color: theme.subtitleColor,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),

              // Book Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.book_online_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'BOOK THIS PACKAGE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingConfirmationSheet extends StatefulWidget {
  final String packageId;
  final Map<String, dynamic> data;
  final ThemeController theme;

  const _BookingConfirmationSheet({
    required this.packageId,
    required this.data,
    required this.theme,
  });

  @override
  State<_BookingConfirmationSheet> createState() => _BookingConfirmationSheetState();
}

class _BookingConfirmationSheetState extends State<_BookingConfirmationSheet> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.data['title'] ?? 'Untitled Package';
    final basePrice = (widget.data['basePriceRands'] ?? 0).toDouble();
    final commission = basePrice * 0.05;
    final totalPrice = basePrice + commission;

    return Container(
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.theme.subtitleColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              Icon(Icons.book_online_rounded, color: widget.theme.accentColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Confirm Booking',
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: widget.theme.accentColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),

          // Price Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.theme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.theme.accentColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                // Base Package Rate
                _PriceRow(
                  label: 'Base Package Rate',
                  value: 'R ${basePrice.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                ),
                const Divider(height: 20),

                // 5% Platform Admin Fee
                _PriceRow(
                  label: '5% Platform Admin Fee',
                  value: 'R ${commission.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                  isFee: true,
                ),
                const Divider(height: 20),

                // Final Booking Total
                _PriceRow(
                  label: 'Booking Total',
                  value: 'R ${totalPrice.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                  isTotal: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Warning
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Booking will be sent for outfitter approval',
                    style: TextStyle(
                      color: Colors.amber.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.theme.textColor,
                    side: BorderSide(color: widget.theme.accentColor.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _confirmBooking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'CONFIRM BOOKING',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBooking() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final outfitterId = widget.data['outfitterId'] as String?;
      final basePrice = (widget.data['basePriceRands'] ?? 0).toDouble();

      if (outfitterId == null) {
        throw Exception('Invalid package: missing outfitter ID');
      }

      await PackageBookingManager.instance.bookPackage(
        packageId: widget.packageId,
        outfitterId: outfitterId,
        basePriceRands: basePrice,
      );

      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Booking request submitted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Booking failed: $e'),
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
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeController theme;
  final bool isFee;
  final bool isTotal;

  const _PriceRow({
    required this.label,
    required this.value,
    required this.theme,
    this.isFee = false,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
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
            color: isFee
                ? Colors.amber.shade700
                : isTotal
                    ? Colors.green
                    : theme.textColor,
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
