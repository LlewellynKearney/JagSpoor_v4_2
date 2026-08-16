import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../../../core/services/payfast_checkout.dart';
import '../models/package_pricing.dart';
import '../services/package_booking_manager.dart';
import '../services/outfitter_analytics_service.dart';
import '../services/chat_and_filter_service.dart';
import '../services/pricing_math.dart';
import '../services/deposit_payment_simulator.dart';

// PayFast sandbox configuration now lives in a single source:
// `lib/core/services/payfast_checkout.dart` (`PayfastCheckout`), which both
// the marketplace checkout and the custom-package builder route through.

class HunterPackageMarketplaceScreen extends StatefulWidget {
  final ThemeController theme;

  const HunterPackageMarketplaceScreen({super.key, required this.theme});

  @override
  State<HunterPackageMarketplaceScreen> createState() =>
      _HunterPackageMarketplaceScreenState();
}

class _HunterPackageMarketplaceScreenState
    extends State<HunterPackageMarketplaceScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String? _selectedProvince;
  late TabController _tabController;

  /// Set `true` when a PayFast browser checkout is launched so the app-resume
  /// lifecycle listener can detect that the user returned from the external
  /// browser and prompt a booking-status refresh. (v4.5 to-do Item #10.)
  bool _awaitingPayfastReturn = false;

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App-resume PayFast return detection (v4.5 to-do Item #10): when the app
    // resumes from the background (the user returned from the external
    // PayFast browser checkout) and a checkout was launched, prompt the user
    // to refresh/fetch the latest booking status. The bookings list is
    // already a reactive Firestore `snapshots()` stream, so the data auto-
    // updates on resume; this SnackBar is the explicit prompt the spec wants.
    if (state == AppLifecycleState.resumed && _awaitingPayfastReturn) {
      _awaitingPayfastReturn = false;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Welcome back! Verifying your latest booking status from the '
            'PayFast checkout...',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
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
                padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
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
          padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final booking = bookings[index];
            final data = booking.data() as Map<String, dynamic>;
            final bookingId = booking.id;

            return _HunterBookingCard(
              bookingId: bookingId,
              data: data,
              theme: theme,
              onPayFastCheckoutLaunched: () =>
                  _awaitingPayfastReturn = true,
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
                      label: endDate != null
                          ? '${startDate.day}/${startDate.month} – ${endDate.day}/${endDate.month}/${endDate.year}'
                          : 'From ${startDate.day}/${startDate.month}/${startDate.year}',
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

              // Book Button (disabled + relabelled when sold out).
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSoldOut ? null : onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSoldOut
                        ? Colors.grey
                        : const Color(0xFF1565C0),
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
    final urls = raw is List ? raw.whereType<String>().toList() : const <String>[];
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
    final basePrice = (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    // Hunter-facing total + 25% deposit — both derived via the single-source
    // PricingMath helper. The total equals the base package cost (there is no
    // platform commission); no "Platform Fee" line is rendered to the hunter.
    final totalPrice = PricingMath.resolveHunterTotal(
      totalHunterPrice: (widget.data['totalPriceZAR'] as num?)?.toDouble(),
      basePrice: basePrice,
    );
    final depositAmount = PricingMath.depositFromTotal(totalPrice);

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
                  const Divider(height: 20),

                  // Deposit due on approval
                  _PriceRow(
                    label:
                        '25% Deposit (due on approval · non-refundable)',
                    value: _formatZAR(depositAmount),
                    theme: widget.theme,
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
                      'Booking request is sent for outfitter approval. On approval '
                      'a 25% non-refundable deposit is due to confirm your dates.',
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
                    onPressed: (_isLoading || isSoldOut)
                        ? null
                        : _confirmBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSoldOut
                          ? Colors.grey
                          : const Color(0xFF1565C0),
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
          icon: isItemized
              ? Icons.list_alt_rounded
              : Icons.payments_rounded,
          label: isItemized ? 'Itemized Package' : 'All-Inclusive Package',
        ),
        if (start != null)
          _summaryChip(
            icon: Icons.event_available_rounded,
            label: end != null
                ? 'Available ${start.day}/${start.month} – ${end.day}/${end.month}/${end.year}'
                : 'From ${start.day}/${start.month}/${start.year}',
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
            if (pricing.lineItems.isNotEmpty &&
                pricing.speciesItems.isNotEmpty)
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
      final basePrice = (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
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
            color:
                isTotal
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

  /// Invoked when a PayFast browser checkout is launched from this card so the
  /// marketplace screen's app-resume lifecycle listener can detect the user's
  /// return from the external browser and prompt a booking-status refresh.
  /// (v4.5 to-do Item #10.)
  final VoidCallback? onPayFastCheckoutLaunched;

  const _HunterBookingCard({
    required this.bookingId,
    required this.data,
    required this.theme,
    this.onPayFastCheckoutLaunched,
  });

  @override
  State<_HunterBookingCard> createState() => _HunterBookingCardState();
}

class _HunterBookingCardState extends State<_HunterBookingCard> {
  bool _isChatExpanded = false;
  bool _isPaying = false;
  bool _isSimulating = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending Approval':
        return Colors.orange;
      case 'Approved':
      case 'Pending Deposit':
        return Colors.green;
      case 'Paid':
        return Colors.teal;
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
    final basePrice =
        (widget.data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    // Hunter-facing total: equals the base booking cost (there is no platform
    // commission). For legacy bookings that carry a marked-up
    // `totalHunterPriceRands` (written by a prior version that applied a 7.5%
    // commission), the base price is preferred so the card reflects the base
    // booking cost.
    final totalPrice = PricingMath.resolveHunterTotal(
      totalHunterPrice: (widget.data['totalHunterPriceRands'] as num?)?.toDouble(),
      basePrice: basePrice,
    );

    // Deposit flow: when the outfitter approves, the booking moves to
    // `Pending Deposit` and the hunter pays the 25% non-refundable deposit
    // via PayFast. The deposit amount is stored on the booking; if it is
    // missing (legacy bookings), derive it off the total.
    final depositAmount = PricingMath.resolveDeposit(
      storedDeposit: (widget.data['depositAmountRands'] as num?)?.toDouble(),
      total: totalPrice,
    );
    final balanceAmount = (widget.data['balanceAmountRands'] as num?)?.toDouble() ??
        PricingMath.balanceFromTotal(totalPrice);
    final statusLower = status.toLowerCase();

    // PayFast checkout eligibility: render the Pay button when the booking is
    // awaiting the deposit. The canonical post-approval status is
    // `'Pending Deposit'` (space-separated, written by
    // `approveBookingAndRequestDeposit`), so the check is case-insensitive on
    // the space form. The legacy `approved` / `pending_payment` spellings are
    // retained as fallbacks for older booking documents. (v4.5 to-do Item #7
    // — previously this checked the underscore form `'pending_deposit'`,
    // which never matched the canonical space-spelled status, so the deposit
    // button silently failed to render on `Pending Deposit` bookings.)
    final isDepositDueStatus = statusLower == 'pending deposit' ||
        statusLower == 'pending_deposit' ||
        statusLower == 'approved' ||
        statusLower == 'pending_payment';
    final payfastAmount = depositAmount;
    final showPayButton = isDepositDueStatus && payfastAmount > 0;

    // Date-change request visibility: hunter may request a date change once
    // the booking is approved / awaiting deposit / paid (i.e. dates matter).
    // Hide if a request is already pending.
    final dateChangePending =
        (widget.data['dateChangeRequestPending'] as bool?) ?? false;
    final dateChangeMap =
        widget.data['dateChangeRequest'] as Map<String, dynamic>?;
    final dateChange = dateChangeMap != null
        ? DateChangeRequest.fromMap(dateChangeMap)
        : null;
    final canRequestDateChange =
        (statusLower == 'pending_deposit' ||
            statusLower == 'approved' ||
            statusLower == 'paid') &&
            !dateChangePending;

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

          // Deposit breakdown banner (when approved / awaiting deposit).
          if (showPayButton && depositAmount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    _depositRow('Total Price', totalPrice),
                    const SizedBox(height: 4),
                    _depositRow(
                        '25% Non-Refundable Deposit Due', depositAmount,
                        emphasize: true),
                    const SizedBox(height: 4),
                    _depositRow('Balance (settled with outfitter)',
                        balanceAmount),
                  ],
                ),
              ),
            ),

          // 💳 PayFast deposit checkout — prominent primary action rendered
          // directly on the card ABOVE the chat expansion panel so the hunter
          // can pay the 25% deposit without scrolling past the chat thread.
          // Shown only for payable bookings (deposit-due status, deposit > 0).
          // (v4.5 to-do Item #7.)
          if (showPayButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isPaying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.lock_clock_rounded,
                          color: Colors.white),
                  label: Text(
                    depositAmount > 0
                        ? 'Pay 25% Deposit (${PricingMath.formatCurrency(depositAmount)})'
                        : 'Pay via PayFast',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.green.shade700
                        .withValues(alpha: 0.5),
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isPaying
                      ? null
                      : () => _initiatePayFastCheckout(
                            bookingId: widget.bookingId,
                            amount: payfastAmount,
                            itemName: packageName,
                          ),
                ),
              ),
            ),

          // 🐛 DEBUG PayFast payment simulator — a secondary debug action
          // rendered ONLY in `kDebugMode` for bookings awaiting the deposit.
          // On tap it calls `_simulatePaymentSuccess`, which writes the
          // booking document directly to the post-payment state (status ->
          // `Paid`, `depositPaidAt` server timestamp) — exactly the state the
          // deployed PayFast ITN handler writes on a COMPLETE payment. This
          // lets a sandbox tester exercise the full booking-status transition
          // without going through the browser checkout. (v4.5 to-do Item #10.)
          if (kDebugMode &&
              DepositPaymentSimulator.canSimulate(status) &&
              depositAmount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _isSimulating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.bug_report, size: 20),
                  label: const Text('Simulate PayFast Deposit (Debug)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    side: BorderSide(color: Colors.deepOrange.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isSimulating
                      ? null
                      : () => _simulatePaymentSuccess(widget.bookingId),
                ),
              ),
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
        ],
      ),
    );
  }

  Widget _depositRow(String label, double value, {bool emphasize = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize
                ? widget.theme.textColor
                : widget.theme.subtitleColor,
            fontSize: emphasize ? 13 : 12,
            fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          'R ${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: emphasize ? Colors.green : widget.theme.textColor,
            fontSize: emphasize ? 14 : 12,
            fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
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
            return Padding(
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
                              lastDate:
                                  DateTime.now().add(const Duration(days: 730)),
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
                              lastDate:
                                  DateTime.now().add(const Duration(days: 730)),
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
                      hintStyle:
                          TextStyle(color: widget.theme.subtitleColor),
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
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
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
                        ? '${value.day}/${value.month}/${value.year}'
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

  /// Builds the PayFast sandbox payment URL from the booking details and
  /// launches it in the external browser. The booking id is passed as
  /// `m_payment_id` so the ITN handler can reconcile it back to the booking.
  /// [itemName] is the package/booking title, surfaced as the PayFast line
  /// item name. Toggles the in-card [_isPaying] loading state and surfaces a
  /// confirmation snackbar once the checkout portal has opened (or a failure
  /// snackbar if the browser hand-off is unavailable). (v4.5 to-do Item #7.)
  Future<void> _initiatePayFastCheckout({
    required String bookingId,
    required double amount,
    String? itemName,
  }) async {
    if (_isPaying) return;
    setState(() => _isPaying = true);
    // Signal the marketplace screen's app-resume listener that a browser
    // checkout is in flight so it can detect the user's return. (v4.5 to-do
    // Item #10.)
    widget.onPayFastCheckoutLaunched?.call();
    // Capture the messenger before the async gap (the widget may unmount
    // while the browser hand-off is in flight).
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // Route through the single-source PayFast sandbox launcher so the
      // sandbox configuration (host / merchant id / key / ITN endpoint)
      // lives in exactly one place (`PayfastCheckout`). The amount charged
      // is the 25% marked-up deposit (already resolved off
      // `totalHunterPriceRands × 0.25`).
      final launched = await PayfastCheckout.launchDeposit(
        bookingId: bookingId,
        amount: amount,
        itemName: itemName,
      );
      if (!mounted) return;
      if (launched) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'PayFast checkout portal opened in your browser — pay your 25% '
              'deposit to confirm the booking.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open PayFast checkout — no browser app available. '
              'Please try again or contact the outfitter.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(content: Text('PayFast checkout failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPaying = false);
      }
    }
  }

  /// **Debug-only** PayFast deposit payment simulator (v4.5 to-do Item #10).
  ///
  /// Invoked by the "Simulate PayFast Deposit (Debug)" card button
  /// (`kDebugMode` only, deposit-due bookings). Calls
  /// `PackageBookingManager.simulateDepositPaid`, which writes the booking
  /// document directly to the post-payment state (`status` -> `Paid`,
  /// `depositPaidAt` server timestamp) — exactly the state the deployed PayFast
  /// ITN handler writes on a COMPLETE payment. The reactive `bookings` stream
  /// then re-renders the card in the `Paid` state automatically.
  Future<void> _simulatePaymentSuccess(String bookingId) async {
    if (_isSimulating) return;
    setState(() => _isSimulating = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await PackageBookingManager.instance
          .simulateDepositPaid(bookingId: bookingId);
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            '✅ [DEBUG] Deposit payment simulated — booking marked Paid.',
          ),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ [DEBUG] Simulation failed: $e\n'
              'Note: the bookings rule only permits the outfitter to flip '
              'the status field — run as the outfitter/admin or relax rules '
              'in your sandbox.',
            ),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSimulating = false);
      }
    }
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
