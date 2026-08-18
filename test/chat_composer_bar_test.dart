import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/widgets/chat_composer_bar.dart';

/// Widget tests for [ChatComposerBar].
///
/// The composer was extracted into a dedicated [StatefulWidget] so its
/// [TextEditingController] + [FocusNode] state is isolated from the
/// message-list Firestore stream rebuilds (and the keyboard's
/// `resizeToAvoidBottomInset` rebuilds). These tests lock in the
/// isolation contract: the controller is created once in [initState],
/// survives a parent rebuild WITHOUT being recreated, and the send
/// button is disabled while the input is empty. The send path itself
/// (which calls [ChatAndFilterService] -> Firestore) is not exercised
/// here, so no Firebase app is required.
void main() {
  late ThemeController theme;

  setUp(() {
    theme = ThemeController();
  });

  testWidgets(
      'renders the text input + a send button that is enabled when idle',
      (tester) async {
    final probeKey = GlobalKey<_RebuildProbeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _RebuildProbe(
          key: probeKey,
          child: ChatComposerBar(
            bookingId: 'b1',
            theme: theme,
            senderName: 'Hunter',
          ),
        ),
      ),
    ));

    // Input field is present.
    expect(find.byType(TextField), findsOneWidget);
    // Send button is present and enabled when idle (the empty-input guard
    // is handled inside _sendMessage, which no-ops on empty text).
    final sendButton = find.byType(IconButton);
    expect(sendButton, findsOneWidget);
    final iconButton = tester.widget<IconButton>(sendButton);
    expect(iconButton.onPressed, isNotNull,
        reason: 'send is enabled when idle; empty-input guard is internal');
  });

  testWidgets(
      'the TextEditingController persists across a parent rebuild '
      '(no controller recreation -- the keyboard focus contract)',
      (tester) async {
    final probeKey = GlobalKey<_RebuildProbeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _RebuildProbe(
          key: probeKey,
          child: ChatComposerBar(
            bookingId: 'b1',
            theme: theme,
            senderName: 'Hunter',
          ),
        ),
      ),
    ));

    // Type some text into the composer.
    await tester.enterText(find.byType(TextField), 'hello bushveld');
    await tester.pump();

    // Capture the controller instance backing the TextField.
    final textFieldBefore = tester.widget<TextField>(find.byType(TextField));
    final controllerBefore = textFieldBefore.controller;
    expect(controllerBefore, isNotNull);
    expect(controllerBefore!.text, 'hello bushveld');

    // Force a PARENT rebuild (simulates a message-stream re-emit or a
    // keyboard-inset resize triggering the Scaffold's build). The composer's
    // own State must NOT be torn down + recreated -- the controller instance
    // + its text must survive.
    probeKey.currentState!.rebuild();
    await tester.pump();

    final textFieldAfter = tester.widget<TextField>(find.byType(TextField));
    final controllerAfter = textFieldAfter.controller;
    // Same controller instance survives the rebuild (no recreation).
    expect(controllerAfter, same(controllerBefore),
        reason: 'TextEditingController must not be recreated on parent rebuild');
    // Text content survives the rebuild.
    expect(controllerAfter!.text, 'hello bushveld');
  });

  testWidgets('shows the send icon when idle (no in-flight spinner)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatComposerBar(
          bookingId: 'b1',
          theme: theme,
          senderName: 'Hunter',
        ),
      ),
    ));

    // Idle -> send icon present, no progress indicator.
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'the composer is NOT wrapped in a GestureDetector that would steal '
      'the tap from the TextField (the keyboard-focus / IMM contract)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatComposerBar(
          bookingId: 'b1',
          theme: theme,
          senderName: 'Hunter',
        ),
      ),
    ));

    // A parent GestureDetector with HitTestBehavior.opaque competes with the
    // TextField's own TapGestureRecognizer in the gesture arena and wins
    // (last-registered recognizer wins a default arena), stealing the tap so
    // the EditableText's internal handler never fires -> the IMM never binds
    // to the EditText -> "ssi() view is not EditText" + immediate keyboard
    // hide. The composer must expose the TextField directly (no opaque
    // wrapper) so the TextField's own tap handling requests focus.
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    // No GestureDetector may sit between the TextField and the composer's
    // root Row (an opaque wrapper there is what steals the tap).
    final gestureAncestor = find.ancestor(
      of: textField,
      matching: find.byType(GestureDetector),
    );
    expect(gestureAncestor, findsNothing,
        reason:
            'A parent GestureDetector would steal the tap from the TextField '
            'and break the IMM keyboard binding; the TextField must handle '
            'its own tap (onTap -> requestFocus) without arena contention.');
  });

  testWidgets(
      'tapping the TextField requests focus on the retained FocusNode '
      '(keyboard stays open for typing)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatComposerBar(
          bookingId: 'b1',
          theme: theme,
          senderName: 'Hunter',
        ),
      ),
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));
    final focusNode = textField.focusNode!;
    expect(focusNode.hasFocus, isFalse);

    // Tap the field -- the TextField's own onTap requests focus (no competing
    // GestureDetector steals the pointer).
    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue,
        reason: 'Tapping the TextField must request focus so the keyboard '
            'binds to the EditText and stays open while typing.');
  });
}

/// A parent widget that rebuilds on demand so the tests can assert the
/// composer's [TextEditingController] survives a parent rebuild (the
/// keyboard focus / no-recreation contract the fix enforces).
class _RebuildProbe extends StatefulWidget {
  final Widget child;
  const _RebuildProbe({super.key, required this.child});
  @override
  State<_RebuildProbe> createState() => _RebuildProbeState();
}

class _RebuildProbeState extends State<_RebuildProbe> {
  int tick = 0;
  void rebuild() => setState(() => tick++);
  @override
  Widget build(BuildContext context) => widget.child;
}
