import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/support/services/support_email_composer.dart';

/// Automated support-email generator tests.
///
/// Verifies the `mailto:support@jag-spoor.co.za` target, the
/// `Uri.encodeComponent`-safe escaping (spaces → `%20`, newlines → `%0D%0A`,
/// no literal `+`), and the dynamic injection of User ID, Description, and
/// System Context fields into both the bug-report and feature-suggestion
/// templates.
void main() {
  group('SupportEmailComposer — mailto target', () {
    test('bug report mailto targets the canonical support inbox', () {
      final uri = SupportEmailComposer.buildBugReportMailtoUri(
        userId: 'uid-123',
        title: 'Crash on login',
        steps: 'Tap login',
        severity: 'Critical',
      );
      expect(uri.scheme, 'mailto');
      expect(uri.path, SupportEmailComposer.supportEmail);
      expect(uri.toString(), startsWith('mailto:support@jag-spoor.co.za?'));
    });

    test('feature suggestion mailto targets the canonical support inbox', () {
      final uri = SupportEmailComposer.buildFeatureSuggestionMailtoUri(
        userId: 'uid-456',
        title: 'Dark map mode',
        description: 'Add a dark topo layer',
        benefits: 'Less battery',
      );
      expect(uri.scheme, 'mailto');
      expect(uri.path, SupportEmailComposer.supportEmail);
    });
  });

  group('SupportEmailComposer — Uri.encodeComponent escaping', () {
    test('spaces are encoded as %20, never as a literal +', () {
      final uri = SupportEmailComposer.buildBugReportMailtoUri(
        userId: 'u',
        title: 'two words',
        steps: 'single step',
        severity: 'Low',
      );
      final str = uri.toString();
      // The subject carries the title; its spaces must be %20, not '+'.
      expect(str, contains('two%20words'));
      expect(str.contains('two+words'), isFalse);
    });

    test('newlines in the body are percent-encoded (no raw line breaks)', () {
      final uri = SupportEmailComposer.buildFeatureSuggestionMailtoUri(
        userId: 'u',
        title: 't',
        description: 'line one\nline two',
        benefits: 'b1\nb2',
      );
      final str = uri.toString();
      // No raw CR/LF should leak into the mailto string.
      expect(str.contains('\n'), isFalse);
      expect(str.contains('\r'), isFalse);
      // The encoded newline pair must be present.
      expect(str, contains('%0A'));
    });

    test('ampersand and equals in user text do not break the query structure', () {
      // An unescaped '&' or '=' in the body could otherwise inject a second
      // mailto parameter. Uri.encodeComponent must neutralize them.
      final uri = SupportEmailComposer.buildBugReportMailtoUri(
        userId: 'u',
        title: 'a & b = c',
        steps: 'x=1&y=2',
        severity: 'Medium',
      );
      final str = uri.toString();
      // Only one 'subject=' and one 'body=' parameter separator should exist
      // in the raw mailto string.
      expect('?subject='.allMatches(str).length, 1);
      expect('&body='.allMatches(str).length, 1);
    });
  });

  group('SupportEmailComposer — dynamic field injection', () {
    test('bug report body injects User ID, severity, and system context', () {
      final body = SupportEmailComposer.buildBugReportEmailBody(
        userId: 'uid-ABC',
        title: 'Crash',
        steps: 'step one\nstep two',
        severity: 'Critical',
      );
      expect(body, contains('User ID    : uid-ABC'));
      expect(body, contains('Severity   : Critical'));
      expect(body, contains('step one'));
      expect(body, contains('step two'));
      expect(body, contains('SYSTEM CONTEXT'));
      expect(body, contains('Platform      :'));
      expect(body, contains('OS Version    :'));
      expect(body, contains('App Package   : com.jagspoor.app'));
    });

    test('feature suggestion body injects User ID and system context', () {
      final body = SupportEmailComposer.buildFeatureSuggestionEmailBody(
        userId: 'uid-XYZ',
        title: 'Dark mode',
        description: 'desc line',
        benefits: 'benefit line',
      );
      expect(body, contains('User ID    : uid-XYZ'));
      expect(body, contains('desc line'));
      expect(body, contains('benefit line'));
      expect(body, contains('SYSTEM CONTEXT'));
      expect(body, contains('Locale        :'));
    });

    test('empty / blank fields render N/A rather than blank lines', () {
      final body = SupportEmailComposer.buildBugReportEmailBody(
        userId: '',
        title: '  ',
        steps: '',
        severity: '',
      );
      expect(body, contains('User ID    : N/A'));
      expect(body, contains('Title      : N/A'));
      expect(body, contains('Severity   : N/A'));
      // Empty steps list falls back to an N/A bullet.
      expect(body, contains('• N/A'));
    });
  });

  group('SupportEmailComposer — system context block', () {
    test('systemContextBlock lists every context field on its own line', () {
      final block = SupportEmailComposer.systemContextBlock();
      expect(block, contains('Platform'));
      expect(block, contains('OS Version'));
      expect(block, contains('Locale'));
      expect(block, contains('CPU Cores'));
      expect(block, contains('App Package'));
      expect(block, contains('Channel'));
      // Must not throw on the desktop test runner (Platform is available).
      expect(block, isNot(contains('web')));
    });
  });
}
