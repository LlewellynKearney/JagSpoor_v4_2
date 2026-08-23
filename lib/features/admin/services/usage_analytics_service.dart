import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../auth/services/user_role_provider.dart';

/// Aggregated usage totals for one role partition (Hunter / Outfitter).
class RoleUsageSummary {
  final AppRole role;
  final Map<String, int> featureCounts;

  const RoleUsageSummary({required this.role, required this.featureCounts});

  int get total => featureCounts.values.fold(0, (acc, n) => acc + n);

  /// Feature names ordered by descending usage (ties alphabetical).
  List<String> get orderedFeatures {
    final entries = featureCounts.entries.toList();
    entries.sort((a, b) =>
        b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return entries.map((e) => e.key).toList();
  }
}

/// Full usage bundle for the Admin portal, partitioned by role.
class UsageAnalytics {
  final Map<AppRole, RoleUsageSummary> byRole;

  const UsageAnalytics({required this.byRole});

  RoleUsageSummary get hunters =>
      byRole[AppRole.hunter] ??
      const RoleUsageSummary(role: AppRole.hunter, featureCounts: {});
  RoleUsageSummary get outfitters =>
      byRole[AppRole.outfitter] ??
      const RoleUsageSummary(role: AppRole.outfitter, featureCounts: {});
}

/// Screen-view / feature-usage telemetry tracker.
///
/// Events are written to the `feature_usage_events` Firestore collection with
/// the caller's resolved role ([UserRoleProvider]) so the Admin portal can
/// partition the metrics by Hunter vs. Outfitter. Fire-and-forget: tracking
/// failures are swallowed so analytics never break user flows. The role is
/// resolved at write time, and unknown roles are skipped (admins are not
/// tracked so the Hunter vs. Outfitter comparison stays clean).
class UsageAnalyticsService {
  UsageAnalyticsService._();
  static final UsageAnalyticsService instance = UsageAnalyticsService._();

  /// Firestore collection the events are written to. Kept as a constant so
  /// the Admin aggregation + Firestore rules reference a single source.
  static const String eventsCollection = 'feature_usage_events';

  /// Test seam: inject `FakeFirebaseFirestore` so tracking + aggregation can
  /// run without a live Firebase app (same pattern as
  /// [AdminAnalyticsService.firestoreForTesting]).
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  /// Test seam: override the resolved role / uid (production reads them from
  /// [UserRoleProvider] / [FirebaseAuth] lazily with a `[core/no-app]` guard
  /// so cold-launch + widget tests do not throw).
  @visibleForTesting
  static AppRole? roleForTesting;
  @visibleForTesting
  static String? userIdForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
    roleForTesting = null;
    userIdForTesting = null;
  }

  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  AppRole _resolveRole() {
    if (roleForTesting != null) return roleForTesting!;
    try {
      return UserRoleProvider.instance.role;
    } catch (_) {
      return AppRole.unknown;
    }
  }

  String? _resolveUserId() {
    if (userIdForTesting != null) return userIdForTesting;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Pure aggregation helper: groups raw event documents into per-role
  /// feature-name counts. Unit-testable without a Firestore emulator.
  static UsageAnalytics aggregateUsage(
    Iterable<Map<String, dynamic>> events,
  ) {
    final grouped = <AppRole, Map<String, int>>{};
    for (final event in events) {
      final roleName = (event['role'] as String? ?? '').trim();
      final role = AppRole.fromString(roleName);
      if (role != AppRole.hunter && role != AppRole.outfitter) continue;
      final name = (event['event'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final bucket = grouped.putIfAbsent(role, () => <String, int>{});
      bucket[name] = (bucket[name] ?? 0) + 1;
    }
    return UsageAnalytics(
      byRole: grouped.map(
        (role, counts) =>
            MapEntry(role, RoleUsageSummary(role: role, featureCounts: counts)),
      ),
    );
  }

  /// Records a screen view. [screenName] should be the class/feature label,
  /// e.g. 'Hunter Dashboard'. Unknown roles are not recorded.
  Future<void> trackScreenView(String screenName) async {
    await _track(screenName, 'screen_view');
  }

  /// Records a feature interaction, e.g. a dashboard card tap.
  Future<void> trackFeatureUsage(String featureName) async {
    await _track(featureName, 'feature_usage');
  }

  Future<void> _track(String name, String type) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final role = _resolveRole();
    if (role != AppRole.hunter && role != AppRole.outfitter) return;
    try {
      await _db.collection(eventsCollection).add({
        'event': trimmed,
        'type': type,
        'role': role.name,
        'userId': _resolveUserId(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Fire-and-forget: analytics must never block the user.
    }
  }

  /// Aggregates all recorded events, partitioned by role (Hunter vs.
  /// Outfitter). Bounded to the most recent 5000 documents so the dashboard
  /// stays responsive; failure degrades to empty partitions.
  Future<UsageAnalytics> fetchUsageAnalytics({int limit = 5000}) async {
    try {
      final snap = await _db
          .collection(eventsCollection)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      return aggregateUsage(snap.docs.map((d) => d.data()));
    } catch (_) {
      return const UsageAnalytics(byRole: {});
    }
  }
}
