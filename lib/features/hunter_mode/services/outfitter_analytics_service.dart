import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/offline_stream_guard.dart';
import '../models/booking_status.dart';
import 'outfitter_enterprise_manager.dart';
import 'pricing_math.dart';

class OutfitterAnalyticsService {
  static final OutfitterAnalyticsService _instance =
      OutfitterAnalyticsService._internal();
  static OutfitterAnalyticsService get instance => _instance;

  OutfitterAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Booking statuses that represent **realized** outfitter revenue -- i.e.
  /// the outfitter has a confirmed claim on the base price because payment
  /// has been verified.
  ///
  /// The off-platform booking lifecycle is:
  ///   `Pending Approval` -> `Awaiting Payment` -> `Confirmed` -> `Completed`
  ///
  /// Only `Confirmed` (payment verified) and `Completed` (hunt delivered)
  /// count toward realized revenue. `Pending Approval` and
  /// `Awaiting Payment` are explicitly excluded -- the payment has not yet
  /// been verified, so the revenue is not realized.
  static const List<String> earnedBookingStatuses = BookingStatus.earnedStatuses;

  // ==========================================
  // OUTFITTER FINANCIAL SUMMARY AGGREGATION
  // ==========================================
  /// Streams real-time financial summary for an outfitter based on earned
  /// bookings ([earnedBookingStatuses]).
  ///
  /// Calculates:
  /// - grossEarnings: Sum of the booking totals collected from hunters across
  ///   earned bookings. The total equals the base price (there is no platform
  ///   commission); for legacy documents the base price is preferred.
  /// - netEarnings: `grossEarnings` (the outfitter receives the full booking
  ///   amount; no platform cut is deducted).
  /// - totalBookings: Count of earned bookings.
  ///
  /// Parameters:
  /// - outfitterId: The UID of the outfitter
  ///
  /// Returns: Stream with financial metrics
  Stream<Map<String, double>> getRevenueSummaryStream(String outfitterId) {
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('bookings')
          .where('outfitterId', isEqualTo: outfitterId)
          .where('status', whereIn: earnedBookingStatuses)
          .snapshots()
          .map((snapshot) {
            final summary = PricingMath.aggregateRevenueSummary(
              snapshot.docs.map((d) => d.data()),
            );
            return {
              'grossEarnings': summary.grossRevenue,
              'netEarnings': summary.netEarnings,
              'totalBookings': summary.totalBookings.toDouble(),
            };
          }),
      fallback: const <String, double>{
        'grossEarnings': 0.0,
        'netEarnings': 0.0,
        'totalBookings': 0.0,
      },
      debugLabel: 'bookings.revenue',
    );
  }

  // ==========================================
  // HUNTER REGIONAL PACKAGE FILTER QUERY
  // ==========================================
  /// Streams packages filtered by geographic location.
  ///
  /// Filters packages by resolving the parent farm's location (province/district)
  /// when a farmId is present, or by direct package location fields.
  ///
  /// Parameters:
  /// - province: Optional province filter (e.g., "Northern Cape")
  /// - district: Optional district filter (e.g., "ZF Mgcawu")
  ///
  /// Returns: Stream of filtered packages with farm details
  Stream<List<Map<String, dynamic>>> getFilteredPackagesStream({
    String? province,
    String? district,
  }) {
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('packages')
          // Include sold-out listings so hunters see them as read-only
          // "Sold Out" cards rather than the offering silently disappearing.
          .where('status', whereIn: ['active', 'sold_out'])
          .snapshots()
          .asyncMap((packageSnapshot) async {
            final List<Map<String, dynamic>> filteredPackages = [];

            for (final packageDoc in packageSnapshot.docs) {
              final packageData = packageDoc.data();
              Map<String, dynamic>? farmData;

              // Try to fetch parent farm data if farmId exists
              final farmId = packageData['farmId'] as String?;
              if (farmId != null && farmId.isNotEmpty) {
                try {
                  final farmDoc =
                      await _firestore.collection('farms').doc(farmId).get();
                  if (farmDoc.exists) {
                    farmData = farmDoc.data();
                  }
                } catch (e) {
                  // Farm document may have been deleted
                  continue;
                }
              }

              // Extract location from farm or direct package fields
              final packageProvince =
                  packageData['province'] as String? ??
                  farmData?['province'] as String? ??
                  '';
              final packageDistrict =
                  packageData['district'] as String? ??
                  farmData?['district'] as String? ??
                  '';

              // Apply filters
              bool matchesProvince =
                  province == null ||
                  province.isEmpty ||
                  packageProvince.toLowerCase() == province.toLowerCase();
              bool matchesDistrict =
                  district == null ||
                  district.isEmpty ||
                  packageDistrict.toLowerCase() == district.toLowerCase();

              if (matchesProvince && matchesDistrict) {
                // Build enriched package object with farm location details
                filteredPackages.add({
                  'packageId': packageDoc.id,
                  'packageData': packageData,
                  'farmId': farmId,
                  'farmName': farmData?['name'] ?? 'Unknown Farm',
                  'province': packageProvince,
                  'district': packageDistrict,
                });
              }
            }

            return filteredPackages;
          }),
      fallback: const <Map<String, dynamic>>[],
      debugLabel: 'packages.filtered',
    );
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  /// Get pending bookings count for an outfitter -- bookings awaiting the
  /// outfitter's approval (`Pending Approval`).
  Stream<int> getPendingBookingsCountStream(String outfitterId) {
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('bookings')
          .where('outfitterId', isEqualTo: outfitterId)
          .where('status', isEqualTo: BookingStatus.pendingApproval)
          .snapshots()
          .map((snapshot) => snapshot.size),
      fallback: 0,
      debugLabel: 'bookings.pendingCount',
    );
  }

  /// Get total packages count for an outfitter
  Stream<int> getTotalPackagesCountStream(String outfitterId) {
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('packages')
          .where('outfitterId', isEqualTo: outfitterId)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .map((snapshot) => snapshot.size),
      fallback: 0,
      debugLabel: 'packages.totalCount',
    );
  }

  // ==========================================
  // SPECIES REVENUE BREAKDOWN
  // ==========================================

  /// Aggregates the per-species revenue breakdown for an outfitter's earned
  /// (payment-verified: Confirmed / Completed) bookings.
  ///
  /// Species revenue is resolved from two data sources per booking:
  /// - **Custom harvested species** -- a custom-package booking carries its
  ///   own `selectedItemsList` line items (`name` + `quantity` + `lineTotal` /
  ///   `unitPriceHunterZAR`), written by
  ///   `FarmGamePriceListManager.submitCustomPackageBooking`.
  /// - **Package animals** -- a marketplace booking references
  ///   `packages/{packageId}`, whose `speciesItems` carry `speciesName` +
  ///   `quantity` + `pricePerAnimal` / `total`.
  ///
  /// Returns the aggregated rows sorted by revenue (desc), each
  /// `{species, revenue, count}`. Empty when no earned booking carries
  /// species data (the dashboard then shows its "No species revenue data
  /// yet" empty state).
  Future<List<Map<String, dynamic>>> getSpeciesRevenueBreakdown(
      String outfitterId) async {
    final snapshot = await _firestore
        .collection('bookings')
        .where('outfitterId', isEqualTo: outfitterId)
        .where('status', whereIn: earnedBookingStatuses)
        .get();

    final bookings = snapshot.docs.map((d) => d.data()).toList();

    // Fetch the linked package docs for bookings that do not carry their own
    // species line items (marketplace bookings keep the species list on the
    // package doc). Custom-package bookings ('CUSTOM_BUILT') have no package
    // doc, so they are never fetched.
    final packageIds = <String>{};
    for (final data in bookings) {
      if (hasInlineSpeciesItems(data)) continue;
      final packageId = (data['packageId'] as String?)?.trim();
      if (packageId != null &&
          packageId.isNotEmpty &&
          packageId != 'CUSTOM_BUILT') {
        packageIds.add(packageId);
      }
    }
    final packagesById = <String, Map<String, dynamic>>{};
    for (final packageId in packageIds) {
      try {
        final pkg =
            await _firestore.collection('packages').doc(packageId).get();
        final data = pkg.data();
        if (data != null) packagesById[packageId] = data;
      } catch (_) {
        // A deleted / unreadable package simply contributes no species.
      }
    }

    return aggregateSpeciesRevenue(bookings, packagesById);
  }

  /// Whether a booking document carries its own species line items (custom
  /// harvested species) instead of referencing a package's species list.
  static bool hasInlineSpeciesItems(Map<String, dynamic> booking) {
    final items = booking['selectedItemsList'];
    return items is List && items.isNotEmpty;
  }

  /// Pure aggregation of per-species revenue + harvest counts from booking
  /// records (and their linked package records). Dependency-free so the
  /// breakdown can be unit-tested without the Firestore emulator.
  ///
  /// [bookings] are raw `bookings` document maps (already filtered to the
  /// earned statuses by the caller). [packagesById] maps `packageId` -> the
  /// raw `packages` document map, used to resolve the species list for
  /// marketplace bookings that do not carry inline `selectedItemsList`.
  ///
  /// Returns rows sorted by revenue descending (alphabetical tie-break),
  /// each `{species, revenue, count}`.
  static List<Map<String, dynamic>> aggregateSpeciesRevenue(
    Iterable<Map<String, dynamic>> bookings,
    Map<String, Map<String, dynamic>> packagesById,
  ) {
    final revenueBySpecies = <String, double>{};
    final countBySpecies = <String, int>{};

    void accumulate(String? rawName, num? rawQty, double revenue) {
      final species = rawName?.trim() ?? '';
      if (species.isEmpty) return;
      final qty = rawQty?.toInt() ?? 1;
      final safeQty = qty < 1 ? 1 : qty;
      revenueBySpecies[species] =
          (revenueBySpecies[species] ?? 0.0) + revenue;
      countBySpecies[species] = (countBySpecies[species] ?? 0) + safeQty;
    }

    for (final booking in bookings) {
      if (hasInlineSpeciesItems(booking)) {
        // Custom harvested species (custom-package booking).
        final items = booking['selectedItemsList'] as List;
        for (final raw in items.whereType<Map>()) {
          final item = Map<String, dynamic>.from(raw);
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          final lineTotal = (item['lineTotal'] as num?)?.toDouble();
          final unitPrice =
              (item['unitPriceHunterZAR'] as num?)?.toDouble() ??
                  (item['hunterPrice'] as num?)?.toDouble() ??
                  0.0;
          accumulate(
            (item['name'] ?? item['speciesName'] ?? item['speciesId'])
                as String?,
            qty,
            lineTotal ?? unitPrice * qty,
          );
        }
        continue;
      }

      // Marketplace booking: resolve the linked package's advertised species.
      final packageId = (booking['packageId'] as String?)?.trim();
      final package = packageId == null ? null : packagesById[packageId];
      final speciesItems = package?['speciesItems'];
      if (speciesItems is! List) continue;
      for (final raw in speciesItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final total = (item['total'] as num?)?.toDouble();
        final pricePerAnimal =
            (item['pricePerAnimal'] as num?)?.toDouble() ?? 0.0;
        accumulate(
          (item['speciesName'] ?? item['name']) as String?,
          qty,
          total ?? pricePerAnimal * qty,
        );
      }
    }

    final rows = revenueBySpecies.keys
        .map((species) => <String, dynamic>{
              'species': species,
              'revenue': revenueBySpecies[species],
              'count': countBySpecies[species] ?? 0,
            })
        .toList();
    rows.sort((a, b) {
      final byRevenue =
          (b['revenue'] as double).compareTo(a['revenue'] as double);
      if (byRevenue != 0) return byRevenue;
      return (a['species'] as String).compareTo(b['species'] as String);
    });
    return rows;
  }

  /// Get available trophy stock summary across all farms
  Future<Map<String, dynamic>> getTrophyStockSummary(String outfitterId) async {
    final snapshot =
        await _firestore
            .collection(OutfitterEnterpriseManager.trophyStockCollection)
            .where('outfitterId', isEqualTo: outfitterId)
            .get();

    int totalAvailable = 0;
    double totalValue = 0.0;
    final speciesMap = <String, int>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final count = (data['availableCount'] ?? 0) as int;
      final price = (data['pricePerTrophyRands'] ?? 0).toDouble();
      final species = data['species'] ?? 'Unknown';

      totalAvailable += count;
      totalValue += count * price;
      speciesMap[species] = (speciesMap[species] ?? 0) + count;
    }

    return {
      'totalAvailable': totalAvailable,
      'totalValue': totalValue,
      'speciesBreakdown': speciesMap,
      'speciesCount': speciesMap.length,
    };
  }

  /// Get monthly booking statistics
  Future<Map<String, Map<String, int>>> getMonthlyBookingStats(
    String outfitterId, {
    int monthsBack = 6,
  }) async {
    final now = DateTime.now();
    final stats = <String, Map<String, int>>{};

    for (int i = 0; i < monthsBack; i++) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey =
          '${month.year}-${month.month.toString().padLeft(2, '0')}';
      stats[monthKey] = {'approved': 0, 'declined': 0, 'pending': 0};
    }

    final snapshot =
        await _firestore
            .collection('bookings')
            .where('outfitterId', isEqualTo: outfitterId)
            .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final timestamp = data['bookingTimestamp'] as Timestamp?;
      if (timestamp == null) continue;

      final bookingDate = timestamp.toDate();
      final monthKey =
          '${bookingDate.year}-${bookingDate.month.toString().padLeft(2, '0')}';
      final status = data['status'] as String? ?? '';

      if (stats.containsKey(monthKey)) {
        // "approved" counts bookings where the outfitter has accepted the
        // request (awaiting payment or payment-verified). "pending" counts
        // un-reviewed requests. "declined" counts rejections. Cancelled /
        // completed are not categorized here.
        if (status == BookingStatus.approvedAwaitingPayment ||
            status == BookingStatus.confirmed ||
            status == BookingStatus.completed ||
            status == 'Approved') {
          stats[monthKey]!['approved'] =
              (stats[monthKey]!['approved'] ?? 0) + 1;
        } else if (status == BookingStatus.declined) {
          stats[monthKey]!['declined'] =
              (stats[monthKey]!['declined'] ?? 0) + 1;
        } else if (status == BookingStatus.pendingApproval) {
          stats[monthKey]!['pending'] = (stats[monthKey]!['pending'] ?? 0) + 1;
        }
      }
    }

    return stats;
  }

  /// Get farms summary for an outfitter
  Future<int> getFarmCount(String outfitterId) async {
    final snapshot =
        await _firestore
            .collection('farms')
            .where('outfitterId', isEqualTo: outfitterId)
            .where('status', isEqualTo: 'active')
            .get();
    return snapshot.size;
  }

  /// Get managers count across all farms
  Future<int> getManagerCount(String outfitterId) async {
    final snapshot =
        await _firestore
            .collection('farm_managers')
            .where('outfitterId', isEqualTo: outfitterId)
            .where('status', isEqualTo: 'Active')
            .get();
    return snapshot.size;
  }
}
