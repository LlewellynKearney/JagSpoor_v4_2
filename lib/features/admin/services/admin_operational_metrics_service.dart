import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/admin_operational_metrics.dart';

/// The raw, joined operational data the Admin Portal V2 package + booking KPIs
/// are aggregated from.
///
/// Fetched ONCE by [AdminOperationalMetricsService.fetchData]; the pure
/// [AdminPackageMetrics.aggregate] / [AdminBookingMetrics.aggregate] factories
/// then derive every figure locally, so the numbers match a Firestore console
/// spot-check of the same documents.
class AdminOperationalData {
  /// Packages with [AdminPackageRecord.resolvedProvince] filled from the
  /// `farms/{farmId}` join (blank when the farm is missing — those count toward
  /// the "Unknown Province" bucket, never dropped).
  final List<AdminPackageRecord> packages;

  final List<AdminBookingRecord> bookings;

  /// Every outfitter uid from the `outfitters` collection.
  final Set<String> outfitterIds;

  /// uid -> email (hunter + outfitter + outfitter profile).
  final Map<String, String> emailByUid;

  /// outfitter uid -> display name.
  final Map<String, String> outfitterNameByUid;

  /// packageId -> title.
  final Map<String, String> packageTitleById;

  const AdminOperationalData({
    this.packages = const [],
    this.bookings = const [],
    this.outfitterIds = const {},
    this.emailByUid = const {},
    this.outfitterNameByUid = const {},
    this.packageTitleById = const {},
  });

  /// Aggregates the package KPI bundle from this snapshot.
  AdminPackageMetrics packageMetrics({DateTime? now}) =>
      AdminPackageMetrics.aggregate(
        packages,
        bookingPackageIds: {for (final b in bookings) b.packageId},
        outfitterIds: outfitterIds,
        emailByUid: emailByUid,
        now: now,
      );

  /// Aggregates the booking KPI bundle from this snapshot.
  AdminBookingMetrics bookingMetrics({DateTime? now}) =>
      AdminBookingMetrics.aggregate(
        bookings,
        emailByUid: emailByUid,
        outfitterNameByUid: outfitterNameByUid,
        packageTitleById: packageTitleById,
        now: now,
      );
}

/// Fetches the `packages` / `bookings` / `farms` / `outfitters` documents the
/// Admin Portal V2 operational KPIs are derived from, and performs the
/// `farms/{farmId}` province join.
///
/// The fetch happens ONCE (via [fetchData]); the screen then aggregates locally
/// with the pure model factories. Unlike the user KPIs, the package / booking
/// figures are point-in-time snapshots and do NOT respond to the date filter, so
/// no re-fetch or re-aggregation is triggered by a filter change.
///
/// Aggregation is CLIENT-SIDE because the deployed `getAdminPortalKpis` Cloud
/// Function does not expose per-province package or booking-pipeline figures.
///
/// Retired outfitters are skipped from the `outfitters` set (mirrors the
/// server's `isDisabledAccount`) so a disabled login cannot distort the
/// "Outfitters With 0 Packages" count.
class AdminOperationalMetricsService {
  AdminOperationalMetricsService._();
  static final AdminOperationalMetricsService instance =
      AdminOperationalMetricsService._();

