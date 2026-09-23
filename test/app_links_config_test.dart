import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural regression guards for the post-Dynamic-Links App Links
/// configuration. Firebase Dynamic Links (`jagspoor.page.link`) was shut down
/// by Google on 2025-08-25, so referral invites now use standard HTTPS App
/// Links on `jagspoor.co.za/r/<CODE>` (plus a `jagspoor://` scheme fallback).
///
/// These parse the real config files and would fail if a future change
/// reverted the migration.
String _read(String relative) =>
    File(relative).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('AndroidManifest App Links', () {
    late String manifest;

    setUp(() => manifest = _read('android/app/src/main/AndroidManifest.xml'));

    test('declares an autoVerify HTTPS App Link for jagspoor.co.za/r/', () {
      expect(manifest, contains('android:autoVerify="true"'));
      expect(manifest, contains('android:scheme="https"'));
      expect(manifest, contains('android:host="jagspoor.co.za"'));
      expect(manifest, contains('android:pathPrefix="/r/"'));
    });

    test('declares the jagspoor://referral scheme fallback', () {
      expect(manifest, contains('android:scheme="jagspoor"'));
      expect(manifest, contains('android:host="referral"'));
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

    test('apple-app-site-association maps jagspoor.co.za /r/*', () {
      final json =
          jsonDecode(_read('public/.well-known/apple-app-site-association'))
              as Map;
      final details = (json['applinks'] as Map)['details'] as List;
      final paths = (details.first as Map)['paths'] as List;
      expect(paths, contains('/r/*'));
    });
  });

  group('referral landing page + hosting rewrite', () {
    test('the landing page resolves the code from the URL', () {
      final html = _read('public/r/index.html');
      expect(html, contains('/r/'));
      expect(html, contains('jagspoor://referral?code='));
      expect(html, contains('za.co.jagspoor.app'));
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
  });

  group('iOS Universal Links', () {
    test('Runner.entitlements associates jagspoor.co.za', () {
      final ent = _read('ios/Runner/Runner.entitlements');
      expect(ent, contains('com.apple.developer.associated-domains'));
      expect(ent, contains('applinks:jagspoor.co.za'));
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
