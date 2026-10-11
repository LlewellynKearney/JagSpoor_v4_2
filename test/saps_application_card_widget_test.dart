import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jagspoor/features/ballistics/data/models/saps_application_model.dart';
import 'package:jagspoor/features/hunter_mode/presentation/saps_tracker_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_cfr_scraper_client.dart';
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
    String rawStatus = '',
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
      rawStatus: rawStatus,
      submittedAt: submittedAt,
      createdAt: createdAt,
      provincialDfoReceivedAt: provincialDfoReceivedAt,
      lastChecked: DateTime(2026, 9, 5, 10, 30),
    );
  }

  Widget wrap(
    SapsApplication app, {
    FakeFirebaseFirestore? firestore,
    SapsCfrScraperClient Function()? enquiryClientFactory,
  }) {
    final fs = firestore ?? FakeFirebaseFirestore();
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SapsApplicationCard(
            application: app,
            trackerService: SapsTrackerService.forTesting(fs),
            enquiryClientFactory: enquiryClientFactory,
          ),
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

    // Expanded: the FIREARM DETAILS section shows explicit labelled rows for
    // serial / calibre / make / type / app no.
    expect(find.text('FIREARM DETAILS'), findsOneWidget);
    expect(find.text('Make'), findsOneWidget);
    expect(find.text('Calibre'), findsOneWidget);
    expect(find.text('s/n'), findsOneWidget);
    expect(find.text('App No'), findsOneWidget);
    expect(find.text('TIKKA T3X'), findsWidgets);
    expect(find.text('6MM MUSGRAVE'), findsWidgets);
    expect(find.text('OB14468'), findsWidgets);
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

  testWidgets('renders the LIVE payload: At Central Registry + SAPS status '
      'date + firearm details + raw response', (tester) async {
    final app = SapsApplication(
      id: 'app-2',
      hunterId: 'hunter-1',
      referenceNumber: '10654672',
      idNumber: '9001015009087',
      applicationType: 'Section 16 Dedicated Hunting',
      currentStatus: 'At Central Registry',
      firearmMake: 'HOWA',
      calibre: '.338 WIN MAG',
      serialNumber: 'F004574',
      rawStatus: 'IN PREPARATION FOR CONSIDERATION',
      liveStage: 2,
      statusDate: '2026/10/09',
      statusDescription: 'No status available contact the DFO',
      nextStep: 'No status available contact the DFO',
      rawPayload: const {
        'applicationNumber': '10654672',
        'calibre': '.338 WIN MAG',
        'make': 'HOWA',
        'serialNumber': 'F004574',
        'statusDate': '2026/10/09',
        'status': 'IN PREPARATION FOR CONSIDERATION',
      },
      lastChecked: DateTime(2026, 10, 11, 7, 11),
    );
    await tester.pumpWidget(wrap(app));

    // Collapsed: progress badge + SAPS status date + next-step indicator.
    expect(find.text('At Central Registry'), findsWidgets);
    expect(find.textContaining('SAPS Status Date:'), findsOneWidget);
    // Stage 2 -> next step is the stage-derived CFR next step.
    expect(find.text('Next: Printed / Ready for Collection'), findsOneWidget);

    await tester.tap(find.text('Section 16 Dedicated Hunting'));
    await tester.pumpAndSettle();

    // Expanded: labelled firearm rows + raw SAPS response section.
    expect(find.text('FIREARM DETAILS'), findsOneWidget);
    expect(find.text('HOWA'), findsWidgets);
    expect(find.text('.338 WIN MAG'), findsWidgets);
    expect(find.text('F004574'), findsWidgets);
    expect(find.text('RAW SAPS RESPONSE'), findsOneWidget);
  });

  testWidgets('edit + delete actions render on the card header',
      (tester) async {
    await tester.pumpWidget(wrap(buildApp()));
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('delete confirms then shows a Deleted snackbar with undo',
      (tester) async {
    final fs = FakeFirebaseFirestore();
    await fs.collection('license_applications').doc('app-1').set({
      'hunterId': 'hunter-1',
      'referenceNumber': '10470664',
      'serialNumber': 'OB14468',
    });
    await tester.pumpWidget(wrap(buildApp(), firestore: fs));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // Confirmation dialog.
    expect(find.text('Delete application?'), findsOneWidget);
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Deleted'), findsOneWidget);
    expect(find.text('UNDO'), findsOneWidget);
    // The document is gone from Firestore.
    final doc = await fs.collection('license_applications').doc('app-1').get();
    expect(doc.exists, isFalse);
  });

  testWidgets('the approved card shows the Add-to-Safe action',
      (tester) async {
    await tester.pumpWidget(
      wrap(buildApp(status: 'Approved')),
    );
    expect(find.text('Add to Digital Firearm Safe'), findsOneWidget);
  });

  testWidgets('edit re-runs the live enquiry and persists the corrected '
      'serial + live status', (tester) async {
    const resultsHtml =
        '<b>Search Results:</b><table>'
        '<tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>'
        '<td>9001015009087</td><td>.338 WIN MAG</td><td>HOWA</td>'
        '<td>F004574</td><td>2026/10/09</td>'
        '<td>Received at Licensing Section</td>'
        '<td>For consideration by the Commissioner</td>'
        '<td>Await decision</td></tr></table>';
    final mock = MockClient((_) async => http.Response(resultsHtml, 200));
    final fs = FakeFirebaseFirestore();
    // Start the card with the typo'd serial (F0004574) that produced the
    // stale "no records" result; the edit corrects it to F004574.
    await fs.collection('license_applications').doc('app-1').set({
      'hunterId': 'hunter-1',
      'referenceNumber': '10654672',
      'serialNumber': 'F0004574',
    });
    final app = SapsApplication(
      id: 'app-1',
      hunterId: 'hunter-1',
      referenceNumber: '10654672',
      idNumber: '9001015009087',
      applicationType: 'Section 16 Dedicated Hunting',
      currentStatus: 'Application received at DFO',
      serialNumber: 'F0004574',
      lastChecked: DateTime(2026, 10, 11),
    );
    await tester.pumpWidget(wrap(
      app,
      firestore: fs,
      enquiryClientFactory: () => SapsCfrScraperClient(httpClient: mock),
    ));

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    // Correct the serial in the edit dialog, then save.
    await tester.enterText(
      find.widgetWithText(TextField, 'Firearm Serial Number'),
      'F004574',
    );
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    // The doc now carries the corrected serial + the live classified status.
    final data =
        (await fs.collection('license_applications').doc('app-1').get())
            .data()!;
    expect(data['serialNumber'], 'F004574');
    expect(data['liveStage'], 2);
    expect(data['statusDate'], '2026/10/09');
    expect('${data['rawStatus']}', contains('For consideration'));
  });
}
