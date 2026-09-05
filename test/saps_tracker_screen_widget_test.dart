import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/presentation/saps_tracker_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the SMS paste block + refresh button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SapsTrackerScreen(),
      ),
    );

    // The SMS paste field and its extraction button are present.
    expect(
      find.widgetWithText(TextField, 'Paste SAPS Notification SMS'),
      findsWidgets,
    );
    expect(find.text('Extract Details from SMS'), findsOneWidget);
    // The manual refresh action is present.
    expect(find.byIcon(Icons.refresh), findsWidgets);
  });

  testWidgets('parsing a pasted SAPS SMS pre-populates the form fields',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SapsTrackerScreen(),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Paste SAPS Notification SMS'),
      'SAPS msg: Application Ref. 10470664 for calibre 6MM MUSGRAVE '
      's/n OB14468',
    );
    await tester.tap(find.text('Extract Details from SMS'));
    await tester.pumpAndSettle();

    // The reference / calibre / serial fields are pre-populated from the SMS.
    final refField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Application Reference Code'),
    );
    expect(refField.controller!.text, '10470664');

    final calibreField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Calibre'),
    );
    expect(calibreField.controller!.text, '6MM MUSGRAVE');

    final serialField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Serial Number'),
    );
    expect(serialField.controller!.text, 'OB14468');

    // A confirmation snackbar summarises the extracted details.
    expect(find.textContaining('Details found'), findsWidgets);
  });

  testWidgets('parsing a blank SMS shows an error snackbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SapsTrackerScreen(),
      ),
    );

    await tester.tap(find.text('Extract Details from SMS'));
    await tester.pump();

    expect(
      find.textContaining('Paste a SAPS notification SMS first'),
      findsOneWidget,
    );
  });
}