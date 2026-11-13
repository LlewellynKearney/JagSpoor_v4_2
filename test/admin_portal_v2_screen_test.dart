import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/screens/admin_portal_v2_screen.dart';
import 'package:jagspoor/features/admin/services/admin_auth_guard.dart';
import 'package:jagspoor/features/admin/services/admin_operational_metrics_service.dart';
import 'package:jagspoor/features/admin/services/admin_user_metrics_service.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

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
}
