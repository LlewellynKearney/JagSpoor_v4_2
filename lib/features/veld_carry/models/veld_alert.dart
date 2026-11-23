/// One advisory raised from a farm's live veld data.
///
/// Alerts are **never persisted**. `buildAlerts()` in
/// `veld_carry_alerts.dart` recomputes them from the camps, stock, permits and
/// rainfall that already exist, so an alert can never go stale and a dismiss
/// can never hide a real problem on the next load.
///
/// Outfitter-only: nothing in this model may be surfaced on a hunter-facing
/// screen.
class VeldAlert {
  const VeldAlert({
    required this.id,
    required this.farmId,
    this.campId,
    required this.alertType,
    required this.severity,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isDismissed = false,
    this.dismissedAt,
  });

  // ── Severity ─────────────────────────────────────────────────────────

  static const String severityInfo = 'info';
  static const String severityWarning = 'warning';
  static const String severityCritical = 'critical';

  /// Urgency order — the first entry is the most urgent, so a plain sort over
  /// this list puts critical alerts first.
  static const List<String> severities = [
    severityCritical,
    severityWarning,
    severityInfo,
  ];

  // ── Alert types ──────────────────────────────────────────────────────

  static const String typeOverstocked = 'overstocked';
  static const String typeSeverelyOverstocked = 'severely_overstocked';
  static const String typePermitExpiring = 'permit_expiring';
  static const String typePermitExpired = 'permit_expired';
  static const String typeNoStockRecorded = 'no_stock_recorded';
  static const String typeNoRainfallRecorded = 'no_rainfall_recorded';

  static const List<String> alertTypes = [
    typeOverstocked,
    typeSeverelyOverstocked,
    typePermitExpiring,
    typePermitExpired,
    typeNoStockRecorded,
    typeNoRainfallRecorded,
  ];

  /// Stable id — derived from the alert type plus the record it describes, so
  /// the same condition always yields the same id across reloads.
  final String id;

  final String farmId;

  /// The camp the alert is about, or `null` for a farm-wide alert (permits).
  final String? campId;

  final String alertType;

  /// One of [severities].
  final String severity;

  final String title;
  final String message;
  final DateTime createdAt;

  /// Session-only dismissal flag. Never written to Firestore in this phase.
  final bool isDismissed;
  final DateTime? dismissedAt;

  /// `null` camp means the alert concerns the whole farm.
  bool get isFarmWide => campId == null || campId!.trim().isEmpty;

  bool get isCritical => severity == severityCritical;
  bool get isWarning => severity == severityWarning;

  /// 0 for critical, 1 for warning, 2 for info — used to sort most urgent
  /// first.
  int get severityRank {
    final index = severities.indexOf(severity);
    return index < 0 ? severities.length : index;
  }

  /// Normalises any severity spelling to one of [severities] (`info` when the
  /// value is unknown, so a malformed alert can never out-rank a real one).
  static String normalizeSeverity(Object? value) {
    final text = (value ?? '').toString().trim().toLowerCase();
    return severities.contains(text) ? text : severityInfo;
  }

  /// Normalises an alert type to one of [alertTypes], or `null` when the value
  /// is not a known type.
  static String? normalizeAlertType(Object? value) {
    final text = (value ?? '').toString().trim().toLowerCase();
    return alertTypes.contains(text) ? text : null;
  }

  VeldAlert copyWith({
    String? id,
    String? farmId,
    String? campId,
    String? alertType,
    String? severity,
    String? title,
    String? message,
    DateTime? createdAt,
    bool? isDismissed,
    DateTime? dismissedAt,
  }) =>
      VeldAlert(
        id: id ?? this.id,
        farmId: farmId ?? this.farmId,
        campId: campId ?? this.campId,
        alertType: alertType ?? this.alertType,
        severity: severity ?? this.severity,
        title: title ?? this.title,
        message: message ?? this.message,
        createdAt: createdAt ?? this.createdAt,
        isDismissed: isDismissed ?? this.isDismissed,
        dismissedAt: dismissedAt ?? this.dismissedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'farmId': farmId,
        if (campId != null) 'campId': campId,
        'alertType': alertType,
        'severity': severity,
        'title': title,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'isDismissed': isDismissed,
        if (dismissedAt != null)
          'dismissedAt': dismissedAt!.toIso8601String(),
      };

  /// Reads a previously serialised alert (e.g. from local storage). Unknown
  /// severities fall back to `info`; unknown alert types are rejected.
  factory VeldAlert.fromMap(Map<String, dynamic> map) {
    final type = normalizeAlertType(map['alertType']);
    if (type == null) {
      throw ArgumentError.value(
        map['alertType'],
        'alertType',
        'Unknown veld alert type',
      );
    }
    final dismissedAt = _parseDate(map['dismissedAt']);
    return VeldAlert(
      id: (map['id'] ?? '').toString(),
      farmId: (map['farmId'] ?? '').toString(),
      campId: _optionalText(map['campId']),
      alertType: type,
      severity: normalizeSeverity(map['severity']),
      title: (map['title'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      isDismissed: map['isDismissed'] == true,
      dismissedAt: dismissedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VeldAlert &&
      other.id == id &&
      other.farmId == farmId &&
      other.campId == campId &&
      other.alertType == alertType &&
      other.severity == severity &&
      other.title == title &&
      other.message == message &&
      other.createdAt == createdAt &&
      other.isDismissed == isDismissed &&
      other.dismissedAt == dismissedAt;

  @override
  int get hashCode => Object.hash(
        id,
        farmId,
        campId,
        alertType,
        severity,
        title,
        message,
        createdAt,
        isDismissed,
        dismissedAt,
      );

  @override
  String toString() =>
      'VeldAlert($id, $alertType, $severity, "$message")';
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}
