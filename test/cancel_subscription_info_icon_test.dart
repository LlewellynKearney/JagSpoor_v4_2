import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/widgets/cancel_subscription_info_icon.dart';

/// The cancel-help UI: the platform copy, the gating resolver and the dialog
/// (including the tappable support address).
///
/// `url_launcher` is a platform channel, so it is mocked — no test here needs a
/// real mail client.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final launched = <String>[];

  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          launched.add(call.arguments['url'] as String? ?? '');
        }
        return true;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });

  Widget host(Widget child, {bool dark = false}) => MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: Scaffold(body: Center(child: child)),
      );

  // ── copy ─────────────────────────────────────────────────────────────────

  group('getCancelInstructions', () {
    test('Google Play copy walks through the Play Store path', () {
      final text = getCancelInstructions(BillingPlatform.googlePlay);
      expect(text, contains('Open Google Play Store app'));
      expect(text, contains('Payments & subscriptions > Subscriptions'));
      expect(text, contains('Select JagSpoor'));
      expect(text, contains('Tap Cancel subscription'));
      expect(text, contains('Cancel at least 24h before renewal'));
    });

    test('PayFast copy points at the PayFast dashboard', () {
      final text = getCancelInstructions(BillingPlatform.payfast);
      expect(text, contains('website billing'));
      expect(text, contains('MANAGE SUBSCRIPTION ON PAYFAST'));
      expect(text, contains('My Subscriptions'));
      expect(text, contains('Cancel next to your JagSpoor plan'));
    });

    test('alternative-billing copy says it came through Google Play', () {
      final text = getCancelInstructions(BillingPlatform.payfastAlternative);
      expect(text, contains('PayFast via Google Play'));
      expect(text, contains('alternative billing choice through Google Play'));
      expect(text, contains('MANAGE SUBSCRIPTION ON PAYFAST'));
    });

    test('every variant names the hyphenated support address', () {
      for (final platform in BillingPlatform.values) {
        expect(
          getCancelInstructions(platform),
          contains('support@jag-spoor.co.za'),
          reason: '$platform must offer the support address',
        );
        // The legacy (non-hyphenated) dispute address must NOT appear.
        expect(getCancelInstructions(platform), isNot(contains('support@jagspoor')));
      }
    });

    test('the mailto target carries the cancel-subscription subject', () {
      expect(cancelSupportMailto, startsWith('mailto:support@jag-spoor.co.za'));
      expect(cancelSupportMailto, contains('subject=Cancel%20Subscription%20Help'));
    });
  });

  // ── gating ───────────────────────────────────────────────────────────────

  group('CancelSubscriptionInfoIcon.resolveFor', () {
    test('web build -> payfast, for an active subscriber', () {
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: true,
          hasActiveSubscription: true,
          isPayfastBilled: false,
          isPayfastAlternative: false,
          isActivePlaySub: false,
        ),
        BillingPlatform.payfast,
      );
    });

    test('web build with no active subscription -> hidden', () {
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: true,
          hasActiveSubscription: false,
          isPayfastBilled: false,
          isPayfastAlternative: false,
          isActivePlaySub: false,
        ),
        isNull,
      );
    });

    test('native PayFast-billed -> alternative copy (routes to PayFast)', () {
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: false,
          hasActiveSubscription: true,
          isPayfastBilled: true,
          isPayfastAlternative: false,
          isActivePlaySub: false,
        ),
        BillingPlatform.payfastAlternative,
      );
    });

    test('native PayFast chosen via User Choice -> alternative copy', () {
      // `payfastChosen` selects the COPY among active subscribers; it is not a
      // gate opener, so an active subscription is still required (a trial user
      // mid-choice has nothing to cancel).
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: false,
          hasActiveSubscription: true,
          isPayfastBilled: false,
          isPayfastAlternative: false,
          isActivePlaySub: false,
          payfastChosen: true,
        ),
        BillingPlatform.payfastAlternative,
      );
    });

    test('choosing PayFast alone does not reveal the icon to a trial user', () {
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: false,
          hasActiveSubscription: false,
          isPayfastBilled: false,
          isPayfastAlternative: false,
          isActivePlaySub: false,
          payfastChosen: true,
        ),
        isNull,
      );
    });

    test('native Play-billed -> googlePlay copy', () {
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: false,
          hasActiveSubscription: true,
          isPayfastBilled: false,
          isPayfastAlternative: false,
          isActivePlaySub: true,
        ),
        BillingPlatform.googlePlay,
      );
    });

    test('PayFast wins over Play when both flags are set', () {
      // A PayFast subscriber must never be told to use the Play manager.
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: false,
          hasActiveSubscription: true,
          isPayfastBilled: true,
          isPayfastAlternative: true,
          isActivePlaySub: true,
        ),
        BillingPlatform.payfastAlternative,
      );
    });

    test('trial / no subscription -> hidden (nothing to cancel)', () {
      expect(
        CancelSubscriptionInfoIcon.resolveFor(
          isWebBilling: false,
          hasActiveSubscription: false,
          isPayfastBilled: false,
          isPayfastAlternative: false,
          isActivePlaySub: false,
        ),
        isNull,
      );
    });
  });

  // ── widget ───────────────────────────────────────────────────────────────

  group('CancelSubscriptionInfoIcon', () {
    testWidgets('renders a keyed info icon with the tooltip', (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.googlePlay,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('cancelInfoIcon_googlePlay')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byTooltip('How to cancel'), findsOneWidget);
    });

    testWidgets('the key is per-platform', (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.payfastAlternative,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('cancelInfoIcon_payfastAlternative')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cancelInfoIcon_googlePlay')),
        findsNothing,
      );
    });

    testWidgets('tapping opens the dialog with the platform copy',
        (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.payfast,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cancelSubscriptionHelpDialog')),
        findsOneWidget,
      );
      expect(find.text('How to cancel your subscription'), findsOneWidget);
      expect(
        find.textContaining('MANAGE SUBSCRIPTION ON PAYFAST'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cancelInfoCloseButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cancelInfoEmailButton')),
        findsOneWidget,
      );
    });

    testWidgets('the close button dismisses the dialog', (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.googlePlay,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('cancelInfoCloseButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancelInfoCloseButton')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cancelSubscriptionHelpDialog')),
        findsNothing,
      );
    });

    testWidgets('Email Support launches the mailto target', (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.googlePlay,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('cancelInfoEmailButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancelInfoEmailButton')));
      await tester.pumpAndSettle();

      expect(launched, isNotEmpty);
      expect(launched.last, contains('mailto:support@jag-spoor.co.za'));
      expect(launched.last, contains('Cancel%20Subscription%20Help'));
    });

    testWidgets('the inline address span is wired to launch mailto',
        (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.payfast,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      // The address is rendered as its own TextSpan carrying a
      // TapGestureRecognizer, so it is tappable independently of the
      // surrounding copy. (`tapOnText` cannot reach it — the substring lives
      // inside a span tree, not a plain Text — so the recognizer's callback is
      // driven directly.)
      final rich = find.byWidgetPredicate(
        (w) => w is SelectableText && w.textSpan != null,
      );
      expect(rich, findsOneWidget);
      final span = tester.widget<SelectableText>(rich).textSpan!;
      final spans = <TextSpan>[];
      span.visitChildren((s) {
        if (s is TextSpan) spans.add(s);
        return true;
      });
      final emailSpan = spans.firstWhere((s) => s.text == cancelSupportEmail);
      expect(emailSpan.recognizer, isNotNull);
      expect(emailSpan.style?.decoration, TextDecoration.underline);

      (emailSpan.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();
      expect(launched, isNotEmpty);
      expect(launched.last, contains('mailto:support@jag-spoor.co.za'));
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.googlePlay,
          ),
          dark: true,
        ),
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.text('How to cancel your subscription'), findsOneWidget);
    });

    testWidgets('the dialog content is scrollable and width-capped',
        (tester) async {
      await tester.pumpWidget(
        host(
          const CancelSubscriptionInfoIcon(
            platform: BillingPlatform.payfastAlternative,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      // A long instruction body must never overflow the dialog.
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cancelSubscriptionHelpDialog')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      // The content is capped at 400 logical px on mobile (the Dialog itself
      // fills the 800px test surface; the ConstrainedBox is what caps it).
      final contentSize = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('cancelSubscriptionHelpDialog')),
          matching: find.byType(ConstrainedBox),
        ).first,
      );
      expect(contentSize.width, lessThanOrEqualTo(400));
    });
  });
}
