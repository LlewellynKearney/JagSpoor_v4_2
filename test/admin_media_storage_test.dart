import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/features/admin/services/media_storage_analytics.dart';
import 'package:jagspoor/features/admin/services/usage_analytics_service.dart';
import 'package:jagspoor/features/admin/widgets/media_storage_charts.dart';
import 'package:jagspoor/features/auth/services/user_role_provider.dart';

/// Admin portal — media/storage analytics aggregator + service, feature-usage
/// breakdown math, and the fl_chart visual components.
void main() {
  // Pin the FieldValue platform before any production `FieldValue` is
  // realized (mirrors the optic_log_service_test pattern).
  FakeFirebaseFirestore();

  final now = DateTime(2026, 8, 20, 15, 30);

  Map<String, dynamic> docAt(DateTime date, List<String> photos) => {
        'createdAt': Timestamp.fromDate(date),
        'imageUrls': photos,
      };

  group('MediaStorageAggregator.countPhotos', () {
    test('counts array entries + non-empty string fields', () {
      final count = MediaStorageAggregator.countPhotos(
        const {
          'imageUrls': ['a.jpg', 'b.jpg'],
          'photoUrl': 'c.jpg',
        },
        arrayFields: const ['imageUrls'],
        stringFields: const ['photoUrl'],
      );
      expect(count, 3);
    });

    test('ignores blank entries and non-string items', () {
      final count = MediaStorageAggregator.countPhotos(
        const {
          'photos': ['a.jpg', '', '   ', 42, null],
        },
        arrayFields: const ['photos'],
      );
      expect(count, 1);
    });

    test('missing fields count as zero', () {
      expect(
        MediaStorageAggregator.countPhotos(const {},
            arrayFields: const ['imageUrls'], stringFields: const ['photoUrl']),
        0,
      );
    });
  });

  group('MediaStorageAggregator.dateFromDoc', () {
    test('resolves Timestamp, ISO string, DateTime, and millis', () {
      final ts = DateTime(2026, 8, 19);
      expect(
        MediaStorageAggregator.dateFromDoc(
            {'createdAt': Timestamp.fromDate(ts)}, const ['createdAt']),
        ts,
      );
      expect(
        MediaStorageAggregator.dateFromDoc(
            {'createdAt': '2026-08-19T10:00:00.000'}, const ['createdAt']),
        DateTime.parse('2026-08-19T10:00:00.000'),
      );
      expect(
        MediaStorageAggregator.dateFromDoc(
            {'createdAt': ts}, const ['createdAt']),
        ts,
      );
      expect(
        MediaStorageAggregator.dateFromDoc(
            {'createdAt': ts.millisecondsSinceEpoch}, const ['createdAt']),
        DateTime.fromMillisecondsSinceEpoch(ts.millisecondsSinceEpoch),
      );
    });

    test('falls back through the date-field list and nulls when absent', () {
      final ts = DateTime(2026, 8, 19);
      expect(
        MediaStorageAggregator.dateFromDoc(
            {'lastUpdated': Timestamp.fromDate(ts)},
            const ['createdAt', 'lastUpdated']),
        ts,
      );
      expect(
        MediaStorageAggregator.dateFromDoc(const {}, const ['createdAt']),
        isNull,
      );
      expect(
        MediaStorageAggregator.dateFromDoc(
            {'createdAt': 'not-a-date'}, const ['createdAt']),
        isNull,
      );
    });
  });

  group('MediaStorageAggregator.estimateFootprintBytes', () {
    test('scales linearly by the average photo size', () {
      expect(MediaStorageAggregator.estimateFootprintBytes(4),
          4 * MediaStorageAggregator.averagePhotoBytes);
      expect(MediaStorageAggregator.estimateFootprintBytes(0), 0);
      expect(MediaStorageAggregator.estimateFootprintBytes(-3), 0);
    });
  });

  group('MediaStorageAggregator.aggregate', () {
    Map<String, List<String>> arraysFor(Set<String> keys) => {
          for (final k in keys) k: const ['imageUrls'],
        };
    Map<String, List<String>> datesFor(Set<String> keys) => {
          for (final k in keys) k: const ['createdAt'],
        };

    test('counts photos per collection and totals', () {
      final analytics = MediaStorageAggregator.aggregate(
        {
          'packages': [docAt(now, const ['a', 'b']), docAt(now, const ['c'])],
          'trophies': [docAt(now, const ['d'])],
        },
        collectionLabels: const {'packages': 'Packages', 'trophies': 'Trophies'},
        arrayFields: arraysFor({'packages', 'trophies'}),
        stringFields: const {'packages': [], 'trophies': []},
        dateFields: datesFor({'packages', 'trophies'}),
        now: now,
      );
      expect(analytics.totalPhotos, 4);
      expect(analytics.totalDocsWithPhotos, 3);
      final packages = analytics.byCollection.firstWhere(
          (c) => c.key == 'packages');
      expect(packages.photoCount, 3);
      expect(packages.docsWithPhotos, 2);
      expect(packages.docCount, 2);
    });

    test('builds a zero-filled daily trend across the window', () {
      final analytics = MediaStorageAggregator.aggregate(
        {
          'packages': [
            docAt(now, const ['a', 'b']), // today
            docAt(now.subtract(const Duration(days: 2)), const ['c']),
          ],
        },
        collectionLabels: const {'packages': 'Packages'},
        arrayFields: arraysFor({'packages'}),
        stringFields: const {'packages': []},
        dateFields: datesFor({'packages'}),
        now: now,
        trendDays: 7,
      );
      expect(analytics.dailyTrend, hasLength(7));
      expect(analytics.dailyTrend.last.count, 2);
      expect(analytics.dailyTrend[4].count, 1); // 2 days ago
      expect(
          analytics.dailyTrend.where((p) => p.count == 0).length, 5);
      // Oldest → newest chronological order.
      expect(analytics.dailyTrend.first.day.isBefore(analytics.dailyTrend.last.day),
          isTrue);
    });

    test('excludes out-of-window docs from the trend but not the totals', () {
      final analytics = MediaStorageAggregator.aggregate(
        {
          'packages': [
            docAt(now.subtract(const Duration(days: 30)), const ['old']),
            docAt(now, const ['new']),
          ],
        },
        collectionLabels: const {'packages': 'Packages'},
        arrayFields: arraysFor({'packages'}),
        stringFields: const {'packages': []},
        dateFields: datesFor({'packages'}),
        now: now,
        trendDays: 14,
      );
      expect(analytics.totalPhotos, 2);
      expect(analytics.dailyTrend.last.count, 1);
      expect(analytics.dailyTrend.fold(0, (acc, p) => acc + p.count), 1);
    });

    test('docs without a resolvable date count in totals, not the trend', () {
      final analytics = MediaStorageAggregator.aggregate(
        {
          'packages': [
            const {'imageUrls': ['a']}, // no createdAt
            docAt(now, const ['b']),
          ],
        },
        collectionLabels: const {'packages': 'Packages'},
        arrayFields: arraysFor({'packages'}),
        stringFields: const {'packages': []},
        dateFields: datesFor({'packages'}),
        now: now,
      );
      expect(analytics.totalPhotos, 2);
      expect(analytics.dailyTrend.fold(0, (acc, p) => acc + p.count), 1);
    });

    test('estimatedFootprintMb derives from the total photo count', () {
      final analytics = MediaStorageAggregator.aggregate(
        {
          'packages': [docAt(now, const ['a', 'b'])],
        },
        collectionLabels: const {'packages': 'Packages'},
        arrayFields: arraysFor({'packages'}),
        stringFields: const {'packages': []},
        dateFields: datesFor({'packages'}),
        now: now,
      );
      expect(
        analytics.estimatedFootprintMb,
        closeTo(2 * MediaStorageAggregator.averagePhotoBytes / (1024 * 1024),
            0.0001),
      );
    });
  });

  group('MediaStorageAnalyticsService (FakeFirebaseFirestore)', () {
    setUp(() {
      MediaStorageAnalyticsService.firestoreForTesting =
          FakeFirebaseFirestore();
    });
    tearDown(() {
      MediaStorageAnalyticsService.firestoreForTesting = null;
    });

    test('aggregates across the platform media collections', () async {
      final fake = MediaStorageAnalyticsService.firestoreForTesting!;
      await fake.collection('packages').add({
        'imageUrls': ['pkg1.jpg', 'pkg2.jpg'],
        'createdAt': Timestamp.fromDate(now),
      });
      await fake.collection('trophy_stock').add({
        'trophyPhotoUrls': ['ts1.jpg'],
        'lastUpdated': Timestamp.fromDate(now),
      });
      await fake.collection('users').add({'profileImageUrl': 'me.jpg'});
      final analytics =
          await MediaStorageAnalyticsService.instance.fetch(now: now);
      expect(analytics.totalPhotos, 4);
      expect(
          analytics.byCollection.map((c) => c.key),
          containsAll(
              ['packages', 'trophy_stock', 'trophies', 'bug_reports', 'farms', 'users']));
      expect(
          analytics.byCollection
              .firstWhere((c) => c.key == 'trophy_stock')
              .photoCount,
          1);
      expect(
          analytics.byCollection
              .firstWhere((c) => c.key == 'users')
              .photoCount,
          1);
      expect(analytics.dailyTrend, hasLength(14));
      expect(analytics.dailyTrend.last.count, 3); // dated today
    });

    test('an unseeded collection degrades to an empty bucket', () async {
      final fake = MediaStorageAnalyticsService.firestoreForTesting!;
      await fake.collection('packages').add({
        'imageUrls': ['pkg.jpg'],
        'createdAt': Timestamp.fromDate(now),
      });
      final analytics =
          await MediaStorageAnalyticsService.instance.fetch(now: now);
      expect(analytics.totalPhotos, 1);
      expect(
          analytics.byCollection
              .firstWhere((c) => c.key == 'farms')
              .photoCount,
          0);
    });
  });

  group('Feature usage breakdown math (balanced counts + percentages)', () {
    const summary = RoleUsageSummary(
      role: AppRole.hunter,
      featureCounts: {
        'A': 10,
        'B': 7,
        'C': 5,
        'D': 4,
        'E': 3,
        'F': 2,
        'G': 1,
      },
    );

    test('counts balance exactly with the role total', () {
      final entries = summary.breakdown(limit: 5);
      expect(entries.map((e) => e.name),
          ['A', 'B', 'C', 'D', 'E', UsageBreakdownEntry.otherName]);
      expect(entries.fold(0, (acc, e) => acc + e.count), summary.total);
    });

    test('the Other row accounts for every remaining action', () {
      final other = summary
          .breakdown(limit: 5)
          .firstWhere((e) => e.name == UsageBreakdownEntry.otherName);
      expect(other.count, 3); // F + G = 2 + 1
      expect(other.percent, closeTo(3 / 32 * 100, 0.0001));
    });

    test('percentages sum to 100', () {
      final entries = summary.breakdown(limit: 5);
      final totalPercent = entries.fold(0.0, (acc, e) => acc + e.percent);
      expect(totalPercent, closeTo(100.0, 0.0001));
    });

    test('no Other row when all features fit the limit', () {
      const small = RoleUsageSummary(
        role: AppRole.outfitter,
        featureCounts: {'A': 3, 'B': 1},
      );
      final entries = small.breakdown(limit: 5);
      expect(entries, hasLength(2));
      expect(
          entries.any((e) => e.name == UsageBreakdownEntry.otherName), isFalse);
      expect(entries.fold(0, (acc, e) => acc + e.count), small.total);
    });

    test('empty totals yield an empty breakdown and zero percentages', () {
      const empty = RoleUsageSummary(role: AppRole.hunter, featureCounts: {});
      expect(empty.breakdown(), isEmpty);
      expect(empty.percentageOf('Anything'), 0.0);
    });
  });

  group('Media & storage chart widgets', () {
    testWidgets('PhotoUploadTrendBarChart renders without exceptions',
        (tester) async {
      final theme = ThemeController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PhotoUploadTrendBarChart(
            theme: theme,
            points: [
              for (var i = 0; i < 14; i++)
                PhotoUploadPoint(
                  day: DateTime(2026, 8, 7).add(Duration(days: i)),
                  count: i % 4,
                ),
            ],
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('StorageFootprintPieChart renders sections + legend',
        (tester) async {
      final theme = ThemeController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StorageFootprintPieChart(
            theme: theme,
            byCollection: const [
              CollectionPhotoCount(
                  key: 'packages',
                  label: 'Packages',
                  photoCount: 8,
                  docsWithPhotos: 3,
                  docCount: 5),
              CollectionPhotoCount(
                  key: 'users',
                  label: 'Profiles',
                  photoCount: 2,
                  docsWithPhotos: 2,
                  docCount: 4),
            ],
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Packages'), findsOneWidget);
      expect(find.text('Profiles'), findsOneWidget);
    });

    testWidgets('StorageFootprintPieChart renders an empty state',
        (tester) async {
      final theme = ThemeController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StorageFootprintPieChart(
            theme: theme,
            byCollection: const [],
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('No photo uploads recorded yet.'), findsOneWidget);
    });
  });

  group('Admin dashboard media section wiring contract', () {
    final src = File('lib/features/admin/screens/admin_dashboard_screen.dart')
        .readAsStringSync();

    test('renders the Media & Storage section with both charts', () {
      expect(src.contains("Media & Storage"), isTrue);
      expect(src.contains('_buildMediaStorageSection'), isTrue);
      expect(src.contains('PhotoUploadTrendBarChart'), isTrue);
      expect(src.contains('StorageFootprintPieChart'), isTrue);
      expect(src.contains('MediaStorageAnalyticsService.instance.fetch()'),
          isTrue);
    });

    test('feature usage card uses the balanced breakdown', () {
      expect(src.contains('summary.breakdown(limit: 5)'), isTrue);
      expect(src.contains('UsageBreakdownEntry.otherName'), isTrue);
      expect(src.contains('100.0%'), isTrue);
    });
  });
}
