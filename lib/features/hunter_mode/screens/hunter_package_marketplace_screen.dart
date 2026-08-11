import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../services/package_booking_manager.dart';
import '../services/outfitter_analytics_service.dart';
import '../services/chat_and_filter_service.dart';

// ── PayFast SANDBOX configuration ──────────────────────────────────────────
// PayFast's published sandbox test credentials (NOT production secrets).
// Replace merchant_id/merchant_key/host with live values before launch.
const String _kPayfastSandboxHost = 'https://sandbox.payfast.co.za';
const String _kPayfastSandboxMerchantId = '10000100';
const String _kPayfastSandboxMerchantKey = '46f0cd694581a';
// Instant Transaction Notification endpoint — deployed payfastITNHandler
// Cloud Function. Update region/host after deploy.
const String _kPayfastNotifyUrl =
    'https://us-central1-jagspoor.cloudfunctions.net/payfastITNHandler';
const String _kPayfastReturnUrl = 'https://jagspoor.web.app/booking-success';
const String _kPayfastCancelUrl = 'https://jagspoor.web.app/booking-cancelled';

class HunterPackageMarketplaceScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterPackageMarketplaceScreen({super.key, required this.theme});

  @override
  State<HunterPackageMarketplaceScreen> createState() =>
      _HunterPackageMarketplaceScreenState();
}

