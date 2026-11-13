import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/admin/models/admin_user_metrics.dart';
import 'package:jagspoor/features/admin/services/admin_user_metrics_service.dart';

/// Task 3 — Admin Portal V2 trial + subscription KPIs.
///
/// Covers the pure aggregation (the numbers a Firestore console spot-check
/// would confirm) and the fetch path (disabled-account exclusion + graceful
/// failure) against a real `FakeFirebaseFirestore` — no mocks of the
/// aggregation itself.
void main() {
  group('AdminDateFilter', () {
    final now = DateTime(2026, 11, 13, 15, 30);

    test('startFor windows are inclusive of today', () {
      expect(AdminDateFilter.today.startFor(now), DateTime(2026, 11, 13));
      expect(AdminDateFilter.last7Days.startFor(now), DateTime(2026, 11, 7));
      expect(AdminDateFilter.last30Days.startFor(now), DateTime(2026, 10, 15));
      expect(AdminDateFilter.allTime.startFor(now), isNull);
    });

    test('includes respects the window boundaries', () {
      expect(
          AdminDateFilter.today.includes(DateTime(2026, 11, 13, 9), now), isTrue);
      expect(
          AdminDateFilter.today.includes(DateTime(2026, 11, 12, 23), now),
          isFalse);
      expect(
          AdminDateFilter.last7Days.includes(DateTime(2026, 11, 7), now),
          isTrue);
      expect(
          AdminDateFilter.last7Days.includes(DateTime(2026, 11, 6), now),
          isFalse);
      expect(AdminDateFilter.allTime.includes(DateTime(2020, 1, 1), now),
          isTrue);
    });

    test('a null or future timestamp never counts', () {
      expect(AdminDateFilter.allTime.includes(null, now), isFalse);
      expect(
          AdminDateFilter.allTime.includes(DateTime(2027, 1, 1), now), isFalse);
    });
  });

  group('AdminUserRecord.isTrialActive', () {
    final now = DateTime(2026, 11, 13);

    test('active when the trial-end timestamp is in the future', () {
      final r = AdminUserRecord(
        uid: 'u1',
        trialEnd: now.add(const Duration(days: 5)),
      );
      expect(r.isTrialActive(now), isTrue);
    });

    test('expired when the trial-end timestamp is in the past', () {
      final r = AdminUserRecord(
        uid: 'u1',
        trialEnd: now.subtract(const Duration(days: 1)),
        subscriptionStatus: 'trialing',
      );
      expect(r.isTrialActive(now), isFalse);
    });

    test('active from a trial status with no timestamp', () {
      expect(
          AdminUserRecord(uid: 'u1', subscriptionStatus: 'trialing')
              .isTrialActive(now),
          isTrue);
      expect(
          AdminUserRecord(uid: 'u1', subscriptionStatus: 'trial')
              .isTrialActive(now),
          isTrue);
    });

    test('falls back to the 30-day creation window', () {
      final within =
          AdminUserRecord(uid: 'u1', createdAt: now.subtract(const Duration(days: 10)));
      final beyond =
          AdminUserRecord(uid: 'u1', createdAt: now.subtract(const Duration(days: 40)));
      expect(within.isTrialActive(now), isTrue);
      expect(beyond.isTrialActive(now), isFalse);
    });

    test('requiresPayment blocks trial access at every step', () {
      final r = AdminUserRecord(
        uid: 'u1',
        trialEnd: now.add(const Duration(days: 5)),
        requiresPayment: true,
      );
      expect(r.isTrialActive(now), isFalse);
    });

    test('no trial fields and no createdAt fails closed', () {
      expect(AdminUserRecord(uid: 'u1').isTrialActive(now), isFalse);
    });
  });

  group('AdminUserRecord.isPremiumActive', () {
    final now = DateTime(2026, 11, 13);

    test('active when hasActivePurchase is set (server-confirmed)', () {
      expect(
          AdminUserRecord(uid: 'u1', hasActivePurchase: true)
              .isPremiumActive(now),
          isTrue);
    });

    test('requires a future premiumExpiry (bare active status does not count)',
        () {
      final noExpiry =
          AdminUserRecord(uid: 'u1', subscriptionStatus: 'active');
      expect(noExpiry.isPremiumActive(now), isFalse);

      final future = AdminUserRecord(
        uid: 'u1',
        subscriptionStatus: 'active',
        premiumExpiry: now.add(const Duration(days: 20)),
      );
      expect(future.isPremiumActive(now), isTrue);

      final past = AdminUserRecord(
        uid: 'u1',
        subscriptionStatus: 'active',
        premiumExpiry: now.subtract(const Duration(days: 1)),
      );
      expect(past.isPremiumActive(now), isFalse);
    });

    test('isPremium + future expiry grants access', () {
      final r = AdminUserRecord(
        uid: 'u1',
        isPremium: true,
        premiumExpiry: now.add(const Duration(days: 5)),
      );
      expect(r.isPremiumActive(now), isTrue);
    });
  });

  group('AdminUserMetrics.aggregate', () {
    final now = DateTime(2026, 11, 13);

    test('counts new users inside the filter window only', () {
      final records = [
        AdminUserRecord(uid: 'a', createdAt: now), // today
        AdminUserRecord(uid: 'b', createdAt: now.subtract(const Duration(days: 3))),
        AdminUserRecord(uid: 'c', createdAt: now.subtract(const Duration(days: 20))),
        AdminUserRecord(uid: 'd'), // no createdAt
      ];
      expect(
          AdminUserMetrics.aggregate(records,
                  filter: AdminDateFilter.today, now: now)
              .newUsers,
          1);
      expect(
          AdminUserMetrics.aggregate(records,
                  filter: AdminDateFilter.last7Days, now: now)
              .newUsers,
          2);
      expect(
          AdminUserMetrics.aggregate(records,
                  filter: AdminDateFilter.last30Days, now: now)
              .newUsers,
          3);
      expect(
          AdminUserMetrics.aggregate(records,
                  filter: AdminDateFilter.allTime, now: now)
              .newUsers,
          3);
    });

    test('trial + subscription figures are snapshots (ignore the filter)', () {
      final records = [
        AdminUserRecord(
          uid: 'a',
          createdAt: now.subtract(const Duration(days: 40)),
          trialEnd: now.add(const Duration(days: 5)),
        ),
        AdminUserRecord(
          uid: 'b',
          createdAt: now,
          role: 'hunter',
          subscriptionStatus: 'active',
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
      ];
      final today =
          AdminUserMetrics.aggregate(records, filter: AdminDateFilter.today, now: now);
      final allTime =
          AdminUserMetrics.aggregate(records, filter: AdminDateFilter.allTime, now: now);
      // Snapshots are identical regardless of the date filter.
      expect(today.trialActive, allTime.trialActive);
      expect(today.subscribedHunters, allTime.subscribedHunters);
      expect(today.trialActive, 1);
      expect(today.subscribedHunters, 1);
      // Only New Users changes.
      expect(today.newUsers, 1);
      expect(allTime.newUsers, 2);
    });

    test('trial expired no sub requires a past trialEnd and no premium', () {
      final records = [
        AdminUserRecord(
            uid: 'expired',
            trialEnd: now.subtract(const Duration(days: 2))), // counts
        AdminUserRecord(
            uid: 'active',
            trialEnd: now.add(const Duration(days: 2))), // not expired
        AdminUserRecord(
          uid: 'expired-but-paid',
          trialEnd: now.subtract(const Duration(days: 2)),
          hasActivePurchase: true, // premium -> excluded
        ),
        AdminUserRecord(uid: 'no-trial'), // never had a trial -> excluded
      ];
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.allTime, now: now);
      expect(m.trialExpiredNoSub, 1);
    });

    test('subscribed hunters / outfitters split by role', () {
      final records = [
        AdminUserRecord(
            uid: 'h1',
            role: 'hunter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30))),
        AdminUserRecord(
            uid: 'h2',
            role: 'hunter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30))),
        AdminUserRecord(
            uid: 'o1',
            role: 'outfitter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30))),
        // A trialing account is NOT a subscriber.
        AdminUserRecord(
            uid: 't1', role: 'hunter', subscriptionStatus: 'trialing'),
      ];
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.allTime, now: now);
      expect(m.subscribedHunters, 2);
      expect(m.subscribedOutfitters, 1);
      expect(m.totalSubscribers, 3);
    });

    test('ever-started-trial counts trialStart presence (all aliases)', () {
      final records = [
        AdminUserRecord(uid: 'a', trialStart: now),
        AdminUserRecord(uid: 'b', trialStart: now),
        AdminUserRecord(uid: 'c'), // never started
      ];
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.allTime, now: now);
      expect(m.usersEverStartedTrial, 2);
    });

    test('conversion % is subscribers / ever-started, one decimal', () {
      final records = [
        // 2 subscribers...
        AdminUserRecord(
            uid: 'h1',
            role: 'hunter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30)),
            trialStart: now),
        AdminUserRecord(
            uid: 'o1',
            role: 'outfitter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30)),
            trialStart: now),
        // ...out of 4 who ever started a trial.
        AdminUserRecord(uid: 't1', trialStart: now),
        AdminUserRecord(uid: 't2', trialStart: now),
      ];
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.allTime, now: now);
      expect(m.totalSubscribers, 2);
      expect(m.usersEverStartedTrial, 4);
      expect(m.trialToPaidConversionPercent, 50.0);
      expect(m.trialToPaidConversionLabel, '50.0%');
    });

    test('conversion % is 0.0 when nobody started a trial (no divide-by-zero)',
        () {
      final m = AdminUserMetrics.aggregate(
        [AdminUserRecord(uid: 'a', role: 'hunter')],
        filter: AdminDateFilter.allTime,
        now: now,
      );
      expect(m.usersEverStartedTrial, 0);
      expect(m.trialToPaidConversionPercent, 0.0);
      expect(m.trialToPaidConversionLabel, '0.0%');
    });

    test('rounds to one decimal place', () {
      // 1 subscriber / 3 ever-started = 33.333... -> 33.3%
      final records = [
        AdminUserRecord(
            uid: 'h1',
            role: 'hunter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30)),
            trialStart: now),
        AdminUserRecord(uid: 't1', trialStart: now),
        AdminUserRecord(uid: 't2', trialStart: now),
      ];
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.allTime, now: now);
      expect(m.trialToPaidConversionLabel, '33.3%');
    });

    test('unknown plan bucket counts active subscribers with no plan', () {
      final records = [
        AdminUserRecord(
            uid: 'h1',
            role: 'hunter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30))), // no plan
        AdminUserRecord(
            uid: 'h2',
            role: 'hunter',
            subscriptionStatus: 'active',
            premiumExpiry: now.add(const Duration(days: 30)),
            plan: 'hunter_monthly'),
      ];
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.allTime, now: now);
      expect(m.unknownPlanSubscribers, 1);
    });

    test('missing trial / subscription fields never crash the aggregation',
        () {
      final records = [
        AdminUserRecord(uid: 'empty'),
        AdminUserRecord(uid: 'partial', role: 'hunter'),
      ];
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.today, now: now);
      expect(m.newUsers, 0);
      expect(m.trialActive, 0);
      expect(m.trialExpiredNoSub, 0);
      expect(m.subscribedHunters, 0);
      expect(m.subscribedOutfitters, 0);
      expect(m.trialToPaidConversionLabel, '0.0%');
    });
  });

  group('AdminUserRecord.fromMap field aliases', () {
    test('reads the trial aliases (trialStartedAt / trialStart / subscriptionTrial*)',
        () {
      final end = DateTime(2026, 12, 1);
      final start = DateTime(2026, 11, 1);
      final r = AdminUserRecord.fromMap('u1', {
        'trialStartedAt': Timestamp.fromDate(start),
        'trialEndsAt': Timestamp.fromDate(end),
      });
      expect(r.trialStart, start);
      expect(r.trialEnd, end);

      final r2 = AdminUserRecord.fromMap('u2', {
        'subscriptionTrialStart': Timestamp.fromDate(start),
        'subscriptionTrialEndsAt': Timestamp.fromDate(end),
      });
      expect(r2.trialStart, start);
      expect(r2.trialEnd, end);

      // `trialStart` / `trialEnd` (backend-trigger schema).
      final r3 = AdminUserRecord.fromMap('u3', {
        'trialStart': Timestamp.fromDate(start),
        'trialEnd': Timestamp.fromDate(end),
      });
      expect(r3.trialStart, start);
      expect(r3.trialEnd, end);
    });

    test('reads the plan from subscriptionProduct (with aliases)', () {
      expect(
          AdminUserRecord.fromMap('u1', {'subscriptionProduct': 'hunter_yearly'})
              .plan,
          'hunter_yearly');
      expect(
          AdminUserRecord.fromMap('u1', {'plan': 'outfitter_monthly'}).plan,
          'outfitter_monthly');
      expect(AdminUserRecord.fromMap('u1', {}).plan, '');
    });

    test('reads the provider from subscriptionProvider / Platform / Source', () {
      expect(
          AdminUserRecord.fromMap('u1', {'subscriptionProvider': 'google_play'})
              .provider,
          'google_play');
      expect(
          AdminUserRecord.fromMap('u1', {'subscriptionPlatform': 'payfast'})
              .provider,
          'payfast');
      expect(
          AdminUserRecord.fromMap('u1', {'subscriptionSource': 'google_play'})
              .provider,
          'google_play');
    });

    test('reads createdAt (camel + snake) and premiumExpiry', () {
      final created = DateTime(2026, 1, 2);
      expect(
          AdminUserRecord.fromMap('u1', {'createdAt': Timestamp.fromDate(created)})
              .createdAt,
          created);
      expect(
          AdminUserRecord.fromMap('u1', {'created_at': created}).createdAt,
          created);
      expect(
          AdminUserRecord.fromMap(
                  'u1', {'premiumExpiry': Timestamp.fromDate(created)})
              .premiumExpiry,
          created);
    });

    test('an empty / null document parses to a safe default', () {
      final r = AdminUserRecord.fromMap('u1', null);
      expect(r.uid, 'u1');
      expect(r.plan, '');
      expect(r.trialEnd, isNull);
      expect(r.isTrialActive(DateTime(2026, 11, 13)), isFalse);
      expect(r.isPremiumActive(DateTime(2026, 11, 13)), isFalse);
    });
  });

  group('AdminUserMetricsService (FakeFirebaseFirestore)', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      AdminUserMetricsService.firestoreForTesting = firestore;
    });

    tearDown(() {
      AdminUserMetricsService.firestoreForTesting = null;
    });

    test('fetches every non-disabled user document', () async {
      await firestore.collection('users').doc('u1').set({
        'role': 'hunter',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 13)),
      });
      await firestore.collection('users').doc('u2').set({
        'role': 'outfitter',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 10)),
      });
      final records = await AdminUserMetricsService.instance.fetchRecords();
      expect(records.length, 2);
      expect(records.map((r) => r.uid), containsAll(['u1', 'u2']));
    });

    test('excludes disabled / deleted accounts', () async {
      await firestore.collection('users').doc('active').set({'role': 'hunter'});
      await firestore.collection('users').doc('disabled').set({
        'role': 'hunter',
        'disabled': true,
      });
      await firestore.collection('users').doc('deleted').set({
        'role': 'deleted',
      });
      final records = await AdminUserMetricsService.instance.fetchRecords();
      expect(records.map((r) => r.uid), ['active']);
    });

    test('aggregates the full KPI bundle from Firestore', () async {
      final now = DateTime(2026, 11, 13);
      await firestore.collection('users').doc('hunter-sub').set({
        'role': 'hunter',
        'subscriptionStatus': 'active',
        'subscriptionProduct': 'hunter_monthly',
        'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
        'trialStartedAt': Timestamp.fromDate(now.subtract(const Duration(days: 40))),
        'trialEndsAt': Timestamp.fromDate(now.subtract(const Duration(days: 10))),
        'createdAt': Timestamp.fromDate(now),
      });
      await firestore.collection('users').doc('outfitter-trial').set({
        'role': 'outfitter',
        'subscriptionStatus': 'trialing',
        'trialStartedAt': Timestamp.fromDate(now.subtract(const Duration(days: 5))),
        'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 25))),
        'createdAt': Timestamp.fromDate(now),
      });
      await firestore.collection('users').doc('expired').set({
        'role': 'hunter',
        'trialStartedAt': Timestamp.fromDate(now.subtract(const Duration(days: 60))),
        'trialEndsAt': Timestamp.fromDate(now.subtract(const Duration(days: 30))),
        'createdAt': Timestamp.fromDate(now),
      });

      final records = await AdminUserMetricsService.instance.fetchRecords();
      final m = AdminUserMetrics.aggregate(records,
          filter: AdminDateFilter.today, now: now);

      expect(m.newUsers, 3);
      expect(m.subscribedHunters, 1);
      expect(m.subscribedOutfitters, 0);
      expect(m.trialActive, 1); // the outfitter trial
      expect(m.trialExpiredNoSub, 1); // the expired hunter
      expect(m.usersEverStartedTrial, 3);
      // 1 subscriber / 3 ever-started = 33.3%
      expect(m.trialToPaidConversionLabel, '33.3%');
    });

    test('a fetch failure yields an empty list (never throws)', () async {
      // No Firebase app configured -> the real FirebaseFirestore.instance
      // access throws; the service catches it and returns empty.
      AdminUserMetricsService.firestoreForTesting = null;
      final records = await AdminUserMetricsService.instance.fetchRecords();
      expect(records, isEmpty);
    });
  });
}
