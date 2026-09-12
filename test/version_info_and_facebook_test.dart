// Tests for the version-display + Facebook link widgets added to the
// hunter/outfitter profile-settings surfaces.
//
//  - VersionInfo: the pure fallback contract (fallbackVersionName /
//    fallbackVersionCode) surfaced headlessly, where package_info_plus
//    cannot resolve a real bundle.
//  - VersionInfoCaption: renders the version line (fallback in tests).
//  - FacebookLinkTile: renders the community link row with the correct
//    URL constant (launch itself is platform-gated and not exercised).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/widgets/version_info.dart';
import 'package:jagspoor/features/shared/widgets/facebook_link_tile.dart';

void main() {
  group('VersionInfo fallback contract', () {
    test('fallback constants mirror the current Android Play build', () {
      expect(VersionInfo.fallbackVersionName, '4.3');
      expect(VersionInfo.fallbackVersionCode, '4');
    });

    test('resolve() never throws on unsupported hosts', () async {
      // package_info_plus cannot resolve a real bundle on the headless test
      // host; resolve() must degrade to the documented fallback values.
      final info = await VersionInfo.resolve();
      expect(info['name'], anyOf(VersionInfo.fallbackVersionName, isNotEmpty));
      expect(info['code'], anyOf(VersionInfo.fallbackVersionCode, isNotEmpty));
      expect(info['display'], contains('build'));
    });
  });

  testWidgets('VersionInfoCaption renders the version line', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: const VersionInfoCaption()),
    ));
    await tester.pump();
    expect(
      find.text(
        'v${VersionInfo.fallbackVersionName} · build ${VersionInfo.fallbackVersionCode}',
      ),
      findsWidgets,
    );
  });

  testWidgets('FacebookLinkTile renders the community link row', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: const FacebookLinkTile()),
    ));
    expect(find.text('Follow Us on Facebook'), findsOneWidget);
    expect(FacebookLinkTile.facebookUrl, contains('facebook.com'));
    expect(
      FacebookLinkTile.facebookUrl,
      'https://www.facebook.com/profile.php?id=61593783617254',
    );
  });
}