  /// Test seam: inject a fake Firestore so the fetch runs without a live
  /// Firebase app.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  /// Upper bound on documents read per collection, so a pathological
  /// collection can never hang the portal.
  static const int scanLimit = 5000;

  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  /// Whether an `outfitters/{uid}` document represents a retired outfitter that
  /// must be excluded from the operational counts.
  static bool isDisabledOutfitter(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['disabled'] == true) return true;
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    return role == 'disabled' || role == 'deleted';
  }

  /// Reads every collection the operational KPIs need and returns the joined
  /// snapshot.
  ///
  /// [userEmailByUid] supplies the hunter / outfitter emails already parsed from
  /// the `users` records (the screen's Task 3 fetch) so this method never reads
  /// `users` a second time. Outfitter emails from the `outfitters` collection
  /// are merged on top.
  ///
  /// Best-effort per collection: a permission / index / network failure on one
  /// collection yields an empty result for that collection (the caller then
  /// renders zeroes) rather than throwing, so one broken read never crashes the
  /// portal.
  Future<AdminOperationalData> fetchData({
    Map<String, String> userEmailByUid = const {},
  }) async {
    final packages = await _fetchPackages();
    final bookings = await _fetchBookings();
    final farmProvinceById = await _fetchFarmProvinces();
    final outfitterProfiles = await _fetchOutfitterProfiles();

    // Province join: fill each package's resolved province from its farm.
    final joinedPackages = <AdminPackageRecord>[
      for (final p in packages)
        p.withProvince(farmProvinceById[p.farmId] ?? ''),
    ];

    final emailByUid = <String, String>{...userEmailByUid};
    final outfitterNameByUid = <String, String>{};
    for (final entry in outfitterProfiles.entries) {
      final profile = entry.value;
      if (profile.email.isNotEmpty) emailByUid[entry.key] = profile.email;
      if (profile.name.isNotEmpty) outfitterNameByUid[entry.key] = profile.name;
    }

    final packageTitleById = <String, String>{
      for (final p in packages) p.id: p.title,
    };

    return AdminOperationalData(
      packages: joinedPackages,
      bookings: bookings,
      outfitterIds: outfitterProfiles.keys.toSet(),
      emailByUid: emailByUid,
      outfitterNameByUid: outfitterNameByUid,
      packageTitleById: packageTitleById,
    );
  }

  Future<List<AdminPackageRecord>> _fetchPackages() async {
    try {
      final snap = await _db.collection('packages').limit(scanLimit).get();
      return [
        for (final doc in snap.docs)
          AdminPackageRecord.fromMap(doc.id, doc.data()),
      ];
    } catch (e) {
      debugPrint('AdminOperationalMetricsService packages failed: $e');
      return const <AdminPackageRecord>[];
    }
  }

  Future<List<AdminBookingRecord>> _fetchBookings() async {
    try {
      final snap = await _db.collection('bookings').limit(scanLimit).get();
      return [
        for (final doc in snap.docs)
          AdminBookingRecord.fromMap(doc.id, doc.data()),
      ];
    } catch (e) {
      debugPrint('AdminOperationalMetricsService bookings failed: $e');
      return const <AdminBookingRecord>[];
    }
  }

  /// farmId -> province, from the `farms` collection.
  Future<Map<String, String>> _fetchFarmProvinces() async {
    try {
      final snap = await _db.collection('farms').limit(scanLimit).get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final province = (doc.data()['province'] ?? '').toString().trim();
        if (province.isNotEmpty) map[doc.id] = province;
      }
      return map;
    } catch (e) {
      debugPrint('AdminOperationalMetricsService farms failed: $e');
      return const <String, String>{};
    }
  }

  /// outfitter uid -> {email, name}, from the `outfitters` collection.
  Future<Map<String, _OutfitterProfile>> _fetchOutfitterProfiles() async {
    try {
      final snap = await _db.collection('outfitters').limit(scanLimit).get();
      final map = <String, _OutfitterProfile>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (isDisabledOutfitter(data)) continue;
        map[doc.id] = _OutfitterProfile(
          email: (data['email'] ?? '').toString().trim().toLowerCase(),
          name: _firstNonEmpty([
            data['businessName'],
            data['displayName'],
            data['name'],
          ]),
        );
      }
      return map;
    } catch (e) {
      debugPrint('AdminOperationalMetricsService outfitters failed: $e');
      return const <String, _OutfitterProfile>{};
    }
  }

  static String _firstNonEmpty(List<dynamic> candidates) {
    for (final raw in candidates) {
      final value = (raw ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}

class _OutfitterProfile {
  final String email;
  final String name;
  const _OutfitterProfile({required this.email, required this.name});
}
