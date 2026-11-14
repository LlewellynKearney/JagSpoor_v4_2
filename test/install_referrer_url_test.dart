import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/services/referral_link_service.dart';

/// Task 2B — Play Install Referrer URL/parse contracts.
///
/// Covers the Play Store `referrer=` URL the share link emits and the parser
/// the Dart `InstallReferrerService` uses to turn a raw referrer string back
/// into a referral code. Pure + dependency-free.
void main() {
  group('ReferralLinkService.buildPlayStoreReferrerUrl', () {
    test('builds the Play URL with a referral_<CODE> referrer', () {
      final url =
          ReferralLinkService.buildPlayStoreReferrerUrl('JAGSPOOR7Q3X');
      expect(url, startsWith(
          'https://play.google.com/store/apps/details?id=za.co.jagspoor.app'));
      expect(url, contains('&referrer=referral_JAGSPOOR7Q3X'));
    });

    test('lower-cases + trims the code before building the URL', () {
      final url =
          ReferralLinkService.buildPlayStoreReferrerUrl('  jagspoor7q3x  ');
      expect(url, contains('&referrer=referral_JAGSPOOR7Q3X'));
    });

    test('blank code yields the plain listing URL (no referrer)', () {
      expect(
        ReferralLinkService.buildPlayStoreReferrerUrl(''),
        ReferralLinkService.playStoreUrl,
      );
      expect(
        ReferralLinkService.buildPlayStoreReferrerUrl('   '),
        isNot(contains('referrer=')),
      );
    });
  });

  group('ReferralLinkService.parseInstallReferrer', () {
    test('parses the canonical referral_<CODE> value', () {
      expect(
        ReferralLinkService.parseInstallReferrer('referral_JAGSPOOR7Q3X'),
        'JAGSPOOR7Q3X',
      );
    });

    test('is case-insensitive + tolerant of surrounding whitespace', () {
      expect(
        ReferralLinkService.parseInstallReferrer('  Referral_jagspoor7q3x  '),
        'JAGSPOOR7Q3X',
      );
    });

    test('tolerates extra &-joined params', () {
      expect(
        ReferralLinkService.parseInstallReferrer(
            'referral_JAGSPOOR7Q3X&utm_source=share'),
        'JAGSPOOR7Q3X',
      );
    });

    test('tolerates a leading ? or &', () {
      expect(
        ReferralLinkService.parseInstallReferrer('?referral_ABC23456'),
        'ABC23456',
      );
      expect(
        ReferralLinkService.parseInstallReferrer('&referral_ABC23456'),
        'ABC23456',
      );
    });

    test('accepts a bare code (no prefix)', () {
      expect(
        ReferralLinkService.parseInstallReferrer('ABC23456'),
        'ABC23456',
      );
    });

    test('returns null for null / blank / prefix-only referrers', () {
      expect(ReferralLinkService.parseInstallReferrer(null), isNull);
      expect(ReferralLinkService.parseInstallReferrer(''), isNull);
      expect(ReferralLinkService.parseInstallReferrer('   '), isNull);
      expect(ReferralLinkService.parseInstallReferrer('referral_'), isNull);
    });

    test('round-trips the URL builder through the parser', () {
      final url = ReferralLinkService.buildPlayStoreReferrerUrl('JAGSPOOR7Q3X');
      final referrer = Uri.parse(url).queryParameters['referrer'];
      expect(
        ReferralLinkService.parseInstallReferrer(referrer),
        'JAGSPOOR7Q3X',
      );
    });

    test('does not throw on a malformed percent escape', () {
      expect(
        ReferralLinkService.parseInstallReferrer('referral_%E0%A4%A'),
        isNotNull,
      );
    });
  });
}
