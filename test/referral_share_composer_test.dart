import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/referral/services/referral_share_composer.dart';

/// Pure unit tests for [ReferralShareComposer] — the deep-link / message /
/// WhatsApp builders that drive the ReferralShareWidget copy + share actions.
void main() {
  group('ReferralShareComposer.buildReferralLink', () {
    test('builds an App Link carrying the code as a path segment', () {
      expect(
        ReferralShareComposer.buildReferralLink('JAGSPOOR7Q3X'),
        'https://jagspoor.co.za/r/JAGSPOOR7Q3X',
      );
    });

    test('never emits the dead page.link domain', () {
      final link = ReferralShareComposer.buildReferralLink('JAGSPOOR7Q3X');
      expect(link.contains('page.link'), isFalse);
      expect(link.startsWith('https://jagspoor.co.za/r/'), isTrue);
    });

    test('builds the custom-scheme fallback', () {
      expect(
        ReferralShareComposer.buildCustomSchemeLink('JAGSPOOR7Q3X'),
        'jagspoor://referral?code=JAGSPOOR7Q3X',
      );
    });

    test('upper-cases + trims the code', () {
      expect(
        ReferralShareComposer.buildReferralLink('  jagspoor7q3x '),
        'https://jagspoor.co.za/r/JAGSPOOR7Q3X',
      );
    });

    test('returns an empty string for a blank code', () {
      expect(ReferralShareComposer.buildReferralLink(''), isEmpty);
      expect(ReferralShareComposer.buildReferralLink(null), isEmpty);
      expect(ReferralShareComposer.buildReferralLink('   '), isEmpty);
    });
  });

  group('ReferralShareComposer.buildShareMessage', () {
    test('includes the code + the deep link + support contact', () {
      final message =
          ReferralShareComposer.buildShareMessage('JAGSPOOR7Q3X');
      expect(message, contains('JAGSPOOR7Q3X'));
      expect(
        message,
        contains('jagspoor.co.za/r/JAGSPOOR7Q3X'),
      );
      expect(message, contains('Refer a friend and we both unlock rewards.'));
      expect(message, contains('support@jagspoor.co.za'));
    });

    test('returns an empty string for a blank code', () {
      expect(ReferralShareComposer.buildShareMessage(''), isEmpty);
    });
  });

  group('ReferralShareComposer.buildWhatsAppShareLink', () {
    test('builds a wa.me deep link with an encoded text payload', () {
      final link = ReferralShareComposer.buildWhatsAppShareLink(
          'JAGSPOOR7Q3X');
      expect(link, startsWith('https://wa.me/?text='));
      // The whole message is percent-encoded, so the App Link's `/r/` path
      // appears encoded (`%2Fr%2F`).
      expect(link, contains('%2Fr%2F'));
      expect(link, contains('JAGSPOOR7Q3X'));
      // The text payload must be percent-encoded (safe for the WhatsApp
      // intent) and not contain raw spaces/newlines.
      expect(link.contains(' '), isFalse);
      expect(link.contains('\n'), isFalse);
    });

    test('returns an empty string for a blank code', () {
      expect(ReferralShareComposer.buildWhatsAppShareLink(''), isEmpty);
    });
  });

  group('ReferralShareComposer.formatCodeForDisplay', () {
    test('groups the code in blocks of four', () {
      expect(
        ReferralShareComposer.formatCodeForDisplay('JAGSPOOR7Q3X'),
        'JAGS POOR 7Q3X',
      );
      expect(
        ReferralShareComposer.formatCodeForDisplay('ABCD1234'),
        'ABCD 1234',
      );
    });

    test('handles short + blank codes', () {
      expect(ReferralShareComposer.formatCodeForDisplay('ABC'), 'ABC');
      expect(ReferralShareComposer.formatCodeForDisplay(''), isEmpty);
      expect(ReferralShareComposer.formatCodeForDisplay(null), isEmpty);
    });

    test('upper-cases a lowercase input', () {
      expect(
        ReferralShareComposer.formatCodeForDisplay('jagspoor7q3x'),
        'JAGS POOR 7Q3X',
      );
    });
  });
}