import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Admin-configured subscription amounts (ZAR per user per month), stored on
/// `app_config/subscriptions`. Distinct hunter + outfitter rates are set
/// manually in the Admin portal; the revenue figures are derived from the
/// configured rates × the current subscriber counts.
class SubscriptionConfig {
  final double hunterSubscriptionZAR;
  final double outfitterSubscriptionZAR;

  const SubscriptionConfig({
    this.hunterSubscriptionZAR = 0.0,
    this.outfitterSubscriptionZAR = 0.0,
  });

  SubscriptionConfig copyWith({
    double? hunterSubscriptionZAR,
    double? outfitterSubscriptionZAR,
  }) =>
      SubscriptionConfig(
        hunterSubscriptionZAR:
            hunterSubscriptionZAR ?? this.hunterSubscriptionZAR,
        outfitterSubscriptionZAR:
            outfitterSubscriptionZAR ?? this.outfitterSubscriptionZAR,
      );

  /// Firestore / model hydration. Numeric strings are tolerated.
  static SubscriptionConfig fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SubscriptionConfig();
    return SubscriptionConfig(
      hunterSubscriptionZAR: _asDouble(data['hunterSubscriptionZAR']),
      outfitterSubscriptionZAR: _asDouble(data['outfitterSubscriptionZAR']),
    );
  }

  Map<String, dynamic> toMap() => {
        'hunterSubscriptionZAR': hunterSubscriptionZAR,
        'outfitterSubscriptionZAR': outfitterSubscriptionZAR,
      };

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// Derived subscription-driven revenue totals for the dashboard.
class SubscriptionRevenue {
  final int hunterCount;
  final int outfitterCount;
  final SubscriptionConfig config;

  const SubscriptionRevenue({
    required this.hunterCount,
    required this.outfitterCount,
    required this.config,
  });

  double get monthlyRecurringRevenue =>
      hunterCount * config.hunterSubscriptionZAR +
      outfitterCount * config.outfitterSubscriptionZAR;
  double get annualProjection => monthlyRecurringRevenue * 12;
  double get dailyEstimate => monthlyRecurringRevenue / 30;
  double get weeklyEstimate => monthlyRecurringRevenue * 7 / 30;
}

/// Reads / writes the Admin-configured subscription amounts and computes the
/// derived revenue figures for the Admin portal.
class SubscriptionConfigService {
  SubscriptionConfigService._();
  static final SubscriptionConfigService instance = SubscriptionConfigService._();

  /// Config document path. `app_config` docs are admin-write / signed-in-read
  /// per `firestore.rules`.
  static const String configPath = 'app_config';
  static const String configDocId = 'subscriptions';

  /// Test seam: inject `FakeFirebaseFirestore` (same pattern as the other
  /// admin services) so the config round-trip is unit-testable.
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    firestoreForTesting = null;
  }

  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  /// Loads the current config (zero amounts when absent/unreadable).
  Future<SubscriptionConfig> loadConfig() async {
    try {
      final snap = await _db.collection(configPath).doc(configDocId).get();
      return SubscriptionConfig.fromMap(snap.data());
    } catch (_) {
      return const SubscriptionConfig();
    }
  }

  /// Saves the admin-configured amounts (merge so other `app_config` fields
  /// are preserved). Invalid (negative) amounts are clamped to zero.
  Future<void> saveConfig(SubscriptionConfig config) async {
    final sanitized = SubscriptionConfig(
      hunterSubscriptionZAR:
          config.hunterSubscriptionZAR < 0 ? 0.0 : config.hunterSubscriptionZAR,
      outfitterSubscriptionZAR: config.outfitterSubscriptionZAR < 0
          ? 0.0
          : config.outfitterSubscriptionZAR,
    );
    await _db
        .collection(configPath)
        .doc(configDocId)
        .set(sanitized.toMap(), SetOptions(merge: true));
  }

  /// Pure revenue derivation: configured amounts × the respective subscriber
  /// counts. Unit-testable without a Firestore emulator.
  static SubscriptionRevenue computeRevenue(
    SubscriptionConfig config, {
    required int hunterCount,
    required int outfitterCount,
  }) =>
      SubscriptionRevenue(
        hunterCount: hunterCount,
        outfitterCount: outfitterCount,
        config: config,
      );
}
