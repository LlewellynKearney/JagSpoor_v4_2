import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart';

/// Layout contract for the Booking Requests screen header:
/// - the transparent full-bleed AppBar's title + back button must clear the
///   device's system status bar;
/// - the bushveld background image must still extend to the top edge of the
///   screen (behind the AppBar);
/// - the category filter bar must render fully BELOW the AppBar (the old
///   `kToolbarHeight + kTextTabBarHeight` spacer was ~26px short because the
///   icon+text tabs are taller than `kTextTabBarHeight`, so the filter bar
///   slid up underneath the TabBar).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const statusBarHeight = 32.0;

  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    OutfitterBookingDashboardScreen.firestoreForTesting = fake;
    OutfitterBookingDashboardScreen.currentUserIdResolverForTesting =
        () => 'test-uid';
  });

  tearDown(() {
    OutfitterBookingDashboardScreen.firestoreForTesting = null;
    OutfitterBookingDashboardScreen.currentUserIdResolverForTesting = null;
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await fake.collection('bookings').doc('b1').set({
      'outfitterId': 'test-uid',
      'hunterId': 'h1',
      'packageId': 'CUSTOM_BUILT',
      'packageName': 'Custom Package · Bosveld',
      'status': 'Pending Approval',
      'bookingTimestamp': 1700000000000,
      'totalHunterPriceRands': 1000.0,
    });
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(top: statusBarHeight),
          padding: EdgeInsets.only(top: statusBarHeight),
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OutfitterBookingDashboardScreen(
                        theme: ThemeController(),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('title + back button clear the system status bar',
      (tester) async {
    await pumpScreen(tester);

    final title = find.text('💳 Booking Requests');
    expect(title, findsOneWidget);
    expect(
      tester.getTopLeft(title).dy,
      greaterThanOrEqualTo(statusBarHeight),
      reason: 'The AppBar title must clear the system status bar.',
    );

    final backButton = find.byIcon(Icons.arrow_back);
    expect(backButton, findsOneWidget);
    expect(
      tester.getTopLeft(backButton).dy,
      greaterThanOrEqualTo(statusBarHeight),
      reason: 'The back button must clear the system status bar.',
    );
  });

  testWidgets('bushveld background still extends to the top edge',
      (tester) async {
    await pumpScreen(tester);

    final networkImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((img) => img.image is NetworkImage)
        .toList();
    expect(networkImages, isNotEmpty,
        reason: 'The bushveld network background must be present.');
    expect(
      tester.getTopLeft(find.byWidget(networkImages.first)).dy,
      0.0,
      reason: 'The background image must extend to the top edge.',
    );
  });

  testWidgets('category filter bar renders fully below the AppBar',
      (tester) async {
    await pumpScreen(tester);

    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final filterChipTop =
        tester.getTopLeft(find.text('Standard Hunting Packages')).dy;
    expect(
      filterChipTop,
      greaterThanOrEqualTo(appBarBottom),
      reason: 'The category filter bar must not be overlapped by the '
          'AppBar + TabBar header.',
    );
  });
}
