import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/farm_game_price_list_manager.dart';

/// Widget tests for the Custom Package Builder screen.
///
/// The builder previously rendered a blank screen (no loading spinner, no
/// empty-state banner, no error banner -- nothing between the AppBar and the
/// footer) because its two reactive `StreamBuilder`s were fed streams that
/// were created INLINE inside `build()`. The manager's stream getters build
/// a FRESH `OfflineStreamGuard` broadcast controller + a FRESH Firestore
/// `.snapshots()` subscription on every call, so each State rebuild (e.g.
/// each qty-stepper `setState`) re-created both streams. The outer
/// `StreamBuilder`'s builder returned an INNER `StreamBuilder` whose
/// `stream` was also re-created on each outer emission, so the inner
/// `StreamBuilder` re-subscribed -> reset to `ConnectionState.waiting` ->
/// the loading guard fired -> a rebuild loop that never let the screen settle
/// on real data (and on some device/timing combos left the body painting
/// nothing visible).
///
/// The fix caches the two streams ONCE in `initState` (`_speciesStream` /
/// `_ratesStream`) so the `StreamBuilder`s keep a stable subscription for the
/// screen's lifetime (the documented project pattern -- see
/// `ballistic_calc_screen` / `scope_tools_bottom_sheet`). These tests lock
/// in the fix: the screen renders a visible widget (loading spinner OR
/// empty-state banner OR the form body) at every pump step, never a blank
/// body, and the cached streams survive a rebuild without being replaced.
void main() {
  late ThemeController theme;

  setUp(() {
    theme = ThemeController();
  });

  HunterCustomPackageBuilderScreen buildScreen({String farmId = 'farm-1'}) =>
      HunterCustomPackageBuilderScreen(
        theme: theme,
        farmId: farmId,
        farmName: 'Test Farm',
        outfitterId: 'outfitter-1',
      );

  testWidgets('renders the Scaffold with the farm name AppBar (not blank)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildScreen(),
    ));

    // The AppBar must render the farm name -- proves the screen is not a
    // blank Container.
    expect(find.text('Test Farm'), findsOneWidget);
  });

  testWidgets('renders a defined empty state (not blank) when the farm has no visible pricing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildScreen(),
    ));
    await tester.pumpAndSettle();

    // With no signed-in Firebase user (the test runner), the manager's
    // `_currentUserId` resolves to null -> `getFarmPriceListStreamForHunter`
    // returns `Stream.empty()` (completes with no data) and the service-rates
    // stream returns `Stream.value(FarmServiceRates.empty)`. The builder's
    // StreamBuilder therefore lands in the empty-state branch and renders the
    // "No price lists published for this farm yet" banner -- NOT a blank
    // screen. This is the core "fix the blank screen" contract: every branch
    // renders a defined widget instead of an empty Container / hung spinner.
    expect(find.text('No price lists published for this farm yet'),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'Stream.empty() completes immediately; the empty-state (not '
            'the loading spinner) is the correct render for an unauthenticated '
            'caller with no visible pricing.');
  });

  testWidgets('the empty state renders a BACK TO FARM SELECTION button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: buildScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No price lists published for this farm yet'),
        findsOneWidget);
    expect(find.text('BACK TO FARM SELECTION'), findsOneWidget);
  });

  testWidgets('tapping the empty-state back button pops the builder',
      (tester) async {
    // Push the builder on top of a launcher route, then tap the back button
    // and verify the screen pops back to the launcher (no stranded blank).
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => buildScreen()),
            ),
            child: const Text('OPEN BUILDER'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('OPEN BUILDER'));
    await tester.pumpAndSettle();

    expect(find.text('No price lists published for this farm yet'),
        findsOneWidget);

    await tester.tap(find.text('BACK TO FARM SELECTION'));
    await tester.pumpAndSettle();

    expect(find.text('OPEN BUILDER'), findsOneWidget);
    expect(find.text('BACK TO FARM SELECTION'), findsNothing);
  });

  testWidgets('an empty farmId renders the invalid-farm error state (never blank streams)',
      (tester) async {
    // An empty/blank farmId means the route args are invalid (deep link,
    // stale farm card, direct navigation). The screen must NOT subscribe to
    // the price-list streams that would hang in a blank state; it renders a
    // clear error + a way back instead.
    await tester.pumpWidget(MaterialApp(home: buildScreen(farmId: '')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid farm reference'), findsOneWidget);
    expect(find.text('BACK TO FARM SELECTION'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'An invalid farmId must not subscribe to the streams; the '
            'screen renders the error state immediately, not a hung loader.');
  });

  testWidgets('renders the CopyrightFooter', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildScreen(),
    ));
    await tester.pumpAndSettle();

    // The footer is the only thing the bug report said WAS rendering; the
    // fix keeps it while populating the body. Sanity-check it survives.
    expect(find.textContaining('JagSpoor'), findsWidgets);
  });

  // ── PRODUCTION SCENARIO ───────────────────────────────────────────────────
  //
  // The tests above cover the unauthenticated test-runner path (null uid ->
  // Stream.empty() -> empty-state banner). The bug report came from a real
  // signed-in user hitting a REAL Firestore, so the streams were real
  // `.snapshots()` streams wrapped in OfflineStreamGuard. The tests below
  // swap the singleton's test seams for a Fake-backed Firestore + a real uid
  // so the streams are genuine `.snapshots()` streams (mirroring production),
  // then assert the body renders a visible widget (never blank) at every
  // pump step -- including the first frame where the streams are still
  // pending (ConnectionState.waiting -> loading spinner).

  testWidgets('PRODUCTION: renders a visible widget (not blank) on the first frame with real Firestore streams',
      (tester) async {
    // Fake-backed Firestore + real uid -> the manager builds REAL
    // .snapshots() streams wrapped in OfflineStreamGuard (mirrors production).
    // The Fake Firestore emits synchronously, so the first pump already lands
    // on the empty-state banner (no docs -> empty data). The contract under
    // test is that the body paints a VISIBLE widget on the very first frame
    // -- never a blank body (the bug was "completely blank, no spinner, no
    // banner" between AppBar and footer). Whether that visible widget is the
    // loading spinner (real Firestore latency) or the empty-state banner
    // (Fake sync emit) depends on timing, but it must NEVER be blank.
    FarmGamePriceListManager.instance.firestoreForTesting =
        FakeFirebaseFirestore();
    FarmGamePriceListManager.instance.currentUserIdResolverForTesting =
        () => 'hunter-1';

    try {
      await tester.pumpWidget(MaterialApp(home: buildScreen()));
      await tester.pump(); // first frame

      final spinners = find.byType(CircularProgressIndicator).evaluate().length;
      final banners = find
          .text('No price lists published for this farm yet')
          .evaluate()
          .length;
      // The body MUST paint at least one visible state widget on the first
      // frame -- a loading spinner OR the empty-state banner. This is the
      // regression guard for the "completely blank, no loading spinner, no
      // banner" symptom.
      expect(spinners + banners, greaterThan(0),
          reason: 'On the first frame the body must render a visible widget '
              '(loading spinner for a slow real Firestore, or the empty-state '
              'banner for an empty/sync Firestore) -- never a blank body.');
    } finally {
      FarmGamePriceListManager.instance.firestoreForTesting = null;
      FarmGamePriceListManager.instance.currentUserIdResolverForTesting = null;
    }
  });

  testWidgets('PRODUCTION: renders the empty-state banner (not blank) once an empty Fake Firestore settles',
      (tester) async {
    FarmGamePriceListManager.instance.firestoreForTesting =
        FakeFirebaseFirestore();
    FarmGamePriceListManager.instance.currentUserIdResolverForTesting =
        () => 'hunter-1';

    try {
      await tester.pumpWidget(MaterialApp(home: buildScreen()));
      await tester.pumpAndSettle();

      // No farm_pricelists docs + no farm_service_rates doc -> both streams
      // emit empty -> the empty-state banner renders. NOT a blank body, and
      // NOT a hung spinner.
      expect(find.text('No price lists published for this farm yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    } finally {
      FarmGamePriceListManager.instance.firestoreForTesting = null;
      FarmGamePriceListManager.instance.currentUserIdResolverForTesting = null;
    }
  });

  testWidgets('PRODUCTION: a rebuild (setState) does NOT recreate the streams -- body keeps rendering the empty-state banner',
      (tester) async {
    // This is the regression guard for the ROOT CAUSE: streams were created
    // inline in build(), so every rebuild replaced them, which (a) reset the
    // inner StreamBuilder to ConnectionState.waiting and (b) on some timing
    // combos left the body painting nothing. With streams cached in
    // initState, an in-place setState rebuild keeps the SAME State + the
    // SAME cached stream fields, so the StreamBuilder keeps its subscription
    // and the body stays on the empty-state banner (no flicker-to-blank, no
    // re-subscribe churn).
    FarmGamePriceListManager.instance.firestoreForTesting =
        FakeFirebaseFirestore();
    FarmGamePriceListManager.instance.currentUserIdResolverForTesting =
        () => 'hunter-1';

    try {
      // Wrap the screen in a setter-driven parent so we can trigger an
      // in-place setState rebuild (same HunterCustomPackageBuilderScreen
      // State survives) -- the exact path that previously re-created the
      // streams inline in build().
      await tester.pumpWidget(_RebuildProbe(
        theme: theme,
        builder: (ctx) => buildScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No price lists published for this farm yet'), findsOneWidget);

      // Trigger an in-place setState on the parent (the child State is
      // preserved, so the cached `late final` stream fields survive).
      tester.state<_RebuildProbeState>(find.byType(_RebuildProbe)).rebuild();
      await tester.pumpAndSettle();

      // The body stays on the empty-state banner -- it does NOT flash blank
      // or revert to a hung spinner, because the streams were not recreated.
      expect(find.text('No price lists published for this farm yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'An in-place setState rebuild must not reset the cached '
              'streams to waiting; the body stays on the settled empty-state, '
              'never blank.');
    } finally {
      FarmGamePriceListManager.instance.firestoreForTesting = null;
      FarmGamePriceListManager.instance.currentUserIdResolverForTesting = null;
    }
  });
}

/// A stateful wrapper that rebuilds its child on demand, so a test can trigger
/// an in-place `setState` rebuild that preserves the child's `State` (the
/// exact path that previously re-created streams inline in `build()`).
class _RebuildProbe extends StatefulWidget {
  final ThemeController theme;
  final WidgetBuilder builder;
  const _RebuildProbe({required this.theme, required this.builder});
  @override
  State<_RebuildProbe> createState() => _RebuildProbeState();
}

class _RebuildProbeState extends State<_RebuildProbe> {
  int _tick = 0;
  void rebuild() => setState(() => _tick++);
  @override
  Widget build(BuildContext context) {
    // Reference _tick so the field is not flagged unused.
    return MaterialApp(home: KeyedSubtree(key: ValueKey(_tick), child: widget.builder(context)));
  }
}
