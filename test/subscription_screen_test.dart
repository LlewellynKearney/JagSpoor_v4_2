import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/subscription/services/payfast_service.dart';
import 'package:jagspoor/features/subscription/services/subscription_status_service.dart';
import 'package:jagspoor/features/subscription/subscription_screen.dart';

void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    SubscriptionStatusService.firestoreForTesting = fake;
    SubscriptionStatusService.currentUserIdResolverForTesting = () => 'uid-1';
  });

  tearDown(SubscriptionStatusService.resetTestSeams);

  Widget buildScreen({SubscriptionTier? tier}) => MaterialApp(
        home: SubscriptionScreen(theme: ThemeController(), tier: tier),
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    SubscriptionTier? tier,
  }) async {
    await tester.pumpWidget(buildScreen(tier: tier));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();
  }

  group('rendering', () {
    testWidgets('shows the tier pricing, trial banner, promo field and '
        'subscribe button', (tester) async {
      await pumpScreen(tester);

      expect(find.text('NO ACTIVE SUBSCRIPTION'), findsOneWidget);
      expect(find.text('TIER PRICING'), findsOneWidget);
      // Hunter mode (default): ONLY the Hunter tier card renders.
      expect(find.text('R 19.99 / month'), findsOneWidget);
      expect(find.text('R 199.99 / month'), findsNothing);
      expect(find.text('After a 30-day free trial'), findsOneWidget);

      // The promo section sits below the tier card on the 800x600 test
      // surface; scroll it into view before asserting.
      await scrollTo(tester, find.byKey(const ValueKey('promoCodeField')));
      expect(find.text('PROMO CODE'), findsOneWidget);
      expect(find.byKey(const ValueKey('promoCodeField')), findsOneWidget);

      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));
      expect(find.text('SUBSCRIBE VIA PAYFAST'), findsOneWidget);
      expect(find.byKey(const ValueKey('checkoutTotalCard')), findsOneWidget);
      expect(find.text('R 0.00'), findsOneWidget); // free trial row
    });

    testWidgets('marks the hunter tier as YOUR TIER by default', (tester) async {
      await pumpScreen(tester);
      final hunterCard = find.byKey(const ValueKey('tierCard_hunter'));
      expect(hunterCard, findsOneWidget);
      expect(
        find.descendant(of: hunterCard, matching: find.text('YOUR TIER')),
        findsOneWidget,
      );
      // The outfitter card is hidden completely in Hunter Mode.
      expect(find.byKey(const ValueKey('tierCard_outfitter')), findsNothing);
    });

    testWidgets('marks the outfitter tier as YOUR TIER when tier is passed',
        (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.outfitter);
      final outfitterCard = find.byKey(const ValueKey('tierCard_outfitter'));
      expect(outfitterCard, findsOneWidget);
      expect(
        find.descendant(of: outfitterCard, matching: find.text('YOUR TIER')),
        findsOneWidget,
      );
      // The hunter card is hidden completely in Outfitter Mode.
      expect(find.byKey(const ValueKey('tierCard_hunter')), findsNothing);
      // The checkout total maps the outfitter price.
      await scrollTo(tester, find.byKey(const ValueKey('checkoutTotalCard')));
      expect(find.text('R 199.99'), findsOneWidget);
    });
  });

  group('mode-isolated tier display', () {
    const hunterFeatures = [
      'Full Hunter Toolkit & Ballistics Calculator',
      'Weather, Wind & Solunar Tracker',
      'SA Game Guide & Field Estimates',
      'Digital Firearm Safe & Ammunition Manager',
      'Package Marketplace & Custom Package Builder',
      'Digital Trophy Room & Sighting Logger',
      'Off-Grid Topographic Maps & Spoor Identifier',
      'SAPS License Application Tracker',
    ];

    const outfitterFeatures = [
      'Farm Control Panel & Manager Assignments',
      'Custom Farm Species Price List Management',
      'Hunting Package Publishing & Booking Request Management',
      'Slaughterhouse & Carcass Weight Matrix',
      'Off-Grid Mesh Sync & Team Radar',
      'Business Intelligence & Revenue Analytics',
    ];

    testWidgets('Hunter Mode renders ONLY the Hunter tier card with the '
        'full hunter feature list', (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);

      final hunterCard = find.byKey(const ValueKey('tierCard_hunter'));
      expect(hunterCard, findsOneWidget);
      expect(find.byKey(const ValueKey('tierCard_outfitter')), findsNothing);

      for (final feature in hunterFeatures) {
        expect(
          find.descendant(of: hunterCard, matching: find.text(feature)),
          findsOneWidget,
          reason: 'missing hunter feature: $feature',
        );
      }
      // Outfitter-only features never render in Hunter Mode.
      for (final feature in outfitterFeatures) {
        expect(find.text(feature), findsNothing);
      }
    });

    testWidgets('Outfitter Mode renders ONLY the Outfitter tier card with '
        'the full outfitter feature list', (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.outfitter);

      final outfitterCard = find.byKey(const ValueKey('tierCard_outfitter'));
      expect(outfitterCard, findsOneWidget);
      expect(find.byKey(const ValueKey('tierCard_hunter')), findsNothing);

      for (final feature in outfitterFeatures) {
        expect(
          find.descendant(of: outfitterCard, matching: find.text(feature)),
          findsOneWidget,
          reason: 'missing outfitter feature: $feature',
        );
      }
      // Hunter-only feature bullets never render in Outfitter Mode.
      expect(find.text('SAPS License Application Tracker'), findsNothing);
      expect(
        find.text('Digital Firearm Safe & Ammunition Manager'),
        findsNothing,
      );
      // The inaccurate "Everything in Hunter Tier included" copy was removed;
      // only outfitter/farm-manager features are listed.
      expect(find.text('Everything in Hunter Tier included'), findsNothing);
    });

    testWidgets('the monthly summary reflects the Hunter tier fee',
        (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.hunter);
      await scrollTo(tester, find.byKey(const ValueKey('checkoutTotalCard')));
      expect(find.text('Then monthly (hunter)'), findsOneWidget);
      expect(find.text('R 19.99'), findsOneWidget);
      expect(find.text('Then monthly (outfitter)'), findsNothing);
    });

    testWidgets('the monthly summary reflects the Outfitter tier fee',
        (tester) async {
      await pumpScreen(tester, tier: SubscriptionTier.outfitter);
      await scrollTo(tester, find.byKey(const ValueKey('checkoutTotalCard')));
      expect(find.text('Then monthly (outfitter)'), findsOneWidget);
      expect(find.text('R 199.99'), findsOneWidget);
      expect(find.text('Then monthly (hunter)'), findsNothing);
    });
  });

  group('promo code hook', () {
    testWidgets('a valid promo code adjusts the checkout total', (tester) async {
      await pumpScreen(tester);

      await scrollTo(tester, find.byKey(const ValueKey('promoCodeField')));
      await tester.enterText(
          find.byKey(const ValueKey('promoCodeField')), 'jagspoor10');
      await tester.tap(find.byKey(const ValueKey('applyPromoButton')));
      await tester.pump();

      expect(find.byKey(const ValueKey('promoAppliedLabel')), findsOneWidget);
      expect(find.textContaining('JAGSPOOR10'), findsWidgets);
      expect(find.textContaining('10% off'), findsOneWidget);

      // 19.99 - 10% = 17.99 shown as the promo-adjusted monthly total.
      await scrollTo(tester, find.byKey(const ValueKey('checkoutTotalCard')));
      expect(find.text('Promo-adjusted monthly'), findsOneWidget);
      expect(find.text('R 17.99'), findsOneWidget);
    });

    testWidgets('an invalid promo code surfaces an error and no adjustment',
        (tester) async {
      await pumpScreen(tester);

      await scrollTo(tester, find.byKey(const ValueKey('promoCodeField')));
      await tester.enterText(
          find.byKey(const ValueKey('promoCodeField')), 'NOT_A_CODE');
      await tester.tap(find.byKey(const ValueKey('applyPromoButton')));
      await tester.pump();

      expect(find.text('Invalid promo code'), findsOneWidget);
      expect(find.byKey(const ValueKey('promoAppliedLabel')), findsNothing);
      expect(find.text('Promo-adjusted monthly'), findsNothing);
    });
  });

  group('subscription status banner', () {
    testWidgets('shows FREE TRIAL ACTIVE with remaining days', (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'trial',
        'subscriptionTier': 'hunter',
        'subscriptionTrialEndsAt': DateTime.now().add(const Duration(days: 15)),
      });
      await pumpScreen(tester);

      expect(find.text('FREE TRIAL ACTIVE'), findsOneWidget);
      expect(find.textContaining('left of your 30-day free trial'),
          findsOneWidget);
    });

    testWidgets('shows SUBSCRIPTION ACTIVE and disables the subscribe button',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'active',
        'subscriptionTier': 'outfitter',
      });
      await pumpScreen(tester);

      expect(find.text('SUBSCRIPTION ACTIVE'), findsOneWidget);
      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('subscribeButton')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows SUBSCRIPTION CANCELLED for a cancelled sub',
        (tester) async {
      await fake.collection('users').doc('uid-1').set({
        'subscriptionStatus': 'cancelled',
      });
      await pumpScreen(tester);
      expect(find.text('SUBSCRIPTION CANCELLED'), findsOneWidget);
    });
  });

  group('subscribe action', () {
    testWidgets('without a signed-in user a clear snackbar is shown',
        (tester) async {
      // No Firebase app is initialized in the test env, so the email/uid
      // resolution returns null and the subscribe action short-circuits.
      await pumpScreen(tester);

      await scrollTo(tester, find.byKey(const ValueKey('subscribeButton')));
      await tester.tap(find.byKey(const ValueKey('subscribeButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Please sign in with a valid email to subscribe.'),
        findsOneWidget,
      );
    });
  });
}
