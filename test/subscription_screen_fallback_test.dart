import 'dart:async';

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

/// Regression suite for the "subscription screen stays on the selector"
/// defect.
///
/// Root cause (two compounding bugs in `SubscriptionScreen`):
///  1. `build()` re-created the Firestore `watchMySubscription()` stream on
///     EVERY rebuild. Each rebuild therefore re-subscribed and reset the
///     `StreamBuilder` to `ConnectionState.waiting` with no data, so an ACTIVE
///     subscriber briefly rendered the empty "NO ACTIVE SUBSCRIPTION" state
///     (the plan selector) instead of the active banner + plan cards.
///  2. `watchMySubscription()` ended with `.handleError(...)`, whose callback
///     return value is IGNORED by `Stream.handleError`. A stream error was
///     silently discarded and the stream never emitted nor completed, leaving
///     the `StreamBuilder` stuck in `waiting` — the screen rendered the empty
///     selector state forever.
///
/// These tests lock the contract: with an ACTIVE subscription the screen
/// stays on the SAME screen, keeps the green "SUBSCRIPTION ACTIVE" banner at
/// the top, keeps BOTH pricing cards below it, and badges the current plan
/// "YOUR TIER".
void main() {
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

  Widget buildScreen({SubscriptionTier? tier}) => MaterialApp(
        home: SubscriptionScreen(theme: ThemeController(), tier: tier),
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('active subscription keeps the screen + both plan cards', () {
    testWidgets(
        'an ACTIVE hunter sees the banner AND both pricing cards (never only '
        'the selector)', (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
        'subscriptionPlatform': 'payfast',
        'subscriptionProduct': 'hunter_monthly',
      });
      await pumpScreen(tester);

      // The green active banner stays at the TOP of the same screen.
      expect(find.text('SUBSCRIPTION ACTIVE'), findsOneWidget);
      // It did NOT fall back to the empty selector state.
      expect(find.text('NO ACTIVE SUBSCRIPTION'), findsNothing);
      // BOTH plan cards remain visible BELOW the banner.
      expect(find.text('TIER PRICING'), findsOneWidget);
      expect(find.byKey(const ValueKey('tierCard_hunter_monthly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('tierCard_hunter_yearly')),
          findsOneWidget);
      expect(find.text('R 34.99/month'), findsOneWidget);
      expect(find.text('R 349.99/year'), findsOneWidget);
    });

    testWidgets('the active plan is badged YOUR TIER (monthly)',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
        'subscriptionProduct': 'hunter_monthly',
      });
      await pumpScreen(tester);

      expect(find.text('YOUR TIER'), findsOneWidget);
      // The badge sits on the MONTHLY card, not the yearly one.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tierCard_hunter_monthly')),
          matching: find.text('YOUR TIER'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tierCard_hunter_yearly')),
          matching: find.text('YOUR TIER'),
        ),
        findsNothing,
      );
    });

    testWidgets('the active plan is badged YOUR TIER (yearly)', (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
        'subscriptionProduct': 'hunter_yearly',
      });
      await pumpScreen(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tierCard_hunter_yearly')),
          matching: find.text('YOUR TIER'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tierCard_hunter_monthly')),
          matching: find.text('YOUR TIER'),
        ),
        findsNothing,
      );
    });

    testWidgets(
        'the screen STAYS visible across a rebuild (no re-subscribe flicker)',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'outfitter',
        'subscriptionProduct': 'outfitter_yearly',
      });
      await tester.pumpWidget(
        MaterialApp(home: _RebuildProbe(
          child: SubscriptionScreen(
            theme: ThemeController(),
            tier: SubscriptionTier.outfitter,
          ),
        )),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('SUBSCRIPTION ACTIVE'), findsOneWidget);
      // The stream must be built ONCE for the State — never per build().
      final callsAfterMount =
          SubscriptionStatusService.watchMySubscriptionCalls;
      expect(callsAfterMount, 1);

      // Force an in-place rebuild of the SAME State (e.g. a theme toggle or a
      // purchase-stream setState). The cached stream must keep the resolved
      // subscription, so the banner + both cards survive the rebuild AND no
      // new Firestore subscription is opened.
      await tester.tap(find.byKey(const ValueKey('rebuildProbeButton')));
      await tester.pump();

      expect(SubscriptionStatusService.watchMySubscriptionCalls, 1,
          reason: 'a rebuild must NOT re-create the subscription stream');
      expect(find.text('SUBSCRIPTION ACTIVE'), findsOneWidget);
      expect(find.text('NO ACTIVE SUBSCRIPTION'), findsNothing);
      expect(find.byKey(const ValueKey('tierCard_outfitter_monthly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('tierCard_outfitter_yearly')),
          findsOneWidget);
    });

    testWidgets(
        'the active banner renders on the FIRST frame (seeded, no flash of the '
        'empty state)', (tester) async {
      // A stream that has NOT emitted yet models real Firestore latency: the
      // first frame must be driven by the one-shot seed, not the stream's
      // initial snapshot.
      const active = UserSubscription(
        status: SubscriptionStatus.active,
        tier: SubscriptionTier.hunter,
        planId: 'hunter_monthly',
      );
      final controller = StreamController<UserSubscription>();
      addTearDown(controller.close);
      SubscriptionStatusService.streamForTesting = () => controller.stream;
      SubscriptionStatusService.oneShotForTesting = () async => active;

      await tester.pumpWidget(buildScreen());
      // A single frame — the stream has NOT emitted yet.
      await tester.pump();

      expect(find.text('SUBSCRIPTION ACTIVE'), findsOneWidget);
      expect(find.text('NO ACTIVE SUBSCRIPTION'), findsNothing);
      expect(find.byKey(const ValueKey('tierCard_hunter_monthly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('tierCard_hunter_yearly')),
          findsOneWidget);
    });
  });

  group('non-active states keep the selector (no spurious YOUR TIER)', () {
    testWidgets('a trialing account has no YOUR TIER badge', (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'trialing',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt': DateTime.now().add(const Duration(days: 20)),
      });
      await pumpScreen(tester);

      expect(find.text('FREE TRIAL ACTIVE'), findsOneWidget);
      expect(find.text('YOUR TIER'), findsNothing);
      expect(find.byKey(const ValueKey('tierCard_hunter_monthly')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('tierCard_hunter_yearly')),
          findsOneWidget);
    });

    testWidgets('an active subscription with NO plan id badges nothing',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'hunter',
      });
      await pumpScreen(tester);

      expect(find.text('SUBSCRIPTION ACTIVE'), findsOneWidget);
      // No plan id on file -> neither card claims to be the user's tier.
      expect(find.text('YOUR TIER'), findsNothing);
    });
  });

  group('UserSubscription.activeCycle resolution', () {
    test('yearly plan ids resolve to the yearly cycle', () {
      final sub = UserSubscription.fromMap({
        'subscriptionStatus': 'active',
        'subscriptionProduct': 'outfitter_yearly',
      });
      expect(sub.activeCycle, 'yearly');
      expect(sub.isActiveCycle('yearly'), isTrue);
      expect(sub.isActiveCycle('monthly'), isFalse);
    });

    test('monthly plan ids resolve to the monthly cycle', () {
      final sub = UserSubscription.fromMap({
        'subscriptionStatus': 'active',
        'subscriptionProduct': 'hunter_monthly',
      });
      expect(sub.activeCycle, 'monthly');
      expect(sub.isActiveCycle('monthly'), isTrue);
      expect(sub.isActiveCycle('yearly'), isFalse);
    });

    test('no plan id -> null cycle and no card matches', () {
      final sub = UserSubscription.fromMap({'subscriptionStatus': 'active'});
      expect(sub.activeCycle, isNull);
      expect(sub.isActiveCycle('monthly'), isFalse);
      expect(sub.isActiveCycle('yearly'), isFalse);
    });

    test('tolerates the snake_case / plan aliases', () {
      expect(
        UserSubscription.fromMap({'plan': 'hunter_yearly'}).activeCycle,
        'yearly',
      );
      expect(
        UserSubscription.fromMap({'subscription_product': 'hunter_monthly'})
            .activeCycle,
        'monthly',
      );
      expect(
        UserSubscription.fromMap({'billingCycle': 'yearly'}).activeCycle,
        'yearly',
      );
    });
  });

  group('watchMySubscription is resilient (never hangs the screen)', () {
    test('an unauthenticated caller gets the empty subscription value', () {
      SubscriptionStatusService.currentUserIdResolverForTesting = () => null;
      final stream = SubscriptionStatusService.instance.watchMySubscription();
      expect(stream, emits(const UserSubscription()));
    });

    test('the live stream emits a value (never leaves the UI waiting)', () {
      // The guard must always deliver an emission — an empty fallback on a
      // hard error — so the consuming StreamBuilder can never sit in
      // ConnectionState.waiting forever (the "stuck on the selector" bug the
      // old `.handleError` form produced).
      final stream = SubscriptionStatusService.instance.watchMySubscription();
      expect(stream, emits(anything));
    });

    test('the stream is rebuilt per call (callers MUST cache it)', () {
      // Locks the contract the screen relies on: each call opens a NEW
      // Firestore subscription, which is exactly why `SubscriptionScreen`
      // caches it in `initState` instead of calling it from `build()`.
      SubscriptionStatusService.watchMySubscriptionCalls = 0;
      SubscriptionStatusService.instance.watchMySubscription();
      SubscriptionStatusService.instance.watchMySubscription();
      expect(SubscriptionStatusService.watchMySubscriptionCalls, 2);
    });
  });
}

/// Wraps a child so a `setState` rebuild of the SAME subtree can be triggered
/// from a test (the child's own `State` — and therefore its cached stream —
/// survives the rebuild). Mirrors the probe used by the Custom Package Builder
/// suite.
class _RebuildProbe extends StatefulWidget {
  const _RebuildProbe({required this.child});

  final Widget child;

  @override
  State<_RebuildProbe> createState() => _RebuildProbeState();
}

class _RebuildProbeState extends State<_RebuildProbe> {
  int _rebuilds = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          key: const ValueKey('rebuildProbeButton'),
          onPressed: () => setState(() => _rebuilds++),
          child: Text('rebuild $_rebuilds'),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
