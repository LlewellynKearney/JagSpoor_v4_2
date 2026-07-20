import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Per-province hunting regulation notes for a species.
class ProvincialRegulation {
  final String province;
  final String regulation;

  const ProvincialRegulation({
    required this.province,
    required this.regulation,
  });

  factory ProvincialRegulation.fromJson(Map<String, dynamic> json) {
    return ProvincialRegulation(
      province: json['province'] as String? ?? '',
      regulation: json['regulation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'province': province,
    'regulation': regulation,
  };
}

/// South African game species profile stored in Firestore `animals` collection.
class Animal {
  final String id;
  final String name;
  final String scientificName;
  final String? afrikaansName;
  final String category;
  final List<String> regions;
  final String habitat;
  final String? huntingNotes;
  final String? recommendedCaliber;
  final String? trophyMinimumRW;
  final String? rolandWardMinimum;
  final String? rwMinimum;
  final double? earLength;
  final String? rwMeasurementMethod;
  final String? rwHornDescription;
  final String? shotPlacementTip;
  final double? weightMinKg;
  final double? weightMaxKg;
  final String imageUrl;
  final String? thumbnailUrl;
  final String? heroImageUrl;
  final List<String> galleryUrls;
  final List<ProvincialRegulation> provincialRegulations;
  final List<String> searchKeywords;
  final int sortOrder;
  final DateTime? updatedAt;
  final String? waterDependence;
  final String? primaryDiet;
  final String? ruttingMonths;
  final String? lambingMonths;
  final String? socialStructure;
  final int? longevityYears;
  final int? shoulderHeightMm;

  const Animal({
    required this.id,
    required this.name,
    required this.scientificName,
    this.afrikaansName,
    required this.category,
    this.regions = const [],
    required this.habitat,
    this.huntingNotes,
    this.recommendedCaliber,
    this.trophyMinimumRW,
    this.rolandWardMinimum,
    this.rwMinimum,
    this.earLength,
    this.rwMeasurementMethod,
    this.rwHornDescription,
    this.shotPlacementTip,
    this.weightMinKg,
    this.weightMaxKg,
    required this.imageUrl,
    this.thumbnailUrl,
    this.heroImageUrl,
    this.galleryUrls = const [],
    this.provincialRegulations = const [],
    this.searchKeywords = const [],
    this.sortOrder = 0,
    this.updatedAt,
    this.waterDependence,
    this.primaryDiet,
    this.ruttingMonths,
    this.lambingMonths,
    this.socialStructure,
    this.longevityYears,
    this.shoulderHeightMm,
  });

  factory Animal.fromJson(Map<String, dynamic> json, {String? id}) {
    final resolvedId = id ?? json['id'] as String? ?? '';
    final hero = json['heroImageUrl'] as String?;
    final thumb = json['thumbnailUrl'] as String?;
    final primary = json['imageUrl'] as String? ?? hero ?? thumb ?? '';

    return Animal(
      id: resolvedId,
      name: json['name'] as String? ?? json['commonName'] as String? ?? '',
      scientificName: json['scientificName'] as String? ?? '',
      afrikaansName: json['afrikaansName'] as String?,
      category: json['category'] as String? ?? 'other',
      regions: _stringList(json['regions']),
      habitat: json['habitat'] as String? ?? '',
      huntingNotes: json['huntingNotes'] as String?,
      recommendedCaliber: json['recommendedCaliber'] as String?,
      trophyMinimumRW:
          json['trophyMinimumRW'] as String? ?? json['trophyMin'] as String?,
      rolandWardMinimum:
          json['rolandWardMinimum'] as String? ??
          json['trophyMinimumRW'] as String? ??
          json['trophyMin'] as String?,
      rwMinimum:
          json['rwMinimum'] as String? ??
          json['rolandWardMinimum'] as String? ??
          json['trophyMinimumRW'] as String? ??
          json['trophyMin'] as String?,
      earLength: _doubleOrNull(json['earLength']),
      rwMeasurementMethod: json['rwMeasurementMethod'] as String?,
      rwHornDescription: json['rwHornDescription'] as String?,
      shotPlacementTip: json['shotPlacementTip'] as String?,
      weightMinKg: _doubleOrNull(json['weightMinKg']),
      weightMaxKg: _doubleOrNull(json['weightMaxKg']),
      imageUrl: primary,
      thumbnailUrl: thumb,
      heroImageUrl: hero,
      galleryUrls: _stringList(json['galleryUrls']),
      provincialRegulations: _provincialRegulations(
        json['provincialRegulations'],
      ),
      searchKeywords: _stringList(json['searchKeywords']),
      sortOrder: _intOrZero(json['sortOrder']),
      updatedAt: _dateTimeOrNull(json['updatedAt']),
      waterDependence: json['waterDependence'] as String?,
      primaryDiet: json['primaryDiet'] as String?,
      ruttingMonths: json['ruttingMonths'] as String?,
      lambingMonths: json['lambingMonths'] as String?,
      socialStructure: json['socialStructure'] as String?,
      longevityYears: _intOrNull(json['longevityYears']),
      shoulderHeightMm: _intOrNull(json['shoulderHeightMm']),
    );
  }

  factory Animal.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      debugPrint(
        'Animal document ${doc.id} has no data, returning default animal',
      );
      return Animal(
        id: doc.id,
        name: 'Unknown Animal',
        scientificName: '',
        category: 'other',
        habitat: '',
        imageUrl: '',
      );
    }
    try {
      return Animal.fromJson(data, id: doc.id);
    } catch (e) {
      debugPrint(
        'Error parsing animal ${doc.id}: $e, returning default animal',
      );
      return Animal(
        id: doc.id,
        name:
            data['name'] as String? ??
            data['commonName'] as String? ??
            'Unknown Animal',
        scientificName: data['scientificName'] as String? ?? '',
        category: data['category'] as String? ?? 'other',
        habitat: data['habitat'] as String? ?? '',
        imageUrl: data['imageUrl'] as String? ?? '',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'commonName': name,
    'name': name,
    'scientificName': scientificName,
    if (afrikaansName != null) 'afrikaansName': afrikaansName,
    'category': category,
    'regions': regions,
    'habitat': habitat,
    if (huntingNotes != null) 'huntingNotes': huntingNotes,
    if (recommendedCaliber != null) 'recommendedCaliber': recommendedCaliber,
    if (trophyMinimumRW != null) 'trophyMin': trophyMinimumRW,
    if (trophyMinimumRW != null) 'trophyMinimumRW': trophyMinimumRW,
    if (rolandWardMinimum != null) 'rolandWardMinimum': rolandWardMinimum,
    if (rwMinimum != null) 'rwMinimum': rwMinimum,
    if (earLength != null) 'earLength': earLength,
    if (rwMeasurementMethod != null) 'rwMeasurementMethod': rwMeasurementMethod,
    if (rwHornDescription != null) 'rwHornDescription': rwHornDescription,
    if (shotPlacementTip != null) 'shotPlacementTip': shotPlacementTip,
    if (weightMinKg != null) 'weightMinKg': weightMinKg,
    if (weightMaxKg != null) 'weightMaxKg': weightMaxKg,
    'imageUrl': imageUrl,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    if (heroImageUrl != null) 'heroImageUrl': heroImageUrl,
    'galleryUrls': galleryUrls,
    'provincialRegulations': provincialRegulations
        .map((r) => r.toJson())
        .toList(),
    'searchKeywords': searchKeywords,
    'sortOrder': sortOrder,
    if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    if (waterDependence != null) 'waterDependence': waterDependence,
    if (primaryDiet != null) 'primaryDiet': primaryDiet,
    if (ruttingMonths != null) 'ruttingMonths': ruttingMonths,
    if (lambingMonths != null) 'lambingMonths': lambingMonths,
    if (socialStructure != null) 'socialStructure': socialStructure,
    if (longevityYears != null) 'longevityYears': longevityYears,
    if (shoulderHeightMm != null) 'shoulderHeightMm': shoulderHeightMm,
  };

  /// Typical live weight range for display, e.g. "40–65 kg".
  String? get displayWeightRange {
    if (weightMinKg == null && weightMaxKg == null) return null;
    if (weightMinKg != null && weightMaxKg != null) {
      return '${weightMinKg!.toStringAsFixed(0)}–${weightMaxKg!.toStringAsFixed(0)} kg';
    }
    final single = weightMinKg ?? weightMaxKg;
    return '${single!.toStringAsFixed(0)} kg';
  }

  /// All remote image URLs for prefetch / offline cache warming.
  List<String> get allImageUrls {
    final urls = <String>{imageUrl};
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      urls.add(thumbnailUrl!);
    }
    if (heroImageUrl != null && heroImageUrl!.isNotEmpty) {
      urls.add(heroImageUrl!);
    }
    urls.addAll(galleryUrls.where((u) => u.isNotEmpty));
    return urls.toList();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).toList();
  }

  static List<ProvincialRegulation> _provincialRegulations(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => ProvincialRegulation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static double? _doubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int _intOrZero(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
