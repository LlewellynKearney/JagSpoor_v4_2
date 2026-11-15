import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/version_info.dart';
import 'package:jagspoor/features/admin/screens/admin_portal_v2_screen.dart';
import 'package:jagspoor/features/admin/services/admin_auth_guard.dart';
import 'package:jagspoor/features/admin/services/admin_operational_metrics_service.dart';
import 'package:jagspoor/features/admin/services/admin_user_metrics_service.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Widget tests for the Admin Portal V2 screen.
///
/// Asserts the five Task 3 cards render, that the trial / subscription figures
/// do NOT change with the date filter, and that changing the filter only
/// updates New Users — the whole reason the screen fetches once and
/// re-aggregates locally.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    AdminUserMetricsService.firestoreForTesting = firestore;
    AdminOperationalMetricsService.firestoreForTesting = firestore;
    // Grant admin access deterministically (no Firebase Auth app).
    AdminAuthGuard.adminOverrideForTesting = true;
    UserRoleProvider.instance.setRole(AppRole.admin);
  });

  tearDown(() {
    AdminUserMetricsService.firestoreForTesting = null;
    AdminOperationalMetricsService.firestoreForTesting = null;
    AdminAuthGuard.resetTestSeams();
  });

  Future<void> pumpScreen(WidgetTester tester, {double height = 2400}) async {
    // A tall surface so the lazy ListView builds the note rows below the KPI
    // grid (they are off-screen on the default 800x600 test surface). Task 4
    // tests pass a taller height because the Packages + Bookings sections sit
    // further down.
    tester.view.physicalSize = Size(1200, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminPortalV2Screen(theme: ThemeController.instance),
      ),
    );
    // Resolve the admin guard + the Firestore fetch.
    await tester.pumpAndSettle();
  }

  testWidgets('renders all five Task 3 KPI cards', (tester) async {
    final now = DateTime.now();
    await firestore.collection('users').doc('u1').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'subscriptionProduct': 'hunter_monthly',
      'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
      'createdAt': Timestamp.fromDate(now),
    });

    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('adminV2CardNewUsers')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardTrialActive')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('adminV2CardTrialExpiredNoSub')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardSubscribedHunters')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardSubscribedOutfitters')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardTrialToPaidConversion')),
        findsOneWidget);
  });

  testWidgets('subscribed hunter count reflects the Firestore document',
      (tester) async {
    final now = DateTime.now();
    await firestore.collection('users').doc('h1').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
    });
    await firestore.collection('users').doc('h2').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
    });

    await pumpScreen(tester);

    // The Subscribed Hunters card renders "2".
    final card = find.byKey(const ValueKey('adminV2CardSubscribedHunters'));
    expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget);
  });

  testWidgets('date filter changes ONLY New Users (snapshots stay fixed)',
      (tester) async {
    final now = DateTime.now();
    // A trial-active user created long ago (outside Today, inside All Time).
    await firestore.collection('users').doc('trial-old').set({
      'role': 'hunter',
      'subscriptionStatus': 'trialing',
      'trialStartedAt': Timestamp.fromDate(now.subtract(const Duration(days: 40))),
      'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 5))),
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 40))),
    });
    // A brand-new user created today. Give it an explicit (future) trial end so
    // the trial-active classification is unambiguous rather than relying on the
    // creation-window fallback.
    await firestore.collection('users').doc('fresh').set({
      'role': 'hunter',
      'subscriptionStatus': 'trialing',
      'trialEndsAt': Timestamp.fromDate(now.add(const Duration(days: 25))),
      'createdAt': Timestamp.fromDate(now),
    });

    await pumpScreen(tester);

    // Default filter is All Time: both accounts are new + both are trial-active.
    final newUsersCard = find.byKey(const ValueKey('adminV2CardNewUsers'));
    final trialCard = find.byKey(const ValueKey('adminV2CardTrialActive'));
    expect(
        find.descendant(of: newUsersCard, matching: find.text('2')),
        findsOneWidget);
    expect(
        find.descendant(of: trialCard, matching: find.text('2')),
        findsOneWidget);

    // Switch to Today: New Users drops to 1, Trial Active stays 2 (a snapshot).
    await tester.tap(find.byKey(const ValueKey('adminV2Filter_today')));
    await tester.pumpAndSettle();

    expect(
        find.descendant(of: newUsersCard, matching: find.text('1')),
        findsOneWidget);
    expect(
        find.descendant(of: trialCard, matching: find.text('2')),
        findsOneWidget);
  });

  testWidgets('renders the filter bar with all four options', (tester) async {
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('adminV2DateFilterBar')), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('30d'), findsOneWidget);
    expect(find.text('All Time'), findsOneWidget);
  });

  testWidgets('shows the Unknown plan note only when a subscriber lacks a plan',
      (tester) async {
    final now = DateTime.now();
    await firestore.collection('users').doc('no-plan').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
      // No subscriptionProduct.
    });

    await pumpScreen(tester);

    expect(find.textContaining('Unknown plan: 1'), findsOneWidget);
  });

  testWidgets('denies access for a non-admin', (tester) async {
    AdminAuthGuard.adminOverrideForTesting = false;
    await pumpScreen(tester);
    expect(find.textContaining('Access denied'), findsOneWidget);
  });

  // ==========================================================================
  // TASK 6 — Subscription KPIs + Subscribers List
  // ==========================================================================

  testWidgets('renders the four subscription KPI cards on the dashboard',
      (tester) async {
    await pumpScreen(tester, height: 6000);

    expect(find.byKey(const ValueKey('adminV2DashTotalSubscribers')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashSubscribedGoogle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashSubscribedPayfast')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashTrialUsers')),
        findsOneWidget);
  });

  testWidgets('subscription KPI counts reconcile Google + PayFast + unknown',
      (tester) async {
    final now = DateTime.now();
    final future = Timestamp.fromDate(now.add(const Duration(days: 30)));
    // 2 Google, 1 PayFast, 1 unknown-provider active subscriber.
    await firestore.collection('users').doc('g1').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'subscriptionPlatform': 'google_play',
      'premiumExpiry': future,
    });
    await firestore.collection('users').doc('g2').set({
      'role': 'outfitter',
      'subscriptionStatus': 'active',
      'subscriptionPlatform': 'google_play',
      'premiumExpiry': future,
    });
    await firestore.collection('users').doc('p1').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'subscriptionSource': 'payfast',
      'premiumExpiry': future,
    });
    await firestore.collection('users').doc('x1').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'premiumExpiry': future,
    });
    // A trial user — counted separately, not as a subscriber.
    await firestore.collection('users').doc('t1').set({
      'role': 'hunter',
      'subscriptionStatus': 'trialing',
      'trialEndsAt': future,
    });

    await pumpScreen(tester, height: 6000);

    final total = find.byKey(const ValueKey('adminV2DashTotalSubscribers'));
    final google = find.byKey(const ValueKey('adminV2DashSubscribedGoogle'));
    final payfast = find.byKey(const ValueKey('adminV2DashSubscribedPayfast'));
    final trial = find.byKey(const ValueKey('adminV2DashTrialUsers'));

    expect(find.descendant(of: total, matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: google, matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: payfast, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: trial, matching: find.text('1')), findsOneWidget);
  });

  testWidgets('renders the Subscribers List section with the count',
      (tester) async {
    final now = DateTime.now();
    await firestore.collection('users').doc('g1').set({
      'role': 'hunter',
      'firstName': 'Google',
      'lastName': 'Guy',
      'subscriptionStatus': 'active',
      'subscriptionPlatform': 'google_play',
      'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
    });

    await pumpScreen(tester, height: 6000);

    expect(find.byKey(const ValueKey('adminV2SubscribersSection')),
        findsOneWidget);
    expect(find.text('Showing 1 subscriber'), findsOneWidget);
    expect(find.text('Google Guy'), findsOneWidget);
  });

  testWidgets('the Users tab renders the CSV export card', (tester) async {
    await firestore.collection('users').doc('u1').set({
      'email': 'u1@x.com',
      'role': 'hunter',
    });
    await pumpScreen(tester, height: 6000);

    await tester.tap(find.byKey(const ValueKey('adminV2Tab_users')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('adminV2UsersExportCard')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adminV2ExportAllUsersButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('adminV2ExportNoRoleUsersButton')),
      findsOneWidget,
    );
    expect(find.textContaining('Export All Users ('), findsOneWidget);
  });

  testWidgets('the export card renders exactly once on the Users tab',
      (tester) async {
    await firestore.collection('users').doc('u1').set({
      'email': 'u1@x.com',
      'role': 'hunter',
    });
    await pumpScreen(tester, height: 6000);

    await tester.tap(find.byKey(const ValueKey('adminV2Tab_users')));
    await tester.pumpAndSettle();

    // Exactly one card (the V2 tab owns it; the page renders no duplicate).
    expect(find.byKey(const ValueKey('adminV2UsersExportCard')), findsOneWidget);
    expect(find.text('Users Export (CSV)'), findsOneWidget);
  });

  testWidgets('the export counts match the fetched user rows', (tester) async {
    // 3 users total, 2 with no role (blank + 'none').
    await firestore.collection('users').doc('h1').set({
      'email': 'h1@x.com',
      'role': 'hunter',
    });
    await firestore.collection('users').doc('n1').set({
      'email': 'n1@x.com',
      'role': '',
    });
    await firestore.collection('users').doc('n2').set({
      'email': 'n2@x.com',
      'role': 'none',
    });
    await pumpScreen(tester, height: 6000);

    await tester.tap(find.byKey(const ValueKey('adminV2Tab_users')));
    await tester.pumpAndSettle();

    expect(find.text('Export All Users (3)'), findsOneWidget);
    expect(find.text('Export No Role (2)'), findsOneWidget);
  });

  // ==========================================================================
  // TASK 4 — Packages + Bookings
  // ==========================================================================

  testWidgets('renders all Task 4 package + booking KPI cards', (tester) async {
    await pumpScreen(tester, height: 6000);

    expect(find.byKey(const ValueKey('adminV2CardTotalPackages')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardActivePackages')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardSoldOutPackages')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('adminV2CardDraftArchivedPackages')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardOutfittersZeroPackages')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardTotalBookings')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardBookingConversion')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardStuckPending')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2CardAvgDaysToConfirm')),
        findsOneWidget);
  });

  testWidgets('renders the province breakdown, both tables + status breakdown',
      (tester) async {
    await pumpScreen(tester, height: 6000);
    expect(find.byKey(const ValueKey('adminV2ProvinceBreakdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2BookingStatusBreakdown')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2ZeroBookingTable')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2StuckPendingTable')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2TopOutfittersTable')),
        findsOneWidget);
  });

  testWidgets('package counts derive from the packages collection',
      (tester) async {
    await firestore.collection('packages').doc('p1').set({
      'outfitterId': 'o1',
      'title': 'Active Hunt',
      'status': 'active',
      'quantityAvailable': 2,
    });
    await firestore.collection('packages').doc('p2').set({
      'outfitterId': 'o1',
      'title': 'Sold Out Hunt',
      'status': 'sold_out',
      'quantityAvailable': 0,
    });

    await pumpScreen(tester, height: 6000);

    final totalCard = find.byKey(const ValueKey('adminV2CardTotalPackages'));
    final activeCard = find.byKey(const ValueKey('adminV2CardActivePackages'));
    final soldOutCard = find.byKey(const ValueKey('adminV2CardSoldOutPackages'));
    expect(find.descendant(of: totalCard, matching: find.text('2')),
        findsOneWidget);
    expect(find.descendant(of: activeCard, matching: find.text('1')),
        findsOneWidget);
    expect(find.descendant(of: soldOutCard, matching: find.text('1')),
        findsOneWidget);
  });

  testWidgets('booking conversion derives from booking statuses',
      (tester) async {
    await firestore.collection('bookings').doc('b1').set({
      'status': 'Confirmed',
      'hunterId': 'h1',
      'outfitterId': 'o1',
    });
    await firestore.collection('bookings').doc('b2').set({
      'status': 'Pending Approval',
      'hunterId': 'h1',
      'outfitterId': 'o1',
    });

    await pumpScreen(tester, height: 6000);

    final totalCard = find.byKey(const ValueKey('adminV2CardTotalBookings'));
    final convCard = find.byKey(const ValueKey('adminV2CardBookingConversion'));
    expect(find.descendant(of: totalCard, matching: find.text('2')),
        findsOneWidget);
    // 1 confirmed / 2 total = 50.0%
    expect(find.descendant(of: convCard, matching: find.text('50.0%')),
        findsOneWidget);
  });

  testWidgets('zero-booking table shows an active package with no booking',
      (tester) async {
    await firestore.collection('packages').doc('lonely').set({
      'outfitterId': 'o1',
      'title': 'Lonely Package',
      'status': 'active',
      'quantityAvailable': 5,
    });

    await pumpScreen(tester, height: 6000);

    expect(find.text('Lonely Package'), findsOneWidget);
  });

  testWidgets('a missing farm / missing paymentVerifiedAt never crashes',
      (tester) async {
    // Package with no farmId (Unknown Province) + a booking with no
    // paymentVerifiedAt (Avg Days renders "—").
    await firestore.collection('packages').doc('p1').set({
      'outfitterId': 'o1',
      'title': 'No Farm Package',
      'status': 'active',
      'quantityAvailable': 1,
    });
    await firestore.collection('bookings').doc('b1').set({
      'status': 'Confirmed',
      'hunterId': 'h1',
      'outfitterId': 'o1',
    });

    await pumpScreen(tester, height: 6000);

    expect(tester.takeException(), isNull);
    expect(find.text('Unknown Province'), findsOneWidget);
    final avgCard = find.byKey(const ValueKey('adminV2CardAvgDaysToConfirm'));
    expect(find.descendant(of: avgCard, matching: find.text('—')),
        findsOneWidget);
  });

  // ==========================================================================
  // HEADER APP VERSION
  // ==========================================================================

  group('header app version', () {
    tearDown(() {
      // PackageInfo.setMockInitialValues writes a process-global singleton;
      // clear it so a mocked version cannot leak into another suite.
      PackageInfo.setMockInitialValues(
        appName: 'jagspoor',
        packageName: 'za.co.jagspoor.app',
        version: VersionInfo.fallbackVersionName,
        buildNumber: VersionInfo.fallbackVersionCode,
        buildSignature: '',
      );
    });

    testWidgets('header shows the version label matching VersionInfo',
        (tester) async {
      // Drive a deterministic live resolution so the assertion proves the
      // label is sourced from VersionInfo (not a hardcoded string).
      PackageInfo.setMockInitialValues(
        appName: 'jagspoor',
        packageName: 'za.co.jagspoor.app',
        version: '9.9.9',
        buildNumber: '99',
        buildSignature: '',
      );

      await pumpScreen(tester);

      // The label reads the SAME source as VersionInfo (name + code).
      final expected = VersionInfo.label(name: '9.9.9', code: '99');
      expect(expected, 'v9.9.9+99');

      final labelFinder = find.byKey(const ValueKey('adminV2VersionLabel'));
      expect(labelFinder, findsOneWidget);
      expect(tester.widget<Text>(labelFinder).data, expected);

      // The title wordmark is still present beside it.
      expect(find.text('🛡️ Admin Portal V2'), findsOneWidget);
    });

    testWidgets('version label is in the header, so it shows on every tab',
        (tester) async {
      await pumpScreen(tester, height: 6000);

      // Present on the default Dashboard tab…
      expect(find.byKey(const ValueKey('adminV2VersionLabel')),
          findsOneWidget);

      // …and unchanged after switching to each of the other tabs.
      for (final tab in const [
        'users',
        'packages',
        'bookings',
        'revenue',
        'accountManagement',
      ]) {
        await tester.tap(find.byKey(ValueKey('adminV2Tab_$tab')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('adminV2VersionLabel')),
          findsOneWidget,
          reason: 'version label must render on the $tab tab',
        );
      }
    });

    // JOB 1 — V2 owns the old portal's unique account actions.
    testWidgets('Account Management tab offers Create User + Bulk CSV Import',
        (tester) async {
      await pumpScreen(tester, height: 6000);
      await tester.tap(
          find.byKey(const ValueKey('adminV2Tab_accountManagement')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('adminV2AccountManagementTab')),
          findsOneWidget);
      expect(find.text('Create User'), findsWidgets);
      expect(find.text('Bulk CSV Import'), findsWidgets);
      // The old portal's "Admin Portal V2" entry card is gone — V2 IS the
      // portal, there is nothing to navigate to.
      expect(find.text('Admin Portal V2 card'), findsNothing);
    });

    testWidgets('version label never renders "Unknown" when unresolved',
        (tester) async {
      // Simulate an unresolved bundle (Web / headless): a blank name + code
      // must fall back to the pubspec-mirrored constants, not "Unknown".
      PackageInfo.setMockInitialValues(
        appName: 'jagspoor',
        packageName: 'za.co.jagspoor.app',
        version: '',
        buildNumber: '',
        buildSignature: '',
      );

      await pumpScreen(tester);

      final expected =
          'v${VersionInfo.fallbackVersionName}+${VersionInfo.fallbackVersionCode}';
      final labelFinder = find.byKey(const ValueKey('adminV2VersionLabel'));
      expect(labelFinder, findsOneWidget);
      final labelText = tester.widget<Text>(labelFinder).data;
      expect(labelText, expected);
      // The label itself must never read "Unknown" on any platform.
      expect(labelText, isNot(contains('Unknown')));
    });
  });
}
