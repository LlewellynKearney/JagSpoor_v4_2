import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/ballistics/data/models/saps_application_model.dart';
import 'package:jagspoor/features/hunter_mode/presentation/saps_tracker_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_tracker_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SapsApplication buildApp({
    DateTime? submittedAt,
    DateTime? provincialDfoReceivedAt,
    String calibre = '6MM MUSGRAVE',
    String serialNumber = 'OB14468',
    String status = 'Provincial',
  }) {
    return SapsApplication(
      id: 'app-1',
      hunterId: 'hunter-1',
      referenceNumber: '10470664',
      idNumber: '9001015009087',
      applicationType: 'Section 16 Dedicated Hunting',
      currentStatus: status,
      calibre: calibre,
      serialNumber: serialNumber,
      submittedAt: submittedAt,
      provincialDfoReceivedAt: provincialDfoReceivedAt,
      lastChecked: DateTime(2026, 9, 5, 10, 30),
    );
  }

  Widget wrap(SapsApplication app) {
    final firestore = FakeFirebaseFirestore();
    return MaterialApp(
      home: Scaffold(
        body: SapsApplicationCard(
          application: app,
          trackerService: SapsTrackerService.forTesting(firestore),
        ),
      ),
    );
  }

  testWidgets('shows the submission date prominently on the card',
      (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(submittedAt: DateTime(2026, 9, 1))),
    );

    expect(find.text('Submitted: 1 Sep 2026'), findsOneWidget);
  });

  testWidgets('shows firearm calibre + serial pills on the collapsed card',
      (tester) async {
    await tester.pumpWidget(wrap(buildApp()));

    expect(find.text('6MM MUSGRAVE'), findsOneWidget);
    expect(find.text('s/n OB14468'), findsOneWidget);
  });

  testWidgets('shows working-day tallies for both milestones', (tester) async {
    // Milestones well in the past (the card tallies against DateTime.now(),
    // which is always after these) so the pills render deterministically.
    final app = buildApp(
      submittedAt: DateTime(2026, 6, 1),
      provincialDfoReceivedAt: DateTime(2026, 6, 8),
    );
    await tester.pumpWidget(wrap(app));

    expect(find.textContaining('workdays since submission'), findsOneWidget);
    expect(find.textContaining('workdays at provincial DFO'), findsOneWidget);
  });

  testWidgets('hides the firearm pills when calibre + serial are unknown',
      (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(calibre: '', serialNumber: '')),
    );

    expect(find.text('6MM MUSGRAVE'), findsNothing);
    expect(find.text('s/n OB14468'), findsNothing);
  });
}
