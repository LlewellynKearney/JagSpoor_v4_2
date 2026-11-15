import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/screens/admin_portal_v2_screen.dart';
import 'package:jagspoor/features/admin/services/admin_auth_guard.dart';
import 'package:jagspoor/features/admin/services/admin_operational_metrics_service.dart';
import 'package:jagspoor/features/admin/services/admin_user_metrics_service.dart';
import 'package:jagspoor/features/admin/widgets/admin_v2_common.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

/// Regression tests for the Admin Portal V2 KPI card layout on a NARROW phone.
///
/// The bug (Android, ~360 px): the KPI grid was hard-coded to 4 columns, so a
/// ~80 px card could not fit a full label — "Total Users" broke into
/// "Tot al Use rs" and "R69.98" into "R69. 98". The fix makes the grid 2
/// columns below 600 px and makes both the label and the value single-line
/// (the label ellipsises; the value scales inside a FittedBox).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdminV2MetricCard — single-line contract', () {
    testWidgets('label is single-line + non-wrapping, value is FittedBoxed',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80, // an 80 px card — the worst case on a 4-across phone
            height: 90,
            child: AdminV2MetricCard(
              theme: ThemeController.instance,
              icon: Icons.people_outline,
              label: 'Total Users',
              value: 4,
            ),
          ),
        ),
      ));

      final label = tester.widget<Text>(find.text('Total Users'));
      expect(label.maxLines, 1);
      expect(label.softWrap, isFalse);
      expect(label.overflow, TextOverflow.ellipsis);

      // The value text is wrapped in a FittedBox so "R69.98" can never break.
      final valueFinder = find.text('4');
      final valueText = tester.widget<Text>(valueFinder);
      expect(valueText.maxLines, 1);
      expect(valueText.softWrap, isFalse);
      expect(
        find.ancestor(of: valueFinder, matching: find.byType(FittedBox)),
        findsOneWidget,
      );

      // No overflow error at the narrow width.
      expect(tester.takeException(), isNull);
    });

    testWidgets('a ZAR value is not letter-wrapped at 80 px', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            height: 90,
            child: AdminV2MetricCard(
              theme: ThemeController.instance,
              icon: Icons.payments_outlined,
              label: 'MRR',
              valueLabel: 'R69.98',
            ),
          ),
        ),
      ));

      final value = tester.widget<Text>(find.text('R69.98'));
      expect(value.softWrap, isFalse);
      expect(value.maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('AdminV2MetricGrid — responsive column count', () {
    Future<void> pumpGrid(WidgetTester tester, double width) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: AdminV2MetricGrid(
                children: [
                  for (var i = 0; i < 4; i++)
                    AdminV2MetricCard(
                      theme: ThemeController.instance,
                      icon: Icons.people_outline,
                      label: 'Metric $i',
                      value: i,
                    ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('is 2 columns below 600 px', (tester) async {
      await pumpGrid(tester, 360);
      final grid =
          tester.widget<GridView>(find.byType(GridView).first);
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
    });

    testWidgets('is 4 columns at / above 600 px', (tester) async {
      await pumpGrid(tester, 800);
      final grid =
          tester.widget<GridView>(find.byType(GridView).first);
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 4);
    });
  });

  group('Admin Portal V2 Dashboard at 360 px (Android phone)', () {
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

    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: AdminPortalV2Screen(theme: ThemeController.instance)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('KPI labels render as FULL strings (never split)', (tester) async {
      await firestore.collection('users').doc('u1').set({
        'role': 'hunter',
        'subscriptionStatus': 'active',
        'subscriptionProduct': 'hunter_monthly',
        'createdAt': Timestamp.now(),
      });
      await pumpAt(tester, 360);

      // Full, un-split labels — the exact strings the phone screenshots broke.
      for (final label in const [
        'Total Users',
        'Hunters',
        'Outfitters',
        'No Role',
        'Trial Active',
      ]) {
        expect(find.text(label), findsWidgets,
            reason: '"$label" must render as one whole string');
      }
      // The old broken fragments must NOT exist anywhere.
      for (final fragment in const ['Tot al', 'Use rs', 'Hu nte rs', 'Out fitt']) {
        expect(find.textContaining(fragment), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the KPI grids are 2-across on the phone', (tester) async {
      await pumpAt(tester, 360);
      final grids = tester
          .widgetList<GridView>(find.byType(GridView))
          .map((g) => g.gridDelegate)
          .whereType<SliverGridDelegateWithFixedCrossAxisCount>()
          .toList();
      expect(grids, isNotEmpty);
      for (final d in grids) {
        expect(d.crossAxisCount, 2,
            reason: 'every KPI grid is 2-across on a 360 px phone');
      }
    });
  });
}
