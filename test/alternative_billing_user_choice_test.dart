import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/services/subscription_config_service.dart';
import 'package:jagspoor/features/billing/alternative_billing_service.dart';
import 'package:jagspoor/features/billing/billing_plans.dart';
import 'package:jagspoor/features/billing/billing_service.dart';
import 'package:jagspoor/features/subscription/services/play_billing_service.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';
import 'package:jagspoor/features/subscription/subscription_screen.dart';

/// Google Play **User Choice Billing** (alternative billing) contract.
///
/// Play's policy for the alternative billing programme requires that an
/// Android build:
///   1. offers BOTH Google Play and the alternative system (PayFast),
///   2. lets the user actively choose (never auto-defaulting to PayFast and
///      never hiding Google Play), and
///   3. shows the required service-fee disclosure plus the dispute contact.
///
/// The web build is outside Play billing entirely: it must show PayFast only
/// and no Google Play affordance whatsoever (the hard rule established by
/// commit 8d5d29e).
void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    fake = FakeFirebaseFirestore();
    SubscriptionStatusService.firestoreForTesting = fake;
    SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
    SubscriptionConfigService.firestoreForTesting = fake;
    SubscriptionConfigService.currentUserIdResolverForTesting = () => 'admin-1';
    fake.collection('admin_config').doc('pricing').set({
      'hunter_monthly': 34.99,
      'hunter_yearly': 349.99,
      'outfitter_monthly': 299.99,
      'outfitter_yearly': 2999.99,
    });
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
    AlternativeBillingService.resetTestSeams();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });

  Widget buildScreen({SubscriptionTier? tier}) => MaterialApp(
        home: SubscriptionScreen(theme: ThemeController(), tier: tier),
      );

  Future<void> pumpScreen(WidgetTester tester, {SubscriptionTier? tier}) async {
    await tester.pumpWidget(buildScreen(tier: tier));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Drags the lazily-built checkout list until [finder] is mounted.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 8 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
    }
  }

  /// Scrolls [finder] fully into view and taps it.
  ///
  /// `ensureVisible` is required rather than a bare `tap`: the checkout is a
  /// lazily-built `ListView`, so a widget can be mounted yet positioned
  /// outside the viewport, in which case the tap silently misses.
  Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
    await scrollTo(tester, finder);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Android offers BOTH payment options (User Choice Billing)', () {
    setUp(() {
      // Android: Play Billing available, and this is not the web build.
      BillingService.usesPayFastForTesting = false;
      AlternativeBillingService.isSupportedForTesting = true;
    });

    testWidgets('renders the Google Play AND PayFast options for Hunter',
        (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.byKey(const ValueKey('paymentChoiceSection')));

      expect(find.byKey(const ValueKey('paymentChoiceSection')), findsOneWidget);
      expect(find.byKey(const ValueKey('paymentChoiceGooglePlay')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('paymentChoicePayFast')), findsOneWidget);
      expect(find.text('Pay with Google Play'), findsOneWidget);
      expect(find.text('Pay with PayFast'), findsOneWidget);
      // Google Play must never be hidden on Android.
      expect(find.textContaining('Pay with Google Play'), findsOneWidget);
    });

    testWidgets('renders BOTH options for Outfitter too', (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.outfitter);
      await scrollTo(tester, find.byKey(const ValueKey('paymentChoiceSection')));

      expect(find.byKey(const ValueKey('paymentChoiceGooglePlay')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('paymentChoicePayFast')), findsOneWidget);
    });

    testWidgets('shows the exact required disclosure text', (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.text(AlternativeBillingCopy.disclosure));

      expect(find.text(AlternativeBillingCopy.disclosure), findsOneWidget);
      expect(
        AlternativeBillingCopy.disclosure,
        contains('Google will charge a service fee for alternative billing'),
      );
    });

    testWidgets('shows the dispute contact and support email', (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(
        tester,
        find.byKey(const ValueKey('alternativeBillingDisputeLink')),
      );

      expect(find.byKey(const ValueKey('alternativeBillingDisputeLink')),
          findsOneWidget);
      expect(find.textContaining('support@jagspoor.co.za'), findsWidgets);
      expect(AlternativeBillingCopy.disputeEmail, 'support@jagspoor.co.za');
    });

    testWidgets('does NOT preselect a method (no auto-default to PayFast)',
        (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));

      // Nothing chosen yet -> the CTA is disabled and asks the user to choose.
      expect(find.text('CHOOSE A PAYMENT METHOD'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('subscribeButton')),
      );
      expect(button.onPressed, isNull,
          reason: 'the user must actively choose a payment method');
    });

    testWidgets('choosing PayFast reveals the PayFast footer and CTA',
        (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('paymentChoicePayFast')),
      );

      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));
      expect(find.text('CONTINUE WITH PAYFAST'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('subscribeButton')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('choosing Google Play keeps the Play CTA', (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('paymentChoiceGooglePlay')),
      );

      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));
      expect(find.text('CONTINUE WITH GOOGLE PLAY'), findsOneWidget);
    });

    // ── Regression: the reported "nothing happens / MANAGE shown" bug ──────
    //
    // A brand-new account is provisioned on a 30-day free trial, and
    // `UserSubscription.hasSubscription` is true for a trial. The checkout
    // branch therefore used to route a new user to the Play MANAGER, so the
    // choice surface was hidden, no CTA existed, and the screen showed a red
    // "MANAGE IN GOOGLE PLAY" button that opened the Play Store subscription
    // popup — which is exactly what the tester saw. These tests pin the fix:
    // a live trial is a purchaser, not a subscriber.
    testWidgets('a live free trial still gets the choice surface AND a CTA',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt':
            DateTime.now().add(const Duration(days: 25)),
      });
      await pumpScreen(tester, tier: SubscriptionTier.hunter);

      await scrollTo(tester, find.byKey(const ValueKey('paymentChoiceSection')));
      expect(find.byKey(const ValueKey('paymentChoiceSection')), findsOneWidget,
          reason: 'a trial has not been charged — it must be able to choose');
      expect(find.text('Pay with Google Play'), findsOneWidget);
      expect(find.text('Pay with PayFast'), findsOneWidget);

      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));
      expect(find.text('CHOOSE A PAYMENT METHOD'), findsOneWidget);

      // The manager affordance must NOT be reachable for a trial: there is no
      // Play subscription to manage, and it is the reported bug.
      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      expect(find.byKey(const ValueKey('cancelSubscriptionButton')),
          findsNothing);
      // No RESTORE either — nothing has been purchased.
      expect(find.byKey(const ValueKey('restorePurchasesButton')), findsNothing);
    });

    testWidgets('a trial user who picks a method gets an enabled CTA',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'outfitter',
        'subscriptionTrialEndsAt':
            DateTime.now().add(const Duration(days: 25)),
      });
      await pumpScreen(tester, tier: SubscriptionTier.outfitter);

      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('paymentChoicePayFast')),
      );
      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));

      // The tap on the tile must actually change state (the reported "tapping
      // the radios does nothing"): the label reflects the choice and the CTA
      // is live.
      expect(find.text('CONTINUE WITH PAYFAST'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('subscribeButton')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('an active subscriber keeps MANAGE and gets no choice surface',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
        'subscriptionPlatform': 'google_play',
        'subscriptionRenewalDate':
            DateTime.now().add(const Duration(days: 20)),
      });
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.byKey(const ValueKey('cancelSubscriptionButton')));

      expect(find.byKey(const ValueKey('paymentChoiceSection')), findsNothing,
          reason: 'nothing to buy — no choice to make');
      expect(find.text('MANAGE IN GOOGLE PLAY'), findsOneWidget);
      expect(find.byKey(const ValueKey('restorePurchasesButton')),
          findsOneWidget);
    });
  });

  group('web build keeps the PayFast-only hard rule', () {
    setUp(() {
      BillingService.usesPayFastForTesting = true;
      // Even if the platform reported Play support, the web build must never
      // render the choice surface.
      AlternativeBillingService.isSupportedForTesting = true;
    });

    testWidgets('no choice surface, no Google Play option', (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));

      expect(find.byKey(const ValueKey('paymentChoiceSection')), findsNothing);
      expect(find.byKey(const ValueKey('paymentChoiceGooglePlay')), findsNothing);
      expect(find.text('Pay with Google Play'), findsNothing);
      expect(find.text('SUBSCRIBE VIA PAYFAST'), findsOneWidget);
    });

    testWidgets('never renders MANAGE IN GOOGLE PLAY for an active subscriber',
        (tester) async {
      // An active subscriber whose platform records google_play.
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
        'subscriptionPlatform': 'google_play',
      });
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));

      expect(find.text('MANAGE IN GOOGLE PLAY'), findsNothing);
      expect(find.byKey(const ValueKey('cancelSubscriptionButton')),
          findsNothing);
      expect(find.textContaining('MANAGE SUBSCRIPTION ON PAYFAST'),
          findsOneWidget);
    });
  });

  group('non-Android native build has no choice surface', () {
    setUp(() {
      BillingService.usesPayFastForTesting = false;
      AlternativeBillingService.isSupportedForTesting = false;
    });

    testWidgets('iOS/desktop shows neither the choice nor PayFast-only UI',
        (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));

      expect(find.byKey(const ValueKey('paymentChoiceSection')), findsNothing);
      // The native Play checkout remains available.
      expect(find.text('SUBSCRIBE VIA GOOGLE PLAY'), findsOneWidget);
    });
  });

  group('AlternativeBillingCopy constants', () {
    test('disclosure names both systems and the service fee', () {
      expect(AlternativeBillingCopy.disclosure, contains('Google Play'));
      expect(AlternativeBillingCopy.disclosure, contains('PayFast'));
      expect(
        AlternativeBillingCopy.disclosure,
        contains('service fee'),
      );
    });

    test('dispute copy carries the support email', () {
      expect(
        AlternativeBillingCopy.dispute,
        contains('unauthorized alternative billing transactions'),
      );
      expect(
        AlternativeBillingCopy.disputeMailto,
        'mailto:support@jagspoor.co.za',
      );
    });
  });

  group('signed PayFast GET URL (native launch path)', () {
    test('carries every signed field including the signature', () {
      const payment = PayFastPayment(
        processUrl: 'https://sandbox.payfast.co.za/eng/process',
        fields: {
          'merchant_id': '10000100',
          'amount': '34.99',
          'custom_str4': 'alt_billing',
          'signature': 'abc123',
        },
        merchantPaymentId: 'sub_uid-1_hunter_monthly',
        planId: 'hunter_monthly',
        amount: 34.99,
      );
      final url = BillingService.buildSignedGetUrl(payment);
      expect(url, startsWith('https://sandbox.payfast.co.za/eng/process?'));
      expect(url, contains('merchant_id=10000100'));
      expect(url, contains('amount=34.99'));
      expect(url, contains('custom_str4=alt_billing'));
      expect(url, contains('signature=abc123'));
    });

    test('percent-encodes values that need it', () {
      const payment = PayFastPayment(
        processUrl: 'https://sandbox.payfast.co.za/eng/process',
        fields: {
          'item_name': 'JagSpoor Hunter Monthly',
          'return_url': 'https://jagspoor.web.app/#/subscription/success',
        },
        merchantPaymentId: 'sub_uid-1_hunter_monthly',
        planId: 'hunter_monthly',
        amount: 34.99,
      );
      final url = BillingService.buildSignedGetUrl(payment);
      expect(url, contains('item_name=JagSpoor+Hunter+Monthly'));
      expect(url, contains('return_url=https%3A%2F%2Fjagspoor.web.app'));
    });
  });

  group('BillingService.pay forwards the alternative-billing flag', () {
    test('an alternative-billing checkout uses the PayFast path on native',
        () async {
      BillingService.usesPayFastForTesting = false;
      var capturedBody = '';
      BillingService.httpPostForTesting = (uri, headers, body) async {
        capturedBody = body.toString();
        return _signedFormResponse();
      };
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.formSubmitterForTesting = (url, fields) => true;

      final result = await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.byId('hunter_monthly')!,
        alternativeBilling: true,
      );

      expect(result.launched, isTrue);
      expect(capturedBody, contains('"alternativeBilling":true'));
      expect(capturedBody, contains('hunter_monthly'));
    });

    test('a plain native checkout does not send the flag', () async {
      BillingService.usesPayFastForTesting = true;
      var capturedBody = '';
      BillingService.httpPostForTesting = (uri, headers, body) async {
        capturedBody = body.toString();
        return _signedFormResponse();
      };
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.formSubmitterForTesting = (url, fields) => true;

      await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.byId('hunter_monthly')!,
      );

      expect(capturedBody, isNot(contains('alternativeBilling')));
    });
  });

  group('native alternative-billing checkout opens the signed URL', () {
    test('launches the browser with the signed GET URL, not a DOM form',
        () async {
      // Not the web build: the native path must hand the signed URL to the
      // device browser (there is no DOM to submit a form into).
      BillingService.usesPayFastForTesting = false;
      BillingService.httpPostForTesting = (uri, headers, body) async =>
          _signedFormResponse();
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';

      Uri? launchedUri;
      BillingService.urlLauncherForTesting = (uri) async {
        launchedUri = uri;
        return true;
      };
      var formSubmitted = false;
      BillingService.formSubmitterForTesting = (url, fields) {
        formSubmitted = true;
        return true;
      };

      final result = await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.byId('hunter_monthly')!,
        alternativeBilling: true,
      );

      expect(result.launched, isTrue);
      expect(launchedUri, isNotNull);
      expect(launchedUri.toString(),
          startsWith('https://sandbox.payfast.co.za/eng/process?'));
      expect(formSubmitted, isFalse,
          reason: 'a native host has no DOM to submit a form into');
    });

    test('a refused browser hand-off reports a failure', () async {
      BillingService.usesPayFastForTesting = false;
      BillingService.httpPostForTesting = (uri, headers, body) async =>
          _signedFormResponse();
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.urlLauncherForTesting = (uri) async => false;

      final result = await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.byId('hunter_monthly')!,
        alternativeBilling: true,
      );

      expect(result.launched, isFalse);
      expect(result.message, isNotNull);
    });
  });
}

/// A minimal successful `createPayFastPayment` response body.
http.Response _signedFormResponse() => http.Response(
      '{"result":{"processUrl":"https://sandbox.payfast.co.za/eng/process",'
      '"fields":{"merchant_id":"10000100","signature":"abc"},'
      '"merchantPaymentId":"sub_uid-1_hunter_monthly",'
      '"planId":"hunter_monthly","amount":34.99}}',
      200,
    );
