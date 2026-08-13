import 'package:cloud_firestore/cloud_firestore.dart';

/// A guided-hunt harvest log entry recorded by an outfitter / PH.
///
/// Stored in the `guided_hunt_logs` collection, scoped to the issuing
/// outfitter via [outfitterId] and assigned to a specific client from the
/// active roster via [clientId]. Records the harvested species, carcass
/// weight, trophy details, shot placement, and cross-references the venison
/// permit ([permitId]) and the local slaughterhouse carcass record
/// ([carcassRecordId]) generated from this log.
class GuidedHuntLog {
  final String id;
  final String outfitterId;

  /// Snapshot of the assigned client at the time of the log.
  final String clientId;
  final String clientName;
  final String? clientIdPassport;

  /// Optional booking this harvest belongs to.
  final String? bookingId;

  final String species;
  final String sex;

  /// Field-dressed / carcass weight in kilograms.
  final double carcassWeightKg;
  final String shotLocationDescription;
  final double? shotLat;
  final double? shotLng;

  /// Trophy measurement (e.g. horn length in inches) + raw measurement label.
  final double? trophyMeasurementInches;
  final String? trophyMeasurementLabel;
  final List<String> trophyPhotoUrls;

  /// Shot placement (e.g. "Broadside - heart/lung").
  final String shotPlacement;
  final double? rifleCalibreMm;
  final double? distanceMeters;

  /// Cross-references to generated downstream documents.
  final String? permitId;
  final String? carcassRecordId;

  final String? notes;
  final DateTime huntDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const GuidedHuntLog({
    required this.id,
    required this.outfitterId,
    required this.clientId,
    required this.clientName,
    this.clientIdPassport,
    this.bookingId,
    required this.species,
    this.sex = 'Unknown',
    this.carcassWeightKg = 0.0,
    this.shotLocationDescription = '',
    this.shotLat,
    this.shotLng,
    this.trophyMeasurementInches,
    this.trophyMeasurementLabel,
    this.trophyPhotoUrls = const [],
    this.shotPlacement = '',
    this.rifleCalibreMm,
    this.distanceMeters,
    this.permitId,
    this.carcassRecordId,
    this.notes,
    required this.huntDate,
    this.createdAt,
    this.updatedAt,
  });

  factory GuidedHuntLog.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return GuidedHuntLog.fromMap(doc.data() ?? const <String, dynamic>{},
        id: doc.id);
  }

  /// Parses a hunt log from a raw map (no Firestore snapshot required).
  factory GuidedHuntLog.fromMap(Map<String, dynamic> data, {String? id}) {
    return GuidedHuntLog(
      id: id ?? data['id'] as String? ?? '',
      outfitterId: data['outfitterId'] as String? ?? '',
      clientId: data['clientId'] as String? ?? '',
      clientName: data['clientName'] as String? ?? '',
      clientIdPassport: data['clientIdPassport'] as String?,
      bookingId: data['bookingId'] as String?,
      species: data['species'] as String? ?? 'Unknown',
      sex: data['sex'] as String? ?? 'Unknown',
      carcassWeightKg: (data['carcassWeightKg'] as num?)?.toDouble() ?? 0.0,
      shotLocationDescription:
          data['shotLocationDescription'] as String? ?? '',
      shotLat: (data['shotLat'] as num?)?.toDouble(),
      shotLng: (data['shotLng'] as num?)?.toDouble(),
      trophyMeasurementInches:
          (data['trophyMeasurementInches'] as num?)?.toDouble(),
      trophyMeasurementLabel: data['trophyMeasurementLabel'] as String?,
      trophyPhotoUrls:
          ((data['trophyPhotoUrls'] as List<dynamic>?) ?? const [])
              .map((e) => e.toString())
              .toList(),
      shotPlacement: data['shotPlacement'] as String? ?? '',
      rifleCalibreMm: (data['rifleCalibreMm'] as num?)?.toDouble(),
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble(),
      permitId: data['permitId'] as String?,
      carcassRecordId: data['carcassRecordId'] as String?,
      notes: data['notes'] as String?,
      huntDate: (data['huntDate'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'outfitterId': outfitterId,
      'clientId': clientId,
      'clientName': clientName,
      if (clientIdPassport != null) 'clientIdPassport': clientIdPassport,
      if (bookingId != null) 'bookingId': bookingId,
      'species': species,
      'sex': sex,
      'carcassWeightKg': carcassWeightKg,
      'shotLocationDescription': shotLocationDescription,
      if (shotLat != null) 'shotLat': shotLat,
      if (shotLng != null) 'shotLng': shotLng,
      if (trophyMeasurementInches != null)
        'trophyMeasurementInches': trophyMeasurementInches,
      if (trophyMeasurementLabel != null)
        'trophyMeasurementLabel': trophyMeasurementLabel,
      'trophyPhotoUrls': trophyPhotoUrls,
      'shotPlacement': shotPlacement,
      if (rifleCalibreMm != null) 'rifleCalibreMm': rifleCalibreMm,
      if (distanceMeters != null) 'distanceMeters': distanceMeters,
      if (permitId != null) 'permitId': permitId,
      if (carcassRecordId != null) 'carcassRecordId': carcassRecordId,
      if (notes != null) 'notes': notes,
      'huntDate': Timestamp.fromDate(huntDate),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
    };
  }

  GuidedHuntLog copyWith({
    String? permitId,
    String? carcassRecordId,
    DateTime? updatedAt,
  }) {
    return GuidedHuntLog(
      id: id,
      outfitterId: outfitterId,
      clientId: clientId,
      clientName: clientName,
      clientIdPassport: clientIdPassport,
      bookingId: bookingId,
      species: species,
      sex: sex,
      carcassWeightKg: carcassWeightKg,
      shotLocationDescription: shotLocationDescription,
      shotLat: shotLat,
      shotLng: shotLng,
      trophyMeasurementInches: trophyMeasurementInches,
      trophyMeasurementLabel: trophyMeasurementLabel,
      trophyPhotoUrls: trophyPhotoUrls,
      shotPlacement: shotPlacement,
      rifleCalibreMm: rifleCalibreMm,
      distanceMeters: distanceMeters,
      permitId: permitId ?? this.permitId,
      carcassRecordId: carcassRecordId ?? this.carcassRecordId,
      notes: notes,
      huntDate: huntDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
