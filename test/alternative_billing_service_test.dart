import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/billing/alternative_billing_service.dart';
import 'package:jagspoor/features/billing/billing_plans.dart';
import 'package:jagspoor/features/subscription/services/subscription_pricing.dart';

/// Google Play User Choice Billing (alternative billing) contract.
///
/// Locks:
///   * the real Play Billing Library surface (there is NO
///     `createAlternativeBillingReportingToken()`; the token comes from
///     `createAlternativeBillingOnlyReportingDetailsAsync` /
///     `UserChoiceDetails.getExternalTransactionToken`),
///   * the method-channel contract `com.jagspoor/alternative_billing`,
///   * graceful degradation when Play cannot supply a token,
///   * the `alternative_billing_reports` document shape incl. the 26% fee,
///   * the alternative SKU mapping (`jagspoor_<plan>_payfast`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Construct a FakeFirebaseFirestore FIRST, before any test touches
  // `FieldValue.serverTimestamp()` (buildReport does). fake_cloud_firestore
  // installs its mock `FieldValuePlatform` as a side-effect of construction;
  // if a production `FieldValue` is realised first, the platform binds to
  // `MethodChannelFieldValue` and later fakes throw `type
  // 'MethodChannelFieldValue' is not a subtype of type
  // 'MockFieldValuePlatform'`. Constructing one fake up-front pins the
  // platform for the whole process. (Same pattern as
  // test/optic_log_service_test.dart.)
  FakeFirebaseFirestore();

  setUp(AlternativeBillingService.resetTestSeams);
  tearDown(AlternativeBillingService.resetTestSeams);

  group('platform capability', () {
    test('is false off Android (web / iOS / desktop)', () {
      AlternativeBillingService.isSupportedForTesting = false;
      expect(AlternativeBillingService.instance.isSupported, isFalse);
    });

    test('is true on Android', () {
      AlternativeBillingService.isSupportedForTesting = true;
      expect(AlternativeBillingService.instance.isSupported, isTrue);
    });

    test('a non-Android host returns no token instead of throwing', () async {
      AlternativeBillingService.isSupportedForTesting = false;
      expect(
        await AlternativeBillingService.instance.createAlternativeBillingToken(),
        isNull,
      );
      expect(
        await AlternativeBillingService.instance
            .reportAlternativeBillingToken('tok'),
        isFalse,
      );
    });

    test('probeSupport is false when the native host has no bridge', () async {
      // No seam set and no plugin registered: the probe must answer false
      // rather than throwing, which is what keeps the User Choice surface off
      // the test VM (and off any Android build without the programme).
      expect(await AlternativeBillingService.instance.probeSupport(), isFalse);
    });

    test('probeSupport honours the pinned capability', () async {
      AlternativeBillingService.isSupportedForTesting = true;
      expect(await AlternativeBillingService.instance.probeSupport(), isTrue);
      AlternativeBillingService.isSupportedForTesting = false;
      expect(await AlternativeBillingService.instance.probeSupport(), isFalse);
    });
  });

  group('channel contract', () {
    test('uses the agreed channel name', () {
      expect(
        AlternativeBillingService.channel.name,
        'com.jagspoor/alternative_billing',
      );
    });

    test('invokes createAlternativeBillingToken on the native side', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AlternativeBillingService.channel,
              (call) async {
        calls.add(call);
        return 'ext-token-123';
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AlternativeBillingService.channel, null);
      });

      // Force the Android branch by overriding the target platform.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final token =
          await AlternativeBillingService.instance.createAlternativeBillingToken();
      expect(token, 'ext-token-123');
      expect(calls.single.method, 'createAlternativeBillingToken');
    });

    test('reportAlternativeBillingToken passes the token through', () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AlternativeBillingService.channel,
              (call) async {
        seen = call;
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AlternativeBillingService.channel, null);
      });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final ok = await AlternativeBillingService.instance
          .reportAlternativeBillingToken('tok-abc');
      expect(ok, isTrue);
      expect(seen!.method, 'reportAlternativeBillingToken');
      expect((seen!.arguments as Map)['token'], 'tok-abc');
    });
  });

  group('token creation degradation', () {
    test('a missing platform implementation yields null (never throws)',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // No mock handler registered -> MissingPluginException internally.
      expect(
        await AlternativeBillingService.instance.createAlternativeBillingToken(),
        isNull,
      );
    });

    test('a PlatformException yields null (never throws)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AlternativeBillingService.channel,
              (call) async {
        throw PlatformException(code: 'FEATURE_NOT_SUPPORTED');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AlternativeBillingService.channel, null);
      });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        await AlternativeBillingService.instance.createAlternativeBillingToken(),
        isNull,
      );
    });

    test('a blank token from the platform is treated as unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AlternativeBillingService.channel,
              (call) async => '   ');
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AlternativeBillingService.channel, null);
      });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        await AlternativeBillingService.instance.createAlternativeBillingToken(),
        isNull,
      );
    });

    test('a throwing test seam degrades to null', () async {
      AlternativeBillingService.createTokenForTesting =
          () async => throw StateError('boom');
      expect(
        await AlternativeBillingService.instance.createAlternativeBillingToken(),
        isNull,
      );
    });
  });

  group('SKU + product mapping', () {
    test('maps a Play plan id to its alternative SKU', () {
      expect(
        AlternativeBillingService.alternativeSkuFor('hunter_monthly'),
        'jagspoor_hunter_monthly_payfast',
      );
      expect(
        AlternativeBillingService.alternativeSkuFor('hunter_yearly'),
        'jagspoor_hunter_yearly_payfast',
      );
      expect(
        AlternativeBillingService.alternativeSkuFor('outfitter_monthly'),
        'jagspoor_outfitter_monthly_payfast',
      );
      expect(
        AlternativeBillingService.alternativeSkuFor('outfitter_yearly'),
        'jagspoor_outfitter_yearly_payfast',
      );
      expect(AlternativeBillingService.alternativeSkuFor('  '), '');
    });

    test('every catalog plan produces a distinct alternative SKU', () {
      final skus = <String>{};
      for (final tier in SubscriptionTier.values) {
        for (final plan in BillingPlans.forTier(tier)) {
          skus.add(AlternativeBillingService.alternativeSkuFor(plan.planId));
        }
      }
      expect(skus.length, 4);
      expect(skus.every((s) => s.endsWith('_payfast')), isTrue);
    });

    test('Play product ids stay the 4 subscription products', () {
      expect(SubscriptionTier.hunter.playProductId,
          'jagspoor_hunter_monthly');
      expect(SubscriptionTier.outfitter.playProductId,
          'jagspoor_outfitter_monthly');
    });
  });

  group('report document shape', () {
    test('carries the identity, amounts and 26% service fee', () {
      final report = AlternativeBillingService.buildReport(
        userId: 'uid-1',
        tier: SubscriptionTier.hunter,
        cycle: BillingCycle.monthly,
        amountZar: 34.99,
        planId: 'hunter_monthly',
        alternativeSku: 'jagspoor_hunter_monthly_payfast',
        payfastTransactionId: 'pf-99',
        reportingToken: 'tok-1',
        status: AlternativeBillingService.statusReported,
      );

      expect(report['userId'], 'uid-1');
      expect(report['tier'], 'hunter');
      expect(report['billingCycle'], 'monthly');
      expect(report['planId'], 'hunter_monthly');
      expect(report['alternativeSku'], 'jagspoor_hunter_monthly_payfast');
      expect(report['amountZar'], 34.99);
      expect(report['payfastTransactionId'], 'pf-99');
      expect(report['reportingToken'], 'tok-1');
      expect(report['status'], 'reported');
      expect(report['program'], 'user_choice_billing');
      expect(report['reportedAt'], isA<FieldValue>());

      // 26% of 34.99 = 9.0974 -> 9.10
      expect(report['serviceFeeBasisPoints'], 2600);
      expect(report['serviceFeeZar'], 9.10);
      // Also written under the operator-facing spelling used in the Play
      // Console reconciliation notes.
      expect(report['feeBps'], 2600);
    });

    test('the fee is 26% across both tiers and cycles', () {
      final cases = <(SubscriptionTier, BillingCycle, double)>[
        (SubscriptionTier.hunter, BillingCycle.monthly, 34.99),
        (SubscriptionTier.hunter, BillingCycle.yearly, 349.99),
        (SubscriptionTier.outfitter, BillingCycle.monthly, 299.99),
        (SubscriptionTier.outfitter, BillingCycle.yearly, 2999.99),
      ];
      for (final (tier, cycle, amount) in cases) {
        final r = AlternativeBillingService.buildReport(
          userId: 'u',
          tier: tier,
          cycle: cycle,
          amountZar: amount,
          planId: '${tier.key}_${cycle.key}',
          alternativeSku: AlternativeBillingService.alternativeSkuFor(
              '${tier.key}_${cycle.key}'),
        );
        expect(r['serviceFeeZar'],
            closeTo(amount * 0.26, 0.01),
            reason: '$tier/$cycle');
      }
    });
  });

  group('recordAlternativeBillingTransaction', () {
    late FakeFirebaseFirestore fake;

    setUp(() {
      fake = FakeFirebaseFirestore();
      AlternativeBillingService.firestoreForTesting = fake;
      AlternativeBillingService.currentUserIdResolverForTesting = () => 'uid-1';
    });

    test('writes a reported transaction to alternative_billing_reports',
        () async {
      final id = await AlternativeBillingService.instance
          .recordAlternativeBillingTransaction(
        tier: SubscriptionTier.hunter,
        cycle: BillingCycle.monthly,
        amountZar: 34.99,
        payfastTransactionId: 'pf-1',
        reportingToken: 'tok-1',
      );

      expect(id, isNotNull);
      final doc = await fake
          .collection(AlternativeBillingService.reportsCollection)
          .doc(id)
          .get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['userId'], 'uid-1');
      expect(data['tier'], 'hunter');
      expect(data['alternativeSku'], 'jagspoor_hunter_monthly_payfast');
      expect(data['status'], AlternativeBillingService.statusPending,
          reason: 'a token in hand means ready-to-report, not reported — '
              'only the server-side reporter may claim that');
      expect(data['reportingToken'], 'tok-1');
      expect(data['payfastTransactionId'], 'pf-1');
    });

    test('a missing token records token_unavailable (still logged)', () async {
      final id = await AlternativeBillingService.instance
          .recordAlternativeBillingTransaction(
        tier: SubscriptionTier.outfitter,
        cycle: BillingCycle.yearly,
        amountZar: 2999.99,
      );
      final data = (await fake
              .collection(AlternativeBillingService.reportsCollection)
              .doc(id)
              .get())
          .data()!;
      expect(data['status'], AlternativeBillingService.statusTokenUnavailable);
      expect(data['tier'], 'outfitter');
      expect(data['billingCycle'], 'yearly');
      expect(data['reportingToken'], isNull);
    });

    test('an explicit status overrides the derived one', () async {
      final id = await AlternativeBillingService.instance
          .recordAlternativeBillingTransaction(
        tier: SubscriptionTier.hunter,
        cycle: BillingCycle.monthly,
        amountZar: 34.99,
        reportingToken: 'tok',
        status: AlternativeBillingService.statusPending,
      );
      final data = (await fake
              .collection(AlternativeBillingService.reportsCollection)
              .doc(id)
              .get())
          .data()!;
      expect(data['status'], AlternativeBillingService.statusPending);
    });

    test('no signed-in user -> no write, no throw', () async {
      AlternativeBillingService.currentUserIdResolverForTesting = () => null;
      final id = await AlternativeBillingService.instance
          .recordAlternativeBillingTransaction(
        tier: SubscriptionTier.hunter,
        cycle: BillingCycle.monthly,
        amountZar: 34.99,
      );
      expect(id, isNull);
      final all = await fake
          .collection(AlternativeBillingService.reportsCollection)
          .get();
      expect(all.docs, isEmpty);
    });

    test('a report-writer failure never throws', () async {
      AlternativeBillingService.reportWriterForTesting =
          (report) async => throw StateError('offline');
      // Contract: the PayFast checkout has already launched by this point, so
      // a logging failure must never surface as an exception.
      await expectLater(
        AlternativeBillingService.instance.recordAlternativeBillingTransaction(
          tier: SubscriptionTier.hunter,
          cycle: BillingCycle.monthly,
          amountZar: 34.99,
        ),
        completes,
      );
    });
  });
}
