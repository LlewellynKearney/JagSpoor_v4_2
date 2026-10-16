import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/services/subscription_config_service.dart';
import 'package:jagspoor/features/subscription/paywall_screen.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_purchase_recorder.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';
import 'package:jagspoor/features/subscription/subscription_screen.dart';
import 'package:jagspoor/features/subscription/widgets/subscription_management_tile.dart';
import 'package:jagspoor/services/entitlement_service.dart';

/// Google Play Billing compliance.
///
/// A Play-billed subscriber MUST be routed to Google Play's own subscriptions
/// manager and must NEVER be shown a link that steers to an external
/// (website) checkout. Only a PayFast (website) subscriber may see a
/// "Manage subscription on website" affordance.
///
///   * platform == 'google_play' -> the widget tree must NOT contain the text
///     "on website".
///   * platform == 'payfast'     -> it MUST contain "on website".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A future expiry makes `isPremiumActive` true (the hotfix requires an
  // expiry), so the settings tile renders the "active" branch.
  final playEntitlement = UserEntitlement(
    isPremium: true,
    premiumExpiry: DateTime(2999, 1, 1),
    subscriptionStatus: 'active',
    subscriptionPlatform: 'google_play',
  );
  final payfastEntitlement = UserEntitlement(
    isPremium: true,
    premiumExpiry: DateTime(2999, 1, 1),
    subscriptionStatus: 'active',
    subscriptionPlatform: 'payfast',
  );

  setUp(() {
    // Never touch the live billing plugin / Firestore from the widget under
    // test: an empty purchase stream + canned (empty) catalog keep the paywall
    // and subscription screen fully offline.
    PlayPurchaseRecorder.resetTestSeams();
    PlayBillingService.resetTestSeams();
    PlayPurchaseRecorder.purchaseStreamForTesting = Stream.value(const []);
    PlayBillingService.productsForTesting = const {};
    PaywallScreen.entitlementForTesting = null;
    // The website/Play deep links go through url_launcher; stub the channel so
    // a tap never reaches a native intent.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async => true,
    );
  });

  tearDown(() {
    PlayPurchaseRecorder.resetTestSeams();
    PlayBillingService.resetTestSeams();
    SubscriptionStatusService.resetTestSeams();
    SubscriptionConfigService.resetTestSeams();
    PaywallScreen.entitlementForTesting = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });

  // ── Platform resolution on the entitlement model ────────────────────────
  group('UserEntitlement billing platform resolution', () {
    test('reads subscriptionPlatform directly', () {
      expect(playEntitlement.billingPlatform, SubscriptionSource.googlePlay);
      expect(playEntitlement.isPlayBilled, isTrue);
      expect(playEntitlement.isPayfastBilled, isFalse);

      expect(
          payfastEntitlement.billingPlatform, SubscriptionSource.payfast);
      expect(payfastEntitlement.isPayfastBilled, isTrue);
      expect(payfastEntitlement.isPlayBilled, isFalse);
    });

    test('falls back to subscriptionSource when platform is absent', () {
      const fromSource = UserEntitlement(
        isPremium: true,
        subscriptionSource: SubscriptionSource.googlePlay,
      );
      expect(fromSource.billingPlatform, SubscriptionSource.googlePlay);
      expect(fromSource.isPlayBilled, isTrue);
    });

    test('tolerates snake_case + billingPlatform aliases', () {
      expect(
        UserEntitlement.fromMap({'subscription_platform': 'google_play'})
            .billingPlatform,
        SubscriptionSource.googlePlay,
      );
      expect(
        UserEntitlement.fromMap({'billingPlatform': 'payfast'})
            .billingPlatform,
        SubscriptionSource.payfast,
      );
    });

    test('is case-insensitive and trims', () {
      expect(
        UserEntitlement.fromMap({'subscriptionPlatform': '  GOOGLE_PLAY '})
            .billingPlatform,
        SubscriptionSource.googlePlay,
      );
    });

    test('trial / unknown platforms resolve to null (never Play, never web)',
        () {
      const trial = UserEntitlement(
        subscriptionSource: SubscriptionSource.trial,
        subscriptionStatus: 'trialing',
      );
      expect(trial.billingPlatform, isNull);
      expect(trial.isPlayBilled, isFalse);
      expect(trial.isPayfastBilled, isFalse);
    });

    test('the entitlement mirror carries the platform through the merge', () {
      const usersDoc = UserEntitlement(subscriptionStatus: 'active');
      const mirror = UserEntitlement(
        isPremium: true,
        subscriptionPlatform: 'google_play',
      );
      final merged = usersDoc.mergePremiumMirror(mirror);
      expect(merged.billingPlatform, SubscriptionSource.googlePlay);
      expect(merged.isPlayBilled, isTrue);
    });

    test('fromEntitlementMirror reads the platform', () {
      final e = UserEntitlement.fromEntitlementMirror({
        'isPremium': true,
        'subscriptionPlatform': 'payfast',
      });
      expect(e.isPayfastBilled, isTrue);
    });
  });

  // ── Paywall compliance ──────────────────────────────────────────────────
  group('PaywallScreen Play compliance', () {
    Widget paywall() => MaterialApp(
          home: PaywallScreen(theme: ThemeController()),
        );

    testWidgets(
        'google_play platform: the widget tree must NOT contain "on website"',
        (tester) async {
      PaywallScreen.entitlementForTesting = playEntitlement;
      await tester.pumpWidget(paywall());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('on website'), findsNothing);
      expect(find.textContaining('website'), findsNothing);
      // The compliant Play affordance + helper text are present.
      expect(find.byKey(const ValueKey('paywallManagePlayButton')),
          findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
      expect(find.text('Subscription billed by Google Play'), findsOneWidget);
      // The website button key is gone entirely.
      expect(find.byKey(const ValueKey('paywallWebsiteButton')), findsNothing);
      // No subscribe call-to-action is offered to an active subscriber.
      expect(find.byKey(const ValueKey('paywallPlaySubscribeButton')),
          findsNothing);
    });

    testWidgets('payfast platform: the widget tree MUST contain "on website"',
        (tester) async {
      PaywallScreen.entitlementForTesting = payfastEntitlement;
      await tester.pumpWidget(paywall());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('on website'), findsOneWidget);
      expect(find.byKey(const ValueKey('paywallManageWebsiteButton')),
          findsOneWidget);
      expect(find.text('Manage subscription on website'), findsOneWidget);
      // No Play manager for a website subscriber, and no subscribe CTA.
      expect(find.byKey(const ValueKey('paywallManagePlayButton')),
          findsNothing);
      expect(find.byKey(const ValueKey('paywallPlaySubscribeButton')),
          findsNothing);
    });

    testWidgets('no active subscription: subscribe CTA, never a website link',
        (tester) async {
      PaywallScreen.entitlementForTesting = const UserEntitlement();
      await tester.pumpWidget(paywall());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('paywallPlaySubscribeButton')),
          findsOneWidget);
      expect(find.textContaining('on website'), findsNothing);
      expect(find.byKey(const ValueKey('paywallWebsiteButton')), findsNothing);
    });

    testWidgets('tapping the Play manager opens the Play subscriptions URL',
        (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          calls.add(call);
          return true;
        },
      );
      PaywallScreen.entitlementForTesting = playEntitlement;
      await tester.pumpWidget(paywall());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const ValueKey('paywallManagePlayButton')));
      await tester.pump();

      final url = calls
          .map((c) => c.arguments)
          .whereType<Map>()
          .map((a) => a['url'])
          .whereType<String>()
          .firstWhere((u) => u.contains('play.google.com'), orElse: () => '');
      expect(url, contains('play.google.com/store/account/subscriptions'));
      expect(url, isNot(contains('jagspoor.co.za')));
    });

    test('the Play manager URL is the subscriptions manager for the package',
        () {
      expect(
        PaywallScreen.playSubscriptionsUrl,
        contains('play.google.com/store/account/subscriptions'),
      );
      expect(PaywallScreen.playSubscriptionsUrl,
          contains('package=za.co.jagspoor.app'));
      expect(PaywallScreen.websiteBillingUrl, contains('jagspoor.co.za'));
    });
  });

  // ── Subscription screen compliance ──────────────────────────────────────
  group('SubscriptionScreen Play compliance', () {
    late FakeFirebaseFirestore fake;

    Future<void> seedUser(String platform) async {
      fake = FakeFirebaseFirestore();
      SubscriptionStatusService.firestoreForTesting = fake;
      SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
      SubscriptionConfigService.firestoreForTesting = fake;
      SubscriptionConfigService.currentUserIdResolverForTesting = () => 'a-1';
      await fake.collection('admin_config').doc('pricing').set({
        'hunter_monthly': 34.99,
        'outfitter_monthly': 299.99,
      });
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
        'subscriptionPlatform': platform,
      });
    }

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

    testWidgets('google_play: manage button is Play, no "on website"',
        (tester) async {
      await seedUser('google_play');
      await pumpScreen(tester);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('cancelSubscriptionButton')),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pump();

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsOneWidget);
      expect(find.textContaining('on website'), findsNothing);
      expect(find.byKey(const ValueKey('manageWebsiteSubscriptionButton')),
          findsNothing);
    });

    testWidgets('payfast: website manage button IS shown', (tester) async {
      await seedUser('payfast');
      await pumpScreen(tester);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('manageWebsiteSubscriptionButton')),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pump();

      expect(find.text('MANAGE SUBSCRIPTION ON WEBSITE'), findsOneWidget);
      expect(find.byKey(const ValueKey('cancelSubscriptionButton')),
          findsNothing);
    });
  });

  // ── Settings / account tile compliance ──────────────────────────────────
  group('SubscriptionManagementTile compliance', () {
    Widget tile(UserEntitlement entitlement) => MaterialApp(
          home: Scaffold(
            body: SubscriptionManagementTile(
              theme: ThemeController(),
              entitlementStream: Stream.value(entitlement),
            ),
          ),
        );

    testWidgets('google_play: no "on website", helper text present',
        (tester) async {
      await tester.pumpWidget(tile(playEntitlement));
      await tester.pump();

      expect(find.textContaining('on website'), findsNothing);
      expect(
          find.byKey(const ValueKey('settingsManagePlaySubscriptionTile')),
          findsOneWidget);
      expect(find.text('Subscription billed by Google Play'), findsOneWidget);
    });

    testWidgets('payfast: "on website" IS present', (tester) async {
      await tester.pumpWidget(tile(payfastEntitlement));
      await tester.pump();

      expect(find.textContaining('on website'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('settingsManageWebsiteSubscriptionTile')),
          findsOneWidget);
    });

    testWidgets('no subscription: informational, no website link',
        (tester) async {
      await tester.pumpWidget(tile(const UserEntitlement()));
      await tester.pump();

      expect(find.textContaining('on website'), findsNothing);
      expect(find.byKey(const ValueKey('settingsNoSubscriptionTile')),
          findsOneWidget);
    });
  });

  // ── Structural: no website checkout deep link anywhere in the app ────────
  group('no website checkout deep link for Play users', () {
    test('the Play manager URL constant is the subscriptions manager', () {
      expect(PlayBillingService.playStoreSubscriptionsBase,
          'https://play.google.com/store/account/subscriptions?sku=');
      expect(
        PlayBillingService.instance
            .subscriptionCenterUrlFor(SubscriptionTier.hunter),
        contains('play.google.com/store/account/subscriptions'),
      );
      expect(
        PlayBillingService.instance
            .subscriptionCenterUrlFor(SubscriptionTier.hunter),
        contains('package=za.co.jagspoor.app'),
      );
    });

    test('the website billing URL is the account billing page, not /pricing',
        () {
      expect(PlayBillingService.websiteBillingUrl,
          'https://jagspoor.co.za/account/billing');
    });
  });
}
