import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/auth/auth_screen.dart';

/// Widget tests for the login screen's credential-autofill integration
/// (Task 1): the email + password fields must live inside an `AutofillGroup`
/// and carry the correct `AutofillHints` so Android Credential Manager /
/// iOS Keychain can fill and save the credentials.
void main() {
  Widget buildScreen() {
    return MaterialApp(
      home: AuthScreen(themedata: ThemeController()),
    );
  }

  group('Login screen autofill integration', () {
    testWidgets('email + password fields are wrapped in an AutofillGroup', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      expect(find.byType(AutofillGroup), findsOneWidget);
      // Both credential fields are descendants of the AutofillGroup.
      expect(
        find.descendant(
          of: find.byType(AutofillGroup),
          matching: find.byKey(const ValueKey('loginEmailField')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AutofillGroup),
          matching: find.byKey(const ValueKey('loginPasswordField')),
        ),
        findsOneWidget,
      );
    });

    /// Reads the inner [TextField] of the keyed [TextFormField] (the hints
    /// and keyboard type live on the inner field, not the form wrapper).
    TextField innerTextField(WidgetTester tester, Key key) {
      return tester.widget<TextField>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(TextField),
        ),
      );
    }

    testWidgets('email field exposes email + username autofill hints', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      final field = innerTextField(
        tester,
        const ValueKey('loginEmailField'),
      );
      expect(field.autofillHints, isNotNull);
      expect(field.autofillHints, contains(AutofillHints.email));
      expect(field.autofillHints, contains(AutofillHints.username));
      expect(field.keyboardType, TextInputType.emailAddress);
    });

    testWidgets('password field exposes the password hint in login mode', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      final field = innerTextField(
        tester,
        const ValueKey('loginPasswordField'),
      );
      expect(field.autofillHints, equals(const [AutofillHints.password]));
    });

    testWidgets(
      'password field exposes the newPassword hint in registration mode',
      (tester) async {
        await tester.pumpWidget(buildScreen());
        await tester.pump();

        // Flip to registration mode (the switch button sits below the fold
        // on the 800x600 test surface, so scroll it into view first).
        await tester.ensureVisible(find.text('SWITCH TO REGISTRATION'));
        await tester.pump();
        await tester.tap(find.text('SWITCH TO REGISTRATION'));
        await tester.pump();

        final field = innerTextField(
          tester,
          const ValueKey('loginPasswordField'),
        );
        expect(field.autofillHints, equals(const [AutofillHints.newPassword]));
      },
    );
  });

  group('finishAutofillContext structural contract', () {
    test('successful sign-in commits the autofill context', () {
      final source = File('lib/features/auth/auth_screen.dart').readAsStringSync();
      // The sign-in success path calls the prompter after
      // signInWithEmailAndPassword.
      final signInIdx = source.indexOf('signInWithEmailAndPassword(');
      final promptIdx = source.indexOf(
        'AutofillCredentialPrompter.promptSaveCredentials()',
      );
      expect(signInIdx, greaterThan(-1));
      expect(promptIdx, greaterThan(signInIdx));
    });

    test('successful registration commits the autofill context', () {
      final source = File('lib/features/auth/auth_screen.dart').readAsStringSync();
      final registerIdx = source.indexOf('createUserWithEmailAndPassword(');
      expect(registerIdx, greaterThan(-1));
      // Two prompt call sites: one for sign-in, one for registration.
      final prompts = 'AutofillCredentialPrompter.promptSaveCredentials()'
          .allMatches(source)
          .length;
      expect(prompts, 2);
    });

    test('the prompter invokes TextInput.finishAutofillContext', () {
      final source = File(
        'lib/features/auth/services/autofill_credential_prompter.dart',
      ).readAsStringSync();
      expect(source, contains('TextInput.finishAutofillContext()'));
      expect(
        source,
        contains("static const String finishMethod = "
            "'TextInput.finishAutofillContext'"),
      );
    });
  });
}
