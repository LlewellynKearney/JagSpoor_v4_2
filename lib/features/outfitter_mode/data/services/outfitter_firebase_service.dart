import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/services/offline_stream_guard.dart';
import '../models/client_booking.dart';
import '../models/lodging_unit.dart';
import '../models/fleet_asset.dart';

class OutfitterFirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// True when there is a signed-in outfitter. Stream getters return a stable
  /// empty stream when this is false so an unauthenticated caller (e.g. a
  /// screen mounting before auth resolves, or after sign-out) never crashes
  /// its StreamBuilder with a null-scoped Firestore query.
  bool get _isAuthenticated => _auth.currentUser != null;

  Stream<List<ClientBooking>> getBookingsStream() {
    if (!_isAuthenticated) return Stream.value(const <ClientBooking>[]);
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('outfitter/bookings')
          .orderBy('arrivalDate', descending: false)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => ClientBooking.fromFirestore(doc))
                .toList();
          }),
      fallback: const <ClientBooking>[],
      debugLabel: 'outfitter.bookings',
    );
  }

  Stream<List<LodgingUnit>> getLodgingStream() {
    if (!_isAuthenticated) return Stream.value(const <LodgingUnit>[]);
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('outfitter/lodging')
          .orderBy('unitName')
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => LodgingUnit.fromFirestore(doc))
                .toList();
          }),
      fallback: const <LodgingUnit>[],
      debugLabel: 'outfitter.lodging',
    );
  }

  Stream<List<FleetAsset>> getFleetStream() {
    if (!_isAuthenticated) return Stream.value(const <FleetAsset>[]);
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('outfitter/fleet')
          .orderBy('vehicleName')
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => FleetAsset.fromFirestore(doc))
                .toList();
          }),
      fallback: const <FleetAsset>[],
      debugLabel: 'outfitter.fleet',
    );
  }

  Stream<List<LodgingUnit>> getVacantLodgingStream() {
    if (!_isAuthenticated) return Stream.value(const <LodgingUnit>[]);
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('outfitter/lodging')
          .where('status', isEqualTo: 'vacant')
          .orderBy('unitName')
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => LodgingUnit.fromFirestore(doc))
                .toList();
          }),
      fallback: const <LodgingUnit>[],
      debugLabel: 'outfitter.vacant_lodging',
    );
  }

  Stream<List<FleetAsset>> getActiveFleetStream() {
    if (!_isAuthenticated) return Stream.value(const <FleetAsset>[]);
    return OfflineStreamGuard.offlineResilient(
      _firestore
          .collection('outfitter/fleet')
          .where('operationalStatus', isEqualTo: 'active')
          .orderBy('vehicleName')
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => FleetAsset.fromFirestore(doc))
                .toList();
          }),
      fallback: const <FleetAsset>[],
      debugLabel: 'outfitter.active_fleet',
    );
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

      final lodgingRef = _firestore
          .collection('outfitter/lodging')
          .doc(lodgingId);
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
      await _firestore.collection('outfitter/lodging').doc(lodgingId).update({
        'currentOccupants': newOccupantCount,
      });
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
      await _firestore.collection('outfitter/lodging').doc(lodgingId).update({
        'status': newStatus,
      });
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
      await _firestore.collection('outfitter/fleet').doc(vehicleId).update({
        'operationalStatus': newStatus,
      });
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
      await _firestore.collection('outfitter/bookings').doc(bookingId).update({
        'status': newStatus,
      });
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
      await _firestore.collection('outfitter/fleet').doc(vehicleId).update({
        'fuelLevelPercentage': fuelPercentage,
      });
      debugPrint('Fuel level updated: $vehicleId -> $fuelPercentage%');
    } catch (e) {
      debugPrint('Error updating fuel level: $e');
      rethrow;
    }
  }
}
