import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ClientBooking {
  final String id;
  final String clientName;
  final String contactNumber;
  final DateTime arrivalDate;
  final DateTime departureDate;
  final String lodgingId;
  final String vehicleId;
  final String status;

  const ClientBooking({
    required this.id,
    required this.clientName,
    required this.contactNumber,
    required this.arrivalDate,
    required this.departureDate,
    required this.lodgingId,
    required this.vehicleId,
    this.status = 'pending',
  });

  factory ClientBooking.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      debugPrint('ClientBooking document ${doc.id} has no data, returning default booking');
      return ClientBooking(
        id: doc.id,
        clientName: 'Unknown Client',
        contactNumber: '',
        arrivalDate: DateTime.now(),
        departureDate: DateTime.now(),
        lodgingId: '',
        vehicleId: '',
      );
    }
    try {
      return ClientBooking.fromJson(data, id: doc.id);
    } catch (e) {
      debugPrint('Error parsing ClientBooking ${doc.id}: $e, returning default booking');
      return ClientBooking(
        id: doc.id,
        clientName: data['clientName'] as String? ?? 'Unknown Client',
        contactNumber: data['contactNumber'] as String? ?? '',
        arrivalDate: _dateTimeOrNow(data['arrivalDate']),
        departureDate: _dateTimeOrNow(data['departureDate']),
        lodgingId: data['lodgingId'] as String? ?? '',
        vehicleId: data['vehicleId'] as String? ?? '',
        status: data['status'] as String? ?? 'pending',
      );
    }
  }

  factory ClientBooking.fromJson(Map<String, dynamic> json, {String? id}) {
    return ClientBooking(
      id: id ?? json['id'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      contactNumber: json['contactNumber'] as String? ?? '',
      arrivalDate: _dateTimeOrNow(json['arrivalDate']),
      departureDate: _dateTimeOrNow(json['departureDate']),
      lodgingId: json['lodgingId'] as String? ?? '',
      vehicleId: json['vehicleId'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientName': clientName,
    'contactNumber': contactNumber,
    'arrivalDate': Timestamp.fromDate(arrivalDate),
    'departureDate': Timestamp.fromDate(departureDate),
    'lodgingId': lodgingId,
    'vehicleId': vehicleId,
    'status': status,
  };

  Map<String, dynamic> toFirestore() => toJson();

  static DateTime _dateTimeOrNow(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
