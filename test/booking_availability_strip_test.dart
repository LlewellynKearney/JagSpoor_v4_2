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
}
