import 'package:cloud_firestore/cloud_firestore.dart';

/// A single entry in an application's status timeline.
class SapsStatusTimelineEntry {
  final String label;
  final DateTime? timestamp;
  final String? detail;

  const SapsStatusTimelineEntry({
    required this.label,
    this.timestamp,
    this.detail,
  });

  factory SapsStatusTimelineEntry.fromJson(Map<String, dynamic> json) {
    return SapsStatusTimelineEntry(
      label: (json['label'] as String?) ?? '',
      timestamp: _dateTimeOrNull(json['timestamp']),
      detail: json['detail'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
        if (detail != null) 'detail': detail,
      };

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
}

/// A suggested / estimated waiting-period for a given stage, sourced from the
/// tracking system's guidance (e.g. "DFO processing: 2–4 weeks").
class SapsWaitingEstimate {
  final String stageLabel;
  final String estimate;

  const SapsWaitingEstimate({
    required this.stageLabel,
    required this.estimate,
  });

  factory SapsWaitingEstimate.fromJson(Map<String, dynamic> json) {
    return SapsWaitingEstimate(
      stageLabel: (json['stageLabel'] as String?) ?? '',
      estimate: (json['estimate'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'stageLabel': stageLabel,
        'estimate': estimate,
      };
}

/// A single batch to which the application belongs (batch number, submission
/// date, count of applications in the batch, status).
class SapsBatchDetail {
  final String batchNumber;
  final DateTime? submittedAt;
  final int? applicationCount;
  final String? status;

  const SapsBatchDetail({
    required this.batchNumber,
    this.submittedAt,
    this.applicationCount,
    this.status,
  });

  factory SapsBatchDetail.fromJson(Map<String, dynamic> json) {
    return SapsBatchDetail(
      batchNumber: (json['batchNumber'] as String?) ?? '',
      submittedAt: _dateTimeOrNull(json['submittedAt']),
      applicationCount: json['applicationCount'] as int?,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'batchNumber': batchNumber,
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
        if (applicationCount != null) 'applicationCount': applicationCount,
        if (status != null) 'status': status,
      };

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }
    return null;
  }
}

/// Comprehensive tracking details for an application, surfaced in the
/// expandable detail view. All fields are optional: the tracking system may
/// not have timeline / batch / waiting-period data for every application, and
/// the UI degrades gracefully when an individual section is empty.
class SapsTrackingDetails {
  final String applicationId;
  final List<SapsStatusTimelineEntry> timeline;
  final List<SapsWaitingEstimate> waitingEstimates;
  final List<SapsBatchDetail> batches;
  final String? currentProgressLabel;
  final String? currentProgressDetail;
  final DateTime? refreshedAt;

  const SapsTrackingDetails({
    required this.applicationId,
    this.timeline = const [],
    this.waitingEstimates = const [],
    this.batches = const [],
    this.currentProgressLabel,
    this.currentProgressDetail,
    this.refreshedAt,
  });

  factory SapsTrackingDetails.fromJson(
    Map<String, dynamic> json, {
    String? applicationId,
  }) {
    return SapsTrackingDetails(
      applicationId: applicationId ?? (json['applicationId'] as String?) ?? '',
      timeline: _timelineFrom(json['timeline']),
      waitingEstimates: _estimatesFrom(json['waitingEstimates']),
      batches: _batchesFrom(json['batches']),
      currentProgressLabel: json['currentProgressLabel'] as String?,
      currentProgressDetail: json['currentProgressDetail'] as String?,
      refreshedAt: _dateTimeOrNull(json['refreshedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'applicationId': applicationId,
        'timeline': timeline.map((e) => e.toJson()).toList(),
        'waitingEstimates': waitingEstimates.map((e) => e.toJson()).toList(),
        'batches': batches.map((e) => e.toJson()).toList(),
        if (currentProgressLabel != null)
          'currentProgressLabel': currentProgressLabel,
        if (currentProgressDetail != null)
          'currentProgressDetail': currentProgressDetail,
        if (refreshedAt != null) 'refreshedAt': refreshedAt!.toIso8601String(),
      };

  static List<SapsStatusTimelineEntry> _timelineFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) =>
            SapsStatusTimelineEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  static List<SapsWaitingEstimate> _estimatesFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) => SapsWaitingEstimate.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  static List<SapsBatchDetail> _batchesFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) => SapsBatchDetail.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }
    return null;
  }
}

/// Pure builder for a default/suggested tracking-details fallback used when
/// the tracker returns no structured timeline (older documents / mock mode).
class SapsTrackingDetailsFactory {
  SapsTrackingDetailsFactory._();

  /// Builds a standardised timeline from an application's card-level fields so
  /// the detail view always has *something* to show even when the tracking
  /// system stores no explicit timeline.
  static SapsTrackingDetails fromApplicationFields({
    required String applicationId,
    String? currentStatus,
    String? statusMessage,
    DateTime? submittedAt,
    DateTime? statusUpdatedAt,
    DateTime? refreshedAt,
    String? batchNumber,
  }) {
    final timeline = <SapsStatusTimelineEntry>[];

    if (submittedAt != null) {
      timeline.add(SapsStatusTimelineEntry(
        label: 'Application submitted',
        timestamp: submittedAt,
      ));
    }
    if (statusUpdatedAt != null ||
        statusMessage != null ||
        currentStatus != null) {
      timeline.add(SapsStatusTimelineEntry(
        label: statusMessage ?? currentStatus ?? 'Latest update',
        timestamp: statusUpdatedAt,
        detail: 'Latest known status recorded for this application.',
      ));
    }

    return SapsTrackingDetails(
      applicationId: applicationId,
      timeline: timeline,
      waitingEstimates: const [
        SapsWaitingEstimate(
          stageLabel: 'DFO processing',
          estimate: 'Typically 2–4 weeks',
        ),
        SapsWaitingEstimate(
          stageLabel: 'Provincial processing',
          estimate: 'Typically 6–10 weeks',
        ),
        SapsWaitingEstimate(
          stageLabel: 'CFR processing',
          estimate: 'Typically 8–16 weeks',
        ),
        SapsWaitingEstimate(
          stageLabel: 'Printing & collection',
          estimate: 'Typically 1–2 weeks after approval',
        ),
      ],
      batches: batchNumber != null && batchNumber.isNotEmpty
          ? [
              SapsBatchDetail(
                batchNumber: batchNumber,
                submittedAt: submittedAt,
                status: currentStatus,
              ),
            ]
          : const [],
      currentProgressLabel: statusMessage ?? currentStatus,
      currentProgressDetail:
          'Application is ${statusMessage ?? currentStatus ?? 'being processed'}.',
      refreshedAt: refreshedAt,
    );
  }
}
