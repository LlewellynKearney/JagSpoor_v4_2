import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_details.dart';
import 'package:jagspoor/features/hunter_mode/screens/hunter_custom_package_builder_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/booking_availability_service.dart';
import 'package:jagspoor/features/hunter_mode/services/farm_details_resolver.dart';
import 'package:jagspoor/features/hunter_mode/services/farm_game_price_list_manager.dart';
import 'package:jagspoor/features/hunter_mode/widgets/booking_availability_strip.dart';
import 'package:jagspoor/features/hunter_mode/widgets/trophy_booking_confirmation_sheet.dart';
import 'package:jagspoor/services/external_booking_adapter.dart';

/// Widget-level integration tests for the interactive booking availability
/// strip embedded in the two remaining hunter booking flows: the Custom
/// Package Builder form and the Trophy Registry & Booking confirmation sheet.
///
/// Both flows must (1) render the live date-slot strip, (2) keep the submit /
/// book action DISABLED until the hunter taps a hunt window on the strip, and
/// (3) refuse selection of outfitter-blocked (red) days. The availability
/// lookup is injected through the strip's `availabilityLoader` seam so no
/// Firestore / network access happens.
void main() {
  final todayMidnight = normalizeBookingDate(DateTime.now());
  final tomorrow = todayMidnight.add(const Duration(days: 1));

  BookingAvailability fakeAvailability({Set<DateTime> blocked = const {}}) {
    return BookingAvailability(
      outfitterId: 'outfitter-1',
      externalBlockedDates: blocked,
      localBlockedDates: const {},
      systemType: ExternalBookingSystemType.manual,
      externalReachable: true,
    );
  }

  /// Finds a day-number slot inside the availability strip (descendant-scoped
  /// so day numbers never collide with other texts on the screen).
  Finder daySlot(DateTime day) => find.descendant(
        of: find.byType(BookingAvailabilityStrip),
        matching: find.text('${day.day}'),
      );

  group('Trophy Registry & Booking confirmation sheet', () {
    late ThemeController theme;

    const trophy = <String, dynamic>{
      'id': 'trophy-1',
      'outfitterId': 'outfitter-1',
      'species': 'Impala',
      'available': 2,
      'pricePerTrophy': 5000.0,
      'farmId': 'farm-1',
      'farmName': 'Test Farm',
      'town': 'Waterberg',
      'province': 'Limpopo',
      'sex': 'Male',
    };

    setUp(() async {
      theme = ThemeController();
      // Bind the farm-details resolver to a fake Firestore so the sheet's
      // farm panel resolves against a real (in-memory) store instead of
      // failing with `[core/no-app]` (no Firebase app exists in tests).
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('farms').doc('farm-1').set({
        'name': 'Test Farm',
        'district': 'Waterberg',
        'province': 'Limpopo',
      });
      FarmDetailsResolver.firestoreForTesting = fakeFirestore;
    });

    tearDown(() => FarmDetailsResolver.firestoreForTesting = null);

    Widget buildSheet({Set<DateTime> blocked = const {}}) {
      return MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: Scaffold(
          body: TrophyBookingConfirmationSheet(
            trophy: trophy,
            theme: theme,
            availabilityLoader: () async => fakeAvailability(blocked: blocked),
          ),
        ),
      );
    }

    ElevatedButton bookButton(WidgetTester tester) =>
        tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'BOOK THIS TROPHY'),
        );

    testWidgets('renders the availability strip and keeps BOOK disabled until '
        'a hunt window is selected', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pumpAndSettle();

      // The live strip renders in interactive mode.
      expect(find.text('LIVE DATE AVAILABILITY'), findsOneWidget);
      expect(
        find.text('Tap an available (green) start date, then an end date.'),
        findsOneWidget,
      );
      expect(find.text('No hunt window selected yet.'), findsOneWidget);

      // The BOOK button is present but DISABLED while no window is selected,
      // with an explanatory hint.
      expect(bookButton(tester).onPressed, isNull,
          reason: 'A trophy hunt booking must require a strip date '
              'selection before it can be submitted.');
      expect(
        find.textContaining(
            'Select your hunt dates on the availability strip'),
        findsOneWidget,
      );
    });

    testWidgets('tapping an available day selects the window and enables '
        'BOOK', (tester) async {
      await tester.pumpWidget(buildSheet());
      await tester.pumpAndSettle();

      await tester.tap(daySlot(todayMidnight));
      await tester.pumpAndSettle();
      await tester.tap(daySlot(tomorrow));
      await tester.pumpAndSettle();

      // The selection summary reports the chosen window ...
      expect(find.textContaining('Selected:'), findsOneWidget);
      expect(find.textContaining('(2 days)'), findsOneWidget);
      // ... and the BOOK button is now enabled.
      expect(bookButton(tester).onPressed, isNotNull);
    });

    testWidgets('outfitter-blocked days are NOT selectable and BOOK stays '
        'disabled', (tester) async {
      await tester.pumpWidget(buildSheet(blocked: {todayMidnight}));
      await tester.pumpAndSettle();

      await tester.tap(daySlot(todayMidnight));
      await tester.pumpAndSettle();

      expect(find.text('No hunt window selected yet.'), findsOneWidget);
      expect(bookButton(tester).onPressed, isNull,
          reason: 'A blocked (red) day must never start a booking window.');
    });
  });

  group('Custom Package Builder', () {
    late ThemeController theme;
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() async {
      theme = ThemeController();
      fakeFirestore = FakeFirebaseFirestore();
      // Seed a published farm price list so the builder renders the full form
      // (species rows + the hunt-window availability card).
      await fakeFirestore.collection('farm_pricelists').doc('sp1').set({
        'farmId': 'farm-1',
        'outfitterId': 'outfitter-1',
        'speciesName': 'Impala',
        'qty': 3,
        'price': 1500.0,
        'gender': 'Male',
      });
      FarmGamePriceListManager.instance.firestoreForTesting = fakeFirestore;
      FarmGamePriceListManager.instance.currentUserIdResolverForTesting =
          () => 'hunter-1';
    });

    tearDown(() {
      FarmGamePriceListManager.instance.firestoreForTesting = null;
      FarmGamePriceListManager.instance.currentUserIdResolverForTesting = null;
    });

    Widget buildBuilder({Set<DateTime> blocked = const {}}) {
      return MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: HunterCustomPackageBuilderScreen(
          theme: theme,
          farmId: 'farm-1',
          farmDetails: const FarmDetails(farmId: 'farm-1', name: 'Test Farm'),
          outfitterId: 'outfitter-1',
          availabilityLoader: () async => fakeAvailability(blocked: blocked),
        ),
      );
    }

    void useTallSurface(WidgetTester tester) {
      // The builder body is a lazy ListView; enlarge the test surface so the
      // submit card is built (otherwise off-screen items are never laid out).
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    ElevatedButton submitButton(WidgetTester tester) =>
        tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Submit Custom Package Request'),
        );

    testWidgets('renders the interactive availability strip in the hunt '
        'window card', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(buildBuilder());
      await tester.pumpAndSettle();

      expect(find.text('LIVE DATE AVAILABILITY'), findsOneWidget);
      expect(
        find.text('Tap an available (green) start date, then an end date.'),
        findsOneWidget,
      );
      expect(
        find.text('Required — pick your hunting dates below.'),
        findsOneWidget,
      );
    });

    testWidgets('submission is DISABLED until a hunt window is selected on '
        'the strip (even with line items picked)', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(buildBuilder());
      await tester.pumpAndSettle();

      // No quantities + no dates -> disabled.
      expect(submitButton(tester).onPressed, isNull);

      // Pick a species quantity (the + steppers in tree order are: hunters,
      // observers, then the first species row).
      await tester.tap(find.byIcon(Icons.add_rounded).at(2));
      await tester.pumpAndSettle();

      // A line item is selected but no hunt window -> STILL disabled, with
      // the explanatory hint.
      expect(submitButton(tester).onPressed, isNull,
          reason: 'The strip date selection is REQUIRED even when line items '
              'are picked.');
      expect(
        find.textContaining(
            'Select your hunt dates on the availability strip above'),
        findsOneWidget,
      );

      // Select the hunt window on the strip (tap start + end).
      await tester.tap(daySlot(todayMidnight));
      await tester.pumpAndSettle();
      await tester.tap(daySlot(tomorrow));
      await tester.pumpAndSettle();

      // Now the window is selected -> the derived hunting-days summary +
      // the selection summary render and the submit button enables.
      expect(find.textContaining('1 hunting day selected'), findsOneWidget);
      expect(find.textContaining('Selected:'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('outfitter-blocked days cannot start the window, so '
        'submission stays disabled', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(buildBuilder(blocked: {todayMidnight}));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded).at(2));
      await tester.pumpAndSettle();
      await tester.tap(daySlot(todayMidnight));
      await tester.pumpAndSettle();

      expect(find.text('No hunt window selected yet.'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);
    });
  });
}
