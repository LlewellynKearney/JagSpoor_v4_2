import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/widgets/force_update_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required String message,
    VoidCallback? onUpdatePressed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showForceUpdateDialog(
                  context,
                  message: message,
                  onUpdatePressed: onUpdatePressed,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the blocking title, server message and UPDATE NOW',
      (tester) async {
    await pumpDialog(
      tester,
      message: 'A critical update is required. Please update to continue.',
    );

    expect(find.text('Update Required'), findsOneWidget);
    expect(
      find.text('A critical update is required. Please update to continue.'),
      findsOneWidget,
    );
    expect(find.text('UPDATE NOW'), findsOneWidget);
  });

  testWidgets('has no dismissive action (no Later / Cancel)', (tester) async {
    await pumpDialog(tester, message: 'Please update.');

    expect(find.text('Later'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('tapping the barrier does NOT dismiss the dialog',
      (tester) async {
    await pumpDialog(tester, message: 'Please update.');

    // Tap in the top-left corner, well outside the centred dialog.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Update Required'), findsOneWidget);
  });

  testWidgets('UPDATE NOW invokes the injected update action', (tester) async {
    var pressed = 0;
    await pumpDialog(
      tester,
      message: 'Please update.',
      onUpdatePressed: () => pressed++,
    );

    await tester.tap(find.text('UPDATE NOW'));
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('ForceUpdateDialog.fromDecision renders the decision message',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ForceUpdateDialog(
            message: 'Server-authored kill-switch copy.',
          ),
        ),
      ),
    );

    expect(find.text('Server-authored kill-switch copy.'), findsOneWidget);
    expect(find.text('UPDATE NOW'), findsOneWidget);
  });
}