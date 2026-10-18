import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/services/subscription_config_service.dart';
import 'package:jagspoor/features/billing/billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';
import 'package:jagspoor/features/subscription/subscription_screen.dart';

/// Web-billing routing contract for the subscription checkout.
///
/// The web build charges through PayFast; Google Play Billing does not exist
/// in a browser. These tests lock two things the web build got wrong:
///   1. the Google Play affordances ("MANAGE IN GOOGLE PLAY", "RESTORE
///      PURCHASES") must be HIDDEN on the web, and
///   2. the checkout must be centred at 800px on a desktop-width viewport
///      instead of stretching edge-to-edge.
void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    SubscriptionStatusService.firestoreForTesting = fake;
    SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
    SubscriptionConfigService.firestoreForTesting = fake;
    SubscriptionConfigService.currentUserIdResolverForTesting = () => 'admin-1';
    fake.collection('admin_config').doc('pricing').set({
      'hunter_monthly': 34.99,
      'outfitter_monthly': 299.99,
    });
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async => true,
    );
  });

  tearDown(() {
    SubscriptionStatusService.resetTestSeams();
    SubscriptionConfigService.resetTestSeams();
    PlayBillingService.resetTestSeams();
    BillingService.resetTestSeams();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });

  Widget buildScreen({SubscriptionTier? tier}) => MaterialApp(
        home: SubscriptionScreen(theme: ThemeController(), tier: tier),
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Scrolls the checkout list to its end so the below-the-fold action buttons
  /// (subscribe / manage / restore) are actually built. A [ListView] builds
  /// lazily, so an unscrolled `findsNothing` would pass trivially.
  Future<void> scrollToBottom(WidgetTester tester) async {
    // Several bounded drags so the lazily-built list reaches its end and the
    // action buttons are genuinely mounted before we assert on them.
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();
    }
  }

  group('web build (PayFast) hides the Google Play affordances', () {
    setUp(() => BillingService.usesPayFastForTesting = true);

    testWidgets('no RESTORE PURCHASES and no MANAGE IN GOOGLE PLAY',
        (tester) async {
      await pumpScreen(tester);
      await scrollToBottom(tester);

      // The Play-only restore affordance is a Play Billing requirement.
      expect(find.byKey(const ValueKey('restorePurchasesButton')), findsNothing);
      expect(find.text('RESTORE PURCHASES'), findsNothing);
      // The Play manager affordance cannot work in a browser.
      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      // The PayFast checkout CTA is what renders instead.
      expect(find.text('SUBSCRIBE VIA PAYFAST'), findsOneWidget);
    });

    testWidgets('an active web subscriber is managed on PayFast',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionPlatform': 'payfast',
        'subscriptionTier': 'hunter',
        'subscriptionRenewalDate': DateTime.now().add(const Duration(days: 20)),
      });
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.text('MANAGE SUBSCRIPTION ON PAYFAST'), findsOneWidget);
      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      // The subscribe CTA is replaced by the manage action.
      expect(find.text('SUBSCRIBE VIA PAYFAST'), findsNothing);
    });
  });

  group('native build keeps the Google Play affordances', () {
    setUp(() => BillingService.usesPayFastForTesting = false);

    testWidgets('RESTORE PURCHASES and the Play subscribe CTA render',
        (tester) async {
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.byKey(const ValueKey('restorePurchasesButton')),
          findsOneWidget);
      expect(find.text('SUBSCRIBE VIA GOOGLE PLAY'), findsOneWidget);
      expect(find.text('MANAGE SUBSCRIPTION ON PAYFAST'), findsNothing);
    });

    testWidgets('an active native subscriber is managed in Google Play',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionPlatform': 'google_play',
        'subscriptionTier': 'hunter',
        'subscriptionRenewalDate': DateTime.now().add(const Duration(days: 20)),
      });
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsOneWidget);
      expect(find.text('MANAGE SUBSCRIPTION ON PAYFAST'), findsNothing);
    });
  });

  group('desktop layout', () {
    setUp(() => BillingService.usesPayFastForTesting = true);

    testWidgets('is centred at 800px on a wide viewport', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScreen(tester);

      // The content is capped at 800px rather than filling the 1600px width.
      final constrained = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      expect(
        constrained.any((c) => c.constraints.maxWidth == 800),
        isTrue,
        reason: 'the checkout must be capped at 800px on desktop',
      );
      // And the ListView is genuinely narrower than the viewport.
      final listWidth = tester.getSize(find.byType(ListView).first).width;
      expect(listWidth, lessThanOrEqualTo(800));
    });

    testWidgets('stays full-width on a mobile viewport', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScreen(tester);

      final listWidth = tester.getSize(find.byType(ListView).first).width;
      expect(listWidth, closeTo(390, 1));
    });
  });

  test('the PayFast dashboard URL is the PayFast site', () {
    expect(BillingService.payfastDashboardUrl, startsWith('https://'));
    expect(BillingService.payfastDashboardUrl, contains('payfast.co.za'));
  });
}
