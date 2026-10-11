import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A firearm stored in the Digital Firearm Safe.
///
/// The document lives in the owner-scoped `firearms` Firestore collection
/// (matched by `ownerId == request.auth.uid`). The Digital Firearm Safe
/// screen, the ballistic calculator, the optic-link dropdown and the SAPS
/// approved-application import all read/write this shape.
///
/// The SAPS import (`Firearm.fromSaps`) stamps [fromSaps] + [rawPayload] so
/// an imported firearm can be traced back to the CFR enquiry that created it.
class Firearm {
  final String id;

  /// Firearm make / brand (e.g. `HOWA`). Persisted under the `make` key the
  /// safe's manual form and quick-edit sheet already use.
  final String make;

  /// Model designation (optional, e.g. `1500`).
  final String model;

  /// Calibre as the CFR portal reports it (e.g. `.338 WIN MAG`). Persisted
  /// under BOTH `caliber` and `calibre` so every reader resolves it.
  final String calibre;

  /// Serial number (e.g. `F004574`). Uniqueness key for the safe import — a
  /// firearm whose serial already exists is never duplicated.
  final String serial;

  /// SAPS application number (e.g. `10654672`). Empty for a manually added
  /// firearm that was never tied to a tracked application.
  final String appNo;

  /// Application / licence type (e.g. `Section 16 Dedicated Hunting`).
  final String type;

  /// Last known SAPS status phrase (e.g. `Approved`).
  final String status;

  /// The date the SAPS portal reported for this status
  /// (`STATUS DATE`, e.g. `2026/10/09`). Null when unavailable.
  final DateTime? statusDate;

  /// When the firearm was added to the safe. Null for legacy docs (the
  /// Firestore write stamps a server timestamp).
  final DateTime? addedAt;

  /// True when this firearm was imported from an approved SAPS application
  /// rather than entered/scanned manually.
  final bool fromSaps;

  /// The raw CFR enquiry payload the firearm was created from (only set when
  /// [fromSaps] is true). Kept for traceability / future fields.
  final Map<String, dynamic>? rawPayload;

  const Firearm({
    required this.id,
    required this.make,
    required this.calibre,
    required this.serial,
    this.model = '',
    this.appNo = '',
    this.type = '',
    this.status = '',
    this.statusDate,
    this.addedAt,
    this.fromSaps = false,
    this.rawPayload,
  });

  factory Firearm.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      debugPrint('Firearm document ${doc.id} has no data');
      return Firearm(id: doc.id, make: '', calibre: '', serial: '');
    }
    return Firearm.fromJson(data, id: doc.id);
  }

  factory Firearm.fromJson(Map<String, dynamic> json, {String? id}) {
    return Firearm(
      id: id ?? (json['id'] as String?) ?? '',
      make: (json['make'] as String?) ??
          (json['manufacturer'] as String?) ??
          (json['brand'] as String?) ??
          '',
      model: (json['model'] as String?) ?? '',
      calibre: (json['calibre'] as String?) ??
          (json['caliber'] as String?) ??
          '',
      serial: (json['serial'] as String?) ??
          (json['serialNumber'] as String?) ??
          '',
      appNo: (json['appNo'] as String?) ?? (json['appNumber'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      statusDate: _dateTimeOrNull(json['statusDate']),
      addedAt: _dateTimeOrNull(json['addedAt'] ?? json['createdAt']),
      fromSaps: json['fromSaps'] as bool? ?? false,
      rawPayload: json['rawPayload'] is Map
          ? Map<String, dynamic>.from(json['rawPayload'] as Map)
          : null,
    );
  }

  /// Builds a safe firearm from a parsed CFR enquiry result.
  ///
  /// [statusDate] accepts the portal's `yyyy/MM/dd` string (or an ISO /
  /// DateTime value) via the shared tolerant parser. [id] is left blank so
  /// the repository assigns the Firestore document id on write.
  factory Firearm.fromSaps({
    required String make,
    required String calibre,
    required String serial,
    String appNo = '',
    String type = '',
    String status = '',
    Object? statusDate,
    Map<String, dynamic>? rawPayload,
  }) {
    return Firearm(
      id: '',
      make: make.trim(),
      calibre: calibre.trim(),
      serial: serial.trim(),
      appNo: appNo.trim(),
      type: type.trim(),
      status: status.trim(),
      statusDate: _dateTimeOrNull(statusDate),
      addedAt: DateTime.now(),
      fromSaps: true,
      rawPayload: rawPayload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'make': make,
        'model': model,
        // Dual-stamp the calibre under both spellings so the ballistic
        // calculator (`caliber`) and the safe screens (`calibre`) agree.
        'calibre': calibre,
        'caliber': calibre,
        'serial': serial,
        'serialNumber': serial,
        'appNo': appNo,
        'type': type,
        'status': status,
        if (statusDate != null) 'statusDate': statusDate!.toIso8601String(),
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
        'fromSaps': fromSaps,
        if (rawPayload != null) 'rawPayload': rawPayload,
      };

  Map<String, dynamic> toFirestore() => toJson();

  /// Human-readable label, e.g. `HOWA .338 WIN MAG (F004574)`.
  String get displayName {
    final base = [make, model].where((s) => s.isNotEmpty).join(' ');
    final head = base.isNotEmpty ? base : 'Unnamed firearm';
    final parts = <String>[
      if (calibre.isNotEmpty) calibre,
      if (serial.isNotEmpty) '($serial)',
    ];
    if (parts.isEmpty) return head;
    return '$head ${parts.join(' ')}';
  }

  /// True when the serial number is usable as a uniqueness key.
  bool get hasSerial => serial.trim().isNotEmpty;

  Firearm copyWith({
    String? id,
    String? make,
    String? model,
    String? calibre,
    String? serial,
    String? appNo,
    String? type,
    String? status,
    DateTime? statusDate,
    DateTime? addedAt,
    bool? fromSaps,
    Map<String, dynamic>? rawPayload,
  }) {
    return Firearm(
      id: id ?? this.id,
      make: make ?? this.make,
      model: model ?? this.model,
      calibre: calibre ?? this.calibre,
      serial: serial ?? this.serial,
      appNo: appNo ?? this.appNo,
      type: type ?? this.type,
      status: status ?? this.status,
      statusDate: statusDate ?? this.statusDate,
      addedAt: addedAt ?? this.addedAt,
      fromSaps: fromSaps ?? this.fromSaps,
      rawPayload: rawPayload ?? this.rawPayload,
    );
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      // The CFR portal renders the status date as `yyyy/MM/dd`; normalise the
      // slashes to dashes so DateTime.tryParse accepts it.
      return DateTime.tryParse(trimmed.replaceAll('/', '-'));
    }
    return null;
  }
}
