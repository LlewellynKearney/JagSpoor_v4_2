import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/admin/services/subscription_config_service.dart';
import 'package:jagspoor/features/admin/services/usage_analytics_service.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

/// Admin portal — subscription revenue config + feature-usage telemetry.
///
/// Firestore operations are exercised against `FakeFirebaseFirestore` via
/// the services' documented test seams (no emulator needed); the pure
/// aggregation / derivation helpers are tested in isolation.
void main() {
  // Pin the FieldValue platform before any production `FieldValue` is
  // realized, mirroring the pattern in optic_log_service_test.dart.
  FakeFirebaseFirestore();

  group('SubscriptionConfig model', () {
    test('round-trips a full config', () {
      final config = SubscriptionConfig.fromMap(const {
        'hunterSubscriptionZAR': 149.99,
        'outfitterSubscriptionZAR': 499.5,
      });
      expect(config.hunterSubscriptionZAR, 149.99);
      expect(config.outfitterSubscriptionZAR, 499.5);
      expect(config.toMap(), {
        'hunterSubscriptionZAR': 149.99,
        'outfitterSubscriptionZAR': 499.5,
      });
    });

    test('defaults to zero amounts for an absent config doc', () {
      final config = SubscriptionConfig.fromMap(null);
      expect(config.hunterSubscriptionZAR, 0.0);
      expect(config.outfitterSubscriptionZAR, 0.0);
    });

    test('tolerates numeric strings', () {
      final config = SubscriptionConfig.fromMap(const {
        'hunterSubscriptionZAR': '120',
        'outfitterSubscriptionZAR': '350.5',
      });
      expect(config.hunterSubscriptionZAR, 120.0);
      expect(config.outfitterSubscriptionZAR, 350.5);
    });

    test('copyWith updates only the supplied field', () {
      const base = SubscriptionConfig(
          hunterSubscriptionZAR: 100, outfitterSubscriptionZAR: 200);
      final updated = base.copyWith(outfitterSubscriptionZAR: 250);
      expect(updated.hunterSubscriptionZAR, 100);
      expect(updated.outfitterSubscriptionZAR, 250);
    });
  });

  group('SubscriptionConfigService load / save', () {
    setUp(() {
      SubscriptionConfigService.resetTestSeams();
    });
    tearDown(() {
      SubscriptionConfigService.resetTestSeams();
    });

    test('saves and reloads the config (FakeFirebaseFirestore)', () async {
      final fake = FakeFirebaseFirestore();
      SubscriptionConfigService.firestoreForTesting = fake;
      await SubscriptionConfigService.instance.saveConfig(
        const SubscriptionConfig(
            hunterSubscriptionZAR: 99, outfitterSubscriptionZAR: 399),
      );
      final loaded = await SubscriptionConfigService.instance.loadConfig();
      expect(loaded.hunterSubscriptionZAR, 99);
      expect(loaded.outfitterSubscriptionZAR, 399);
    });

    test('clamps negative amounts to zero on save', () async {
      final fake = FakeFirebaseFirestore();
      SubscriptionConfigService.firestoreForTesting = fake;
      await SubscriptionConfigService.instance.saveConfig(
        const SubscriptionConfig(
            hunterSubscriptionZAR: -10, outfitterSubscriptionZAR: -250),
      );
      final loaded = await SubscriptionConfigService.instance.loadConfig();
      expect(loaded.hunterSubscriptionZAR, 0.0);
      expect(loaded.outfitterSubscriptionZAR, 0.0);
    });

    test('absent config doc yields zero amounts', () async {
      final fake = FakeFirebaseFirestore();
      SubscriptionConfigService.firestoreForTesting = fake;
      final loaded = await SubscriptionConfigService.instance.loadConfig();
      expect(loaded.hunterSubscriptionZAR, 0.0);
      expect(loaded.outfitterSubscriptionZAR, 0.0);
    });
  });

  group('SubscriptionRevenue derivation', () {
    test('MRR = hunter count × hunter rate + outfitter count × rate', () {
      const config = SubscriptionConfig(
          hunterSubscriptionZAR: 100, outfitterSubscriptionZAR: 400);
      final revenue = SubscriptionConfigService.computeRevenue(
        config,
        hunterCount: 12,
        outfitterCount: 3,
      );
      expect(revenue.monthlyRecurringRevenue, 12 * 100 + 3 * 400);
      expect(revenue.annualProjection,
          closeTo((12 * 100 + 3 * 400) * 12, 0.0001));
      expect(revenue.dailyEstimate,
          closeTo((12 * 100 + 3 * 400) / 30, 0.0001));
      expect(revenue.weeklyEstimate,
          closeTo((12 * 100 + 3 * 400) * 7 / 30, 0.0001));
    });

    test('zero rates yield zero revenue', () {
      final revenue = SubscriptionConfigService.computeRevenue(
        const SubscriptionConfig(),
        hunterCount: 10,
        outfitterCount: 10,
      );
      expect(revenue.monthlyRecurringRevenue, 0);
      expect(revenue.annualProjection, 0);
    });
  });

  group('UsageAnalytics aggregation', () {
    test('partitions by role with per-feature counts', () {
      final usage = UsageAnalyticsService.aggregateUsage([
        {'event': 'Weather & Wind Tracker', 'role': 'hunter', 'type': 'feature_usage'},
        {'event': 'Weather & Wind Tracker', 'role': 'hunter', 'type': 'feature_usage'},
        {'event': 'Hunter Dashboard', 'role': 'hunter', 'type': 'screen_view'},
        {'event': 'Price List', 'role': 'outfitter', 'type': 'feature_usage'},
      ]);
      expect(usage.hunters.total, 3);
      expect(usage.hunters.featureCounts['Weather & Wind Tracker'], 2);
      expect(usage.outfitters.total, 1);
      expect(usage.outfitters.featureCounts['Price List'], 1);
    });

    test('ignores admin / unknown roles so the hunter-vs-outfitter split is clean', () {
      final usage = UsageAnalyticsService.aggregateUsage([
        {'event': 'Admin Portal', 'role': 'admin', 'type': 'screen_view'},
        {'event': 'Hunter Dashboard', 'role': 'hunter', 'type': 'screen_view'},
        {'event': '', 'role': 'hunter', 'type': 'screen_view'},
      ]);
      expect(usage.outfitters.total, 0);
      expect(usage.hunters.total, 1);
      expect(usage.hunters.featureCounts.containsKey('Admin Portal'), isFalse);
    });

    test('orderedFeatures sorts by descending usage then name', () {
      final usage = UsageAnalyticsService.aggregateUsage([
        {'event': 'A', 'role': 'outfitter', 'type': 'feature_usage'},
        {'event': 'B', 'role': 'outfitter', 'type': 'feature_usage'},
        {'event': 'A', 'role': 'outfitter', 'type': 'feature_usage'},
      ]);
      expect(usage.outfitters.orderedFeatures, ['A', 'B']);
    });

    test('empty input yields empty partitions', () {
      final usage = UsageAnalyticsService.aggregateUsage(const []);
      expect(usage.hunters.total, 0);
      expect(usage.outfitters.total, 0);
    });
  });

  group('UsageAnalyticsService tracking (FakeFirebaseFirestore)', () {
    setUp(() {
      UsageAnalyticsService.resetTestSeams();
    });
    tearDown(() {
      UsageAnalyticsService.resetTestSeams();
    });

    test('records a screen view with the resolved role + userId', () async {
      final fake = FakeFirebaseFirestore();
      UsageAnalyticsService.firestoreForTesting = fake;
      UsageAnalyticsService.roleForTesting = AppRole.outfitter;
      UsageAnalyticsService.userIdForTesting = 'uid-9';
      await UsageAnalyticsService.instance
          .trackScreenView('Outfitter Dashboard');
      final snap = await fake
          .collection(UsageAnalyticsService.eventsCollection)
          .get();
      expect(snap.docs, hasLength(1));
      final data = snap.docs.single.data();
      expect(data['event'], 'Outfitter Dashboard');
      expect(data['type'], 'screen_view');
      expect(data['role'], 'outfitter');
      expect(data['userId'], 'uid-9');
      // FakeFirestore resolves serverTimestamp() to a Timestamp; production
      // stores a FieldValue. Either shape satisfies the write contract.
      expect(data.containsKey('timestamp'), isTrue);
    });

    test('records a feature usage event', () async {
      final fake = FakeFirebaseFirestore();
      UsageAnalyticsService.firestoreForTesting = fake;
      UsageAnalyticsService.roleForTesting = AppRole.hunter;
      await UsageAnalyticsService.instance
          .trackFeatureUsage('Weather & Wind Tracker');
      final snap = await fake
          .collection(UsageAnalyticsService.eventsCollection)
          .get();
      expect(snap.docs.single.data()['type'], 'feature_usage');
      expect(snap.docs.single.data()['role'], 'hunter');
    });

    test('skips admins (the hunter-vs-outfitter split stays clean)', () async {
      final fake = FakeFirebaseFirestore();
      UsageAnalyticsService.firestoreForTesting = fake;
      UsageAnalyticsService.roleForTesting = AppRole.admin;
      await UsageAnalyticsService.instance.trackScreenView('Admin Portal');
      final snap = await fake
          .collection(UsageAnalyticsService.eventsCollection)
          .get();
      expect(snap.docs, isEmpty);
    });

    test('fetchUsageAnalytics groups events by role', () async {
      final fake = FakeFirebaseFirestore();
      UsageAnalyticsService.firestoreForTesting = fake;
      UsageAnalyticsService.roleForTesting = AppRole.hunter;
      await UsageAnalyticsService.instance.trackScreenView('Hunter Dashboard');
      await UsageAnalyticsService.instance.trackScreenView('Hunter Dashboard');
      final usage =
          await UsageAnalyticsService.instance.fetchUsageAnalytics();
      expect(usage.hunters.featureCounts['Hunter Dashboard'], 2);
    });

    test('a Firestore failure is swallowed (never breaks user flows)', () async {
      // No Firebase app in the test runner → the instance getter throws;
      // the fire-and-forget catch must swallow it without rethrowing.
      UsageAnalyticsService.resetTestSeams();
      await UsageAnalyticsService.instance.trackScreenView('X');
      // reach here without exception.
    });
  });

  group('Admin dashboard wiring contract', () {
    final src =
        File('lib/features/admin/screens/admin_dashboard_screen.dart')
            .readAsStringSync();

    test('renders the subscription config card with hunter + outfitter fields',
        () {
      expect(src.contains('Subscription amounts (per user / month)'), isTrue);
      expect(src.contains('Hunter subscription (ZAR)'), isTrue);
      expect(src.contains('Outfitter subscription (ZAR)'), isTrue);
      expect(src.contains('_saveSubscriptionConfig'), isTrue);
    });

    test('renders MRR / ARR / daily / weekly estimates', () {
      expect(src.contains('monthlyRecurringRevenue'), isTrue);
      expect(src.contains('annualProjection'), isTrue);
      expect(src.contains('dailyEstimate'), isTrue);
      expect(src.contains('weeklyEstimate'), isTrue);
    });

    test('renders the feature usage section partitioned by role', () {
      expect(src.contains('Feature Usage by Role'), isTrue);
      expect(src.contains('Hunters'), isTrue);
      expect(src.contains('Outfitters'), isTrue);
    });

    test('hunter + outfitter dashboards record views + feature taps', () {
      final hunter = File('lib/features/hunter_mode/hunter_dashboard.dart')
          .readAsStringSync();
      final outfitter = File(
              'lib/features/outfitter_mode/outfitter_dashboard.dart')
          .readAsStringSync();
      expect(
          hunter.contains("trackScreenView('Hunter Dashboard')"), isTrue);
      expect(hunter.contains('trackFeatureUsage(feature.title)'), isTrue);
      expect(
          outfitter.contains("trackScreenView('Outfitter Dashboard')"),
          isTrue);
      expect(outfitter.contains('trackFeatureUsage(title)'), isTrue);
    });

    test('firestore.rules carries the new collections', () {
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules.contains('match /app_config/{docId}'), isTrue);
      expect(rules.contains('match /feature_usage_events/{eventId}'), isTrue);
      expect(
        rules.contains(
          'match /feature_usage_events/{eventId} {\n      allow create: if isSignedIn();',
        ),
        isTrue,
      );
    });
  });
}