class _HunterPackageMarketplaceScreenState
    extends State<HunterPackageMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedProvince;
  late TabController _tabController;

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
          // Tab Bar
          Container(
            color: theme.cardColor,
            child: TabBar(
              controller: _tabController,
              labelColor: theme.accentColor,
              unselectedLabelColor: theme.subtitleColor,
              indicatorColor: theme.accentColor,
              tabs: const [
                Tab(text: '📦 Packages'),
                Tab(text: '💬 My Bookings'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Packages Tab
                _buildPackagesTab(theme),
                // My Bookings Tab with Chat
                _buildMyBookingsTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackagesTab(ThemeController theme) {
    return Column(
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
            stream: OutfitterAnalyticsService.instance
                .getFilteredPackagesStream(province: _selectedProvince),
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
                  final packageId = packageData['packageId'] as String? ?? '';
                  final data =
                      packageData['packageData'] as Map<String, dynamic>? ??
                      <String, dynamic>{};
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
    );
  }

  Widget _buildMyBookingsTab(ThemeController theme) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return Center(
        child: Text(
          'Please sign in to view your bookings',
          style: TextStyle(color: theme.textColor),
        ),
      );
    }

    return StreamBuilder(
      stream:
          FirebaseFirestore.instance
              .collection('bookings')
              .where('hunterId', isEqualTo: currentUserId)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.green),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading bookings',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Sort bookings in-memory by timestamp (descending)
        final docs = snapshot.data?.docs ?? [];
        final bookings = List<QueryDocumentSnapshot>.from(docs)..sort((a, b) {
          final aTime = a['bookingTimestamp'] as Timestamp?;
          final bTime = b['bookingTimestamp'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        if (bookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.book_online_rounded,
                  color: theme.accentColor.withValues(alpha: 0.5),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'No bookings yet',
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Book a package to start chatting with outfitters',
                  style: TextStyle(color: theme.subtitleColor),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final booking = bookings[index];
            final data = booking.data() as Map<String, dynamic>;
            final bookingId = booking.id;

            return _HunterBookingCard(
              bookingId: bookingId,
              data: data,
              theme: theme,
            );
          },
        );
      },
    );
  }

  void _showBookingSheet(
    BuildContext context,
    String packageId,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _BookingConfirmationSheet(
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
    final title = data['title'] as String? ?? 'Untitled Package';
    final description = data['description'] as String? ?? '';
    final price = (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
                style: TextStyle(color: theme.subtitleColor, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Inclusions Tags
              if (inclusions.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      inclusions.take(4).map((item) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: theme.accentColor.withValues(alpha: 0.3),
                            ),
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
  State<_BookingConfirmationSheet> createState() =>
      _BookingConfirmationSheetState();
}

class _BookingConfirmationSheetState extends State<_BookingConfirmationSheet> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.data['title'] as String? ?? 'Untitled Package';
    final basePrice = (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
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
              Icon(
                Icons.book_online_rounded,
                color: widget.theme.accentColor,
                size: 28,
              ),
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
            style: TextStyle(color: widget.theme.accentColor, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // Price Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.theme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.theme.accentColor.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                // Base Package Rate
                _PriceRow(
                  label: 'Base Package Rate',
                  value:
                      'R ${basePrice.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                ),
                const Divider(height: 20),

                // 5% Platform Admin Fee
                _PriceRow(
                  label: '5% Platform Admin Fee',
                  value:
                      'R ${commission.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                  isFee: true,
                ),
                const Divider(height: 20),

                // Final Booking Total
                _PriceRow(
                  label: 'Booking Total',
                  value:
                      'R ${totalPrice.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
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
                    side: BorderSide(
                      color: widget.theme.accentColor.withValues(alpha: 0.5),
                    ),
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
                  child:
                      _isLoading
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
      final basePrice = (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;

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
            color:
                isFee
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

class _HunterBookingCard extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> data;
  final ThemeController theme;

  const _HunterBookingCard({
    required this.bookingId,
    required this.data,
    required this.theme,
  });

  @override
  State<_HunterBookingCard> createState() => _HunterBookingCardState();
}

class _HunterBookingCardState extends State<_HunterBookingCard> {
  bool _isChatExpanded = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending Approval':
        return Colors.orange;
      case 'Approved':
        return Colors.green;
      case 'Declined':
        return Colors.red;
      case 'Completed':
        return Colors.blue;
      case 'Cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  /// Toggles the chat drawer open/closed.
  void _toggleChatDrawer() {
    setState(() {
      _isChatExpanded = !_isChatExpanded;
    });
  }

  /// Unread-message envelope indicator for the card header.
  ///
  /// Driven by the booking's `hunterHasUnread` flag (written by the chat
  /// flow when the outfitter sends a message the hunter hasn't seen). When
  /// the flag is true the `Icons.mail` icon is highlighted in orange;
  /// otherwise it stays muted grey. Tapping it opens the chat drawer.
  Widget _buildUnreadMailIndicator() {
    final hasUnread = (widget.data['hunterHasUnread'] as bool?) ?? false;
    return InkWell(
      onTap: () => _toggleChatDrawer(),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          Icons.mail,
          color: hasUnread ? Colors.orange : Colors.grey,
          size: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.data['status'] as String? ?? 'Pending Approval';
    final packageName =
        widget.data['packageName'] as String? ?? 'Custom Package';
    final totalPrice = (widget.data['totalHunterPriceRands'] as num?)?.toDouble() ?? 0.0;

    // PayFast checkout eligibility: render the Pay button when the booking is
    // awaiting payment (case-insensitive) and has a non-zero price. Price is
    // resolved from totalHunterPriceRands, falling back to totalPriceZAR.
    final payfastAmount =
        (widget.data['totalHunterPriceRands'] as num?)?.toDouble() ??
            (widget.data['totalPriceZAR'] as num?)?.toDouble() ??
            0.0;
    final statusLower = status.toLowerCase();
    // The Pay button is strictly hidden when there is nothing to pay.
    // payfastAmount <= 0 (incl. 0, negative, or NaN) forces showPayButton false.
    final isPayableStatus = statusLower == 'pending_payment' ||
        statusLower == 'pending_deposit' ||
        statusLower == 'approved';
    final isPayableAmount = payfastAmount > 0;
    final showPayButton = isPayableStatus && isPayableAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor(status).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.book_online_rounded,
                    color: _getStatusColor(status),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        packageName,
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildUnreadMailIndicator(),
                const SizedBox(width: 8),
                Text(
                  'R ${totalPrice.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

          // 💬 Chat & Negotiation Thread Panel
          _buildChatDrawer(),

          // 💳 PayFast checkout — shown only for payable bookings.
          if (showPayButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payment_rounded, color: Colors.white),
                  label: const Text('Pay via PayFast'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _initiatePayFastCheckout(
                    bookingId: widget.bookingId,
                    amount: payfastAmount,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the PayFast sandbox payment URL from the booking details and
  /// launches it in the external browser. The booking id is passed as
  /// `m_payment_id` so the ITN handler can reconcile it back to the booking.
  Future<void> _initiatePayFastCheckout({
    required String bookingId,
    required double amount,
  }) async {
    final params = <String, String>{
      'merchant_id': _kPayfastSandboxMerchantId,
      'merchant_key': _kPayfastSandboxMerchantKey,
      'return_url': _kPayfastReturnUrl,
      'cancel_url': _kPayfastCancelUrl,
      'notify_url': _kPayfastNotifyUrl,
      'm_payment_id': bookingId,
      'amount': amount.toStringAsFixed(2),
      'item_name': 'JagSpoor Booking $bookingId',
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final urlString = '$_kPayfastSandboxHost/eng/process?$query';
    final uri = Uri.parse(urlString);

    if (!await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open PayFast checkout')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildChatDrawer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: widget.theme.accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Expandable Header
          InkWell(
            onTap: () => _toggleChatDrawer(),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.theme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.chat_rounded,
                      color: widget.theme.accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '💬 Open Chat & Negotiation Thread',
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _isChatExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: widget.theme.accentColor,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),

          // Expandable Chat Content
          if (_isChatExpanded)
            Container(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Chat Messages Stream
                  SizedBox(
                    height: 200,
                    child: StreamBuilder(
                      stream:
                          FirebaseFirestore.instance
                              .collection('bookings')
                              .doc(widget.bookingId)
                              .collection('chats')
                              .orderBy('timestamp', descending: false)
                              .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.green,
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error loading chat',
                              style: TextStyle(color: Colors.red),
                            ),
                          );
                        }

                        final messages = snapshot.data?.docs ?? [];
                        if (messages.isEmpty) {
                          return Center(
                            child: Text(
                              'No messages yet - start the conversation!',
                              style: TextStyle(
                                color: widget.theme.subtitleColor,
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _chatScrollController,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index].data();
                            final senderId = msg['senderId'] as String? ?? '';
                            final isMe =
                                senderId ==
                                FirebaseAuth.instance.currentUser?.uid;

                            return _ChatBubbleHunter(
                              text: msg['text'] as String? ?? '',
                              senderName:
                                  msg['senderName'] as String? ?? 'Unknown',
                              isMe: isMe,
                              theme: widget.theme,
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Chat Input Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          style: TextStyle(color: widget.theme.textColor),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(
                              color: widget.theme.subtitleColor,
                            ),
                            filled: true,
                            fillColor: widget.theme.backgroundColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: widget.theme.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                          ),
                          onPressed: _sendChatMessage,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    try {
      await ChatAndFilterService.instance.sendChatMessage(
        bookingId: widget.bookingId,
        messageText: text,
        senderName: FirebaseAuth.instance.currentUser?.displayName ?? 'Hunter',
      );
      _chatController.clear();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ChatBubbleHunter extends StatelessWidget {
  final String text;
  final String senderName;
  final bool isMe;
  final ThemeController theme;

  const _ChatBubbleHunter({
    required this.text,
    required this.senderName,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color:
              isMe ? theme.accentColor.withValues(alpha: 0.2) : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color:
                isMe
                    ? theme.accentColor.withValues(alpha: 0.3)
                    : theme.accentColor.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                senderName,
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(color: theme.textColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
