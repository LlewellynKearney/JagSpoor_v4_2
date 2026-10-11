import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jagspoor/features/hunter_mode/presentation/saps_tracker_screen.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_cfr_scraper_client.dart';

/// Builds a tracker screen whose ENQUIRE action is backed by a mocked
/// transport, so the live result-card states can be exercised with no network.
Widget buildScreen(String html, {bool json = false}) {
  final mock = MockClient((request) async {
    if (json) {
      return http.Response(html, 200, headers: {
        'content-type': 'application/json',
      });
    }
    return http.Response(html, 200);
  });
  return MaterialApp(
    home: SapsTrackerScreen(
      enquiryClientFactory: () => SapsCfrScraperClient(httpClient: mock),
    ),
  );
}

Future<void> enquire(WidgetTester tester, String ref, String serial) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Reference Number'),
    ref,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Firearm Serial Number'),
    serial,
  );
  await tester.tap(find.text('ENQUIRE'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const resultsHtml =
      '<b>Search Results:</b><table>'
      '<tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>'
      '<td>9001015009087</td><td>.338 WIN MAG</td><td>HOWA</td>'
      '<td>F004574</td><td>2026/10/09</td>'
      '<td>Received at Licensing Section</td>'
      '<td>For consideration by the Commissioner</td>'
      '<td>Await decision</td></tr></table>';

  testWidgets('renders the live enquiry panel (ref + serial + hint)',
      (tester) async {
    await tester.pumpWidget(buildScreen(resultsHtml));

    expect(find.text('CHECK LIVE STATUS'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Reference Number'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Firearm Serial Number'),
        findsOneWidget);
    expect(
      find.textContaining('For firearm renewal: enter BOTH Ref + Serial'),
      findsOneWidget,
    );
    expect(find.text('ENQUIRE'), findsOneWidget);
  });

  testWidgets('renders the full result card for a stage>=0 enquiry',
      (tester) async {
    await tester.pumpWidget(buildScreen(resultsHtml));
    await enquire(tester, '10654672', 'F004574');

    expect(find.text('RESULT'), findsOneWidget);
    expect(find.text('STAGE'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('APP NO'), findsOneWidget);
    expect(find.text('10654672'), findsWidgets);
    expect(find.text('CALIBRE'), findsOneWidget);
    expect(find.text('.338 WIN MAG'), findsWidgets);
    expect(find.text('MAKE'), findsOneWidget);
    expect(find.text('HOWA'), findsWidgets);
    expect(find.text('SERIAL'), findsOneWidget);
    expect(find.text('F004574'), findsWidgets);
    expect(find.text('STATUS DATE'), findsOneWidget);
    expect(find.text('2026/10/09'), findsWidgets);
    // The raw "Received at Licensing Section / For consideration…" phrase
    // classifies to the CFR stage -> label "At Central Registry".
    expect(find.text('At Central Registry'), findsWidgets);
    // NOT an approved status -> no Add-to-Safe button.
    expect(find.text('Add to Digital Firearm Safe'), findsNothing);
  });

  testWidgets('the Add-to-Safe button appears for an approved status',
      (tester) async {
    const approvedHtml =
        '<b>Search Results:</b><table>'
        '<tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>'
        '<td>9001015009087</td><td>.338 WIN MAG</td><td>HOWA</td>'
        '<td>F004574</td><td>2026/10/09</td>'
        '<td>Approved</td><td>Licence approved and printed</td>'
        '<td>Collect at police station</td></tr></table>';
    await tester.pumpWidget(buildScreen(approvedHtml));
    await enquire(tester, '10654672', 'F004574');

    expect(find.text('Add to Digital Firearm Safe'), findsOneWidget);
    expect(find.byIcon(Icons.shield), findsOneWidget);
  });

  testWidgets('renders the NOT FOUND card + portal snippet', (tester) async {
    const notFoundHtml =
        '<i>The data on this page were updated on <b>2026-10-10</b>.</i>'
        '<table><tr><td colspan="9">No records to retrieve for your '
        'selected Reference Number (10470664) and Serial Number '
        '(OB14468) ...</td></tr></table>';
    await tester.pumpWidget(buildScreen(notFoundHtml));
    await enquire(tester, '10470664', 'OB14468');

    expect(
      find.textContaining('No records to retrieve for your selected'),
      findsOneWidget,
    );
    expect(
      find.textContaining('PORTAL HTML SNIPPET'),
      findsOneWidget,
    );
  });

  testWidgets('renders the amber NEED_SERIAL_AND_REF banner', (tester) async {
    const needSerialHtml =
        '<input type="hidden" name="csrf" value="tok">'
        '<div>Please supply a Serial Number AND Reference Number</div>';
    await tester.pumpWidget(buildScreen(needSerialHtml));
    await enquire(tester, '10654672', '');

    expect(
      find.textContaining('Enter both Serial + Reference for firearm apps'),
      findsOneWidget,
    );
  });

  testWidgets('shows an error when both enquiry fields are empty',
      (tester) async {
    await tester.pumpWidget(buildScreen(resultsHtml));
    await tester.tap(find.text('ENQUIRE'));
    await tester.pump();

    expect(
      find.textContaining('Enter a Reference Number'),
      findsOneWidget,
    );
  });
}
