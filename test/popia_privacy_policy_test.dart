import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/auth/screens/privacy_policy_screen.dart';
import 'package:jagspoor/features/legal/popia_registration.dart';
import 'package:jagspoor/features/legal/sensitive_personal_information.dart';

/// POPIA compliance contract tests.
///
/// Two groups:
///  1. The published policy content — the registration particulars of the
///     Information Regulator certificate MUST appear verbatim, and every
///     mandatory POPIA s.18 disclosure element must be present.
///  2. The data-handling contract — the POPIA s.26 special personal
///     information fields must be classified as sensitive and must NOT be
///     readable by other signed-in users (rules + client split).
void main() {
  group('PopiaRegistration particulars (Information Regulator certificate)', () {
    test('carries the registered organisation + registration number', () {
      expect(PopiaRegistration.organisationName,
          'JAGSPOOR VELD AND VENTURES');
      expect(PopiaRegistration.registrationNumber, '2026-066026');
      expect(PopiaRegistration.registrationDate, '2026-09-05');
      expect(PopiaRegistration.companyRegistrationNumber, '2026/675772/07');
      expect(PopiaRegistration.issuingAuthority,
          'Information Regulator (South Africa)');
    });

    test('names the appointed Information Officer', () {
      expect(PopiaRegistration.informationOfficerName,
          'Donald Llewelyn Kearney');
      expect(PopiaRegistration.informationOfficerAppointed, '2026-09-01');
    });

    test('exposes the Information Regulator complaint channels', () {
      expect(PopiaRegistration.regulatorWebsite,
          'https://inforegulator.org.za');
      expect(PopiaRegistration.regulatorComplaintsEmail,
          'complaints@inforegulator.org.za');
      expect(PopiaRegistration.regulatorPhone, isNotEmpty);
      expect(PopiaRegistration.regulatorAddress, isNotEmpty);
    });

    test('exposes the Information Officer contact address', () {
      expect(PopiaRegistration.privacyEmail, contains('@jag-spoor.co.za'));
      expect(PopiaRegistration.supportEmail, contains('@jag-spoor.co.za'));
    });

    test('registrationSummary includes the number + date', () {
      final s = PopiaRegistration.registrationSummary;
      expect(s, contains('2026-066026'));
      expect(s, contains('2026-09-05'));
      expect(s, contains('JAGSPOOR VELD AND VENTURES'));
    });
  });

  group('SensitivePersonalInformation classification (POPIA s.26)', () {
    test('health / ID / firearm fields are classified sensitive', () {
      for (final f in const [
        'bloodType',
        'allergies',
        'medicalAid',
        'emergencyContact',
        'idNumber',
        'hunterStatus',
        'provincialPermits',
      ]) {
        expect(SensitivePersonalInformation.isSensitive(f), isTrue,
            reason: '$f must be treated as special personal information');
      }
    });

    test('ordinary account-directory fields are NOT sensitive', () {
      for (final f in const [
        'firstName',
        'lastName',
        'phone',
        'email',
        'farmName',
        'role',
        'profileImageUrl',
      ]) {
        expect(SensitivePersonalInformation.isSensitive(f), isFalse,
            reason: '$f is required for cross-user booking contact');
      }
    });

    test('extract() selects only the sensitive subset', () {
      final extracted = SensitivePersonalInformation.extract({
        'firstName': 'Jan',
        'idNumber': '8501015009087',
        'bloodType': 'O+',
        'allergies': 'Penicillin',
      });
      expect(extracted.keys, unorderedEquals(['idNumber', 'bloodType', 'allergies']));
      expect(extracted.containsKey('firstName'), isFalse);
    });

    test('redact() strips every sensitive field', () {
      final redacted = SensitivePersonalInformation.redact({
        'firstName': 'Jan',
        'idNumber': '8501015009087',
        'bloodType': 'O+',
        'allergies': 'Penicillin',
        'medicalAid': 'Discovery',
        'emergencyContact': '082 000 0000',
        'provincialPermits': 'GP-123',
        'hunterStatus': 'Dedicated',
      });
      expect(redacted, {'firstName': 'Jan'});
      for (final f in SensitivePersonalInformation.allSensitiveFields) {
        expect(redacted.containsKey(f), isFalse, reason: '$f leaked');
      }
    });

    test('private profile path is owner-scoped under users/{uid}', () {
      expect(SensitivePersonalInformation.privateProfilePath('abc'),
          'users/abc/private/profile');
    });
  });

  group('Privacy policy screen content (POPIA s.18 disclosure)', () {
    Future<void> pumpPolicy(WidgetTester tester,
        {bool acceptance = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyPolicyScreen(showAcceptanceFooter: acceptance),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Renders the whole screen into one searchable string so multi-line
    /// section bodies can be asserted without depending on wrapping.
    String renderedText(WidgetTester tester) {
      final widgets = tester.widgetList<Text>(find.byType(Text));
      return widgets.map((t) => t.data ?? '').join('\n');
    }

    testWidgets('states the organisation, registration number and officer',
        (tester) async {
      await pumpPolicy(tester);
      final txt = renderedText(tester);
      expect(txt, contains('JAGSPOOR VELD AND VENTURES'));
      expect(txt, contains('2026-066026'));
      expect(txt, contains('Donald Llewelyn Kearney'));
      expect(txt, contains(PopiaRegistration.privacyEmail));
    });

    testWidgets('discloses the categories of personal information collected',
        (tester) async {
      await pumpPolicy(tester);
      final txt = renderedText(tester);
      // Identity / contact / health / location / hunting / device data
      expect(txt, contains('PERSONAL INFORMATION WE COLLECT'));
      expect(txt, contains('South African ID / passport number'));
      expect(txt, contains('Blood type'));
      expect(txt, contains('allergies'));
      expect(txt, contains('Medical-aid details'));
      expect(txt, contains('GPS coordinates'));
      expect(txt, contains('Firebase Cloud Messaging'));
      expect(txt, contains('Farm name'));
      expect(txt, contains('Trophy records'));
    });

    testWidgets('discloses the lawful purpose for processing', (tester) async {
      await pumpPolicy(tester);
      final txt = renderedText(tester);
      expect(txt, contains('WHY WE PROCESS IT (LAWFUL PURPOSE)'));
      expect(txt, contains('Performance of a Contract'));
      expect(txt, contains('Compliance with a Legal Obligation'));
      expect(txt, contains('Explicit Consent'));
      expect(txt, contains('Legitimate Interest'));
    });

    testWidgets('discloses retention, rights, security, cross-border, '
        'cookies and FCM', (tester) async {
      await pumpPolicy(tester);
      final txt = renderedText(tester);
      expect(txt, contains('HOW LONG WE KEEP IT (RETENTION)'));
      expect(txt, contains('YOUR RIGHTS UNDER POPIA'));
      expect(txt, contains('Right of Access'));
      expect(txt, contains('Right to Correction'));
      expect(txt, contains('Right to Deletion'));
      expect(txt, contains('Right to Object'));
      expect(txt, contains('SECURITY SAFEGUARDS'));
      expect(txt, contains('CROSS-BORDER TRANSFER'));
      expect(txt, contains('COOKIES, LOCAL STORAGE & PUSH NOTIFICATIONS'));
    });

    testWidgets('states how to complain to the Information Regulator',
        (tester) async {
      await pumpPolicy(tester);
      final txt = renderedText(tester);
      expect(txt, contains('Lodge a Complaint'));
      expect(txt, contains(PopiaRegistration.regulatorWebsite));
      expect(txt, contains(PopiaRegistration.regulatorComplaintsEmail));
      expect(find.byKey(const ValueKey('privacyPolicyRegulatorButton')),
          findsOneWidget);
    });

    testWidgets('shows the last-updated date and policy version',
        (tester) async {
      await pumpPolicy(tester);
      final txt = renderedText(tester);
      expect(txt, contains('Last Updated:'));
      expect(txt, contains(PopiaRegistration.lastUpdated));
      expect(txt, contains(PopiaRegistration.policyVersion));
    });

    testWidgets('promises health / ID / firearm data is owner-only readable',
        (tester) async {
      await pumpPolicy(tester);
      final txt = renderedText(tester);
      expect(txt, contains('only by you'));
      expect(txt, contains('special personal information'));
    });

    testWidgets('acceptance footer is rendered only when requested',
        (tester) async {
      await pumpPolicy(tester);
      expect(find.byKey(const ValueKey('privacyPolicyAcceptButton')),
          findsNothing);

      await pumpPolicy(tester, acceptance: true);
      expect(find.byKey(const ValueKey('privacyPolicyAcceptButton')),
          findsOneWidget);
    });

    testWidgets('acceptance button pops with true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen(
                        showAcceptanceFooter: true,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final btn = find.byKey(const ValueKey('privacyPolicyAcceptButton'));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('firestore.rules POPIA sensitive-data contract', () {
    late String rules;

    setUpAll(() {
      rules = _readRules();
    });

    test('users/{uid}/private is owner-only (never cross-user readable)', () {
      final block = _blockFor(rules, 'match /users/{userId}/private/{docId}');
      expect(block, isNotEmpty);
      expect(
        block,
        contains('request.auth.uid == userId'),
        reason: 'the private profile must be owner-scoped',
      );
      // It must NOT be the blanket signed-in read used by the parent doc.
      expect(block, isNot(contains('allow read: if isSignedIn();')));
    });

    test('2FA security subcollection is owner-scoped', () {
      final block = _blockFor(rules, 'match /users/{userId}/security/{docId}');
      expect(block, isNotEmpty);
      expect(block, contains('request.auth.uid == userId'));
    });

    test('noSensitiveFieldAdded() helper freezes every sensitive field', () {
      for (final f in SensitivePersonalInformation.allSensitiveFields) {
        expect(rules, contains("sensitiveFieldUnchanged('$f')"),
            reason: '$f must be frozen on the cross-user-readable doc');
      }
    });

    test('the users/{uid} write grant applies the sensitive-field guard', () {
      final block = _blockFor(rules, 'match /users/{userId} {');
      expect(block, contains('noSensitiveFieldAdded()'));
    });
  });
}

String _readRules() {
  // `flutter test` runs with the package root as the CWD.
  return _file('firestore.rules');
}

String _file(String relative) {
  final f = File(relative);
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

/// Extracts a rules block (brace-depth aware) starting at [needle].
///
/// Two subtleties this handles:
///  * the scan begins AFTER the needle, so a parameter brace inside the match
///    path (e.g. `{userId}`) is never mistaken for the block's opening brace;
///  * full-line `//` comments are stripped first, because prose such as
///    `set(..., {merge: true})` would otherwise unbalance the brace count.
String _blockFor(String rules, String needle) {
  final clean = _stripComments(rules);
  final start = clean.indexOf(needle);
  if (start < 0) return '';
  final open = clean.indexOf('{', start + needle.length);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < clean.length; i++) {
    final c = clean[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return clean.substring(start, i + 1);
    }
  }
  return clean.substring(start);
}

/// Removes full-line `//` comments so brace/paren counting is not confused by
/// prose that mentions braces.
String _stripComments(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');
