import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/presentation/saps_tracker_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Expands the collapsible "Register New Application" accordion so the
  /// registration form (SMS paste box + fields) is mounted and reachable,
  /// then scrolls the extraction button into view (the expanded form is tall
  /// and its SMS Quick Add box may sit below the fold on the test viewport).
  Future<void> expandRegisterAccordion(WidgetTester tester) async {
    await tester.tap(find.text('Register New Application'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Extract Details from SMS'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the collapsible Register New Application accordion '
      'collapsed by default + refresh button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SapsTrackerScreen(),
      ),
    );

    // The slick accordion header is always visible.
    expect(find.text('Register New Application'), findsOneWidget);

    // The registration body is COLLAPSED by default: the SMS paste box and
    // its extraction button are NOT mounted until the header is expanded.
    expect(
      find.widgetWithText(TextField, 'Paste SAPS Notification SMS'),
      findsNothing,
    );
    expect(find.text('Extract Details from SMS'), findsNothing);

    // The manual refresh action is present.
    expect(find.byIcon(Icons.refresh), findsWidgets);

    // Expanding the accordion mounts the prominent "Paste SAPS SMS / Quick
    // Add" box at the top of the registration view.
    await expandRegisterAccordion(tester);
    expect(find.text('Paste SAPS SMS / Quick Add'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Paste SAPS Notification SMS'),
      findsOneWidget,
    );
    expect(find.text('Extract Details from SMS'), findsOneWidget);
  });

  testWidgets('parsing a pasted SAPS SMS pre-populates the form fields',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SapsTrackerScreen(),
      ),
    );
    await expandRegisterAccordion(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Paste SAPS Notification SMS'),
      'SAPS msg: Application Ref. 10470664 make TIKKA T3X for calibre '
      '6MM MUSGRAVE s/n OB14468',
    );
    await tester.tap(find.text('Extract Details from SMS'));
    await tester.pumpAndSettle();

    // The reference / make / calibre / serial fields are pre-populated.
    final refField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Application Reference Code'),
    );
    expect(refField.controller!.text, '10470664');

    final makeField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Firearm Make / Brand'),
    );
    expect(makeField.controller!.text, 'TIKKA T3X');

    final calibreField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Calibre'),
    );
    expect(calibreField.controller!.text, '6MM MUSGRAVE');

    final serialField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Serial Number'),
    );
    expect(serialField.controller!.text, 'OB14468');

    // A confirmation snackbar summarises the extracted details (+ make).
    expect(find.textContaining('Details found'), findsWidgets);
    expect(find.textContaining('Make: TIKKA T3X'), findsWidgets);
  });

  testWidgets('parsing a blank SMS shows an error snackbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SapsTrackerScreen(),
      ),
    );
    await expandRegisterAccordion(tester);

    await tester.tap(find.text('Extract Details from SMS'));
    await tester.pump();

    expect(
      find.textContaining('Paste a SAPS notification SMS first'),
      findsOneWidget,
    );
  });

  testWidgets('register form exposes the firearm make field', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SapsTrackerScreen(),
      ),
    );
    await expandRegisterAccordion(tester);

    // The new Firearm Make / Brand input renders alongside calibre + serial.
    final makeField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Firearm Make / Brand'),
    );
    expect(makeField, isNotNull);
    expect(
      find.widgetWithText(TextField, 'Calibre'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'Serial Number'),
      findsOneWidget,
    );
    // And the register CTA is present once expanded.
    expect(find.text('Register Application for Tracking'), findsOneWidget);
  });
}