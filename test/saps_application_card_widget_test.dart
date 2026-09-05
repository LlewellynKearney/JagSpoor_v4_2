import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/ballistics/data/models/saps_application_model.dart';
import 'package:jagspoor/features/hunter_mode/presentation/saps_tracker_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_tracker_service.dart';
import 'package:jagspoor/features/shared/widgets/hunter_media_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SapsApplication buildApp({
    DateTime? submittedAt,
    DateTime? createdAt,
    DateTime? provincialDfoReceivedAt,
    String firearmMake = 'TIKKA T3X',
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
      firearmMake: firearmMake,
      calibre: calibre,
      serialNumber: serialNumber,
      submittedAt: submittedAt,
      createdAt: createdAt,
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

  testWidgets('falls back to the record creation date when submittedAt is '
      'missing', (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(createdAt: DateTime(2026, 8, 20))),
    );

    expect(find.text('Submitted: 20 Aug 2026 (record created)'),
        findsOneWidget);
  });

  testWidgets('shows the next anticipated status indicator', (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(status: 'Provincial')),
    );

    expect(find.text('Next: CFR'), findsOneWidget);
  });

  testWidgets('shows the plain-language current status description',
      (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(status: 'Provincial')),
    );

    expect(
      find.textContaining('Provincial Firearms Office'),
      findsOneWidget,
    );
  });

  testWidgets('shows firearm make + calibre + serial pills on the collapsed '
      'card', (tester) async {
    await tester.pumpWidget(wrap(buildApp()));

    // The collapsed pill band renders each firearm attribute as a distinct
    // HunterDataPill (the expanded section keeps its own offstage copies, so
    // anchor the assertions to pill descendants of the collapsed band).
    expect(
      find.descendant(
        of: find.byType(HunterDataPill),
        matching: find.text('TIKKA T3X'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HunterDataPill),
        matching: find.text('6MM MUSGRAVE'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HunterDataPill),
        matching: find.text('s/n OB14468'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hides the firearm pills when make + calibre + serial are '
      'unknown', (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(firearmMake: '', calibre: '', serialNumber: '')),
    );

    expect(
      find.descendant(
        of: find.byType(HunterDataPill),
        matching: find.text('TIKKA T3X'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(HunterDataPill),
        matching: find.text('6MM MUSGRAVE'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(HunterDataPill),
        matching: find.text('s/n OB14468'),
      ),
      findsNothing,
    );
  });

  testWidgets('shows firearm details section on the expanded card',
      (tester) async {
    await tester.pumpWidget(wrap(buildApp()));
    await tester.tap(find.text('Section 16 Dedicated Hunting'));
    await tester.pumpAndSettle();

    // Expanded: the FIREARM DETAILS section shows the composed firearm label
    // plus the individual make / calibre / serial chips (each chip also keeps
    // its collapsed-pill copy, so findsWidgets rather than findsOneWidget).
    expect(find.text('FIREARM DETAILS'), findsOneWidget);
    expect(
      find.text('TIKKA T3X • 6MM MUSGRAVE • s/n OB14468'),
      findsOneWidget,
    );
    expect(find.text('TIKKA T3X'), findsWidgets);
    expect(find.text('6MM MUSGRAVE'), findsWidgets);
    expect(find.text('s/n OB14468'), findsWidgets);
  });

  testWidgets('firearm details section degrades gracefully when all firearm '
      'fields are omitted (e.g. Competency Certificate)', (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(firearmMake: '', calibre: '', serialNumber: '')),
    );
    await tester.tap(find.text('Section 16 Dedicated Hunting'));
    await tester.pumpAndSettle();

    // Expanded: the FIREARM DETAILS section renders the composed label only
    // (which falls back to "Firearm not specified") and no empty chips.
    expect(find.text('FIREARM DETAILS'), findsOneWidget);
    expect(find.text('Firearm not specified'), findsOneWidget);
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
}
