import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jagspoor/features/billing/billing_plans.dart';
import 'package:jagspoor/features/billing/billing_service.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

void main() {
  setUp(BillingService.resetTestSeams);
  tearDown(BillingService.resetTestSeams);

  group('BillingPlans catalog', () {
    test('offers a monthly + yearly plan per tier', () {
      for (final tier in SubscriptionTier.values) {
        final plans = BillingPlans.forTier(tier);
        expect(plans.length, 2);
        expect(plans.map((p) => p.cycle).toSet(),
            {BillingCycle.monthly, BillingCycle.yearly});
        expect(plans.every((p) => p.tier == tier), isTrue);
      }
    });

    test('plan ids match the server catalog (plans.ts)', () {
      expect(BillingPlans.monthlyFor(SubscriptionTier.hunter).planId,
          'hunter_monthly');
      expect(BillingPlans.forTier(SubscriptionTier.hunter).last.planId,
          'hunter_yearly');
      expect(BillingPlans.monthlyFor(SubscriptionTier.outfitter).planId,
          'outfitter_monthly');
      expect(BillingPlans.forTier(SubscriptionTier.outfitter).last.planId,
          'outfitter_yearly');
    });

    test('amounts match the server catalog', () {
      expect(BillingPlans.monthlyFor(SubscriptionTier.hunter).amountZar, 34.99);
      expect(BillingPlans.forTier(SubscriptionTier.hunter).last.amountZar,
          349.99);
      expect(
          BillingPlans.monthlyFor(SubscriptionTier.outfitter).amountZar, 299.99);
      expect(BillingPlans.forTier(SubscriptionTier.outfitter).last.amountZar,
          2999.99);
    });

    test('byId resolves a known plan and rejects unknown ids', () {
      expect(BillingPlans.byId('hunter_monthly')?.tier,
          SubscriptionTier.hunter);
      expect(BillingPlans.byId('outfitter_yearly')?.isYearly, isTrue);
      expect(BillingPlans.byId('nope'), isNull);
      expect(BillingPlans.byId(null), isNull);
      expect(BillingPlans.byId(''), isNull);
    });

    test('priceLabel + savings math', () {
      final monthly = BillingPlans.monthlyFor(SubscriptionTier.hunter);
      final yearly = BillingPlans.forTier(SubscriptionTier.hunter).last;
      expect(monthly.priceLabel, 'R 34.99/month');
      expect(yearly.priceLabel, 'R 349.99/year');
      expect(monthly.isYearly, isFalse);
      expect(yearly.isYearly, isTrue);
      // Yearly 349.99 vs 12 x 34.99 = 419.88 -> ~17% saving.
      expect(yearly.savingsPercent(monthly.amountZar), 17);
      // A monthly plan has no savings hint.
      expect(monthly.savingsPercent(yearly.amountZar), isNull);
      // A yearly plan with no baseline has no hint.
      expect(yearly.savingsPercent(null), isNull);
    });
  });

  group('BillingService.requestPayFastPayment', () {
    test('rejects when there is no signed-in user', () async {
      BillingService.currentUserIdResolverForTesting = () => null;
      final result = await BillingService.instance
          .requestPayFastPayment(role: 'hunter', planId: 'hunter_monthly');
      expect(result.payment, isNull);
      expect(result.error, contains('Sign in'));
    });

    test('parses the callable result into a PayFastPayment', () async {
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.httpPostForTesting = (uri, headers, body) async {
        expect(uri.path, contains('createPayFastPayment'));
        expect(headers['Authorization'], 'Bearer id-token');
        final decoded = jsonDecode(body as String) as Map<String, dynamic>;
        expect(decoded['data']['planId'], 'hunter_monthly');
        return http.Response(
          jsonEncode({
            'result': {
              'processUrl': 'https://sandbox.payfast.co.za/eng/process',
              'fields': {'merchant_id': '37584965', 'signature': 'abc'},
              'merchantPaymentId': 'mp-1',
              'planId': 'hunter_monthly',
              'amount': 34.99,
            }
          }),
          200,
        );
      };
      final result = await BillingService.instance
          .requestPayFastPayment(role: 'hunter', planId: 'hunter_monthly');
      expect(result.error, isNull);
      expect(result.payment, isNotNull);
      expect(result.payment!.fields['merchant_id'], '37584965');
      expect(result.payment!.fields['signature'], 'abc');
      expect(result.payment!.amount, 34.99);
    });

    test('surfaces the callable error message on a non-200', () async {
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.httpPostForTesting = (uri, headers, body) async =>
          http.Response(
              jsonEncode({
                'error': {'message': 'PayFast is not configured yet.'}
              }),
              500);
      final result = await BillingService.instance
          .requestPayFastPayment(role: 'hunter', planId: 'hunter_monthly');
      expect(result.payment, isNull);
      expect(result.error, 'PayFast is not configured yet.');
    });

    test('never throws on a transport failure', () async {
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.httpPostForTesting =
          (uri, headers, body) async => throw Exception('offline');
      final result = await BillingService.instance
          .requestPayFastPayment(role: 'hunter', planId: 'hunter_monthly');
      expect(result.payment, isNull);
      expect(result.error, isNotNull);
    });
  });

  group('BillingService.pay (web path)', () {
    setUp(() => BillingService.usesPayFastForTesting = true);

    test('submits the signed form and reports launched', () async {
      // force the web branch by using the test form submitter
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.httpPostForTesting = (uri, headers, body) async =>
          http.Response(
              jsonEncode({
                'result': {
                  'processUrl': 'https://sandbox.payfast.co.za/eng/process',
                  'fields': {'merchant_id': '37584965'},
                  'planId': 'hunter_monthly',
                  'amount': 34.99,
                }
              }),
              200);
      String? submittedUrl;
      Map<String, String>? submittedFields;
      BillingService.formSubmitterForTesting = (url, fields) {
        submittedUrl = url;
        submittedFields = fields;
        return true;
      };
      final result = await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.monthlyFor(SubscriptionTier.hunter),
      );
      expect(result.launched, isTrue);
      expect(submittedUrl, contains('payfast.co.za'));
      expect(submittedFields!['merchant_id'], '37584965');
    });

    test('reports failure when the form could not be submitted', () async {
      BillingService.currentUserIdResolverForTesting = () => 'uid-1';
      BillingService.idTokenResolverForTesting = () async => 'id-token';
      BillingService.httpPostForTesting = (uri, headers, body) async =>
          http.Response(
              jsonEncode({
                'result': {
                  'processUrl': 'https://sandbox.payfast.co.za/eng/process',
                  'fields': {'merchant_id': '37584965'},
                  'planId': 'hunter_monthly',
                  'amount': 34.99,
                }
              }),
              200);
      BillingService.formSubmitterForTesting = (url, fields) => false;
      final result = await BillingService.instance.pay(
        role: 'hunter',
        plan: BillingPlans.monthlyFor(SubscriptionTier.hunter),
      );
      expect(result.launched, isFalse);
      expect(result.message, isNotNull);
    });

    test('payWithPlanId rejects an unknown plan id', () async {
      final result = await BillingService.instance
          .payWithPlanId(role: 'hunter', planId: 'bogus_plan');
      expect(result.launched, isFalse);
      expect(result.message, 'Unknown plan.');
    });
  });

  group('BillingService platform routing', () {
    test('non-web builds report usesPayFast == false (Play Billing path)', () {
      // The test host is not the web, so the native branch is selected.
      expect(BillingService.instance.usesPayFast, isFalse);
      expect(BillingService.instance.isWeb, isFalse);
    });

    test('plansForRole resolves both roles', () {
      expect(
          BillingService.instance.plansForRole('hunter').first.planId,
          'hunter_monthly');
      expect(BillingService.instance.plansForRole('outfitter').first.planId,
          'outfitter_monthly');
    });
  });
}
