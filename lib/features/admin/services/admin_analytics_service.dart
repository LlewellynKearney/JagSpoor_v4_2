import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/services/user_role_provider.dart';
import '../../hunter_mode/models/booking_status.dart';
import '../../hunter_mode/services/outfitter_enterprise_manager.dart';
import 'admin_auth_guard.dart';

/// Aggregated metrics for the master admin analytics dashboard.
class AdminMetrics {
  final int totalOutfitters;
  final int activeHunters;
  final int listedPackages;
  final int activeBookings;
  final int totalTrophies;
  final int registeredUsers;
  final int activeSessions;

  const AdminMetrics({
    required this.totalOutfitters,
    required this.activeHunters,
    required this.listedPackages,
    required this.activeBookings,
    required this.totalTrophies,
    required this.registeredUsers,
    required this.activeSessions,
  });
}

/// A single financial period's gross booking revenue figures (in ZAR).
class FinancialPeriod {
  final String label;
  final double grossBookingRevenue;

  const FinancialPeriod({
    required this.label,
    required this.grossBookingRevenue,
  });

  /// Outfitter net equals gross booking revenue (there is no platform
  /// commission deducted).
  double get outfitterNet => grossBookingRevenue;
}

/// Full financial analytics bundle.
class FinancialAnalytics {
  final FinancialPeriod daily;
  final FinancialPeriod weekly;
  final FinancialPeriod monthly;
  final FinancialPeriod yearly;

  const FinancialAnalytics({
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.yearly,
  });
}

/// Reads platform-wide aggregates for the master admin dashboard.
///
/// Entity counts use Firestore's `count()` aggregation queries so the dashboard
/// never downloads full collections. Financial figures are derived from the
/// `bookings` collection using the booking total (`totalHunterPriceRands`,
/// falling back to `totalPriceZAR` / `basePriceRands`). There is no platform
/// commission; the outfitter net equals the gross booking revenue.
class AdminAnalyticsService {
  AdminAnalyticsService._();
  static final AdminAnalyticsService instance = AdminAnalyticsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<int> _count(CollectionReference<Map<String, dynamic>> ref) async {
    final agg = await ref.count().get();
    return agg.count ?? 0;
  }

  Future<int> _countQuery(Query<Map<String, dynamic>> query) async {
    final agg = await query.count().get();
    return agg.count ?? 0;
  }

  /// Entity overview metrics.
  ///
  /// Each sub-query is wrapped independently so a PERMISSION_DENIED or missing
  /// index on one collection never blocks the whole dashboard — failed counts
  /// contribute 0 and the remaining metrics still render.
  Future<AdminMetrics> fetchEntityMetrics() async {
    final results = await Future.wait([
      _safeCount(() => _count(_db.collection('outfitters'))),
      _safeCount(() => _countQuery(
          _db.collection('users').where('role', isEqualTo: 'hunter'))),
      _safeCount(() => _count(_db.collection('packages'))),
      // Active bookings = realized (earned) bookings, i.e. payment verified
      // (Confirmed) or hunt delivered (Completed). The legacy 'Paid' status
      // no longer exists in the off-platform booking lifecycle.
      _safeCount(() => _countQuery(_db
          .collection('bookings')
          .where('status', whereIn: BookingStatus.earnedStatuses))),
      _safeCount(() => _count(_db.collection(
          OutfitterEnterpriseManager.trophyStockCollection))),
      _safeCount(() => _count(_db.collection('users'))),
    ]);

    // Active sessions = signed-in users we can observe. Firebase Auth does not
    // expose a live session count from the client; we approximate it with the
    // number of users whose `users` doc carries a recent FCM token (a proxy for
    // devices that have logged in and registered for push). Best-effort: on
    // failure (absent field / index / permission) it stays at 0.
    final activeSessions = await _safeCount(() async {
      final tokenAgg = await _db
          .collection('users')
          .where('fcmTokens', isNotEqualTo: null)
          .count()
          .get();
      return tokenAgg.count ?? 0;
    });

    return AdminMetrics(
      totalOutfitters: results[0],
      activeHunters: results[1],
      listedPackages: results[2],
      activeBookings: results[3],
      totalTrophies: results[4],
      registeredUsers: results[5],
      activeSessions: activeSessions,
    );
  }

  /// Runs a count operation, returning 0 on any failure (permission denied,
  /// missing index, network) so a single broken query never blocks the rest.
  Future<int> _safeCount(Future<int> Function() op) async {
    try {
      return await op();
    } catch (_) {
      return 0;
    }
  }

  /// Sums gross booking revenue for bookings whose `bookingTimestamp`
  /// (falling back to `createdAt`) falls within the window `[start, end)`.
  /// Only realized (earned) bookings contribute -- i.e. payment verified
  /// (Confirmed) or hunt delivered (Completed). There is no platform
  /// commission; the outfitter net equals the gross booking revenue.
  ///
  /// Returns a zeroed period on any failure (permission denied, missing index)
  /// so one broken window never blocks the rest of the financial section.
  Future<FinancialPeriod> _sumPeriod(String label, DateTime start, DateTime end) async {
    try {
      final startTs = Timestamp.fromDate(start);
      final endTs = Timestamp.fromDate(end);

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('bookings')
            .where('status', whereIn: BookingStatus.earnedStatuses)
            .where('bookingTimestamp', isGreaterThanOrEqualTo: startTs)
            .where('bookingTimestamp', isLessThan: endTs)
            .get();
      } catch (_) {
        // Fall back to `createdAt` if `bookingTimestamp` is not indexed/absent.
        snap = await _db
            .collection('bookings')
            .where('status', whereIn: BookingStatus.earnedStatuses)
            .where('createdAt', isGreaterThanOrEqualTo: startTs)
            .where('createdAt', isLessThan: endTs)
            .get();
      }

      double gross = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final grossVal =
            (data['totalHunterPriceRands'] as num?)?.toDouble() ??
                (data['totalPriceZAR'] as num?)?.toDouble() ??
                (data['basePriceRands'] as num?)?.toDouble() ??
                0.0;
        gross += grossVal;
      }

      return FinancialPeriod(
        label: label,
        grossBookingRevenue: gross,
      );
    } catch (_) {
      // Graceful degradation: return a zeroed period instead of throwing.
      return FinancialPeriod(
          label: label, grossBookingRevenue: 0);
    }
  }

  /// Financial analytics across daily / weekly / monthly / yearly windows,
  /// measured backwards from now. Each period is independent; a failure in one
  /// window yields a zeroed period rather than failing the whole bundle.
  Future<FinancialAnalytics> fetchFinancialAnalytics({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    final startOfToday = DateTime(ref.year, ref.month, ref.day);

    final results = await Future.wait([
      _sumPeriod('Today', startOfToday, ref),
      _sumPeriod('This Week', ref.subtract(const Duration(days: 7)), ref),
      _sumPeriod('This Month', ref.subtract(const Duration(days: 30)), ref),
      _sumPeriod('This Year', ref.subtract(const Duration(days: 365)), ref),
    ]);

    return FinancialAnalytics(
      daily: results[0],
      weekly: results[1],
      monthly: results[2],
      yearly: results[3],
    );
  }

  /// Sign out the admin (used by the dashboard sign-out action).
  Future<void> signOut() async {
    await _auth.signOut();
    // Clear cached role state so the next sign-in re-resolves from scratch.
    UserRoleProvider.instance.reset();
    AdminAuthGuard.instance.reset();
  }
}
