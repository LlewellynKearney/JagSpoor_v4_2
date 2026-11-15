import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/admin/models/admin_subscription_metrics.dart';
import 'package:jagspoor/features/admin/models/admin_user_metrics.dart';

/// Task 2 — the Admin Portal V2 subscription KPIs + Subscribers List.
///
/// Covers the Google / PayFast / Total reconciliation, the trial count, the
/// provider resolution, the filter dropdown, the search, and the newest-first
/// Start Date sort.
void main() {
  final now = DateTime(2026, 11, 15);

  AdminUserRecord sub({
    required String uid,
    String name = '',
    String email = '',
    String role = 'hunter',
    String provider = '',
    String plan = 'hunter_monthly',
    String status = 'active',
    DateTime? start,
    bool active = true,
  }) =>
      AdminUserRecord(
        uid: uid,
        email: email,
        firstName: name,
        role: role,
        provider: provider,
        plan: plan,
        subscriptionStatus: status,
        subscriptionStart: start,
        premiumExpiry: active ? now.add(const Duration(days: 30)) : null,
      );

  group('provider resolution', () {
    test('Google Play Billing maps to Google', () {
      expect(resolveAdminSubscriptionProvider('google_play'),
          AdminSubscriptionProvider.google);
      expect(resolveAdminSubscriptionProvider('google_play_billing'),
          AdminSubscriptionProvider.google);
    });

    test('PayFast + alternative (User Choice) map to PayFast', () {
      expect(resolveAdminSubscriptionProvider('payfast'),
          AdminSubscriptionProvider.payfast);
      expect(resolveAdminSubscriptionProvider('payfast_alternative'),
          AdminSubscriptionProvider.payfast);
      expect(resolveAdminSubscriptionProvider('user_choice'),
          AdminSubscriptionProvider.payfast);
    });

    test('blank / unknown maps to none (never guessed)', () {
      expect(resolveAdminSubscriptionProvider(''),
          AdminSubscriptionProvider.none);
      expect(resolveAdminSubscriptionProvider('stripe'),
          AdminSubscriptionProvider.none);
    });
  });

  group('KPI aggregation', () {
    test('Google + PayFast + unknown == Total Subscribers', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        sub(uid: 'g1', provider: 'google_play'),
        sub(uid: 'g2', provider: 'google_play_billing'),
        sub(uid: 'p1', provider: 'payfast'),
        sub(uid: 'p2', provider: 'payfast_alternative'),
        sub(uid: 'u1', provider: ''), // unknown provider
      ], now: now);

      expect(metrics.totalSubscribers, 5);
      expect(metrics.googleCount, 2);
      expect(metrics.payfastCount, 2);
      expect(metrics.unknownProviderCount, 1);
      expect(
        metrics.googleCount + metrics.payfastCount + metrics.unknownProviderCount,
        metrics.totalSubscribers,
      );
    });

    test('non-active accounts are excluded from the subscriber KPIs', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        sub(uid: 'g1', provider: 'google_play'),
        // No premium expiry -> not an active subscriber.
        AdminUserRecord(uid: 'expired', provider: 'google_play', role: 'hunter'),
      ], now: now);

      expect(metrics.totalSubscribers, 1);
      expect(metrics.googleCount, 1);
    });

    test('trial users are counted separately (not as subscribers)', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        sub(uid: 'g1', provider: 'google_play'),
        AdminUserRecord(
          uid: 't1',
          role: 'hunter',
          subscriptionStatus: 'trialing',
          trialEnd: now.add(const Duration(days: 10)),
        ),
      ], now: now);

      expect(metrics.totalSubscribers, 1);
      expect(metrics.trialCount, 1);
    });

    test('the subscriber rows include active / trial / cancelled / expired', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        sub(uid: 'a', provider: 'google_play', start: DateTime(2026, 10, 1)),
        AdminUserRecord(
          uid: 't',
          role: 'hunter',
          subscriptionStatus: 'trialing',
          trialEnd: now.add(const Duration(days: 10)),
        ),
        AdminUserRecord(
          uid: 'c',
          role: 'hunter',
          subscriptionStatus: 'cancelled',
          cancelledAt: now.subtract(const Duration(days: 2)),
        ),
        AdminUserRecord(
          uid: 'e',
          role: 'hunter',
          subscriptionStatus: 'active',
          premiumExpiry: now.subtract(const Duration(days: 3)),
        ),
        // A never-subscribed account is NOT in the list.
        AdminUserRecord(uid: 'none', role: 'hunter'),
      ], now: now);

      final byUid = {for (final r in metrics.subscribers) r.uid: r};
      expect(byUid.containsKey('none'), isFalse);
      expect(byUid['a']!.status, AdminSubscriberStatus.active);
      expect(byUid['t']!.status, AdminSubscriberStatus.trial);
      expect(byUid['c']!.status, AdminSubscriberStatus.cancelled);
      expect(byUid['e']!.status, AdminSubscriberStatus.expired);
    });
  });

  group('subscribers list rows', () {
    test('sorted by Start Date newest first (undated last)', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        sub(uid: 'old', provider: 'google_play', start: DateTime(2026, 1, 1)),
        sub(uid: 'new', provider: 'google_play', start: DateTime(2026, 11, 1)),
        sub(uid: 'mid', provider: 'google_play', start: DateTime(2026, 6, 1)),
        // No start date -> sorts last.
        sub(uid: 'undated', provider: 'google_play', start: null),
      ], now: now);

      expect(
        metrics.subscribers.map((r) => r.uid).toList(),
        ['new', 'mid', 'old', 'undated'],
      );
    });

    test('plan label resolves the canonical bucket label', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        sub(uid: 'a', provider: 'google_play', plan: 'hunter_yearly'),
        sub(uid: 'b', provider: 'payfast', plan: 'outfitter_monthly'),
      ], now: now);
      final byUid = {for (final r in metrics.subscribers) r.uid: r};
      expect(byUid['a']!.planLabel, 'Hunter Yearly');
      expect(byUid['b']!.planLabel, 'Outfitter Monthly');
    });

    test('filter dropdown narrows by provider / trial / active', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        sub(uid: 'g', provider: 'google_play'),
        sub(uid: 'p', provider: 'payfast'),
        AdminUserRecord(
          uid: 't',
          role: 'hunter',
          subscriptionStatus: 'trialing',
          trialEnd: now.add(const Duration(days: 5)),
        ),
      ], now: now);

      expect(
        metrics
            .visibleSubscribers(filter: AdminSubscriberFilter.google)
            .map((r) => r.uid)
            .toList(),
        ['g'],
      );
      expect(
        metrics
            .visibleSubscribers(filter: AdminSubscriberFilter.payfast)
            .map((r) => r.uid)
            .toList(),
        ['p'],
      );
      expect(
        metrics
            .visibleSubscribers(filter: AdminSubscriberFilter.trial)
            .map((r) => r.uid)
            .toList(),
        ['t'],
      );
      expect(
        metrics
            .visibleSubscribers(filter: AdminSubscriberFilter.active)
            .map((r) => r.uid)
            .toList(),
        ['g', 'p'],
      );
      expect(metrics.visibleSubscribers().length, 3);
    });

    test('search matches name or email', () {
      final metrics = AdminSubscriptionMetrics.aggregate([
        AdminUserRecord(
          uid: 'a',
          firstName: 'Sipho',
          email: 'sipho@example.com',
          provider: 'google_play',
          subscriptionStatus: 'active',
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
        AdminUserRecord(
          uid: 'b',
          firstName: 'Anna',
          email: 'anna@outfitter.co.za',
          provider: 'payfast',
          subscriptionStatus: 'active',
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
      ], now: now);

      expect(metrics.visibleSubscribers(query: 'sipho').single.uid, 'a');
      expect(metrics.visibleSubscribers(query: 'OUTFITTER').single.uid, 'b');
      expect(metrics.visibleSubscribers(query: 'zzz'), isEmpty);
    });
  });
}
