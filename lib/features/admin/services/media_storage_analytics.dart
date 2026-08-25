import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../hunter_mode/services/outfitter_enterprise_manager.dart';

/// Photo uploads recorded on a single calendar day (local midnight).
class PhotoUploadPoint {
  final DateTime day;
  final int count;

  const PhotoUploadPoint({required this.day, required this.count});
}

/// Photo-document stats for one Firestore collection.
class CollectionPhotoCount {
  /// Stable key (the Firestore collection name).
  final String key;

  /// Human label for the chart legend.
  final String label;

  /// Total photo URLs found across the sampled documents.
  final int photoCount;

  /// Documents that carry at least one photo.
  final int docsWithPhotos;

  /// Total sampled documents (photo-carrying or not).
  final int docCount;

  const CollectionPhotoCount({
    required this.key,
    required this.label,
    required this.photoCount,
    required this.docsWithPhotos,
    required this.docCount,
  });
}

/// Platform-wide media/storage analytics bundle for the Admin portal.
class MediaStorageAnalytics {
  /// Daily photo-upload counts, oldest → newest, one entry per day in the
  /// trend window (zero-filled).
  final List<PhotoUploadPoint> dailyTrend;

  /// Per-collection photo stats (fixed registry order).
  final List<CollectionPhotoCount> byCollection;

  const MediaStorageAnalytics({
    required this.dailyTrend,
    required this.byCollection,
  });

  int get totalPhotos =>
      byCollection.fold(0, (acc, c) => acc + c.photoCount);

  int get totalDocsWithPhotos =>
      byCollection.fold(0, (acc, c) => acc + c.docsWithPhotos);

  /// Estimated Firebase Storage footprint in megabytes.
  double get estimatedFootprintMb =>
      MediaStorageAggregator.estimateFootprintBytes(totalPhotos) / (1024 * 1024);
}

/// Pure, dependency-free aggregation of photo-carrying Firestore documents
/// into the Admin media/storage analytics bundle. Unit-testable without a
/// Firestore emulator.
class MediaStorageAggregator {
  MediaStorageAggregator._();

  /// Assumed average bytes per uploaded photo. Every upload pipeline in the
  /// app compresses through `ImageService.compressExisting` (1280 px, JPEG
  /// q75–85), which lands ~250 KB per image; the Firestore documents only
  /// store the download URLs, so the true byte size is unknown client-side
  /// and this documented constant is the footprint estimator.
  static const int averagePhotoBytes = 250 * 1024;

  /// Estimated storage footprint (bytes) for [photoCount] photos.
  static int estimateFootprintBytes(int photoCount) =>
      photoCount < 0 ? 0 : photoCount * averagePhotoBytes;

  /// Counts the photo URLs carried by one document: every entry of the given
  /// array fields plus each non-empty string field.
  static int countPhotos(
    Map<String, dynamic> doc, {
    List<String> arrayFields = const [],
    List<String> stringFields = const [],
  }) {
    var count = 0;
    for (final field in arrayFields) {
      final value = doc[field];
      if (value is List) {
        count += value.whereType<String>().where((s) => s.trim().isNotEmpty).length;
      }
    }
    for (final field in stringFields) {
      final value = doc[field];
      if (value is String && value.trim().isNotEmpty) count += 1;
    }
    return count;
  }

  /// Resolves the document's creation/upload date from the first present
  /// date field. Tolerates Firestore [Timestamp], ISO string, [DateTime],
  /// and milliseconds-since-epoch. Returns null when unresolvable (the doc
  /// is excluded from the trend, but still counted in the totals).
  static DateTime? dateFromDoc(
    Map<String, dynamic> doc,
    List<String> dateFields,
  ) {
    for (final field in dateFields) {
      final value = doc[field];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
    }
    return null;
  }

