import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/client_booking.dart';
import '../models/lodging_unit.dart';
import '../models/fleet_asset.dart';

class OutfitterFirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<ClientBooking>> getBookingsStream() {
    return _firestore
        .collection('outfitter/bookings')
        .orderBy('arrivalDate', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ClientBooking.fromFirestore(doc))
          .toList();
    }).handleError((error) {
      debugPrint('Error fetching bookings stream: $error');
      return <ClientBooking>[];
    });
  }

  Stream<List<LodgingUnit>> getLodgingStream() {
    return _firestore
        .collection('outfitter/lodging')
        .orderBy('unitName')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => LodgingUnit.fromFirestore(doc))
          .toList();
    }).handleError((error) {
      debugPrint('Error fetching lodging stream: $error');
      return <LodgingUnit>[];
    });
  }

  Stream<List<FleetAsset>> getFleetStream() {
    return _firestore
        .collection('outfitter/fleet')
        .orderBy('vehicleName')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FleetAsset.fromFirestore(doc))
          .toList();
    }).handleError((error) {
      debugPrint('Error fetching fleet stream: $error');
      return <FleetAsset>[];
    });
  }

  Stream<List<LodgingUnit>> getVacantLodgingStream() {
    return _firestore
        .collection('outfitter/lodging')
        .where('status', isEqualTo: 'vacant')
        .orderBy('unitName')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => LodgingUnit.fromFirestore(doc))
          .toList();
    }).handleError((error) {
      debugPrint('Error fetching vacant lodging stream: $error');
      return <LodgingUnit>[];
    });
  }

  Stream<List<FleetAsset>> getActiveFleetStream() {
    return _firestore
        .collection('outfitter/fleet')
        .where('operationalStatus', isEqualTo: 'active')
        .orderBy('vehicleName')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FleetAsset.fromFirestore(doc))
          .toList();
    }).handleError((error) {
      debugPrint('Error fetching active fleet stream: $error');
      return <FleetAsset>[];
    });
  }

  Future<String> createBooking({
    required String clientName,
    required String contactNumber,
    required DateTime arrivalDate,
    required DateTime departureDate,
    required String lodgingId,
    required String vehicleId,
  }) async {
    try {
      final bookingRef = _firestore.collection('outfitter/bookings').doc();
      final booking = ClientBooking(
        id: bookingRef.id,
        clientName: clientName,
        contactNumber: contactNumber,
        arrivalDate: arrivalDate,
        departureDate: departureDate,
        lodgingId: lodgingId,
        vehicleId: vehicleId,
        status: 'pending',
      );

      final batch = _firestore.batch();
      batch.set(bookingRef, booking.toFirestore());

      final lodgingRef = _firestore.collection('outfitter/lodging').doc(lodgingId);
      batch.update(lodgingRef, {'status': 'occupied'});

      await batch.commit();
      debugPrint('Booking created successfully: ${bookingRef.id}');
      return bookingRef.id;
    } catch (e) {
      debugPrint('Error creating booking: $e');
      rethrow;
    }
  }

  Future<void> updateLodgingOccupants({
    required String lodgingId,
    required int newOccupantCount,
  }) async {
    try {
      await _firestore
          .collection('outfitter/lodging')
          .doc(lodgingId)
          .update({'currentOccupants': newOccupantCount});
      debugPrint('Lodging occupants updated: $lodgingId');
    } catch (e) {
      debugPrint('Error updating lodging occupants: $e');
      rethrow;
    }
  }

  Future<void> updateLodgingStatus({
    required String lodgingId,
    required String newStatus,
  }) async {
    try {
      await _firestore
          .collection('outfitter/lodging')
          .doc(lodgingId)
          .update({'status': newStatus});
      debugPrint('Lodging status updated: $lodgingId -> $newStatus');
    } catch (e) {
      debugPrint('Error updating lodging status: $e');
      rethrow;
    }
  }

  Future<void> toggleAssetOperationalState({
    required String vehicleId,
    required String newStatus,
  }) async {
    try {
      await _firestore
          .collection('outfitter/fleet')
          .doc(vehicleId)
          .update({'operationalStatus': newStatus});
      debugPrint('Fleet asset status updated: $vehicleId -> $newStatus');
    } catch (e) {
      debugPrint('Error toggling asset operational state: $e');
      rethrow;
    }
  }

  Future<void> updateBookingStatus({
    required String bookingId,
    required String newStatus,
  }) async {
    try {
      await _firestore
          .collection('outfitter/bookings')
          .doc(bookingId)
          .update({'status': newStatus});
      debugPrint('Booking status updated: $bookingId -> $newStatus');
    } catch (e) {
      debugPrint('Error updating booking status: $e');
      rethrow;
    }
  }

  Future<void> updateFuelLevel({
    required String vehicleId,
    required int fuelPercentage,
  }) async {
    try {
      await _firestore
          .collection('outfitter/fleet')
          .doc(vehicleId)
          .update({'fuelLevelPercentage': fuelPercentage});
      debugPrint('Fuel level updated: $vehicleId -> $fuelPercentage%');
    } catch (e) {
      debugPrint('Error updating fuel level: $e');
      rethrow;
    }
  }
}
