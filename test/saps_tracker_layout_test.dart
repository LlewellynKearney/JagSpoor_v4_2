import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/ballistics/data/models/saps_application_model.dart';
import 'package:jagspoor/features/hunter_mode/presentation/saps_tracker_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_tracker_service.dart';

void main() {
  SapsApplication buildApp({String status = 'CFR Processing'}) {
    return SapsApplication(
      id: 'app-1',
      hunterId: 'hunter-1',
      referenceNumber: '10470664',
      idNumber: '9001015009087',
      applicationType: 'Section 16 Dedicated Hunting',
      currentStatus: status,
      firearmMake: 'TIKKA T3X TACTICAL AAC-SD RIFLE',
      calibre: '6.5MM CREEDMOOR',
      serialNumber: 'OB14468',
      submittedAt: DateTime(2026, 6, 1),
      createdAt: DateTime(2026, 6, 1),
      provincialDfoReceivedAt: DateTime(2026, 6, 8),
      lastChecked: DateTime(2026, 9, 5, 10, 30),
    );
  }

  testWidgets('SAPS card: LONG labels at narrow width, expanded, no overflow',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SapsApplicationCard(
              application: buildApp(),
              trackerService: SapsTrackerService.forTesting(
                FakeFirebaseFirestore(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Section 16 Dedicated Hunting'));
    await tester.pumpAndSettle();
    final e = tester.takeException();
    expect(e, isNull, reason: 'no overflow when card expanded: $e');
  });

  // REGRESSION GUARD for the root-cause bug: the card header Row had an
  // unconstrained status badge, so the real CFR phrase "Application received
  // at DFO" (with a long application type) overflowed the card horizontally
  // by 164 px at 1.3x text scale. The type is now Expanded and the badge is
  // Flexible + ellipsized.
  testWidgets('SAPS card: header with long status + long type, narrow + 1.3x',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SapsApplicationCard(
              application: buildApp(status: 'Application received at DFO'),
              trackerService: SapsTrackerService.forTesting(
                FakeFirebaseFirestore(),
              ),
            ),
          ),
        ),
      ),
    );
    final e = tester.takeException();
    expect(e, isNull, reason: 'no overflow in card header: $e');
  });

  testWidgets('SAPS screen: no overflow large text scale, register expanded',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const MaterialApp(home: SapsTrackerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register New Application'));
    await tester.pumpAndSettle();
    final e = tester.takeException();
    expect(e, isNull, reason: 'no overflow large text register: $e');
  });

  testWidgets('SAPS screen: no overflow small screen, register expanded',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 480 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SapsTrackerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register New Application'));
    await tester.pumpAndSettle();
    final e = tester.takeException();
    expect(e, isNull, reason: 'no overflow small screen register: $e');
  });
}
