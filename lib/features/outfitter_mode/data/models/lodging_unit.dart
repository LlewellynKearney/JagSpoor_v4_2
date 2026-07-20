import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class LodgingUnit {
  final String id;
  final String unitName;
  final int maxCapacity;
  final int currentOccupants;
  final String status;

  const LodgingUnit({
    required this.id,
    required this.unitName,
    required this.maxCapacity,
    this.currentOccupants = 0,
    this.status = 'vacant',
  });

  factory LodgingUnit.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      debugPrint('LodgingUnit document ${doc.id} has no data, returning default unit');
      return LodgingUnit(
        id: doc.id,
        unitName: 'Unknown Unit',
        maxCapacity: 1,
      );
    }
    try {
      return LodgingUnit.fromJson(data, id: doc.id);
    } catch (e) {
      debugPrint('Error parsing LodgingUnit ${doc.id}: $e, returning default unit');
      return LodgingUnit(
        id: doc.id,
        unitName: data['unitName'] as String? ?? 'Unknown Unit',
        maxCapacity: _intOrOne(data['maxCapacity']),
        currentOccupants: _intOrZero(data['currentOccupants']),
        status: data['status'] as String? ?? 'vacant',
      );
    }
  }

  factory LodgingUnit.fromJson(Map<String, dynamic> json, {String? id}) {
    return LodgingUnit(
      id: id ?? json['id'] as String? ?? '',
      unitName: json['unitName'] as String? ?? '',
      maxCapacity: _intOrOne(json['maxCapacity']),
      currentOccupants: _intOrZero(json['currentOccupants']),
      status: json['status'] as String? ?? 'vacant',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'unitName': unitName,
    'maxCapacity': maxCapacity,
    'currentOccupants': currentOccupants,
    'status': status,
  };

  Map<String, dynamic> toFirestore() => toJson();

  static int _intOrZero(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int _intOrOne(dynamic value) {
    if (value is int) return value > 0 ? value : 1;
    if (value is num) return value.toInt() > 0 ? value.toInt() : 1;
    if (value is String) return int.tryParse(value) ?? 1;
    return 1;
  }
}
