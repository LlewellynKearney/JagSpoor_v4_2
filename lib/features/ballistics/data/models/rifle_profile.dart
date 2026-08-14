import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'optic_profile.dart';

/// Represents a rifle profile from the Digital Firearm Safe.
class RifleProfile {
  final String id;
  final String name;
  final String caliber;
  final double scopeClickValue;
  final String serialNumber;
  final String ownerId;

  /// Manufacturer / brand as stored in the Digital Firearm Safe (the manual
  /// firearm form persists `make`; legacy optics-only docs may omit it).
  /// Used to render the optic-link dropdown as "make model (calibre)".
  final String make;

  /// Model designation as stored in the Digital Firearm Safe. Used together
  /// with [make] to render the optic-link dropdown label.
  final String model;

  /// Barrel length as stored in the Digital Firearm Safe (free-text, e.g.
  /// '16"' or '406 mm'). Used to auto-populate scope-calibration specs when
  /// a firearm is linked. Empty on legacy firearm documents.
  final String barrelLength;

  /// Linked optic specification (tube diameter, HOB, turret units, focal
  /// plane, reticle, etc.). May be null on legacy firearm documents.
  final OpticProfile? optic;

  const RifleProfile({
    required this.id,
    required this.name,
    required this.caliber,
    this.scopeClickValue = 0.25,
    this.serialNumber = '',
    this.ownerId = '',
    this.make = '',
    this.model = '',
    this.barrelLength = '',
    this.optic,
  });

  factory RifleProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      debugPrint('RifleProfile document ${doc.id} has no data');
      return RifleProfile(id: doc.id, name: 'Unknown Rifle', caliber: '');
    }
    return RifleProfile.fromJson(data, id: doc.id);
  }

  factory RifleProfile.fromJson(Map<String, dynamic> json, {String? id}) {
    OpticProfile? optic;
    final opticData = json['optic'];
    if (opticData is Map) {
      optic = OpticProfile.fromJson(
        opticData.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final clickValue = _doubleOrDefault(json['scopeClickValue']);
    return RifleProfile(
      id: id ?? (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      caliber: (json['caliber'] as String?) ??
          (json['calibre'] as String?) ??
          '',
      scopeClickValue: clickValue,
      serialNumber: (json['serialNumber'] as String?) ??
          (json['serial'] as String?) ??
          '',
      ownerId: (json['ownerId'] as String?) ?? '',
      make: (json['make'] as String?) ??
          (json['brand'] as String?) ??
          (json['manufacturer'] as String?) ??
          '',
      model: (json['model'] as String?) ??
          (json['modelName'] as String?) ??
          '',
      barrelLength: (json['barrelLength'] as String?) ?? '',
      optic: optic,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'caliber': caliber,
        'scopeClickValue': scopeClickValue,
        'serialNumber': serialNumber,
        'ownerId': ownerId,
        'make': make,
        'model': model,
        'barrelLength': barrelLength,
        if (optic != null) 'optic': optic!.toJson(),
      };

  Map<String, dynamic> toFirestore() => toJson();

  static double _doubleOrDefault(dynamic value) {
    if (value == null) return 0.25;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.25;
    return 0.25;
  }

  /// Human-readable label for the optic-link dropdown, formatted as
  /// "make model (calibre)" per the Optical Suite spec. Falls back to
  /// [name] then to a generic "Unnamed firearm" when make/model are absent
  /// (legacy docs), and renders an em-dash when calibre is unknown so the
  /// parentheses are never empty.
  String get displayName {
    final makeModel = [make, model].where((s) => s.isNotEmpty).join(' ');
    final base = makeModel.isNotEmpty
        ? makeModel
        : (name.isNotEmpty ? name : 'Unnamed firearm');
    final cal = caliber.isNotEmpty ? caliber : '—';
    return '$base ($cal)';
  }

  RifleProfile copyWith({
    String? id,
    String? name,
    String? caliber,
    double? scopeClickValue,
    String? serialNumber,
    String? ownerId,
    String? make,
    String? model,
    String? barrelLength,
    OpticProfile? optic,
  }) {
    return RifleProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      caliber: caliber ?? this.caliber,
      scopeClickValue: scopeClickValue ?? this.scopeClickValue,
      serialNumber: serialNumber ?? this.serialNumber,
      ownerId: ownerId ?? this.ownerId,
      make: make ?? this.make,
      model: model ?? this.model,
      barrelLength: barrelLength ?? this.barrelLength,
      optic: optic ?? this.optic,
    );
  }
}

/// Represents ammunition loaded in a rifle from the Ammunition Manager.
class AmmoProfile {
  final String id;
  final String rifleId;
  final int bulletWeightGrains;
  final double velocityMs;
  final double ballisticCoefficient;
  final int remainingStockCount;
  final String ownerId;

  const AmmoProfile({
    required this.id,
    required this.rifleId,
    required this.bulletWeightGrains,
    this.velocityMs = 0.0,
    this.ballisticCoefficient = 0.0,
    this.remainingStockCount = 0,
    this.ownerId = '',
  });

  factory AmmoProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      debugPrint('AmmoProfile document ${doc.id} has no data');
      return AmmoProfile(id: doc.id, rifleId: '', bulletWeightGrains: 0);
    }
    return AmmoProfile.fromJson(data, id: doc.id);
  }

  factory AmmoProfile.fromJson(Map<String, dynamic> json, {String? id}) {
    return AmmoProfile(
      id: id ?? json['id'] as String? ?? '',
      rifleId: json['rifleId'] as String? ?? '',
      bulletWeightGrains: _intOrDefault(json['bulletWeightGrains']),
      velocityMs: _doubleOrDefault(json['velocityMs']),
      ballisticCoefficient: _doubleOrDefault(json['ballisticCoefficient']),
      remainingStockCount: _intOrDefault(json['remainingStockCount']),
      ownerId: json['ownerId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rifleId': rifleId,
    'bulletWeightGrains': bulletWeightGrains,
    'velocityMs': velocityMs,
    'ballisticCoefficient': ballisticCoefficient,
    'remainingStockCount': remainingStockCount,
    'ownerId': ownerId,
  };

  Map<String, dynamic> toFirestore() => toJson();

  static int _intOrDefault(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _doubleOrDefault(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  AmmoProfile copyWith({
    String? id,
    String? rifleId,
    int? bulletWeightGrains,
    double? velocityMs,
    double? ballisticCoefficient,
    int? remainingStockCount,
    String? ownerId,
  }) {
    return AmmoProfile(
      id: id ?? this.id,
      rifleId: rifleId ?? this.rifleId,
      bulletWeightGrains: bulletWeightGrains ?? this.bulletWeightGrains,
      velocityMs: velocityMs ?? this.velocityMs,
      ballisticCoefficient: ballisticCoefficient ?? this.ballisticCoefficient,
      remainingStockCount: remainingStockCount ?? this.remainingStockCount,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  bool get isLowStock => remainingStockCount > 0 && remainingStockCount <= 10;
  bool get isOutOfStock => remainingStockCount <= 0;
}
