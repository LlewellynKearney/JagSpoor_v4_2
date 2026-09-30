import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural regression guards for the post-Dynamic-Links App Links
/// configuration. Firebase Dynamic Links (`jagspoor.page.link`) was shut down
/// by Google on 2025-08-25, so referral invites now use standard HTTPS App
/// Links on `jag-spoor.co.za/r/<CODE>` (plus a `jagspoor://` scheme fallback).
///
/// These parse the real config files and would fail if a future change
/// reverted the migration.
String _read(String relative) =>
    File(relative).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('AndroidManifest App Links', () {
    late String manifest;

    setUp(() => manifest = _read('android/app/src/main/AndroidManifest.xml'));

    test('declares an autoVerify HTTPS App Link for jag-spoor.co.za/r', () {
      expect(manifest, contains('android:autoVerify="true"'));
      expect(manifest, contains('android:scheme="https"'));
      expect(manifest, contains('android:host="jag-spoor.co.za"'));
      expect(manifest, contains('android:pathPrefix="/r"'));
    });

    test('declares the /.well-known pathPrefix for association-file checks', () {
      expect(manifest, contains('android:pathPrefix="/.well-known"'));
    });

    test('declares the jagspoor://referral scheme fallback', () {
      expect(manifest, contains('android:scheme="jagspoor"'));
      expect(manifest, contains('android:host="referral"'));
    });

    test('no legacy jagspoor.co.za (hyphen-less) host remains', () {
      // The canonical domain is jag-spoor.co.za; a bare jagspoor.co.za host
      // (no hyphen) is the wrong Afrihost domain and must never reappear.
      expect(
        RegExp(r'android:host="jagspoor\.co\.za"').hasMatch(manifest),
        isFalse,
      );
    });

    test('no live page.link reference remains (comments only)', () {
      // Strip XML comments (which legitimately document the shutdown) and
      // assert no ACTIVE data/host attribute mentions the dead domain.
      final withoutComments =
          manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      expect(withoutComments.contains('page.link'), isFalse);
    });
  });

  group('association files', () {
    test('assetlinks.json targets the production Android package', () {
      final json =
          jsonDecode(_read('public/.well-known/assetlinks.json')) as List;
      final target = (json.first as Map)['target'] as Map;
      expect(target['package_name'], 'za.co.jagspoor.app');
      expect(target['sha256_cert_fingerprints'], isA<List>());
    });

    test('apple-app-site-association maps jag-spoor.co.za /r/*', () {
      final json =
          jsonDecode(_read('public/.well-known/apple-app-site-association'))
              as Map;
      final details = (json['applinks'] as Map)['details'] as List;
      final paths = (details.first as Map)['paths'] as List;
      expect(paths, contains('/r/*'));
      expect((details.first as Map)['appID'], contains('za.co.jagspoor.app'));
    });
  });

  group('referral landing page + hosting rewrite', () {
    test('the landing page resolves the code from the path and ?code=', () {
      final html = _read('public/r/index.html');
      expect(html, contains('/r/'));
      expect(html, contains("params.get('code')"));
      expect(html, contains("split('/')"));
      expect(html, contains('jagspoor://referral?code='));
      expect(html, contains('za.co.jagspoor.app'));
      // Deep-links into an installed app, else falls back to Play.
      expect(html, contains('intent://referral'));
      expect(html, contains('play.google.com/store/apps/details'));
    });

    test('firebase.json rewrites /r/** to the landing page', () {
      final config = jsonDecode(_read('firebase.json')) as Map;
      final hosting = config['hosting'] as Map;
      expect(hosting['public'], 'public');
      final rewrites = hosting['rewrites'] as List;
      final rule = rewrites.first as Map;
      expect(rule['source'], '/r/**');
      expect(rule['destination'], '/r/index.html');
    });

    test('firebase.json serves the .well-known association files', () {
      final config = jsonDecode(_read('firebase.json')) as Map;
      final hosting = config['hosting'] as Map;
      // Hosting must NOT auto-generate (and thereby override) the association
      // files -- our hand-authored assetlinks.json / AASA must win.
      expect(hosting['appAssociation'], 'NONE');
      // The default `**/.*` ignore pattern excludes the `.well-known`
      // directory from the upload, so it must be gone.
      final ignore = (hosting['ignore'] as List).cast<String>();
      expect(ignore.contains('**/.*'), isFalse);
      // A Content-Type override keeps the extension-less AASA served as JSON.
      final headers = (hosting['headers'] as List).cast<Map>();
      final sources = headers.map((h) => h['source']).toList();
      expect(sources, contains('/.well-known/assetlinks.json'));
      expect(sources, contains('/.well-known/apple-app-site-association'));
    });

    test('firebase.json has no catch-all rewrite (would break assetlinks)', () {
      final config = jsonDecode(_read('firebase.json')) as Map;
      final hosting = config['hosting'] as Map;
      final rewrites = (hosting['rewrites'] as List).cast<Map>();
      for (final rule in rewrites) {
        expect(rule['source'], isNot('**'));
        expect(rule['destination'], isNot('/index.html'));
      }
    });
  });

  group('iOS Universal Links', () {
    test('Runner.entitlements associates jag-spoor.co.za', () {
      final ent = _read('ios/Runner/Runner.entitlements');
      expect(ent, contains('com.apple.developer.associated-domains'));
      expect(ent, contains('applinks:jag-spoor.co.za'));
    });

    test('Info.plist declares the jagspoor URL scheme', () {
      final plist = _read('ios/Runner/Info.plist');
      expect(plist, contains('CFBundleURLTypes'));
      expect(plist, contains('<string>jagspoor</string>'));
    });

    test('the entitlements file is wired into the Xcode project', () {
      final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
      expect(pbx, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'));
    });
  });

  group('referralCodes Firestore rules', () {
    late String rules;

    setUp(() => rules = _read('firestore.rules'));

    test('a referralCodes match block exists', () {
      expect(rules, contains('match /referralCodes/{code}'));
    });

    test('reads are signed-in scoped and creates are owner-scoped', () {
      expect(rules, contains('allow read: if isSignedIn();'));
      expect(
        rules,
        contains('request.resource.data.ownerUid == request.auth.uid'),
      );
    });
  });
}
