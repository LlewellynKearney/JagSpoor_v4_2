import 'package:cloud_firestore/cloud_firestore.dart';

/// A client hunter managed by an outfitter / professional hunter (PH).
///
/// Stored in the `client_roster` collection and scoped to the issuing
/// outfitter via [outfitterId]. Captures the identity + contact details plus
/// references to the package/booking the client is attached to and a running
/// list of venison-permit ids issued for that client — the rosetta stone that
/// ties guided hunt logs to permit + slaughterhouse manifest generation.
class ClientProfile {
  final String id;
  final String outfitterId;
  final String fullName;
  final String idPassportNumber;
  final String nationality;
  final String cellNumber;
  final String email;
  final String address;

  /// Optional id of the `packages` doc the client has been booked on.
  final String? assignedPackageId;
  final String? assignedPackageName;

  /// Optional id of the `bookings` doc linking the client to a hunt.
  final String? assignedBookingId;

  /// Running list of `venison_permits` ids issued for this client.
  final List<String> permitReferenceIds;

  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ClientProfile({
    required this.id,
    required this.outfitterId,
    required this.fullName,
    this.idPassportNumber = '',
    this.nationality = '',
    this.cellNumber = '',
    this.email = '',
    this.address = '',
    this.assignedPackageId,
    this.assignedPackageName,
    this.assignedBookingId,
    this.permitReferenceIds = const [],
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory ClientProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ClientProfile.fromMap(doc.data() ?? const <String, dynamic>{},
        id: doc.id);
  }

  /// Parses a client from a raw map (no Firestore snapshot required). Useful
  /// for testing and for callers that already hold the document data.
  factory ClientProfile.fromMap(Map<String, dynamic> data, {String? id}) {
    return ClientProfile(
      id: id ?? data['id'] as String? ?? '',
      outfitterId: data['outfitterId'] as String? ?? '',
      fullName: data['fullName'] as String? ?? '',
      idPassportNumber: data['idPassportNumber'] as String? ?? '',
      nationality: data['nationality'] as String? ?? '',
      cellNumber: data['cellNumber'] as String? ?? '',
      email: data['email'] as String? ?? '',
      address: data['address'] as String? ?? '',
      assignedPackageId: data['assignedPackageId'] as String?,
      assignedPackageName: data['assignedPackageName'] as String?,
      assignedBookingId: data['assignedBookingId'] as String?,
      permitReferenceIds:
          ((data['permitReferenceIds'] as List<dynamic>?) ?? const [])
              .map((e) => e.toString())
              .toList(),
      notes: data['notes'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'outfitterId': outfitterId,
      'fullName': fullName,
      'idPassportNumber': idPassportNumber,
      'nationality': nationality,
      'cellNumber': cellNumber,
      'email': email,
      'address': address,
      if (assignedPackageId != null) 'assignedPackageId': assignedPackageId,
      if (assignedPackageName != null)
        'assignedPackageName': assignedPackageName,
      if (assignedBookingId != null) 'assignedBookingId': assignedBookingId,
      'permitReferenceIds': permitReferenceIds,
      if (notes != null) 'notes': notes,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
    };
  }

  ClientProfile copyWith({
    String? fullName,
    String? idPassportNumber,
    String? nationality,
    String? cellNumber,
    String? email,
    String? address,
    String? assignedPackageId,
    String? assignedPackageName,
    String? assignedBookingId,
    List<String>? permitReferenceIds,
    String? notes,
    DateTime? updatedAt,
  }) {
    return ClientProfile(
      id: id,
      outfitterId: outfitterId,
      fullName: fullName ?? this.fullName,
      idPassportNumber: idPassportNumber ?? this.idPassportNumber,
      nationality: nationality ?? this.nationality,
      cellNumber: cellNumber ?? this.cellNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      assignedPackageId: assignedPackageId ?? this.assignedPackageId,
      assignedPackageName: assignedPackageName ?? this.assignedPackageName,
      assignedBookingId: assignedBookingId ?? this.assignedBookingId,
      permitReferenceIds: permitReferenceIds ?? this.permitReferenceIds,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
