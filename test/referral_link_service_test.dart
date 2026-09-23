import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/services/referral_link_service.dart';

/// Unit tests for [ReferralLinkService] — the post-Dynamic-Links App Links
/// replacement (Firebase Dynamic Links was shut down 2025-08-25).
void main() {
  group('ReferralLinkService.generateReferralLink', () {
    test('builds the canonical /r/<CODE> App Link', () {
      expect(
        ReferralLinkService.generateReferralLink('uid-1', 'JAGSPOOR7Q3X'),
        'https://jagspoor.co.za/r/JAGSPOOR7Q3X',
      );
    });

    test('never emits the dead page.link domain', () {
      final link = ReferralLinkService.generateReferralLink('uid-1', 'ABC123');
      expect(link.contains('page.link'), isFalse);
      expect(link.startsWith('https://jagspoor.co.za/r/'), isTrue);
    });

    test('upper-cases + trims the code', () {
      expect(
        ReferralLinkService.generateReferralLink('uid-1', '  jagspoor7q3x '),
        'https://jagspoor.co.za/r/JAGSPOOR7Q3X',
      );
    });

    test('returns empty for a blank / null code', () {
      expect(ReferralLinkService.generateReferralLink('uid-1', ''), isEmpty);
      expect(ReferralLinkService.generateReferralLink('uid-1', '   '), isEmpty);
    });

    test('the single-arg overload matches the two-arg form', () {
      expect(
        ReferralLinkService.generateReferralLinkForCode('ABC123'),
        ReferralLinkService.generateReferralLink('', 'ABC123'),
      );
    });
  });

  group('ReferralLinkService.generateCustomSchemeLink', () {
    test('builds the jagspoor:// fallback', () {
      expect(
        ReferralLinkService.generateCustomSchemeLink('JAGSPOOR7Q3X'),
        'jagspoor://referral?code=JAGSPOOR7Q3X',
      );
    });

    test('returns empty for a blank code', () {
      expect(ReferralLinkService.generateCustomSchemeLink(''), isEmpty);
      expect(ReferralLinkService.generateCustomSchemeLink('   '), isEmpty);
    });
  });

  group('ReferralLinkService.buildShareMessage', () {
    test('includes the marketing line + the App Link', () {
      final message =
          ReferralLinkService.buildShareMessage('JAGSPOOR7Q3X', userId: 'u1');
      expect(message, contains('1 month free'));
      expect(message, contains('https://jagspoor.co.za/r/JAGSPOOR7Q3X'));
      expect(message.contains('page.link'), isFalse);
    });

    test('returns empty for a blank code', () {
      expect(ReferralLinkService.buildShareMessage(''), isEmpty);
    });
  });

  group('ReferralLinkService.extractReferralCode', () {
    test('extracts from an HTTPS App Link path', () {
      expect(
        ReferralLinkService.extractReferralCode(
          Uri.parse('https://jagspoor.co.za/r/JAGSPOOR7Q3X'),
        ),
        'JAGSPOOR7Q3X',
      );
    });

    test('extracts from the custom-scheme query param', () {
      expect(
        ReferralLinkService.extractReferralCode(
          Uri.parse('jagspoor://referral?code=JAGSPOOR7Q3X'),
        ),
        'JAGSPOOR7Q3X',
      );
    });

    test('tolerates a ?code= query on the HTTPS link (web redirect)', () {
      expect(
        ReferralLinkService.extractReferralCode(
          Uri.parse('https://jagspoor.co.za/r/JAGSPOOR7Q3X?code=OTHER123'),
        ),
        // The path segment wins over the query param.
        'JAGSPOOR7Q3X',
      );
      expect(
        ReferralLinkService.extractReferralCode(
          Uri.parse('https://jagspoor.co.za/somewhere?code=QUERY123'),
        ),
        'QUERY123',
      );
    });

    test('upper-cases the extracted code', () {
      expect(
        ReferralLinkService.extractReferralCode(
          Uri.parse('https://jagspoor.co.za/r/abc123'),
        ),
        'ABC123',
      );
    });

    test('returns null for a non-referral link', () {
      expect(
        ReferralLinkService.extractReferralCode(
          Uri.parse('https://jagspoor.co.za/about'),
        ),
        isNull,
      );
      expect(
        ReferralLinkService.extractReferralCode(
          Uri.parse('https://example.com/r/ABC123'),
        ),
        // A different host is still parsed if the /r/ shape matches; the
        // service is shape-based, host validation happens in the manifest.
        'ABC123',
      );
      expect(ReferralLinkService.extractReferralCode(null), isNull);
    });

    test('isReferralLink reflects the extraction', () {
      expect(
        ReferralLinkService.isReferralLink(
          Uri.parse('https://jagspoor.co.za/r/ABC123'),
        ),
        isTrue,
      );
      expect(
        ReferralLinkService.isReferralLink(Uri.parse('https://jagspoor.co.za')),
        isFalse,
      );
      expect(ReferralLinkService.isReferralLink(null), isFalse);
    });

    test('the built link round-trips through the extractor', () {
      final link =
          ReferralLinkService.generateReferralLink('uid-1', 'ROUNDTRIP9');
      expect(
        ReferralLinkService.extractReferralCode(Uri.parse(link)),
        'ROUNDTRIP9',
      );
      final scheme = ReferralLinkService.generateCustomSchemeLink('ROUNDTRIP9');
      expect(
        ReferralLinkService.extractReferralCode(Uri.parse(scheme)),
        'ROUNDTRIP9',
      );
    });
  });

  group('ReferralLinkService constants', () {
    test('the domain is the owned production domain', () {
      expect(ReferralLinkService.domain, 'https://jagspoor.co.za');
      expect(ReferralLinkService.referralPathPrefix, '/r/');
    });

    test('association-file paths are the well-known locations', () {
      expect(ReferralLinkService.assetLinksPath, '/.well-known/assetlinks.json');
      expect(
        ReferralLinkService.appleAppSiteAssociationPath,
        '/.well-known/apple-app-site-association',
      );
    });
  });
}
