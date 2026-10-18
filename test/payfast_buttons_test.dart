import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/billing/billing_plans.dart';
import 'package:jagspoor/features/billing/billing_service.dart';
import 'package:jagspoor/features/billing/payfast_buttons.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

/// The PayFast subscription buttons shown on the web build.
///
/// FINAL PRICING (VAT inclusive):
///   Hunter Monthly R34.99 · Hunter Yearly R349.99
///   Outfitter Monthly R299.99 · Outfitter Yearly R2999.99
///
/// Only the ACTIVE role's two plans render (never the other role's).
void main() {
  setUp(BillingService.resetTestSeams);
  tearDown(BillingService.resetTestSeams);

  Widget host({
    SubscriptionTier tier = SubscriptionTier.hunter,
    BillingCycle? selectedCycle,
    void Function(BillingPlan)? onPlanSelected,
    VoidCallback? onLaunched,
    void Function(String)? onError,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PayFastHunterOutfitterButtons(
              theme: ThemeController(),
              tier: tier,
              selectedCycle: selectedCycle,
              // Render on the VM test host (production gates on kIsWeb).
              forceShow: true,
              onPlanSelected: onPlanSelected,
              onLaunched: onLaunched == null ? null : (_) => onLaunched(),
              onError: onError,
            ),
          ),
        ),
      );

  group('PayFastHunterOutfitterButtons rendering', () {
    testWidgets('hunter renders ONLY the two hunter plan buttons',
        (tester) async {
      await tester.pumpWidget(host(tier: SubscriptionTier.hunter));

      expect(find.byKey(const ValueKey('payfastPlanButton_hunter_monthly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('payfastPlanButton_hunter_yearly')),
          findsOneWidget);
      // The other role's buttons never render.
      expect(find.byKey(const ValueKey('payfastPlanButton_outfitter_monthly')),
          findsNothing);
      expect(find.byKey(const ValueKey('payfastPlanButton_outfitter_yearly')),
          findsNothing);

      expect(find.text('HUNTER MONTHLY'), findsOneWidget);
      expect(find.text('HUNTER YEARLY'), findsOneWidget);

      // The two confirmed hunter prices, rendered verbatim.
      expect(find.text('R 34.99/month'), findsOneWidget);
      expect(find.text('R 349.99/year'), findsOneWidget);
    });

    testWidgets('outfitter renders ONLY the two outfitter plan buttons',
        (tester) async {
      await tester.pumpWidget(host(tier: SubscriptionTier.outfitter));

      expect(find.byKey(const ValueKey('payfastPlanButton_outfitter_monthly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('payfastPlanButton_outfitter_yearly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('payfastPlanButton_hunter_monthly')),
          findsNothing);
      expect(find.byKey(const ValueKey('payfastPlanButton_hunter_yearly')),
          findsNothing);

      expect(find.text('OUTFITTER MONTHLY'), findsOneWidget);
      expect(find.text('OUTFITTER YEARLY'), findsOneWidget);
      expect(find.text('R 299.99/month'), findsOneWidget);
      expect(find.text('R 2999.99/year'), findsOneWidget);
    });

    testWidgets('renders nothing off the web when not forced', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PayFastHunterOutfitterButtons(
            theme: ThemeController(),
            tier: SubscriptionTier.hunter,
          ),
        ),
      ));
      // The VM test host is not the web, so no buttons render.
      expect(find.text('HUNTER MONTHLY'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('the selected cycle highlights its button', (tester) async {
      await tester.pumpWidget(
        host(tier: SubscriptionTier.hunter, selectedCycle: BillingCycle.yearly),
      );
      // Yearly is selected -> a FilledButton; monthly is the outlined option.
      expect(
        tester.widget(find.byKey(
            const ValueKey('payfastPlanButton_hunter_yearly'))),
        isA<FilledButton>(),
      );
      expect(
        tester.widget(find.byKey(
            const ValueKey('payfastPlanButton_hunter_monthly'))),
        isA<OutlinedButton>(),
      );
    });

    testWidgets('tapping a button launches the matching plan id and reports it',
        (tester) async {
      BillingService.usesPayFastForTesting = true;
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'tok';
      String? requestedPlanId;
      BillingService.httpPostForTesting = (uri, headers, body) async {
        // Capture the plan id the button requested.
        requestedPlanId = RegExp(r'"planId":"([^"]+)"')
            .firstMatch(body as String)
            ?.group(1);
        return http.Response('{"result":{}}', 200);
      };
      BillingService.formSubmitterForTesting = (url, fields) => true;

      BillingPlan? selected;
      var launched = false;
      await tester.pumpWidget(host(
        tier: SubscriptionTier.outfitter,
        onPlanSelected: (p) => selected = p,
        onLaunched: () => launched = true,
      ));

      final button =
          find.byKey(const ValueKey('payfastPlanButton_outfitter_yearly'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(requestedPlanId, 'outfitter_yearly');
      expect(selected?.planId, 'outfitter_yearly');
      expect(launched, isTrue);
    });

    testWidgets('surfaces an error when the checkout cannot start',
        (tester) async {
      BillingService.usesPayFastForTesting = true;
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'tok';
      BillingService.httpPostForTesting =
          (uri, headers, body) async => throw Exception('offline');
      String? errorMessage;
      await tester.pumpWidget(host(onError: (m) => errorMessage = m));

      final button =
          find.byKey(const ValueKey('payfastPlanButton_hunter_monthly'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(errorMessage, isNotNull);
    });
  });

  group('final pricing contract', () {
    test('BillingPlans mirrors the confirmed PayFast catalog', () {
      expect(BillingPlans.monthlyFor(SubscriptionTier.hunter).amountZar, 34.99);
      expect(BillingPlans.forTier(SubscriptionTier.hunter).last.amountZar,
          349.99);
      expect(
          BillingPlans.monthlyFor(SubscriptionTier.outfitter).amountZar, 299.99);
      expect(BillingPlans.forTier(SubscriptionTier.outfitter).last.amountZar,
          2999.99);
    });
  });
}
