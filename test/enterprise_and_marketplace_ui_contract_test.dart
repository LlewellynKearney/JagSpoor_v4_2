import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural source-contract tests for the three UI updates:
///
/// 1. "Income per Farm" breakdown on the Enterprise Business Intelligence
///    screen (aggregates earned-booking ZAR revenue per farmId).
/// 2. Town name rendered directly below the package title on the hunter
///    Package Marketplace card (resolved from the farm / package document).
/// 3. "My Bookings" split into active / upcoming hunts vs the "Past Hunts"
///    archive tab.
///
/// These follow the codebase's structural-test pattern (the Firestore
/// emulator cannot run in this sandbox -- see AGENTS.md environment
/// constraints): the pure aggregation / classification logic is unit-tested
/// elsewhere (`revenue_analytics_report_exporter_test.dart`,
/// `booking_activity_classifier_test.dart`); here we lock the screen-level
/// wiring so a future refactor cannot silently regress the feature.
void main() {
  // Run from the project root (flutter test sets the CWD to the package root).
  final revenueScreen = File(
          'lib/features/hunter_mode/screens/outfitter_revenue_screen.dart')
      .readAsStringSync();
  final analyticsService = File(
          'lib/features/hunter_mode/services/outfitter_analytics_service.dart')
      .readAsStringSync();
  final marketplaceScreen = File(
          'lib/features/hunter_mode/screens/hunter_package_marketplace_screen.dart')
      .readAsStringSync();

  group('Task 1 -- Income per Farm on the Enterprise BI screen', () {
    test('the combined analytics stream yields a farmRevenue payload', () {
      expect(revenueScreen.contains("_getFarmRevenueData"), isTrue);
      expect(revenueScreen.contains("'farmRevenue': farmRevenueData"), isTrue);
    });

    test('the farm revenue data method aggregates earned bookings per farm', () {
      expect(
        revenueScreen.contains(".where('outfitterId', isEqualTo: uid)"),
        isTrue,
      );
      expect(
        revenueScreen.contains('RevenueAnalyticsReportExporter.aggregateFarmRevenue'),
        isTrue,
        reason:
            'the on-screen card and the PDF export must share one aggregation',
      );
      expect(
        revenueScreen.contains('OutfitterAnalyticsService.earnedBookingStatuses'),
        isTrue,
        reason: 'only payment-verified (earned) bookings count toward income',
      );
    });

    test('the Income per Farm section renders below the species breakdown', () {
      final speciesIdx = revenueScreen.indexOf('Species Revenue Breakdown');
      final farmIdx = revenueScreen.indexOf('Income per Farm');
      expect(speciesIdx, greaterThan(-1));
      expect(farmIdx, greaterThan(-1));
      expect(farmIdx, greaterThan(speciesIdx),
          reason:
              'the farm breakdown belongs alongside/below the species section');
    });

    test('the Income per Farm section renders one row per farm with revenue', () {
      expect(revenueScreen.contains('_FarmRevenueRow'), isTrue);
      expect(revenueScreen.contains('earned booking'), isTrue);
    });
  });

  group('Task 2 -- town name on the Package Marketplace card', () {
    test('the package stream resolves a town (package/farm town -> district)',
        () {
      expect(
        analyticsService.contains("packageData['town'] as String? ??"),
        isTrue,
      );
      expect(
        analyticsService.contains("farmData?['town'] as String? ??"),
        isTrue,
      );
      expect(analyticsService.contains("'town': packageTown"), isTrue);
    });

    test('the package card receives and renders the town below the title', () {
      expect(marketplaceScreen.contains("packageData['town'] as String?"), isTrue);
      expect(marketplaceScreen.contains('required this.town'), isTrue);
      expect(marketplaceScreen.contains('if (town.isNotEmpty)'), isTrue);
      // The town row must sit directly below the title Text in the card's
      // build method (search AFTER the title style so the constructor's
      // `required this.town` field does not satisfy the check).
      final cardSrc = marketplaceScreen.substring(
        marketplaceScreen.indexOf('class _PackageCard'),
      );
      final titleIdx = cardSrc.indexOf('fontSize: 16');
      expect(titleIdx, greaterThan(-1));
      final townIdx = cardSrc.indexOf('town,', titleIdx);
      expect(townIdx, greaterThan(-1),
          reason: 'the town Text must render directly below the title');
    });
  });

  group('Task 3 -- My Bookings active vs Past Hunts archive', () {
    test('the marketplace has three tabs incl. Past Hunts', () {
      expect(marketplaceScreen.contains('TabController(length: 3'), isTrue);
      expect(marketplaceScreen.contains('🗂 Past Hunts'), isTrue);
      expect(marketplaceScreen.contains('📋 My Bookings'), isTrue);
    });

    test('the bookings list filters via BookingActivityClassifier', () {
      expect(
        marketplaceScreen.contains('BookingActivityClassifier.isPastHunt'),
        isTrue,
      );
      expect(
        marketplaceScreen.contains('pastOnly ? isPast : !isPast'),
        isTrue,
        reason: 'My Bookings shows only active/upcoming hunts; Past Hunts '
            'shows the archived complement',
      );
    });

    test('the two booking tabs pass the pastOnly flag', () {
      expect(
        marketplaceScreen.contains('_buildMyBookingsTab(theme, pastOnly: false)'),
        isTrue,
      );
      expect(
        marketplaceScreen.contains('_buildMyBookingsTab(theme, pastOnly: true)'),
        isTrue,
      );
    });
  });

  group('Task 4 -- optic history ownerId alias rules', () {
    final rules = File('firestore.rules').readAsStringSync();

    test('optic_logs read accepts both userId and ownerId aliases', () {
      final blockStart = rules.indexOf('match /optic_logs/{logId}');
      expect(blockStart, greaterThan(-1));
      final block = rules.substring(blockStart, blockStart + 700);
      expect(block.contains("isOwnerOf('userId')"), isTrue);
      expect(block.contains("isOwnerOf('ownerId')"), isTrue);
    });
  });
}
