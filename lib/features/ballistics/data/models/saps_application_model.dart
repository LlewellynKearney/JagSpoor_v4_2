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

  /// Firearm calibre extracted from a SAPS notification SMS (e.g. `6MM
  /// MUSGRAVE`) or entered manually. Empty when unknown/legacy doc.

  final String calibre;

  /// Firearm serial number extracted from a SAPS notification SMS
  /// (e.g. `OB14468`) or entered manually. Empty when unknown/legacy doc.
  final String serialNumber;

  /// Raw status message / SMS status-type text the last update surfaced
  /// (e.g. `licence collection notice`, `Application received at DFO`).
  final String statusMessage;

  /// Optional batch identifier when the tracking system groups
  /// applications into a submission batch. Empty when unknown.

  final String batchNumber;

  /// Time the application was first registered / submitted. Null when the
  /// legacy or external doc did not record it (UI falls back to the card's
  /// creation window).
  final DateTime? submittedAt;

  /// Time the status was last updated by the tracking system (distinct
  /// from [lastChecked], which is when the app looked). Null for legacy docs.

  final DateTime? statusUpdatedAt;

  const SapsApplication({
    required this.id,
    required this.hunterId,
    required this.referenceNumber,
    required this.idNumber,
    required this.applicationType,
    required this.currentStatus,
    required this.lastChecked,
    this.calibre = '',
    this.serialNumber = '',
    this.statusMessage = '',
    this.batchNumber = '',
    this.submittedAt,
    this.statusUpdatedAt,
  });

  factory SapsApplication.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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

  /// Renders the multi-token display label for the tracked firearm,
  /// e.g. "6MM MUSGRAVE • s/n OB14468". Falls back to '[Calibre] •
  /// s/n [Serial]' with each present part omitted when empty, then
  /// 'Firearm not specified' when neither calibre nor serial is known.

  String get firearmLabel {
    if (calibre.isNotEmpty && serialNumber.isNotEmpty) {
      return '$calibre • s/n $serialNumber';
    }
    if (calibre.isNotEmpty) {
      return calibre;
    }
    if (serialNumber.isNotEmpty) {
      return 's/n $serialNumber';
    }
    return 'Firearm not specified';
  }

  factory SapsApplication.fromJson(Map<String, dynamic> json, {String? id}) {
    return SapsApplication(
      id: id ?? (json['id'] as String?) ?? '',
      hunterId: (json['hunterId'] as String?) ?? '',
      referenceNumber: (json['referenceNumber'] as String?) ?? '',
      idNumber: (json['idNumber'] as String?) ?? '',
      applicationType:
          (json['applicationType'] as String?) ?? 'Competency Certificate',
      currentStatus: (json['currentStatus'] as String?) ?? 'Pending',
      calibre: (json['calibre'] as String?) ?? '',
      serialNumber: (json['serialNumber'] as String?) ?? '',
      statusMessage: (json['statusMessage'] as String?) ?? '',
      batchNumber: (json['batchNumber'] as String?) ?? '',
      submittedAt: _dateTimeOrNull(json['submittedAt']),
      statusUpdatedAt: _dateTimeOrNull(json['statusUpdatedAt']),
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
        'calibre': calibre,
        'serialNumber': serialNumber,
        'statusMessage': statusMessage,
        'batchNumber': batchNumber,
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
        if (statusUpdatedAt != null)
          'statusUpdatedAt': statusUpdatedAt!.toIso8601String(),
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

  /// Parses a nullable Firestore date value into a `DateTime`, returning
  /// null for a missing/blank/unparseable value (the expanded detail fields
  /// are optional).
  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }
    return null;
  }

  SapsApplication copyWith({
    String? id,
    String? hunterId,
    String? referenceNumber,
    String? idNumber,
    String? applicationType,
    String? currentStatus,
    DateTime? lastChecked,
    String? calibre,
    String? serialNumber,
    String? statusMessage,
    String? batchNumber,
    DateTime? submittedAt,
    DateTime? statusUpdatedAt,
    bool clearSubmittedAt = false,
    bool clearStatusUpdatedAt = false,
  }) {
    return SapsApplication(
      id: id ?? this.id,
      hunterId: hunterId ?? this.hunterId,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      idNumber: idNumber ?? this.idNumber,
      applicationType: applicationType ?? this.applicationType,
      currentStatus: currentStatus ?? this.currentStatus,
      calibre: calibre ?? this.calibre,
      serialNumber: serialNumber ?? this.serialNumber,
      statusMessage: statusMessage ?? this.statusMessage,
      batchNumber: batchNumber ?? this.batchNumber,
      submittedAt: clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
      statusUpdatedAt: clearStatusUpdatedAt
          ? null
          : (statusUpdatedAt ?? this.statusUpdatedAt),
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
    'Section 13 – Licence to possess a firearm for self-defence',
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
