import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FleetAsset {
  final String id;
  final String vehicleName;
  final String registrationNumber;
  final String currentDriver;
  final int fuelLevelPercentage;
  final String operationalStatus;

  const FleetAsset({
    required this.id,
    required this.vehicleName,
    required this.registrationNumber,
    this.currentDriver = '',
    this.fuelLevelPercentage = 0,
    this.operationalStatus = 'active',
  });

  factory FleetAsset.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      debugPrint('FleetAsset document ${doc.id} has no data, returning default asset');
      return FleetAsset(
        id: doc.id,
        vehicleName: 'Unknown Vehicle',
        registrationNumber: '',
      );
    }
    try {
      return FleetAsset.fromJson(data, id: doc.id);
    } catch (e) {
      debugPrint('Error parsing FleetAsset ${doc.id}: $e, returning default asset');
      return FleetAsset(
        id: doc.id,
        vehicleName: data['vehicleName'] as String? ?? 'Unknown Vehicle',
        registrationNumber: data['registrationNumber'] as String? ?? '',
        currentDriver: data['currentDriver'] as String? ?? '',
        fuelLevelPercentage: _intOrZero(data['fuelLevelPercentage']),
        operationalStatus: data['operationalStatus'] as String? ?? 'active',
      );
    }
  }

  factory FleetAsset.fromJson(Map<String, dynamic> json, {String? id}) {
    return FleetAsset(
      id: id ?? json['id'] as String? ?? '',
      vehicleName: json['vehicleName'] as String? ?? '',
      registrationNumber: json['registrationNumber'] as String? ?? '',
      currentDriver: json['currentDriver'] as String? ?? '',
      fuelLevelPercentage: _intOrZero(json['fuelLevelPercentage']),
      operationalStatus: json['operationalStatus'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicleName': vehicleName,
    'registrationNumber': registrationNumber,
    'currentDriver': currentDriver,
    'fuelLevelPercentage': fuelLevelPercentage,
    'operationalStatus': operationalStatus,
  };

  Map<String, dynamic> toFirestore() => toJson();

  static int _intOrZero(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
