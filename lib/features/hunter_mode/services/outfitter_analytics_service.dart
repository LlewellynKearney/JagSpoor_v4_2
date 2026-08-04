import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class OutfitterAnalyticsService {
  static final OutfitterAnalyticsService _instance =
      OutfitterAnalyticsService._internal();
  static OutfitterAnalyticsService get instance => _instance;

  OutfitterAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==========================================
  // OUTFITTER FINANCIAL SUMMARY AGGREGATION
  // ==========================================
  /// Streams real-time financial summary for an outfitter based on approved bookings.
  ///
  /// Calculates:
  /// - grossEarnings: Sum of all basePriceRands from approved bookings
  /// - platformFees: Sum of all platformCommissionRands (5% split)
  /// - netEarnings: grossEarnings minus platformFees
  /// - totalBookings: Count of approved bookings
  ///
  /// Parameters:
  /// - outfitterId: The UID of the outfitter
  ///
  /// Returns: Stream with financial metrics
  Stream<Map<String, double>> getRevenueSummaryStream(String outfitterId) {
    return _firestore
        .collection('bookings')
        .where('outfitterId', isEqualTo: outfitterId)
        .where('status', isEqualTo: 'Approved')
        .snapshots()
        .map((snapshot) {
          double grossEarnings = 0.0;
          double platformFees = 0.0;
          int totalBookings = 0;

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final basePrice = (data['basePriceRands'] ?? 0).toDouble();
            final commission =
                (data['platformCommissionRands'] ?? 0).toDouble();

            grossEarnings += basePrice;
            platformFees += commission;
            totalBookings++;
          }

          final netEarnings = grossEarnings - platformFees;

          return {
            'grossEarnings': grossEarnings,
            'platformFees': platformFees,
            'netEarnings': netEarnings,
            'totalBookings': totalBookings.toDouble(),
          };
        });
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
    return _firestore
        .collection('packages')
        .where('status', isEqualTo: 'active')
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
        });
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  /// Get pending bookings count for an outfitter
  Stream<int> getPendingBookingsCountStream(String outfitterId) {
    return _firestore
        .collection('bookings')
        .where('outfitterId', isEqualTo: outfitterId)
        .where('status', isEqualTo: 'Pending Approval')
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  /// Get total packages count for an outfitter
  Stream<int> getTotalPackagesCountStream(String outfitterId) {
    return _firestore
        .collection('packages')
        .where('outfitterId', isEqualTo: outfitterId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  /// Get available trophy stock summary across all farms
  Future<Map<String, dynamic>> getTrophyStockSummary(String outfitterId) async {
    final snapshot =
        await _firestore
            .collection('trophies')
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
        if (status == 'Approved') {
          stats[monthKey]!['approved'] =
              (stats[monthKey]!['approved'] ?? 0) + 1;
        } else if (status == 'Declined') {
          stats[monthKey]!['declined'] =
              (stats[monthKey]!['declined'] ?? 0) + 1;
        } else if (status == 'Pending Approval') {
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
