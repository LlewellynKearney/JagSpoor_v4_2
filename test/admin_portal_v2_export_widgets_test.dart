import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/models/admin_subscription_metrics.dart';
import 'package:jagspoor/features/admin/models/admin_user_metrics.dart';
import 'package:jagspoor/features/admin/widgets/admin_subscribers_list_section.dart';
import 'package:jagspoor/features/admin/widgets/admin_users_export_card.dart';

/// Widget tests for the Admin Portal V2 export card + Subscribers List.
///
/// The export card's CSV hand-off is injected so no browser / share sheet is
/// touched; the assertions cover the button labels + counts, the admin gate,
/// the filter / search wiring, and the KPI card rendering.
void main() {
  final now = DateTime(2026, 11, 15);

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      );

  AdminUserRecord rec({
    required String uid,
    String email = '',
    String name = '',
    String role = '',
    String provider = '',
    String plan = 'hunter_monthly',
    String status = 'active',
    DateTime? start,
    DateTime? premiumExpiry,
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
        premiumExpiry: premiumExpiry,
      );

  group('AdminUsersExportCard', () {
    testWidgets('renders both export buttons with the row counts',
        (tester) async {
      final records = [
        rec(uid: 'a', email: 'a@x.com', role: 'hunter'),
        rec(uid: 'b', email: 'b@x.com', role: ''),
        rec(uid: 'c', email: 'c@x.com', role: 'none'),
      ];

      await tester.pumpWidget(wrap(AdminUsersExportCard(
        theme: ThemeController.instance,
        records: records,
        isAdmin: true,
      )));

      expect(find.text('Export All Users (3)'), findsOneWidget);
      expect(find.text('Export No Role (2)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('adminV2ExportAllUsersButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adminV2ExportNoRoleUsersButton')),
        findsOneWidget,
      );
    });

    testWidgets('counts match the CSV row count exactly', (tester) async {
      final records = List.generate(7, (i) => rec(uid: 'u$i', email: 'u$i@x.com'));
      // Two have no role.
      records[0] = rec(uid: 'u0', email: 'u0@x.com', role: 'hunter');
      records[1] = rec(uid: 'u1', email: 'u1@x.com', role: 'hunter');
      records[2] = rec(uid: 'u2', email: 'u2@x.com', role: 'outfitter');
      records[3] = rec(uid: 'u3', email: 'u3@x.com', role: 'outfitter');
      records[4] = rec(uid: 'u4', email: 'u4@x.com', role: 'outfitter');

      await tester.pumpWidget(wrap(AdminUsersExportCard(
        theme: ThemeController.instance,
        records: records,
        isAdmin: true,
      )));

      expect(find.text('Export All Users (7)'), findsOneWidget);
      expect(find.text('Export No Role (2)'), findsOneWidget);
    });

    testWidgets('tapping Export All delivers the all-users CSV', (tester) async {
      String? capturedName;
      String? capturedContent;

      await tester.pumpWidget(wrap(AdminUsersExportCard(
        theme: ThemeController.instance,
        records: [
          rec(uid: 'a', email: 'a@x.com', role: 'hunter'),
          rec(uid: 'b', email: 'b@x.com', role: ''),
        ],
        isAdmin: true,
        deliverOverride: ({required fileName, required content}) async {
          capturedName = fileName;
          capturedContent = content;
          return true;
        },
      )));

      await tester.tap(find.byKey(const ValueKey('adminV2ExportAllUsersButton')));
      await tester.pumpAndSettle();

      expect(capturedName, startsWith('jagspoor-users-'));
      expect(capturedName, endsWith('.csv'));
      expect(capturedContent, contains('a@x.com'));
      expect(capturedContent, contains('b@x.com'));
      // A success snackbar is shown.
      expect(find.textContaining('Exported 2 users'), findsOneWidget);
    });

    testWidgets('tapping Export No Role delivers only the no-role CSV',
        (tester) async {
      String? capturedName;
      String? capturedContent;

      await tester.pumpWidget(wrap(AdminUsersExportCard(
        theme: ThemeController.instance,
        records: [
          rec(uid: 'a', email: 'a@x.com', role: 'hunter'),
          rec(uid: 'b', email: 'b@x.com', role: ''),
        ],
        isAdmin: true,
        deliverOverride: ({required fileName, required content}) async {
          capturedName = fileName;
          capturedContent = content;
          return true;
        },
      )));

      await tester
          .tap(find.byKey(const ValueKey('adminV2ExportNoRoleUsersButton')));
      await tester.pumpAndSettle();

      expect(capturedName, startsWith('jagspoor-users-no-role-'));
      expect(capturedContent, isNot(contains('a@x.com')));
      expect(capturedContent, contains('b@x.com'));
    });

    testWidgets('a non-admin sees the Admin only note and no export happens',
        (tester) async {
      var delivered = false;

      await tester.pumpWidget(wrap(AdminUsersExportCard(
        theme: ThemeController.instance,
        records: [rec(uid: 'a', email: 'a@x.com', role: 'hunter')],
        isAdmin: false,
        deliverOverride: ({required fileName, required content}) async {
          delivered = true;
          return true;
        },
      )));

      expect(find.textContaining('Admin only'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('adminV2ExportAllUsersButton')));
      await tester.pumpAndSettle();

      // No file handed off, and the "Admin only" message is surfaced.
      expect(delivered, isFalse);
      expect(find.textContaining('Admin only'), findsWidgets);
    });

    testWidgets('a failed hand-off shows a failure message', (tester) async {
      await tester.pumpWidget(wrap(AdminUsersExportCard(
        theme: ThemeController.instance,
        records: [rec(uid: 'a', email: 'a@x.com', role: 'hunter')],
        isAdmin: true,
        deliverOverride: ({required fileName, required content}) async => false,
      )));

      await tester.tap(find.byKey(const ValueKey('adminV2ExportAllUsersButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not export'), findsOneWidget);
    });
  });

  group('AdminSubscribersListSection', () {
    AdminSubscriptionMetrics metricsFor(List<AdminUserRecord> records) =>
        AdminSubscriptionMetrics.aggregate(records, now: now);

    testWidgets('renders the table + the "Showing X subscribers" count',
        (tester) async {
      final metrics = metricsFor([
        rec(
          uid: 'g',
          email: 'g@x.com',
          name: 'Google Guy',
          provider: 'google_play',
          start: DateTime(2026, 10, 1),
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
        rec(
          uid: 'p',
          email: 'p@x.com',
          name: 'PayFast Pete',
          provider: 'payfast',
          start: DateTime(2026, 9, 1),
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
      ]);

      await tester.pumpWidget(wrap(AdminSubscribersListSection(
        theme: ThemeController.instance,
        metrics: metrics,
      )));

      expect(
        find.byKey(const ValueKey('adminV2SubscribersSection')),
        findsOneWidget,
      );
      expect(find.text('Showing 2 subscribers'), findsOneWidget);
      expect(find.text('Google Guy'), findsOneWidget);
      expect(find.text('PayFast Pete'), findsOneWidget);
      // The provider badges live in the table (the filter chips also carry
      // "Google" / "PayFast", so scope the assertion to the table).
      final table = find.byKey(const ValueKey('adminV2SubscribersTable'));
      expect(
        find.descendant(of: table, matching: find.text('Google')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text('PayFast')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text('Active')),
        findsNWidgets(2),
      );
    });

    testWidgets('the filter dropdown narrows the visible rows', (tester) async {
      final metrics = metricsFor([
        rec(
          uid: 'g',
          email: 'g@x.com',
          name: 'Google Guy',
          provider: 'google_play',
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
        rec(
          uid: 'p',
          email: 'p@x.com',
          name: 'PayFast Pete',
          provider: 'payfast',
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
      ]);

      await tester.pumpWidget(wrap(AdminSubscribersListSection(
        theme: ThemeController.instance,
        metrics: metrics,
      )));

      await tester.tap(find.byKey(const ValueKey('adminV2SubscriberFilter_google')));
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 subscriber'), findsOneWidget);
      expect(find.text('Google Guy'), findsOneWidget);
      expect(find.text('PayFast Pete'), findsNothing);
    });

    testWidgets('search by email narrows the rows', (tester) async {
      final metrics = metricsFor([
        rec(
          uid: 'g',
          email: 'g@x.com',
          name: 'Google Guy',
          provider: 'google_play',
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
        rec(
          uid: 'p',
          email: 'p@x.com',
          name: 'PayFast Pete',
          provider: 'payfast',
          premiumExpiry: now.add(const Duration(days: 30)),
        ),
      ]);

      await tester.pumpWidget(wrap(AdminSubscribersListSection(
        theme: ThemeController.instance,
        metrics: metrics,
      )));

      await tester.enterText(find.byType(TextField), 'payfast');
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 subscriber'), findsOneWidget);
      expect(find.text('PayFast Pete'), findsOneWidget);
      expect(find.text('Google Guy'), findsNothing);
    });

    testWidgets('an empty list renders the empty-state copy', (tester) async {
      await tester.pumpWidget(wrap(AdminSubscribersListSection(
        theme: ThemeController.instance,
        metrics: const AdminSubscriptionMetrics(),
      )));

      expect(find.text('Showing 0 subscribers'), findsOneWidget);
      expect(find.textContaining('No subscribers match'), findsOneWidget);
    });
  });
}
