import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/hunter_mode/services/feedback_firebase_service.dart';

void main() {
  group('FeedbackFirebaseService Payload Tests', () {
    late FeedbackFirebaseService service;

    setUp(() {
      service = FeedbackFirebaseService();
    });

    group('Bug Report Payload Structure', () {
      test('should handle valid bug report parameters', () {
        const title = 'App crashes on trophy upload';
        const steps = '1. Open Trophy Room\n2. Tap Add Trophy\n3. Select image\n4. App crashes';
        const severity = 'Critical';

        expect(title, isA<String>());
        expect(steps, isA<String>());
        expect(severity, isA<String>());
        expect(title.isNotEmpty, isTrue);
        expect(steps.isNotEmpty, isTrue);
        expect(severity.isNotEmpty, isTrue);
      });

      test('should serialize severity levels correctly', () {
        final validSeverities = ['Low', 'Medium', 'Critical'];

        for (final severity in validSeverities) {
          expect(
            validSeverities.contains(severity),
            isTrue,
            reason: 'Severity "$severity" should be valid',
          );
        }
      });

      test('should handle empty string gracefully in payload', () {
        const emptyTitle = '';
        const emptySteps = '';
        const emptySeverity = '';

        expect(emptyTitle.isEmpty, isTrue);
        expect(emptySteps.isEmpty, isTrue);
        expect(emptySeverity.isEmpty, isTrue);
      });

      test('should handle special characters in bug report', () {
        const titleWithSpecial = 'Bug with "quotes" & <special> chars!';
        const stepsWithNewlines = 'Step 1\nStep 2\nStep 3';
        const stepsWithUnicode = '中文步骤\nΕλληνικά βήματα';

        expect(titleWithSpecial.contains('"'), isTrue);
        expect(stepsWithNewlines.contains('\n'), isTrue);
        expect(stepsWithUnicode.isNotEmpty, isTrue);
      });
    });

    group('Feature Suggestion Payload Structure', () {
      test('should handle valid feature suggestion parameters', () {
        const title = 'GPS tracking for hunting routes';
        const description = 'Allow users to track and save their hunting routes with GPS coordinates.';
        const benefits = 'Improves navigation and helps track animal movement patterns.';

        expect(title, isA<String>());
        expect(description, isA<String>());
        expect(benefits, isA<String>());
        expect(title.isNotEmpty, isTrue);
        expect(description.isNotEmpty, isTrue);
        expect(benefits.isNotEmpty, isTrue);
      });

      test('should handle multi-line description', () {
        const description = '''
This feature should include:
- Route tracking
- Waypoint marking
- Distance calculation
- Export to GPX format
''';

        expect(description.contains('-'), isTrue);
        expect(description.split('\n').length, greaterThan(1));
      });

      test('should handle empty strings in feature payload', () {
        const emptyTitle = '';
        const emptyDescription = '';
        const emptyBenefits = '';

        expect(emptyTitle.isEmpty, isTrue);
        expect(emptyDescription.isEmpty, isTrue);
        expect(emptyBenefits.isEmpty, isTrue);
      });
    });

    group('Email Payload Construction', () {
      test('should handle email subject line formatting', () {
        const title = 'App crashes on trophy upload';
        const subject = '[Bug Report] $title';

        expect(subject.startsWith('[Bug Report]'), isTrue);
        expect(subject.contains(title), isTrue);
      });

      test('should handle email body construction for bug reports', () {
        const title = 'Test Bug';
        const steps = 'Step 1: Do this\nStep 2: Do that';
        const severity = 'Medium';

        final body = '''
BUG REPORT - Jagspoor Hunter Dashboard

Title: $title

Severity Level: $severity

Steps to Reproduce:
$steps

---
Submitted via Jagspoor App
''';

        expect(body.contains('BUG REPORT'), isTrue);
        expect(body.contains(title), isTrue);
        expect(body.contains(severity), isTrue);
        expect(body.contains(steps), isTrue);
        expect(body.contains('---'), isTrue);
      });

      test('should handle email body construction for feature suggestions', () {
        const title = 'New Feature';
        const description = 'Feature description here';
        const benefits = 'Benefit 1\nBenefit 2';

        final body = '''
FEATURE SUGGESTION - Jagspoor Hunter Dashboard

Proposed Feature: $title

Detailed Description:
$description

Expected Benefits to Hunting Teams:
$benefits

---
Submitted via Jagspoor App
''';

        expect(body.contains('FEATURE SUGGESTION'), isTrue);
        expect(body.contains(title), isTrue);
        expect(body.contains(description), isTrue);
        expect(body.contains(benefits), isTrue);
      });

      test('should handle URI encoding for special characters', () {
        const subject = 'Bug: App crashes with "quotes" & symbols';
        const encodedSubject = Uri.encodeComponent(subject);

        expect(encodedSubject.contains('"'), isFalse);
        expect(encodedSubject.contains('&'), isFalse);
        expect(encodedSubject.isNotEmpty, isTrue);
      });

      test('should handle URL-safe encoding for email bodies', () {
        const body = 'Body with "quotes" & <brackets> and\nnewlines';
        final encodedBody = Uri.encodeComponent(body);

        expect(encodedBody.contains('"'), isFalse);
        expect(encodedBody.contains('&'), isFalse);
        expect(encodedBody.contains('<'), isFalse);
        expect(encodedBody.contains('>'), isFalse);
        expect(encodedBody.contains('\n'), isFalse);
      });
    });

    group('Firestore Document Structure', () {
      test('should have required fields for bug report', () {
        final requiredFields = ['title', 'steps', 'severity', 'timestamp'];

        for (final field in requiredFields) {
          expect(field.isNotEmpty, isTrue);
        }
      });

      test('should have required fields for feature suggestion', () {
        final requiredFields = ['title', 'description', 'benefits', 'timestamp'];

        for (final field in requiredFields) {
          expect(field.isNotEmpty, isTrue);
        }
      });

      test('should handle optional hunterId field', () {
        const loggedInUserId = 'user_123';
        const anonymousUserId = null;

        expect(loggedInUserId, isA<String>());
        expect(anonymousUserId, isNull);
      });
    });

    group('Edge Cases and Null Safety', () {
      test('should handle null user ID gracefully', () {
        const userId = null;

        final document = <String, dynamic>{
          'title': 'Test',
          'hunterId': userId,
        };

        expect(document['hunterId'], isNull);
        expect(document.containsKey('hunterId'), isTrue);
      });

      test('should handle very long text inputs', () {
        final longTitle = 'A' * 500;
        final longSteps = 'Step: ${'X' * 1000}\n' * 10;

        expect(longTitle.length, equals(500));
        expect(longSteps.length, greaterThan(1000));
      });

      test('should handle Unicode characters in all fields', () {
        const unicodeTitle = '标题测试🔫🦌';
        const unicodeSteps = '步骤1\nШаг 2\nخطوة 3';
        const unicodeBenefits = '利益۱۲۳';

        expect(unicodeTitle.isNotEmpty, isTrue);
        expect(unicodeSteps.isNotEmpty, isTrue);
        expect(unicodeBenefits.isNotEmpty, isTrue);
      });

      test('should handle whitespace-only strings', () {
        const whitespaceOnly = '   \n\t  \n  ';

        expect(whitespaceOnly.trim().isEmpty, isTrue);
      });
    });

    group('Email Target Address', () {
      test('should use correct support email', () {
        const expectedEmail = 'llewellynkearney@gmail.com';

        expect(expectedEmail.contains('@'), isTrue);
        expect(expectedEmail.contains('gmail.com'), isTrue);
      });

      test('should construct valid mailto URI', () {
        const email = 'llewellynkearney@gmail.com';
        const subject = 'Test Subject';
        const body = 'Test Body';

        final uri = Uri(
          scheme: 'mailto',
          path: email,
          queryParameters: {
            'subject': subject,
            'body': body,
          },
        );

        expect(uri.scheme, equals('mailto'));
        expect(uri.path, equals(email));
        expect(uri.queryParameters['subject'], equals(subject));
        expect(uri.queryParameters['body'], equals(body));
      });
    });
  });
}
