import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/payfast_secure_footer.dart';
import 'package:jagspoor/core/widgets/splash_logo.dart';
import 'package:jagspoor/features/admin/services/subscription_config_service.dart';
import 'package:jagspoor/features/billing/billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';
import 'package:jagspoor/features/subscription/subscription_screen.dart';

/// Regression guards for three reported defects:
///   1. the splash logo filled the viewport on a wide browser window,
///   2. the web build still rendered the red "MANAGE IN GOOGLE PLAY" button
///      for an active subscriber whose platform was google_play / unknown,
///   3. the subscription checkout had no PayFast trust footer.
void main() {
  group('splash logo is bounded (never fills the viewport)', () {
    testWidgets('the logo is capped at 200px and 22% of the viewport height',
        (tester) async {
      // A wide, short viewport — the exact shape that used to balloon the
      // logo (width * 0.6 drove BOTH dimensions).
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SplashLogo())),
      );
      await tester.pump();

      final image = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) => w is Image && w.image is AssetImage,
        ),
      );
      final provider = image.image as AssetImage;
      expect(provider.assetName, 'assets/app logo/logo1.png');
      expect(image.fit, BoxFit.contain);

      // The logo must sit inside a ConstrainedBox whose maxWidth is the
      // 160/200 cap (NOT the raw viewport width) and whose maxHeight is 22%
      // of the viewport height.
      final box = tester.widget<ConstrainedBox>(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(ConstrainedBox),
        ).first,
      );
      final constraints = box.constraints;
      expect(constraints.maxWidth, lessThanOrEqualTo(200));
      expect(constraints.maxHeight, closeTo(900 * 0.22, 1.0));

      // And the rendered logo must be far smaller than the 1600px viewport.
      final size = tester.getSize(find.byType(Image));
      expect(size.width, lessThanOrEqualTo(200));
      expect(size.width, lessThan(1600 * 0.2));

      // It is centred and padded.
      expect(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(Center),
        ),
        findsWidgets,
      );
      final padding = tester.widget<Padding>(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(Padding),
        ).first,
      );
      expect(padding.padding, const EdgeInsets.all(SplashLogo.padding));
    });

    test('the splash body is centred + scroll-safe and uses the bounded logo',
        () {
      // Structural contract: the boot gate performs Firebase reads, so the
      // live SplashScreen cannot be mounted in a widget test without a
      // Firebase app. Parse the source instead (the established pattern for
      // these source-level contracts) to lock the layout shape.
      final source =
          File('lib/core/splash_screen.dart').readAsStringSync();
      // The bounded, aspect-preserving logo widget is what renders.
      expect(source, contains('const SplashLogo()'));
      expect(source, isNot(contains('size.width * 0.6')));
      // Centred but scrollable, so a short viewport cannot overflow the
      // logo + wordmark + spinner + footer Column.
      expect(source, contains('SingleChildScrollView'));
      expect(source, contains('minHeight: constraints.maxHeight'));
      expect(source, contains('mainAxisAlignment: MainAxisAlignment.center'));
    });
  });

  group('PayFast secure footer', () {
    testWidgets('renders the bundled logo + caption', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PayFastSecureFooter()),
        ),
      );
      await tester.pump();

      expect(PayFastSecureFooter.logoAsset, 'assets/images/payfast_logo.png');
      expect(find.text('Secure payments by PayFast'), findsOneWidget);
      final image = tester.widget<Image>(
        find.byWidgetPredicate((w) => w is Image && w.image is AssetImage),
      );
      expect((image.image as AssetImage).assetName,
          'assets/images/payfast_logo.png');
      expect(image.height, 32);
      expect(image.fit, BoxFit.contain);
    });
  });

  group('web hides the Google Play manager for an active subscriber', () {
    late FakeFirebaseFirestore fake;

    setUp(() {
      fake = FakeFirebaseFirestore();
      SubscriptionStatusService.firestoreForTesting = fake;
      SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
      SubscriptionConfigService.firestoreForTesting = fake;
      SubscriptionConfigService.currentUserIdResolverForTesting = () => 'a-1';
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

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SubscriptionScreen(
          theme: ThemeController(),
          tier: SubscriptionTier.hunter,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> scrollToBottom(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pump();
      }
    }

    testWidgets(
        'an ACTIVE subscriber whose platform is google_play gets NO Play '
        'button on web (PayFast manage + footer instead)', (tester) async {
      BillingService.usesPayFastForTesting = true;
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        // The platform recorded on the doc is Play — but this is a browser,
        // so a Play manager link is meaningless and must not render.
        'subscriptionPlatform': 'google_play',
        'subscriptionTier': 'hunter',
      });
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      expect(find.byKey(const ValueKey('cancelSubscriptionButton')),
          findsNothing);
      expect(find.text('MANAGE SUBSCRIPTION ON PAYFAST'), findsOneWidget);
      // The PayFast trust footer renders on the web checkout.
      expect(find.byType(PayFastSecureFooter), findsOneWidget);
    });

    testWidgets(
        'an ACTIVE subscriber whose platform is UNKNOWN gets NO Play button '
        'on web', (tester) async {
      BillingService.usesPayFastForTesting = true;
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
        // No subscriptionPlatform at all — the pre-fix code defaulted this
        // straight to the red "MANAGE IN GOOGLE PLAY" button.
      });
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      expect(find.text('MANAGE SUBSCRIPTION ON PAYFAST'), findsOneWidget);
    });

    testWidgets('a NATIVE active subscriber still gets MANAGE IN GOOGLE PLAY '
        'and NO PayFast footer', (tester) async {
      BillingService.usesPayFastForTesting = false;
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionPlatform': 'google_play',
        'subscriptionTier': 'hunter',
      });
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsOneWidget);
      expect(find.text('MANAGE SUBSCRIPTION ON PAYFAST'), findsNothing);
      // Never advertise a third-party payment provider on a Play screen.
      expect(find.byType(PayFastSecureFooter), findsNothing);
    });

    testWidgets('the web checkout shows the PayFast footer for a trial too',
        (tester) async {
      BillingService.usesPayFastForTesting = true;
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt':
            DateTime.now().add(const Duration(days: 20)),
      });
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.byType(PayFastSecureFooter), findsOneWidget);
      expect(find.text('SUBSCRIBE VIA PAYFAST'), findsOneWidget);
    });

    // The exact reported scenario: a TRIAL user on the web taps Subscriptions.
    // The red "MANAGE IN GOOGLE PLAY" button must never appear — not for the
    // Hunter path, not for the Outfitter path.
    testWidgets('a WEB HUNTER trial shows no Play button, PayFast CTA + footer',
        (tester) async {
      BillingService.usesPayFastForTesting = true;
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt':
            DateTime.now().add(const Duration(days: 20)),
      });
      await pumpScreen(tester);
      await scrollToBottom(tester);

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      expect(find.byKey(const ValueKey('cancelSubscriptionButton')),
          findsNothing);
      expect(find.text('SUBSCRIBE VIA PAYFAST'), findsOneWidget);
      expect(find.byType(PayFastSecureFooter), findsOneWidget);
    });

    testWidgets('a WEB OUTFITTER trial shows no Play button, PayFast CTA + '
        'footer', (tester) async {
      BillingService.usesPayFastForTesting = true;
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'outfitter',
        'subscriptionTrialEndsAt':
            DateTime.now().add(const Duration(days: 20)),
      });
      await tester.pumpWidget(MaterialApp(
        home: SubscriptionScreen(
          theme: ThemeController(),
          tier: SubscriptionTier.outfitter,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await scrollToBottom(tester);

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      expect(find.byKey(const ValueKey('cancelSubscriptionButton')),
          findsNothing);
      expect(find.text('SUBSCRIBE VIA PAYFAST'), findsOneWidget);
      expect(find.byType(PayFastSecureFooter), findsOneWidget);
      // Both Outfitter plan cards (Monthly + Yearly) render on the web.
      expect(find.text('Outfitter Monthly'), findsOneWidget);
      expect(find.text('Outfitter Yearly'), findsOneWidget);
      expect(find.text('R 299.99/month'), findsOneWidget);
      expect(find.text('R 2999.99/year'), findsOneWidget);
    });

    testWidgets('a WEB subscriber with a legacy PayFast platform also gets no '
        'Play button', (tester) async {
      BillingService.usesPayFastForTesting = true;
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionPlatform': 'payfast',
        'subscriptionTier': 'outfitter',
      });
      await tester.pumpWidget(MaterialApp(
        home: SubscriptionScreen(
          theme: ThemeController(),
          tier: SubscriptionTier.outfitter,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await scrollToBottom(tester);

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      expect(find.text('MANAGE SUBSCRIPTION ON PAYFAST'), findsOneWidget);
    });

    test('the web branch of _buildSubscribeButton can never reach the Play '
        'manager builder', () {
      // Structural contract: the FIRST thing _buildSubscribeButton does is
      // branch on the PLATFORM (`_isWebBilling` == kIsWeb) and return — so on
      // a browser build the native block below (which is the only caller of
      // _buildManageInGooglePlayButton) is unreachable. The Play manager
      // builder is also independently guarded on `!_isWebBilling`.
      final source = File('lib/features/subscription/subscription_screen.dart')
          .readAsStringSync();
      final methodStart = source.indexOf('Widget _buildSubscribeButton(');
      // The DEFINITION (not the call site inside _buildSubscribeButton).
      final methodEnd = source.indexOf('Widget _buildManageInGooglePlayButton(');
      expect(methodStart, greaterThan(-1));
      expect(methodEnd, greaterThan(methodStart));
      final body = source.substring(methodStart, methodEnd);

      // The web guard comes FIRST and returns before the native branch.
      final webGuard = body.indexOf('if (_isWebBilling) {');
      // The native branch is gated on `isActive` (NOT `hasSubscription`): a
      // live free trial has never been charged, so it must fall through to the
      // checkout CTA rather than the Play manager.
      final nativeGuard = body.indexOf('if (sub.isActive) {');
      expect(webGuard, greaterThan(-1));
      expect(nativeGuard, greaterThan(webGuard));
      expect(body.contains('if (sub.hasSubscription) {'), isFalse,
          reason: 'hasSubscription includes a live free trial, which must '
              'reach the checkout CTA, not the Play manager');
      // Nothing between the start and the web guard calls the Play builder.
      expect(body.substring(0, webGuard).contains('_buildManageInGooglePlay'),
          isFalse);
      // The Play manager builder is itself web-guarded (defense in depth).
      expect(
        source.substring(methodEnd, methodEnd + 300),
        contains('if (_isWebBilling) return const SizedBox.shrink();'),
      );
    });
  });
}
