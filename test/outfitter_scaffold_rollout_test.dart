import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural rollout contract: the shared bushveld background stack and the
/// high-contrast action chips must be applied consistently across every
/// outfitter-side screen so the entire portal carries the same immersive
/// aesthetic (and no screen regresses back to a plain themed background).
///
/// The Firestore emulator cannot run in this sandbox, so this suite asserts
/// the rollout contract by reading the screen sources directly (mirroring
/// the established `firestore_rules_seeding_test` structural pattern).
void main() {
  const outfitterScreens = {
    'dashboard': 'lib/features/outfitter_mode/outfitter_dashboard.dart',
    'farm_management':
        'lib/features/hunter_mode/screens/outfitter_enterprise_panel_screen.dart',
    'trophy_stock':
        'lib/features/hunter_mode/screens/outfitter_trophy_stock_screen.dart',
    'package_publishing':
        'lib/features/hunter_mode/screens/outfitter_package_creator_screen.dart',
    'package_management':
        'lib/features/hunter_mode/screens/outfitter_package_manager_screen.dart',
    'price_lists':
        'lib/features/hunter_mode/screens/outfitter_price_list_screen.dart',
    'booking_requests':
        'lib/features/hunter_mode/screens/outfitter_booking_dashboard_screen.dart',
    'permit_log':
        'lib/features/hunter_mode/screens/venison_permit_list_screen.dart',
    'revenue_bi':
        'lib/features/hunter_mode/screens/outfitter_revenue_screen.dart',
  };

  String readSource(String relPath) => File(relPath).readAsStringSync();

  group('shared bushveld background rollout', () {
    test('the shared background stack helper exists and exposes the photo + '
        'asset fallback + mode-aware scrim', () {
      final src =
          readSource('lib/features/outfitter_mode/widgets/outfitter_scaffold.dart');
      expect(src.contains('class OutfitterBushveldBackground'), isTrue);
      expect(src.contains('kBackgroundImageUrl'), isTrue);
      expect(src.contains('kBackgroundFallbackAsset'), isTrue);
      expect(src.contains('Greater Kudu.jpg'), isTrue);
      expect(
        src.contains('scrim({bool isDarkMode = true})'),
        isTrue,
        reason: 'The scrim must accept a mode flag.',
      );
      // Light-mode warm cream veil colours.
      expect(src.contains('Color(0xE6F7F1E6)'), isTrue,
          reason: 'Light-mode scrim must be a warm cream veil.');
      // Dark-mode dense black gradient colours.
      expect(src.contains('Color(0xA6000000)'), isTrue,
          reason: 'Dark-mode scrim must be a dense black gradient.');
    });

    test('OutfitterUi light-mode palette uses rich warm cards + espresso text',
        () {
      final src =
          readSource('lib/features/outfitter_mode/widgets/outfitter_scaffold.dart');
      expect(src.contains('class OutfitterUi'), isTrue);
      expect(
        src.contains('Color(0xFFEFE7DC)'),
        isTrue,
        reason: 'The light card surface must be the toned-down warm EFE7DC.',
      );
      expect(src.contains('Color(0xFF2C221E)'), isTrue,
          reason: 'The espresso title text must be 0xFF2C221E.');
      expect(src.contains('Color(0xFF4A3B32)'), isTrue,
          reason: 'The warm-brown secondary text must be 0xFF4A3B32.');
    });

    for (final entry in outfitterScreens.entries) {
      test('${entry.key} renders the shared bushveld background stack', () {
        final src = readSource(entry.value);
        expect(
          src.contains('OutfitterScaffold') ||
              src.contains('OutfitterBushveldBackground'),
          isTrue,
          reason:
              '${entry.key} must render the shared OutfitterBushveldBackground '
              'stack (directly or via OutfitterScaffold) so the portal carries '
              'the immersive bushveld aesthetic.',
        );
        expect(
          src.contains('backgroundColor: Colors.transparent') ||
              src.contains('extendBodyBehindAppBar'),
          isTrue,
          reason:
              '${entry.key} must full-bleed the background under a transparent '
              'AppBar (extendBodyBehindAppBar).',
        );
      });
    }
  });

  group('top-right action icon contrast chips', () {
    test('the OutfitterActionChip widget renders a high-contrast dark chip', () {
      final src =
          readSource('lib/features/outfitter_mode/widgets/outfitter_scaffold.dart');
      expect(src.contains('class OutfitterActionChip'), isTrue);
      expect(src.contains('BoxShape.circle'), isTrue);
      expect(src.contains('Colors.black.withAlpha'), isTrue,
          reason: 'The chip background must be a translucent dark circle so '
              'icons stay readable on the bright sunrise region.');
    });

    test('the outfitter dashboard uses frosted chips for its header actions',
        () {
      final src = readSource(outfitterScreens['dashboard']!);
      // The dashboard header groups its actions into frosted circular chips
      // (Hunter-Mode parity) via the shared HunterFrostedCircleButton.
      expect(src.contains('HunterFrostedCircleButton'), isTrue,
          reason: 'The header actions must be frosted circular chips.');
      expect(src.contains('OutfitterDashboardHeader'), isTrue,
          reason: 'The dashboard must render the branded frosted header.');
      expect(src.contains('Icons.lock_reset_rounded'), isTrue);
      // The raw accent-only IconButton for settings/logout must be gone.
      expect(
        src.contains('icon: Icon(Icons.settings_rounded, color: theme.accentColor)'),
        isFalse,
        reason: 'The low-contrast raw IconButton must be replaced by the chip.',
      );
    });

    test('the price list screen uses chips for its three action icons', () {
      final src = readSource(outfitterScreens['price_lists']!);
      expect(
        src.split('OutfitterActionChip(').length - 1,
        greaterThanOrEqualTo(3),
        reason: 'PDF export, CSV import, and refresh must each be a chip.',
      );
    });

    test('the trophy stock + revenue screens use chips for their PDF icons',
        () {
      for (final key in ['trophy_stock', 'revenue_bi']) {
        final src = readSource(outfitterScreens[key]!);
        expect(src.contains('OutfitterActionChip'), isTrue,
            reason: '$key must render its top-right PDF action as a chip.');
        expect(src.contains('Icons.picture_as_pdf_rounded'), isTrue);
      }
    });
  });
}
