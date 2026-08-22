import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/services/booking_availability_service.dart';
import 'package:jagspoor/features/hunter_mode/widgets/booking_availability_strip.dart';
import 'package:jagspoor/services/external_booking_adapter.dart';

/// Widget tests for the live date-slot availability strip in the hunter
/// booking flow. The availability lookup is injected so no Firestore / network
/// access happens.
void main() {
  final today = DateTime.now();
  final todayMidnight = normalizeBookingDate(today);

  BookingAvailability fakeAvailability({
    Set<DateTime> blocked = const {},
    bool externalReachable = true,
  }) {
    return BookingAvailability(
      outfitterId: 'outfitter-1',
      externalBlockedDates: blocked,
      localBlockedDates: const {},
      systemType: ExternalBookingSystemType.mock,
      externalReachable: externalReachable,
    );
  }

  Widget buildStrip({
    Set<DateTime> blocked = const {},
    bool externalReachable = true,
    bool fail = false,
    int dayCount = 14,
  }) {
    return MaterialApp(
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: BookingAvailabilityStrip(
            outfitterId: 'outfitter-1',
            theme: ThemeController(),
            dayCount: dayCount,
            availabilityLoader: () async {
              if (fail) throw Exception('offline');
              return fakeAvailability(
                blocked: blocked,
                externalReachable: externalReachable,
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets('renders the header + a date slot per day', (tester) async {
    await tester.pumpWidget(buildStrip(dayCount: 7));
    expect(find.text('LIVE DATE AVAILABILITY'), findsOneWidget);
    expect(find.text('Checking live availability…'), findsOneWidget);
    await tester.pumpAndSettle();
    // 7 day slots render with the "all available" summary.
    expect(find.text('All dates shown are available.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets('reports blocked dates in the summary', (tester) async {
    await tester.pumpWidget(buildStrip(blocked: {todayMidnight}));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1 date(s) shown are unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('renders the cloud-off indicator when the external calendar '
      'is unreachable', (tester) async {
    await tester.pumpWidget(buildStrip(externalReachable: false));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('renders a graceful fallback when the lookup fails',
      (tester) async {
    await tester.pumpWidget(buildStrip(fail: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Live availability could not be checked'),
      findsOneWidget,
    );
  });

  group('interactive date selection', () {
    Widget buildSelectableStrip({
      Set<DateTime> blocked = const {},
      ExternalBookingSystemType systemType = ExternalBookingSystemType.manual,
      void Function(BookingDateSelection?)? onSelectionChanged,
      DateTime? initialStart,
      DateTime? initialEnd,
    }) {
      return MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BookingAvailabilityStrip(
              outfitterId: 'outfitter-1',
              theme: ThemeController(),
              dayCount: 7,
              onSelectionChanged: onSelectionChanged,
              initialStart: initialStart,
              initialEnd: initialEnd,
              availabilityLoader: () async => BookingAvailability(
                outfitterId: 'outfitter-1',
                externalBlockedDates: blocked,
                localBlockedDates: const {},
                systemType: systemType,
                externalReachable: true,
              ),
            ),
          ),
        ),
      );
    }

    Finder daySlot(DateTime day) => find.text('${day.day}');

    testWidgets('manual mode is labelled + available dates are tappable',
        (tester) async {
      BookingDateSelection? selection;
      await tester.pumpWidget(
        buildSelectableStrip(
          onSelectionChanged: (s) => selection = s,
        ),
      );
      await tester.pumpAndSettle();

      // Mode label + tap hint render in interactive mode.
      expect(find.text('Manually managed by the outfitter'), findsOneWidget);
      expect(
        find.text('Tap an available (green) start date, then an end date.'),
        findsOneWidget,
      );

      // Tapping an available date selects it as the window start.
      await tester.tap(daySlot(todayMidnight));
      await tester.pumpAndSettle();
      expect(selection, isNotNull);
      expect(selection!.start, todayMidnight);
      expect(selection!.end, todayMidnight);
      expect(selection!.dayCount, 1);
      expect(find.textContaining('Selected:'), findsOneWidget);
    });

    testWidgets('blocked dates are NOT selectable', (tester) async {
      BookingDateSelection? selection;
      await tester.pumpWidget(
        buildSelectableStrip(
          blocked: {todayMidnight},
          onSelectionChanged: (s) => selection = s,
        ),
      );
      await tester.pumpAndSettle();

      // Tapping a blocked date must not start a selection.
      await tester.tap(daySlot(todayMidnight));
      await tester.pumpAndSettle();
      expect(selection, isNull);
      expect(find.text('No hunt window selected yet.'), findsOneWidget);
    });

    testWidgets('tap 2 selects the window end (range selection)',
        (tester) async {
      BookingDateSelection? selection;
      await tester.pumpWidget(
        buildSelectableStrip(onSelectionChanged: (s) => selection = s),
      );
      await tester.pumpAndSettle();

      final start = todayMidnight.add(const Duration(days: 1));
      final end = todayMidnight.add(const Duration(days: 3));
      await tester.tap(daySlot(start));
      await tester.pumpAndSettle();
      await tester.tap(daySlot(end));
      await tester.pumpAndSettle();

      expect(selection, isNotNull);
      expect(selection!.start, start);
      expect(selection!.end, end);
      expect(selection!.dayCount, 3);
    });

    testWidgets('a third tap restarts the selection window', (tester) async {
      BookingDateSelection? selection;
      await tester.pumpWidget(
        buildSelectableStrip(onSelectionChanged: (s) => selection = s),
      );
      await tester.pumpAndSettle();

      final first = todayMidnight.add(const Duration(days: 1));
      final second = todayMidnight.add(const Duration(days: 3));
      final third = todayMidnight.add(const Duration(days: 5));
      await tester.tap(daySlot(first));
      await tester.pumpAndSettle();
      await tester.tap(daySlot(second));
      await tester.pumpAndSettle();
      // A fresh tap after a completed window restarts the selection.
      await tester.tap(daySlot(third));
      await tester.pumpAndSettle();

      expect(selection, isNotNull);
      expect(selection!.start, third);
      expect(selection!.end, third);
      expect(selection!.dayCount, 1);
    });

    testWidgets('initial selection renders the seeded window summary',
        (tester) async {
      final start = todayMidnight.add(const Duration(days: 2));
      final end = todayMidnight.add(const Duration(days: 4));
      await tester.pumpWidget(
        buildSelectableStrip(
          onSelectionChanged: (_) {},
          initialStart: start,
          initialEnd: end,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('(3 days)'), findsOneWidget);
    });

    testWidgets('external (mock) mode label is shown instead of manual',
        (tester) async {
      await tester.pumpWidget(
        buildSelectableStrip(
          systemType: ExternalBookingSystemType.mock,
          onSelectionChanged: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mock availability simulator'), findsOneWidget);
      expect(
        find.text('Manually managed by the outfitter'),
        findsNothing,
      );
    });

    testWidgets('render-only strip (no onSelectionChanged) does NOT show the '
        'selection summary or tap hint', (tester) async {
      await tester.pumpWidget(buildStrip(dayCount: 7));
      await tester.pumpAndSettle();
      expect(
        find.text('Tap an available (green) start date, then an end date.'),
        findsNothing,
      );
      expect(find.textContaining('Selected:'), findsNothing);
      expect(find.text('No hunt window selected yet.'), findsNothing);
    });
  });
}
