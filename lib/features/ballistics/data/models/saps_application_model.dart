import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../hunter_mode/services/sa_working_days.dart';

/// Tracks SAPS firearm license and competency application status.
class SapsApplication {
  final String id;
  final String hunterId;
  final String referenceNumber;
  final String idNumber;
  final String applicationType;
  final String currentStatus;
  final DateTime lastChecked;

  /// Firearm make / brand (e.g. `TIKKA T3X`) extracted from a SAPS
  /// notification SMS or entered manually. Empty when unknown / legacy doc /
  /// a Competency Certificate application (which has no firearm attached).
  final String firearmMake;

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
  /// legacy or external doc did not record it (the UI falls back to the
  /// record's [createdAt] timestamp).
  final DateTime? submittedAt;

  /// Time the application document was created. Used as the fallback for the
  /// submission milestone when [submittedAt] is missing / unrecorded, so
  /// the working-day tally is always computable and displayed.
  final DateTime? createdAt;

  /// Time the application was received at the provincial DFO (the second
  /// milestone). Null when the tracking system has not yet recorded it or
  /// the application is still at the district office.
  final DateTime? provincialDfoReceivedAt;

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
    this.firearmMake = '',
    this.calibre = '',
    this.serialNumber = '',
    this.statusMessage = '',
    this.batchNumber = '',
    this.submittedAt,
    this.createdAt,
    this.provincialDfoReceivedAt,
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
  /// e.g. "TIKKA T3X • 6MM MUSGRAVE • s/n OB14468". Each present part
  /// ([firearmMake] / [calibre] / [serialNumber]) is included in order and
  /// omitted when empty, then 'Firearm not specified' when none is known.
  String get firearmLabel {
    final parts = <String>[
      if (firearmMake.trim().isNotEmpty) firearmMake.trim(),
      if (calibre.trim().isNotEmpty) calibre.trim(),
      if (serialNumber.trim().isNotEmpty) 's/n ${serialNumber.trim()}',
    ];
    if (parts.isEmpty) return 'Firearm not specified';
    return parts.join(' • ');
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
      firearmMake: (json['firearmMake'] as String?) ??
          (json['make'] as String?) ??
          (json['firearm_make'] as String?) ??
          '',
      calibre: (json['calibre'] as String?) ?? '',
      serialNumber: (json['serialNumber'] as String?) ?? '',
      statusMessage: (json['statusMessage'] as String?) ?? '',
      batchNumber: (json['batchNumber'] as String?) ?? '',
      submittedAt: _dateTimeOrNull(json['submittedAt']),
      createdAt: _dateTimeOrNull(json['createdAt']) ??
          _dateTimeOrNull(json['created_at']),
      provincialDfoReceivedAt: _dateTimeOrNull(
        json['provincialDfoReceivedAt'] ?? json['dfoReceivedAt'],
      ),
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
        // Dual-stamp the make under both the canonical camelCase key and the
        // shorter `make` alias so legacy / third-party readers that look up
        // either spelling resolve the same firearm brand.
        'firearmMake': firearmMake,
        'make': firearmMake,
        'calibre': calibre,
        'serialNumber': serialNumber,
        'statusMessage': statusMessage,
        'batchNumber': batchNumber,
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (provincialDfoReceivedAt != null)
          'provincialDfoReceivedAt': provincialDfoReceivedAt!.toIso8601String(),
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
    String? firearmMake,
    String? calibre,
    String? serialNumber,
    String? statusMessage,
    String? batchNumber,
    DateTime? submittedAt,
    DateTime? createdAt,
    DateTime? provincialDfoReceivedAt,
    DateTime? statusUpdatedAt,
    bool clearSubmittedAt = false,
    bool clearCreatedAt = false,
    bool clearProvincialDfoReceivedAt = false,
    bool clearStatusUpdatedAt = false,
  }) {
    return SapsApplication(
      id: id ?? this.id,
      hunterId: hunterId ?? this.hunterId,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      idNumber: idNumber ?? this.idNumber,
      applicationType: applicationType ?? this.applicationType,
      currentStatus: currentStatus ?? this.currentStatus,
      firearmMake: firearmMake ?? this.firearmMake,
      calibre: calibre ?? this.calibre,
      serialNumber: serialNumber ?? this.serialNumber,
      statusMessage: statusMessage ?? this.statusMessage,
      batchNumber: batchNumber ?? this.batchNumber,
      submittedAt: clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
      createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
      provincialDfoReceivedAt: clearProvincialDfoReceivedAt
          ? null
          : (provincialDfoReceivedAt ?? this.provincialDfoReceivedAt),
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

  /// Effective submission date: prefers the official [submittedAt], falling
  /// back to the record's [createdAt] timestamp when the official submission
  /// date is missing or recorded as unrecorded. This guarantees the working-
  /// day tally is always computable and displayed for every application.

  DateTime? get effectiveSubmissionDate => submittedAt ?? createdAt;

  /// Working days (weekends + SA public holidays excluded) elapsed since the
  /// application's [effectiveSubmissionDate]. Returns `null` when the effective
  /// submission date is unknown or still in the future.
  int? workingDaysSinceSubmitted(DateTime now) {
    return SaWorkingDays.workingDaysSince(effectiveSubmissionDate, now);
  }

  /// The next anticipated status label in the SAPS licensing workflow sequence
  /// (e.g. moving from Local DFO to Provincial, or Provincial to Central
  /// Firearms Register / CFR). Uses the same tolerant substring matching as
  /// `convertRawStatusToStage` so realistic status strings like
  /// "Application received at DFO" or "CFR Processing" resolve correctly.
  String get nextStatusLabel {
    final normalized = currentStatus.toLowerCase();
    if (normalized.contains('provincial') ||
        normalized.contains('province')) {
      return 'CFR';
    }
    if (normalized.contains('cfr') ||
        normalized.contains('registry') ||
        normalized.contains('central firearms')) {
      return 'Printed / Ready for Collection';
    }
    if (normalized.contains('printed') ||
        normalized.contains('ready') ||
        normalized.contains('approved') ||
        normalized.contains('completed')) {
      return 'Licence Collected';
    }
    // Any submitted / received / DFO / pending state -> Provincial.
    return 'Provincial';
  }

  /// Plain-language description of what happens operationally during the
  /// application's current [currentStatus] stage. Designed to be displayed
  /// directly on the card / detail panel.
  String get currentStatusDescription {
    final normalized = currentStatus.toLowerCase();
    if (normalized.contains('provincial') ||
        normalized.contains('province')) {
      return 'The Provincial Firearms Office is reviewing your application, '
          'running background and reference checks and verifying that all '
          'supporting documents are in order before forwarding it to the '
          'Central Firearms Registry (CFR).';
    }
    if (normalized.contains('cfr') ||
        normalized.contains('registry') ||
        normalized.contains('central firearms')) {
      return 'The Central Firearms Registry (CFR) is the final decision-making '
          'authority. It performs the final vetting, criminal-record checks, '
          'and approval/refusal determination. Once approved, your licence '
          'is printed and sent to your designated police station for '
          'collection.';
    }
    if (normalized.contains('printed') ||
        normalized.contains('ready') ||
        normalized.contains('approved') ||
        normalized.contains('completed')) {
      return 'Your licence card has been printed and is ready (or has been '
          'collected) at your designated police station. Bring your ID '
          'document and the notification SMS when collecting.';
    }
    if (normalized.contains('submitted') ||
        normalized.contains('received') ||
        normalized.contains('dfo') ||
        normalized.contains('district firearms') ||
        normalized.contains('pending')) {
      return 'Your application has been captured and is being vetted at your '
          'local District Firearms Office (DFO). Officials check your ID, '
          'competency certificate and references before forwarding it to '
          'the provincial office.';
    }
    return 'Your application is progressing through the SAPS licensing '
        'workflow. Officials at the current office are reviewing it before '
        'forwarding it to the next authority.';
  }

  /// Suggested waiting-period estimate for the current status stage (used
  /// by the detail view context card).
  String get currentStatusEstimate {
    switch (stageIndex) {
      case 0:
        return 'DFO processing typically takes 2–4 weeks.';
      case 1:
        return 'Provincial processing typically takes 6–10 weeks.';
      case 2:
        return 'CFR processing typically takes 8–16 weeks.';
      default:
        return 'Printing and collection typically takes 1–2 weeks after '
            'approval.';
    }
  }

  /// Working days elapsed since the application was received at the
  /// provincial DFO ([provincialDfoReceivedAt]). Returns `null` when that
  /// milestone is unknown or still in the future.
  int? workingDaysSinceProvincialDfo(DateTime now) {
    return SaWorkingDays.workingDaysSince(provincialDfoReceivedAt, now);
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