  /// Aggregates sampled documents per collection into the analytics bundle.
  ///
  /// [docsByCollection] maps a collection key to its sampled documents.
  /// [collectionLabels] maps a collection key to its display label. [now]
  /// anchors the trend window (the most recent [trendDays] days, inclusive
  /// of today), zero-filled so the chart always renders a stable width.
  static MediaStorageAnalytics aggregate(
    Map<String, List<Map<String, dynamic>>> docsByCollection, {
    required Map<String, String> collectionLabels,
    required Map<String, List<String>> arrayFields,
    required Map<String, List<String>> stringFields,
    required Map<String, List<String>> dateFields,
    required DateTime now,
    int trendDays = 14,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final buckets = List<int>.filled(trendDays, 0);

    final counts = <CollectionPhotoCount>[];
    for (final entry in docsByCollection.entries) {
      final key = entry.key;
      final docs = entry.value;
      var photoCount = 0;
      var docsWithPhotos = 0;
      for (final doc in docs) {
        final photos = countPhotos(
          doc,
          arrayFields: arrayFields[key] ?? const [],
          stringFields: stringFields[key] ?? const [],
        );
        photoCount += photos;
        if (photos > 0) docsWithPhotos += 1;
        if (photos > 0) {
          final date = dateFromDoc(doc, dateFields[key] ?? const []);
          if (date != null) {
            final day = DateTime(date.year, date.month, date.day);
            final index = trendDays - 1 - today.difference(day).inDays;
            if (index >= 0 && index < trendDays) buckets[index] += photos;
          }
        }
      }
      counts.add(CollectionPhotoCount(
        key: key,
        label: collectionLabels[key] ?? key,
        photoCount: photoCount,
        docsWithPhotos: docsWithPhotos,
        docCount: docs.length,
      ));
    }

    final trend = <PhotoUploadPoint>[
      for (var i = 0; i < trendDays; i++)
        PhotoUploadPoint(
          day: today.subtract(Duration(days: trendDays - 1 - i)),
          count: buckets[i],
        ),
    ];

    return MediaStorageAnalytics(dailyTrend: trend, byCollection: counts);
  }
}

/// Reads photo-carrying documents across the platform's media collections
/// and aggregates them into the Admin media/storage analytics bundle.
///
/// Every Firestore query is individually best-effort: a PERMISSION_DENIED /
/// missing index on one collection contributes an empty bucket so the Admin
/// dashboard section still renders the remaining collections.
class MediaStorageAnalyticsService {
  MediaStorageAnalyticsService._();
  static final MediaStorageAnalyticsService instance =
      MediaStorageAnalyticsService._();

  /// Test seam: inject a fake Firestore (e.g. `FakeFirebaseFirestore`).
  @visibleForTesting
  static FirebaseFirestore? firestoreForTesting;

  FirebaseFirestore get _db => firestoreForTesting ?? FirebaseFirestore.instance;

  /// Collection key → display label.
  static const Map<String, String> collectionLabels = {
    'packages': 'Packages',
    OutfitterEnterpriseManager.trophyStockCollection: 'Trophy Stock',
    'trophies': 'Hunter Trophies',
    'bug_reports': 'Bug Reports',
    'farms': 'Farms',
    'users': 'Profiles',
  };

  /// Collection key → photo URL array fields.
  static const Map<String, List<String>> arrayFields = {
    'packages': ['imageUrls'],
    OutfitterEnterpriseManager.trophyStockCollection: ['trophyPhotoUrls'],
    'trophies': ['photos'],
    'bug_reports': ['screenshotUrls'],
    'farms': ['photoUrls'],
    'users': [],
  };

  /// Collection key → single-photo URL string fields.
  static const Map<String, List<String>> stringFields = {
    'packages': [],
    OutfitterEnterpriseManager.trophyStockCollection: [],
    'trophies': [],
    'bug_reports': [],
    'farms': ['photoUrl'],
    'users': ['profileImageUrl'],
  };

  /// Collection key → date fields (first present wins).
  static const Map<String, List<String>> dateFields = {
    'packages': ['createdAt'],
    OutfitterEnterpriseManager.trophyStockCollection: ['createdAt', 'lastUpdated'],
    'trophies': ['createdAt'],
    'bug_reports': ['timestamp', 'createdAt'],
    'farms': ['createdAt'],
    'users': ['createdAt'],
  };

  Future<List<Map<String, dynamic>>> _fetchCollection(String key,
      {required int limit}) async {
    try {
      final snap = await _db.collection(key).limit(limit).get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Aggregates photo upload volume + storage footprint across all media
  /// collections. Bounded to [limit] documents per collection so the
  /// dashboard stays responsive.
  Future<MediaStorageAnalytics> fetch({
    int limit = 500,
    int trendDays = 14,
    DateTime? now,
  }) async {
    final docsByCollection = <String, List<Map<String, dynamic>>>{};
    await Future.wait(collectionLabels.keys.map((key) async {
      docsByCollection[key] = await _fetchCollection(key, limit: limit);
    }));
    return MediaStorageAggregator.aggregate(
      docsByCollection,
      collectionLabels: collectionLabels,
      arrayFields: arrayFields,
      stringFields: stringFields,
      dateFields: dateFields,
      now: now ?? DateTime.now(),
      trendDays: trendDays,
    );
  }
}
