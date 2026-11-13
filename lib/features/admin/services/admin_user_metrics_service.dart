import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/admin_user_metrics.dart';

/// Fetches + caches the `users/{uid}` documents the Admin Portal V2 user-level
/// KPIs are derived from.
///
/// The fetch happens ONCE (via [fetchRecords]); the screen then re-runs
/// [AdminUserMetrics.aggregate] locally on every date-filter change, so
/// switching the Today / 7d / 30d / All Time filter never hits Firestore
/// again. The trial / subscription figures are snapshots and ignore the
/// filter entirely.
///
/// Aggregation is CLIENT-SIDE because the deployed `getAdminPortalKpis`
/// Cloud Function does not expose trial buckets (it only reports subscriber
/// totals + the Play/PayFast split — see `functions/src/admin/kpis.ts`). The
/// trial / conversion figures are therefore computed here from the same
/// `users` documents the server aggregates, using the exact
/// `entitlement_service.dart` trial/premium resolution so the admin numbers
/// agree with the in-app paywall gate.
///
/// Retired accounts (`disabled: true` / `role: 'disabled'`) are skipped so a
/// disabled login can never inflate the counts (mirrors the server's
/// `isDisabledAccount`).
class AdminUserMetricsService {
  AdminUserMetricsService._();
  static final AdminUserMetricsService instance = AdminUserMetricsService._();

  /// Test seam: inject a fake Firestore so the fetch runs without a live
  /// Firebase app.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  /// Upper bound on documents read, so a pathological collection can never
  /// hang the portal. The portal is an operator surface, so a bounded partial
  /// result is preferable to an unbounded scan.
  static const int scanLimit = 5000;

  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  /// Whether a `users/{uid}` document represents a retired account that must
  /// be excluded from every operational metric.
  static bool isDisabledAccount(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['disabled'] == true) return true;
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    return role == 'disabled' || role == 'deleted';
  }

  /// Reads the `users` collection and returns the parsed records.
  ///
  /// Best-effort: a permission / index / network failure yields an empty list
  /// (the caller then renders zeroes + an error note) rather than throwing, so
  /// one broken read never crashes the portal.
  Future<List<AdminUserRecord>> fetchRecords() async {
    try {
      final snap = await _db.collection('users').limit(scanLimit).get();
      final records = <AdminUserRecord>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        if (isDisabledAccount(data)) continue;
        records.add(AdminUserRecord.fromMap(doc.id, data));
      }
      return records;
    } catch (e) {
      debugPrint('AdminUserMetricsService.fetchRecords failed: $e');
      return const <AdminUserRecord>[];
    }
  }
}
