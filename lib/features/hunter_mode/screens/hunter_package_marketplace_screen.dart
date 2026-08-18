import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/booking_status.dart';
import '../models/package_pricing.dart';
import '../services/booking_calendar_service.dart';
import '../services/package_booking_manager.dart';
import '../services/outfitter_analytics_service.dart';
import '../services/chat_and_filter_service.dart';
import '../services/pricing_math.dart';

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

  late final TabController _tabController;
  String? _selectedProvince;

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
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, SafeBottomInset.of(context)),
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
        const CopyrightFooter(),
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
      stream: FirebaseFirestore.instance
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
        final bookings = List<QueryDocumentSnapshot>.from(docs)
          ..sort((a, b) {
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

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, SafeBottomInset.of(context)),
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
              ),
            ),
            const CopyrightFooter(),
          ],
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
    final title = data['title'] as String? ?? 'Untitled Package';
    final description = data['description'] as String? ?? '';
    final price = (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    // Hunter-facing total: equals the base package cost (there is no platform
    // commission). For legacy documents that carry a marked-up `totalPriceZAR`
    // (written by a prior version that applied a 7.5% commission), the base
    // price is preferred so the card reflects the base package cost.
    final totalPrice = PricingMath.resolveHunterTotal(
      totalHunterPrice: (data['totalPriceZAR'] as num?)?.toDouble(),
      basePrice: price,
    );
    final inclusions = List<String>.from(data['inclusions'] ?? []);

    // Inventory / sold-out state (Item #11). Legacy packages default to 1 slot.
    final quantityAvailable =
        PackageQuantity.fromData(data['quantityAvailable']);
    final statusStr = data['status'] as String?;
    final isSoldOut = PackageQuantity.isSoldOut(
      quantityAvailable: quantityAvailable,
      status: statusStr,
    );

    // Pricing mode + breakdown details for the marketplace card.
    final pricing = PackagePricing.fromMap(data);
    final isItemized = pricing.mode == PackagePricingMode.itemized;
    final speciesCount = pricing.speciesItems.length;
    final lineItemCount = pricing.lineItems.length;

    // Availability window.
    final startDate = pricing.availabilityStart;
    final endDate = pricing.availabilityEnd;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'R ${totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Text(
                          'total price',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isSoldOut) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'SOLD OUT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
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

              // Package gallery (uploaded images, if any).
              _buildGallery(theme),
              const SizedBox(height: 12),

              // Pricing mode + species + availability meta row.
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _metaChip(
                    theme,
                    icon: isItemized
                        ? Icons.list_alt_rounded
                        : Icons.payments_rounded,
                    label: isItemized ? 'Itemized' : 'All-Inclusive',
                  ),
                  if (speciesCount > 0)
                    _metaChip(
                      theme,
                      icon: Icons.pets_rounded,
                      label: '$speciesCount species'
                          '${lineItemCount > 0 ? ' · $lineItemCount items' : ''}',
                    )
                  else if (lineItemCount > 0)
                    _metaChip(
                      theme,
                      icon: Icons.list_alt_rounded,
                      label: '$lineItemCount items',
                    ),
                  if (startDate != null)
                    _metaChip(
                      theme,
                      icon: Icons.event_available_rounded,
                      label: BookingCalendarEventBuilder.formatDateRange(
                              start: startDate, end: endDate) ??
                          'Select dates',
                    ),
                  _metaChip(
                    theme,
                    icon: isSoldOut
                        ? Icons.do_not_disturb_on_rounded
                        : Icons.confirmation_number_rounded,
                    label: PackageQuantity.remainingLabel(quantityAvailable),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Inclusions Tags
              if (inclusions.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: inclusions.take(4).map((item) {
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

              // Book Button (disabled + relabelled when sold out).
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSoldOut ? null : onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isSoldOut ? Colors.grey : const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSoldOut
                            ? Icons.do_not_disturb_rounded
                            : Icons.book_online_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSoldOut ? 'SOLD OUT' : 'VIEW DETAILS & BOOK',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _metaChip(ThemeController theme,
      {required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.accentColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: theme.subtitleColor,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal strip of uploaded package gallery images. Returns an empty
  /// [SizedBox] when the package has no images so the card layout is unchanged.
  Widget _buildGallery(ThemeController theme) {
    final raw = data['imageUrls'];
    final urls =
        raw is List ? raw.whereType<String>().toList() : const <String>[];
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: urls[index],
              fit: BoxFit.cover,
              width: 128,
              height: 96,
              placeholder: (_, __) => Container(
                width: 128,
                color: theme.backgroundColor,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                width: 128,
                color: theme.backgroundColor,
                child: Icon(Icons.broken_image, color: theme.subtitleColor),
              ),
            ),
          );
        },
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
    final basePrice =
        (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    // Hunter-facing total — derived via the single-source PricingMath helper.
    // The total equals the base package cost (there is no platform commission
    // and no deposit split).
    final totalPrice = PricingMath.resolveHunterTotal(
      totalHunterPrice: (widget.data['totalPriceZAR'] as num?)?.toDouble(),
      basePrice: basePrice,
    );

    final pricing = PackagePricing.fromMap(widget.data);
    final inclusions = List<String>.from(widget.data['inclusions'] ?? []);

    // Inventory / sold-out state for the booking sheet.
    final quantityAvailable =
        PackageQuantity.fromData(widget.data['quantityAvailable']);
    final isSoldOut = PackageQuantity.isSoldOut(
      quantityAvailable: quantityAvailable,
      status: widget.data['status'] as String?,
    );

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
      child: SingleChildScrollView(
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
                    'Package Details',
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
            const SizedBox(height: 12),

            // Pricing mode + availability summary.
            _packageMetaSummary(pricing),
            const SizedBox(height: 16),

            // Itemized / all-inclusive breakdown.
            _breakdownSection(pricing, inclusions, basePrice),
            const SizedBox(height: 16),

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
                  // Hunter-facing total — the total equals the base package
                  // cost (there is no platform commission).
                  _PriceRow(
                    label: 'Total Price',
                    value: _formatZAR(totalPrice),
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
                      'Booking request is sent for outfitter approval. On '
                      'approval the total price is due to confirm your dates.',
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

            // Sold-out banner (only when no slots remain).
            if (isSoldOut)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.do_not_disturb_on_rounded,
                        color: Colors.red, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This package is sold out and can no longer be booked. '
                        'Please choose another package or contact the outfitter '
                        'about future availability.',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

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
                    onPressed:
                        (_isLoading || isSoldOut) ? null : _confirmBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isSoldOut ? Colors.grey : const Color(0xFF1565C0),
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
                                'BOOK THIS PACKAGE',
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
      ),
    );
  }

  /// Compact meta summary: pricing mode + availability window.
  Widget _packageMetaSummary(PackagePricing pricing) {
    final isItemized = pricing.mode == PackagePricingMode.itemized;
    final start = pricing.availabilityStart;
    final end = pricing.availabilityEnd;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _summaryChip(
          icon: isItemized ? Icons.list_alt_rounded : Icons.payments_rounded,
          label: isItemized ? 'Itemized Package' : 'All-Inclusive Package',
        ),
        if (start != null)
          _summaryChip(
            icon: Icons.event_available_rounded,
            label: 'Available ${BookingCalendarEventBuilder.formatDateRange(start: start, end: end) ?? ''}',
          ),
      ],
    );
  }

  Widget _summaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.theme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: widget.theme.accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: widget.theme.subtitleColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive itemized / all-inclusive breakdown view.
  Widget _breakdownSection(
      PackagePricing pricing, List<String> inclusions, double basePrice) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  color: widget.theme.accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                pricing.mode == PackagePricingMode.itemized
                    ? 'ITEMIZED BREAKDOWN'
                    : 'ALL-INCLUSIVE PACKAGE',
                style: TextStyle(
                  color: widget.theme.subtitleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (pricing.mode == PackagePricingMode.itemized) ...[
            if (pricing.lineItems.isEmpty && pricing.speciesItems.isEmpty)
              Text(
                'No itemized lines published.',
                style: TextStyle(
                    color: widget.theme.subtitleColor,
                    fontStyle: FontStyle.italic,
                    fontSize: 13),
              ),
            ...pricing.lineItems.map((item) => _breakdownLine(
                  label: item.label,
                  detail:
                      '${item.quantity} × R ${item.pricePerUnit.toStringAsFixed(2)}',
                  total: item.total,
                )),
            if (pricing.lineItems.isNotEmpty && pricing.speciesItems.isNotEmpty)
              const Divider(height: 16),
            ...pricing.speciesItems.map((species) => _breakdownLine(
                  label: species.speciesName,
                  icon: Icons.pets_rounded,
                  detail:
                      '${species.quantity} × R ${species.pricePerAnimal.toStringAsFixed(2)} / animal',
                  total: species.total,
                )),
          ] else ...[
            _breakdownLine(
              label: 'All-Inclusive Total',
              icon: Icons.payments_rounded,
              detail: 'Single package price',
              total: pricing.allInclusivePrice,
            ),
            if (pricing.speciesItems.isNotEmpty) ...[
              const Divider(height: 16),
              Text(
                'ADVERTISED SPECIES',
                style: TextStyle(
                  color: widget.theme.subtitleColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              ...pricing.speciesItems.map((species) => _breakdownLine(
                    label: species.speciesName,
                    icon: Icons.pets_rounded,
                    detail:
                        '${species.quantity} × R ${species.pricePerAnimal.toStringAsFixed(2)} / animal',
                    total: species.total,
                  )),
            ],
          ],
          if (inclusions.isNotEmpty) ...[
            const Divider(height: 16),
            Text(
              'INCLUSIONS',
              style: TextStyle(
                color: widget.theme.subtitleColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: inclusions.map((item) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.theme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: widget.theme.accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      color: widget.theme.accentColor,
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _breakdownLine({
    required String label,
    required String detail,
    required double total,
    IconData icon = Icons.circle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: widget.theme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    color: widget.theme.subtitleColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'R ${total.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.green,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatZAR(double value) =>
      'R ${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  Future<void> _confirmBooking() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final outfitterId = widget.data['outfitterId'] as String?;
      final basePrice =
          (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
      final packageName = widget.data['title'] as String?;

      if (outfitterId == null) {
        throw Exception('Invalid package: missing outfitter ID');
      }

      await PackageBookingManager.instance.bookPackage(
        packageId: widget.packageId,
        outfitterId: outfitterId,
        basePriceRands: basePrice,
        packageName: packageName,
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
        // Surface a clear "sold out" message when the transaction rejected
        // the booking due to no remaining slots.
        final soldOut = e is PackageSoldOutException;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(soldOut
                ? '❌ This package is sold out and can no longer be booked.'
                : '❌ Booking failed: $e'),
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
  final bool isTotal;

  const _PriceRow({
    required this.label,
    required this.value,
    required this.theme,
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
            color: isTotal ? Colors.green : theme.textColor,
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
      case BookingStatus.pendingApproval:
        return Colors.orange;
      case BookingStatus.approvedAwaitingPayment:
        return Colors.amber.shade700;
      case 'Approved': // legacy -- treat like awaiting payment
        return Colors.amber.shade700;
      case BookingStatus.confirmed:
        return Colors.green;
      case BookingStatus.completed:
        return Colors.blue;
      case BookingStatus.declined:
        return Colors.red;
      case BookingStatus.cancelled:
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

  /// Saves the finalized (Confirmed / Completed) booking's hunt dates, farm
  /// details, and package title to the device's native calendar via
  /// [BookingCalendarService]. Surfaces a snackbar on success / "no dates"
  /// / failure so the hunter always gets feedback.
  Future<void> _addToCalendar() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // Resolve the hunt window ONCE from the SAME booking map the UI card
      // reads through, then bake the resolved start/end directly into the
      // payload. This guarantees the calendar service never has to guess or
      // re-parse: every date alias (startDate / endDate / availabilityStart /
      // availabilityEnd) carries the already-resolved DateTime, so the
      // service's resolver finds a value regardless of which alias family it
      // scans. The doc `id` is also injected (it lives on the
      // QueryDocumentSnapshot, not inside the data map) so the event
      // description can reference the Booking ID (buildDescription reads
      // booking['id']).
      //
      // Alias priority is preserved: higher-priority keys
      // (confirmedStartDate / checkInDate) still win over the injected
      // startDate / availabilityStart, so a post-date-change-approval date
      // is never clobbered by this injection.
      final window = BookingCalendarEventBuilder.resolveWindow(widget.data);
      final payload = {
        ...widget.data,
        if (window != null) ...{
          'startDate': window.start,
          'endDate': window.end,
          'availabilityStart': window.start,
          'availabilityEnd': window.end,
        },
        'id': widget.bookingId,
      };
      // VALIDATION GATE: resolve the window from the FINAL payload (not just
      // widget.data) so the check reflects exactly what the calendar service
      // will resolve. If the window resolves successfully, NEVER show the
      // "No hunt dates on file" warning -- force straight through to the
      // platform calendar. A subsequent `launched == false` can then only
      // mean the device calendar rejected the event (no calendar app,
      // permission denied, user cancel), which is reported accurately below
      // -- never as a false-positive "no dates" warning.
      final resolvedWindow =
          BookingCalendarEventBuilder.resolveWindow(payload);
      if (resolvedWindow == null) {
        if (!mounted) return;
        if (messenger != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                  'No hunt dates on file for this booking -- cannot add to calendar.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final launched =
          await BookingCalendarService.instance.addToCalendar(payload);
      if (!mounted) return;
      final snackBar = SnackBar(
        content: Text(
          launched
              ? 'Opening your calendar to save this hunt...'
              // The window WAS resolved, so a `false` here means the device
              // calendar rejected the event (no calendar app, permission
              // denied, user cancel) -- NOT a missing-dates problem.
              : 'Could not open your device calendar. Check that a calendar '
                  'app is installed and permissions are granted.',
        ),
        backgroundColor: launched ? Colors.green : Colors.orange,
      );
      if (messenger != null) messenger.showSnackBar(snackBar);
    } catch (e) {
      if (!mounted) return;
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Unable to add to calendar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    final status =
        widget.data['status'] as String? ?? BookingStatus.pendingApproval;
    final packageName =
        widget.data['packageName'] as String? ?? 'Custom Package';
    final basePrice =
        (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    // Hunter-facing total: equals the base booking cost (there is no platform
    // commission). For legacy bookings that carry a marked-up
    // `totalHunterPriceRands` (written by a prior version that applied a 7.5%
    // commission), the base price is preferred so the card reflects the base
    // booking cost.
    final totalPrice = PricingMath.resolveHunterTotal(
      totalHunterPrice:
          (widget.data['totalHunterPriceRands'] as num?)?.toDouble(),
      basePrice: basePrice,
    );
    final statusLower = status.toLowerCase();

    // Date-change request visibility: hunter may request a date change once
    // the booking has been accepted by the outfitter (awaiting payment or
    // confirmed -- i.e. dates matter). Hide if a request is already pending.
    final dateChangePending =
        (widget.data['dateChangeRequestPending'] as bool?) ?? false;
    final dateChangeMap =
        widget.data['dateChangeRequest'] as Map<String, dynamic>?;
    final dateChange =
        dateChangeMap != null ? DateChangeRequest.fromMap(dateChangeMap) : null;
    final isPostApproval = statusLower == 'approved' ||
        statusLower == 'awaiting payment' ||
        statusLower == 'confirmed';
    final canRequestDateChange = isPostApproval && !dateChangePending;
    // The "Add to Calendar" action is offered once the booking is finalized
    // (Confirmed / Completed) -- i.e. the outfitter has verified the direct
    // payment and the hunt dates are locked in.
    final canAddToCalendar = statusLower == 'confirmed' ||
        statusLower == 'completed';

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
                          BookingStatus.hunterBadgeLabel(status).toUpperCase(),
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

          // Hunt dates row: surfaces the booking's hunt window (start -> end)
          // copied from the package's availability dates at booking time so
          // the hunter can see the dates on the card AND the "Add to
          // Calendar" action resolves them without a separate package read.
          // Hidden when the booking has no dates on file.
          Builder(
            builder: (context) {
              final window =
                  BookingCalendarEventBuilder.resolveWindow(widget.data);
              if (window == null) return const SizedBox.shrink();
              // Single source of truth for the date-range label format —
              // `d MMM yyyy – d MMM yyyy` (or one date for a single-day
              // hunt). Mirrors the outfitter banner exactly.
              final dateLabel =
                  BookingCalendarEventBuilder.formatWindow(window) ??
                      'No hunt dates on file';
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.theme.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: widget.theme.accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_rounded,
                          color: widget.theme.accentColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hunt dates: $dateLabel',
                          style: TextStyle(
                            color: widget.theme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Date-change request status banner.
          if (dateChange != null && !dateChange.isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _dateChangeResolvedBanner(dateChange),
            ),
          if (dateChangePending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _dateChangePendingBanner(),
            ),

          // 💬 Chat & Negotiation Thread Panel
          _buildChatDrawer(),

          // 📅 Request Date Change button.
          if (canRequestDateChange)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_repeat_rounded, size: 20),
                  label: const Text('Request Date Change'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.theme.accentColor,
                    side: BorderSide(
                      color: widget.theme.accentColor.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _showDateChangeRequestSheet(),
                ),
              ),
            ),

          // 💬 Direct action button for off-platform payment communication:
          // in-app chat with the outfitter. Lets the hunter coordinate the
          // direct payment with the outfitter through the booking's embedded
          // chat thread.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _toggleChatDrawer,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.theme.accentColor,
                      side: BorderSide(color: widget.theme.accentColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 20),
                    label: const Text(
                      'IN-APP CHAT',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 📅 Add to Calendar: offered once the booking is finalized
          // (Confirmed / Completed) so the hunter can save the hunt dates,
          // farm details, and package title to their phone's native calendar.
          if (canAddToCalendar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addToCalendar,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.event_available_rounded, size: 20),
                  label: const Text(
                    'ADD HUNT TO CALENDAR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateChangePendingBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded,
              color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Date change request sent — awaiting outfitter decision.',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateChangeResolvedBanner(DateChangeRequest request) {
    final approved = request.status == 'approved';
    final color = approved ? Colors.green : Colors.red;
    final verb = approved ? 'approved' : 'declined';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(approved ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your date change request was $verb.',
              style: TextStyle(
                color: color.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet collecting the hunter's requested new dates + reason,
  /// submitted via [PackageBookingManager.requestDateChange].
  void _showDateChangeRequestSheet() {
    DateTime? newStart;
    DateTime? newEnd;
    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              bottom: true,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              widget.theme.subtitleColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.event_repeat_rounded,
                            color: widget.theme.accentColor, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Request Date Change',
                          style: TextStyle(
                            color: widget.theme.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Propose new dates for your outfitter to approve or decline.',
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _dateChangeDateChip(
                            label: 'New Start Date',
                            value: newStart,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: newStart ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 730)),
                              );
                              if (picked != null) {
                                setSheetState(() {
                                  newStart = picked;
                                  if (newEnd != null &&
                                      newEnd!.isBefore(picked)) {
                                    newEnd = picked;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dateChangeDateChip(
                            label: 'New End Date',
                            value: newEnd,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    newEnd ?? newStart ?? DateTime.now(),
                                firstDate: newStart ?? DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 730)),
                              );
                              if (picked != null) {
                                setSheetState(() {
                                  newEnd = picked;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonController,
                      style: TextStyle(color: widget.theme.textColor),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Reason for date change (optional)...',
                        hintStyle: TextStyle(color: widget.theme.subtitleColor),
                        filled: true,
                        fillColor: widget.theme.backgroundColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color:
                                widget.theme.accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: widget.theme.textColor,
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
                            onPressed: () async {
                              if (newStart == null && newEnd == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Please select at least one new date'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              try {
                                await PackageBookingManager.instance
                                    .requestDateChange(
                                  bookingId: widget.bookingId,
                                  request: DateChangeRequest(
                                    requestedStartDate: newStart,
                                    requestedEndDate: newEnd,
                                    reason: reasonController.text.trim(),
                                  ),
                                );
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          '✅ Date change request sent to outfitter'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('❌ Failed: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.theme.accentColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('SEND REQUEST',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
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

  Widget _dateChangeDateChip({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: widget.theme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.event_rounded,
                color: widget.theme.accentColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: widget.theme.subtitleColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    value != null
                        ? BookingCalendarEventBuilder.formatDate(value)
                        : 'Select date',
                    style: TextStyle(
                      color: value != null
                          ? widget.theme.textColor
                          : widget.theme.subtitleColor,
                      fontSize: 13,
                      fontWeight:
                          value != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                      stream: FirebaseFirestore.instance
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
                            final isMe = senderId ==
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
            color: isMe
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
