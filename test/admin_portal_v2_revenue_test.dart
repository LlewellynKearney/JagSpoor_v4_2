import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/models/admin_revenue_metrics.dart';
import 'package:jagspoor/features/admin/models/admin_user_metrics.dart';
import 'package:jagspoor/features/admin/screens/admin_portal_v2_screen.dart';
import 'package:jagspoor/features/admin/services/admin_auth_guard.dart';
import 'package:jagspoor/features/admin/services/admin_operational_metrics_service.dart';
import 'package:jagspoor/features/admin/services/admin_user_metrics_service.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

/// Builds an [AdminUserRecord] from a raw map (mirrors the service's parse).
AdminUserRecord _record(String uid, Map<String, dynamic> data) =>
    AdminUserRecord.fromMap(uid, data);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==========================================================================
  // TASK 5 — Revenue model unit tests
  // ==========================================================================

  group('price constants match the server truth (plans.ts)', () {
    test('monthly / yearly prices + yearly MRR contributions', () {
      expect(kHunterMonthlyZar, 34.99);
      expect(kHunterYearlyZar, 349.99);
      expect(kOutfitterMonthlyZar, 299.99);
      expect(kOutfitterYearlyZar, 2999.99);
      // MRR = annual / 12 rounded to cents.
      expect(kHunterYearlyMrrZar, 29.17);
      expect(kOutfitterYearlyMrrZar, 250.00);
    });

    test('AdminPlanBucket.mrrPerSubscriber maps each bucket', () {
      expect(AdminPlanBucket.hunterMonthly.mrrPerSubscriber, 34.99);
      expect(AdminPlanBucket.hunterYearly.mrrPerSubscriber, 29.17);
      expect(AdminPlanBucket.outfitterMonthly.mrrPerSubscriber, 299.99);
      expect(AdminPlanBucket.outfitterYearly.mrrPerSubscriber, 250.00);
      expect(AdminPlanBucket.hunterMonthly.isOutfitter, isFalse);
      expect(AdminPlanBucket.outfitterYearly.isOutfitter, isTrue);
    });
  });

  group('resolveAdminPlanBucket', () {
    test('resolves the PayFast catalog ids', () {
      expect(resolveAdminPlanBucket('hunter_monthly'),
          AdminPlanBucket.hunterMonthly);
      expect(resolveAdminPlanBucket('hunter_yearly'),
          AdminPlanBucket.hunterYearly);
      expect(resolveAdminPlanBucket('outfitter_monthly'),
          AdminPlanBucket.outfitterMonthly);
      expect(resolveAdminPlanBucket('outfitter_yearly'),
          AdminPlanBucket.outfitterYearly);
    });

    test('resolves the Google Play product ids', () {
      expect(resolveAdminPlanBucket('jagspoor_hunter_monthly'),
          AdminPlanBucket.hunterMonthly);
      expect(resolveAdminPlanBucket('jagspoor_outfitter_yearly'),
          AdminPlanBucket.outfitterYearly);
    });

    test('resolves the alternative-billing ids', () {
      expect(resolveAdminPlanBucket('jagspoor_hunter_monthly_payfast'),
          AdminPlanBucket.hunterMonthly);
      expect(resolveAdminPlanBucket('jagspoor_outfitter_yearly_payfast'),
          AdminPlanBucket.outfitterYearly);
    });

    test('is case-insensitive + tolerates annual / month spellings', () {
      expect(resolveAdminPlanBucket('HUNTER_ANNUAL'),
          AdminPlanBucket.hunterYearly);
      expect(resolveAdminPlanBucket('Outfitter Month'),
          AdminPlanBucket.outfitterMonthly);
    });

    test('blank / unrecognised ids are null (surfaced as Unknown)', () {
      expect(resolveAdminPlanBucket(null), isNull);
      expect(resolveAdminPlanBucket(''), isNull);
      expect(resolveAdminPlanBucket('premium'), isNull);
      expect(resolveAdminPlanBucket('hunter_lifetime'), isNull);
    });
  });

  group('resolveAdminProviderBucket', () {
    test('payfast wins, user_choice is matched first', () {
      expect(resolveAdminProviderBucket('payfast'),
          AdminProviderBucket.payfast);
      expect(resolveAdminProviderBucket('payfast_alternative'),
          AdminProviderBucket.payfast);
      expect(resolveAdminProviderBucket('user_choice'),
          AdminProviderBucket.userChoice);
      // The brief's User Choice bucket must NOT be swallowed by the payfast
      // prefix match.
      expect(resolveAdminProviderBucket('user_choice_payfast'),
          AdminProviderBucket.userChoice);
    });

    test('play / google_play map to Google Play', () {
      expect(resolveAdminProviderBucket('play'), AdminProviderBucket.play);
      expect(resolveAdminProviderBucket('google_play'),
          AdminProviderBucket.play);
      expect(resolveAdminProviderBucket('google_play_billing'),
          AdminProviderBucket.play);
    });

    test('blank / unrecognised bucket as Unknown', () {
      expect(resolveAdminProviderBucket(null), AdminProviderBucket.unknown);
      expect(resolveAdminProviderBucket(''), AdminProviderBucket.unknown);
      expect(resolveAdminProviderBucket('stripe'),
          AdminProviderBucket.unknown);
    });
  });

  group('formatAdminZar', () {
    test('comma thousands + two decimals', () {
      expect(formatAdminZar(1234.56), 'R1,234.56');
      expect(formatAdminZar(0), 'R0.00');
      expect(formatAdminZar(34.99), 'R34.99');
      expect(formatAdminZar(1000000), 'R1,000,000.00');
      expect(formatAdminZar(999.9), 'R999.90');
    });
  });

  group('AdminRevenueMetrics.aggregate', () {
    final now = DateTime(2026, 11, 13, 12);

    AdminUserRecord activeSub(
      String uid, {
      required String plan,
      String provider = 'payfast',
      String role = 'hunter',
    }) =>
        _record(uid, {
          'role': role,
          'subscriptionStatus': 'active',
          'subscriptionProduct': plan,
          'subscriptionProvider': provider,
          'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
        });

    test('empty input yields all-zero metrics', () {
      final m = AdminRevenueMetrics.aggregate(const [], now: now);
      expect(m.totalMrr, 0);
      expect(m.arr, 0);
      expect(m.activeSubscribers, 0);
      expect(m.churnedCount, 0);
      expect(m.pipelineValue, 0);
      expect(m.totalMrrLabel, 'R0.00');
    });

    test('MRR matches the manual calc across all four buckets', () {
      final m = AdminRevenueMetrics.aggregate([
        activeSub('u1', plan: 'hunter_monthly'),
        activeSub('u2', plan: 'hunter_monthly'),
        activeSub('u3', plan: 'hunter_yearly'),
        activeSub('u4', plan: 'outfitter_monthly', role: 'outfitter'),
        activeSub('u5', plan: 'outfitter_yearly', role: 'outfitter'),
      ], now: now);

      // 2 × 34.99 + 1 × 29.17 + 1 × 299.99 + 1 × 250.00 = 649.14
      expect(m.totalMrr, closeTo(649.14, 0.0001));
      expect(m.totalMrrLabel, 'R649.14');
      // Hunter: 2 × 34.99 + 29.17 = 99.15 ; Outfitter: 299.99 + 250.00 = 549.99
      expect(m.hunterMrr, closeTo(99.15, 0.0001));
      expect(m.outfitterMrr, closeTo(549.99, 0.0001));
      expect(m.hunterMrrLabel, 'R99.15');
      expect(m.outfitterMrrLabel, 'R549.99');
    });

    test('ARR = MRR × 12', () {
      final m = AdminRevenueMetrics.aggregate([
        activeSub('u1', plan: 'hunter_monthly'),
        activeSub('u2', plan: 'hunter_monthly'),
      ], now: now);
      expect(m.totalMrr, closeTo(69.98, 0.0001));
      expect(m.arr, closeTo(839.76, 0.0001));
      expect(m.arrLabel, 'R839.76');
    });

    test('plan split carries the four buckets in canonical order', () {
      final m = AdminRevenueMetrics.aggregate([
        activeSub('u1', plan: 'hunter_monthly'),
        activeSub('u2', plan: 'outfitter_yearly', role: 'outfitter'),
      ], now: now);
      final split = m.planSplit;
      expect(split.map((r) => r.label).toList(), [
        'Hunter Monthly',
        'Hunter Yearly',
        'Outfitter Monthly',
        'Outfitter Yearly',
      ]);
      expect(split[0].count, 1);
      expect(split[0].mrrLabel, 'R34.99');
      expect(split[3].count, 1);
      expect(split[3].mrrLabel, 'R250.00');
    });

    test('provider split counts + percentages (PayFast / Play / User Choice)',
        () {
      final m = AdminRevenueMetrics.aggregate([
        activeSub('u1', plan: 'hunter_monthly', provider: 'payfast'),
        activeSub('u2', plan: 'hunter_monthly', provider: 'payfast'),
        activeSub('u3', plan: 'hunter_monthly', provider: 'google_play'),
        activeSub('u4', plan: 'hunter_monthly', provider: 'user_choice'),
      ], now: now);

      expect(m.activeSubscribers, 4);
      expect(m.providerCountFor(AdminProviderBucket.payfast), 2);
      expect(m.providerCountFor(AdminProviderBucket.play), 1);
      expect(m.providerCountFor(AdminProviderBucket.userChoice), 1);
      expect(m.providerCountFor(AdminProviderBucket.unknown), 0);
      expect(m.providerPercentLabel(AdminProviderBucket.payfast), '50.0%');
      expect(m.providerPercentLabel(AdminProviderBucket.play), '25.0%');
      expect(m.providerPercentLabel(AdminProviderBucket.userChoice), '25.0%');
    });

    test('a missing provider buckets as Unknown (split still reconciles)', () {
      final m = AdminRevenueMetrics.aggregate([
        activeSub('u1', plan: 'hunter_monthly', provider: ''),
      ], now: now);
      expect(m.providerCountFor(AdminProviderBucket.unknown), 1);
      expect(m.providerPercentLabel(AdminProviderBucket.unknown), '100.0%');
    });

    test('an unpriced active subscriber is excluded from MRR but counted', () {
      final m = AdminRevenueMetrics.aggregate([
        activeSub('u1', plan: 'premium_tier'),
      ], now: now);
      expect(m.totalMrr, 0);
      expect(m.activeSubscribers, 1);
      expect(m.unknownPlanActiveSubscribers, 1);
    });

    test('a trial-only account is NOT counted as a subscriber', () {
      final m = AdminRevenueMetrics.aggregate([
        _record('u1', {
          'role': 'hunter',
          'subscriptionStatus': 'trialing',
          'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 10))),
        }),
      ], now: now);
      expect(m.activeSubscribers, 0);
      expect(m.totalMrr, 0);
    });

    test('churned list carries email + plan + cancelledAt', () {
      final m = AdminRevenueMetrics.aggregate([
        _record('c1', {
          'email': 'gone@example.com',
          'subscriptionStatus': 'cancelled',
          'subscriptionProduct': 'hunter_monthly',
          'subscriptionCancelledAt':
              Timestamp.fromDate(DateTime(2026, 10, 1)),
        }),
      ], now: now);
      expect(m.churnedCount, 1);
      expect(m.churned.single.email, 'gone@example.com');
      expect(m.churned.single.planLabel, 'hunter_monthly');
      expect(m.churned.single.cancelledAtLabel, '2026-10-01');
    });

    test('churned cancelledAt falls back to updatedAt', () {
      final m = AdminRevenueMetrics.aggregate([
        _record('c1', {
          'email': 'gone@example.com',
          'subscriptionStatus': 'cancelled',
          'subscriptionProduct': 'outfitter_monthly',
          'updatedAt': Timestamp.fromDate(DateTime(2026, 9, 15)),
        }),
      ], now: now);
      expect(m.churned.single.cancelledAtLabel, '2026-09-15');
    });

    test('churned rows are sorted newest-first', () {
      final m = AdminRevenueMetrics.aggregate([
        _record('c1', {
          'subscriptionStatus': 'cancelled',
          'subscriptionCancelledAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        }),
        _record('c2', {
          'subscriptionStatus': 'cancelled',
          'subscriptionCancelledAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
        }),
      ], now: now);
      expect(m.churned.map((r) => r.uid).toList(), ['c2', 'c1']);
    });

    test('pipeline value = hunters × 34.99 + outfitters × 299.99', () {
      final m = AdminRevenueMetrics.aggregate([
        _record('t1', {
          'role': 'hunter',
          'subscriptionStatus': 'trialing',
          'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 5))),
        }),
        _record('t2', {
          'role': 'hunter',
          'subscriptionStatus': 'trialing',
          'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 5))),
        }),
        _record('t3', {
          'role': 'outfitter',
          'subscriptionStatus': 'trialing',
          'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 5))),
        }),
      ], now: now);
      expect(m.trialActiveHunters, 2);
      expect(m.trialActiveOutfitters, 1);
      expect(m.trialActiveTotal, 3);
      // 2 × 34.99 + 1 × 299.99 = 369.97
      expect(m.pipelineValue, closeTo(369.97, 0.0001));
      expect(m.pipelineLabel, 'R369.97');
    });

    test('a paying subscriber is not also counted in the pipeline', () {
      final m = AdminRevenueMetrics.aggregate([
        _record('u1', {
          'role': 'hunter',
          'subscriptionStatus': 'active',
          'subscriptionProduct': 'hunter_monthly',
          'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
          'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 5))),
        }),
      ], now: now);
      expect(m.activeSubscribers, 1);
      expect(m.trialActiveTotal, 0);
      expect(m.pipelineValue, 0);
    });
  });

  // ==========================================================================
  // TASK 5 — Screen widget tests
  // ==========================================================================

  group('AdminPortalV2Screen revenue section', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      AdminUserMetricsService.firestoreForTesting = firestore;
      AdminOperationalMetricsService.firestoreForTesting = firestore;
      AdminAuthGuard.adminOverrideForTesting = true;
      UserRoleProvider.instance.setRole(AppRole.admin);
    });

    tearDown(() {
      AdminUserMetricsService.firestoreForTesting = null;
      AdminOperationalMetricsService.firestoreForTesting = null;
      AdminAuthGuard.resetTestSeams();
    });

    Future<void> pumpScreen(WidgetTester tester, {double height = 7200}) async {
      tester.view.physicalSize = Size(1200, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminPortalV2Screen(theme: ThemeController.instance),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders all Task 5 revenue cards', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('adminV2CardTotalMrr')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminV2CardArr')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminV2CardHunterMrr')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('adminV2CardOutfitterMrr')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminV2PlanSplit')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminV2ProviderSplit')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminV2PipelineCard')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminV2ChurnedTable')), findsOneWidget);
    });

    testWidgets('MRR matches a manual calc from the Firestore spot-check',
        (tester) async {
      final expiry = Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30)));
      await firestore.collection('users').doc('u1').set({
        'role': 'hunter',
        'subscriptionStatus': 'active',
        'subscriptionProduct': 'hunter_monthly',
        'subscriptionProvider': 'payfast',
        'premiumExpiry': expiry,
      });
      await firestore.collection('users').doc('u2').set({
        'role': 'outfitter',
        'subscriptionStatus': 'active',
        'subscriptionProduct': 'outfitter_yearly',
        'subscriptionProvider': 'google_play',
        'premiumExpiry': expiry,
      });

      await pumpScreen(tester);

      // 34.99 + 250.00 = 284.99
      final totalCard = find.byKey(const ValueKey('adminV2CardTotalMrr'));
      expect(find.descendant(of: totalCard, matching: find.text('R284.99')),
          findsOneWidget);
      // ARR = 284.99 × 12 = 3419.88
      final arrCard = find.byKey(const ValueKey('adminV2CardArr'));
      expect(find.descendant(of: arrCard, matching: find.text('R3,419.88')),
          findsOneWidget);
      // Hunter MRR 34.99 / Outfitter MRR 250.00
      final hunterCard = find.byKey(const ValueKey('adminV2CardHunterMrr'));
      expect(find.descendant(of: hunterCard, matching: find.text('R34.99')),
          findsOneWidget);
      final outfitterCard =
          find.byKey(const ValueKey('adminV2CardOutfitterMrr'));
      expect(find.descendant(of: outfitterCard, matching: find.text('R250.00')),
          findsOneWidget);
    });

    testWidgets('the pipeline card is clearly labelled as not-realized',
        (tester) async {
      await firestore.collection('users').doc('t1').set({
        'role': 'hunter',
        'subscriptionStatus': 'trialing',
        'trialEndsAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 5))),
      });

      await pumpScreen(tester);

      expect(find.text('PIPELINE — If all trials convert'), findsOneWidget);
      final pipelineCard = find.byKey(const ValueKey('adminV2PipelineCard'));
      // 1 hunter × 34.99 = 34.99
      expect(find.descendant(of: pipelineCard, matching: find.text('R34.99')),
          findsOneWidget);
    });

    testWidgets('churned table shows email + plan + cancellation date',
        (tester) async {
      await firestore.collection('users').doc('c1').set({
        'email': 'churned@example.com',
        'role': 'hunter',
        'subscriptionStatus': 'cancelled',
        'subscriptionProduct': 'hunter_monthly',
        'subscriptionCancelledAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });

      await pumpScreen(tester);

      expect(find.text('churned@example.com'), findsOneWidget);
      expect(find.text('hunter_monthly'), findsOneWidget);
      expect(find.text('2026-10-01'), findsOneWidget);
    });

    testWidgets('renders cleanly with no subscribers (zero state)',
        (tester) async {
      await pumpScreen(tester);
      expect(tester.takeException(), isNull);
      final totalCard = find.byKey(const ValueKey('adminV2CardTotalMrr'));
      expect(find.descendant(of: totalCard, matching: find.text('R0.00')),
          findsOneWidget);
      expect(find.text('No cancelled subscriptions.'), findsOneWidget);
    });
  });
}
