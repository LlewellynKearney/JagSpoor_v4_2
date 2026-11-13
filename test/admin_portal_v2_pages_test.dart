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

/// Widget tests for the Task 6 Admin Portal V2 pages + dashboard layout.
///
/// Covers: the tab bar (Dashboard / Users / Packages / Bookings / Revenue),
/// the four dashboard KPI rows + the three charts, and each page's filters
/// (Users email search + role filter + No Role list; Packages status /
/// province / outfitter filters; Bookings status filter) — all read-only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> pumpScreen(WidgetTester tester, {double height = 2400}) async {
    tester.view.physicalSize = Size(1400, height);
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

  Future<void> openTab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('adminV2Tab_$name')));
    await tester.pumpAndSettle();
  }

  // ==========================================================================
  // Tab bar + dashboard layout
  // ==========================================================================

  testWidgets('renders the five-tab bar', (tester) async {
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('adminV2TabBar')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2Tab_dashboard')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2Tab_users')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2Tab_packages')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2Tab_bookings')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2Tab_revenue')), findsOneWidget);
  });

  testWidgets('dashboard renders the four KPI rows', (tester) async {
    await pumpScreen(tester, height: 4000);
    // Row 1
    expect(find.byKey(const ValueKey('adminV2DashTotalUsers')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashHunters')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashOutfitters')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashNoRole')), findsOneWidget);
    // Row 2
    expect(find.byKey(const ValueKey('adminV2DashMrr')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashTrialActive')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashTrialToPaid')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashRequestsToConfirmed')),
        findsOneWidget);
    // Row 3
    expect(find.byKey(const ValueKey('adminV2DashTotalPackages')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashActivePackages')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashSoldOutPackages')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2DashPackagesZeroBookings')),
        findsOneWidget);
  });

  testWidgets('dashboard renders the three charts', (tester) async {
    await pumpScreen(tester, height: 4000);
    expect(find.byKey(const ValueKey('adminV2ChartNewUsers')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2ChartBookingsByStatus')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2ChartPackagesPerProvince')),
        findsOneWidget);
  });

  testWidgets('dashboard audience tiles derive from Firestore roles',
      (tester) async {
    await firestore.collection('users').doc('h1').set({'role': 'hunter'});
    await firestore.collection('users').doc('o1').set({'role': 'outfitter'});
    await firestore.collection('users').doc('d1').set({
      'role': 'dual',
      'isDualRole': true,
      'roles': ['hunter', 'outfitter'],
    });
    await firestore.collection('users').doc('n1').set({'role': ''});

    await pumpScreen(tester, height: 4000);

    // 4 accounts: hunter(h1) + dual(d1) = 2 hunters; outfitter(o1) + dual(d1)
    // = 2 outfitters; noRole(n1) = 1; total = 4.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adminV2DashTotalUsers')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adminV2DashHunters')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adminV2DashOutfitters')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adminV2DashNoRole')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  // ==========================================================================
  // Users page
  // ==========================================================================

  testWidgets('Users page lists users with plan + provider', (tester) async {
    await firestore.collection('users').doc('h1').set({
      'email': 'hunter@example.com',
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'subscriptionProduct': 'hunter_monthly',
      'subscriptionProvider': 'payfast',
      'premiumExpiry': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30))),
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'users');

    expect(find.byKey(const ValueKey('adminV2UsersPage')), findsOneWidget);
    expect(find.text('hunter@example.com'), findsWidgets);
    expect(find.text('hunter_monthly'), findsOneWidget);
    expect(find.text('payfast'), findsOneWidget);
    expect(find.text('2026-01-02'), findsOneWidget);
  });

  testWidgets('Users page email search filters the table', (tester) async {
    await firestore.collection('users').doc('a').set({
      'email': 'alice@example.com',
      'role': 'hunter',
    });
    await firestore.collection('users').doc('b').set({
      'email': 'bob@example.com',
      'role': 'hunter',
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'users');

    expect(find.text('alice@example.com'), findsWidgets);
    expect(find.text('bob@example.com'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'alice');
    await tester.pumpAndSettle();

    expect(find.text('alice@example.com'), findsWidgets);
    expect(find.text('bob@example.com'), findsNothing);
  });

  testWidgets('Users page role filter isolates the role', (tester) async {
    await firestore.collection('users').doc('h').set({
      'email': 'h@example.com',
      'role': 'hunter',
    });
    await firestore.collection('users').doc('o').set({
      'email': 'o@example.com',
      'role': 'outfitter',
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'users');

    await tester.tap(find.byKey(const ValueKey('adminV2UserRole_outfitter')));
    await tester.pumpAndSettle();

    // The Outfitter row stays; the Hunter row is filtered out of the users
    // table. (The hunter may still appear in the No Role table only if it had
    // no role — it has one, so it is absent entirely.)
    expect(find.text('o@example.com'), findsWidgets);
    expect(find.text('h@example.com'), findsNothing);
  });

  testWidgets('Users page shows the No Role list', (tester) async {
    await firestore.collection('users').doc('n1').set({
      'email': 'norole@example.com',
      'role': '',
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'users');

    expect(find.byKey(const ValueKey('adminV2NoRoleTable')), findsOneWidget);
    expect(find.text('norole@example.com'), findsWidgets);
  });

  // ==========================================================================
  // Packages page
  // ==========================================================================

  testWidgets('Packages page lists province from the farm join', (tester) async {
    await firestore.collection('farms').doc('f1').set({'province': 'Limpopo'});
    await firestore.collection('packages').doc('p1').set({
      'title': 'Kudu Hunt',
      'outfitterId': 'o1',
      'farmId': 'f1',
      'status': 'active',
      'quantityAvailable': 3,
      'createdAt': Timestamp.fromDate(DateTime(2026, 2, 3)),
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'packages');

    expect(find.byKey(const ValueKey('adminV2PackagesPage')), findsOneWidget);
    expect(find.text('Kudu Hunt'), findsOneWidget);
    expect(find.text('Limpopo'), findsWidgets);
    expect(find.text('2026-02-03'), findsOneWidget);
  });

  testWidgets('Packages page status filter narrows the list', (tester) async {
    await firestore.collection('packages').doc('p1').set({
      'title': 'Active One',
      'status': 'active',
      'quantityAvailable': 2,
    });
    await firestore.collection('packages').doc('p2').set({
      'title': 'Sold Out One',
      'status': 'sold_out',
      'quantityAvailable': 0,
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'packages');

    expect(find.text('Active One'), findsOneWidget);
    expect(find.text('Sold Out One'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('adminV2PackageStatus_sold_out')));
    await tester.pumpAndSettle();

    expect(find.text('Sold Out One'), findsOneWidget);
    expect(find.text('Active One'), findsNothing);
  });

  testWidgets('Packages page renders the outfitter dropdown', (tester) async {
    await firestore.collection('packages').doc('p1').set({
      'title': 'Hunt',
      'outfitterId': 'o1',
      'status': 'active',
      'quantityAvailable': 1,
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'packages');

    expect(
      find.byKey(const ValueKey('adminV2PackageOutfitterDropdown')),
      findsOneWidget,
    );
  });

  // ==========================================================================
  // Bookings page
  // ==========================================================================

  testWidgets('Bookings page lists emails + package + status', (tester) async {
    await firestore.collection('users').doc('h1').set({
      'email': 'hunter@example.com',
      'role': 'hunter',
    });
    await firestore.collection('users').doc('o1').set({
      'email': 'outfitter@example.com',
      'role': 'outfitter',
    });
    await firestore.collection('bookings').doc('b1').set({
      'status': 'Confirmed',
      'hunterId': 'h1',
      'outfitterId': 'o1',
      'packageName': 'Kudu Hunt',
      'createdAt': Timestamp.fromDate(DateTime(2026, 3, 4)),
      'paymentVerified': true,
      'paymentVerifiedAt': Timestamp.fromDate(DateTime(2026, 3, 6)),
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'bookings');

    expect(find.byKey(const ValueKey('adminV2BookingsPage')), findsOneWidget);
    expect(find.text('hunter@example.com'), findsWidgets);
    expect(find.text('outfitter@example.com'), findsWidgets);
    expect(find.text('Kudu Hunt'), findsOneWidget);
    expect(find.text('Confirmed'), findsWidgets);
    expect(find.text('2026-03-04'), findsOneWidget);
  });

  testWidgets('Bookings page status filter narrows the list', (tester) async {
    await firestore.collection('bookings').doc('b1').set({
      'status': 'Confirmed',
      'packageName': 'Conf',
    });
    await firestore.collection('bookings').doc('b2').set({
      'status': 'Pending Approval',
      'packageName': 'Pend',
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'bookings');

    expect(find.text('Conf'), findsOneWidget);
    expect(find.text('Pend'), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('adminV2BookingStatus_Pending Approval')));
    await tester.pumpAndSettle();

    expect(find.text('Pend'), findsOneWidget);
    expect(find.text('Conf'), findsNothing);
  });

  testWidgets('Bookings page shows days stuck for a stale pending booking',
      (tester) async {
    await firestore.collection('bookings').doc('stuck').set({
      'status': 'Pending Approval',
      'packageName': 'Old Pending',
      'createdAt':
          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 12))),
    });

    await pumpScreen(tester, height: 4000);
    await openTab(tester, 'bookings');

    // The Days Stuck column renders a number > 7 for the stale booking.
    expect(find.text('Old Pending'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  // ==========================================================================
  // Revenue page
  // ==========================================================================

  testWidgets('Revenue page shows MRR / ARR / split / pipeline', (tester) async {
    final now = DateTime.now();
    await firestore.collection('users').doc('h1').set({
      'role': 'hunter',
      'subscriptionStatus': 'active',
      'subscriptionProduct': 'hunter_monthly',
      'subscriptionProvider': 'payfast',
      'premiumExpiry': Timestamp.fromDate(now.add(const Duration(days: 30))),
    });

    await pumpScreen(tester, height: 6000);
    await openTab(tester, 'revenue');

    expect(find.byKey(const ValueKey('adminV2RevenuePage')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2PageCardTotalMrr')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2PageCardArr')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2PagePlanSplit')), findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2PageProviderSplit')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('adminV2PagePipelineCard')), findsOneWidget);
    expect(find.text('PIPELINE — If all trials convert'), findsOneWidget);
    // ZAR formatting: 1 hunter monthly = R34.99.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adminV2PageCardTotalMrr')),
        matching: find.text('R34.99'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Revenue page never crashes with missing subscription fields',
      (tester) async {
    await firestore.collection('users').doc('x').set({'role': 'hunter'});

    await pumpScreen(tester, height: 6000);
    await openTab(tester, 'revenue');

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adminV2PageCardTotalMrr')),
        matching: find.text('R0.00'),
      ),
      findsOneWidget,
    );
  });
}
