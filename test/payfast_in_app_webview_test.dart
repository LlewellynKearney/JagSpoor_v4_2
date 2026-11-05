import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jagspoor/features/billing/billing_plans.dart';
import 'package:jagspoor/features/billing/billing_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Play **User Choice Billing** in-app compliance (IN_APP_EXPERIENCE-4551).
///
/// The alternative-billing programme requires that a user who chooses the
/// alternative system (PayFast) is NOT led outside the app. The native PayFast
/// checkout must therefore open in an **in-app WebView**
/// (`LaunchMode.inAppWebView`) and never be handed to an external browser
/// (`LaunchMode.externalApplication`, i.e. Chrome / Safari).
///
/// These tests pin that contract on the real launch path — the default
/// `url_launcher` hand-off, exercised through its method channel — so a future
/// change back to an external browser fails loudly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  late List<MethodCall> calls;

  setUp(() {
    BillingService.resetTestSeams();
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    BillingService.resetTestSeams();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PayFast native launch mode (IN_APP_EXPERIENCE-4551)', () {
    test('uses the in-app WebView, never an external browser', () {
      expect(BillingService.nativeLaunchMode, LaunchMode.inAppWebView);
      expect(
        BillingService.nativeLaunchMode,
        isNot(LaunchMode.externalApplication),
        reason: 'an alternative-billing choice must not lead outside the app',
      );
    });
  });

  group('native alternative-billing checkout opens an in-app WebView', () {
    test('the default hand-off requests an in-app WebView (useWebView=true)',
        () async {
      // Native host, and DO NOT set `urlLauncherForTesting`: this exercises the
      // real `_defaultUrlLauncher` -> `launchUrl` -> platform channel path.
      BillingService.usesPayFastForTesting = false;
      BillingService.httpPostForTesting = (uri, headers, body) async =>
          _signedFormResponse();
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';

      final result = await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.byId('hunter_monthly')!,
        alternativeBilling: true,
      );

      expect(result.launched, isTrue);

      final launch = calls.singleWhere((c) => c.method == 'launch');
      final args = launch.arguments as Map<Object?, Object?>;
      // `useWebView: true` is exactly what the in-app WebView mode maps to on
      // the method channel — the checkout renders INSIDE JagSpoor.
      expect(args['useWebView'], isTrue);
      expect(args['useSafariVC'], isTrue);
      expect(args['enableJavaScript'], isTrue);
      // And it is the signed PayFast https checkout URL, not an external intent.
      expect(args['url'], startsWith('https://sandbox.payfast.co.za/eng/process?'));
    });

    test('a refused WebView hand-off reports a failure', () async {
      BillingService.usesPayFastForTesting = false;
      BillingService.httpPostForTesting = (uri, headers, body) async =>
          _signedFormResponse();
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      // The platform refuses to open the WebView.
      BillingService.urlLauncherForTesting = (uri) async => false;

      final result = await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.byId('hunter_monthly')!,
        alternativeBilling: true,
      );

      expect(result.launched, isFalse);
      expect(result.message, isNotNull);
      expect(result.message, isNot(contains('browser')));
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
