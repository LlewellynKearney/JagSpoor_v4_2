import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Tracks SAPS firearm license and competency application status.
class SapsApplication {
  final String id;
  final String hunterId;
  final String referenceNumber;
  final String idNumber;
  final String applicationType;
  final String currentStatus;
  final DateTime lastChecked;

  const SapsApplication({
    required this.id,
    required this.hunterId,
    required this.referenceNumber,
    required this.idNumber,
    required this.applicationType,
    required this.currentStatus,
    required this.lastChecked,
  });

  factory SapsApplication.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      debugPrint('SapsApplication document ${doc.id} has no data');
      return SapsApplication(
        id: doc.id,
        hunterId: '',
        referenceNumber: '',
        idNumber: '',
        applicationType: 'Competency Certificate',
        currentStatus: 'Unknown',
        lastChecked: DateTime.now(),
      );
    }
    return SapsApplication.fromJson(data, id: doc.id);
  }

  factory SapsApplication.fromJson(Map<String, dynamic> json, {String? id}) {
    return SapsApplication(
      id: id ?? (json['id'] as String?) ?? '',
      hunterId: (json['hunterId'] as String?) ?? '',
      referenceNumber: (json['referenceNumber'] as String?) ?? '',
      idNumber: (json['idNumber'] as String?) ?? '',
      applicationType: (json['applicationType'] as String?) ?? 'Competency Certificate',
      currentStatus: (json['currentStatus'] as String?) ?? 'Pending',
      lastChecked: _dateTimeOrDefault(json['lastChecked']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hunterId': hunterId,
        'referenceNumber': referenceNumber,
        'idNumber': idNumber,
        'applicationType': applicationType,
        'currentStatus': currentStatus,
        'lastChecked': lastChecked.toIso8601String(),
      };

  Map<String, dynamic> toFirestore() => toJson();

  static DateTime _dateTimeOrDefault(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  SapsApplication copyWith({
    String? id,
    String? hunterId,
    String? referenceNumber,
    String? idNumber,
    String? applicationType,
    String? currentStatus,
    DateTime? lastChecked,
  }) {
    return SapsApplication(
      id: id ?? this.id,
      hunterId: hunterId ?? this.hunterId,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      idNumber: idNumber ?? this.idNumber,
      applicationType: applicationType ?? this.applicationType,
      currentStatus: currentStatus ?? this.currentStatus,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  /// Returns the stage index (0-3) based on current status for progress tracking.
  int get stageIndex {
    switch (currentStatus.toLowerCase()) {
      case 'submitted':
      case 'dfo':
      case 'district_firearms_officer':
        return 0;
      case 'provincial':
      case 'provincial_office':
        return 1;
      case 'cfr':
      case 'central_firearms_registry':
        return 2;
      case 'printed':
      case 'ready_for_collection':
      case 'completed':
        return 3;
      default:
        return 0;
    }
  }

  /// Application type options for the dropdown selector.
  static const List<String> applicationTypes = [
    'Competency Certificate',
    'Section 15 Occasional Sport',
    'Section 16 Dedicated Hunting',
  ];

  /// Status stages for the progress tracker bar.
  static const List<String> statusStages = [
    'DFO',
    'Provincial',
    'CFR',
    'Printed',
  ];
}
