import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Represents a rifle profile from the Digital Firearm Safe.
class RifleProfile {
  final String id;
  final String name;
  final String caliber;
  final double scopeClickValue;
  final String serialNumber;
  final String ownerId;

  const RifleProfile({
    required this.id,
    required this.name,
    required this.caliber,
    this.scopeClickValue = 0.25,
    this.serialNumber = '',
    this.ownerId = '',
  });

  factory RifleProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      debugPrint('RifleProfile document ${doc.id} has no data');
      return RifleProfile(
        id: doc.id,
        name: 'Unknown Rifle',
        caliber: '',
      );
    }
    return RifleProfile.fromJson(data, id: doc.id);
  }

  factory RifleProfile.fromJson(Map<String, dynamic> json, {String? id}) {
    return RifleProfile(
      id: id ?? (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      caliber: (json['caliber'] as String?) ?? '',
      scopeClickValue: _doubleOrDefault(json['scopeClickValue']),
      serialNumber: (json['serialNumber'] as String?) ?? '',
      ownerId: (json['ownerId'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'caliber': caliber,
        'scopeClickValue': scopeClickValue,
        'serialNumber': serialNumber,
        'ownerId': ownerId,
      };

  Map<String, dynamic> toFirestore() => toJson();

  static double _doubleOrDefault(dynamic value) {
    if (value == null) return 0.25;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.25;
    return 0.25;
  }

  RifleProfile copyWith({
    String? id,
    String? name,
    String? caliber,
    double? scopeClickValue,
    String? serialNumber,
    String? ownerId,
  }) {
    return RifleProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      caliber: caliber ?? this.caliber,
      scopeClickValue: scopeClickValue ?? this.scopeClickValue,
      serialNumber: serialNumber ?? this.serialNumber,
      ownerId: ownerId ?? this.ownerId,
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

  const AmmoProfile({
    required this.id,
    required this.rifleId,
    required this.bulletWeightGrains,
    this.velocityMs = 0.0,
    this.ballisticCoefficient = 0.0,
    this.remainingStockCount = 0,
  });

  factory AmmoProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      debugPrint('AmmoProfile document ${doc.id} has no data');
      return AmmoProfile(
        id: doc.id,
        rifleId: '',
        bulletWeightGrains: 0,
      );
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
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rifleId': rifleId,
        'bulletWeightGrains': bulletWeightGrains,
        'velocityMs': velocityMs,
        'ballisticCoefficient': ballisticCoefficient,
        'remainingStockCount': remainingStockCount,
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
  }) {
    return AmmoProfile(
      id: id ?? this.id,
      rifleId: rifleId ?? this.rifleId,
      bulletWeightGrains: bulletWeightGrains ?? this.bulletWeightGrains,
      velocityMs: velocityMs ?? this.velocityMs,
      ballisticCoefficient: ballisticCoefficient ?? this.ballisticCoefficient,
      remainingStockCount: remainingStockCount ?? this.remainingStockCount,
    );
  }

  bool get isLowStock => remainingStockCount > 0 && remainingStockCount <= 10;
  bool get isOutOfStock => remainingStockCount <= 0;
}
