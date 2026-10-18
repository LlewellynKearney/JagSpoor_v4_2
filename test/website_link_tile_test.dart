import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/shared/widgets/website_link_tile.dart';

/// Website link contract.
///
/// The Hunter profile + Outfitter settings screens surface a "Visit JagSpoor
/// Website" row (next to the existing Facebook row) pointing at the public
/// `https://jag-spoor.co.za` site. These tests lock the URL constant, the
/// widget's rendered copy, and the presence of the tile at BOTH call sites so
/// a future refactor cannot silently drop it from one portal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WebsiteLinkTile exposes the canonical JagSpoor website URL', () {
    expect(WebsiteLinkTile.websiteUrl, 'https://jag-spoor.co.za');
    expect(WebsiteLinkTile.websiteUrl.startsWith('https://'), isTrue);
  });

  testWidgets('WebsiteLinkTile renders the website row', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WebsiteLinkTile()),
    ));
    expect(find.text('Visit JagSpoor Website'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('WebsiteLinkTile honours custom title + subtitle',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WebsiteLinkTile(
          title: 'JagSpoor Site',
          subtitle: 'jag-spoor.co.za',
        ),
      ),
    ));
    expect(find.text('JagSpoor Site'), findsOneWidget);
    expect(find.text('jag-spoor.co.za'), findsOneWidget);
  });

  test('both the Hunter profile and Outfitter settings render the tile', () {
    final hunter =
        File('lib/features/hunter_mode/hunter_profile_screen.dart')
            .readAsStringSync();
    expect(hunter.contains('WebsiteLinkTile'), isTrue,
        reason: 'The Hunter profile must show the website link.');
    expect(hunter.contains('website_link_tile.dart'), isTrue);

    final outfitter =
        File('lib/features/outfitter_mode/outfitter_dashboard.dart')
            .readAsStringSync();
    expect(outfitter.contains('WebsiteLinkTile'), isTrue,
        reason: 'The Outfitter settings must show the website link.');
    expect(outfitter.contains('website_link_tile.dart'), isTrue);
  });

  test('the website URL lives in the shared tile, not hardcoded per screen',
      () {
    final tile = File('lib/features/shared/widgets/website_link_tile.dart')
        .readAsStringSync();
    expect(tile.contains("'https://jag-spoor.co.za'"), isTrue);
    // The profile screens reference the widget rather than the raw URL, so the
    // single source of truth stays the tile.
    final hunter =
        File('lib/features/hunter_mode/hunter_profile_screen.dart')
            .readAsStringSync();
    expect(hunter.contains("'https://jag-spoor.co.za'"), isFalse);
  });
}
